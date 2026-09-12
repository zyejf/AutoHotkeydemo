use asd_ipc_protocol::*;

#[test]
fn test_ipc_command_toggle_group_roundtrip() {
    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
        mode: Some("periodic".to_string()),
        key_press_duration: Some(10),
        hold_keys: Some(vec!["Shift".to_string()]),
        hold_mode: Some("continuous".to_string()),
        mode_data: Some(serde_json::json!({"keys": ["1"], "intervals": [50]})),
    };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
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
            assert!(active);
            assert_eq!(mode, Some("periodic".to_string()));
            assert_eq!(key_press_duration, Some(10));
            assert_eq!(hold_keys, Some(vec!["Shift".to_string()]));
            assert_eq!(hold_mode, Some("continuous".to_string()));
            assert!(mode_data.is_some());
        }
        _ => panic!("Expected ToggleGroup"),
    }
}

#[test]
fn test_ipc_command_register_hotkey_roundtrip() {
    let cmd = IpcCommand::RegisterHotkey {
        hotkey: "F1".to_string(),
        group_id: "1".to_string(),
    };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
        IpcCommand::RegisterHotkey { hotkey, group_id } => {
            assert_eq!(hotkey, "F1");
            assert_eq!(group_id, "1");
        }
        _ => panic!("Expected RegisterHotkey"),
    }
}

#[test]
fn test_ipc_command_unregister_hotkey_roundtrip() {
    let cmd = IpcCommand::UnregisterHotkey {
        hotkey: "F2".to_string(),
    };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
        IpcCommand::UnregisterHotkey { hotkey } => {
            assert_eq!(hotkey, "F2");
        }
        _ => panic!("Expected UnregisterHotkey"),
    }
}

#[test]
fn test_ipc_command_start_recording_roundtrip() {
    let cmd = IpcCommand::StartRecording {
        group_id: "3".to_string(),
        mode: "periodic".to_string(),
    };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
        IpcCommand::StartRecording { group_id, mode } => {
            assert_eq!(group_id, "3");
            assert_eq!(mode, "periodic");
        }
        _ => panic!("Expected StartRecording"),
    }
}

#[test]
fn test_ipc_command_stop_recording_roundtrip() {
    let cmd = IpcCommand::StopRecording;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::StopRecording));
}

#[test]
fn test_ipc_command_pause_recording_roundtrip() {
    let cmd = IpcCommand::PauseRecording;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::PauseRecording));
}

#[test]
fn test_ipc_command_resume_recording_roundtrip() {
    let cmd = IpcCommand::ResumeRecording;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::ResumeRecording));
}

#[test]
fn test_ipc_command_emergency_release_roundtrip() {
    let cmd = IpcCommand::EmergencyRelease;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::EmergencyRelease));
}

#[test]
fn test_ipc_command_ping_roundtrip() {
    let cmd = IpcCommand::Ping;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::Ping));
}

#[test]
fn test_ipc_command_shutdown_roundtrip() {
    let cmd = IpcCommand::Shutdown;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::Shutdown));
}

#[test]
fn test_ipc_command_hold_mode_toggle_roundtrip() {
    let cmd = IpcCommand::HoldModeToggle { enabled: true };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
        IpcCommand::HoldModeToggle { enabled } => assert!(enabled),
        _ => panic!("Expected HoldModeToggle"),
    }
}

#[test]
fn test_ipc_command_start_validation_roundtrip() {
    let cmd = IpcCommand::StartValidation {
        group_id: "5".to_string(),
    };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
        IpcCommand::StartValidation { group_id } => assert_eq!(group_id, "5"),
        _ => panic!("Expected StartValidation"),
    }
}

#[test]
fn test_ipc_command_stop_validation_roundtrip() {
    let cmd = IpcCommand::StopValidation;
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    assert!(matches!(decoded, IpcCommand::StopValidation));
}

