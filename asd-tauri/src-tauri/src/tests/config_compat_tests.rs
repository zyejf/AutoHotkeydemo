use asd_domain::config::*;

static MAIN_CONFIG_JSON: &str = include_str!("../../config.json");
static TESTS_CONFIG_JSON: &str = include_str!("../../tests_config.json");

fn strip_bom(s: &str) -> &str {
    s.trim_start_matches('\u{feff}')
}

fn parse_main_config() -> Config {
    let cleaned = strip_bom(MAIN_CONFIG_JSON);
    serde_json::from_str(cleaned).expect("main config.json 反序列化失败")
}

fn parse_tests_config() -> Config {
    let cleaned = strip_bom(TESTS_CONFIG_JSON);
    serde_json::from_str(cleaned).expect("tests_config.json 反序列化失败")
}

#[test]
fn test_deserialize_actual_config() {
    let main_cfg = parse_main_config();
    assert_eq!(main_cfg.control_hotkeys.emergency, "F10");
    assert!(main_cfg.group_settings.contains_key("1"));
    assert!(main_cfg.group_settings.contains_key("test_cycle"));
    assert!(main_cfg.hold_settings.is_some());
    assert_eq!(main_cfg.version.as_deref(), Some("3.0"));

    let tests_cfg = parse_tests_config();
    assert_eq!(tests_cfg.control_hotkeys.emergency, "f12");
    assert!(tests_cfg.group_settings.contains_key("1"));
    assert!(tests_cfg.group_settings.contains_key("6"));
    assert!(tests_cfg.hold_settings.is_some());
}

#[test]
fn test_roundtrip_serialization() {
    for (label, json_str) in [("main", MAIN_CONFIG_JSON), ("tests", TESTS_CONFIG_JSON)] {
        let cleaned = strip_bom(json_str);
        let original_value: serde_json::Value =
            serde_json::from_str(cleaned).expect("{label} 原始 JSON 解析失败");

        let config: Config = serde_json::from_str(cleaned).expect("{label} 反序列化失败");

        let roundtrip_str = serde_json::to_string(&config).expect("{label} 序列化失败");
        let roundtrip_value: serde_json::Value =
            serde_json::from_str(&roundtrip_str).expect("{label} 往返 JSON 解析失败");

        assert_eq!(original_value, roundtrip_value, "{label} 往返序列化不一致");
    }
}

#[test]
fn test_periodic_mode_flat() {
    let cfg = parse_main_config();
    let group = cfg
        .group_settings
        .get("test_cycle")
        .expect("缺少 test_cycle 组");

    assert_eq!(group.mode, "periodic");
    assert_eq!(group.hotkey, "F2");
    assert_eq!(group.key_press_duration, Some(20));
    assert_eq!(group.name.as_deref(), Some("测试周期按键"));

    match &group.mode_data {
        ModeData::Periodic(data) => {
            assert_eq!(data.keys, vec!["a"]);
            assert_eq!(data.intervals, vec![100]);
        }
        other => panic!("test_cycle 应为 Periodic 模式，实际: {other:?}"),
    }
}

#[test]
fn test_hybrid_mode_groups() {
    let cfg = parse_main_config();
    let group = cfg.group_settings.get("1").expect("缺少组 1");

    assert_eq!(group.mode, "hybrid");
    assert_eq!(group.hotkey, "F1");
    assert_eq!(group.key_press_duration, Some(10));
    assert_eq!(group.name.as_deref(), Some("示例混合"));

    match &group.mode_data {
        ModeData::Hybrid(data) => {
            assert_eq!(data.groups.len(), 2);
            assert_eq!(data.seq_interval, Some(100));

            match &data.groups[0] {
                GroupItem::Periodic {
                    press_keys,
                    intervals,
                } => {
                    assert_eq!(*press_keys, vec!["1", "2", "3"]);
                    assert_eq!(*intervals, vec![50, 50, 50]);
                }
                other => panic!("groups[0] 应为 Periodic，实际: {other:?}"),
            }

            match &data.groups[1] {
                GroupItem::Sequence {
                    press_keys,
                    delays,
                    seq_interval,
                } => {
                    assert_eq!(*press_keys, vec!["A", "S", "D"]);
                    assert_eq!(*delays, vec![200, 500, 2000]);
                    assert_eq!(*seq_interval, None);
                }
                other => panic!("groups[1] 应为 Sequence，实际: {other:?}"),
            }
        }
        other => panic!("组 1 应为 Hybrid 模式，实际: {other:?}"),
    }
}

#[test]
fn test_enhanced_sequence_mode() {
    let cfg = parse_tests_config();
    let group = cfg.group_settings.get("1").expect("缺少组 1");

    assert_eq!(group.mode, "enhanced_sequence");
    assert_eq!(group.hotkey, "F1");

    match &group.mode_data {
        ModeData::EnhancedSequence(data) => {
            assert_eq!(data.press_keys, vec!["Space", "4", "RButton"]);
            assert_eq!(data.press_delays, vec![50, 50, 50]);
        }
        other => panic!("组 1 应为 EnhancedSequence，实际: {other:?}"),
    }
}

