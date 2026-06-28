use asd_application::config_repository::ConfigRepository;
use asd_application::error::AppError;
#[allow(deprecated)]
use asd_application::scheduler::SkillManager;
use asd_application::state::AppState;
use asd_test_harness::*;
use indexmap::IndexMap;
use std::collections::HashMap;
use std::sync::Arc;

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

fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert("1".to_string(), make_periodic_group_config());

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

#[allow(dead_code)]
fn make_skill_group(id: &str, mode: &str) -> SkillGroup {
    let mode_data = match mode {
        "periodic" => ModeData::Periodic(PeriodicData {
            keys: vec!["1".to_string()],
            intervals: vec![50],
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
        hold_keys: None,
        hold_mode: None,
        mode_data,
    }
}

#[test]
fn test_config_to_validator_to_result() {
    let mut group_settings = IndexMap::new();
    group_settings.insert("1".to_string(), make_periodic_group_config());

    let result = ConfigValidator::validate(&group_settings);
    assert!(result.is_valid());

    let mut bad_settings = IndexMap::new();
    bad_settings.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "".to_string(),
            key_press_duration: None,
            name: None,
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec![],
                intervals: vec![],
            }),
        },
    );
    let result = ConfigValidator::validate(&bad_settings);
    assert!(!result.is_valid());
    assert!(result.errors.iter().any(|e| e.field == "hotkey"));
    assert!(result.errors.iter().any(|e| e.field == "keys"));
    assert!(result.errors.iter().any(|e| e.field == "intervals"));
}

#[test]
fn test_config_to_validator_duplicate_hotkeys() {
    let mut group_settings = IndexMap::new();
    group_settings.insert("1".to_string(), make_periodic_group_config());
    group_settings.insert(
        "2".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: None,
            name: None,
            mode: "sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Sequence(SequenceData {
                keys: vec!["2".to_string()],
                delays: vec![100],
            }),
        },
    );

    let result = ConfigValidator::validate(&group_settings);
    assert!(!result.is_valid());
    assert!(result
        .errors
        .iter()
        .any(|e| e.field == "hotkey" && e.message.contains("重复")));
}

#[test]
fn test_config_to_validator_serialization_roundtrip() {
    let mut group_settings = IndexMap::new();
    group_settings.insert("1".to_string(), make_periodic_group_config());

    let result = ConfigValidator::validate(&group_settings);
    let json = serde_json::to_string(&result).unwrap();
    let decoded: ValidationResult = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.is_valid(), result.is_valid());
    assert_eq!(decoded.errors.len(), result.errors.len());
}

