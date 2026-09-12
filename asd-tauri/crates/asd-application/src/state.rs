use crate::config_repository::ConfigRepository;
use crate::error::AppError;
use asd_domain::config::{Config, WatchdogStateEnum};
use asd_domain::models::SkillGroup;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use parking_lot::RwLock;
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

/// 子进程监控状态，用于序列化到前端展示。
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct WatchdogState {
    pub status: WatchdogStateEnum,
    #[serde(rename = "restartCount")]
    pub restart_count: u32,
    #[serde(skip)]
    pub last_restart: Option<std::time::Instant>,
    #[serde(
        rename = "backoffDurationSecs",
        serialize_with = "serialize_duration_secs"
    )]
    pub backoff_duration: Duration,
}

fn serialize_duration_secs<S: serde::Serializer>(
    duration: &Duration,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_f64(duration.as_secs_f64())
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
    version: u64,
}

/// 应用全局状态，管理配置、分组、热键注册和 IPC 通信。
///
/// `AppState` 是应用层的核心结构体，通过 `parking_lot::RwLock` 和 `AtomicBool` 提供线程安全的并发访问。
/// 所有 Tauri 命令通过 `Arc<AppState>` 共享此状态。
///
/// # 磁盘 I/O 策略
///
/// `save_config_atomic` 和 `delete_group_atomic` 先在写锁内更新内存状态，
/// 释放写锁后再执行磁盘写入。如果磁盘写入失败，重新获取写锁回滚内存状态。
/// 这意味着在磁盘写入期间，读操作可以看到尚未持久化的内存状态，
/// 但避免了磁盘 I/O 阻塞所有读操作的风险。
///
/// # TOCTOU 权衡
///
/// `save_config_atomic` 和 `delete_group_atomic` 在 `config_state` 写锁内更新
/// 配置和分组，释放锁后再获取 `active_hotkeys` 写锁更新热键注册。在两个锁释放
/// 之间的极短时间窗口内，其他线程可能读取到不一致的状态（配置已更新但
/// `active_hotkeys` 尚未同步）。这与 `set_group_active` 的 TOCTOU 权衡一致，
/// 是可接受的，因为时间窗口极短且合并两个 RwLock 会增加锁争用。
pub struct AppState {
    config_state: RwLock<ConfigState>,
    ipc_sender: Arc<dyn IpcSender>,
    pub(crate) active_hotkeys: RwLock<HashMap<String, String>>,
    pub emergency_mode: AtomicBool,
    pub hold_mode_enabled: AtomicBool,
    pub recording_mode: RwLock<Option<String>>,
    pub validation_in_progress: AtomicBool,
    pub watchdog_state: RwLock<WatchdogState>,
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
            config_state: RwLock::new(ConfigState {
                config,
                groups,
                version: 0,
            }),
            ipc_sender,
            active_hotkeys: RwLock::new(HashMap::new()),
            emergency_mode: AtomicBool::new(false),
            hold_mode_enabled: AtomicBool::new(false),
            recording_mode: RwLock::new(None),
            validation_in_progress: AtomicBool::new(false),
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
            .load(std::sync::atomic::Ordering::SeqCst)
    }

    /// 设置紧急释放模式。
    ///
    /// 注意：此方法使用 `store` 直接写入，绕过了命令层的 `compare_exchange` 保护。
    /// 仅用于测试代码。生产代码应使用 `system_cmd::emergency_release`/`clear_emergency`。
    #[cfg(test)]
    pub(crate) fn set_emergency_mode(&self, enabled: bool) {
        self.emergency_mode
            .store(enabled, std::sync::atomic::Ordering::SeqCst);
    }

    pub fn is_hold_mode_enabled(&self) -> bool {
        self.hold_mode_enabled
            .load(std::sync::atomic::Ordering::SeqCst)
    }

    /// 设置长按模式。
    ///
    /// 注意：此方法使用 `store` 直接写入，绕过了命令层的 `compare_exchange` 保护。
    /// 仅用于测试代码。生产代码应使用 `system_cmd::toggle_hold_mode`。
    #[cfg(test)]
    pub(crate) fn set_hold_mode_enabled(&self, enabled: bool) {
        self.hold_mode_enabled
            .store(enabled, std::sync::atomic::Ordering::SeqCst);
    }

    pub fn get_group(&self, id: &str) -> Option<SkillGroup> {
        self.config_state.read().groups.get(id).cloned()
    }

    /// 设置分组的激活状态。
    ///
    /// # TOCTOU 权衡
    ///
    /// 此方法先在 `config_state` 写锁内更新分组的 `active` 字段，释放锁后
    /// 再获取 `active_hotkeys` 写锁更新热键注册。在两个锁释放之间的极短时间窗口内，
    /// 其他线程可能读取到不一致的状态（`group.active == true` 但 `active_hotkeys` 中
    /// 还没有对应条目）。这是可接受的权衡，因为：
    /// 1. 时间窗口极短（微秒级）
    /// 2. 不影响 IPC 命令发送（IPC 命令在锁外发送）
    /// 3. 合并两个 RwLock 会增加锁争用（热键注册是高频操作）
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

    /// 更新分组热键（仅配置，不更新 active_hotkeys）。
    ///
    /// 调用方责任：若分组处于 active 状态，必须自行维护 active_hotkeys 一致性。
    /// 外部调用方应使用 `group_service::register_hotkey` 替代，后者自动处理
    /// 活跃/非活跃分组的 active_hotkeys 和 IPC 注册。
    pub(crate) fn set_group_hotkey(
        &self,
        group_id: &str,
        new_hotkey: &str,
    ) -> Result<(), AppError> {
        let mut cs = self.config_state.write();
        let group = cs
            .groups
            .get_mut(group_id)
            .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;
        group.hotkey = new_hotkey.to_string();
        // 同步更新 config.group_settings 以保持双源一致
        if let Some(gs) = cs.config.group_settings.get_mut(group_id) {
            gs.hotkey = new_hotkey.to_string();
        }
        Ok(())
    }

    pub fn toggle_group_active(&self, id: &str) -> Result<(bool, SkillGroup), AppError> {
        let (new_active, group, hotkey) = {
            let mut cs = self.config_state.write();
            let group = cs
                .groups
                .get_mut(id)
                .ok_or_else(|| AppError::GroupNotFound(id.to_string()))?;
            group.active = !group.active;
            (group.active, group.clone(), group.hotkey.clone())
        };

        if new_active {
            self.active_hotkeys
                .write()
                .insert(hotkey.clone(), id.to_string());
        } else {
            self.active_hotkeys.write().remove(&hotkey);
        }

        self.emit_event(
            "status_update",
            serde_json::json!({
                "groupId": id,
                "active": new_active,
            }),
        );
        Ok((new_active, group))
    }

    pub fn active_group_ids(&self) -> Vec<String> {
        self.active_hotkeys.read().values().cloned().collect()
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
        {
            let mut ws = self.watchdog_state.write();
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

    pub fn emit_event(&self, event: &str, payload: serde_json::Value) -> bool {
        self.event_emitter.emit(event, payload)
    }

    pub fn reset_watchdog(&self) -> Result<(), AppError> {
        self.watchdog
            .reset()
            .map_err(|e| AppError::Internal(format!("重置看门狗失败: {e}")))
    }

    pub fn get_config_path(&self) -> Option<PathBuf> {
        self.config_path.read().clone()
    }

    pub fn set_config_path(&self, path: PathBuf) {
        *self.config_path.write() = Some(path);
    }

    pub fn save_config_atomic(&self, mut new_config: Config) -> Result<(), AppError> {
        // 内部验证配置，防止无效配置被写入内存和磁盘
        let validation = asd_domain::validator::ConfigValidator::validate_config(&new_config);
        if !validation.is_valid() {
            return Err(AppError::Validation(
                validation
                    .errors
                    .iter()
                    .map(|e| e.to_string())
                    .collect::<Vec<_>>()
                    .join("; "),
            ));
        }

        let config_path = self.get_config_path();

        let (old_config, old_groups, old_version, new_hotkey_map, new_groups) = {
            let mut guard = self.config_state.write();
            new_config.last_modified = Some(chrono::Local::now().to_rfc3339());
            let old_config = guard.config.clone();
            let old_groups = guard.groups.clone();
            let old_version = guard.version;

            let mut new_groups = Self::build_groups_from_config(&new_config);
            for (id, new_group) in new_groups.iter_mut() {
                if let Some(old_group) = old_groups.get(id) {
                    new_group.active = old_group.active;
                }
            }

            let mut new_hotkey_map = HashMap::new();
            for (id, group) in &new_groups {
                if group.active {
                    new_hotkey_map.insert(group.hotkey.clone(), id.clone());
                }
            }

            guard.config = new_config.clone();
            guard.groups = new_groups.clone();
            guard.version += 1;
            (
                old_config,
                old_groups,
                old_version,
                new_hotkey_map,
                new_groups,
            )
        };

        {
            let mut registry = self.active_hotkeys.write();
            *registry = new_hotkey_map;
        }

        if let Some(path) = config_path {
            if let Err(e) = ConfigRepository::save_to_path(&new_config, &path) {
                tracing::error!("保存配置到磁盘失败，回滚内存状态: {e}");
                let restored_hotkey_map = {
                    let mut guard = self.config_state.write();
                    if guard.version == old_version + 1 {
                        guard.config = old_config;
                        guard.groups = old_groups;
                        guard.version = old_version;
                    } else {
                        tracing::warn!(
                            "保存失败后回滚跳过：版本已变更 (当前={}, 预期={})",
                            guard.version,
                            old_version + 1
                        );
                    }
                    let mut map = HashMap::new();
                    for (id, group) in &guard.groups {
                        if group.active {
                            map.insert(group.hotkey.clone(), id.clone());
                        }
                    }
                    map
                };
                {
                    let mut registry = self.active_hotkeys.write();
                    *registry = restored_hotkey_map;
                }
                return Err(AppError::Config(e));
            }
        } else {
            tracing::warn!(
                "save_config_atomic: config_path 未设置，仅更新内存状态，配置不会持久化到磁盘"
            );
        }

        self.sync_config_changes_to_ahk(&old_groups, &new_groups);

        Ok(())
    }

    /// 注册热键到 active_hotkeys 映射。
    ///
    /// # 调用方责任
    ///
    /// 若同一 group_id 已注册了其他热键，调用方必须先调用 `unregister_hotkey`
    /// 注销旧热键，否则旧热键将残留在 active_hotkeys 中导致热键泄漏。
    pub fn register_hotkey(
        &self,
        hotkey: &str,
        group_id: &str,
    ) -> Result<Option<String>, AppError> {
        let mut registry = self.active_hotkeys.write();
        if let Some(existing) = registry.get(hotkey) {
            return Ok(Some(existing.clone()));
        }
        let existing = registry.insert(hotkey.to_string(), group_id.to_string());
        Ok(existing)
    }

    pub fn unregister_hotkey(&self, hotkey: &str) -> Result<bool, AppError> {
        let mut registry = self.active_hotkeys.write();
        Ok(registry.remove(hotkey).is_some())
    }

    pub fn unregister_hotkey_return_group(&self, hotkey: &str) -> Result<Option<String>, AppError> {
        let mut registry = self.active_hotkeys.write();
        Ok(registry.remove(hotkey))
    }

    pub fn is_hotkey_registered(&self, hotkey: &str) -> Result<bool, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry.contains_key(hotkey))
    }

    pub fn get_hotkey_group(&self, hotkey: &str) -> Result<Option<String>, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry.get(hotkey).cloned())
    }

    pub fn get_hotkey_group_id(&self, group_id: &str) -> Result<Option<String>, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry
            .iter()
            .find(|(_, gid)| *gid == group_id)
            .map(|(h, _)| h.clone()))
    }

    pub fn remove_group_hotkeys(&self, group_id: &str) -> Result<(), AppError> {
        let mut registry = self.active_hotkeys.write();
        registry.retain(|_, gid| gid != group_id);
        Ok(())
    }

    pub fn swap_hotkey(
        &self,
        new_hotkey: &str,
        group_id: &str,
    ) -> Result<Option<String>, AppError> {
        let mut registry = self.active_hotkeys.write();
        if let Some(existing) = registry.get(new_hotkey) {
            if existing != group_id {
                return Err(AppError::Validation(format!(
                    "热键 '{}' 已被分组 '{}' 注册",
                    new_hotkey, existing
                )));
            }
        }
        let old_hotkey = registry
            .iter()
            .find(|(_, gid)| *gid == group_id)
            .map(|(h, _)| h.clone());
        if let Some(ref old) = old_hotkey {
            if old != new_hotkey {
                registry.remove(old);
            }
        }
        registry.insert(new_hotkey.to_string(), group_id.to_string());
        Ok(old_hotkey)
    }

    pub fn get_all_registered_hotkeys(&self) -> Result<Vec<(String, String)>, AppError> {
        let registry = self.active_hotkeys.read();
        Ok(registry
            .iter()
            .map(|(hotkey, group_id)| (hotkey.clone(), group_id.clone()))
            .collect())
    }

    fn group_params_changed(old: &SkillGroup, new: &SkillGroup) -> bool {
        old.mode != new.mode
            || old.mode_data != new.mode_data
            || old.key_press_duration != new.key_press_duration
            || old.hold_keys != new.hold_keys
            || old.hold_mode != new.hold_mode
    }

    /// 将配置变更同步到 AHK 子进程。
    ///
    /// # 热键变更窗口
    ///
    /// 热键注销和重注册通过独立的 IPC 命令顺序发送。在 UnregisterHotkey 和
    /// RegisterHotkey 之间，目标热键可能短暂处于未注册状态（亚毫秒级窗口），
    /// 用户按键可能不被响应。此为 fire-and-forget IPC 的固有局限。
    ///
    /// # 并发命令乱序风险
    ///
    /// 此方法使用 `try_send_ipc_command`（fire-and-forget）发送热键注册/注销命令。
    /// 如果 `toggle_group` 等并发操作同时发送热键命令，AHK 侧可能收到乱序的
    /// 注册/注销命令，导致热键注册状态与 Rust 侧 `active_hotkeys` 不一致。
    /// 此风险在实际场景中极低（需要高并发配置修改+分组切换），且 AHK 重连后
    /// 会通过 `post_connect_callback` 重新同步状态。
    fn sync_config_changes_to_ahk(
        &self,
        old_groups: &IndexMap<String, SkillGroup>,
        new_groups: &IndexMap<String, SkillGroup>,
    ) {
        let mut hotkeys_to_unregister: Vec<String> = Vec::new();
        let mut hotkeys_to_register: Vec<(String, String)> = Vec::new();
        let mut toggle_commands: Vec<IpcCommand> = Vec::new();

        for (id, new_group) in new_groups {
            let was_active = old_groups.get(id).map(|g| g.active).unwrap_or(false);

            if new_group.active && !was_active {
                toggle_commands.push(crate::group_service::build_toggle_command(
                    id, true, new_group,
                ));
                hotkeys_to_register.push((new_group.hotkey.clone(), id.clone()));
            } else if !new_group.active && was_active {
                if let Some(old_group) = old_groups.get(id) {
                    toggle_commands.push(crate::group_service::build_toggle_command(
                        id, false, old_group,
                    ));
                    hotkeys_to_unregister.push(old_group.hotkey.clone());
                }
            } else if new_group.active && was_active {
                if let Some(old_group) = old_groups.get(id) {
                    if old_group.hotkey != new_group.hotkey {
                        tracing::info!(
                            "分组 {} 热键变更 {} → {}，同步到 AHK",
                            id,
                            old_group.hotkey,
                            new_group.hotkey
                        );
                        hotkeys_to_unregister.push(old_group.hotkey.clone());
                        hotkeys_to_register.push((new_group.hotkey.clone(), id.clone()));
                    }
                    if Self::group_params_changed(old_group, new_group) {
                        tracing::info!("分组 {} 参数已变更，重新同步到 AHK", id);
                        toggle_commands.push(crate::group_service::build_toggle_command(
                            id, true, new_group,
                        ));
                    }
                }
            }
        }

        for (id, old_group) in old_groups {
            if old_group.active && !new_groups.contains_key(id) {
                toggle_commands.push(crate::group_service::build_toggle_command(
                    id, false, old_group,
                ));
                hotkeys_to_unregister.push(old_group.hotkey.clone());
            }
        }

        let new_hotkey_set: std::collections::HashSet<&str> = hotkeys_to_register
            .iter()
            .map(|(h, _)| h.as_str())
            .collect();
        for hotkey in &hotkeys_to_unregister {
            if !new_hotkey_set.contains(hotkey.as_str()) {
                let unreg_cmd = IpcCommand::UnregisterHotkey {
                    hotkey: hotkey.clone(),
                };
                self.try_send_ipc_command(&unreg_cmd);
            }
        }
        for (hotkey, group_id) in &hotkeys_to_register {
            let reg_cmd = IpcCommand::RegisterHotkey {
                hotkey: hotkey.clone(),
                group_id: group_id.clone(),
            };
            self.try_send_ipc_command(&reg_cmd);
        }

        for cmd in toggle_commands {
            self.try_send_ipc_command(&cmd);
        }
    }

    /// 原子删除分组：先更新内存，再写磁盘，最后同步 IPC。
    ///
    /// # 执行顺序
    ///
    /// 1. 在 `config_state` 写锁内删除分组、递增版本号
    /// 2. 更新 `active_hotkeys`（移除已删除分组的热键）
    /// 3. 写入磁盘（若失败则回滚内存状态）
    /// 4. 发送 IPC 命令（ToggleGroup(false) + UnregisterHotkey）
    ///
    /// # IPC 失败行为
    ///
    /// 磁盘写入成功后发送 IPC 命令（ToggleGroup(false) + UnregisterHotkey）。
    /// 若 IPC 发送失败，内存和磁盘状态已提交（分组已删除），但 AHK 子进程可能
    /// 仍在执行该分组的按键序列且热键钩子仍然注册。此为已知设计权衡——
    /// IPC 失败时无法回滚磁盘写入，使用 `try_send_ipc_command` 仅记录警告。
    pub fn delete_group_atomic(&self, group_id: &str) -> Result<bool, AppError> {
        let config_path = self.get_config_path();

        let (is_active, ipc_cmd, deleted_hotkey, saved_config, old_config, old_groups, old_version) = {
            let mut cs = self.config_state.write();

            if !cs.config.group_settings.contains_key(group_id) {
                return Err(AppError::GroupNotFound(group_id.to_string()));
            }

            let is_active = cs.groups.get(group_id).map(|g| g.active).unwrap_or(false);

            let old_config = cs.config.clone();
            let old_groups = cs.groups.clone();
            let old_version = cs.version;
            cs.config.group_settings.shift_remove(group_id);

            let deleted_group = cs.groups.shift_remove(group_id);
            cs.version += 1;

            let saved_config = cs.config.clone();

            let deleted_hotkey = if is_active {
                deleted_group.as_ref().map(|g| g.hotkey.clone())
            } else {
                None
            };

            let ipc_cmd = if is_active {
                deleted_group
                    .as_ref()
                    .map(|g| crate::group_service::build_toggle_command(group_id, false, g))
            } else {
                None
            };

            (
                is_active,
                ipc_cmd,
                deleted_hotkey,
                saved_config,
                old_config,
                old_groups,
                old_version,
            )
        };

        // 无论是否活跃，都清理 active_hotkeys 中可能残留的热键
        // （由于 config_state 和 active_hotkeys 使用不同 RwLock，非活跃分组
        // 的热键可能因 TOCTOU 窗口残留在 active_hotkeys 中）
        self.active_hotkeys.write().retain(|_, gid| gid != group_id);

        if let Some(path) = config_path {
            if let Err(e) = ConfigRepository::save_to_path(&saved_config, &path) {
                tracing::error!("删除分组后保存配置失败，回滚内存状态: {e}");
                let restored_hotkey_map = {
                    let mut cs = self.config_state.write();
                    if cs.version == old_version + 1 {
                        cs.config = old_config;
                        cs.groups = old_groups;
                        cs.version = old_version;
                    } else {
                        tracing::warn!(
                            "删除分组回滚跳过：版本已变更 (当前={}, 预期={})",
                            cs.version,
                            old_version + 1
                        );
                    }
                    let mut map = HashMap::new();
                    for (id, group) in &cs.groups {
                        if group.active {
                            map.insert(group.hotkey.clone(), id.clone());
                        }
                    }
                    map
                };
                {
                    let mut registry = self.active_hotkeys.write();
                    *registry = restored_hotkey_map;
                }
                return Err(AppError::Config(format!("删除分组后保存配置失败: {e}")));
            }
        }

        if let Some(cmd) = ipc_cmd {
            self.try_send_ipc_command(&cmd);
        }
        if let Some(hotkey) = deleted_hotkey {
            let unreg_cmd = IpcCommand::UnregisterHotkey { hotkey };
            self.try_send_ipc_command(&unreg_cmd);
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
            "磁盘写入失败时内存应保持原始值"
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

    struct RecordingMockIpcSender {
        commands: std::sync::Mutex<Vec<IpcCommand>>,
    }
    impl RecordingMockIpcSender {
        fn new() -> Self {
            Self {
                commands: std::sync::Mutex::new(Vec::new()),
            }
        }
        fn take_commands(&self) -> Vec<IpcCommand> {
            std::mem::take(&mut *self.commands.lock().unwrap())
        }
    }
    impl IpcSender for RecordingMockIpcSender {
        fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
            self.commands.lock().unwrap().push(cmd);
            Ok(1)
        }
        fn send_and_wait(
            &self,
            _cmd: IpcCommand,
            _timeout: Duration,
        ) -> Result<IpcMessage, String> {
            Ok(IpcMessage::response(1, 0, "ok", None))
        }
        fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
            Ok(())
        }
    }

    fn make_recording_state() -> (Arc<AppState>, Arc<RecordingMockIpcSender>) {
        let config = make_test_config();
        let ipc_sender = Arc::new(RecordingMockIpcSender::new());
        let watchdog = Arc::new(MockProcessWatcher);
        let event_emitter = Arc::new(MockEventEmitter::new());
        let state = Arc::new(AppState::new(
            config,
            ipc_sender.clone(),
            watchdog,
            event_emitter,
        ));
        (state, ipc_sender)
    }

    fn base_group() -> SkillGroup {
        SkillGroup {
            id: "1".to_string(),
            name: "测试组".to_string(),
            hotkey: "F1".to_string(),
            active: false,
            mode: "periodic".to_string(),
            key_press_duration: 10,
            hold_keys: None,
            hold_mode: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        }
    }

    #[test]
    fn test_group_params_changed_identical() {
        let g = base_group();
        assert!(!AppState::group_params_changed(&g, &g));
    }

    #[test]
    fn test_group_params_changed_mode() {
        let old_g = base_group();
        let mut new_g = old_g.clone();
        new_g.mode = "sequence".to_string();
        assert!(AppState::group_params_changed(&old_g, &new_g));
    }

    #[test]
    fn test_group_params_changed_mode_data() {
        let old_g = base_group();
        let mut new_g = old_g.clone();
        new_g.mode_data = ModeData::Periodic(PeriodicData {
            keys: vec!["2".to_string()],
            intervals: vec![100],
        });
        assert!(AppState::group_params_changed(&old_g, &new_g));
    }

    #[test]
    fn test_group_params_changed_key_press_duration() {
        let old_g = base_group();
        let mut new_g = old_g.clone();
        new_g.key_press_duration = 20;
        assert!(AppState::group_params_changed(&old_g, &new_g));
    }

    #[test]
    fn test_group_params_changed_hold_keys() {
        let old_g = base_group();
        let mut new_g = old_g.clone();
        new_g.hold_keys = Some(vec!["Shift".to_string()]);
        assert!(AppState::group_params_changed(&old_g, &new_g));
    }

    #[test]
    fn test_group_params_changed_hold_mode() {
        let old_g = base_group();
        let mut new_g = old_g.clone();
        new_g.hold_mode = Some("continuous".to_string());
        assert!(AppState::group_params_changed(&old_g, &new_g));
    }

    #[test]
    fn test_group_params_changed_hotkey() {
        let old_g = base_group();
        let mut new_g = old_g.clone();
        new_g.hotkey = "F2".to_string();
        assert!(!AppState::group_params_changed(&old_g, &new_g));
    }

    #[test]
    fn test_sync_newly_activated_group() {
        let (state, sender) = make_recording_state();

        let mut old_groups = IndexMap::new();
        old_groups.insert(
            "1".to_string(),
            SkillGroup {
                id: "1".to_string(),
                name: "测试组".to_string(),
                hotkey: "F1".to_string(),
                active: false,
                mode: "periodic".to_string(),
                key_press_duration: 10,
                hold_keys: None,
                hold_mode: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["1".to_string()],
                    intervals: vec![50],
                }),
            },
        );

        state.set_group_active("1", true).unwrap();
        sender.take_commands();

        let new_groups = state.read_groups().unwrap();
        state.sync_config_changes_to_ahk(&old_groups, &new_groups);

        let cmds = sender.take_commands();
        assert_eq!(cmds.len(), 2);
        match &cmds[0] {
            IpcCommand::RegisterHotkey { hotkey, group_id } => {
                assert_eq!(hotkey, "F1");
                assert_eq!(group_id, "1");
            }
            other => panic!("Expected RegisterHotkey, got {:?}", other),
        }
        match &cmds[1] {
            IpcCommand::ToggleGroup {
                group_id, active, ..
            } => {
                assert_eq!(group_id, "1");
                assert!(*active);
            }
            other => panic!("Expected ToggleGroup(true), got {:?}", other),
        }
    }

    #[test]
    fn test_sync_deactivated_group() {
        let (state, sender) = make_recording_state();
        state.set_group_active("1", true).unwrap();
        sender.take_commands();

        let mut old_groups = IndexMap::new();
        old_groups.insert(
            "1".to_string(),
            SkillGroup {
                id: "1".to_string(),
                name: "测试组".to_string(),
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
            },
        );

        state.set_group_active("1", false).unwrap();
        let new_groups = state.read_groups().unwrap();
        state.sync_config_changes_to_ahk(&old_groups, &new_groups);

        let cmds = sender.take_commands();
        assert_eq!(cmds.len(), 2);
        match &cmds[0] {
            IpcCommand::UnregisterHotkey { hotkey } => {
                assert_eq!(hotkey, "F1");
            }
            other => panic!("Expected UnregisterHotkey, got {:?}", other),
        }
        match &cmds[1] {
            IpcCommand::ToggleGroup {
                group_id, active, ..
            } => {
                assert_eq!(group_id, "1");
                assert!(!*active);
            }
            other => panic!("Expected ToggleGroup(false), got {:?}", other),
        }
    }

    #[test]
    fn test_sync_hotkey_change() {
        let (state, sender) = make_recording_state();
        state.set_group_active("1", true).unwrap();
        sender.take_commands();

        let mut new_config = make_test_config();
        new_config.group_settings.get_mut("1").unwrap().hotkey = "F2".to_string();
        state.save_config_atomic(new_config).unwrap();

        let cmds = sender.take_commands();
        assert_eq!(cmds.len(), 2);
        match &cmds[0] {
            IpcCommand::UnregisterHotkey { hotkey } => {
                assert_eq!(hotkey, "F1");
            }
            other => panic!("Expected UnregisterHotkey(F1), got {:?}", other),
        }
        match &cmds[1] {
            IpcCommand::RegisterHotkey { hotkey, group_id } => {
                assert_eq!(hotkey, "F2");
                assert_eq!(group_id, "1");
            }
            other => panic!("Expected RegisterHotkey(F2), got {:?}", other),
        }
    }

    #[test]
    fn test_sync_param_change() {
        let (state, sender) = make_recording_state();
        state.set_group_active("1", true).unwrap();
        sender.take_commands();

        let mut new_config = make_test_config();
        new_config
            .group_settings
            .get_mut("1")
            .unwrap()
            .key_press_duration = Some(99);
        state.save_config_atomic(new_config).unwrap();

        let cmds = sender.take_commands();
        assert_eq!(cmds.len(), 1);
        match &cmds[0] {
            IpcCommand::ToggleGroup {
                group_id, active, ..
            } => {
                assert_eq!(group_id, "1");
                assert!(*active);
            }
            other => panic!("Expected ToggleGroup(true), got {:?}", other),
        }
    }

    #[test]
    fn test_sync_deleted_active_group() {
        let (state, sender) = make_recording_state();
        state.set_group_active("1", true).unwrap();
        sender.take_commands();

        let new_config = Config {
            control_hotkeys: ControlHotkeys {
                emergency: "F10".to_string(),
                release_all_holds: "^r".to_string(),
                show_status: "^0".to_string(),
                toggle_all: "^1".to_string(),
                toggle_hold_mode: "^h".to_string(),
            },
            group_settings: IndexMap::new(),
            hold_settings: None,
            last_modified: None,
            version: Some("3.0".to_string()),
        };
        state.save_config_atomic(new_config).unwrap();

        let cmds = sender.take_commands();
        assert_eq!(cmds.len(), 2);
        match &cmds[0] {
            IpcCommand::UnregisterHotkey { hotkey } => {
                assert_eq!(hotkey, "F1");
            }
            other => panic!("Expected UnregisterHotkey, got {:?}", other),
        }
        match &cmds[1] {
            IpcCommand::ToggleGroup {
                group_id, active, ..
            } => {
                assert_eq!(group_id, "1");
                assert!(!*active);
            }
            other => panic!("Expected ToggleGroup(false), got {:?}", other),
        }
    }

    #[test]
    fn test_sync_no_changes() {
        let (state, sender) = make_recording_state();
        sender.take_commands();

        let new_config = make_test_config();
        state.save_config_atomic(new_config).unwrap();

        let cmds = sender.take_commands();
        assert!(
            cmds.is_empty(),
            "无变更时不应发送任何 IPC 命令，实际收到 {} 条",
            cmds.len()
        );
    }

    #[test]
    fn test_sync_hotkey_swap_no_unregister() {
        let mut config = make_test_config();
        config.group_settings.insert(
            "2".to_string(),
            GroupConfig {
                hotkey: "F2".to_string(),
                key_press_duration: Some(10),
                name: Some("测试组2".to_string()),
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["2".to_string()],
                    intervals: vec![100],
                }),
            },
        );
        let ipc_sender = Arc::new(RecordingMockIpcSender::new());
        let watchdog = Arc::new(MockProcessWatcher);
        let event_emitter = Arc::new(MockEventEmitter::new());
        let state = Arc::new(AppState::new(
            config,
            ipc_sender.clone(),
            watchdog,
            event_emitter,
        ));

        state.set_group_active("1", true).unwrap();
        state.set_group_active("2", true).unwrap();
        ipc_sender.take_commands();

        let mut new_config = state.read_config().unwrap();
        new_config.group_settings.get_mut("1").unwrap().hotkey = "F2".to_string();
        new_config.group_settings.get_mut("2").unwrap().hotkey = "F1".to_string();
        state.save_config_atomic(new_config).unwrap();

        let cmds = ipc_sender.take_commands();

        let unreg_count = cmds
            .iter()
            .filter(|c| matches!(c, IpcCommand::UnregisterHotkey { .. }))
            .count();
        assert_eq!(unreg_count, 0, "热键交换场景不应发送 UnregisterHotkey 命令");

        let reg_cmds: Vec<_> = cmds
            .iter()
            .filter_map(|c| {
                if let IpcCommand::RegisterHotkey { hotkey, group_id } = c {
                    Some((hotkey.clone(), group_id.clone()))
                } else {
                    None
                }
            })
            .collect();
        assert_eq!(reg_cmds.len(), 2);
        assert!(reg_cmds.contains(&("F2".to_string(), "1".to_string())));
        assert!(reg_cmds.contains(&("F1".to_string(), "2".to_string())));
    }

    #[test]
    fn test_watchdog_state_serializes_restart_count_as_camel_case() {
        let state = WatchdogState::new();
        let json = serde_json::to_string(&state).unwrap();
        assert!(
            json.contains("\"restartCount\""),
            "JSON 应包含 restartCount 字段（camelCase），实际: {}",
            json
        );
        assert!(
            !json.contains("\"restart_count\""),
            "JSON 不应包含 restart_count 字段（snake_case），实际: {}",
            json
        );
    }
}
