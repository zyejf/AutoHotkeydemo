use crate::config::{GroupConfig, ModeData};
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
    #[serde(
        rename = "modeData",
        serialize_with = "serialize_mode_data",
        deserialize_with = "deserialize_mode_data",
        default = "default_mode_data"
    )]
    pub mode_data: ModeData,
}

fn serialize_mode_data<S: serde::Serializer>(
    data: &ModeData,
    serializer: S,
) -> Result<S::Ok, S::Error> {
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

    let mut value =
        serde_json::to_value(data).map_err(|e| serde::ser::Error::custom(e.to_string()))?;

    if let serde_json::Value::Object(ref mut map) = value {
        map.insert(
            "mode".to_string(),
            serde_json::Value::String(mode_str.to_string()),
        );
    }

    value.serialize(serializer)
}

fn deserialize_mode_data<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<ModeData, D::Error> {
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
    ModeData::Periodic(crate::config::PeriodicData {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::*;

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
}
