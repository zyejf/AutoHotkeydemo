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

/// 「按键序列 + 时间序列」这一对字段的**命名**。
///
/// 6 个简单模式共用 [`ValidationResult::check_keys_and_timings`] 的校验逻辑，
/// 彼此的差别全在这四个字符串里 —— 把它们打包成结构体而不是摊成 4 个参数，
/// 是为了让调用点能**具名**写出每个字段的用途（顺序错了会立刻看出来），
/// 同时不撞 `clippy::too_many_arguments`（该 lint **会把 `self` 算进去**）。
struct KeysTimingNaming<'a> {
    /// 错误文本的主语，形如 `"periodic 模式"` —— 调用方自带「模式 / 子组」字样，
    /// 校验函数不再补。
    subject: &'a str,
    /// `ValidationError::field` 里按键字段的路径（`keys` 或 `pressKeys`）。
    keys_field: &'a str,
    /// `ValidationError::field` 里时间序列字段的路径
    ///（`intervals` / `delays` / `pressDelays`）。
    timings_field: &'a str,
    /// 时间序列在错误文本里的叫法：`"间隔"` 或 `"延迟"`。
    timings_label: &'a str,
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

    /// 校验「按键序列 + 时间序列」这对字段 —— 6 个简单模式**共用的校验形状**。
    ///
    /// 三条规则，**顺序即错误产生的顺序**：按键非空 → 时间序列非空 → 时间值不含 0。
    /// 字段名与文案用词由 `naming` 决定，见 [`KeysTimingNaming`]。
    ///
    /// ⚠️ 只覆盖**形状相同**的那 6 个模式：`hold` / `joystick_hold` 没有时间序列，
    /// `hybrid` 系列的子组文案自带类型前缀（见
    /// [`ConfigValidator::validate_hybrid_subgroups`]），都不走这里 ——
    /// 强行统一任一侧都会让另一侧的信息变少。
    fn check_keys_and_timings(
        &mut self,
        group_id: &str,
        naming: &KeysTimingNaming<'_>,
        keys: &[String],
        timings: &[u64],
    ) {
        let KeysTimingNaming {
            subject,
            keys_field,
            timings_field,
            timings_label,
        } = naming;
        if keys.is_empty() {
            self.add_error(group_id, keys_field, &format!("{subject}需要至少一个按键"));
        }
        if timings.is_empty() {
            self.add_error(
                group_id,
                timings_field,
                &format!("{subject}需要至少一个{timings_label}"),
            );
        }
        if timings.contains(&0) {
            self.add_error(group_id, timings_field, &format!("{timings_label}不能为 0"));
        }
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

    /// 按 `mode` 分派到对应的子校验器。
    ///
    /// 拆分动机见 TD-023：原本这一个函数 **294 行**，是「按 mode 分派的子校验器
    /// 集合」，任一个 mode 的校验写错都要在 300 行里翻。现在每个 mode 一个函数，
    /// 各自都在 20 行以内。
    ///
    /// ⚠️ **新增 mode 要改两处**：这里加一个分支 **并且** 实现对应的 `validate_*`。
    /// 只改一处会让 `_` 分支兜住 —— 那时报的是「未知模式」，**不会校验
    /// `mode_data` 的内容**，配置错误会被静默放过。
    fn validate_mode_data(
        group_id: &str,
        mode: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        match mode {
            "periodic" => Self::validate_periodic(group_id, mode_data, result),
            "sequence" => Self::validate_sequence(group_id, mode_data, result),
            "hybrid" => Self::validate_hybrid(group_id, mode_data, result),
            "hold" => Self::validate_hold(group_id, mode_data, result),
            "enhanced_periodic" => Self::validate_enhanced_periodic(group_id, mode_data, result),
            "enhanced_sequence" => Self::validate_enhanced_sequence(group_id, mode_data, result),
            "enhanced_hybrid" => Self::validate_enhanced_hybrid(group_id, mode_data, result),
            "joystick_periodic" => Self::validate_joystick_periodic(group_id, mode_data, result),
            "joystick_sequence" => Self::validate_joystick_sequence(group_id, mode_data, result),
            "joystick_hold" => Self::validate_joystick_hold(group_id, mode_data, result),
            _ => result.add_error(group_id, "mode", &format!("未知模式: {mode}")),
        }
    }

    fn validate_periodic(group_id: &str, mode_data: &ModeData, result: &mut ValidationResult) {
        let ModeData::Periodic(data) = mode_data else {
            result.add_error(group_id, "mode_data", "periodic 模式数据类型不匹配");
            return;
        };
        result.check_keys_and_timings(
            group_id,
            &KeysTimingNaming {
                subject: "periodic 模式",
                keys_field: "keys",
                timings_field: "intervals",
                timings_label: "间隔",
            },
            &data.keys,
            &data.intervals,
        );
    }

    fn validate_sequence(group_id: &str, mode_data: &ModeData, result: &mut ValidationResult) {
        let ModeData::Sequence(data) = mode_data else {
            result.add_error(group_id, "mode_data", "sequence 模式数据类型不匹配");
            return;
        };
        result.check_keys_and_timings(
            group_id,
            &KeysTimingNaming {
                subject: "sequence 模式",
                keys_field: "keys",
                timings_field: "delays",
                timings_label: "延迟",
            },
            &data.keys,
            &data.delays,
        );
    }

    fn validate_enhanced_periodic(
        group_id: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        let ModeData::EnhancedPeriodic(data) = mode_data else {
            result.add_error(
                group_id,
                "mode_data",
                "enhanced_periodic 模式数据类型不匹配",
            );
            return;
        };
        result.check_keys_and_timings(
            group_id,
            &KeysTimingNaming {
                subject: "enhanced_periodic 模式",
                keys_field: "pressKeys",
                timings_field: "intervals",
                timings_label: "间隔",
            },
            &data.press_keys,
            &data.intervals,
        );
    }

    fn validate_enhanced_sequence(
        group_id: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        let ModeData::EnhancedSequence(data) = mode_data else {
            result.add_error(
                group_id,
                "mode_data",
                "enhanced_sequence 模式数据类型不匹配",
            );
            return;
        };
        result.check_keys_and_timings(
            group_id,
            &KeysTimingNaming {
                subject: "enhanced_sequence 模式",
                keys_field: "pressKeys",
                timings_field: "pressDelays",
                timings_label: "延迟",
            },
            &data.press_keys,
            &data.press_delays,
        );
    }

    fn validate_joystick_periodic(
        group_id: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        let ModeData::JoystickPeriodic(data) = mode_data else {
            result.add_error(
                group_id,
                "mode_data",
                "joystick_periodic 模式数据类型不匹配",
            );
            return;
        };
        result.check_keys_and_timings(
            group_id,
            &KeysTimingNaming {
                subject: "joystick_periodic 模式",
                keys_field: "pressKeys",
                timings_field: "intervals",
                timings_label: "间隔",
            },
            &data.press_keys,
            &data.intervals,
        );
    }

    fn validate_joystick_sequence(
        group_id: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        let ModeData::JoystickSequence(data) = mode_data else {
            result.add_error(
                group_id,
                "mode_data",
                "joystick_sequence 模式数据类型不匹配",
            );
            return;
        };
        result.check_keys_and_timings(
            group_id,
            &KeysTimingNaming {
                subject: "joystick_sequence 模式",
                keys_field: "pressKeys",
                timings_field: "delays",
                timings_label: "延迟",
            },
            &data.press_keys,
            &data.delays,
        );
    }

    fn validate_hybrid(group_id: &str, mode_data: &ModeData, result: &mut ValidationResult) {
        let ModeData::Hybrid(data) = mode_data else {
            result.add_error(group_id, "mode_data", "hybrid 模式数据类型不匹配");
            return;
        };
        if data.groups.is_empty() {
            result.add_error(group_id, "groups", "hybrid 模式需要至少一个子组");
        }
        Self::validate_hybrid_subgroups(group_id, &data.groups, result);
    }

    fn validate_enhanced_hybrid(
        group_id: &str,
        mode_data: &ModeData,
        result: &mut ValidationResult,
    ) {
        let ModeData::EnhancedHybrid(data) = mode_data else {
            result.add_error(group_id, "mode_data", "enhanced_hybrid 模式数据类型不匹配");
            return;
        };
        if data.groups.is_empty() {
            result.add_error(group_id, "groups", "enhanced_hybrid 模式需要至少一个子组");
        }
        Self::validate_hybrid_subgroups(group_id, &data.groups, result);
    }

    /// 校验 `hybrid` / `enhanced_hybrid` 的子组列表 —— **两个模式共用同一套规则与文案**。
    ///
    /// ⚠️ 子组错误的 `field` 只有 `groups[i]`，**不含子组类型**，所以错误文本必须
    /// 自带「periodic 子组」/「sequence 子组」才能定位 —— 这与顶层恰恰相反：
    /// 顶层的 `field` 已经是 `keys` / `intervals` 这类具名字段，文本里就只说
    ///「间隔不能为 0」。两种文案风格不一是**有意为之**，统一任一侧都会让
    /// 另一侧少一块信息。
    fn validate_hybrid_subgroups(
        group_id: &str,
        groups: &[GroupItem],
        result: &mut ValidationResult,
    ) {
        for (i, sub) in groups.iter().enumerate() {
            let sub_label = format!("groups[{i}]");
            match sub {
                GroupItem::Periodic {
                    press_keys,
                    intervals,
                } => {
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
                GroupItem::Sequence {
                    press_keys, delays, ..
                } => {
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
    }

    fn validate_hold(group_id: &str, mode_data: &ModeData, result: &mut ValidationResult) {
        // holdDuration=0 表示无限保持（直到主动停止），是合法值
        // holdDuration>0 表示固定时长保持，超时后自动释放
        // 此处无需额外校验，holdDuration 的非负性由类型系统保证（u64）
        if !matches!(mode_data, ModeData::Hold(_)) {
            result.add_error(group_id, "mode_data", "hold 模式数据类型不匹配");
        }
    }

    fn validate_joystick_hold(group_id: &str, mode_data: &ModeData, result: &mut ValidationResult) {
        let ModeData::JoystickHold(data) = mode_data else {
            result.add_error(group_id, "mode_data", "joystick_hold 模式数据类型不匹配");
            return;
        };
        if data.hold_duration.unwrap_or(0) == 0 {
            result.add_warning(&format!(
                "[{group_id}] joystick_hold 模式未设置 holdDuration"
            ));
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

    // TD-023 拆分 `validate_mode_data` 时补的**特征测试**（共 7 条，见下方）。
    //
    // ⚠️ 补它们的直接原因：这 10 个 mode 的**错误文案此前一条测试都没有**
    //（全仓 grep 零命中）。也就是说，把文案写错、或把某个 mode 分支接到别的
    // `ModeData` 变体上，整个测试套件都是绿的 —— 那次重构原本**没有任何回归保护**，
    // 只能临时写一份「新旧实现逐条比对」的差量测试来兜（165 组输入全一致）。
    //
    // 按**关注点**拆成 7 条而不是写成一个大测试：合成一条会撞
    // `clippy::too_many_lines`（241 行 / 上限 100），而且失败时定位更慢。
    // 7 条共享 `mode_data_msg_` 前缀 —— 阳性对照靠这个前缀一次跑全。
    //
    // 改动校验规则、字段名或文案时必须同步更新这些测试 ——
    // 这些字符串是**给终端用户看的**，不是内部实现细节。

    /// 一个「不属于其它任何模式」的 `ModeData`，专门用来触发类型不匹配分支。
    fn hold_mode_data() -> ModeData {
        ModeData::Hold(HoldData {
            hold_duration: 0,
            auto_repeat: None,
            repeat_interval: None,
        })
    }

    fn one_key() -> Vec<String> {
        vec!["a".to_string()]
    }

    /// `hybrid` 与 `enhanced_hybrid` 的数据结构不同但子组校验逻辑共用，
    /// 这里按 mode 名造外层，让两个 mode 能跑同一批断言。
    fn hybrid_mode_data(mode: &str, groups: Vec<GroupItem>) -> ModeData {
        match mode {
            "hybrid" => ModeData::Hybrid(HybridData {
                groups,
                seq_interval: None,
            }),
            _ => ModeData::EnhancedHybrid(EnhancedHybridData {
                groups,
                seq_interval: None,
            }),
        }
    }

    /// ① 每个 mode 配上一个「不是自己」的 `ModeData` —— 都应只报类型不匹配。
    ///    这一条专门防「mode 分支接到别的变体上」这类重构事故。
    #[test]
    fn mode_data_msg_type_mismatch() {
        for (mode, data) in [
            ("periodic", hold_mode_data()),
            ("sequence", hold_mode_data()),
            ("hybrid", hold_mode_data()),
            (
                "hold",
                ModeData::Periodic(PeriodicData {
                    keys: one_key(),
                    intervals: vec![10],
                }),
            ),
            ("enhanced_periodic", hold_mode_data()),
            ("enhanced_sequence", hold_mode_data()),
            ("enhanced_hybrid", hold_mode_data()),
            ("joystick_periodic", hold_mode_data()),
            ("joystick_sequence", hold_mode_data()),
            ("joystick_hold", hold_mode_data()),
        ] {
            let mut r = ValidationResult::new();
            ConfigValidator::validate_mode_data("g", mode, &data, &mut r);
            assert_eq!(r.errors.len(), 1, "mode={mode} 应只报一条类型不匹配");
            assert_eq!(r.errors[0].field, "mode_data", "mode={mode}");
            assert_eq!(r.errors[0].message, format!("{mode} 模式数据类型不匹配"));
        }
    }

    /// ② 「按键非空 / 时间序列非空」两条规则的文案，逐个 mode 钉住字段名。
    ///    6 个模式共用同一段校验逻辑，差别全在字段名与「间隔 / 延迟」的叫法上。
    #[test]
    fn mode_data_msg_empty_keys_and_timings() {
        let empty_cases: Vec<(&str, ModeData, &str, &str, &str)> = vec![
            (
                "periodic",
                ModeData::Periodic(PeriodicData {
                    keys: vec![],
                    intervals: vec![],
                }),
                "keys",
                "intervals",
                "间隔",
            ),
            (
                "sequence",
                ModeData::Sequence(SequenceData {
                    keys: vec![],
                    delays: vec![],
                }),
                "keys",
                "delays",
                "延迟",
            ),
            (
                "enhanced_periodic",
                ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                    press_keys: vec![],
                    intervals: vec![],
                }),
                "pressKeys",
                "intervals",
                "间隔",
            ),
            (
                "enhanced_sequence",
                ModeData::EnhancedSequence(EnhancedSequenceData {
                    press_keys: vec![],
                    press_delays: vec![],
                }),
                "pressKeys",
                "pressDelays",
                "延迟",
            ),
            (
                "joystick_periodic",
                ModeData::JoystickPeriodic(JoystickPeriodicData {
                    press_keys: vec![],
                    intervals: vec![],
                    joystick_id: None,
                }),
                "pressKeys",
                "intervals",
                "间隔",
            ),
            (
                "joystick_sequence",
                ModeData::JoystickSequence(JoystickSequenceData {
                    press_keys: vec![],
                    delays: vec![],
                    joystick_id: None,
                }),
                "pressKeys",
                "delays",
                "延迟",
            ),
        ];
        for (mode, data, keys_field, timings_field, label) in &empty_cases {
            let mut r = ValidationResult::new();
            ConfigValidator::validate_mode_data("g", mode, data, &mut r);
            assert_eq!(r.errors.len(), 2, "mode={mode} 应报按键与时间序列两条");
            assert_eq!(r.errors[0].field, *keys_field, "mode={mode} 按键字段名");
            assert_eq!(r.errors[0].message, format!("{mode} 模式需要至少一个按键"));
            assert_eq!(r.errors[1].field, *timings_field, "mode={mode} 时间字段名");
            assert_eq!(
                r.errors[1].message,
                format!("{mode} 模式需要至少一个{label}")
            );
        }
    }

    /// ③ 时间值为 0：顶层文案里**不带** mode 前缀（`field` 已指明是哪个字段）。
    #[test]
    fn mode_data_msg_zero_timing() {
        let zero_cases: Vec<(&str, ModeData, &str, &str)> = vec![
            (
                "periodic",
                ModeData::Periodic(PeriodicData {
                    keys: one_key(),
                    intervals: vec![0],
                }),
                "intervals",
                "间隔",
            ),
            (
                "sequence",
                ModeData::Sequence(SequenceData {
                    keys: one_key(),
                    delays: vec![0],
                }),
                "delays",
                "延迟",
            ),
            (
                "enhanced_sequence",
                ModeData::EnhancedSequence(EnhancedSequenceData {
                    press_keys: one_key(),
                    press_delays: vec![0],
                }),
                "pressDelays",
                "延迟",
            ),
            (
                "joystick_periodic",
                ModeData::JoystickPeriodic(JoystickPeriodicData {
                    press_keys: one_key(),
                    intervals: vec![0],
                    joystick_id: None,
                }),
                "intervals",
                "间隔",
            ),
        ];
        for (mode, data, timings_field, label) in &zero_cases {
            let mut r = ValidationResult::new();
            ConfigValidator::validate_mode_data("g", mode, data, &mut r);
            assert_eq!(r.errors.len(), 1, "mode={mode} 应只报零值一条");
            assert_eq!(r.errors[0].field, *timings_field, "mode={mode}");
            assert_eq!(r.errors[0].message, format!("{label}不能为 0"));
        }
    }

    /// ④ 子组：`field` 只有 `groups[i]`（不含子组类型），所以文案必须自带类型。
    ///    `hybrid` 与 `enhanced_hybrid` 共用这段逻辑，两个 mode 都验一遍。
    #[test]
    fn mode_data_msg_subgroups() {
        //    三个子组刻意错开形状，一次覆盖全部 5 条涉及到的文案：
        //    [0] 按键空 + 间隔含 0（非空）→ 触发「至少一个按键」+「间隔不能为 0」；
        //    [1] 按键空 + 延迟为空     → 触发「至少一个按键」+「至少一个延迟」；
        //    [2] 按键非空 + 间隔为空   → 只触发「至少一个间隔」。
        let bad_subs = || {
            vec![
                GroupItem::Periodic {
                    press_keys: vec![],
                    intervals: vec![0],
                },
                GroupItem::Sequence {
                    press_keys: vec![],
                    delays: vec![],
                    seq_interval: None,
                },
                GroupItem::Periodic {
                    press_keys: one_key(),
                    intervals: vec![],
                },
            ]
        };
        for mode in ["hybrid", "enhanced_hybrid"] {
            let data = hybrid_mode_data(mode, bad_subs());
            let mut r = ValidationResult::new();
            ConfigValidator::validate_mode_data("g", mode, &data, &mut r);
            let got: Vec<(&str, &str)> = r
                .errors
                .iter()
                .map(|e| (e.field.as_str(), e.message.as_str()))
                .collect();
            assert_eq!(
                got,
                vec![
                    ("groups[0]", "periodic 子组需要至少一个按键"),
                    ("groups[0]", "periodic 子组间隔不能为 0"),
                    ("groups[1]", "sequence 子组需要至少一个按键"),
                    ("groups[1]", "sequence 子组需要至少一个延迟"),
                    ("groups[2]", "periodic 子组需要至少一个间隔"),
                ],
                "mode={mode} 子组文案"
            );
        }
    }

    /// ⑤ 空子组列表：报在 `groups` 字段上（不是某个 `groups[i]`）。
    #[test]
    fn mode_data_msg_empty_subgroups() {
        for (mode, expect) in [
            ("hybrid", "hybrid 模式需要至少一个子组"),
            ("enhanced_hybrid", "enhanced_hybrid 模式需要至少一个子组"),
        ] {
            let data = hybrid_mode_data(mode, vec![]);
            let mut r = ValidationResult::new();
            ConfigValidator::validate_mode_data("g", mode, &data, &mut r);
            assert_eq!(r.errors.len(), 1, "mode={mode}");
            assert_eq!(r.errors[0].field, "groups");
            assert_eq!(r.errors[0].message, expect);
        }
    }

    /// ⑥ `joystick_hold` 未设置 holdDuration 是**告警不是错误** —— 不是错误这点
    ///    很容易在重构时被顺手改成 `add_error`，钉住它。
    #[test]
    fn mode_data_msg_joystick_hold_missing_duration_is_warning() {
        let js_hold = ModeData::JoystickHold(JoystickHoldData {
            hold_duration: None,
            auto_repeat: None,
            repeat_interval: None,
            joystick_id: None,
        });
        let mut r = ValidationResult::new();
        ConfigValidator::validate_mode_data("g", "joystick_hold", &js_hold, &mut r);
        assert!(r.errors.is_empty(), "缺 holdDuration 不应报错");
        assert_eq!(
            r.warnings,
            vec!["[g] joystick_hold 模式未设置 holdDuration"]
        );
    }

    /// ⑦ 未知模式：只报 `mode` 字段，**不校验** `mode_data` 的内容
    ///    （这条是 `_` 分支兜底，别把它改成会去校验内容的版本）。
    #[test]
    fn mode_data_msg_unknown_mode_only_reports_mode_field() {
        let mut r = ValidationResult::new();
        ConfigValidator::validate_mode_data("g", "bogus_mode", &hold_mode_data(), &mut r);
        assert_eq!(r.errors.len(), 1);
        assert_eq!(r.errors[0].field, "mode");
        assert_eq!(r.errors[0].message, "未知模式: bogus_mode");
    }

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
