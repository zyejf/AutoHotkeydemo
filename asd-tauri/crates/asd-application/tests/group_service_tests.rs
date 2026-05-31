use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::*;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use std::sync::Arc;

struct RecordingIpcSender {
    commands: std::sync::Mutex<Vec<IpcCommand>>,
}

impl RecordingIpcSender {
    fn new() -> Self {
        Self {
            commands: std::sync::Mutex::new(Vec::new()),
        }
    }

    fn sent_commands(&self) -> Vec<IpcCommand> {
        self.commands.lock().unwrap().clone()
    }
}

impl IpcSender for RecordingIpcSender {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        self.commands.lock().unwrap().push(cmd);
        Ok(1)
    }

    fn send_and_wait(
        &self,
        cmd: IpcCommand,
        _timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        self.commands.lock().unwrap().push(cmd);
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
            name: Some("测试组1".to_string()),
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
    group_settings.insert(
        "2".to_string(),
        GroupConfig {
            hotkey: "F2".to_string(),
            key_press_duration: None,
            name: Some("测试组2".to_string()),
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

fn make_test_state_with_recording() -> (Arc<AppState>, Arc<RecordingIpcSender>) {
    let config = make_test_config();
    let ipc_sender = Arc::new(RecordingIpcSender::new());
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

#[test]
fn test_toggle_group() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::toggle_group(&state, "1");
    assert!(result.is_ok());
    let status = result.unwrap();
    assert_eq!(status.id, "1");
    assert!(status.active);
}

#[test]
fn test_toggle_group_not_found() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::toggle_group(&state, "999");
    assert!(matches!(result, Err(AppError::GroupNotFound(_))));
}

#[test]
fn test_toggle_group_sends_ipc() {
    let (state, ipc) = make_test_state_with_recording();
    asd_application::group_service::toggle_group(&state, "1").unwrap();
    let commands = ipc.sent_commands();
    assert_eq!(commands.len(), 1);
    match &commands[0] {
        IpcCommand::ToggleGroup {
            group_id, active, ..
        } => {
            assert_eq!(group_id, "1");
            assert!(*active);
        }
        _ => panic!("Expected ToggleGroup IPC command"),
    }
}

#[test]
fn test_toggle_group_twice() {
    let (state, _ipc) = make_test_state_with_recording();
    let status1 = asd_application::group_service::toggle_group(&state, "1").unwrap();
    assert!(status1.active);
    let status2 = asd_application::group_service::toggle_group(&state, "1").unwrap();
    assert!(!status2.active);
}

#[test]
fn test_delete_group() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::delete_group(&state, "1");
    assert!(result.is_ok());
    let group = state.get_group("1");
    assert!(group.is_none());
}

#[test]
fn test_delete_group_not_found() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::delete_group(&state, "999");
    assert!(result.is_ok());
}

#[test]
fn test_toggle_all() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::toggle_all(&state, true);
    assert!(result.is_ok());
    let group1 = state.get_group("1").unwrap();
    let group2 = state.get_group("2").unwrap();
    assert!(group1.active);
    assert!(group2.active);
}

#[test]
fn test_batch_toggle_groups() {
    let (state, _ipc) = make_test_state_with_recording();
    let result =
        asd_application::group_service::batch_toggle_groups(&state, &["1".to_string()], true);
    assert!(result.is_ok());
    let group1 = state.get_group("1").unwrap();
    assert!(group1.active);
    let group2 = state.get_group("2").unwrap();
    assert!(!group2.active);
}

#[test]
fn test_batch_delete_groups() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::batch_delete_groups(&state, &["1".to_string()]);
    assert!(result.is_ok());
    assert!(state.get_group("1").is_none());
    assert!(state.get_group("2").is_some());
}

#[test]
fn test_reorder_groups() {
    let (state, _ipc) = make_test_state_with_recording();
    let result =
        asd_application::group_service::reorder_groups(&state, &["2".to_string(), "1".to_string()]);
    assert!(result.is_ok());
    let groups = state.read_groups().unwrap();
    let keys: Vec<&String> = groups.keys().collect();
    assert_eq!(keys[0], &"2".to_string());
    assert_eq!(keys[1], &"1".to_string());
}

#[test]
fn test_register_hotkey() {
    let (state, ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::register_hotkey(&state, "F3", "1");
    assert!(result.is_ok());
    let commands = ipc.sent_commands();
    assert_eq!(commands.len(), 1);
    match &commands[0] {
        IpcCommand::RegisterHotkey { hotkey, group_id } => {
            assert_eq!(hotkey, "F3");
            assert_eq!(group_id, "1");
        }
        _ => panic!("Expected RegisterHotkey IPC command"),
    }
}

#[test]
fn test_register_hotkey_duplicate() {
    let (state, _ipc) = make_test_state_with_recording();
    asd_application::group_service::register_hotkey(&state, "F3", "1").unwrap();
    let result = asd_application::group_service::register_hotkey(&state, "F3", "2");
    assert!(matches!(result, Err(AppError::Validation(_))));
}

#[test]
fn test_unregister_hotkey() {
    let (state, ipc) = make_test_state_with_recording();
    asd_application::group_service::register_hotkey(&state, "F3", "1").unwrap();
    let result = asd_application::group_service::unregister_hotkey(&state, "F3");
    assert!(result.is_ok());
    let commands = ipc.sent_commands();
    match &commands[1] {
        IpcCommand::UnregisterHotkey { hotkey } => {
            assert_eq!(hotkey, "F3");
        }
        _ => panic!("Expected UnregisterHotkey IPC command"),
    }
}

#[test]
fn test_unregister_hotkey_not_registered() {
    let (state, _ipc) = make_test_state_with_recording();
    let result = asd_application::group_service::unregister_hotkey(&state, "F99");
    assert!(matches!(result, Err(AppError::Validation(_))));
}
