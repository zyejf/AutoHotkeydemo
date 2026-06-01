use asd_application::config_repository::ConfigRepository;
use asd_application::error::AppError;
#[allow(deprecated)]
use asd_application::scheduler::SkillManager;
use asd_application::state::{AppState, WatchdogState};
use asd_domain::config::*;
use asd_domain::models::SkillGroup;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use std::collections::HashMap;
use std::sync::Arc;

struct MockIpcSender {
    sent_commands: std::sync::Mutex<Vec<IpcCommand>>,
}

impl MockIpcSender {
    fn new() -> Self {
        Self {
            sent_commands: std::sync::Mutex::new(Vec::new()),
        }
    }
}

impl IpcSender for MockIpcSender {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        self.sent_commands.lock().unwrap().push(cmd);
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

fn make_periodic_group_config() -> GroupConfig {
    GroupConfig {
        hotkey: "F1".to_string(),
        key_press_duration: Some(10),
        name: Some("周期按键".to_string()),
        mode: "periodic".to_string(),
        hold_keys: None,
        hold_mode: None,
        hold_pattern: None,
        hold_triggers: None,
        mode_data: ModeData::Periodic(PeriodicData {
            keys: vec!["1".to_string()],
            intervals: vec![50],
        }),
    }
}

fn make_sequence_group_config() -> GroupConfig {
    GroupConfig {
        hotkey: "F2".to_string(),
        key_press_duration: None,
        name: Some("序列按键".to_string()),
        mode: "sequence".to_string(),
        hold_keys: None,
        hold_mode: None,
        hold_pattern: None,
        hold_triggers: None,
        mode_data: ModeData::Sequence(SequenceData {
            keys: vec!["A".to_string()],
            delays: vec![100],
        }),
    }
}

fn make_hold_group_config() -> GroupConfig {
    GroupConfig {
        hotkey: "F3".to_string(),
        key_press_duration: None,
        name: Some("长按模式".to_string()),
        mode: "hold".to_string(),
        hold_keys: Some(vec!["Shift".to_string()]),
        hold_mode: Some("continuous".to_string()),
        hold_pattern: None,
        hold_triggers: None,
        mode_data: ModeData::Hold(HoldData {
            hold_duration: 500,
            auto_repeat: None,
            repeat_interval: None,
        }),
    }
}

fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert("1".to_string(), make_periodic_group_config());
    group_settings.insert("2".to_string(), make_sequence_group_config());
    group_settings.insert("3".to_string(), make_hold_group_config());

    Config {
        control_hotkeys: ControlHotkeys {
            emergency: "F10".to_string(),
            release_all_holds: "^r".to_string(),
            show_status: "^0".to_string(),
            toggle_all: "^1".to_string(),
            toggle_hold_mode: "^h".to_string(),
        },
        group_settings,
        hold_settings: Some(HoldSettings {
            allow_overlap: false,
            check_interval: 50,
            debounce_delay: 25,
            press_speed: 80,
            release_on_emergency: true,
        }),
        last_modified: None,
        version: Some("3.0".to_string()),
    }
}

fn make_skill_group(id: &str, mode: &str) -> SkillGroup {
    let mode_data = match mode {
        "periodic" => ModeData::Periodic(PeriodicData {
            keys: vec!["1".to_string()],
            intervals: vec![50],
        }),
        "sequence" => ModeData::Sequence(SequenceData {
            keys: vec!["A".to_string()],
            delays: vec![100],
        }),
        "hold" => ModeData::Hold(HoldData {
            hold_duration: 500,
            auto_repeat: None,
            repeat_interval: None,
        }),
        _ => ModeData::Periodic(PeriodicData {
            keys: vec!["1".to_string()],
            intervals: vec![50],
        }),
    };

    SkillGroup {
        id: id.to_string(),
        name: format!("组 {id}"),
        hotkey: format!("F{id}"),
        active: false,
        mode: mode.to_string(),
        key_press_duration: 10,
        hold_keys: if mode == "hold" {
            Some(vec!["Shift".to_string()])
        } else {
            None
        },
        hold_mode: if mode == "hold" {
            Some("continuous".to_string())
        } else {
            None
        },
        mode_data,
    }
}

