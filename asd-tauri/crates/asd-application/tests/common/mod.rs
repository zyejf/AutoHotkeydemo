use asd_application::state::AppState;
use asd_domain::config::*;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use std::sync::{Arc, Mutex};

pub struct MockIpcSender;

impl IpcSender for MockIpcSender {
    fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
        Ok(1)
    }
    fn send_and_wait(
        &self,
        _cmd: IpcCommand,
        _timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        Ok(IpcMessage::response(
            1,
            0,
            "ok",
            Some(serde_json::json!({
                "keys": ["1", "2"],
                "mode": "periodic",
                "intervals": [50, 100],
                "delays": []
            })),
        ))
    }
    fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
        Ok(())
    }
}

pub struct RecordingIpcSender {
    commands: Mutex<Vec<IpcCommand>>,
}

impl RecordingIpcSender {
    pub fn new() -> Self {
        Self {
            commands: Mutex::new(Vec::new()),
        }
    }
    pub fn sent_commands(&self) -> Vec<IpcCommand> {
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

pub struct MockEventEmitter;

impl EventEmitter for MockEventEmitter {
    fn emit(&self, _event: &str, _payload: serde_json::Value) -> bool {
        true
    }
}

pub struct MockProcessWatcher;

impl ProcessWatcher for MockProcessWatcher {
    fn state(&self) -> WatchdogStateEnum {
        WatchdogStateEnum::Idle
    }
    fn restart_count(&self) -> u32 {
        0
    }
}

pub fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
            name: Some("test".to_string()),
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
            key_press_duration: Some(10),
            name: Some("test2".to_string()),
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

pub fn make_test_state() -> Arc<AppState> {
    Arc::new(AppState::new(
        make_test_config(),
        Arc::new(MockIpcSender),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter),
    ))
}

pub fn make_test_state_with_recording_sender() -> (Arc<AppState>, Arc<RecordingIpcSender>) {
    let sender = Arc::new(RecordingIpcSender::new());
    let state = Arc::new(AppState::new(
        make_test_config(),
        sender.clone(),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter),
    ));
    (state, sender)
}

pub fn make_test_state_with_path() -> (Arc<AppState>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let config_path = dir.path().join("config.json");
    let state = make_test_state();
    state.set_config_path(config_path);
    (state, dir)
}
