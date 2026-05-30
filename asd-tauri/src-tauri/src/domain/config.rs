use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(rename = "CONTROL_HOTKEYS")]
    pub control_hotkeys: ControlHotkeys,
    #[serde(rename = "GroupSettings")]
    pub group_settings: IndexMap<String, GroupConfig>,
    #[serde(
        rename = "HoldSettings",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub hold_settings: Option<HoldSettings>,
    #[serde(
        rename = "lastModified",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub last_modified: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self::default_config()
    }
}

impl Config {
    #[deprecated(
        since = "0.2.0",
        note = "使用 load_from_path() 替代，支持 app_data_dir"
    )]
    pub fn load_default() -> Self {
        Self::load_from_file("config.json")
    }

    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Self {
        let path = path.as_ref();
        match fs::read_to_string(path) {
            Ok(content) => {
                let cleaned = content.trim_start_matches('\u{feff}');
                match serde_json::from_str(cleaned) {
                    Ok(config) => config,
                    Err(e) => {
                        tracing::error!("配置文件解析失败: {e}");
                        Self::default_config()
                    }
                }
            }
            Err(e) => {
                tracing::warn!("配置文件读取失败: {e}，使用默认配置");
                Self::default_config()
            }
        }
    }

    #[deprecated(since = "0.2.0", note = "使用 save_to_path() 替代，支持原子写入")]
    pub fn save(&self) -> Result<(), String> {
        self.save_to_file("config.json")
    }

    pub fn save_to_file<P: AsRef<Path>>(&self, path: P) -> Result<(), String> {
        let path = path.as_ref();
        let json =
            serde_json::to_string_pretty(self).map_err(|e| format!("序列化配置失败: {e}"))?;
        fs::write(path, json).map_err(|e| format!("写入配置文件失败: {e}"))?;
        Ok(())
    }

    /// 从指定路径加载配置，返回 Result（不吞错误）
    /// 与 load_from_file 不同，此方法在文件不存在或解析失败时返回 Err
    pub fn load_from_path<P: AsRef<Path>>(path: P) -> Result<Self, String> {
        let path = path.as_ref();
        let content = fs::read_to_string(path).map_err(|e| format!("读取配置文件失败: {e}"))?;
        let cleaned = content.trim_start_matches('\u{feff}');
        serde_json::from_str(cleaned).map_err(|e| format!("解析配置文件失败: {e}"))
    }

    /// 原子写入配置到指定路径
    /// 使用临时文件 + rename 确保写入的原子性：
    /// 1. 先写入同目录下的临时文件 (.tmp_前缀)
    /// 2. 成功后 rename 到目标路径
    /// 3. 如果 rename 失败，删除临时文件
    pub fn save_to_path<P: AsRef<Path>>(&self, path: P) -> Result<(), String> {
        let path = path.as_ref();
        let json =
            serde_json::to_string_pretty(self).map_err(|e| format!("序列化配置失败: {e}"))?;

        // 构造临时文件路径：同目录下 .tmp_ 前缀
        let file_name = path
            .file_name()
            .ok_or_else(|| "无效的文件路径".to_string())?
            .to_string_lossy()
            .to_string();
        let tmp_file_name = format!(".tmp_{file_name}");
        let tmp_path = path.with_file_name(&tmp_file_name);

        // 步骤1: 写入临时文件
        fs::write(&tmp_path, &json).map_err(|e| format!("写入临时配置文件失败: {e}"))?;

        // 步骤2: rename 到目标路径（原子操作）
        if let Err(e) = fs::rename(&tmp_path, path) {
            // rename 失败，清理临时文件
            let _ = fs::remove_file(&tmp_path);
            return Err(format!("重命名配置文件失败: {e}"));
        }

        Ok(())
    }

    fn default_config() -> Self {
        Self {
            control_hotkeys: ControlHotkeys {
                emergency: "F10".to_string(),
                release_all_holds: "^r".to_string(),
                show_status: "^0".to_string(),
                toggle_all: "^1".to_string(),
                toggle_hold_mode: "^h".to_string(),
            },
            group_settings: IndexMap::new(),
            hold_settings: Some(HoldSettings {
                allow_overlap: false,
                check_interval: 50,
                debounce_delay: 25,
                press_speed: 80,
                release_on_emergency: true,
            }),
            last_modified: None,
            version: Some("3.0".to_string()),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ControlHotkeys {
    pub emergency: String,
    #[serde(rename = "releaseAllHolds")]
    pub release_all_holds: String,
    #[serde(rename = "showStatus")]
    pub show_status: String,
    #[serde(rename = "toggleAll")]
    pub toggle_all: String,
    #[serde(rename = "toggleHoldMode")]
    pub toggle_hold_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoldSettings {
    #[serde(rename = "allowOverlap")]
    pub allow_overlap: bool,
    #[serde(rename = "checkInterval")]
    pub check_interval: u64,
    #[serde(rename = "debounceDelay")]
    pub debounce_delay: u64,
    #[serde(rename = "pressSpeed")]
    pub press_speed: u64,
    #[serde(rename = "releaseOnEmergency")]
    pub release_on_emergency: bool,
}

#[derive(Debug, Clone)]
pub struct GroupConfig {
    pub hotkey: String,
    pub key_press_duration: Option<u64>,
    pub name: Option<String>,
    pub mode: String,
    pub hold_keys: Option<Vec<String>>,
    pub hold_mode: Option<String>,
    pub hold_pattern: Option<String>,
    pub hold_triggers: Option<Vec<serde_json::Value>>,
    pub mode_data: ModeData,
}

impl Serialize for ModeData {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            ModeData::Periodic(data) => data.serialize(serializer),
            ModeData::Sequence(data) => data.serialize(serializer),
            ModeData::Hybrid(data) => data.serialize(serializer),
            ModeData::Hold(data) => data.serialize(serializer),
            ModeData::EnhancedPeriodic(data) => data.serialize(serializer),
            ModeData::EnhancedSequence(data) => data.serialize(serializer),
            ModeData::EnhancedHybrid(data) => data.serialize(serializer),
            ModeData::JoystickPeriodic(data) => data.serialize(serializer),
            ModeData::JoystickSequence(data) => data.serialize(serializer),
            ModeData::JoystickHold(data) => data.serialize(serializer),
        }
    }
}

#[derive(Debug, Clone)]
pub enum ModeData {
    Periodic(PeriodicData),
    Sequence(SequenceData),
    Hybrid(HybridData),
    Hold(HoldData),
    EnhancedPeriodic(EnhancedPeriodicData),
    EnhancedSequence(EnhancedSequenceData),
    EnhancedHybrid(EnhancedHybridData),
    JoystickPeriodic(JoystickPeriodicData),
    JoystickSequence(JoystickSequenceData),
    JoystickHold(JoystickHoldData),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeriodicData {
    pub keys: Vec<String>,
    pub intervals: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceData {
    pub keys: Vec<String>,
    pub delays: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HybridData {
    pub groups: Vec<GroupItem>,
    #[serde(
        rename = "seqInterval",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub seq_interval: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoldData {
    #[serde(rename = "holdDuration")]
    pub hold_duration: u64,
    #[serde(
        rename = "autoRepeat",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub auto_repeat: Option<bool>,
    #[serde(
        rename = "repeatInterval",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub repeat_interval: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedPeriodicData {
    #[serde(rename = "pressKeys")]
    pub press_keys: Vec<String>,
    pub intervals: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedSequenceData {
    #[serde(rename = "pressKeys")]
    pub press_keys: Vec<String>,
    #[serde(rename = "pressDelays")]
    pub press_delays: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedHybridData {
    pub groups: Vec<GroupItem>,
    #[serde(
        rename = "seqInterval",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub seq_interval: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoystickPeriodicData {
    #[serde(rename = "pressKeys", default)]
    pub press_keys: Vec<String>,
    #[serde(default)]
    pub intervals: Vec<u64>,
    #[serde(
        rename = "joystickId",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub joystick_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoystickSequenceData {
    #[serde(rename = "pressKeys", default)]
    pub press_keys: Vec<String>,
    #[serde(default)]
    pub delays: Vec<u64>,
    #[serde(
        rename = "joystickId",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub joystick_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoystickHoldData {
    #[serde(
        rename = "holdDuration",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub hold_duration: Option<u64>,
    #[serde(
        rename = "autoRepeat",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub auto_repeat: Option<bool>,
    #[serde(
        rename = "repeatInterval",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub repeat_interval: Option<u64>,
    #[serde(
        rename = "joystickId",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub joystick_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum GroupItem {
    #[serde(rename = "periodic")]
    Periodic {
        #[serde(rename = "pressKeys")]
        press_keys: Vec<String>,
        #[serde(default)]
        intervals: Vec<u64>,
    },
    #[serde(rename = "sequence")]
    Sequence {
        #[serde(rename = "pressKeys")]
        press_keys: Vec<String>,
        #[serde(default)]
        delays: Vec<u64>,
        #[serde(
            rename = "seqInterval",
            default,
            skip_serializing_if = "Option::is_none"
        )]
        seq_interval: Option<u64>,
    },
}

impl<'de> Deserialize<'de> for GroupConfig {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;

        let hotkey = value
            .get("hotkey")
            .and_then(|v| v.as_str())
            .ok_or_else(|| serde::de::Error::missing_field("hotkey"))?
            .to_string();

        let mode = value
            .get("mode")
            .and_then(|v| v.as_str())
            .ok_or_else(|| serde::de::Error::missing_field("mode"))?
            .to_string();

        let key_press_duration = value.get("keyPressDuration").and_then(|v| v.as_u64());

        let name = value
            .get("name")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let hold_keys = value
            .get("holdKeys")
            .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok());

        let hold_mode = value
            .get("holdMode")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let hold_pattern = value
            .get("holdPattern")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let hold_triggers = value
            .get("holdTriggers")
            .map(|v| {
                serde_json::from_value::<Vec<serde_json::Value>>(v.clone()).unwrap_or_default()
            })
            .filter(|v| !v.is_empty());

        let mode_data = match mode.as_str() {
            "periodic" => ModeData::Periodic(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("periodic: {e}")))?,
            ),
            "sequence" => ModeData::Sequence(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("sequence: {e}")))?,
            ),
            "hybrid" => ModeData::Hybrid(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("hybrid: {e}")))?,
            ),
            "hold" => ModeData::Hold(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("hold: {e}")))?,
            ),
            "enhanced_periodic" => ModeData::EnhancedPeriodic(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("enhanced_periodic: {e}")))?,
            ),
            "enhanced_sequence" => ModeData::EnhancedSequence(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("enhanced_sequence: {e}")))?,
            ),
            "enhanced_hybrid" => ModeData::EnhancedHybrid(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("enhanced_hybrid: {e}")))?,
            ),
            "joystick_periodic" => ModeData::JoystickPeriodic(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("joystick_periodic: {e}")))?,
            ),
            "joystick_sequence" => ModeData::JoystickSequence(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("joystick_sequence: {e}")))?,
            ),
            "joystick_hold" => ModeData::JoystickHold(
                serde_json::from_value(value.clone())
                    .map_err(|e| serde::de::Error::custom(format!("joystick_hold: {e}")))?,
            ),
            _ => return Err(serde::de::Error::custom(format!("unknown mode: {mode}"))),
        };

        Ok(GroupConfig {
            hotkey,
            key_press_duration,
            name,
            mode,
            hold_keys,
            hold_mode,
            hold_pattern,
            hold_triggers,
            mode_data,
        })
    }
}