fn make_test_state() -> Arc<AppState> {
    let config = make_test_config();
    let ipc_sender = Arc::new(MockIpcSender::new());
    let watchdog = Arc::new(MockProcessWatcher);
    let event_emitter = Arc::new(MockEventEmitter::new());
    Arc::new(AppState::new(config, ipc_sender, watchdog, event_emitter))
}

#[test]
fn test_skill_manager_lifecycle() {
    let ipc_sender = Arc::new(MockIpcSender::new());
    let mut groups = HashMap::new();
    groups.insert("1".to_string(), make_skill_group("1", "periodic"));
    groups.insert("2".to_string(), make_skill_group("2", "sequence"));

    let mut mgr = SkillManager::new(groups, ipc_sender);

    assert!(!mgr.get_group("1").unwrap().active);
    assert!(mgr.get_active_groups().is_empty());

    mgr.activate("1").unwrap();
    assert!(mgr.get_group("1").unwrap().active);
    assert_eq!(mgr.get_active_groups().len(), 1);
    assert_eq!(mgr.get_hotkey_group("F1"), Some("1"));

    mgr.deactivate("1").unwrap();
    assert!(!mgr.get_group("1").unwrap().active);
    assert!(mgr.get_active_groups().is_empty());
    assert_eq!(mgr.get_hotkey_group("F1"), None);
}

#[test]
fn test_skill_manager_toggle() {
    let ipc_sender = Arc::new(MockIpcSender::new());
    let mut groups = HashMap::new();
    groups.insert("1".to_string(), make_skill_group("1", "periodic"));

    let mut mgr = SkillManager::new(groups, ipc_sender);

    let result = mgr.toggle("1").unwrap();
    assert!(result);
    assert!(mgr.get_group("1").unwrap().active);

    let result = mgr.toggle("1").unwrap();
    assert!(!result);
    assert!(!mgr.get_group("1").unwrap().active);
}

#[test]
fn test_skill_manager_reload() {
    let ipc_sender = Arc::new(MockIpcSender::new());
    let mut groups = HashMap::new();
    groups.insert("1".to_string(), make_skill_group("1", "periodic"));

    let mut mgr = SkillManager::new(groups, ipc_sender);
    mgr.activate("1").unwrap();
    assert!(mgr.get_hotkey_group("F1").is_some());

    let mut new_groups = HashMap::new();
    new_groups.insert("3".to_string(), make_skill_group("3", "hold"));
    mgr.reload_groups(new_groups);

    assert!(mgr.get_group("1").is_none());
    assert!(mgr.get_group("3").is_some());
    assert!(mgr.get_hotkey_group("F1").is_none());
}

#[test]
fn test_skill_manager_hotkey_registry() {
    let ipc_sender = Arc::new(MockIpcSender::new());
    let mut groups = HashMap::new();
    groups.insert("1".to_string(), make_skill_group("1", "periodic"));

    let mut mgr = SkillManager::new(groups, ipc_sender);

    mgr.register_hotkey("F10", "10").unwrap();
    assert_eq!(mgr.get_hotkey_group("F10"), Some("10"));

    let result = mgr.register_hotkey("F10", "11");
    assert!(result.is_err());

    mgr.unregister_hotkey("F10").unwrap();
    assert_eq!(mgr.get_hotkey_group("F10"), None);

    let result = mgr.unregister_hotkey("F10");
    assert!(result.is_err());
}

#[test]
fn test_skill_manager_nonexistent_group() {
    let ipc_sender = Arc::new(MockIpcSender::new());
    let groups = HashMap::new();
    let mut mgr = SkillManager::new(groups, ipc_sender);

    assert!(mgr.activate("999").is_err());
    assert!(mgr.deactivate("999").is_err());
    assert!(mgr.toggle("999").is_err());
}

#[test]
fn test_skill_manager_build_toggle_command() {
    let group = make_skill_group("1", "periodic");
    let cmd = SkillManager::build_toggle_command(&group);
    match cmd {
        IpcCommand::ToggleGroup {
            group_id,
            active,
            mode,
            key_press_duration,
            hold_keys,
            hold_mode,
            mode_data,
        } => {
            assert_eq!(group_id, "1");
            assert!(!active);
            assert_eq!(mode, Some("periodic".to_string()));
            assert_eq!(key_press_duration, Some(10));
            assert!(hold_keys.is_none());
            assert!(hold_mode.is_none());
            assert!(mode_data.is_some());
        }
        _ => panic!("Expected ToggleGroup"),
    }
}

