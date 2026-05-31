use asd_domain::config::*;
use asd_domain::models::*;
use asd_domain::validator::*;
use indexmap::IndexMap;

fn make_periodic_config() -> GroupConfig {
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

fn make_sequence_config() -> GroupConfig {
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

fn make_hybrid_config() -> GroupConfig {
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

fn make_hold_config() -> GroupConfig {
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

fn make_enhanced_periodic_config() -> GroupConfig {
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

fn make_enhanced_sequence_config() -> GroupConfig {
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

fn make_enhanced_hybrid_config() -> GroupConfig {
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

fn make_joystick_periodic_config() -> GroupConfig {
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

fn make_joystick_sequence_config() -> GroupConfig {
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

fn make_joystick_hold_config() -> GroupConfig {
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

fn make_full_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert("1".to_string(), make_periodic_config());
    group_settings.insert("2".to_string(), make_hold_config());

    Config {
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
    }
}

#[test]
fn test_config_full_roundtrip() {
    let config = make_full_config();
    let json = serde_json::to_string_pretty(&config).unwrap();
    let decoded: Config = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded.control_hotkeys.emergency, "F10");
    assert_eq!(decoded.control_hotkeys.release_all_holds, "^r");
    assert_eq!(decoded.group_settings.len(), 2);
    assert!(decoded.group_settings.contains_key("1"));
    assert!(decoded.group_settings.contains_key("2"));
    assert!(decoded.hold_settings.is_some());
    assert_eq!(decoded.hold_settings.as_ref().unwrap().check_interval, 50);
    assert_eq!(decoded.version.as_deref(), Some("3.0"));
    assert_eq!(decoded.last_modified.as_deref(), Some("2025-01-01T00:00:00"));
}

#[test]
fn test_config_minimal_roundtrip() {
    let config = Config::default();
    let json = serde_json::to_string(&config).unwrap();
    let decoded: Config = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded.control_hotkeys.emergency, "F10");
    assert!(decoded.group_settings.is_empty());
    assert!(decoded.hold_settings.is_some());
    assert!(decoded.last_modified.is_none());
}

#[test]
fn test_config_without_optional_fields() {
    let json = r#"{
        "CONTROL_HOTKEYS": {
            "emergency": "F10",
            "releaseAllHolds": "^r",
            "showStatus": "^0",
            "toggleAll": "^1",
            "toggleHoldMode": "^h"
        },
        "GroupSettings": {}
    }"#;
    let config: Config = serde_json::from_str(json).unwrap();
    assert!(config.hold_settings.is_none());
    assert!(config.last_modified.is_none());
    assert!(config.version.is_none());
}

#[test]
fn test_config_hold_settings_roundtrip() {
    let mut config = Config::default();
    config.hold_settings = Some(HoldSettings {
        allow_overlap: true,
        check_interval: 100,
        debounce_delay: 50,
        press_speed: 120,
        release_on_emergency: false,
    });
    let json = serde_json::to_string(&config).unwrap();
    let decoded: Config = serde_json::from_str(&json).unwrap();
    let hs = decoded.hold_settings.unwrap();
    assert!(hs.allow_overlap);
    assert_eq!(hs.check_interval, 100);
    assert_eq!(hs.debounce_delay, 50);
    assert_eq!(hs.press_speed, 120);
    assert!(!hs.release_on_emergency);
}

#[test]
fn test_mode_data_periodic_roundtrip() {
    let gc = make_periodic_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.hotkey, "F1");
    assert_eq!(decoded.mode, "periodic");
    match &decoded.mode_data {
        ModeData::Periodic(data) => {
            assert_eq!(data.keys, vec!["1", "2"]);
            assert_eq!(data.intervals, vec![50, 60]);
        }
        other => panic!("Expected Periodic, got {other:?}"),
    }
}

#[test]
fn test_mode_data_sequence_roundtrip() {
    let gc = make_sequence_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::Sequence(data) => {
            assert_eq!(data.keys, vec!["A", "S"]);
            assert_eq!(data.delays, vec![100, 200]);
        }
        other => panic!("Expected Sequence, got {other:?}"),
    }
}

#[test]
fn test_mode_data_hybrid_roundtrip() {
    let gc = make_hybrid_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::Hybrid(data) => {
            assert_eq!(data.groups.len(), 2);
            assert_eq!(data.seq_interval, Some(100));
        }
        other => panic!("Expected Hybrid, got {other:?}"),
    }
}

#[test]
fn test_mode_data_hold_roundtrip() {
    let gc = make_hold_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::Hold(data) => {
            assert_eq!(data.hold_duration, 500);
            assert_eq!(data.auto_repeat, Some(true));
            assert_eq!(data.repeat_interval, Some(100));
        }
        other => panic!("Expected Hold, got {other:?}"),
    }
    assert_eq!(decoded.hold_keys, Some(vec!["Shift".to_string()]));
    assert_eq!(decoded.hold_mode, Some("continuous".to_string()));
}

#[test]
fn test_mode_data_enhanced_periodic_roundtrip() {
    let gc = make_enhanced_periodic_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::EnhancedPeriodic(data) => {
            assert_eq!(data.press_keys, vec!["Space", "1"]);
            assert_eq!(data.intervals, vec![50, 60]);
        }
        other => panic!("Expected EnhancedPeriodic, got {other:?}"),
    }
}

#[test]
fn test_mode_data_enhanced_sequence_roundtrip() {
    let gc = make_enhanced_sequence_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::EnhancedSequence(data) => {
            assert_eq!(data.press_keys, vec!["1", "2"]);
            assert_eq!(data.press_delays, vec![100, 200]);
        }
        other => panic!("Expected EnhancedSequence, got {other:?}"),
    }
}

