use crate::domain::config::Config;
use crate::domain::models::{IpcCommand, IpcMessage, SkillGroup};
use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};
use crate::infrastructure::watchdog::{ProcessWatchdog, WatchdogStateEnum};
use indexmap::IndexMap;
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::sync::RwLock;
use std::time::Duration;
use tauri::Emitter;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("配置错误: {0}")]
    Config(String),
    #[error("IPC 通信错误: {0}")]
    Ipc(String),
    #[error("分组不存在: {0}")]
    GroupNotFound(String),
    #[error("验证失败: {0}")]
    Validation(String),
    #[error("执行器错误: {0}")]
    Executor(String),
    #[error("内部错误: {0}")]
    Internal(String),
}

impl Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

impl From<crate::infrastructure::ipc::IpcError> for AppError {
    fn from(e: crate::infrastructure::ipc::IpcError) -> Self {
        AppError::Ipc(e.to_string())
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct WatchdogState {
    pub status: WatchdogStateEnum,
    pub restart_count: u32,
    #[serde(skip)]
    pub last_restart: Option<std::time::Instant>,
    #[serde(skip)]
    pub backoff_duration: Duration,
}

impl WatchdogState {
    pub fn new() -> Self {
        Self {
            status: WatchdogStateEnum::Idle,
            restart_count: 0,
            last_restart: None,
            backoff_duration: Duration::from_secs(1),
        }
    }
}

impl Default for WatchdogState {
    fn default() -> Self {
        Self::new()
    }
}

/// 配置状态：将 config 和 groups 合并到单一 RwLock 中，
/// 消除双 RwLock 之间的一致性窗口问题。
/// 在旧设计中，save_config_atomic 先更新 config 再更新 groups，
/// 两个独立写锁之间存在一致性窗口，其他线程可能读到新的 config + 旧的 groups。
/// 合并后，单次写锁即可原子更新两者，彻底消除该窗口。
struct ConfigState {
    config: Config,
    groups: IndexMap<String, SkillGroup>,
}

pub struct AppState {
    /// 配置状态：config 和 groups 共享单一 RwLock，保证读写一致性
    config_state: RwLock<ConfigState>,
    pub ipc_manager: tokio::sync::Mutex<Option<IpcManager>>,
    pub ipc_outbound: IpcOutboundSender,
    pub active_hotkeys: RwLock<HashMap<String, String>>,
    pub emergency_mode: AtomicBool,
    pub hold_mode_enabled: AtomicBool,
    pub watchdog_state: RwLock<WatchdogState>,
    pub watchdog: Arc<tokio::sync::Mutex<ProcessWatchdog>>,
    /// Tauri AppHandle，用于向前端 emit 事件
    /// 初始为 None，在 setup() 中通过 set_app_handle() 设置
    pub app_handle: RwLock<Option<tauri::AppHandle>>,
    /// C-5: 配置文件路径，用于原子保存时写入文件
    /// 初始为 None，在 setup() 中通过 set_config_path() 设置
    config_path: RwLock<Option<PathBuf>>,
}

impl AppState {
    pub fn new(
        config: Config,
        ipc_outbound: IpcOutboundSender,
        watchdog: Arc<tokio::sync::Mutex<ProcessWatchdog>>,
    ) -> Self {
        let groups = Self::build_groups_from_config(&config);
        Self {
            config_state: RwLock::new(ConfigState { config, groups }),
            ipc_manager: tokio::sync::Mutex::new(None),
            ipc_outbound,
            active_hotkeys: RwLock::new(HashMap::new()),
            emergency_mode: AtomicBool::new(false),
            hold_mode_enabled: AtomicBool::new(false),
            watchdog_state: RwLock::new(WatchdogState::new()),
            watchdog,
            app_handle: RwLock::new(None),
            config_path: RwLock::new(None),
        }
    }

    pub fn build_groups_from_config(config: &Config) -> IndexMap<String, SkillGroup> {
        let mut groups = IndexMap::new();
        for (id, group_config) in &config.group_settings {
            groups.insert(id.clone(), SkillGroup::from((id, group_config)));
        }
        groups
    }

    /// 读取当前配置的快照（克隆）
    pub fn read_config(&self) -> Result<Config, AppError> {
        let guard = self
            .config_state
            .read()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        Ok(guard.config.clone())
    }

    /// 读取当前分组的快照（克隆）
    pub fn read_groups(&self) -> Result<IndexMap<String, SkillGroup>, AppError> {
        let guard = self
            .config_state
            .read()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        Ok(guard.groups.clone())
    }

    pub fn is_emergency_mode(&self) -> bool {
        self.emergency_mode
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn set_emergency_mode(&self, enabled: bool) {
        self.emergency_mode
            .store(enabled, std::sync::atomic::Ordering::Relaxed);
    }

    pub fn is_hold_mode_enabled(&self) -> bool {
        self.hold_mode_enabled
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn set_hold_mode_enabled(&self, enabled: bool) {
        self.hold_mode_enabled
            .store(enabled, std::sync::atomic::Ordering::Relaxed);
    }

    pub fn get_group(&self, id: &str) -> Option<SkillGroup> {
        self.config_state
            .read()
            .ok()
            .and_then(|g| g.groups.get(id).cloned())
    }

    pub fn set_group_active(&self, id: &str, active: bool) -> Result<(), AppError> {
        // 收集 emit 所需的 groups 数据和 hotkey 更新信息
        // 必须在写锁释放后才能调用 emit_event，否则在 emit_event 中再次获取 config_state 读锁会导致死锁
        // 必须在写锁释放后再更新 active_hotkeys，避免嵌套锁死锁风险
        let (all_groups_data, hotkey_update): (Vec<serde_json::Value>, Option<(bool, String)>) = {
            let mut cs = self
                .config_state
                .write()
                .map_err(|e| AppError::Internal(e.to_string()))?;
            if let Some(group) = cs.groups.get_mut(id) {
                group.active = active;
                let hotkey = group.hotkey.clone();
                // 在写锁仍持有时收集所有 groups 的克隆数据
                let groups_data: Vec<serde_json::Value> = cs
                    .groups
                    .values()
                    .cloned()
                    .map(|g| serde_json::to_value(g).unwrap_or_default())
                    .collect();
                (groups_data, Some((active, hotkey)))
            } else {
                return Err(AppError::GroupNotFound(id.to_string()));
            }
        }; // config_state 写锁在此释放

        // 安全更新 active_hotkeys（无嵌套锁）
        if let Some((is_active, hotkey)) = hotkey_update {
            if is_active {
                self.active_hotkeys
                    .write()
                    .map_err(|e| AppError::Internal(e.to_string()))?
                    .insert(id.to_string(), hotkey);
            } else {
                self.active_hotkeys
                    .write()
                    .map_err(|e| AppError::Internal(e.to_string()))?
                    .remove(id);
            }
        }

        // 写锁已释放，安全调用 emit_event
        self.emit_event(
            "status_update",
            serde_json::json!({
                "groupId": id,
                "active": active,
                "groups": all_groups_data,
            }),
        );
        Ok(())
    }

    pub fn active_group_ids(&self) -> Vec<String> {
        self.active_hotkeys
            .read()
            .map(|h| h.keys().cloned().collect())
            .unwrap_or_default()
    }

    pub async fn send_ipc_command(&self, cmd: &IpcCommand) -> Result<u64, AppError> {
        let mut guard = self.ipc_manager.lock().await;
        let manager = guard
            .as_mut()
            .ok_or_else(|| AppError::Ipc("IPC 管理器未初始化".to_string()))?;
        let seq = manager
            .send_command(cmd.clone())
            .await
            .map_err(|e| AppError::Ipc(e.to_string()))?;
        Ok(seq)
    }

    pub async fn try_send_ipc_command(&self, cmd: &IpcCommand) {
        let mut guard = self.ipc_manager.lock().await;
        if let Some(ref mut manager) = *guard {
            if let Err(e) = manager.send_command(cmd.clone()).await {
                tracing::warn!("IPC 发送失败: {e}");
            }
        }
    }

    /// 发送 IPC 命令并等待 AHK 端响应（带超时）
    /// 用于需要获取 AHK 端返回数据的场景（如 stop_recording）
    pub async fn send_ipc_and_wait(
        &self,
        cmd: &IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, AppError> {
        let mut guard = self.ipc_manager.lock().await;
        let manager = guard
            .as_mut()
            .ok_or_else(|| AppError::Ipc("IPC 管理器未初始化".to_string()))?;
        manager
            .send_and_wait(cmd.clone(), timeout)
            .await
            .map_err(|e| AppError::Ipc(e.to_string()))
    }

    /// 直接发送 IpcMessage（用于心跳 ping、shutdown 等非 command 类型消息）
    pub async fn try_send_ipc_message(&self, msg: &IpcMessage) {
        let mut guard = self.ipc_manager.lock().await;
        if let Some(ref mut manager) = *guard {
            if let Err(e) = manager.send(msg).await {
                tracing::warn!("IPC 消息发送失败: {e}");
            }
        }
    }

    pub fn update_watchdog_state(&self, status: WatchdogStateEnum, restart_count: u32) {
        if let Ok(mut ws) = self.watchdog_state.write() {
            ws.status = status.clone();
            ws.restart_count = restart_count;
        }
        self.emit_event(
            "executor_status",
            serde_json::json!({
                "status": status,
                "restartCount": restart_count,
            }),
        );
    }

    /// 设置 Tauri AppHandle，用于向前端 emit 事件
    /// 应在 setup() 中调用一次
    pub fn set_app_handle(&self, handle: tauri::AppHandle) {
        if let Ok(mut guard) = self.app_handle.write() {
            *guard = Some(handle);
            tracing::info!("AppState: AppHandle 已设置");
        }
    }

    /// 向前端 emit 事件
    /// 返回 true 表示成功发送，返回 false 表示 app_handle 未设置或发送失败
    pub fn emit_event(&self, event: &str, payload: serde_json::Value) -> bool {
        if let Ok(guard) = self.app_handle.read() {
            if let Some(ref handle) = *guard {
                match handle.emit(event, payload) {
                    Ok(()) => true,
                    Err(e) => {
                        tracing::warn!("emit 事件 '{event}' 失败: {e}");
                        false
                    }
                }
            } else {
                // app_handle 未设置，静默返回 false
                false
            }
        } else {
            false
        }
    }

    // ---- C-5: config_path 管理 ----

    /// 获取配置文件路径
    pub fn get_config_path(&self) -> Option<PathBuf> {
        self.config_path.read().ok().and_then(|g| g.clone())
    }

    /// 设置配置文件路径（应在 setup() 中调用）
    pub fn set_config_path(&self, path: PathBuf) {
        if let Ok(mut guard) = self.config_path.write() {
            *guard = Some(path);
        }
    }

    // ---- C-9: 原子保存 ----

    /// 原子保存配置：先更新内存，再写文件，写入失败时回滚内存
    ///
    /// 流程：
    /// 1. 备份当前内存中的配置（单次读锁，保证快照一致性）
    /// 2. 原子更新内存 config + groups（单次写锁，消除双锁一致性窗口）
    /// 3. 如果 config_path 已设置，通过 save_to_path 写入文件（原子写：临时文件+重命名）
    /// 4. 如果文件写入失败，回滚内存到备份值（单次写锁，保证回滚一致性）
    /// 5. 如果 config_path 未设置，仅更新内存（不写文件）
    pub fn save_config_atomic(&self, new_config: Config) -> Result<(), AppError> {
        // 步骤1: 备份当前内存中的配置和 groups（单次读锁，保证快照一致性）
        let old_state = {
            let guard = self
                .config_state
                .read()
                .map_err(|e| AppError::Internal(e.to_string()))?;
            ConfigState {
                config: guard.config.clone(),
                groups: guard.groups.clone(),
            }
        };

        let mut new_groups = Self::build_groups_from_config(&new_config);

        // 同步旧 groups 的 active 状态到新 groups
        // build_groups_from_config 中 SkillGroup::from 硬编码 active: false，
        // 保存配置后若不同步，所有分组会变为非活跃状态
        for (id, new_group) in new_groups.iter_mut() {
            if let Some(old_group) = old_state.groups.get(id) {
                new_group.active = old_group.active;
            }
        }

        // 步骤2: 原子更新内存（单次写锁，消除双锁一致性窗口）
        {
            let mut guard = self
                .config_state
                .write()
                .map_err(|e| AppError::Internal(e.to_string()))?;
            guard.config = new_config.clone();
            guard.groups = new_groups;
        }

        // 步骤3: 如果 config_path 已设置，写入文件
        if let Some(path) = self.get_config_path() {
            if let Err(save_err) = new_config.save_to_path(&path) {
                // 步骤4: 文件写入失败，回滚内存（单次写锁，保证回滚一致性）
                tracing::error!("原子保存失败，回滚内存: {save_err}");
                {
                    let mut guard = self
                        .config_state
                        .write()
                        .map_err(|e| AppError::Internal(e.to_string()))?;
                    guard.config = old_state.config;
                    guard.groups = old_state.groups;
                }
                return Err(AppError::Config(save_err));
            }
        }
        // 步骤5: config_path 为 None 时仅更新内存，视为成功

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::config::*;

    fn make_test_config() -> Config {
        let mut group_settings = IndexMap::new();
        group_settings.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: Some(10),
                name: Some("测试组".to_string()),
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["1".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        Config {
            control_hotkeys: ControlHotkeys {
                emergency: "F10".to_string(),
                release_all_holds: "^r".to_string(),
                show_status: "^0".to_string(),
                toggle_all: "^1".to_string(),
                toggle_hold_mode: "^h".to_string(),
            },
            group_settings,
            hold_settings: None,
            last_modified: None,
            version: Some("3.0".to_string()),
        }
    }

    fn make_test_state() -> Arc<AppState> {
        let config = make_test_config();
        let (tx, _rx) = tokio::sync::mpsc::channel(256);
        let watchdog = Arc::new(tokio::sync::Mutex::new(ProcessWatchdog::new()));
        Arc::new(AppState::new(config, tx, watchdog))
    }

    #[test]
    fn test_app_state_creation() {
        let state = make_test_state();
        assert!(!state.is_emergency_mode());
        assert!(!state.is_hold_mode_enabled());
    }

    #[test]
    fn test_emergency_mode() {
        let state = make_test_state();
        assert!(!state.is_emergency_mode());
        state.set_emergency_mode(true);
        assert!(state.is_emergency_mode());
        state.set_emergency_mode(false);
        assert!(!state.is_emergency_mode());
    }

    #[test]
    fn test_hold_mode() {
        let state = make_test_state();
        assert!(!state.is_hold_mode_enabled());
        state.set_hold_mode_enabled(true);
        assert!(state.is_hold_mode_enabled());
    }

    #[test]
    fn test_groups_from_config() {
        let state = make_test_state();
        let group = state.get_group("1").unwrap();
        assert_eq!(group.id, "1");
        assert_eq!(group.name, "测试组");
        assert_eq!(group.hotkey, "F1");
        assert_eq!(group.mode, "periodic");
        assert!(!group.active);
    }

    #[test]
    fn test_set_group_active() {
        let state = make_test_state();

        state.set_group_active("1", true).unwrap();
        let group = state.get_group("1").unwrap();
        assert!(group.active);
        assert!(state.active_group_ids().contains(&"1".to_string()));

        state.set_group_active("1", false).unwrap();
        let group = state.get_group("1").unwrap();
        assert!(!group.active);
        assert!(!state.active_group_ids().contains(&"1".to_string()));
    }

    #[test]
    fn test_group_not_found() {
        let state = make_test_state();
        let result = state.set_group_active("999", true);
        assert!(matches!(result, Err(AppError::GroupNotFound(_))));
    }

    #[test]
    fn test_app_error_serialization() {
        let err = AppError::Config("测试错误".to_string());
        let json = serde_json::to_string(&err).unwrap();
        assert!(json.contains("配置错误"));
    }

    #[test]
    fn test_app_error_from_ipc_error() {
        let ipc_err = crate::infrastructure::ipc::IpcError::ConnectionClosed;
        let app_err: AppError = ipc_err.into();
        assert!(matches!(app_err, AppError::Ipc(_)));
    }

    #[test]
    fn test_watchdog_state_new() {
        let ws = WatchdogState::new();
        assert_eq!(ws.status, WatchdogStateEnum::Idle);
        assert_eq!(ws.restart_count, 0);
        assert!(ws.last_restart.is_none());
    }

    #[test]
    fn test_update_watchdog_state() {
        let state = make_test_state();

        state.update_watchdog_state(WatchdogStateEnum::Running, 1);
        let ws = state.watchdog_state.read().unwrap();
        assert_eq!(ws.status, WatchdogStateEnum::Running);
        assert_eq!(ws.restart_count, 1);
    }

    #[test]
    fn test_skill_group_serialization() {
        let group = SkillGroup {
            id: "1".to_string(),
            name: "测试".to_string(),
            hotkey: "F1".to_string(),
            active: true,
            mode: "periodic".to_string(),
            key_press_duration: 10,
            hold_keys: None,
            hold_mode: None,
            mode_data: crate::domain::config::ModeData::Periodic(
                crate::domain::config::PeriodicData {
                    keys: vec!["1".to_string()],
                    intervals: vec![50],
                },
            ),
        };
        let json = serde_json::to_string(&group).unwrap();
        let decoded: SkillGroup = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.id, "1");
        assert_eq!(decoded.name, "测试");
        assert!(decoded.active);
    }

    // ---- C-2/C-3: emit_event 方法待实现，暂时跳过相关测试 ----

    // ---- C-5/C-9: config_path 和 save_config_atomic 测试 ----

    /// C-5: 新创建的 AppState 的 config_path 应为 None
    #[test]
    fn test_config_path_default_is_none() {
        let state = make_test_state();
        assert!(
            state.get_config_path().is_none(),
            "新建 AppState 的 config_path 应为 None"
        );
    }

    /// C-5: 可以设置和获取 config_path
    #[test]
    fn test_set_get_config_path() {
        let state = make_test_state();
        let path = std::path::PathBuf::from("/tmp/asd/config.json");
        state.set_config_path(path.clone());
        let retrieved = state.get_config_path().unwrap();
        assert_eq!(retrieved, path, "get_config_path 应返回设置的路径");
    }

    /// C-9: save_config_atomic 应先更新内存再写文件，成功时两者一致
    #[test]
    fn test_save_config_atomic_updates_memory_and_file() {
        let dir = std::env::temp_dir().join("asd_test_save_atomic_success");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let state = make_test_state();
        state.set_config_path(path.clone());

        // 构造新配置
        let mut new_config = make_test_config();
        new_config.control_hotkeys.emergency = "F12".to_string();

        // 执行原子保存
        let result = state.save_config_atomic(new_config.clone());
        assert!(result.is_ok(), "save_config_atomic 应成功: {:?}", result);

        // 验证内存已更新
        let mem_config = state.read_config().unwrap();
        assert_eq!(
            mem_config.control_hotkeys.emergency, "F12",
            "内存中的配置应已更新"
        );

        // 验证文件已写入
        let file_content = std::fs::read_to_string(&path).unwrap();
        let file_config: Config = serde_json::from_str(&file_content).unwrap();
        assert_eq!(
            file_config.control_hotkeys.emergency, "F12",
            "文件中的配置应已更新"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// C-9: save_config_atomic 写文件失败时应回滚内存
    #[test]
    fn test_save_config_atomic_rollback_on_write_failure() {
        let state = make_test_state();
        // 设置一个不存在的目录路径，写入必定失败
        let bad_path = std::path::PathBuf::from("/nonexistent/directory/config.json");
        state.set_config_path(bad_path);

        // 记录原始内存中的值
        let original_emergency = state
            .read_config()
            .unwrap()
            .control_hotkeys
            .emergency
            .clone();

        // 构造新配置
        let mut new_config = make_test_config();
        new_config.control_hotkeys.emergency = "F12".to_string();

        // 执行原子保存（应失败）
        let result = state.save_config_atomic(new_config);
        assert!(result.is_err(), "写入不存在的路径应返回 Err");

        // 验证内存已回滚到原始值
        let mem_config = state.read_config().unwrap();
        assert_eq!(
            mem_config.control_hotkeys.emergency, original_emergency,
            "写入失败时内存应回滚到原始值"
        );
    }

    /// C-5: config_path 为 None 时，save_config_atomic 只更新内存不写文件
    #[test]
    fn test_save_config_atomic_no_path_updates_memory_only() {
        let state = make_test_state();
        // 不设置 config_path（默认为 None）

        let mut new_config = make_test_config();
        new_config.control_hotkeys.emergency = "F12".to_string();

        let result = state.save_config_atomic(new_config);
        assert!(result.is_ok(), "config_path 为 None 时应成功（仅更新内存）");

        let mem_config = state.read_config().unwrap();
        assert_eq!(mem_config.control_hotkeys.emergency, "F12", "内存应已更新");
    }

    /// C-9: save_config_atomic 成功后 groups 也应同步更新
    #[test]
    fn test_save_config_atomic_updates_groups() {
        let dir = std::env::temp_dir().join("asd_test_save_atomic_groups");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let state = make_test_state();
        state.set_config_path(path.clone());

        // 构造包含新分组的新配置
        let mut new_config = make_test_config();
        new_config.group_settings.insert(
            "2".to_string(),
            GroupConfig {
                hotkey: "F2".to_string(),
                key_press_duration: None,
                name: Some("新增组".to_string()),
                mode: "sequence".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Sequence(SequenceData {
                    keys: vec!["A".to_string()],
                    delays: vec![100],
                }),
            },
        );

        let result = state.save_config_atomic(new_config);
        assert!(result.is_ok(), "save_config_atomic 应成功");

        // 验证 groups 已更新
        let groups = state.read_groups().unwrap();
        assert!(groups.contains_key("2"), "新增分组应存在于 groups 中");
        assert_eq!(groups["2"].name, "新增组");

        let _ = std::fs::remove_dir_all(&dir);
    }
}
