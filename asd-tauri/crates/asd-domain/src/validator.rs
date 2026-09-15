use crate::config::{Config, GroupConfig, GroupItem, ModeData};
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

/// 单个间隔/延迟的「合理上界」（毫秒）。
///
/// 超过该值虽不违法（`u64` 类型合法、AHK 侧会照常执行），
/// 但通常意味着配置写错（如把秒当毫秒、或误填 `u64::MAX`），
/// 会导致分组启动后陷入肉眼不可察的超长等待。仅告警，不拦截。
const MAX_REASONABLE_INTERVAL_MS: u64 = 60_000;

/// 热键字符串的合理长度上限。
///
/// 正常 AHK 热键形如 `^!+F1`，远小于该值。超长热键往往来自配置损坏或自动化误写，
/// 会拖慢 AHK 侧解析。仅告警，不拦截。
const MAX_REASONABLE_HOTKEY_LEN: usize = 256;

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
    #[must_use]
    pub fn new() -> Self {
        Self {
            valid: true,
            errors: Vec::new(),
            warnings: Vec::new(),
        }
    }

    #[must_use]
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
/// `validate_hotkey_format` 和 `normalize_hotkey_for_comparison` 共享此列表
const VALID_HOTKEY_KEYS: &[&str] = &[
    "F1",
    "F2",
    "F3",
    "F4",
    "F5",
    "F6",
    "F7",
    "F8",
    "F9",
    "F10",
    "F11",
    "F12",
    "F13",
    "F14",
    "F15",
    "F16",
    "F17",
    "F18",
    "F19",
    "F20",
    "F21",
    "F22",
    "F23",
    "F24",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "Space",
    "Enter",
    "Esc",
    "Tab",
    "Backspace",
    "Delete",
    "Insert",
    "Up",
    "Down",
    "Left",
    "Right",
    "Home",
    "End",
    "PgUp",
    "PgDn",
    "LButton",
    "RButton",
    "MButton",
    "CapsLock",
    "ScrollLock",
    "Pause",
    "PrintScreen",
    "AppsKey",
    "WheelUp",
    "WheelDown",
    "WheelLeft",
    "WheelRight",
    "Numpad0",
    "Numpad1",
    "Numpad2",
    "Numpad3",
    "Numpad4",
    "Numpad5",
    "Numpad6",
    "Numpad7",
    "Numpad8",
    "Numpad9",
    "NumpadEnter",
    "NumpadDot",
    "NumpadAdd",
    "NumpadSub",
    "NumpadMult",
    "NumpadDiv",
    "NumpadDel",
    "NumpadIns",
    "NumpadClear",
    "NumpadUp",
    "NumpadDown",
    "NumpadLeft",
    "NumpadRight",
    "NumpadHome",
    "NumpadEnd",
    "NumpadPgUp",
    "NumpadPgDn",
    "Volume_Up",
    "Volume_Down",
    "Volume_Mute",
    "Browser_Back",
    "Browser_Forward",
    "Browser_Refresh",
    "Browser_Stop",
    "Browser_Search",
    "Browser_Favorites",
    "Browser_Home",
    "Media_Next",
    "Media_Prev",
    "Media_Stop",
    "Media_Play_Pause",
    "Launch_Mail",
    "Launch_Media",
    "Launch_App1",
    "Launch_App2",
];

pub struct ConfigValidator;

impl ConfigValidator {
    #[must_use]
    pub fn validate_config(config: &Config) -> ValidationResult {
        let mut result = Self::validate(&config.group_settings);

        Self::validate_control_hotkey(
            "_global",
            "emergency",
            &config.control_hotkeys.emergency,
            &mut result,
        );
        Self::validate_control_hotkey(
            "_global",
            "releaseAllHolds",
            &config.control_hotkeys.release_all_holds,
            &mut result,
        );
        Self::validate_control_hotkey(
            "_global",
            "showStatus",
            &config.control_hotkeys.show_status,
            &mut result,
        );
        Self::validate_control_hotkey(
            "_global",
            "toggleAll",
            &config.control_hotkeys.toggle_all,
            &mut result,
        );
        Self::validate_control_hotkey(
            "_global",
            "toggleHoldMode",
            &config.control_hotkeys.toggle_hold_mode,
            &mut result,
        );

        Self::validate_control_hotkey_conflicts(config, &mut result);

        if let Some(ref hs) = config.hold_settings {
            if hs.check_interval == 0 {
                result.add_error(
                    "_global",
                    "checkInterval",
                    "HoldSettings.checkInterval 不能为 0",
                );
            }
            if hs.press_speed == 0 {
                result.add_error("_global", "pressSpeed", "HoldSettings.pressSpeed 不能为 0");
            }
        }

        result
    }

