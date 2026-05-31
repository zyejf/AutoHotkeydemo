mod common;

use asd_application::error::AppError;
use asd_application::group_service;
use asd_ipc_protocol::IpcCommand;
use common::*;

#[test]
fn test_toggle_group() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_group(&state, "1");
    assert!(result.is_ok());
    let status = result.unwrap();
    assert_eq!(status.id, "1");
    assert!(status.active);
}

#[test]
fn test_toggle_group_not_found() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_group(&state, "999");
    assert!(matches!(result, Err(AppError::GroupNotFound(_))));
}

#[test]
fn test_toggle_group_sends_ipc() {
    let (state, ipc) = make_test_state_with_recording_sender();
    group_service::toggle_group(&state, "1").unwrap();
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
    let (state, _ipc) = make_test_state_with_recording_sender();
    let status1 = group_service::toggle_group(&state, "1").unwrap();
    assert!(status1.active);
    let status2 = group_service::toggle_group(&state, "1").unwrap();
    assert!(!status2.active);
}

#[test]
fn test_delete_group() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::delete_group(&state, "1");
    assert!(result.is_ok());
    let group = state.get_group("1");
    assert!(group.is_none());
}

#[test]
fn test_delete_group_not_found() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::delete_group(&state, "999");
    assert!(result.is_ok());
}

#[test]
fn test_toggle_all() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_all(&state, true);
    assert!(result.is_ok());
    let group1 = state.get_group("1").unwrap();
    let group2 = state.get_group("2").unwrap();
    assert!(group1.active);
    assert!(group2.active);
}

#[test]
fn test_batch_toggle_groups() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::batch_toggle_groups(&state, &["1".to_string()], true);
    assert!(result.is_ok());
    let group1 = state.get_group("1").unwrap();
    assert!(group1.active);
    let group2 = state.get_group("2").unwrap();
    assert!(!group2.active);
}

#[test]
fn test_batch_delete_groups() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::batch_delete_groups(&state, &["1".to_string()]);
    assert!(result.is_ok());
    assert!(state.get_group("1").is_none());
    assert!(state.get_group("2").is_some());
}

#[test]
fn test_reorder_groups() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::reorder_groups(&state, &["2".to_string(), "1".to_string()]);
    assert!(result.is_ok());
    let groups = state.read_groups().unwrap();
    let keys: Vec<&String> = groups.keys().collect();
    assert_eq!(keys[0], &"2".to_string());
    assert_eq!(keys[1], &"1".to_string());
}

#[test]
fn test_register_hotkey() {
    let (state, ipc) = make_test_state_with_recording_sender();
    let result = group_service::register_hotkey(&state, "F3", "1");
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
    let (state, _ipc) = make_test_state_with_recording_sender();
    group_service::register_hotkey(&state, "F3", "1").unwrap();
    let result = group_service::register_hotkey(&state, "F3", "2");
    assert!(matches!(result, Err(AppError::Validation(_))));
}

#[test]
fn test_unregister_hotkey() {
    let (state, ipc) = make_test_state_with_recording_sender();
    group_service::register_hotkey(&state, "F3", "1").unwrap();
    let result = group_service::unregister_hotkey(&state, "F3");
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
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::unregister_hotkey(&state, "F99");
    assert!(matches!(result, Err(AppError::Validation(_))));
}
