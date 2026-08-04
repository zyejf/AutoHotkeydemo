use crate::config::{Config, GroupConfig, GroupItem, ModeData};
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationError {
    pub group_id: String,
    pub field: String,
    pub message: String,
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[{}] {}: {}", self.group_id, self.field, self.message)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub valid: bool,
    pub errors: Vec<ValidationError>,
    pub warnings: Vec<String>,
}

impl ValidationResult {
    pub fn new() -> Self {
        Self {
            valid: true,
            errors: Vec::new(),
            warnings: Vec::new(),
        }
    }

    pub fn is_valid(&self) -> bool {
        self.errors.is_empty()
    }

    pub fn add_error(&mut self, group_id: &str, field: &str, message: &str) {
        self.valid = false;
        self.errors.push(ValidationError {
            group_id: group_id.to_string(),
            field: field.to_string(),
            message: message.to_string(),
        });
    }

    pub fn add_warning(&mut self, message: &str) {
        self.warnings.push(message.to_string());
    }
}

impl Default for ValidationResult {
    fn default() -> Self {
        Self::new()
    }
}

/// 有效热键键名列表（AHK v2 支持的非修饰符键）
/// validate_hotkey_format 和 normalize_hotkey_for_comparison 共享此列表
const VALID_HOTKEY_KEYS: &[&str] = &[
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "Space", "Enter", "Esc", "Tab", "Backspace", "Delete", "Insert",
    "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn",
    "LButton", "RButton", "MButton",
    "CapsLock", "ScrollLock", "Pause", "PrintScreen", "AppsKey",
    "WheelUp", "WheelDown", "WheelLeft", "WheelRight",
    "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
    "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
    "NumpadEnter", "NumpadDot", "NumpadAdd", "NumpadSub",
    "NumpadMult", "NumpadDiv", "NumpadDel", "NumpadIns",
    "NumpadClear", "NumpadUp", "NumpadDown", "NumpadLeft", "NumpadRight",
    "NumpadHome", "NumpadEnd", "NumpadPgUp", "NumpadPgDn",
    "Volume_Up", "Volume_Down", "Volume_Mute",
    "Browser_Back", "Browser_Forward", "Browser_Refresh", "Browser_Stop",
    "Browser_Search", "Browser_Favorites", "Browser_Home",
    "Media_Next", "Media_Prev", "Media_Stop", "Media_Play_Pause",
    "Launch_Mail", "Launch_Media", "Launch_App1", "Launch_App2",
];

pub struct ConfigValidator;

impl ConfigValidator {
    pub fn validate_config(config: &Config) -> ValidationResult {
        let mut result = Self::validate(&config.group_settings);

        Self::validate_hotkey_format("_global", &config.control_hotkeys.emergency, &mut result);
        Self::validate_hotkey_format("_global", &config.control_hotkeys.release_all_holds, &mut result);
        Self::validate_hotkey_format("_global", &config.control_hotkeys.show_status, &mut result);
        Self::validate_hotkey_format("_global", &config.control_hotkeys.toggle_all, &mut result);
        Self::validate_hotkey_format("_global", &config.control_hotkeys.toggle_hold_mode, &mut result);

        if let Some(ref hs) = config.hold_settings {
            if hs.check_interval == 0 {
                result.add_error("_global", "checkInterval", "HoldSettings.checkInterval 不能为 0");
            }
            if hs.press_speed == 0 {
                result.add_error("_global", "pressSpeed", "HoldSettings.pressSpeed 不能为 0");
            }
        }

        result
    }

    pub fn validate(groups: &IndexMap<String, GroupConfig>) -> ValidationResult {
        let mut result = ValidationResult::new();

        if groups.is_empty() {
            result.add_warning("配置中没有分组");
        }

        Self::validate_duplicate_hotkeys(groups, &mut result);

        for (id, group) in groups {
            Self::validate_hotkey_format(id, &group.hotkey, &mut result);

            if group.hotkey.is_empty() {
                result.add_error(id, "hotkey", "热键不能为空");
            }

            if group.mode.is_empty() {
                result.add_error(id, "mode", "模式不能为空");
                continue;
            }

            Self::validate_mode_data(id, &group.mode, &group.mode_data, &mut result);
            Self::validate_cross_fields(id, group, &mut result);
        }

        result
    }

