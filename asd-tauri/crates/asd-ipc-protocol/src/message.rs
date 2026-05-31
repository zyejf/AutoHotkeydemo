use crate::command::IpcCommand;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcMessage {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub id: Option<String>,
    pub r#type: String,
    #[serde(default)]
    pub seq: u64,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub ack_seq: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub keys: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub delay: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub data: Option<serde_json::Value>,
}

impl IpcMessage {
    /// 从 IpcCommand 构建 IPC 命令消息。
    ///
    /// 通过 `serde_json::to_value` 序列化 `IpcCommand`，然后提取 `action` 和 `data` 字段，
    /// 确保序列化逻辑与 `IpcCommand` 的 serde 派生宏保持一致，无需手动维护两套实现。
    pub fn command(seq: u64, cmd: &IpcCommand) -> Self {
        let serialized = serde_json::to_value(cmd)
            .ok()
            .filter(|v| !v.is_null())
            .unwrap_or(serde_json::Value::Object(Default::default()));

        let action = serialized
            .get("action")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        let data = match serialized {
            serde_json::Value::Object(mut map) => {
                map.remove("action");
                if map.is_empty() {
                    None
                } else {
                    Some(serde_json::Value::Object(map))
                }
            }
            _ => None,
        };

        Self {
            id: None,
            r#type: "command".to_string(),
            seq,
            ack_seq: None,
            action: Some(action),
            keys: None,
            delay: None,
            status: None,
            data,
        }
    }

    pub fn response(seq: u64, ack_seq: u64, status: &str, data: Option<serde_json::Value>) -> Self {
        Self {
            id: None,
            r#type: "response".to_string(),
            seq,
            ack_seq: Some(ack_seq),
            action: None,
            keys: None,
            delay: None,
            status: Some(status.to_string()),
            data,
        }
    }

    pub fn ping(seq: u64) -> Self {
        Self {
            id: None,
            r#type: "ping".to_string(),
            seq,
            ack_seq: None,
            action: None,
            keys: None,
            delay: None,
            status: None,
            data: None,
        }
    }

    pub fn pong(seq: u64, ack_seq: u64) -> Self {
        Self {
            id: None,
            r#type: "pong".to_string(),
            seq,
            ack_seq: Some(ack_seq),
            action: None,
            keys: None,
            delay: None,
            status: None,
            data: None,
        }
    }

    pub fn execute(seq: u64, keys: Vec<String>, delay: u64) -> Self {
        Self {
            id: None,
            r#type: "execute".to_string(),
            seq,
            ack_seq: None,
            action: Some("keypress".to_string()),
            keys: Some(keys),
            delay: Some(delay),
            status: None,
            data: None,
        }
    }

    pub fn result(seq: u64, ack_seq: u64, data: serde_json::Value) -> Self {
        Self {
            id: None,
            r#type: "result".to_string(),
            seq,
            ack_seq: Some(ack_seq),
            action: None,
            keys: None,
            delay: None,
            status: None,
            data: Some(data),
        }
    }

    pub fn shutdown(seq: u64) -> Self {
        Self {
            id: None,
            r#type: "shutdown".to_string(),
            seq,
            ack_seq: None,
            action: Some("shutdown".to_string()),
            keys: None,
            delay: None,
            status: None,
            data: None,
        }
    }

    pub fn hotkey_event(seq: u64, hotkey: &str) -> Self {
        Self {
            id: None,
            r#type: "hotkey".to_string(),
            seq,
            ack_seq: None,
            action: Some("hotkey_event".to_string()),
            keys: Some(vec![hotkey.to_string()]),
            delay: None,
            status: None,
            data: None,
        }
    }

    pub fn heartbeat(seq: u64) -> Self {
        Self {
            id: None,
            r#type: "heartbeat".to_string(),
            seq,
            ack_seq: None,
            action: None,
            keys: None,
            delay: None,
            status: None,
            data: None,
        }
    }