    #[must_use]
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
            Self::validate_suspicious_mode_values(id, &group.mode_data, &mut result);
            Self::validate_cross_fields(id, group, &mut result);
        }

        result
    }

    fn validate_hotkey_format(group_id: &str, hotkey: &str, result: &mut ValidationResult) {
        if hotkey.is_empty() {
            return;
        }

        // BUG-6：超长热键通常是配置损坏或自动化误写。仅 warning——不排除存在
        // 合法的长热键（多修饰键组合、虚拟键名），升级为 error 会拒绝可用配置。
        let hotkey_len = hotkey.chars().count();
        if hotkey_len > MAX_REASONABLE_HOTKEY_LEN {
            result.add_warning(&format!(
                "[{group_id}] 热键长度 ({hotkey_len} 字符) 异常，正常 AHK 热键远短于此，请确认配置是否损坏"
            ));
        }

        let valid_prefixes = [
            "^", "!", "+", "#", "~", "*", "<^", ">^", "<!", ">!", "<+", ">+", "<#", ">#",
        ];
        let mut rest = hotkey;
        while let Some(&prefix) = valid_prefixes.iter().find(|p| rest.starts_with(*p)) {
            rest = &rest[prefix.len()..];
        }

        if rest.is_empty() {
            result.add_error(group_id, "hotkey", "热键必须包含非修饰符键");
            return;
        }

        // 使用 eq_ignore_ascii_case 进行大小写不敏感匹配，正确处理 PascalCase 键名如 "Space"/"space"
        //
        // 权衡取舍（仅 warning 而非 error）：
        // 热键键名可能包含 VALID_HOTKEY_KEYS 白名单之外、但 AHK 实际支持的自定义键名
        // （例如虚拟键、驱动注入的按键、或后续版本新增的键）。若此处升级为 error，
        // 会让这些"合法但不在白名单内"的配置整体被判定为无效，阻止应用启动/保存，
        // 对用户造成比"格式存疑"更大的破坏。因此只记录 warning 提示用户复核，
        // 保留配置的可用性；真正不可恢复的错误（如空热键、仅修饰符）仍在上方返回 error。
        if !VALID_HOTKEY_KEYS
            .iter()
            .any(|k| k.eq_ignore_ascii_case(rest))
        {
            result.add_warning(&format!(
                "[{group_id}] 热键 '{hotkey}' 格式可能不正确，请确认是否为有效的 AHK 热键"
            ));
        }
    }

    fn validate_control_hotkey(
        group_id: &str,
        field: &str,
        hotkey: &str,
        result: &mut ValidationResult,
    ) {
        if hotkey.is_empty() {
            result.add_error(group_id, field, &format!("控制热键 {field} 不能为空"));
        } else {
            Self::validate_hotkey_format(group_id, hotkey, result);
        }
    }

    fn validate_control_hotkey_conflicts(config: &Config, result: &mut ValidationResult) {
        let control_hotkeys: [(&str, &str); 5] = [
            ("emergency", &config.control_hotkeys.emergency),
            ("releaseAllHolds", &config.control_hotkeys.release_all_holds),
            ("showStatus", &config.control_hotkeys.show_status),
            ("toggleAll", &config.control_hotkeys.toggle_all),
            ("toggleHoldMode", &config.control_hotkeys.toggle_hold_mode),
        ];

        let mut seen: std::collections::HashMap<String, String> = std::collections::HashMap::new();
        for (field, hotkey) in control_hotkeys {
            if hotkey.is_empty() {
                continue;
            }
            let normalized = normalize_hotkey_for_comparison(hotkey);
            seen.entry(normalized)
                .or_insert_with(|| format!("_global:{field}"));
        }

        for (id, group) in &config.group_settings {
            if group.hotkey.is_empty() {
                continue;
            }
            let normalized = normalize_hotkey_for_comparison(&group.hotkey);
            if let Some(prev_label) = seen.get(&normalized) {
                result.add_error(
                    id,
                    "hotkey",
                    &format!("热键 '{}' 与控制热键 {} 重复", group.hotkey, prev_label),
                );
            }
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
        if group.mode == "hold" && group.hold_keys.as_ref().is_none_or(std::vec::Vec::is_empty) {
            result.add_warning(&format!("[{group_id}] hold 模式建议设置 holdKeys"));
        }

        if group.hold_keys.is_some() && group.hold_mode.is_none() {
            result.add_warning(&format!("[{group_id}] 设置了 holdKeys 但未指定 holdMode"));
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
                    "[{group_id}] keyPressDuration ({duration}ms) 过大，通常应小于 1000ms"
                ));
            }
        }
    }

    /// 对「合法但可疑」的模式数值发出 warning（BUG-6）。
    ///
    /// 与 `validate_mode_data` 的 error 校验互补：**只告警，不拦截**。
    /// 权衡取舍与热键白名单一致：AHK 侧对 `keys`/`intervals` 长度不匹配有 50ms 兜底、
    /// 对超大间隔也会照常执行，功能不会崩；把这些值升级为 error 会拒绝用户原本
    /// 可用的配置，破坏性大于收益。此处只提示用户复核。
    ///
    /// 覆盖两类可疑值：
    /// 1. 按键数与时间序列长度不匹配 —— 语义歧义，多半是漏写/多写了一个值；
    /// 2. 单个间隔/延迟超过 `MAX_REASONABLE_INTERVAL_MS` —— 多半是单位写错或误填 `u64::MAX`。
    fn validate_suspicious_mode_values(
        group_id: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        // (字段标签, 按键数, 时间序列)
        let mut series: Vec<(String, usize, &[u64])> = Vec::new();

        match mode_data {
            ModeData::Periodic(d) => {
                series.push((
                    "intervals".to_string(),
                    d.keys.len(),
                    d.intervals.as_slice(),
                ));
            }
            ModeData::Sequence(d) => {
                series.push(("delays".to_string(), d.keys.len(), d.delays.as_slice()));
            }
            ModeData::EnhancedPeriodic(d) => {
                series.push((
                    "intervals".to_string(),
                    d.press_keys.len(),
                    d.intervals.as_slice(),
                ));
            }
            ModeData::EnhancedSequence(d) => {
                series.push((
                    "pressDelays".to_string(),
                    d.press_keys.len(),
                    d.press_delays.as_slice(),
                ));
            }
            ModeData::JoystickPeriodic(d) => {
                series.push((
                    "intervals".to_string(),
                    d.press_keys.len(),
                    d.intervals.as_slice(),
                ));
            }
            ModeData::JoystickSequence(d) => {
                series.push((
                    "delays".to_string(),
                    d.press_keys.len(),
                    d.delays.as_slice(),
                ));
            }
            ModeData::Hybrid(d) => {
                Self::collect_group_item_series(&d.groups, &mut series);
            }
            ModeData::EnhancedHybrid(d) => {
                Self::collect_group_item_series(&d.groups, &mut series);
            }
            // hold 模式没有「按键数 ↔ 时间序列」的配对关系，不适用本检查
            ModeData::Hold(_) | ModeData::JoystickHold(_) => {}
        }

        for (label, keys_len, values) in series {
            // 1) 长度不匹配：两者都非空时才提示（空值已由 validate_mode_data 报错，
            //    避免对同一问题重复输出 error + warning）
            if keys_len > 0 && !values.is_empty() && keys_len != values.len() {
                result.add_warning(&format!(
                    "[{}] {} 的按键数 ({}) 与时间序列长度 ({}) 不匹配，将按 AHK 侧兜底值执行，请确认配置意图",
                    group_id,
                    label,
                    keys_len,
                    values.len()
                ));
            }

            // 2) 超长间隔/延迟
            if let Some(&max) = values.iter().max() {
                if max > MAX_REASONABLE_INTERVAL_MS {
                    result.add_warning(&format!(
                        "[{group_id}] {label} 中存在超长时间值 {max}ms（上限建议 {MAX_REASONABLE_INTERVAL_MS}ms），请确认单位是否为毫秒"
                    ));
                }
            }
        }
    }

    /// 从 hybrid / `enhanced_hybrid` 的子组中提取 (标签, 按键数, 时间序列)。
    fn collect_group_item_series<'a>(
        groups: &'a [GroupItem],
        out: &mut Vec<(String, usize, &'a [u64])>,
    ) {
        for (i, sub) in groups.iter().enumerate() {
            match sub {
                GroupItem::Periodic {
                    press_keys,
                    intervals,
                } => {
                    out.push((
                        format!("groups[{i}].intervals"),
                        press_keys.len(),
                        intervals.as_slice(),
                    ));
                }
                GroupItem::Sequence {
                    press_keys, delays, ..
                } => {
                    out.push((
                        format!("groups[{i}].delays"),
                        press_keys.len(),
                        delays.as_slice(),
                    ));
                }
            }
        }
    }

    // TD-023：本函数 294 行（阈值 100），是一个「按 mode 分派的子校验器集合」。
    // 拆它需要先把每个 mode 的子校验抽成函数并逐一对齐错误文案 —— 属于重构，
    // 不在「静态分析收紧」这次改动范围内，故先显式豁免并登记，避免它淹没新告警。
    #[allow(clippy::too_many_lines)]
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
                        let sub_label = format!("groups[{i}]");
                        match sub {
                            GroupItem::Periodic {
                                press_keys,
                                intervals,
                            } => {
                                if press_keys.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "periodic 子组需要至少一个按键",
                                    );
                                }
                                if intervals.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "periodic 子组需要至少一个间隔",
                                    );
                                }
                                if intervals.contains(&0) {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "periodic 子组间隔不能为 0",
                                    );
                                }
                            }
                            GroupItem::Sequence {
                                press_keys, delays, ..
                            } => {
                                if press_keys.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "sequence 子组需要至少一个按键",
                                    );
                                }
                                if delays.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "sequence 子组需要至少一个延迟",
                                    );
                                }
                                if delays.contains(&0) {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "sequence 子组延迟不能为 0",
                                    );
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
                        let sub_label = format!("groups[{i}]");
                        match sub {
                            GroupItem::Periodic {
                                press_keys,
                                intervals,
                            } => {
                                if press_keys.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "periodic 子组需要至少一个按键",
                                    );
                                }
                                if intervals.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "periodic 子组需要至少一个间隔",
                                    );
                                }
                                if intervals.contains(&0) {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "periodic 子组间隔不能为 0",
                                    );
                                }
                            }
                            GroupItem::Sequence {
                                press_keys, delays, ..
                            } => {
                                if press_keys.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "sequence 子组需要至少一个按键",
                                    );
                                }
                                if delays.is_empty() {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "sequence 子组需要至少一个延迟",
                                    );
                                }
                                if delays.contains(&0) {
                                    result.add_error(
                                        group_id,
                                        &sub_label,
                                        "sequence 子组延迟不能为 0",
                                    );
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
                            "[{group_id}] joystick_hold 模式未设置 holdDuration"
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
    prefix_parts.sort_unstable();
    let prefix = prefix_parts.join("");
    // F 键特殊处理：F1-F24 保持大写
    let normalized_rest =
        if rest.starts_with('F') && rest.len() > 1 && rest[1..].chars().all(|c| c.is_ascii_digit())
        {
            rest.to_uppercase()
        } else if let Some(canonical) = VALID_HOTKEY_KEYS
            .iter()
            .find(|k| k.eq_ignore_ascii_case(rest))
        {
            // 使用 VALID_HOTKEY_KEYS 统一列表进行大小写不敏感匹配，返回规范形式
            canonical.to_string()
        } else {
            rest.to_lowercase()
        };
    format!("{prefix}{normalized_rest}")
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

    // ===== BUG-6：可疑配置值的 warning（只告警不拦截） =====

    #[test]
    fn test_keys_intervals_length_mismatch_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "mismatch".to_string(),
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
                    keys: vec!["1".to_string(), "2".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        // 长度不匹配只告警，不改变 valid（AHK 侧有兜底，功能可用）
        assert!(result.is_valid(), "长度不匹配应仅告警，不判定为无效");
        assert!(
            result
                .warnings
                .iter()
                .any(|w| w.contains("不匹配") && w.contains("mismatch")),
            "应提示按键数与时间序列长度不匹配，实际 warnings: {:?}",
            result.warnings
        );
    }

    #[test]
    fn test_extreme_interval_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "huge".to_string(),
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
                    intervals: vec![u64::MAX],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(result.is_valid(), "超长间隔应仅告警，不判定为无效");
        assert!(
            result.warnings.iter().any(|w| w.contains("超长时间值")),
            "应提示超长时间值，实际 warnings: {:?}",
            result.warnings
        );
    }

    #[test]
    fn test_excessive_hotkey_length_warning() {
        let mut groups = IndexMap::new();
        groups.insert(
            "longkey".to_string(),
            GroupConfig {
                hotkey: format!("F1{}", "x".repeat(300)),
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
        assert!(result.is_valid(), "超长热键应仅告警，不判定为无效");
        assert!(
            result.warnings.iter().any(|w| w.contains("热键长度")),
            "应提示热键长度异常，实际 warnings: {:?}",
            result.warnings
        );
    }

    #[test]
    fn test_normal_mode_values_produce_no_suspicious_warning() {
        // 反向用例：长度匹配且间隔合理时**不应**产生新的 warning，
        // 防止上述告警误伤正常配置（避免过度告警淹没真实问题）
        let mut groups = IndexMap::new();
        groups.insert(
            "ok".to_string(),
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
                    keys: vec!["1".to_string(), "2".to_string()],
                    intervals: vec![50, 100],
                }),
            },
        );
        let result = ConfigValidator::validate(&groups);
        assert!(
            !result.warnings.iter().any(|w| w.contains("不匹配")),
            "长度匹配不应产生不匹配告警，实际 warnings: {:?}",
            result.warnings
        );
        assert!(
            !result.warnings.iter().any(|w| w.contains("超长时间值")),
            "合理间隔不应产生超长告警，实际 warnings: {:?}",
            result.warnings
        );
        assert!(
            !result.warnings.iter().any(|w| w.contains("热键长度")),
            "正常热键不应产生长度告警，实际 warnings: {:?}",
            result.warnings
        );
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
            .any(|e| e.field == "intervals" && e.message.contains('0')));
    }

    #[test]
    fn test_empty_hotkey_error() {
        let mut groups = IndexMap::new();
        groups.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: String::new(),
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
                mode: String::new(),
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

    #[test]
    fn test_control_hotkey_empty_error() {
        let mut config = Config::default();
        config.control_hotkeys.emergency = String::new();
        let result = ConfigValidator::validate_config(&config);
        assert!(!result.is_valid(), "控制热键为空应产生错误");
        assert!(result.errors.iter().any(|e| e.field == "emergency"));
    }

    #[test]
    fn test_control_hotkey_conflict_with_group_hotkey() {
        let mut config = Config::default();
        config.control_hotkeys.emergency = "F1".to_string();
        config
            .group_settings
            .insert("1".to_string(), make_periodic_group());
        let result = ConfigValidator::validate_config(&config);
        assert!(!result.is_valid(), "控制热键与分组热键冲突应产生错误");
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "hotkey" && e.message.contains("控制热键")));
    }

    #[test]
    fn test_default_config_is_valid() {
        let config = Config::default();
        let result = ConfigValidator::validate_config(&config);
        assert!(result.is_valid(), "默认配置不应有错误: {:?}", result.errors);
    }
}
