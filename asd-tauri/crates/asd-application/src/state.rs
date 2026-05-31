use crate::config_repository::ConfigRepository;
use crate::error::AppError;
use asd_domain::config::{Config, WatchdogStateEnum};
use asd_domain::models::SkillGroup;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use parking_lot::RwLock;
use std::time::Duration;

/// 子进程监控状态，用于序列化到前端展示。
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

struct ConfigState {
    config: Config,
    groups: IndexMap<String, SkillGroup>,
}

/// 应用全局状态，管理配置、分组、热键注册和 IPC 通信。
///
/// `AppState` 是应用层的核心结构体，通过 `RwLock` 和 `AtomicBool` 提供线程安全的并发访问。
/// 所有 Tauri 命令通过 `Arc<AppState>` 共享此状态。
pub struct AppState {
    config_state: RwLock<ConfigState>,
    ipc_sender: Arc<dyn IpcSender>,
    pub(crate) active_hotkeys: RwLock<HashMap<String, String>>,
    pub emergency_mode: AtomicBool,
    pub hold_mode_enabled: AtomicBool,
    pub watchdog_state: RwLock<WatchdogState>,
    #[allow(dead_code)]
    watchdog: Arc<dyn ProcessWatcher>,
    event_emitter: Arc<dyn EventEmitter>,
    config_path: RwLock<Option<PathBuf>>,
}

