use crate::domain::config::{GroupConfig, ModeData};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillGroup {
    pub id: String,
    pub name: String,
    pub hotkey: String,
    pub active: bool,
    pub mode: String,
    #[serde(rename = "keyPressDuration", default)]
    pub key_press_duration: u64,
    #[serde(rename = "holdKeys", skip_serializing_if = "Option::is_none", default)]
    pub hold_keys: Option<Vec<String>>,
    #[serde(rename = "holdMode", skip_serializing_if = "Option::is_none", default)]
    pub hold_mode: Option<String>,
    #[serde(rename = "modeData",
        serialize_with = "serialize_mode_data",
        deserialize_with = "deserialize_mode_data",
        default = "default_mode_data"
    )]
    pub mode_data: ModeData,
}

fn serialize_mode_data<S: serde::Serializer>(data: &ModeData, serializer: S) -> Result<S::Ok, S::Error> {
    let mode_str = match data {
        ModeData::Periodic(_) => "periodic",
        ModeData::Sequence(_) => "sequence",
        ModeData::Hybrid(_) => "hybrid",
        ModeData::Hold(_) => "hold",
        ModeData::EnhancedPeriodic(_) => "enhanced_periodic",
        ModeData::EnhancedSequence(_) => "enhanced_sequence",
        ModeData::EnhancedHybrid(_) => "enhanced_hybrid",
        ModeData::JoystickPeriodic(_) => "joystick_periodic",
        ModeData::JoystickSequence(_) => "joystick_sequence",
        ModeData::JoystickHold(_) => "joystick_hold",
    };

    let mut value = serde_json::to_value(data)
        .map_err(|e| serde::ser::Error::custom(e.to_string()))?;

    if let serde_json::Value::Object(ref mut map) = value {
        map.insert("mode".to_string(), serde_json::Value::String(mode_str.to_string()));
    }

    value.serialize(serializer)
}

fn deserialize_mode_data<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<ModeData, D::Error> {
    let value = serde_json::Value::deserialize(deserializer)?;
    let mode = value
        .get("mode")
        .and_then(|v| v.as_str())
        .ok_or_else(|| serde::de::Error::missing_field("mode"))?;

    match mode {
        "periodic" => serde_json::from_value(value.clone())
            .map(ModeData::Periodic)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "sequence" => serde_json::from_value(value.clone())
            .map(ModeData::Sequence)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "hybrid" => serde_json::from_value(value.clone())
            .map(ModeData::Hybrid)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "hold" => serde_json::from_value(value.clone())
            .map(ModeData::Hold)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "enhanced_periodic" => serde_json::from_value(value.clone())
            .map(ModeData::EnhancedPeriodic)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "enhanced_sequence" => serde_json::from_value(value.clone())
            .map(ModeData::EnhancedSequence)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "enhanced_hybrid" => serde_json::from_value(value.clone())
            .map(ModeData::EnhancedHybrid)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "joystick_periodic" => serde_json::from_value(value.clone())
            .map(ModeData::JoystickPeriodic)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "joystick_sequence" => serde_json::from_value(value.clone())
            .map(ModeData::JoystickSequence)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        "joystick_hold" => serde_json::from_value(value.clone())
            .map(ModeData::JoystickHold)
            .map_err(|e| serde::de::Error::custom(e.to_string())),
        _ => Err(serde::de::Error::custom(format!("unknown mode: {mode}"))),
    }
}

fn default_mode_data() -> ModeData {
    ModeData::Periodic(crate::domain::config::PeriodicData {
        keys: vec![],
        intervals: vec![],
    })
}