    fn validate_hotkey_format(group_id: &str, hotkey: &str, result: &mut ValidationResult) {
        if hotkey.is_empty() {
            return;
        }

        let valid_prefixes = ["^", "!", "+", "#", "~", "*", "<^", ">^", "<!", ">!", "<+", ">+", "<#", ">#"];
        let mut rest = hotkey;
        while let Some(&prefix) = valid_prefixes.iter().find(|p| rest.starts_with(*p)) {
            rest = &rest[prefix.len()..];
        }

        if rest.is_empty() {
            result.add_error(group_id, "hotkey", "热键必须包含非修饰符键");
            return;
        }

        // 使用 eq_ignore_ascii_case 进行大小写不敏感匹配，正确处理 PascalCase 键名如 "Space"/"space"
        if !VALID_HOTKEY_KEYS.iter().any(|k| k.eq_ignore_ascii_case(rest)) {
            result.add_warning(&format!(
                "[{}] 热键 '{}' 格式可能不正确，请确认是否为有效的 AHK 热键",
                group_id, hotkey
            ));
        }
    }

    fn validate_duplicate_hotkeys(
        groups: &IndexMap<String, GroupConfig>,
        result: &mut ValidationResult,
    ) {
        let mut seen: std::collections::HashMap<String, &str> = std::collections::HashMap::new();
        for (id, group) in groups {
            if group.hotkey.is_empty() {
                continue;
            }
            let normalized = normalize_hotkey_for_comparison(&group.hotkey);
            if let Some(prev_id) = seen.get(&normalized) {
                result.add_error(
                    id,
                    "hotkey",
                    &format!("热键 '{}' 与分组 '{}' 重复", group.hotkey, prev_id),
                );
            } else {
                seen.insert(normalized, id);
            }
        }
    }

    fn validate_cross_fields(group_id: &str, group: &GroupConfig, result: &mut ValidationResult) {
        if group.mode == "hold"
            && group.hold_keys.as_ref().is_none_or(|k| k.is_empty())
        {
            result.add_warning(&format!("[{}] hold 模式建议设置 holdKeys", group_id));
        }

        if group.hold_keys.is_some() && group.hold_mode.is_none() {
            result.add_warning(&format!("[{}] 设置了 holdKeys 但未指定 holdMode", group_id));
        }

        if let Some(ref hold_keys) = group.hold_keys {
            if hold_keys.len() > 4 {
                result.add_warning(&format!(
                    "[{}] holdKeys 数量 ({}) 较多，可能影响操作精度",
                    group_id,
                    hold_keys.len()
                ));
            }
        }

        if let Some(duration) = group.key_press_duration {
            if duration > 1000 {
                result.add_warning(&format!(
                    "[{}] keyPressDuration ({}ms) 过大，通常应小于 1000ms",
                    group_id, duration
                ));
            }
        }
    }