impl Serialize for GroupConfig {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serde_json::Map::new();

        map.insert(
            "hotkey".to_string(),
            serde_json::Value::String(self.hotkey.clone()),
        );
        map.insert(
            "mode".to_string(),
            serde_json::Value::String(self.mode.clone()),
        );

        if let Some(ref v) = self.key_press_duration {
            map.insert(
                "keyPressDuration".to_string(),
                serde_json::Value::Number((*v).into()),
            );
        }
        if let Some(ref v) = self.name {
            map.insert("name".to_string(), serde_json::Value::String(v.clone()));
        }
        if let Some(ref v) = self.hold_keys {
            map.insert(
                "holdKeys".to_string(),
                serde_json::to_value(v).map_err(|e| serde::ser::Error::custom(e.to_string()))?,
            );
        }
        if let Some(ref v) = self.hold_mode {
            map.insert("holdMode".to_string(), serde_json::Value::String(v.clone()));
        }
        if let Some(ref v) = self.hold_pattern {
            map.insert(
                "holdPattern".to_string(),
                serde_json::Value::String(v.clone()),
            );
        }
        if let Some(ref v) = self.hold_triggers {
            map.insert(
                "holdTriggers".to_string(),
                serde_json::to_value(v).map_err(|e| serde::ser::Error::custom(e.to_string()))?,
            );
        }

