// =================================================================
// benchmarks - 性能基准测试
// Phase 5 Task 5.2: 配置性能基准测试
// =================================================================

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use indexmap::IndexMap;

use asd_tauri_lib::domain::config::{
    Config, ControlHotkeys, EnhancedHybridData, EnhancedPeriodicData, EnhancedSequenceData,
    GroupConfig, GroupItem, HoldData, HoldSettings, HybridData, ModeData, PeriodicData,
    SequenceData,
};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use asd_tauri_lib::domain::validator::ConfigValidator;

// =================================================================
// 辅助函数：生成模拟数据
// =================================================================

/// 生成一个包含指定数量分组的配置（模拟 ~13KB JSON）
fn generate_large_config(group_count: usize) -> Config {
    let mut group_settings = IndexMap::new();

    for i in 0..group_count {
        let mode = match i % 7 {
            0 => "periodic",
            1 => "sequence",
            2 => "hybrid",
            3 => "hold",
            4 => "enhanced_periodic",
            5 => "enhanced_sequence",
            _ => "enhanced_hybrid",
        };

        let mode_data = match i % 7 {
            0 => ModeData::Periodic(PeriodicData {
                keys: (0..5).map(|j| format!("key_{i}_{j}")).collect(),
                intervals: (0..5).map(|j| 50 + j as u64 * 10).collect(),
            }),
            1 => ModeData::Sequence(SequenceData {
                keys: (0..5).map(|j| format!("key_{i}_{j}")).collect(),
                delays: (0..5).map(|j| 100 + j as u64 * 20).collect(),
            }),
            2 => ModeData::Hybrid(HybridData {
                groups: vec![
                    GroupItem::Periodic {
                        press_keys: vec!["1".to_string(), "2".to_string()],
                        intervals: vec![50, 60],
                    },
                    GroupItem::Sequence {
                        press_keys: vec!["3".to_string(), "4".to_string()],
                        delays: vec![100, 200],
                        seq_interval: Some(50),
                    },
                ],
                seq_interval: Some(100),
            }),
            3 => ModeData::Hold(HoldData {
                hold_duration: 500,
                auto_repeat: Some(true),
                repeat_interval: Some(100),
            }),
            4 => ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                press_keys: (0..5).map(|j| format!("key_{i}_{j}")).collect(),
                intervals: (0..5).map(|j| 50 + j as u64 * 10).collect(),
            }),
            5 => ModeData::EnhancedSequence(EnhancedSequenceData {
                press_keys: (0..5).map(|j| format!("key_{i}_{j}")).collect(),
                press_delays: (0..5).map(|j| 100 + j as u64 * 20).collect(),
            }),
            _ => ModeData::EnhancedHybrid(EnhancedHybridData {
                groups: vec![
                    GroupItem::Periodic {
                        press_keys: vec!["1".to_string(), "2".to_string()],
                        intervals: vec![50, 60],
                    },
                    GroupItem::Sequence {
                        press_keys: vec!["3".to_string(), "4".to_string()],
                        delays: vec![100, 200],
                        seq_interval: None,
                    },
                ],
                seq_interval: Some(100),
            }),
        };

        group_settings.insert(
            format!("{i}"),
            GroupConfig {
                hotkey: format!("F{}", i + 1),
                key_press_duration: Some(10),
                name: Some(format!("分组 {i}")),
                mode: mode.to_string(),
                hold_keys: if i % 3 == 0 {
                    Some(vec!["Shift".to_string(), "Ctrl".to_string()])
                } else {
                    None
                },
                hold_mode: if i % 3 == 0 {
                    Some("continuous".to_string())
                } else {
                    None
                },
                hold_pattern: None,
                hold_triggers: None,
                mode_data,
            },
        );
    }

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
        last_modified: Some("2025-01-01T00:00:00Z".to_string()),
        version: Some("3.0".to_string()),
    }
}

/// 生成包含 100 个按键的分组配置（用于按键校验基准）
fn generate_100_keys_config() -> IndexMap<String, GroupConfig> {
    let mut groups = IndexMap::new();

    // 10 个分组，每个 10 个按键 = 100 个按键
    for i in 0..10 {
        groups.insert(
            format!("{i}"),
            GroupConfig {
                hotkey: format!("F{}", i + 1),
                key_press_duration: Some(10),
                name: Some(format!("按键组 {i}")),
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: (0..10).map(|j| format!("key_{i}_{j}")).collect(),
                    intervals: (0..10).map(|j| 50 + j as u64 * 5).collect(),
                }),
            },
        );
    }

    groups
}

