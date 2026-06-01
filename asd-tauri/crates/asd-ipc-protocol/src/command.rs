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
    #[serde(rename = "ping")]
    Ping,
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
            assert_eq!(json, re_encoded, "Roundtrip failed for {:?}", cmd);
        }
    }
}