#[test]
fn test_ipc_message_command_to_response_flow() {
    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
        mode: None,
        key_press_duration: None,
        hold_keys: None,
        hold_mode: None,
        mode_data: None,
    };
    let request = IpcMessage::command(1, &cmd);
    assert_eq!(request.r#type, "command");
    assert_eq!(request.seq, 1);
    assert_eq!(request.action.as_deref(), Some("toggle_group"));

    let response = IpcMessage::response(
        2,
        request.seq,
        "ok",
        Some(serde_json::json!({"result": "success"})),
    );
    assert_eq!(response.r#type, "response");
    assert_eq!(response.ack_seq, Some(1));
    assert_eq!(response.status.as_deref(), Some("ok"));
}

#[test]
fn test_ipc_message_ping_pong_flow() {
    let ping = IpcMessage::ping(1);
    assert_eq!(ping.r#type, "ping");
    assert_eq!(ping.seq, 1);

    let pong = IpcMessage::pong(2, 1);
    assert_eq!(pong.r#type, "pong");
    assert_eq!(pong.ack_seq, Some(1));
}

#[test]
fn test_ipc_message_execute_result_flow() {
    let execute = IpcMessage::execute(1, vec!["1".to_string(), "2".to_string()], 50);
    assert_eq!(execute.r#type, "execute");
    assert_eq!(execute.action.as_deref(), Some("keypress"));

    let result = IpcMessage::result(2, 1, serde_json::json!({"status": "ok"}));
    assert_eq!(result.r#type, "result");
    assert_eq!(result.ack_seq, Some(1));
}

#[test]
fn test_ipc_message_shutdown_flow() {
    let shutdown = IpcMessage::shutdown(99);
    assert_eq!(shutdown.r#type, "shutdown");
    assert_eq!(shutdown.action.as_deref(), Some("shutdown"));
}

#[test]
fn test_ipc_message_hotkey_event_flow() {
    let event = IpcMessage::hotkey_event(1, "F1");
    assert_eq!(event.r#type, "hotkey");
    assert_eq!(event.action.as_deref(), Some("hotkey_event"));
    assert_eq!(event.keys.as_deref(), Some(&["F1".to_string()][..]));
}

#[test]
fn test_ipc_message_heartbeat_flow() {
    let hb = IpcMessage::heartbeat(50);
    assert_eq!(hb.r#type, "heartbeat");
    assert_eq!(hb.seq, 50);
    assert!(hb.action.is_none());
}

#[test]
fn test_ipc_message_auth_flow() {
    let auth = IpcMessage::auth("ASD_IPC_AUTH_V1");
    assert_eq!(auth.r#type, "auth");
    assert_eq!(auth.data.as_ref().unwrap()["token"], "ASD_IPC_AUTH_V1");
}

#[test]
fn test_ipc_message_serialization_roundtrip_full() {
    let msg = IpcMessage {
        id: Some("test-123".to_string()),
        r#type: "command".to_string(),
        seq: 42,
        ack_seq: Some(10),
        action: Some("keypress".to_string()),
        keys: Some(vec!["1".to_string(), "2".to_string()]),
        delay: Some(50),
        status: None,
        data: Some(serde_json::json!({"extra": true})),
    };
    let json = serde_json::to_string(&msg).unwrap();
    let decoded: IpcMessage = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.id, Some("test-123".to_string()));
    assert_eq!(decoded.r#type, "command");
    assert_eq!(decoded.seq, 42);
    assert_eq!(decoded.ack_seq, Some(10));
    assert_eq!(decoded.action, Some("keypress".to_string()));
    assert_eq!(decoded.keys, Some(vec!["1".to_string(), "2".to_string()]));
    assert_eq!(decoded.delay, Some(50));
}

#[test]
fn test_hotkey_merger_push_and_flush() {
    let mut merger = HotkeyMerger::new(50);
    merger.push(IpcMessage::hotkey_event(1, "F1"));
    merger.push(IpcMessage::hotkey_event(2, "F2"));
    merger.push(IpcMessage::hotkey_event(3, "F1"));

    assert!(!merger.should_flush());

    std::thread::sleep(std::time::Duration::from_millis(60));
    assert!(merger.should_flush());

    let flushed = merger.flush();
    assert_eq!(flushed.len(), 2);

    let flushed_again = merger.flush();
    assert!(flushed_again.is_empty());
}

#[test]
fn test_hotkey_merger_same_key_overwrite() {
    let mut merger = HotkeyMerger::new(50);
    merger.push(IpcMessage::hotkey_event(1, "F1"));
    merger.push(IpcMessage::hotkey_event(2, "F1"));
    merger.push(IpcMessage::hotkey_event(3, "F1"));

    std::thread::sleep(std::time::Duration::from_millis(60));
    let flushed = merger.flush();
    assert_eq!(flushed.len(), 1);
    assert_eq!(flushed[0].seq, 3);
}

#[test]
fn test_hotkey_merger_should_flush_empty_buffer() {
    let merger = HotkeyMerger::new(10);
    assert!(!merger.should_flush());
}

#[test]
fn test_hotkey_merger_flush_resets_timer() {
    let mut merger = HotkeyMerger::new(50);
    merger.push(IpcMessage::hotkey_event(1, "F1"));

    std::thread::sleep(std::time::Duration::from_millis(60));
    assert!(merger.should_flush());

    merger.flush();
    merger.push(IpcMessage::hotkey_event(2, "F2"));
    assert!(!merger.should_flush());
}

#[test]
fn test_hotkey_merger_default_window() {
    let merger = HotkeyMerger::default();
    assert_eq!(merger.merge_window(), std::time::Duration::from_millis(100));
}

#[test]
fn test_ipc_error_display_messages() {
    assert_eq!(format!("{}", IpcError::ConnectionClosed), "连接已关闭");
    assert_eq!(format!("{}", IpcError::EmptyMessage), "收到空行");
    assert_eq!(format!("{}", IpcError::Timeout), "等待响应超时");
    assert_eq!(format!("{}", IpcError::ChannelClosed), "通道已关闭");

    let size_err = IpcError::MessageTooLarge(100, 64);
    assert!(format!("{size_err}").contains("100"));

    let json_err = IpcError::JsonError("parse error".to_string());
    assert!(format!("{json_err}").contains("parse error"));

    let io_err = IpcError::IoError("io failed".to_string());
    assert!(format!("{io_err}").contains("io failed"));

    let pipe_err = IpcError::PipeBroken("broken".to_string());
    assert!(format!("{pipe_err}").contains("broken"));

    let name_err = IpcError::NameError("name error".to_string());
    assert!(format!("{name_err}").contains("name error"));

    let auth_err = IpcError::AuthFailed("token mismatch".to_string());
    assert!(format!("{auth_err}").contains("认证失败"));
}

#[test]
fn test_ipc_error_from_broken_pipe() {
    let err = std::io::Error::new(std::io::ErrorKind::BrokenPipe, "broken pipe");
    let ipc_err = IpcError::from(err);
    assert!(matches!(ipc_err, IpcError::PipeBroken(_)));
}

#[test]
fn test_ipc_error_from_other_io() {
    let err = std::io::Error::other("some error");
    let ipc_err = IpcError::from(err);
    assert!(matches!(ipc_err, IpcError::IoError(_)));
}

#[test]
fn test_ipc_error_from_json() {
    let result: Result<serde_json::Value, _> = serde_json::from_str("{invalid}");
    if let Err(e) = result {
        let ipc_err = IpcError::from(e);
        assert!(matches!(ipc_err, IpcError::JsonError(_)));
    }
}

#[test]
fn test_ipc_command_and_message_combined() {
    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
        mode: Some("periodic".to_string()),
        key_press_duration: Some(10),
        hold_keys: Some(vec!["Shift".to_string()]),
        hold_mode: Some("continuous".to_string()),
        mode_data: Some(serde_json::json!({"keys": ["1"], "intervals": [50]})),
    };
    let msg = IpcMessage::command(42, &cmd);

    let json = serde_json::to_string(&msg).unwrap();
    let decoded: IpcMessage = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded.r#type, "command");
    assert_eq!(decoded.seq, 42);
    assert_eq!(decoded.action.as_deref(), Some("toggle_group"));
    assert!(decoded.data.is_some());
}

#[test]
fn test_ipc_message_minimal_serialization() {
    let msg = IpcMessage {
        id: None,
        r#type: "ping".to_string(),
        seq: 1,
        ack_seq: None,
        action: None,
        keys: None,
        delay: None,
        status: None,
        data: None,
    };
    let json = serde_json::to_string(&msg).unwrap();
    assert!(!json.contains("id"));
    assert!(!json.contains("ack_seq"));
    assert!(!json.contains("action"));
    assert!(!json.contains("keys"));
    assert!(!json.contains("delay"));
    assert!(!json.contains("status"));
    assert!(!json.contains("data"));
}

#[test]
fn test_ipc_command_all_variants_roundtrip() {
    let cmds: Vec<IpcCommand> = vec![
        IpcCommand::ToggleGroup {
            group_id: "1".to_string(),
            active: false,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        },
        IpcCommand::RegisterHotkey {
            hotkey: "F2".to_string(),
            group_id: "2".to_string(),
        },
        IpcCommand::UnregisterHotkey {
            hotkey: "F3".to_string(),
        },
        IpcCommand::StartRecording {
            group_id: "3".to_string(),
            mode: "periodic".to_string(),
        },
        IpcCommand::StopRecording,
        IpcCommand::PauseRecording,
        IpcCommand::ResumeRecording,
        IpcCommand::EmergencyRelease,
        IpcCommand::Ping,
        IpcCommand::Shutdown,
        IpcCommand::HoldModeToggle { enabled: true },
        IpcCommand::StartValidation {
            group_id: "5".to_string(),
        },
        IpcCommand::StopValidation,
    ];

    for cmd in &cmds {
        let json = serde_json::to_string(cmd).unwrap();
        let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
        let re_encoded = serde_json::to_string(&decoded).unwrap();
        assert_eq!(json, re_encoded);
    }
}