/// 生成 10 个分组用于 toggle 操作基准
fn generate_10_groups_for_toggle() -> IndexMap<String, GroupConfig> {
    let mut groups = IndexMap::new();
    for i in 0..10 {
        groups.insert(
            format!("{i}"),
            GroupConfig {
                hotkey: format!("F{}", i + 1),
                key_press_duration: Some(10),
                name: Some(format!("Toggle 组 {i}")),
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
    }
    groups
}

// =================================================================
// SubTask 5.2.1: 配置性能基准测试
// =================================================================

/// 基准：配置加载（JSON 反序列化）- 目标 <5ms
fn bench_config_loading(c: &mut Criterion) {
    let config = generate_large_config(20);
    let json = serde_json::to_string(&config).unwrap();
    let json_size_kb = json.len() as f64 / 1024.0;

    let mut group = c.benchmark_group("config_loading");
    group.sample_size(50);

    group.bench_function(
        BenchmarkId::new("deserialize_13kb_json", format!("{:.1}KB", json_size_kb)),
        |b| {
            b.iter(|| {
                let _: Config = serde_json::from_str(&json).unwrap();
            });
        },
    );

    group.finish();
}

/// 基准：按键校验 - 目标 <1ms
fn bench_key_validation(c: &mut Criterion) {
    let groups = generate_100_keys_config();

    let mut group = c.benchmark_group("key_validation");
    group.sample_size(100);

    group.bench_function("validate_100_keys", |b| {
        b.iter(|| {
            ConfigValidator::validate(&groups);
        });
    });

    group.finish();
}

/// 基准：分组调度（toggle 操作）- 目标 <2ms
fn bench_group_scheduling(c: &mut Criterion) {
    let groups_config = generate_10_groups_for_toggle();

    let mut group = c.benchmark_group("group_scheduling");
    group.sample_size(100);

    group.bench_function("toggle_10_groups", |b| {
        b.iter(|| {
            // 模拟 10 个分组的 toggle 操作
            for (id, group_config) in &groups_config {
                let _skill_group =
                    asd_tauri_lib::domain::models::SkillGroup::from((id, group_config));
            }
        });
    });

    group.finish();
}

/// 基准：配置序列化
fn bench_config_serialization(c: &mut Criterion) {
    let config = generate_large_config(20);

    let mut group = c.benchmark_group("config_serialization");
    group.sample_size(50);

    group.bench_function("serialize_20_groups", |b| {
        b.iter(|| {
            let _ = serde_json::to_string(&config).unwrap();
        });
    });

    group.finish();
}

// =================================================================
// SubTask 5.2.2: IPC 延迟基准测试
// =================================================================

/// 基准：IpcMessage 序列化 + 反序列化 roundtrip
fn bench_ipc_message_roundtrip(c: &mut Criterion) {
    let msg = IpcMessage::command(
        42,
        &IpcCommand::ToggleGroup {
            group_id: "1".to_string(),
            active: true,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        },
    );

    let mut group = c.benchmark_group("ipc_message");
    group.sample_size(200);

    group.bench_function("roundtrip_toggle_group", |b| {
        b.iter(|| {
            let json = serde_json::to_string(&msg).unwrap();
            let _: IpcMessage = serde_json::from_str(&json).unwrap();
        });
    });

    // 测试 execute 消息 roundtrip
    let exec_msg = IpcMessage::execute(
        100,
        vec!["1".to_string(), "2".to_string(), "3".to_string()],
        50,
    );

    group.bench_function("roundtrip_execute", |b| {
        b.iter(|| {
            let json = serde_json::to_string(&exec_msg).unwrap();
            let _: IpcMessage = serde_json::from_str(&json).unwrap();
        });
    });

    // 测试 response 消息 roundtrip
    let resp_msg = IpcMessage::response(
        200,
        100,
        "ok",
        Some(serde_json::json!({"result": "success", "data": [1, 2, 3]})),
    );

    group.bench_function("roundtrip_response", |b| {
        b.iter(|| {
            let json = serde_json::to_string(&resp_msg).unwrap();
            let _: IpcMessage = serde_json::from_str(&json).unwrap();
        });
    });

    group.finish();
}

/// 基准：IpcCommand 枚举序列化
fn bench_ipc_command_serialization(c: &mut Criterion) {
    let commands = vec![
        (
            "toggle_group",
            IpcCommand::ToggleGroup {
                group_id: "1".to_string(),
                active: true,
                mode: None,
                key_press_duration: None,
                hold_keys: None,
                hold_mode: None,
                mode_data: None,
            },
        ),
        (
            "register_hotkey",
            IpcCommand::RegisterHotkey {
                hotkey: "F1".to_string(),
                group_id: "1".to_string(),
            },
        ),
        ("ping", IpcCommand::Ping),
        (
            "hold_mode_toggle",
            IpcCommand::HoldModeToggle { enabled: true },
        ),
        ("emergency_release", IpcCommand::EmergencyRelease),
    ];

    let mut group = c.benchmark_group("ipc_command");
    group.sample_size(200);

    for (name, cmd) in &commands {
        group.bench_function(BenchmarkId::new("serialize", name), |b| {
            b.iter(|| {
                let _ = serde_json::to_string(cmd).unwrap();
            });
        });

        // 预序列化后测试反序列化
        let json = serde_json::to_string(cmd).unwrap();
        group.bench_function(BenchmarkId::new("deserialize", name), |b| {
            b.iter(|| {
                let _: IpcCommand = serde_json::from_str(&json).unwrap();
            });
        });
    }

    group.finish();
}

/// 基准：IpcMessage 完整构造 + 序列化（模拟 IPC 发送路径）
fn bench_ipc_send_path(c: &mut Criterion) {
    let mut group = c.benchmark_group("ipc_send_path");
    group.sample_size(200);

    group.bench_function("construct_and_serialize_toggle", |b| {
        b.iter(|| {
            let msg = IpcMessage::command(
                42,
                &IpcCommand::ToggleGroup {
                    group_id: "1".to_string(),
                    active: true,
                    mode: None,
                    key_press_duration: None,
                    hold_keys: None,
                    hold_mode: None,
                    mode_data: None,
                },
            );
            let _ = serde_json::to_string(&msg).unwrap();
        });
    });

    group.bench_function("construct_and_serialize_ping", |b| {
        b.iter(|| {
            let msg = IpcMessage::ping(42);
            let _ = serde_json::to_string(&msg).unwrap();
        });
    });

    group.finish();
}

criterion_group!(
    benches,
    bench_config_loading,
    bench_key_validation,
    bench_group_scheduling,
    bench_config_serialization,
    bench_ipc_message_roundtrip,
    bench_ipc_command_serialization,
    bench_ipc_send_path,
);

criterion_main!(benches);