impl AppState {
    pub fn new(
        config: Config,
        ipc_sender: Arc<dyn IpcSender>,
        watchdog: Arc<dyn ProcessWatcher>,
        event_emitter: Arc<dyn EventEmitter>,
    ) -> Self {
        let groups = Self::build_groups_from_config(&config);
        Self {
            config_state: RwLock::new(ConfigState { config, groups }),
            ipc_sender,
            active_hotkeys: RwLock::new(HashMap::new()),
            emergency_mode: AtomicBool::new(false),
            hold_mode_enabled: AtomicBool::new(false),
            watchdog_state: RwLock::new(WatchdogState::new()),
            watchdog,
            event_emitter,
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

    pub fn read_config(&self) -> Result<Config, AppError> {
        let guard = self.config_state.read();
        Ok(guard.config.clone())
    }

    pub fn read_groups(&self) -> Result<IndexMap<String, SkillGroup>, AppError> {
        let guard = self.config_state.read();
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
        self.config_state.read().groups.get(id).cloned()
    }

    pub fn set_group_active(&self, id: &str, active: bool) -> Result<(), AppError> {
        let hotkey_update: Option<(bool, String)> = {
            let mut cs = self.config_state.write();
            if let Some(group) = cs.groups.get_mut(id) {
                group.active = active;
                let hotkey = group.hotkey.clone();
                Some((active, hotkey))
            } else {
                return Err(AppError::GroupNotFound(id.to_string()));
            }
        };

        if let Some((is_active, hotkey)) = hotkey_update {
            if is_active {
                self.active_hotkeys.write().insert(hotkey, id.to_string());
            } else {
                self.active_hotkeys.write().remove(&hotkey);
            }
        }

        self.emit_event(
            "status_update",
            serde_json::json!({
                "groupId": id,
                "active": active,
            }),
        );
        Ok(())
    }

    pub fn active_group_ids(&self) -> Vec<String> {
        self.active_hotkeys
            .read()
            .values()
            .cloned()
            .collect()
    }

    pub fn send_ipc_command(&self, cmd: &IpcCommand) -> Result<u64, AppError> {
        self.ipc_sender
            .send_command(cmd.clone())
            .map_err(AppError::Ipc)
    }

    pub fn try_send_ipc_command(&self, cmd: &IpcCommand) {
        if let Err(e) = self.ipc_sender.send_command(cmd.clone()) {
            tracing::warn!("IPC 发送失败: {e}");
        }
    }

    pub fn send_ipc_and_wait(
        &self,
        cmd: &IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, AppError> {
        self.ipc_sender
            .send_and_wait(cmd.clone(), timeout)
            .map_err(AppError::Ipc)
    }

    pub fn try_send_ipc_message(&self, msg: &IpcMessage) {
        if let Err(e) = self.ipc_sender.send_message(msg) {
            tracing::warn!("IPC 消息发送失败: {e}");
        }
    }

    pub fn update_watchdog_state(&self, status: WatchdogStateEnum, restart_count: u32) {
        let mut ws = self.watchdog_state.write();
        ws.status = status.clone();
        ws.restart_count = restart_count;
        self.emit_event(
            "executor_status",
            serde_json::json!({
                "status": status,
                "restartCount": restart_count,
            }),
        );
    }

    pub fn emit_event(&self, event: &str, payload: serde_json::Value) -> bool {
        self.event_emitter.emit(event, payload)
    }

    pub fn get_config_path(&self) -> Option<PathBuf> {
        self.config_path.read().clone()
    }

    pub fn set_config_path(&self, path: PathBuf) {
        *self.config_path.write() = Some(path);
    }

    pub fn save_config_atomic(&self, new_config: Config) -> Result<(), AppError> {
        let old_state = {
            let mut guard = self.config_state.write();

            let old_config = guard.config.clone();
            let old_groups = guard.groups.clone();

            let mut new_groups = Self::build_groups_from_config(&new_config);
            for (id, new_group) in new_groups.iter_mut() {
                if let Some(old_group) = old_groups.get(id) {
                    new_group.active = old_group.active;
                }
            }

            guard.config = new_config.clone();
            guard.groups = new_groups;

            ConfigState {
                config: old_config,
                groups: old_groups,
            }
        };

        if let Some(path) = self.get_config_path() {
            if let Err(save_err) = ConfigRepository::save_to_path(&new_config, &path) {
                tracing::error!("原子保存失败，回滚内存: {save_err}");
                {
                    let mut guard = self.config_state.write();
                    guard.config = old_state.config;
                    guard.groups = old_state.groups;
                }
                return Err(AppError::Config(save_err));
            }
        }

        Ok(())
    }

    pub fn register_hotkey(
        &self,
        hotkey: &str,
        group_id: &str,
    ) -> Result<Option<String>, AppError> {
        let mut registry = self.active_hotkeys.write();
        let existing = registry.insert(hotkey.to_string(), group_id.to_string());
        Ok(existing)
    }

    pub fn unregister_hotkey(&self, hotkey: &str) -> Result<bool, AppError> {
        let mut registry = self.active_hotkeys.write();
        Ok(registry.remove(hotkey).is_some())
    }

    pub fn is_hotkey_registered(&self, hotkey: &str) -> Result<bool, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry.contains_key(hotkey))
    }

    pub fn get_hotkey_group(&self, hotkey: &str) -> Result<Option<String>, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry.get(hotkey).cloned())
    }

    pub fn remove_group_hotkeys(&self, group_id: &str) -> Result<(), AppError> {
        let mut registry = self.active_hotkeys.write();
        registry.retain(|_, gid| gid != group_id);
        Ok(())
    }

    pub fn get_all_registered_hotkeys(&self) -> Result<Vec<(String, String)>, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry
            .iter()
            .map(|(hotkey, group_id)| (hotkey.clone(), group_id.clone()))
            .collect())
    }

    pub fn delete_group_atomic(&self, group_id: &str) -> Result<bool, AppError> {
        let (is_active, ipc_cmd) = {
            let mut cs = self.config_state.write();

            let is_active = cs.groups.get(group_id).map(|g| g.active).unwrap_or(false);

            let ipc_cmd = if is_active {
                Some(IpcCommand::ToggleGroup {
                    group_id: group_id.to_string(),
                    active: false,
                    mode: None,
                    key_press_duration: None,
                    hold_keys: None,
                    hold_mode: None,
                    mode_data: None,
                })
            } else {
                None
            };

            cs.config.group_settings.shift_remove(group_id);
            cs.groups.shift_remove(group_id);

            if is_active {
                self.active_hotkeys.write().retain(|_, gid| gid != group_id);
            }

            (is_active, ipc_cmd)
        };

        if let Some(cmd) = ipc_cmd {
            self.try_send_ipc_command(&cmd);
        }

        if let Some(path) = self.get_config_path() {
            let config = {
                let guard = self.config_state.read();
                guard.config.clone()
            };
            if let Err(e) = ConfigRepository::save_to_path(&config, &path) {
                tracing::error!("删除分组后保存配置失败: {e}");
                return Err(AppError::Config(format!(
                    "删除分组成功但保存配置失败: {e}"
                )));
            }
        }

        tracing::info!("已删除分组: {}", group_id);
        Ok(is_active)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;

    struct MockIpcSender;
    impl IpcSender for MockIpcSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Ok(1)
        }
        fn send_and_wait(
            &self,
            _cmd: IpcCommand,
            _timeout: std::time::Duration,
        ) -> Result<IpcMessage, String> {
            Ok(IpcMessage::response(1, 0, "ok", None))
        }
        fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
            Ok(())
        }
    }

    struct MockEventEmitter {
        emitted: std::sync::Mutex<Vec<(String, serde_json::Value)>>,
    }
    impl MockEventEmitter {
        fn new() -> Self {
            Self {
                emitted: std::sync::Mutex::new(Vec::new()),
            }
        }
    }
    impl EventEmitter for MockEventEmitter {
        fn emit(&self, event: &str, payload: serde_json::Value) -> bool {
            self.emitted
                .lock()
                .unwrap()
                .push((event.to_string(), payload));
            true
        }
    }

    struct MockProcessWatcher;
    impl ProcessWatcher for MockProcessWatcher {
        fn state(&self) -> WatchdogStateEnum {
            WatchdogStateEnum::Idle
        }
        fn restart_count(&self) -> u32 {
            0
        }
    }

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
        let ipc_sender = Arc::new(MockIpcSender);
        let watchdog = Arc::new(MockProcessWatcher);
        let event_emitter = Arc::new(MockEventEmitter::new());
        Arc::new(AppState::new(config, ipc_sender, watchdog, event_emitter))
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
        let ws = state.watchdog_state.read();
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
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        };
        let json = serde_json::to_string(&group).unwrap();
        let decoded: SkillGroup = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.id, "1");
        assert_eq!(decoded.name, "测试");
        assert!(decoded.active);
    }

    #[test]
    fn test_config_path_default_is_none() {
        let state = make_test_state();
        assert!(
            state.get_config_path().is_none(),
            "新建 AppState 的 config_path 应为 None"
        );
    }

    #[test]
    fn test_set_get_config_path() {
        let state = make_test_state();
        let path = std::path::PathBuf::from("/tmp/asd/config.json");
        state.set_config_path(path.clone());
        let retrieved = state.get_config_path().unwrap();
        assert_eq!(retrieved, path, "get_config_path 应返回设置的路径");
    }

    #[test]
    fn test_save_config_atomic_updates_memory_and_file() {
        let dir = std::env::temp_dir().join("asd_app_test_save_atomic_success");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let state = make_test_state();
        state.set_config_path(path.clone());

        let mut new_config = make_test_config();
        new_config.control_hotkeys.emergency = "F12".to_string();

        let result = state.save_config_atomic(new_config.clone());
        assert!(result.is_ok(), "save_config_atomic 应成功: {:?}", result);

        let mem_config = state.read_config().unwrap();
        assert_eq!(
            mem_config.control_hotkeys.emergency, "F12",
            "内存中的配置应已更新"
        );

        let file_content = std::fs::read_to_string(&path).unwrap();
        let file_config: Config = serde_json::from_str(&file_content).unwrap();
        assert_eq!(
            file_config.control_hotkeys.emergency, "F12",
            "文件中的配置应已更新"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_save_config_atomic_rollback_on_write_failure() {
        let state = make_test_state();
        let bad_path = std::path::PathBuf::from("/nonexistent/directory/config.json");
        state.set_config_path(bad_path);

        let original_emergency = state
            .read_config()
            .unwrap()
            .control_hotkeys
            .emergency
            .clone();

        let mut new_config = make_test_config();
        new_config.control_hotkeys.emergency = "F12".to_string();

        let result = state.save_config_atomic(new_config);
        assert!(result.is_err(), "写入不存在的路径应返回 Err");

        let mem_config = state.read_config().unwrap();
        assert_eq!(
            mem_config.control_hotkeys.emergency, original_emergency,
            "写入失败时内存应回滚到原始值"
        );
    }

    #[test]
    fn test_save_config_atomic_no_path_updates_memory_only() {
        let state = make_test_state();

        let mut new_config = make_test_config();
        new_config.control_hotkeys.emergency = "F12".to_string();

        let result = state.save_config_atomic(new_config);
        assert!(result.is_ok(), "config_path 为 None 时应成功（仅更新内存）");

        let mem_config = state.read_config().unwrap();
        assert_eq!(mem_config.control_hotkeys.emergency, "F12", "内存应已更新");
    }

    #[test]
    fn test_save_config_atomic_updates_groups() {
        let dir = std::env::temp_dir().join("asd_app_test_save_atomic_groups");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let state = make_test_state();
        state.set_config_path(path.clone());

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

        let groups = state.read_groups().unwrap();
        assert!(groups.contains_key("2"), "新增分组应存在于 groups 中");
        assert_eq!(groups["2"].name, "新增组");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_send_ipc_command() {
        let state = make_test_state();
        let cmd = IpcCommand::EmergencyRelease;
        let result = state.send_ipc_command(&cmd);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 1);
    }

    #[test]
    fn test_try_send_ipc_command() {
        let state = make_test_state();
        let cmd = IpcCommand::EmergencyRelease;
        state.try_send_ipc_command(&cmd);
    }

    #[test]
    fn test_send_ipc_and_wait() {
        let state = make_test_state();
        let cmd = IpcCommand::StopRecording;
        let result = state.send_ipc_and_wait(&cmd, Duration::from_secs(5));
        assert!(result.is_ok());
    }

    #[test]
    fn test_try_send_ipc_message() {
        let state = make_test_state();
        let msg = IpcMessage::ping(1);
        state.try_send_ipc_message(&msg);
    }

    #[test]
    fn test_emit_event() {
        let emitter = Arc::new(MockEventEmitter::new());
        let config = make_test_config();
        let ipc_sender = Arc::new(MockIpcSender);
        let watchdog = Arc::new(MockProcessWatcher);
        let state = AppState::new(config, ipc_sender, watchdog, emitter.clone());

        let result = state.emit_event("test_event", serde_json::json!({"key": "value"}));
        assert!(result);

        let emitted = emitter.emitted.lock().unwrap();
        assert_eq!(emitted.len(), 1);
        assert_eq!(emitted[0].0, "test_event");
    }

    #[test]
    fn test_active_group_ids() {
        let state = make_test_state();
        assert!(state.active_group_ids().is_empty());

        state.set_group_active("1", true).unwrap();
        assert_eq!(state.active_group_ids(), vec!["1"]);
    }
}