        let mode_value = serde_json::to_value(&self.mode_data)
            .map_err(|e| serde::ser::Error::custom(e.to_string()))?;
        if let serde_json::Value::Object(mode_map) = mode_value {
            for (key, value) in mode_map {
                map.insert(key, value);
            }
        }

        serde_json::Value::Object(map).serialize(serializer)
    }
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn test_group_item_periodic_deserialize() {
        let json = r#"{"type":"periodic","pressKeys":["1","2"],"intervals":[50,60]}"#;
        let item: GroupItem = serde_json::from_str(json).unwrap();
        match item {
            GroupItem::Periodic {
                press_keys,
                intervals,
            } => {
                assert_eq!(press_keys, vec!["1", "2"]);
                assert_eq!(intervals, vec![50, 60]);
            }
            _ => panic!("Expected Periodic variant"),
        }
    }

    #[test]
    fn test_group_item_sequence_deserialize() {
        let json =
            r#"{"type":"sequence","pressKeys":["A","S"],"delays":[100,200],"seqInterval":50}"#;
        let item: GroupItem = serde_json::from_str(json).unwrap();
        match item {
            GroupItem::Sequence {
                press_keys,
                delays,
                seq_interval,
            } => {
                assert_eq!(press_keys, vec!["A", "S"]);
                assert_eq!(delays, vec![100, 200]);
                assert_eq!(seq_interval, Some(50));
            }
            _ => panic!("Expected Sequence variant"),
        }
    }

    #[test]
    fn test_control_hotkeys_deserialize() {
        let json = r#"{"emergency":"F10","releaseAllHolds":"^r","showStatus":"^0","toggleAll":"^1","toggleHoldMode":"^h"}"#;
        let hk: ControlHotkeys = serde_json::from_str(json).unwrap();
        assert_eq!(hk.emergency, "F10");
        assert_eq!(hk.release_all_holds, "^r");
    }

    #[test]
    fn test_hold_settings_deserialize() {
        let json = r#"{"allowOverlap":false,"checkInterval":50,"debounceDelay":25,"pressSpeed":80,"releaseOnEmergency":true}"#;
        let hs: HoldSettings = serde_json::from_str(json).unwrap();
        assert_eq!(hs.allow_overlap, false);
        assert_eq!(hs.check_interval, 50);
        assert_eq!(hs.debounce_delay, 25);
    }

    // ---- 新增：GroupConfig 10 种模式反序列化测试 ----

    #[test]
    fn test_group_config_periodic_deserialize() {
        let json = r#"{"hotkey":"F1","mode":"periodic","keys":["1","2"],"intervals":[50,60]}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F1");
        assert_eq!(gc.mode, "periodic");
        match &gc.mode_data {
            ModeData::Periodic(data) => {
                assert_eq!(data.keys, vec!["1", "2"]);
                assert_eq!(data.intervals, vec![50, 60]);
            }
            other => panic!("Expected Periodic, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_sequence_deserialize() {
        let json = r#"{"hotkey":"F2","mode":"sequence","keys":["A","S"],"delays":[100,200]}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F2");
        assert_eq!(gc.mode, "sequence");
        match &gc.mode_data {
            ModeData::Sequence(data) => {
                assert_eq!(data.keys, vec!["A", "S"]);
                assert_eq!(data.delays, vec![100, 200]);
            }
            other => panic!("Expected Sequence, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_hybrid_deserialize() {
        let json = r#"{"hotkey":"F3","mode":"hybrid","groups":[{"type":"periodic","pressKeys":["1"],"intervals":[50]},{"type":"sequence","pressKeys":["A"],"delays":[100]}],"seqInterval":50}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F3");
        assert_eq!(gc.mode, "hybrid");
        match &gc.mode_data {
            ModeData::Hybrid(data) => {
                assert_eq!(data.groups.len(), 2);
                assert_eq!(data.seq_interval, Some(50));
            }
            other => panic!("Expected Hybrid, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_hold_deserialize() {
        let json = r#"{"hotkey":"F4","mode":"hold","holdDuration":500,"autoRepeat":true,"repeatInterval":100}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F4");
        assert_eq!(gc.mode, "hold");
        match &gc.mode_data {
            ModeData::Hold(data) => {
                assert_eq!(data.hold_duration, 500);
                assert_eq!(data.auto_repeat, Some(true));
                assert_eq!(data.repeat_interval, Some(100));
            }
            other => panic!("Expected Hold, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_enhanced_periodic_deserialize() {
        let json = r#"{"hotkey":"F5","mode":"enhanced_periodic","pressKeys":["Space","1"],"intervals":[50,60]}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F5");
        assert_eq!(gc.mode, "enhanced_periodic");
        match &gc.mode_data {
            ModeData::EnhancedPeriodic(data) => {
                assert_eq!(data.press_keys, vec!["Space", "1"]);
                assert_eq!(data.intervals, vec![50, 60]);
            }
            other => panic!("Expected EnhancedPeriodic, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_enhanced_sequence_deserialize() {
        let json = r#"{"hotkey":"F6","mode":"enhanced_sequence","pressKeys":["1","2"],"pressDelays":[100,200]}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F6");
        assert_eq!(gc.mode, "enhanced_sequence");
        match &gc.mode_data {
            ModeData::EnhancedSequence(data) => {
                assert_eq!(data.press_keys, vec!["1", "2"]);
                assert_eq!(data.press_delays, vec![100, 200]);
            }
            other => panic!("Expected EnhancedSequence, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_enhanced_hybrid_deserialize() {
        let json = r#"{"hotkey":"F7","mode":"enhanced_hybrid","groups":[{"type":"periodic","pressKeys":["1"],"intervals":[50]}],"seqInterval":100}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F7");
        assert_eq!(gc.mode, "enhanced_hybrid");
        match &gc.mode_data {
            ModeData::EnhancedHybrid(data) => {
                assert_eq!(data.groups.len(), 1);
                assert_eq!(data.seq_interval, Some(100));
            }
            other => panic!("Expected EnhancedHybrid, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_joystick_periodic_deserialize() {
        let json = r#"{"hotkey":"F8","mode":"joystick_periodic","pressKeys":["1"],"intervals":[50],"joystickId":0}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F8");
        assert_eq!(gc.mode, "joystick_periodic");
        match &gc.mode_data {
            ModeData::JoystickPeriodic(data) => {
                assert_eq!(data.press_keys, vec!["1"]);
                assert_eq!(data.intervals, vec![50]);
                assert_eq!(data.joystick_id, Some(0));
            }
            other => panic!("Expected JoystickPeriodic, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_joystick_sequence_deserialize() {
        let json = r#"{"hotkey":"F9","mode":"joystick_sequence","pressKeys":["A"],"delays":[100],"joystickId":1}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F9");
        assert_eq!(gc.mode, "joystick_sequence");
        match &gc.mode_data {
            ModeData::JoystickSequence(data) => {
                assert_eq!(data.press_keys, vec!["A"]);
                assert_eq!(data.delays, vec![100]);
                assert_eq!(data.joystick_id, Some(1));
            }
            other => panic!("Expected JoystickSequence, got {other:?}"),
        }
    }

    #[test]
    fn test_group_config_joystick_hold_deserialize() {
        let json = r#"{"hotkey":"F10","mode":"joystick_hold","holdDuration":500,"autoRepeat":false,"joystickId":2}"#;
        let gc: GroupConfig = serde_json::from_str(json).unwrap();
        assert_eq!(gc.hotkey, "F10");
        assert_eq!(gc.mode, "joystick_hold");
        match &gc.mode_data {
            ModeData::JoystickHold(data) => {
                assert_eq!(data.hold_duration, Some(500));
                assert_eq!(data.auto_repeat, Some(false));
                assert_eq!(data.joystick_id, Some(2));
            }
            other => panic!("Expected JoystickHold, got {other:?}"),
        }
    }

    // ---- 新增：GroupConfig 缺失必需字段测试 ----

    #[test]
    fn test_group_config_missing_hotkey() {
        let json = r#"{"mode":"periodic","keys":["1"],"intervals":[50]}"#;
        let result = serde_json::from_str::<GroupConfig>(json);
        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(
            err_msg.contains("hotkey"),
            "错误信息应提及 hotkey: {err_msg}"
        );
    }

    #[test]
    fn test_group_config_missing_mode() {
        let json = r#"{"hotkey":"F1","keys":["1"],"intervals":[50]}"#;
        let result = serde_json::from_str::<GroupConfig>(json);
        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("mode"), "错误信息应提及 mode: {err_msg}");
    }

    #[test]
    fn test_group_config_unknown_mode() {
        let json = r#"{"hotkey":"F1","mode":"nonexistent","keys":["1"]}"#;
        let result = serde_json::from_str::<GroupConfig>(json);
        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(
            err_msg.contains("unknown mode"),
            "错误信息应提及 unknown mode: {err_msg}"
        );
    }

    // ---- 新增：GroupConfig 序列化 roundtrip 测试（10 种模式） ----

    fn make_periodic_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
            name: Some("周期按键".to_string()),
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string(), "2".to_string()],
                intervals: vec![50, 60],
            }),
        }
    }

    fn make_sequence_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F2".to_string(),
            key_press_duration: None,
            name: None,
            mode: "sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Sequence(SequenceData {
                keys: vec!["A".to_string(), "S".to_string()],
                delays: vec![100, 200],
            }),
        }
    }

    fn make_hybrid_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F3".to_string(),
            key_press_duration: None,
            name: None,
            mode: "hybrid".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Hybrid(HybridData {
                groups: vec![
                    GroupItem::Periodic {
                        press_keys: vec!["1".to_string()],
                        intervals: vec![50],
                    },
                    GroupItem::Sequence {
                        press_keys: vec!["A".to_string()],
                        delays: vec![100],
                        seq_interval: None,
                    },
                ],
                seq_interval: Some(100),
            }),
        }
    }

    fn make_hold_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F4".to_string(),
            key_press_duration: None,
            name: None,
            mode: "hold".to_string(),
            hold_keys: Some(vec!["Shift".to_string()]),
            hold_mode: Some("continuous".to_string()),
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Hold(HoldData {
                hold_duration: 500,
                auto_repeat: Some(true),
                repeat_interval: Some(100),
            }),
        }
    }

    fn make_enhanced_periodic_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F5".to_string(),
            key_press_duration: Some(15),
            name: None,
            mode: "enhanced_periodic".to_string(),
            hold_keys: Some(vec!["Shift".to_string()]),
            hold_mode: Some("continuous".to_string()),
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                press_keys: vec!["Space".to_string(), "1".to_string()],
                intervals: vec![50, 60],
            }),
        }
    }

    fn make_enhanced_sequence_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F6".to_string(),
            key_press_duration: None,
            name: None,
            mode: "enhanced_sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::EnhancedSequence(EnhancedSequenceData {
                press_keys: vec!["1".to_string(), "2".to_string()],
                press_delays: vec![100, 200],
            }),
        }
    }

    fn make_enhanced_hybrid_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F7".to_string(),
            key_press_duration: None,
            name: None,
            mode: "enhanced_hybrid".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::EnhancedHybrid(EnhancedHybridData {
                groups: vec![GroupItem::Periodic {
                    press_keys: vec!["Space".to_string()],
                    intervals: vec![100],
                }],
                seq_interval: Some(50),
            }),
        }
    }

    fn make_joystick_periodic_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F8".to_string(),
            key_press_duration: None,
            name: None,
            mode: "joystick_periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::JoystickPeriodic(JoystickPeriodicData {
                press_keys: vec!["1".to_string()],
                intervals: vec![50],
                joystick_id: Some(0),
            }),
        }
    }

    fn make_joystick_sequence_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F9".to_string(),
            key_press_duration: None,
            name: None,
            mode: "joystick_sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::JoystickSequence(JoystickSequenceData {
                press_keys: vec!["A".to_string()],
                delays: vec![100],
                joystick_id: Some(1),
            }),
        }
    }

    fn make_joystick_hold_group_config() -> GroupConfig {
        GroupConfig {
            hotkey: "F10".to_string(),
            key_press_duration: None,
            name: None,
            mode: "joystick_hold".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::JoystickHold(JoystickHoldData {
                hold_duration: Some(500),
                auto_repeat: Some(false),
                repeat_interval: None,
                joystick_id: Some(2),
            }),
        }
    }

    fn assert_roundtrip(original: &GroupConfig) {
        let json = serde_json::to_string(original).unwrap();
        let decoded: GroupConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(decoded.hotkey, original.hotkey, "hotkey roundtrip 失败");
        assert_eq!(decoded.mode, original.mode, "mode roundtrip 失败");
        assert_eq!(
            decoded.key_press_duration, original.key_press_duration,
            "key_press_duration roundtrip 失败"
        );
        assert_eq!(decoded.name, original.name, "name roundtrip 失败");
        assert_eq!(
            decoded.hold_keys, original.hold_keys,
            "hold_keys roundtrip 失败"
        );
        assert_eq!(
            decoded.hold_mode, original.hold_mode,
            "hold_mode roundtrip 失败"
        );
        assert_eq!(
            decoded.hold_pattern, original.hold_pattern,
            "hold_pattern roundtrip 失败"
        );
        assert_eq!(
            decoded.hold_triggers, original.hold_triggers,
            "hold_triggers roundtrip 失败"
        );

        // 验证 mode_data 序列化后再反序列化类型一致
        let original_json = serde_json::to_string(&original.mode_data).unwrap();
        let decoded_json = serde_json::to_string(&decoded.mode_data).unwrap();
        assert_eq!(original_json, decoded_json, "mode_data roundtrip 不一致");
    }

    #[test]
    fn test_roundtrip_periodic() {
        assert_roundtrip(&make_periodic_group_config());
    }

    #[test]
    fn test_roundtrip_sequence() {
        assert_roundtrip(&make_sequence_group_config());
    }

    #[test]
    fn test_roundtrip_hybrid() {
        assert_roundtrip(&make_hybrid_group_config());
    }

    #[test]
    fn test_roundtrip_hold() {
        assert_roundtrip(&make_hold_group_config());
    }

    #[test]
    fn test_roundtrip_enhanced_periodic() {
        assert_roundtrip(&make_enhanced_periodic_group_config());
    }

    #[test]
    fn test_roundtrip_enhanced_sequence() {
        assert_roundtrip(&make_enhanced_sequence_group_config());
    }

    #[test]
    fn test_roundtrip_enhanced_hybrid() {
        assert_roundtrip(&make_enhanced_hybrid_group_config());
    }

    #[test]
    fn test_roundtrip_joystick_periodic() {
        assert_roundtrip(&make_joystick_periodic_group_config());
    }

    #[test]
    fn test_roundtrip_joystick_sequence() {
        assert_roundtrip(&make_joystick_sequence_group_config());
    }

    #[test]
    fn test_roundtrip_joystick_hold() {
        assert_roundtrip(&make_joystick_hold_group_config());
    }

    // ---- 新增：Config 整体序列化 roundtrip 测试 ----

    #[test]
    fn test_config_roundtrip() {
        let mut group_settings = IndexMap::new();
        group_settings.insert("1".to_string(), make_periodic_group_config());
        group_settings.insert("2".to_string(), make_hold_group_config());

        let config = Config {
            control_hotkeys: ControlHotkeys {
                emergency: "F10".to_string(),
                release_all_holds: "^r".to_string(),
                show_status: "^0".to_string(),
                toggle_all: "^1".to_string(),
                toggle_hold_mode: "^h".to_string(),
            },
            group_settings,
            hold_settings: Some(HoldSettings {
                allow_overlap: false,
                check_interval: 50,
                debounce_delay: 25,
                press_speed: 80,
                release_on_emergency: true,
            }),
            last_modified: Some("2025-01-01T00:00:00".to_string()),
            version: Some("3.0".to_string()),
        };

        let json = serde_json::to_string_pretty(&config).unwrap();
        let decoded: Config = serde_json::from_str(&json).unwrap();

        assert_eq!(decoded.control_hotkeys.emergency, "F10");
        assert_eq!(decoded.group_settings.len(), 2);
        assert!(decoded.group_settings.contains_key("1"));
        assert!(decoded.group_settings.contains_key("2"));
        assert!(decoded.hold_settings.is_some());
        assert_eq!(decoded.version.as_deref(), Some("3.0"));
    }

    // ---- 新增：GroupConfig 可选字段序列化跳过测试 ----

    #[test]
    fn test_group_config_optional_fields_skip_serialization() {
        let gc = GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: None,
            name: None,
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        };
        let json = serde_json::to_string(&gc).unwrap();
        assert!(!json.contains("keyPressDuration"), "None 字段不应序列化");
        assert!(!json.contains("holdKeys"), "None 字段不应序列化");
        assert!(!json.contains("holdMode"), "None 字段不应序列化");
        assert!(!json.contains("holdPattern"), "None 字段不应序列化");
        assert!(!json.contains("holdTriggers"), "None 字段不应序列化");
        assert!(!json.contains("name"), "None 字段不应序列化");
    }

    #[test]
    fn test_group_config_with_all_optional_fields() {
        let gc = GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(20),
            name: Some("测试组".to_string()),
            mode: "periodic".to_string(),
            hold_keys: Some(vec!["Shift".to_string()]),
            hold_mode: Some("continuous".to_string()),
            hold_pattern: Some("toggle".to_string()),
            hold_triggers: Some(vec![serde_json::json!({"type": "press"})]),
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        };
        let json = serde_json::to_string(&gc).unwrap();
        assert!(json.contains("keyPressDuration"));
        assert!(json.contains("holdKeys"));
        assert!(json.contains("holdMode"));
        assert!(json.contains("holdPattern"));
        assert!(json.contains("holdTriggers"));
        assert!(json.contains("测试组"));
    }

    // ---- load_from_file / save_to_file 路径测试 ----

    /// 测试 load_from_file 从指定路径加载配置
    #[test]
    fn test_load_from_file_valid_file() {
        let dir = std::env::temp_dir().join("asd_test_load_from_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("test_config.json");
        let config = Config::default_config();
        let json = serde_json::to_string_pretty(&config).unwrap();
        std::fs::write(&path, json).unwrap();

        let loaded = Config::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
        assert_eq!(loaded.version.as_deref(), Some("3.0"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 测试 load_from_file 文件不存在时回退默认配置
    #[test]
    fn test_load_from_file_missing_file_falls_back() {
        let path = std::path::PathBuf::from("/nonexistent/path/config.json");
        let loaded = Config::load_from_file(&path);
        // load_from_file 在文件不存在时回退到默认配置
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
    }

    /// 测试 load_from_file 解析失败时回退默认配置
    #[test]
    fn test_load_from_file_invalid_json_falls_back() {
        let dir = std::env::temp_dir().join("asd_test_load_invalid_json");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bad_config.json");
        std::fs::write(&path, "{invalid json!!!}").unwrap();

        let loaded = Config::load_from_file(&path);
        // load_from_file 在解析失败时回退到默认配置
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 测试 save_to_file 写入配置
    #[test]
    fn test_save_to_file_atomic_write() {
        let dir = std::env::temp_dir().join("asd_test_save_to_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("atomic_config.json");
        let config = Config::default_config();

        // 保存应成功
        config.save_to_file(&path).expect("save_to_file 应成功");

        // 文件应存在且内容可解析
        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).expect("保存的文件应可解析");
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 测试 save_to_file 覆盖时保持一致性
    #[test]
    fn test_save_to_file_overwrite_consistency() {
        let dir = std::env::temp_dir().join("asd_test_save_overwrite");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("overwrite_config.json");

        // 第一次写入
        let config1 = Config::default_config();
        config1.save_to_file(&path).unwrap();

        // 第二次写入（覆盖）
        let mut config2 = Config::default_config();
        config2.control_hotkeys.emergency = "F12".to_string();
        config2.save_to_file(&path).unwrap();

        // 验证是最新内容
        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).unwrap();
        assert_eq!(
            loaded.control_hotkeys.emergency, "F12",
            "覆盖后应为最新内容"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 测试 save_to_file 在无效路径时返回错误
    #[test]
    fn test_save_to_file_invalid_directory_returns_error() {
        let path = std::path::PathBuf::from("/nonexistent/directory/config.json");
        let config = Config::default_config();
        let result = config.save_to_file(&path);
        assert!(result.is_err(), "无效路径应返回 Err");
    }
}