    pub fn auth(token: &str) -> Self {
        Self {
            id: None,
            r#type: "auth".to_string(),
            seq: 0,
            ack_seq: None,
            action: None,
            keys: None,
            delay: None,
            status: None,
            data: Some(serde_json::json!({"token": token})),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::IpcCommand;

    #[test]
    fn test_ipc_message_command() {
        let cmd = IpcCommand::ToggleGroup {
            group_id: "1".to_string(),
            active: true,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        let msg = IpcMessage::command(42, &cmd);

        assert_eq!(msg.r#type, "command");
        assert_eq!(msg.seq, 42);
        assert_eq!(msg.action.as_deref(), Some("toggle_group"));
        assert!(msg.data.is_some());
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "1");
        assert_eq!(msg.data.as_ref().unwrap()["active"], true);
    }

    #[test]
    fn test_ipc_message_response() {
        let msg = IpcMessage::response(
            100,
            42,
            "ok",
            Some(serde_json::json!({"result": "success"})),
        );

        assert_eq!(msg.r#type, "response");
        assert_eq!(msg.seq, 100);
        assert_eq!(msg.ack_seq, Some(42));
        assert_eq!(msg.status.as_deref(), Some("ok"));
        assert!(msg.data.is_some());
    }

    #[test]
    fn test_ipc_message_serialization_roundtrip() {
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
        assert_eq!(decoded.status, None);
    }

    #[test]
    fn test_ipc_message_minimal() {
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
    fn test_ipc_message_ping_serialization_format() {
        let msg = IpcMessage::ping(42);
        let json = serde_json::to_string(&msg).unwrap();
        assert!(
            json.contains(r#""type":"ping""#),
            "ping message should contain type=ping, got: {json}"
        );
        assert!(
            json.contains(r#""seq":42"#),
            "ping message should contain seq, got: {json}"
        );
        assert!(
            !json.contains("action"),
            "ping message should not contain action, got: {json}"
        );
        assert!(
            !json.contains("ack_seq"),
            "ping message should not contain ack_seq, got: {json}"
        );
    }

    #[test]
    fn test_ipc_command_ping_produces_command_type_not_ping_type() {
        let cmd = IpcCommand::Ping;
        let msg = IpcMessage::command(1, &cmd);
        assert_eq!(
            msg.r#type, "command",
            "IpcCommand::Ping via command() should have type=command"
        );
        assert_eq!(msg.action.as_deref(), Some("ping"), "action should be ping");
    }

    #[test]
    fn test_ipc_message_shutdown_serialization_format() {
        let msg = IpcMessage::shutdown(99);
        let json = serde_json::to_string(&msg).unwrap();
        assert!(
            json.contains(r#""type":"shutdown""#),
            "shutdown message should contain type=shutdown, got: {json}"
        );
        assert!(
            json.contains(r#""seq":99"#),
            "shutdown message should contain seq, got: {json}"
        );
    }

    #[test]
    fn test_ipc_command_shutdown_produces_command_type_not_shutdown_type() {
        let cmd = IpcCommand::Shutdown;
        let msg = IpcMessage::command(1, &cmd);
        assert_eq!(
            msg.r#type, "command",
            "IpcCommand::Shutdown via command() should have type=command"
        );
        assert_eq!(
            msg.action.as_deref(),
            Some("shutdown"),
            "action should be shutdown"
        );
    }

    #[test]
    fn test_ipc_message_auth() {
        let msg = IpcMessage::auth("ASD_IPC_AUTH_V1");
        assert_eq!(msg.r#type, "auth");
        assert_eq!(msg.seq, 0);
        assert!(msg.data.is_some());
        assert_eq!(msg.data.as_ref().unwrap()["token"], "ASD_IPC_AUTH_V1");
    }

    #[test]
    fn test_ipc_message_auth_serialization_roundtrip() {
        let msg = IpcMessage::auth("ASD_IPC_AUTH_V1");
        let json = serde_json::to_string(&msg).unwrap();
        let decoded: IpcMessage = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.r#type, "auth");
        assert_eq!(decoded.data.as_ref().unwrap()["token"], "ASD_IPC_AUTH_V1");
    }

    #[test]
    fn test_ipc_message_command_toggle_group() {
        let cmd = IpcCommand::ToggleGroup {
            group_id: "1".to_string(),
            active: true,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        let msg = IpcMessage::command(42, &cmd);

        assert_eq!(msg.r#type, "command");
        assert_eq!(msg.seq, 42);
        assert_eq!(msg.action.as_deref(), Some("toggle_group"));
        assert!(msg.data.is_some());
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "1");
        assert_eq!(msg.data.as_ref().unwrap()["active"], true);
        assert!(msg.ack_seq.is_none());
    }

    #[test]
    fn test_ipc_message_command_register_hotkey() {
        let cmd = IpcCommand::RegisterHotkey {
            hotkey: "F1".to_string(),
            group_id: "1".to_string(),
        };
        let msg = IpcMessage::command(10, &cmd);

        assert_eq!(msg.action.as_deref(), Some("register_hotkey"));
        assert_eq!(msg.data.as_ref().unwrap()["hotkey"], "F1");
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "1");
    }

    #[test]
    fn test_ipc_message_command_unregister_hotkey() {
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey: "F2".to_string(),
        };
        let msg = IpcMessage::command(11, &cmd);

        assert_eq!(msg.action.as_deref(), Some("unregister_hotkey"));
        assert_eq!(msg.data.as_ref().unwrap()["hotkey"], "F2");
    }

    #[test]
    fn test_ipc_message_command_start_recording() {
        let cmd = IpcCommand::StartRecording {
            group_id: "3".to_string(),
            mode: "periodic".to_string(),
        };
        let msg = IpcMessage::command(12, &cmd);

        assert_eq!(msg.action.as_deref(), Some("start_recording"));
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "3");
        assert_eq!(msg.data.as_ref().unwrap()["mode"], "periodic");
    }

    #[test]
    fn test_ipc_message_command_no_data_variants() {
        let no_data_cmds = vec![
            IpcCommand::StopRecording,
            IpcCommand::EmergencyRelease,
            IpcCommand::Ping,
            IpcCommand::Shutdown,
        ];
        for (i, cmd) in no_data_cmds.into_iter().enumerate() {
            let msg = IpcMessage::command(i as u64, &cmd);
            assert!(msg.data.is_none(), "command {:?} should not have data", cmd);
        }
    }

    #[test]
    fn test_ipc_message_command_hold_mode_toggle() {
        let cmd = IpcCommand::HoldModeToggle { enabled: true };
        let msg = IpcMessage::command(20, &cmd);

        assert_eq!(msg.action.as_deref(), Some("hold_mode_toggle"));
        assert_eq!(msg.data.as_ref().unwrap()["enabled"], true);
    }

    #[test]
    fn test_ipc_message_response_no_data() {
        let msg = IpcMessage::response(100, 42, "error", None);
        assert!(msg.data.is_none());
    }

    #[test]
    fn test_ipc_message_ping() {
        let msg = IpcMessage::ping(1);
        assert_eq!(msg.r#type, "ping");
        assert_eq!(msg.seq, 1);
        assert!(msg.ack_seq.is_none());
        assert!(msg.action.is_none());
        assert!(msg.keys.is_none());
    }

    #[test]
    fn test_ipc_message_pong() {
        let msg = IpcMessage::pong(2, 1);
        assert_eq!(msg.r#type, "pong");
        assert_eq!(msg.seq, 2);
        assert_eq!(msg.ack_seq, Some(1));
    }

    #[test]
    fn test_ipc_message_execute() {
        let msg = IpcMessage::execute(5, vec!["1".to_string(), "2".to_string()], 100);
        assert_eq!(msg.r#type, "execute");
        assert_eq!(msg.seq, 5);
        assert_eq!(msg.action.as_deref(), Some("keypress"));
        assert_eq!(
            msg.keys.as_deref(),
            Some(&["1".to_string(), "2".to_string()][..])
        );
        assert_eq!(msg.delay, Some(100));
    }

    #[test]
    fn test_ipc_message_result() {
        let data = serde_json::json!({"status": "ok", "count": 2});
        let msg = IpcMessage::result(10, 5, data.clone());
        assert_eq!(msg.r#type, "result");
        assert_eq!(msg.seq, 10);
        assert_eq!(msg.ack_seq, Some(5));
        assert_eq!(msg.data.as_ref().unwrap()["status"], "ok");
        assert_eq!(msg.data.as_ref().unwrap()["count"], 2);
    }

    #[test]
    fn test_ipc_message_shutdown() {
        let msg = IpcMessage::shutdown(99);
        assert_eq!(msg.r#type, "shutdown");
        assert_eq!(msg.seq, 99);
        assert_eq!(msg.action.as_deref(), Some("shutdown"));
    }

    #[test]
    fn test_ipc_message_hotkey_event() {
        let msg = IpcMessage::hotkey_event(1, "F1");
        assert_eq!(msg.r#type, "hotkey");
        assert_eq!(msg.action.as_deref(), Some("hotkey_event"));
        assert_eq!(msg.keys.as_deref(), Some(&["F1".to_string()][..]));
    }

    #[test]
    fn test_ipc_message_heartbeat() {
        let msg = IpcMessage::heartbeat(50);
        assert_eq!(msg.r#type, "heartbeat");
        assert_eq!(msg.seq, 50);
        assert!(msg.action.is_none());
    }
}