#[test]
fn test_mode_data_enhanced_hybrid_roundtrip() {
    let gc = make_enhanced_hybrid_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::EnhancedHybrid(data) => {
            assert_eq!(data.groups.len(), 1);
            assert_eq!(data.seq_interval, Some(50));
        }
        other => panic!("Expected EnhancedHybrid, got {other:?}"),
    }
}

#[test]
fn test_mode_data_joystick_periodic_roundtrip() {
    let gc = make_joystick_periodic_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::JoystickPeriodic(data) => {
            assert_eq!(data.press_keys, vec!["1"]);
            assert_eq!(data.intervals, vec![50]);
            assert_eq!(data.joystick_id, Some(0));
        }
        other => panic!("Expected JoystickPeriodic, got {other:?}"),
    }
}

#[test]
fn test_mode_data_joystick_sequence_roundtrip() {
    let gc = make_joystick_sequence_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::JoystickSequence(data) => {
            assert_eq!(data.press_keys, vec!["A"]);
            assert_eq!(data.delays, vec![100]);
            assert_eq!(data.joystick_id, Some(1));
        }
        other => panic!("Expected JoystickSequence, got {other:?}"),
    }
}

#[test]
fn test_mode_data_joystick_hold_roundtrip() {
    let gc = make_joystick_hold_config();
    let json = serde_json::to_string(&gc).unwrap();
    let decoded: GroupConfig = serde_json::from_str(&json).unwrap();
    match &decoded.mode_data {
        ModeData::JoystickHold(data) => {
            assert_eq!(data.hold_duration, Some(500));
            assert_eq!(data.auto_repeat, Some(false));
            assert_eq!(data.repeat_interval, None);
            assert_eq!(data.joystick_id, Some(2));
        }
        other => panic!("Expected JoystickHold, got {other:?}"),
    }
}

#[test]
fn test_skill_group_from_group_config_with_name() {
    let id = "1".to_string();
    let config = make_periodic_config();
    let group: SkillGroup = (&id, &config).into();

    assert_eq!(group.id, "1");
    assert_eq!(group.name, "周期按键");
    assert_eq!(group.hotkey, "F1");
    assert!(!group.active);
    assert_eq!(group.mode, "periodic");
    assert_eq!(group.key_press_duration, 10);
}

#[test]
fn test_skill_group_from_group_config_without_name() {
    let id = "5".to_string();
    let config = make_sequence_config();
    let group: SkillGroup = (&id, &config).into();

    assert_eq!(group.name, "5");
    assert_eq!(group.key_press_duration, 0);
}

#[test]
fn test_skill_group_from_hold_config() {
    let id = "4".to_string();
    let config = make_hold_config();
    let group: SkillGroup = (&id, &config).into();

    assert_eq!(group.hold_keys, Some(vec!["Shift".to_string()]));
    assert_eq!(group.hold_mode, Some("continuous".to_string()));
}

#[test]
fn test_skill_group_serialization_all_modes() {
    let configs: Vec<(&str, GroupConfig)> = vec![
        ("1", make_periodic_config()),
        ("2", make_sequence_config()),
        ("3", make_hybrid_config()),
        ("4", make_hold_config()),
        ("5", make_enhanced_periodic_config()),
        ("6", make_enhanced_sequence_config()),
        ("7", make_enhanced_hybrid_config()),
        ("8", make_joystick_periodic_config()),
        ("9", make_joystick_sequence_config()),
        ("10", make_joystick_hold_config()),
    ];

    for (id, config) in &configs {
        let group: SkillGroup = (&id.to_string(), config).into();
        let json = serde_json::to_string(&group).unwrap();
        let decoded: SkillGroup = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.id, *id);
        assert_eq!(decoded.mode, config.mode);
    }
}

