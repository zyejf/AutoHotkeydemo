use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action")]
pub enum IpcCommand {
    #[serde(rename = "toggle_group")]
    ToggleGroup {
        #[serde(rename = "groupId")]
        group_id: String,
        active: bool,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        mode: Option<String>,
        #[serde(
            rename = "keyPressDuration",
            skip_serializing_if = "Option::is_none",
            default
        )]
        key_press_duration: Option<u64>,
        #[serde(rename = "holdKeys", skip_serializing_if = "Option::is_none", default)]
        hold_keys: Option<Vec<String>>,
        #[serde(rename = "holdMode", skip_serializing_if = "Option::is_none", default)]
        hold_mode: Option<String>,
        #[serde(rename = "modeData", skip_serializing_if = "Option::is_none", default)]
        mode_data: Option<serde_json::Value>,
    },
    #[serde(rename = "register_hotkey")]
    RegisterHotkey {
        hotkey: String,
        #[serde(rename = "groupId")]
        group_id: String,
    },
    #[serde(rename = "unregister_hotkey")]
    UnregisterHotkey { hotkey: String },
    #[serde(rename = "start_recording")]
    StartRecording {
        #[serde(rename = "groupId")]
        group_id: String,
        mode: String,
    },
    #[serde(rename = "stop_recording")]
    StopRecording,
    #[serde(rename = "pause_recording")]
    PauseRecording,
    #[serde(rename = "resume_recording")]
    ResumeRecording,
    #[serde(rename = "emergency_release")]
    EmergencyRelease,
    /// Ping 命令（心跳检测）。
    ///
    /// **处理层级说明**：Rust 侧不通过 `IpcMessage::command()` 发送此变体，
    /// 而是通过 `IpcMessage::ping(seq)` 直接发送（`type: "ping"`，无 `action` 字段）。
    /// AHK 执行器在 `ipc_client.ahk` 的 `_HandleLine` 中按 `type` 字段路由到 `_HandlePing`，
    /// 不经过 `CommandDispatcher.Dispatch`。
    ///
    /// 即使误用 `IpcMessage::command()` 发送，AHK 的 `_HandleCommand` 有防御性路由，
    /// 会拦截 `action: "ping"` 并转发到 `_HandlePing`。
    #[serde(rename = "ping")]
    Ping,
    /// Shutdown 命令（优雅关机）。
    ///
    /// **处理层级说明**：Rust 侧不通过 `IpcMessage::command()` 发送此变体，
    /// 而是通过 `IpcMessage::shutdown(seq)` 直接发送（`type: "shutdown"`）。
    /// AHK 执行器在 `ipc_client.ahk` 的 `_HandleLine` 中按 `type` 字段路由到 `_HandleShutdown`，
    /// 不经过 `CommandDispatcher.Dispatch`。
    ///
    /// 即使误用 `IpcMessage::command()` 发送，AHK 的 `_HandleCommand` 有防御性路由，
    /// 会拦截 `action: "shutdown"` 并转发到 `_HandleShutdown`。
    #[serde(rename = "shutdown")]
    Shutdown,
    #[serde(rename = "hold_mode_toggle")]
    HoldModeToggle { enabled: bool },
    #[serde(rename = "start_validation")]
    StartValidation {
        #[serde(rename = "groupId")]
        group_id: String,
    },
    #[serde(rename = "stop_validation")]
    StopValidation,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::IpcMessage;

    #[test]
    fn test_ipc_command_toggle_group() {
        let cmd = IpcCommand::ToggleGroup {
            group_id: "1".to_string(),
            active: true,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("toggle_group"));
        assert!(json.contains("\"groupId\":\"1\""));
        assert!(json.contains("\"active\":true"));

        let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
        match decoded {
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
    fn test_ipc_command_register_hotkey() {
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

    /// 验证 `IpcCommand::Ping/Shutdown` 的处理层级文档。
    ///
    /// Ping 和 Shutdown 在 Rust 侧不通过 `IpcMessage::command()` 发送，
    /// 而是通过 `IpcMessage::ping()/shutdown()` 直接发送（type="ping"/"shutdown"）。
    /// AHK 执行器在 `ipc_client.ahk` 的 _`HandleLine` 中按 type 字段路由，
    /// 不经过 CommandDispatcher.Dispatch。
    ///
    /// 即使误用 `IpcMessage::command()` 发送，AHK 的 _`HandleCommand` 有防御性路由，
    /// 会拦截 action="ping"/"shutdown" 并转发到 _`HandlePing`/_`HandleShutdown`。
    #[test]
    fn test_ping_shutdown_handling_layer_documented() {
        // 正常路径：IpcMessage::ping() 产生 type="ping"，无 action
        let ping_msg = IpcMessage::ping(1);
        assert_eq!(ping_msg.r#type, "ping");
        assert!(
            ping_msg.action.is_none(),
            "ping 消息不应有 action 字段（通过 type 路由）"
        );

        // 正常路径：IpcMessage::shutdown() 产生 type="shutdown"
        let shutdown_msg = IpcMessage::shutdown(99);
        assert_eq!(shutdown_msg.r#type, "shutdown");

        // 防御路径：IpcCommand::Ping 通过 command() 发送时产生 type="command", action="ping"
        // AHK _HandleCommand 会拦截 action="ping" 并转发到 _HandlePing
        let cmd_ping = IpcMessage::command(1, &IpcCommand::Ping);
        assert_eq!(cmd_ping.r#type, "command");
        assert_eq!(cmd_ping.action.as_deref(), Some("ping"));

        // 防御路径：IpcCommand::Shutdown 通过 command() 发送时产生 type="command", action="shutdown"
        // AHK _HandleCommand 会拦截 action="shutdown" 并转发到 _HandleShutdown
        let cmd_shutdown = IpcMessage::command(1, &IpcCommand::Shutdown);
        assert_eq!(cmd_shutdown.r#type, "command");
        assert_eq!(cmd_shutdown.action.as_deref(), Some("shutdown"));
    }

    #[test]
    fn test_ipc_command_all_variants() {
        let cmds = vec![
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
                group_id: "4".to_string(),
            },
            IpcCommand::StopValidation,
        ];

        for cmd in &cmds {
            let json = serde_json::to_string(cmd).unwrap();
            let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
            let re_encoded = serde_json::to_string(&decoded).unwrap();
            assert_eq!(json, re_encoded, "Roundtrip failed for {cmd:?}");
        }
    }
}
