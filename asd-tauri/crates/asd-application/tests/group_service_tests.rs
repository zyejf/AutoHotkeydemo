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
    // toggle_group sends RegisterHotkey (try_send) + ToggleGroup (send)
    assert_eq!(commands.len(), 2);
    match &commands[0] {
        IpcCommand::RegisterHotkey { hotkey, group_id } => {
            assert_eq!(group_id, "1");
            assert!(!hotkey.is_empty());
        }
        _ => panic!("Expected RegisterHotkey IPC command"),
    }
    match &commands[1] {
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
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), AppError::GroupNotFound(_)));
}

#[test]
fn test_toggle_all() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_all(&state, true);
    assert!(result.is_ok());
    let toggle_result = result.unwrap();
    assert!(toggle_result.succeeded.contains(&"1".to_string()));
    assert!(toggle_result.succeeded.contains(&"2".to_string()));
    assert!(toggle_result.state_errors.is_empty());
    assert!(toggle_result.ipc_rolled_back.is_empty());
    assert!(toggle_result.not_found.is_empty());
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
    let toggle_result = result.unwrap();
    assert!(toggle_result.succeeded.contains(&"1".to_string()));
    assert!(toggle_result.state_errors.is_empty());
    assert!(toggle_result.ipc_rolled_back.is_empty());
    assert!(toggle_result.not_found.is_empty());
    let group1 = state.get_group("1").unwrap();
    assert!(group1.active);
    let group2 = state.get_group("2").unwrap();
    assert!(!group2.active);
}

#[test]
fn test_batch_toggle_groups_not_found() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::batch_toggle_groups(
        &state,
        &["1".to_string(), "999".to_string(), "888".to_string()],
        true,
    );
    assert!(result.is_ok());
    let toggle_result = result.unwrap();
    assert!(toggle_result.succeeded.contains(&"1".to_string()));
    assert!(toggle_result.not_found.contains(&"999".to_string()));
    assert!(toggle_result.not_found.contains(&"888".to_string()));
    assert_eq!(toggle_result.not_found.len(), 2);
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
    let reorder_result = result.unwrap();
    assert_eq!(reorder_result.reordered_count, 2);
    assert!(reorder_result.appended_groups.is_empty());
    let groups = state.read_groups().unwrap();
    let keys: Vec<&String> = groups.keys().collect();
    assert_eq!(keys[0], &"2".to_string());
    assert_eq!(keys[1], &"1".to_string());
}

#[test]
fn test_reorder_groups_with_appended() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::reorder_groups(&state, &["1".to_string()]);
    assert!(result.is_ok());
    let reorder_result = result.unwrap();
    assert_eq!(reorder_result.reordered_count, 1);
    assert!(reorder_result.appended_groups.contains(&"2".to_string()));
    let groups = state.read_groups().unwrap();
    let keys: Vec<&String> = groups.keys().collect();
    assert_eq!(keys[0], &"1".to_string());
    assert_eq!(keys[1], &"2".to_string());
}

#[test]
fn test_register_hotkey() {
    let (state, ipc) = make_test_state_with_recording_sender();
    // 先激活分组，使热键注册发送 IPC 命令
    group_service::toggle_group(&state, "1").unwrap();
    ipc.sent_commands(); // 清空 toggle 产生的命令
    let result = group_service::register_hotkey(&state, "F3", "1");
    assert!(result.is_ok());
    let commands = ipc.sent_commands();
    // 活跃分组注册新热键：先注销旧热键，再注册新热键
    assert!(commands.len() >= 1);
    assert!(commands.iter().any(|c| matches!(
        c,
        IpcCommand::RegisterHotkey { hotkey, group_id } if hotkey == "F3" && group_id == "1"
    )));
}

#[test]
fn test_register_hotkey_duplicate() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    // 激活两个分组，使热键注册经过 active_hotkeys 重复检查
    group_service::toggle_group(&state, "1").unwrap();
    group_service::toggle_group(&state, "2").unwrap();
    // 尝试将分组 2 的热键改为分组 1 已注册的热键
    let group1_hotkey = state.get_group("1").unwrap().hotkey;
    let result = group_service::register_hotkey(&state, &group1_hotkey, "2");
    assert!(matches!(result, Err(AppError::Validation(_))));
}

#[test]
fn test_unregister_hotkey() {
    let (state, ipc) = make_test_state_with_recording_sender();
    // 先激活分组，使热键注册到 active_hotkeys
    group_service::toggle_group(&state, "1").unwrap();
    let hotkey = state.get_group("1").unwrap().hotkey;
    ipc.sent_commands(); // 清空 toggle 产生的命令
    let result = group_service::unregister_hotkey(&state, &hotkey);
    assert!(result.is_ok());
    let commands = ipc.sent_commands();
    assert!(commands.iter().any(|c| matches!(
        c,
        IpcCommand::UnregisterHotkey { hotkey: h } if h == &hotkey
    )));
}

#[test]
fn test_unregister_hotkey_not_registered() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::unregister_hotkey(&state, "F99");
    assert!(matches!(result, Err(AppError::Validation(_))));
}