#[test]
fn test_skill_group_mode_data_roundtrip_periodic() {
    let id = "1".to_string();
    let config = make_periodic_config();
    let group: SkillGroup = (&id, &config).into();
    let json = serde_json::to_string(&group).unwrap();
    let decoded: SkillGroup = serde_json::from_str(&json).unwrap();

    match &decoded.mode_data {
        ModeData::Periodic(data) => {
            assert_eq!(data.keys, vec!["1", "2"]);
            assert_eq!(data.intervals, vec![50, 60]);
        }
        other => panic!("Expected Periodic, got {other:?}"),
    }
}

#[test]
fn test_config_validator_valid_multi_group() {
    let mut groups = IndexMap::new();
    groups.insert("1".to_string(), make_periodic_config());
    groups.insert("2".to_string(), make_sequence_config());
    groups.insert("3".to_string(), make_hybrid_config());

    let result = ConfigValidator::validate(&groups);
    assert!(result.is_valid(), "多组有效配置不应有错误: {:?}", result.errors);
}

#[test]
fn test_config_validator_empty_hotkey_and_mode() {
    let mut groups = IndexMap::new();
    groups.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "".to_string(),
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
    assert!(result.errors.iter().any(|e| e.field == "hotkey"));
    assert!(result.errors.iter().any(|e| e.field == "mode"));
}

#[test]
fn test_config_validator_cross_field_hold_keys_without_hold_mode() {
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
fn test_config_validator_cross_field_large_key_press_duration() {
    let mut groups = IndexMap::new();
    groups.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(5000),
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
    assert!(result.warnings.iter().any(|w| w.contains("keyPressDuration")));
}

#[test]
fn test_config_validator_duplicate_hotkeys_across_groups() {
    let mut groups = IndexMap::new();
    groups.insert("1".to_string(), make_periodic_config());
    groups.insert(
        "2".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: None,
            name: None,
            mode: "sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Sequence(SequenceData {
                keys: vec!["2".to_string()],
                delays: vec![100],
            }),
        },
    );
    let result = ConfigValidator::validate(&groups);
    assert!(!result.is_valid());
    assert!(result.errors.iter().any(|e| e.field == "hotkey" && e.message.contains("重复")));
}

#[test]
fn test_config_validator_hold_mode_without_hold_keys() {
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
fn test_config_validator_periodic_zero_interval() {
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
                intervals: vec![0],
            }),
        },
    );
    let result = ConfigValidator::validate(&groups);
    assert!(!result.is_valid());
    assert!(result.errors.iter().any(|e| e.field == "intervals"));
}

#[test]
fn test_config_validator_mode_data_mismatch_periodic() {
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
    assert!(result.errors.iter().any(|e| e.field == "mode_data"));
}

#[test]
fn test_config_validator_unknown_mode() {
    let mut groups = IndexMap::new();
    groups.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: None,
            name: None,
            mode: "nonexistent".to_string(),
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
fn test_config_validator_empty_groups_warning() {
    let groups = IndexMap::new();
    let result = ConfigValidator::validate(&groups);
    assert!(result.is_valid());
    assert!(!result.warnings.is_empty());
}

#[test]
fn test_watchdog_state_enum_all_variants_roundtrip() {
    let states = vec![
        WatchdogStateEnum::Idle,
        WatchdogStateEnum::Starting,
        WatchdogStateEnum::Running,
        WatchdogStateEnum::Hung,
        WatchdogStateEnum::Restarting,
        WatchdogStateEnum::Recovering,
        WatchdogStateEnum::Failed,
    ];
    for state in &states {
        let json = serde_json::to_string(state).unwrap();
        let decoded: WatchdogStateEnum = serde_json::from_str(&json).unwrap();
        assert_eq!(*state, decoded);
    }
}

#[test]
fn test_watchdog_state_enum_json_representation() {
    let json = serde_json::to_string(&WatchdogStateEnum::Running).unwrap();
    assert!(json.contains("Running"));

    let json = serde_json::to_string(&WatchdogStateEnum::Hung).unwrap();
    assert!(json.contains("Hung"));
}

#[test]
fn test_group_config_deserialize_from_json_string() {
    let json = r#"{"hotkey":"F1","mode":"periodic","keys":["1","2"],"intervals":[50,60]}"#;
    let gc: GroupConfig = serde_json::from_str(json).unwrap();
    assert_eq!(gc.hotkey, "F1");
    assert_eq!(gc.mode, "periodic");
    assert!(gc.name.is_none());
    assert!(gc.key_press_duration.is_none());
}

#[test]
fn test_group_config_deserialize_with_all_optional_fields() {
    let json = r#"{
        "hotkey":"F1",
        "mode":"periodic",
        "name":"测试组",
        "keyPressDuration":20,
        "holdKeys":["Shift"],
        "holdMode":"continuous",
        "holdPattern":"toggle",
        "holdTriggers":[{"type":"press"}],
        "keys":["1"],
        "intervals":[50]
    }"#;
    let gc: GroupConfig = serde_json::from_str(json).unwrap();
    assert_eq!(gc.name, Some("测试组".to_string()));
    assert_eq!(gc.key_press_duration, Some(20));
    assert_eq!(gc.hold_keys, Some(vec!["Shift".to_string()]));
    assert_eq!(gc.hold_mode, Some("continuous".to_string()));
    assert_eq!(gc.hold_pattern, Some("toggle".to_string()));
    assert!(gc.hold_triggers.is_some());
}