#[test]
fn test_app_state_creation_and_groups() {
    let state = make_test_state();
    assert!(!state.is_emergency_mode());
    assert!(!state.is_hold_mode_enabled());

    let group = state.get_group("1").unwrap();
    assert_eq!(group.id, "1");
    assert_eq!(group.name, "周期按键");
    assert_eq!(group.hotkey, "F1");
    assert!(!group.active);

    let group2 = state.get_group("2").unwrap();
    assert_eq!(group2.mode, "sequence");
}

#[test]
fn test_app_state_emergency_mode() {
    let state = make_test_state();
    assert!(!state.is_emergency_mode());

    state.set_emergency_mode(true);
    assert!(state.is_emergency_mode());

    state.set_emergency_mode(false);
    assert!(!state.is_emergency_mode());
}

#[test]
fn test_app_state_hold_mode() {
    let state = make_test_state();
    assert!(!state.is_hold_mode_enabled());

    state.set_hold_mode_enabled(true);
    assert!(state.is_hold_mode_enabled());

    state.set_hold_mode_enabled(false);
    assert!(!state.is_hold_mode_enabled());
}

#[test]
fn test_app_state_set_group_active() {
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
fn test_app_state_group_not_found() {
    let state = make_test_state();
    let result = state.set_group_active("999", true);
    assert!(matches!(result, Err(AppError::GroupNotFound(_))));
}

#[test]
fn test_app_state_read_config() {
    let state = make_test_state();
    let config = state.read_config().unwrap();
    assert_eq!(config.control_hotkeys.emergency, "F10");
    assert_eq!(config.group_settings.len(), 3);
}

#[test]
fn test_app_state_read_groups() {
    let state = make_test_state();
    let groups = state.read_groups().unwrap();
    assert_eq!(groups.len(), 3);
    assert!(groups.contains_key("1"));
    assert!(groups.contains_key("2"));
    assert!(groups.contains_key("3"));
}

#[test]
fn test_app_state_watchdog() {
    let emitter = Arc::new(MockEventEmitter::new());
    let config = make_test_config();
    let ipc_sender = Arc::new(MockIpcSender::new());
    let watchdog = Arc::new(MockProcessWatcher);
    let state = AppState::new(config, ipc_sender, watchdog, emitter);

    state.update_watchdog_state(WatchdogStateEnum::Running, 1);
    {
        let ws = state.watchdog_state.read();
        assert_eq!(ws.status, WatchdogStateEnum::Running);
        assert_eq!(ws.restart_count, 1);
    }

    state.update_watchdog_state(WatchdogStateEnum::Hung, 2);
    {
        let ws = state.watchdog_state.read();
        assert_eq!(ws.status, WatchdogStateEnum::Hung);
        assert_eq!(ws.restart_count, 2);
    }
}

#[test]
fn test_app_state_config_path() {
    let state = make_test_state();
    assert!(state.get_config_path().is_none());

    let path = std::path::PathBuf::from("/tmp/asd/config.json");
    state.set_config_path(path.clone());
    assert_eq!(state.get_config_path().unwrap(), path);
}

#[test]
fn test_app_state_save_config_atomic_success() {
    let dir = std::env::temp_dir().join("asd_integration_test_save_atomic");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("config.json");
    let state = make_test_state();
    state.set_config_path(path.clone());

    let mut new_config = make_test_config();
    new_config.control_hotkeys.emergency = "F12".to_string();

    let result = state.save_config_atomic(new_config.clone());
    assert!(result.is_ok());

    let mem_config = state.read_config().unwrap();
    assert_eq!(mem_config.control_hotkeys.emergency, "F12");

    let file_content = std::fs::read_to_string(&path).unwrap();
    let file_config: Config = serde_json::from_str(&file_content).unwrap();
    assert_eq!(file_config.control_hotkeys.emergency, "F12");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_app_state_save_config_atomic_rollback() {
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
    assert!(result.is_err());

    let mem_config = state.read_config().unwrap();
    assert_eq!(mem_config.control_hotkeys.emergency, original_emergency);
}

#[test]
fn test_app_state_save_config_atomic_no_path() {
    let state = make_test_state();

    let mut new_config = make_test_config();
    new_config.control_hotkeys.emergency = "F12".to_string();

    let result = state.save_config_atomic(new_config);
    assert!(result.is_ok());

    let mem_config = state.read_config().unwrap();
    assert_eq!(mem_config.control_hotkeys.emergency, "F12");
}

#[test]
fn test_app_state_save_config_atomic_preserves_active_state() {
    let dir = std::env::temp_dir().join("asd_integration_test_preserve_active");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("config.json");
    let state = make_test_state();
    state.set_config_path(path.clone());

    state.set_group_active("1", true).unwrap();

    let mut new_config = make_test_config();
    new_config.control_hotkeys.emergency = "F12".to_string();
    state.save_config_atomic(new_config).unwrap();

    let group = state.get_group("1").unwrap();
    assert!(group.active, "保存后 active 状态应保留");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_app_state_ipc_commands() {
    let state = make_test_state();

    let cmd = IpcCommand::EmergencyRelease;
    let result = state.send_ipc_command(&cmd);
    assert!(result.is_ok());

    let cmd = IpcCommand::StopRecording;
    state.try_send_ipc_command(&cmd);

    let result = state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5));
    assert!(result.is_ok());

    let msg = IpcMessage::ping(1);
    state.try_send_ipc_message(&msg);
}

#[test]
fn test_app_state_emit_event() {
    let emitter = Arc::new(MockEventEmitter::new());
    let config = make_test_config();
    let ipc_sender = Arc::new(MockIpcSender::new());
    let watchdog = Arc::new(MockProcessWatcher);
    let state = AppState::new(config, ipc_sender, watchdog, emitter.clone());

    let result = state.emit_event("test_event", serde_json::json!({"key": "value"}));
    assert!(result);

    let emitted = emitter.emitted.lock().unwrap();
    assert_eq!(emitted.len(), 1);
    assert_eq!(emitted[0].0, "test_event");
}

#[test]
#[allow(deprecated)]
fn test_config_repository_load_save_roundtrip() {
    let dir = std::env::temp_dir().join("asd_integration_test_repo_roundtrip");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("config.json");
    let config = make_test_config();

    ConfigRepository::save_to_file(&config, &path).unwrap();
    let loaded = ConfigRepository::load_from_path(&path).unwrap();

    assert_eq!(loaded.control_hotkeys.emergency, "F10");
    assert_eq!(loaded.group_settings.len(), 3);
    assert!(loaded.hold_settings.is_some());

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_config_repository_load_missing_file_fallback() {
    let path = std::path::PathBuf::from("/nonexistent/path/config.json");
    let loaded = ConfigRepository::load_from_file(&path);
    assert_eq!(loaded.control_hotkeys.emergency, "F10");
}

#[test]
fn test_config_repository_load_invalid_json_fallback() {
    let dir = std::env::temp_dir().join("asd_integration_test_invalid_json");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("bad_config.json");
    std::fs::write(&path, "{invalid json!!!}").unwrap();

    let loaded = ConfigRepository::load_from_file(&path);
    assert_eq!(loaded.control_hotkeys.emergency, "F10");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_config_repository_load_from_path_error() {
    let path = std::path::PathBuf::from("/nonexistent/path/config.json");
    let result = ConfigRepository::load_from_path(&path);
    assert!(result.is_err());
}

#[test]
fn test_config_repository_save_to_path_atomic() {
    let dir = std::env::temp_dir().join("asd_integration_test_atomic_save");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("atomic_config.json");
    let config = make_test_config();

    ConfigRepository::save_to_path(&config, &path).unwrap();

    let content = std::fs::read_to_string(&path).unwrap();
    let loaded: Config = serde_json::from_str(&content).unwrap();
    assert_eq!(loaded.control_hotkeys.emergency, "F10");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
#[allow(deprecated)]
fn test_config_repository_save_to_invalid_path() {
    let path = std::path::PathBuf::from("/nonexistent/directory/config.json");
    let config = Config::default();
    let result = ConfigRepository::save_to_file(&config, &path);
    assert!(result.is_err());

    let result = ConfigRepository::save_to_path(&config, &path);
    assert!(result.is_err());
}

#[test]
fn test_config_repository_bom_stripped() {
    let dir = std::env::temp_dir().join("asd_integration_test_bom");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("bom_config.json");
    let config = Config::default();
    let json = serde_json::to_string_pretty(&config).unwrap();
    let bom_json = format!("\u{feff}{json}");
    std::fs::write(&path, bom_json.as_bytes()).unwrap();

    let loaded = ConfigRepository::load_from_file(&path);
    assert_eq!(loaded.control_hotkeys.emergency, "F10");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_app_error_from_ipc_error() {
    let ipc_err = asd_ipc_protocol::IpcError::ConnectionClosed;
    let app_err: AppError = ipc_err.into();
    assert!(matches!(app_err, AppError::Ipc(_)));
    assert!(format!("{app_err}").contains("连接已关闭"));
}

#[test]
fn test_app_error_serialization() {
    let err = AppError::Config("测试错误".to_string());
    let json = serde_json::to_string(&err).unwrap();
    assert!(json.contains("配置错误"));
}

#[test]
fn test_app_error_variants_display() {
    assert!(format!("{}", AppError::Config("c".to_string())).contains("配置错误"));
    assert!(format!("{}", AppError::Ipc("i".to_string())).contains("IPC"));
    assert!(format!("{}", AppError::GroupNotFound("g".to_string())).contains("分组不存在"));
    assert!(format!("{}", AppError::Validation("v".to_string())).contains("验证失败"));
    assert!(format!("{}", AppError::Internal("x".to_string())).contains("内部错误"));
}

#[test]
fn test_watchdog_state_new() {
    let ws = WatchdogState::new();
    assert_eq!(ws.status, WatchdogStateEnum::Idle);
    assert_eq!(ws.restart_count, 0);
    assert!(ws.last_restart.is_none());
}

#[test]
fn test_watchdog_state_default() {
    let ws = WatchdogState::default();
    assert_eq!(ws.status, WatchdogStateEnum::Idle);
}

#[test]
fn test_multiple_groups_concurrent_operations() {
    let state = make_test_state();

    state.set_group_active("1", true).unwrap();
    state.set_group_active("2", true).unwrap();
    state.set_group_active("3", true).unwrap();

    assert_eq!(state.active_group_ids().len(), 3);

    state.set_group_active("1", false).unwrap();
    assert_eq!(state.active_group_ids().len(), 2);
    assert!(!state.active_group_ids().contains(&"1".to_string()));
    assert!(state.active_group_ids().contains(&"2".to_string()));
    assert!(state.active_group_ids().contains(&"3".to_string()));
}

#[test]
fn test_skill_manager_multiple_groups() {
    let ipc_sender = Arc::new(MockIpcSender::new());
    let mut groups = HashMap::new();
    groups.insert("1".to_string(), make_skill_group("1", "periodic"));
    groups.insert("2".to_string(), make_skill_group("2", "sequence"));
    groups.insert("3".to_string(), make_skill_group("3", "hold"));

    let mut mgr = SkillManager::new(groups, ipc_sender);

    mgr.activate("1").unwrap();
    mgr.activate("2").unwrap();
    assert_eq!(mgr.get_active_groups().len(), 2);

    assert_eq!(mgr.get_hotkey_group("F1"), Some("1"));
    assert_eq!(mgr.get_hotkey_group("F2"), Some("2"));

    mgr.deactivate("1").unwrap();
    assert_eq!(mgr.get_hotkey_group("F1"), None);
    assert_eq!(mgr.get_hotkey_group("F2"), Some("2"));
}

#[test]
#[allow(deprecated)]
fn test_config_repository_overwrite_consistency() {
    let dir = std::env::temp_dir().join("asd_integration_test_overwrite");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("config.json");

    let config1 = Config::default();
    ConfigRepository::save_to_file(&config1, &path).unwrap();

    let mut config2 = Config::default();
    config2.control_hotkeys.emergency = "F12".to_string();
    ConfigRepository::save_to_file(&config2, &path).unwrap();

    let loaded = ConfigRepository::load_from_path(&path).unwrap();
    assert_eq!(loaded.control_hotkeys.emergency, "F12");

    let _ = std::fs::remove_dir_all(&dir);
}