#[test]
fn test_ipc_command_to_message_to_serialization() {
    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
        mode: Some("periodic".to_string()),
        key_press_duration: Some(10),
        hold_keys: None,
        hold_mode: None,
        mode_data: None,
    };

    let msg = IpcMessage::command(1, &cmd);
    assert_eq!(msg.r#type, "command");
    assert_eq!(msg.seq, 1);
    assert_eq!(msg.action.as_deref(), Some("toggle_group"));

    let json = serde_json::to_string(&msg).unwrap();
    let decoded: IpcMessage = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.r#type, "command");
    assert_eq!(decoded.seq, 1);

    let response = IpcMessage::response(2, 1, "ok", None);
    let resp_json = serde_json::to_string(&response).unwrap();
    let resp_decoded: IpcMessage = serde_json::from_str(&resp_json).unwrap();
    assert_eq!(resp_decoded.r#type, "response");
    assert_eq!(resp_decoded.ack_seq, Some(1));
}

#[test]
fn test_ipc_command_ping_pong_flow() {
    let cmd = IpcCommand::Ping;
    let msg = IpcMessage::command(1, &cmd);
    assert_eq!(msg.r#type, "command");
    assert_eq!(msg.action.as_deref(), Some("ping"));

    let ping = IpcMessage::ping(2);
    let pong = IpcMessage::pong(3, 2);

    let ping_json = serde_json::to_string(&ping).unwrap();
    let pong_json = serde_json::to_string(&pong).unwrap();

    let ping_decoded: IpcMessage = serde_json::from_str(&ping_json).unwrap();
    let pong_decoded: IpcMessage = serde_json::from_str(&pong_json).unwrap();

    assert_eq!(ping_decoded.r#type, "ping");
    assert_eq!(pong_decoded.r#type, "pong");
    assert_eq!(pong_decoded.ack_seq, Some(2));
}

#[test]
fn test_ipc_command_emergency_release_flow() {
    let cmd = IpcCommand::EmergencyRelease;
    let msg = IpcMessage::command(1, &cmd);
    assert_eq!(msg.action.as_deref(), Some("emergency_release"));
    assert!(msg.data.is_none());

    let json = serde_json::to_string(&msg).unwrap();
    let decoded: IpcMessage = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.action.as_deref(), Some("emergency_release"));
}

#[test]
fn test_skill_group_from_config_to_manager() {
    let config = make_test_config();
    let groups = AppState::build_groups_from_config(&config);

    assert_eq!(groups.len(), 1);
    assert!(groups.contains_key("1"));

    let group = &groups["1"];
    assert_eq!(group.id, "1");
    assert_eq!(group.name, "周期按键");
    assert_eq!(group.hotkey, "F1");
    assert_eq!(group.mode, "periodic");
    assert!(!group.active);

    let ipc_sender = Arc::new(MockIpcSender::new());
    let groups_map: HashMap<String, SkillGroup> = groups.into_iter().collect();
    let mut mgr = SkillManager::new(groups_map, ipc_sender);

    mgr.activate("1").unwrap();
    assert!(mgr.get_group("1").unwrap().active);
    assert_eq!(mgr.get_hotkey_group("F1"), Some("1"));

    let cmd = SkillManager::build_toggle_command(mgr.get_group("1").unwrap());
    match cmd {
        IpcCommand::ToggleGroup {
            group_id, active, ..
        } => {
            assert_eq!(group_id, "1");
            assert!(active);
        }
        _ => panic!("Expected ToggleGroup"),
    }
}

#[test]
fn test_skill_group_from_config_to_ipc_command() {
    let config = make_test_config();
    let groups = AppState::build_groups_from_config(&config);
    let group = &groups["1"];

    let cmd = SkillManager::build_toggle_command(group);
    let msg = IpcMessage::command(1, &cmd);

    assert_eq!(msg.r#type, "command");
    assert_eq!(msg.action.as_deref(), Some("toggle_group"));

    let json = serde_json::to_string(&msg).unwrap();
    let decoded: IpcMessage = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.action.as_deref(), Some("toggle_group"));
    assert!(decoded.data.is_some());
}

#[test]
fn test_full_config_lifecycle() {
    let dir = std::env::temp_dir().join("asd_cross_crate_lifecycle");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("config.json");
    let config = make_test_config();

    ConfigRepository::save_to_path(&config, &path).unwrap();

    let loaded = ConfigRepository::load_from_path(&path).unwrap();
    assert_eq!(loaded.control_hotkeys.emergency, "F10");

    let validation = ConfigValidator::validate(&loaded.group_settings);
    assert!(validation.is_valid(), "加载的配置应通过验证");

    let ipc_sender = Arc::new(MockIpcSender::new());
    let watchdog = Arc::new(MockProcessWatcher);
    let event_emitter = Arc::new(MockEventEmitter::new());
    let state = Arc::new(AppState::new(loaded, ipc_sender, watchdog, event_emitter));
    state.set_config_path(path);

    let groups = state.read_groups().unwrap();
    assert_eq!(groups.len(), 1);

    state.set_group_active("1", true).unwrap();
    let group = state.get_group("1").unwrap();
    assert!(group.active);

    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
        mode: Some("periodic".to_string()),
        key_press_duration: Some(10),
        hold_keys: None,
        hold_mode: None,
        mode_data: None,
    };
    let result = state.send_ipc_command(&cmd);
    assert!(result.is_ok());

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
#[allow(deprecated)]
fn test_config_validation_then_save_reload() {
    let dir = std::env::temp_dir().join("asd_cross_crate_validate_save");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let path = dir.join("config.json");
    let config = make_test_config();

    let validation = ConfigValidator::validate(&config.group_settings);
    assert!(validation.is_valid());

    ConfigRepository::save_to_file(&config, &path).unwrap();

    let loaded = ConfigRepository::load_from_file(&path);
    let revalidation = ConfigValidator::validate(&loaded.group_settings);
    assert!(revalidation.is_valid());

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_ipc_error_propagation_to_app_error() {
    let ipc_err = asd_ipc_protocol::IpcError::ConnectionClosed;
    let app_err: AppError = ipc_err.into();
    assert!(matches!(app_err, AppError::Ipc(_)));

    let ipc_err = asd_ipc_protocol::IpcError::Timeout;
    let app_err: AppError = ipc_err.into();
    assert!(matches!(app_err, AppError::Ipc(_)));
    assert!(format!("{app_err}").contains("超时"));
}

#[test]
fn test_skill_group_serialization_across_crates() {
    let config = make_test_config();
    let groups = AppState::build_groups_from_config(&config);
    let group = &groups["1"];

    let json = serde_json::to_string(group).unwrap();
    let decoded: SkillGroup = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded.id, "1");
    assert_eq!(decoded.name, "周期按键");
    assert_eq!(decoded.hotkey, "F1");
    assert_eq!(decoded.mode, "periodic");
    assert_eq!(decoded.key_press_duration, 10);
}

#[test]
fn test_validation_result_cross_crate_serialization() {
    let mut result = ValidationResult::new();
    result.add_error("1", "hotkey", "不能为空");
    result.add_warning("测试警告");

    let json = serde_json::to_string(&result).unwrap();
    let decoded: ValidationResult = serde_json::from_str(&json).unwrap();

    assert!(!decoded.valid);
    assert_eq!(decoded.errors.len(), 1);
    assert_eq!(decoded.warnings.len(), 1);
    assert_eq!(decoded.errors[0].group_id, "1");
    assert_eq!(decoded.errors[0].field, "hotkey");
}