#[test]
fn test_group_config_serialize_skip_none_fields() {
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
    assert!(!json.contains("keyPressDuration"));
    assert!(!json.contains("holdKeys"));
    assert!(!json.contains("holdMode"));
    assert!(!json.contains("holdPattern"));
    assert!(!json.contains("holdTriggers"));
    assert!(!json.contains("name"));
}

#[test]
fn test_group_config_deserialize_missing_hotkey() {
    let json = r#"{"mode":"periodic","keys":["1"],"intervals":[50]}"#;
    let result = serde_json::from_str::<GroupConfig>(json);
    assert!(result.is_err());
}

#[test]
fn test_group_config_deserialize_missing_mode() {
    let json = r#"{"hotkey":"F1","keys":["1"],"intervals":[50]}"#;
    let result = serde_json::from_str::<GroupConfig>(json);
    assert!(result.is_err());
}

#[test]
fn test_group_config_deserialize_unknown_mode() {
    let json = r#"{"hotkey":"F1","mode":"nonexistent","keys":["1"]}"#;
    let result = serde_json::from_str::<GroupConfig>(json);
    assert!(result.is_err());
}

#[test]
fn test_validation_result_serialization_roundtrip() {
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
fn test_validation_error_display() {
    let err = ValidationError {
        group_id: "1".to_string(),
        field: "keys".to_string(),
        message: "不能为空".to_string(),
    };
    assert_eq!(format!("{err}"), "[1] keys: 不能为空");
}

#[test]
fn test_control_hotkeys_roundtrip() {
    let hk = ControlHotkeys {
        emergency: "F10".to_string(),
        release_all_holds: "^r".to_string(),
        show_status: "^0".to_string(),
        toggle_all: "^1".to_string(),
        toggle_hold_mode: "^h".to_string(),
    };
    let json = serde_json::to_string(&hk).unwrap();
    let decoded: ControlHotkeys = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.emergency, "F10");
    assert_eq!(decoded.release_all_holds, "^r");
    assert_eq!(decoded.show_status, "^0");
    assert_eq!(decoded.toggle_all, "^1");
    assert_eq!(decoded.toggle_hold_mode, "^h");
}

#[test]
fn test_hold_settings_roundtrip() {
    let hs = HoldSettings {
        allow_overlap: true,
        check_interval: 100,
        debounce_delay: 50,
        press_speed: 120,
        release_on_emergency: false,
    };
    let json = serde_json::to_string(&hs).unwrap();
    let decoded: HoldSettings = serde_json::from_str(&json).unwrap();
    assert!(decoded.allow_overlap);
    assert_eq!(decoded.check_interval, 100);
    assert_eq!(decoded.debounce_delay, 50);
    assert_eq!(decoded.press_speed, 120);
    assert!(!decoded.release_on_emergency);
}

#[test]
fn test_group_item_periodic_roundtrip() {
    let item = GroupItem::Periodic {
        press_keys: vec!["1".to_string(), "2".to_string()],
        intervals: vec![50, 60],
    };
    let json = serde_json::to_string(&item).unwrap();
    let decoded: GroupItem = serde_json::from_str(&json).unwrap();
    match decoded {
        GroupItem::Periodic { press_keys, intervals } => {
            assert_eq!(press_keys, vec!["1", "2"]);
            assert_eq!(intervals, vec![50, 60]);
        }
        _ => panic!("Expected Periodic"),
    }
}

#[test]
fn test_group_item_sequence_roundtrip() {
    let item = GroupItem::Sequence {
        press_keys: vec!["A".to_string()],
        delays: vec![100],
        seq_interval: Some(50),
    };
    let json = serde_json::to_string(&item).unwrap();
    let decoded: GroupItem = serde_json::from_str(&json).unwrap();
    match decoded {
        GroupItem::Sequence { press_keys, delays, seq_interval } => {
            assert_eq!(press_keys, vec!["A"]);
            assert_eq!(delays, vec![100]);
            assert_eq!(seq_interval, Some(50));
        }
        _ => panic!("Expected Sequence"),
    }
}