#[test]
fn test_sequence_mode() {
    let cfg = parse_tests_config();
    let group = cfg.group_settings.get("2").expect("缺少组 2");

    assert_eq!(group.mode, "sequence");
    assert_eq!(group.hotkey, "F2");

    match &group.mode_data {
        ModeData::Sequence(data) => {
            assert_eq!(data.keys, vec!["1", "2", "3", "q"]);
            assert_eq!(data.delays, vec![100, 100, 100, 100]);
        }
        other => panic!("组 2 应为 Sequence，实际: {other:?}"),
    }
}

#[test]
fn test_enhanced_periodic_mode() {
    let cfg = parse_tests_config();
    let group = cfg.group_settings.get("3").expect("缺少组 3");

    assert_eq!(group.mode, "enhanced_periodic");
    assert_eq!(group.hotkey, "F3");
    assert_eq!(
        group.hold_keys.as_deref(),
        Some(vec!["Shift".to_string()].as_slice())
    );
    assert_eq!(group.hold_mode.as_deref(), Some("continuous"));

    match &group.mode_data {
        ModeData::EnhancedPeriodic(data) => {
            assert_eq!(
                data.press_keys,
                vec!["space", "1", "2", "3", "RButton", "space"]
            );
            assert_eq!(data.intervals, vec![50, 50, 50, 50, 50, 50]);
        }
        other => panic!("组 3 应为 EnhancedPeriodic，实际: {other:?}"),
    }
}

#[test]
fn test_enhanced_hybrid_mode() {
    let cfg = parse_tests_config();
    let group = cfg.group_settings.get("4").expect("缺少组 4");

    assert_eq!(group.mode, "enhanced_hybrid");
    assert_eq!(group.hotkey, "F4");
    assert_eq!(group.key_press_duration, Some(15));
    assert_eq!(
        group.hold_keys.as_deref(),
        Some(vec!["Shift".to_string(), "Ctrl".to_string()].as_slice())
    );
    assert_eq!(group.hold_mode.as_deref(), Some("continuous"));

    match &group.mode_data {
        ModeData::EnhancedHybrid(data) => {
            assert_eq!(data.groups.len(), 2);
            assert_eq!(data.seq_interval, Some(100));

            match &data.groups[0] {
                GroupItem::Periodic {
                    press_keys,
                    intervals,
                } => {
                    assert_eq!(*press_keys, vec!["Space"]);
                    assert_eq!(*intervals, vec![100]);
                }
                other => panic!("groups[0] 应为 Periodic，实际: {other:?}"),
            }

            match &data.groups[1] {
                GroupItem::Sequence {
                    press_keys,
                    delays,
                    seq_interval,
                } => {
                    assert_eq!(*press_keys, vec!["1", "2", "3", "4", "q"]);
                    assert_eq!(*delays, vec![100, 100, 100, 100, 100]);
                    assert_eq!(*seq_interval, Some(100));
                }
                other => panic!("groups[1] 应为 Sequence，实际: {other:?}"),
            }
        }
        other => panic!("组 4 应为 EnhancedHybrid，实际: {other:?}"),
    }
}

#[test]
fn test_hold_mode() {
    let cfg = parse_tests_config();
    let group = cfg.group_settings.get("6").expect("缺少组 6");

    assert_eq!(group.mode, "hold");
    assert_eq!(group.hotkey, "F6");
    assert_eq!(
        group.hold_keys.as_deref(),
        Some(vec!["RButton".to_string()].as_slice())
    );

    match &group.mode_data {
        ModeData::Hold(data) => {
            assert_eq!(data.hold_duration, 700);
            assert_eq!(data.auto_repeat, Some(false));
            assert_eq!(data.repeat_interval, Some(1000));
        }
        other => panic!("组 6 应为 Hold，实际: {other:?}"),
    }
}

#[test]
fn test_hold_settings_fields() {
    let cfg = parse_main_config();
    let hs = cfg.hold_settings.as_ref().expect("缺少 HoldSettings");
    assert!(!hs.allow_overlap);
    assert_eq!(hs.check_interval, 50);
    assert_eq!(hs.debounce_delay, 25);
    assert_eq!(hs.press_speed, 80);
    assert!(hs.release_on_emergency);

    let cfg2 = parse_tests_config();
    let hs2 = cfg2.hold_settings.as_ref().expect("缺少 HoldSettings");
    assert_eq!(hs2.debounce_delay, 20);
}

#[test]
fn test_control_hotkeys_all_fields() {
    let cfg = parse_main_config();
    let hk = &cfg.control_hotkeys;
    assert_eq!(hk.emergency, "F10");
    assert_eq!(hk.release_all_holds, "^r");
    assert_eq!(hk.show_status, "^0");
    assert_eq!(hk.toggle_all, "^1");
    assert_eq!(hk.toggle_hold_mode, "^h");
}