    fn validate_mode_data(
        group_id: &str,
        mode: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        match mode {
            "periodic" => {
                if let ModeData::Periodic(data) = mode_data {
                    if data.keys.is_empty() {
                        result.add_error(group_id, "keys", "periodic 模式需要至少一个按键");
                    }
                    if data.intervals.is_empty() {
                        result.add_error(group_id, "intervals", "periodic 模式需要至少一个间隔");
                    }
                    if data.intervals.contains(&0) {
                        result.add_error(group_id, "intervals", "间隔不能为 0");
                    }
                } else {
                    result.add_error(group_id, "mode_data", "periodic 模式数据类型不匹配");
                }
            }
            "sequence" => {
                if let ModeData::Sequence(data) = mode_data {
                    if data.keys.is_empty() {
                        result.add_error(group_id, "keys", "sequence 模式需要至少一个按键");
                    }
                    if data.delays.is_empty() {
                        result.add_error(group_id, "delays", "sequence 模式需要至少一个延迟");
                    }
                    if data.delays.contains(&0) {
                        result.add_error(group_id, "delays", "延迟不能为 0");
                    }
                } else {
                    result.add_error(group_id, "mode_data", "sequence 模式数据类型不匹配");
                }
            }
            "hybrid" => {
                if let ModeData::Hybrid(data) = mode_data {
                    if data.groups.is_empty() {
                        result.add_error(group_id, "groups", "hybrid 模式需要至少一个子组");
                    }
                    for (i, sub) in data.groups.iter().enumerate() {
                        let sub_label = format!("groups[{}]", i);
                        match sub {
                            GroupItem::Periodic { press_keys, intervals } => {
                                if press_keys.is_empty() {
                                    result.add_error(group_id, &sub_label, "periodic 子组需要至少一个按键");
                                }
                                if intervals.is_empty() {
                                    result.add_error(group_id, &sub_label, "periodic 子组需要至少一个间隔");
                                }
                                if intervals.contains(&0) {
                                    result.add_error(group_id, &sub_label, "periodic 子组间隔不能为 0");
                                }
                            }
                            GroupItem::Sequence { press_keys, delays, .. } => {
                                if press_keys.is_empty() {
                                    result.add_error(group_id, &sub_label, "sequence 子组需要至少一个按键");
                                }
                                if delays.is_empty() {
                                    result.add_error(group_id, &sub_label, "sequence 子组需要至少一个延迟");
                                }
                                if delays.contains(&0) {
                                    result.add_error(group_id, &sub_label, "sequence 子组延迟不能为 0");
                                }
                            }
                        }
                    }
                } else {
                    result.add_error(group_id, "mode_data", "hybrid 模式数据类型不匹配");
                }
            }
            "hold" => {
                if let ModeData::Hold(_data) = mode_data {
                    // holdDuration=0 表示无限保持（直到主动停止），是合法值
                    // holdDuration>0 表示固定时长保持，超时后自动释放
                    // 此处无需额外校验，holdDuration 的非负性由类型系统保证（u64）
                } else {
                    result.add_error(group_id, "mode_data", "hold 模式数据类型不匹配");
                }
            }
            "enhanced_periodic" => {
                if let ModeData::EnhancedPeriodic(data) = mode_data {
                    if data.press_keys.is_empty() {
                        result.add_error(
                            group_id,
                            "pressKeys",
                            "enhanced_periodic 模式需要至少一个按键",
                        );
                    }
                    if data.intervals.is_empty() {
                        result.add_error(
                            group_id,
                            "intervals",
                            "enhanced_periodic 模式需要至少一个间隔",
                        );
                    }
                    if data.intervals.contains(&0) {
                        result.add_error(group_id, "intervals", "间隔不能为 0");
                    }
                } else {
                    result.add_error(
                        group_id,
                        "mode_data",
                        "enhanced_periodic 模式数据类型不匹配",
                    );
                }
            }
            "enhanced_sequence" => {
                if let ModeData::EnhancedSequence(data) = mode_data {
                    if data.press_keys.is_empty() {
                        result.add_error(
                            group_id,
                            "pressKeys",
                            "enhanced_sequence 模式需要至少一个按键",
                        );
                    }
                    if data.press_delays.is_empty() {
                        result.add_error(
                            group_id,
                            "pressDelays",
                            "enhanced_sequence 模式需要至少一个延迟",
                        );
                    }
                    if data.press_delays.contains(&0) {
                        result.add_error(group_id, "pressDelays", "延迟不能为 0");
                    }
                } else {
                    result.add_error(
                        group_id,
                        "mode_data",
                        "enhanced_sequence 模式数据类型不匹配",
                    );
                }
            }
            "enhanced_hybrid" => {
                if let ModeData::EnhancedHybrid(data) = mode_data {
                    if data.groups.is_empty() {
                        result.add_error(
                            group_id,
                            "groups",
                            "enhanced_hybrid 模式需要至少一个子组",
                        );
                    }
                    for (i, sub) in data.groups.iter().enumerate() {
                        let sub_label = format!("groups[{}]", i);
                        match sub {
                            GroupItem::Periodic { press_keys, intervals } => {
                                if press_keys.is_empty() {
                                    result.add_error(group_id, &sub_label, "periodic 子组需要至少一个按键");
                                }
                                if intervals.is_empty() {
                                    result.add_error(group_id, &sub_label, "periodic 子组需要至少一个间隔");
                                }
                                if intervals.contains(&0) {
                                    result.add_error(group_id, &sub_label, "periodic 子组间隔不能为 0");
                                }
                            }
                            GroupItem::Sequence { press_keys, delays, .. } => {
                                if press_keys.is_empty() {
                                    result.add_error(group_id, &sub_label, "sequence 子组需要至少一个按键");
                                }
                                if delays.is_empty() {
                                    result.add_error(group_id, &sub_label, "sequence 子组需要至少一个延迟");
                                }
                                if delays.contains(&0) {
                                    result.add_error(group_id, &sub_label, "sequence 子组延迟不能为 0");
                                }
                            }
                        }
                    }
                } else {
                    result.add_error(group_id, "mode_data", "enhanced_hybrid 模式数据类型不匹配");
                }
            }
            "joystick_periodic" => {
                if let ModeData::JoystickPeriodic(data) = mode_data {
                    if data.press_keys.is_empty() {
                        result.add_error(
                            group_id,
                            "pressKeys",
                            "joystick_periodic 模式需要至少一个按键",
                        );
                    }
                    if data.intervals.is_empty() {
                        result.add_error(
                            group_id,
                            "intervals",
                            "joystick_periodic 模式需要至少一个间隔",
                        );
                    }
                    if data.intervals.contains(&0) {
                        result.add_error(group_id, "intervals", "间隔不能为 0");
                    }
                } else {
                    result.add_error(
                        group_id,
                        "mode_data",
                        "joystick_periodic 模式数据类型不匹配",
                    );
                }
            }
            "joystick_sequence" => {
                if let ModeData::JoystickSequence(data) = mode_data {
                    if data.press_keys.is_empty() {
                        result.add_error(
                            group_id,
                            "pressKeys",
                            "joystick_sequence 模式需要至少一个按键",
                        );
                    }
                    if data.delays.is_empty() {
                        result.add_error(
                            group_id,
                            "delays",
                            "joystick_sequence 模式需要至少一个延迟",
                        );
                    }
                    if data.delays.contains(&0) {
                        result.add_error(group_id, "delays", "延迟不能为 0");
                    }
                } else {
                    result.add_error(
                        group_id,
                        "mode_data",
                        "joystick_sequence 模式数据类型不匹配",
                    );
                }
            }
            "joystick_hold" => {
                if let ModeData::JoystickHold(data) = mode_data {
                    if data.hold_duration.unwrap_or(0) == 0 {
                        result.add_warning(&format!(
                            "[{}] joystick_hold 模式未设置 holdDuration",
                            group_id
                        ));
                    }
                } else {
                    result.add_error(group_id, "mode_data", "joystick_hold 模式数据类型不匹配");
                }
            }
            _ => {
                result.add_error(group_id, "mode", &format!("未知模式: {mode}"));
            }
        }
    }
}