impl From<(&String, &GroupConfig)> for SkillGroup {
    fn from((id, config): (&String, &GroupConfig)) -> Self {
        Self {
            id: id.clone(),
            name: config.name.clone().unwrap_or_else(|| id.clone()),
            hotkey: config.hotkey.clone(),
            active: false,
            mode: config.mode.clone(),
            key_press_duration: config.key_press_duration.unwrap_or(0),
            hold_keys: config.hold_keys.clone(),
            hold_mode: config.hold_mode.clone(),
            mode_data: config.mode_data.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action")]
pub enum IpcCommand {
    #[serde(rename = "toggle_group")]
    ToggleGroup {
        #[serde(rename = "groupId")]
        group_id: String,
        active: bool,
        /// 执行模式（如 periodic, sequence, enhanced_periodic 等）
        #[serde(skip_serializing_if = "Option::is_none", default)]
        mode: Option<String>,
        /// 按键按下持续时间（毫秒）
        #[serde(rename = "keyPressDuration", skip_serializing_if = "Option::is_none", default)]
        key_press_duration: Option<u64>,
        /// Hold 模式按住的键
        #[serde(rename = "holdKeys", skip_serializing_if = "Option::is_none", default)]
        hold_keys: Option<Vec<String>>,
        /// Hold 模式类型
        #[serde(rename = "holdMode", skip_serializing_if = "Option::is_none", default)]
        hold_mode: Option<String>,
        /// 模式特定配置数据（JSON）
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
    UnregisterHotkey {
        hotkey: String,
    },
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
    HoldModeToggle {
        enabled: bool,
    },
    #[serde(rename = "start_validation")]
    StartValidation {
        #[serde(rename = "groupId")]
        group_id: String,
    },
    #[serde(rename = "stop_validation")]
    StopValidation,
}

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
    pub fn command(seq: u64, cmd: &IpcCommand) -> Self {
        let action_str = match cmd {
            IpcCommand::ToggleGroup { .. } => "toggle_group",
            IpcCommand::RegisterHotkey { .. } => "register_hotkey",
            IpcCommand::UnregisterHotkey { .. } => "unregister_hotkey",
            IpcCommand::StartRecording { .. } => "start_recording",
            IpcCommand::StopRecording => "stop_recording",
            IpcCommand::PauseRecording => "pause_recording",
            IpcCommand::ResumeRecording => "resume_recording",
            IpcCommand::EmergencyRelease => "emergency_release",
            IpcCommand::Ping => "ping",
            IpcCommand::Shutdown => "shutdown",
            IpcCommand::HoldModeToggle { .. } => "hold_mode_toggle",
            IpcCommand::StartValidation { .. } => "start_validation",
            IpcCommand::StopValidation => "stop_validation",
        };

        let data = match cmd {
            IpcCommand::ToggleGroup { group_id, active, mode, key_press_duration, hold_keys, hold_mode, mode_data } => {
                let mut data = serde_json::json!({
                    "groupId": group_id,
                    "active": active
                });
                // 仅在有值时添加可选字段，避免 AHK 侧解析多余 null 字段
                if let Some(ref m) = mode {
                    data["mode"] = serde_json::Value::String(m.clone());
                }
                if let Some(ref kpd) = key_press_duration {
                    data["keyPressDuration"] = serde_json::Value::Number((*kpd).into());
                }
                if let Some(ref hk) = hold_keys {
                    data["holdKeys"] = serde_json::to_value(hk).unwrap_or(serde_json::Value::Null);
                }
                if let Some(ref hm) = hold_mode {
                    data["holdMode"] = serde_json::Value::String(hm.clone());
                }
                if let Some(ref md) = mode_data {
                    data["modeData"] = md.clone();
                }
                Some(data)
            }
            IpcCommand::RegisterHotkey { hotkey, group_id } => Some(serde_json::json!({
                "hotkey": hotkey,
                "groupId": group_id
            })),
            IpcCommand::UnregisterHotkey { hotkey } => Some(serde_json::json!({
                "hotkey": hotkey
            })),
            IpcCommand::StartRecording { group_id, mode } => Some(serde_json::json!({
                "groupId": group_id,
                "mode": mode
            })),
            IpcCommand::StopRecording => None,
            IpcCommand::PauseRecording => None,
            IpcCommand::ResumeRecording => None,
            IpcCommand::EmergencyRelease => None,
            IpcCommand::Ping => None,
            IpcCommand::Shutdown => None,
            IpcCommand::HoldModeToggle { enabled } => Some(serde_json::json!({
                "enabled": enabled
            })),
            IpcCommand::StartValidation { group_id } => Some(serde_json::json!({
                "groupId": group_id
            })),
            IpcCommand::StopValidation => None,
        };

        Self {
            id: None,
            r#type: "command".to_string(),
            seq,
            ack_seq: None,
            action: Some(action_str.to_string()),
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

    /// 构造 IPC 认证消息（C-14: Named Pipe 认证）
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
    use crate::domain::config::*;

    fn make_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
            name: Some("测试组".to_string()),
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

    #[test]
    fn test_skill_group_from_group_config() {
        let id = "1".to_string();
        let config = make_group_config();
        let group: SkillGroup = (&id, &config).into();

        assert_eq!(group.id, "1");
        assert_eq!(group.name, "测试组");
        assert_eq!(group.hotkey, "F1");
        assert!(!group.active);
        assert_eq!(group.mode, "periodic");
        assert_eq!(group.key_press_duration, 10);
    }

    #[test]
    fn test_skill_group_default_name() {
        let id = "5".to_string();
        let mut config = make_group_config();
        config.name = None;
        let group: SkillGroup = (&id, &config).into();

        assert_eq!(group.name, "5");
    }

    #[test]
    fn test_skill_group_serialization_roundtrip() {
        let id = "1".to_string();
        let config = make_group_config();
        let group: SkillGroup = (&id, &config).into();

        let json = serde_json::to_string(&group).unwrap();
        let decoded: SkillGroup = serde_json::from_str(&json).unwrap();

        assert_eq!(decoded.id, "1");
        assert_eq!(decoded.name, "测试组");
        assert_eq!(decoded.hotkey, "F1");
        assert_eq!(decoded.mode, "periodic");
        assert_eq!(decoded.key_press_duration, 10);
    }

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
            IpcCommand::ToggleGroup { group_id, active, .. } => {
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
            IpcCommand::ToggleGroup { group_id: "1".to_string(), active: false, mode: None, key_press_duration: None, hold_keys: None, hold_mode: None, mode_data: None },
            IpcCommand::RegisterHotkey { hotkey: "F2".to_string(), group_id: "2".to_string() },
            IpcCommand::UnregisterHotkey { hotkey: "F3".to_string() },
            IpcCommand::StartRecording { group_id: "3".to_string(), mode: "periodic".to_string() },
            IpcCommand::StopRecording,
            IpcCommand::PauseRecording,
            IpcCommand::ResumeRecording,
            IpcCommand::EmergencyRelease,
            IpcCommand::Ping,
            IpcCommand::Shutdown,
            IpcCommand::HoldModeToggle { enabled: true },
        ];

        for cmd in &cmds {
            let json = serde_json::to_string(cmd).unwrap();
            let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
            let re_encoded = serde_json::to_string(&decoded).unwrap();
            assert_eq!(json, re_encoded, "Roundtrip failed for {:?}", cmd);
        }
    }

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
        // 验证 IpcMessage::ping() 序列化后生成 AHK 期望的 {"type":"ping","seq":N} 格式
        let msg = IpcMessage::ping(42);
        let json = serde_json::to_string(&msg).unwrap();
        assert!(json.contains(r#""type":"ping""#), "ping 消息应包含 type=ping，实际: {json}");
        assert!(json.contains(r#""seq":42"#), "ping 消息应包含 seq，实际: {json}");
        assert!(!json.contains("action"), "ping 消息不应包含 action 字段，实际: {json}");
        assert!(!json.contains("ack_seq"), "ping 消息不应包含 ack_seq 字段，实际: {json}");
    }

    #[test]
    fn test_ipc_command_ping_produces_command_type_not_ping_type() {
        // 验证 IpcCommand::Ping 通过 command() 构造后 type="command"（不是 "ping"）
        // 这就是心跳协议不匹配的根本原因
        let cmd = IpcCommand::Ping;
        let msg = IpcMessage::command(1, &cmd);
        assert_eq!(msg.r#type, "command", "IpcCommand::Ping 通过 command() 构造后 type 应为 command");
        assert_eq!(msg.action.as_deref(), Some("ping"), "action 应为 ping");
        // AHK 按 type 字段路由，收到 type="command" 不会触发 _HandlePing
    }

    #[test]
    fn test_ipc_message_shutdown_serialization_format() {
        // 验证 IpcMessage::shutdown() 序列化后生成 AHK 期望的 {"type":"shutdown",...} 格式
        let msg = IpcMessage::shutdown(99);
        let json = serde_json::to_string(&msg).unwrap();
        assert!(json.contains(r#""type":"shutdown""#), "shutdown 消息应包含 type=shutdown，实际: {json}");
        assert!(json.contains(r#""seq":99"#), "shutdown 消息应包含 seq，实际: {json}");
    }

    #[test]
    fn test_ipc_command_shutdown_produces_command_type_not_shutdown_type() {
        // 验证 IpcCommand::Shutdown 通过 command() 构造后 type="command"（不是 "shutdown"）
        let cmd = IpcCommand::Shutdown;
        let msg = IpcMessage::command(1, &cmd);
        assert_eq!(msg.r#type, "command", "IpcCommand::Shutdown 通过 command() 构造后 type 应为 command");
        assert_eq!(msg.action.as_deref(), Some("shutdown"), "action 应为 shutdown");
    }

    // ---- C-14: auth 消息测试 ----

    #[test]
    fn test_ipc_message_auth() {
        let msg = IpcMessage::auth("ASD_IPC_AUTH_V1");
        assert_eq!(msg.r#type, "auth", "auth 消息 type 应为 auth");
        assert_eq!(msg.seq, 0, "auth 消息 seq 应为 0");
        assert!(msg.data.is_some(), "auth 消息应有 data 字段");
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

    // ---- C-1: ToggleGroup 应包含模式配置字段的测试 ----
    // 注意: 以下测试引用了尚未实现的 IpcCommand::ToggleGroup 扩展字段，
    // 待 C-1 实现后取消注释

    // #[test]
    // fn test_toggle_group_data_includes_mode_config() { ... }

    // #[test]
    // fn test_toggle_group_data_minimal_without_optional_fields() { ... }

    // #[test]
    // fn test_toggle_group_command_roundtrip_with_mode_config() { ... }
}