fn normalize_hotkey_for_comparison(hotkey: &str) -> String {
    let single_modifiers = ['^', '!', '+', '#', '~', '*'];
    let dual_modifiers = ["<^", ">^", "<!", ">!", "<+", ">+", "<#", ">#"];
    let mut rest = hotkey;
    let mut prefix_parts = Vec::new();
    loop {
        if let Some(dm) = dual_modifiers.iter().find(|dm| rest.starts_with(*dm)) {
            prefix_parts.push(*dm);
            rest = &rest[dm.len()..];
        } else if let Some(c) = rest.chars().next() {
            if single_modifiers.contains(&c) {
                prefix_parts.push(&rest[..c.len_utf8()]);
                rest = &rest[c.len_utf8()..];
            } else {
                break;
            }
        } else {
            break;
        }
    }
    prefix_parts.sort();
    let prefix = prefix_parts.join("");
    // F 键特殊处理：F1-F24 保持大写
    let normalized_rest = if rest.starts_with('F')
        && rest.len() > 1
        && rest[1..].chars().all(|c| c.is_ascii_digit())
    {
        rest.to_uppercase()
    } else if let Some(canonical) = VALID_HOTKEY_KEYS.iter().find(|k| k.eq_ignore_ascii_case(rest)) {
        // 使用 VALID_HOTKEY_KEYS 统一列表进行大小写不敏感匹配，返回规范形式
        canonical.to_string()
    } else {
        rest.to_lowercase()
    };
    format!("{}{}", prefix, normalized_rest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::*;
    use indexmap::IndexMap;

    fn make_periodic_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: None,
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
        }
    }

    fn make_empty_periodic_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: None,
            name: None,
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec![],
                intervals: vec![],
            }),
        }
    }

    fn make_hybrid_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F2".to_string(),
            key_press_duration: None,
            name: None,
            mode: "hybrid".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Hybrid(HybridData {
                groups: vec![],
                seq_interval: None,
            }),
        }
    }

    fn make_hold_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F3".to_string(),
            key_press_duration: None,
            name: None,
            mode: "hold".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Hold(HoldData {
                hold_duration: 0,
                auto_repeat: None,
                repeat_interval: None,
            }),
        }
    }

    fn make_enhanced_periodic_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F4".to_string(),
            key_press_duration: None,
            name: None,
            mode: "enhanced_periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                press_keys: vec!["Space".to_string()],
                intervals: vec![50],
            }),
        }
    }

    fn make_enhanced_sequence_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F5".to_string(),
            key_press_duration: None,
            name: None,
            mode: "enhanced_sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::EnhancedSequence(EnhancedSequenceData {
                press_keys: vec!["1".to_string()],
                press_delays: vec![100],
            }),
        }
    }

    fn make_enhanced_hybrid_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F6".to_string(),
            key_press_duration: None,
            name: None,
            mode: "enhanced_hybrid".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::EnhancedHybrid(EnhancedHybridData {
                groups: vec![GroupItem::Periodic {
                    press_keys: vec!["1".to_string()],
                    intervals: vec![50],
                }],
                seq_interval: None,
            }),
        }
    }

    fn make_unknown_mode_group() -> GroupConfig {
        GroupConfig {
            hotkey: "F7".to_string(),
            key_press_duration: None,
            name: None,
            mode: "unknown_mode".to_string(),
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
    fn test_valid_periodic_config() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_periodic_group());
        let result = ConfigValidator::validate(&groups);
        assert!(result.is_valid(), "有效配置不应有错误: {:?}", result.errors);
    }

    #[test]
    fn test_empty_keys_periodic() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_empty_periodic_group());
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "keys"));
        assert!(result.errors.iter().any(|e| e.field == "intervals"));
    }

    #[test]
    fn test_empty_hybrid_groups() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_hybrid_group());
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "groups"));
    }

    #[test]
    fn test_hold_zero_duration() {
        // holdDuration=0 表示无限保持（直到主动停止），现在是合法值
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_hold_group());
        let result = ConfigValidator::validate(&groups);
        assert!(result.is_valid(), "holdDuration=0 应该合法（无限保持模式）");
    }

    #[test]
    fn test_unknown_mode() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_unknown_mode_group());
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "mode"));
    }

    #[test]
    fn test_empty_config_warning() {
        let groups = IndexMap::new();
        let result = ConfigValidator::validate(&groups);
        assert!(result.is_valid());
        assert!(!result.warnings.is_empty());
    }

    #[test]
    fn test_valid_enhanced_modes() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_enhanced_periodic_group());
        groups.insert("2".to_string(), make_enhanced_sequence_group());
        groups.insert("3".to_string(), make_enhanced_hybrid_group());
        let result = ConfigValidator::validate(&groups);
        assert!(
            result.is_valid(),
            "增强模式配置不应有错误: {:?}",
            result.errors
        );
    }

    #[test]
    fn test_validation_error_display() {
        let err = ValidationError {
            group_id: "1".to_string(),
            field: "keys".to_string(),
            message: "不能为空".to_string(),
        };
        assert_eq!(format!("{err}"), "[1] keys: 不能为空");
    }

    #[test]
    fn test_validation_result_serialization() {
        let mut result = ValidationResult::new();
        result.add_error("1", "hotkey", "不能为空");
        result.add_warning("测试警告");
        let json = serde_json::to_string(&result).unwrap();
        let decoded: ValidationResult = serde_json::from_str(&json).unwrap();
        assert!(!decoded.valid);
        assert_eq!(decoded.errors.len(), 1);
        assert_eq!(decoded.warnings.len(), 1);
    }

    #[test]
    fn test_validation_result_default() {
        let result = ValidationResult::default();
        assert!(result.is_valid());
        assert!(result.valid);
    }

    #[test]
    fn test_duplicate_hotkey_detection() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_periodic_group());
        groups.insert(
            "2".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: None,
                name: None,
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["2".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "hotkey" && e.message.contains("重复")));
    }

    #[test]
    fn test_hold_mode_without_hold_keys_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F3".to_string(),
                key_press_duration: None,
                name: None,
                mode: "hold".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Hold(HoldData {
                    hold_duration: 500,
                    auto_repeat: None,
                    repeat_interval: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.warnings.iter().any(|w| w.contains("holdKeys")));
    }

    #[test]
    fn test_hold_keys_without_hold_mode_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: None,
                name: None,
                mode: "periodic".to_string(),
                hold_keys: Some(vec!["Shift".to_string()]),
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["1".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.warnings.iter().any(|w| w.contains("holdMode")));
    }

    #[test]
    fn test_large_key_press_duration_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: Some(2000),
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
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result
            .warnings
            .iter()
            .any(|w| w.contains("keyPressDuration")));
    }

    #[test]
    fn test_invalid_hotkey_format_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "INVALID_KEY".to_string(),
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
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.warnings.iter().any(|w| w.contains("格式可能不正确")));
    }

    #[test]
    fn test_valid_hotkey_format_no_warning() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_periodic_group());
        let result = ConfigValidator::validate(&groups);
        assert!(!result.warnings.iter().any(|w| w.contains("格式可能不正确")));
    }

    fn make_sequence_group() -> GroupConfig {
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
                keys: vec!["1".to_string(), "2".to_string()],
                delays: vec![100, 200],
            }),
        }
    }

    #[test]
    fn test_valid_sequence_config() {
        let mut groups = IndexMap::new();
        groups.insert("1".to_string(), make_sequence_group());
        let result = ConfigValidator::validate(&groups);
        assert!(
            result.is_valid(),
            "有效 sequence 配置不应有错误: {:?}",
            result.errors
        );
    }

    #[test]
    fn test_sequence_empty_keys() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    keys: vec![],
                    delays: vec![100],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "keys" && e.message.contains("sequence")));
    }

    #[test]
    fn test_sequence_empty_delays() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    keys: vec!["1".to_string()],
                    delays: vec![],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "delays"));
    }

    #[test]
    fn test_enhanced_periodic_empty_keys() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F4".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                    press_keys: vec![],
                    intervals: vec![50],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "pressKeys"));
    }

    #[test]
    fn test_enhanced_periodic_empty_intervals() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F4".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                    press_keys: vec!["Space".to_string()],
                    intervals: vec![],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "intervals"));
    }

    #[test]
    fn test_enhanced_sequence_empty_keys() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F5".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_sequence".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::EnhancedSequence(EnhancedSequenceData {
                    press_keys: vec![],
                    press_delays: vec![100],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "pressKeys"));
    }

    #[test]
    fn test_enhanced_sequence_empty_delays() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F5".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_sequence".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::EnhancedSequence(EnhancedSequenceData {
                    press_keys: vec!["1".to_string()],
                    press_delays: vec![],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "pressDelays"));
    }

    #[test]
    fn test_enhanced_hybrid_empty_groups() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F6".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_hybrid".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::EnhancedHybrid(EnhancedHybridData {
                    groups: vec![],
                    seq_interval: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "groups"));
    }

    #[test]
    fn test_valid_joystick_periodic() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(
            result.is_valid(),
            "有效 joystick_periodic 配置不应有错误: {:?}",
            result.errors
        );
    }

    #[test]
    fn test_joystick_periodic_empty_keys() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    press_keys: vec![],
                    intervals: vec![50],
                    joystick_id: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "pressKeys"));
    }

    #[test]
    fn test_valid_joystick_sequence() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    press_keys: vec!["1".to_string()],
                    delays: vec![100],
                    joystick_id: Some(0),
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(
            result.is_valid(),
            "有效 joystick_sequence 配置不应有错误: {:?}",
            result.errors
        );
    }

    #[test]
    fn test_joystick_sequence_empty_keys() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    press_keys: vec![],
                    delays: vec![100],
                    joystick_id: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "pressKeys"));
    }

    #[test]
    fn test_valid_joystick_hold() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    auto_repeat: None,
                    repeat_interval: None,
                    joystick_id: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(
            result.is_valid(),
            "有效 joystick_hold 配置不应有错误: {:?}",
            result.errors
        );
    }

    #[test]
    fn test_joystick_hold_zero_duration_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    hold_duration: Some(0),
                    auto_repeat: None,
                    repeat_interval: None,
                    joystick_id: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.warnings.iter().any(|w| w.contains("holdDuration")));
    }

    #[test]
    fn test_joystick_hold_none_duration_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
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
                    hold_duration: None,
                    auto_repeat: None,
                    repeat_interval: None,
                    joystick_id: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.warnings.iter().any(|w| w.contains("holdDuration")));
    }

    #[test]
    fn test_periodic_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: None,
                name: None,
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Sequence(SequenceData {
                    keys: vec!["1".to_string()],
                    delays: vec![100],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("periodic")));
    }

    #[test]
    fn test_sequence_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F2".to_string(),
                key_press_duration: None,
                name: None,
                mode: "sequence".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("sequence")));
    }

    #[test]
    fn test_hold_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F3".to_string(),
                key_press_duration: None,
                name: None,
                mode: "hold".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("hold")));
    }

    #[test]
    fn test_enhanced_periodic_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F4".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_periodic".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("enhanced_periodic")));
    }

    #[test]
    fn test_enhanced_sequence_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F5".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_sequence".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("enhanced_sequence")));
    }

    #[test]
    fn test_enhanced_hybrid_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F6".to_string(),
                key_press_duration: None,
                name: None,
                mode: "enhanced_hybrid".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("enhanced_hybrid")));
    }

    #[test]
    fn test_joystick_periodic_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F8".to_string(),
                key_press_duration: None,
                name: None,
                mode: "joystick_periodic".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("joystick_periodic")));
    }

    #[test]
    fn test_joystick_sequence_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F9".to_string(),
                key_press_duration: None,
                name: None,
                mode: "joystick_sequence".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("joystick_sequence")));
    }

    #[test]
    fn test_joystick_hold_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F10".to_string(),
                key_press_duration: None,
                name: None,
                mode: "joystick_hold".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("joystick_hold")));
    }

    #[test]
    fn test_periodic_zero_interval() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
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
                    intervals: vec![50, 0, 100],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "intervals" && e.message.contains("0")));
    }

    #[test]
    fn test_empty_hotkey_error() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "".to_string(),
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
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "hotkey"));
    }

    #[test]
    fn test_empty_mode_error() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: None,
                name: None,
                mode: "".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "mode"));
    }

    #[test]
    fn test_valid_hold_config() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F3".to_string(),
                key_press_duration: None,
                name: None,
                mode: "hold".to_string(),
                hold_keys: Some(vec!["Shift".to_string()]),
                hold_mode: Some("continuous".to_string()),
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Hold(HoldData {
                    hold_duration: 500,
                    auto_repeat: None,
                    repeat_interval: None,
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(
            result.is_valid(),
            "有效 hold 配置不应有错误: {:?}",
            result.errors
        );
    }

    #[test]
    fn test_hybrid_mode_data_mismatch() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F2".to_string(),
                key_press_duration: None,
                name: None,
                mode: "hybrid".to_string(),
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
        let result = ConfigValidator::validate(&groups);
        assert!(!result.is_valid());
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "mode_data" && e.message.contains("hybrid")));
    }

    #[test]
    fn test_too_many_hold_keys_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: None,
                name: None,
                mode: "periodic".to_string(),
                hold_keys: Some(vec![
                    "Shift".to_string(),
                    "Ctrl".to_string(),
                    "Alt".to_string(),
                    "Win".to_string(),
                    "F1".to_string(),
                ]),
                hold_mode: Some("continuous".to_string()),
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["1".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result
            .warnings
            .iter()
            .any(|w| w.contains("holdKeys") && w.contains("较多")));
    }

    #[test]
    fn test_modifier_hotkey_format_valid() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "^a".to_string(),
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
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(!result.warnings.iter().any(|w| w.contains("格式可能不正确")));
    }

    #[test]
    fn test_modifier_hotkey_invalid_key_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "^INVALID".to_string(),
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
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.warnings.iter().any(|w| w.contains("格式可能不正确")));
    }
}
