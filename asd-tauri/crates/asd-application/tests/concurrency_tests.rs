//! AppState 并发安全性测试。
//!
//! 验证 `AppState` 在多线程并发访问下的线程安全性：
//! - 无数据竞争导致的内存损坏
//! - 无死锁
//! - 内存状态内部一致（`config.group_settings` 与 `groups` 键集同步）
//! - 磁盘配置文件始终为有效 JSON
//!
//! ## API 适配说明
//!
//! `save_config_atomic` 接收**整个 `Config`**（而非 `(group_id, group_config)`），
//! 因此并发 `save_config_atomic` 本质上是"整体替换"语义，存在 read-modify-write 竞态
//! （最后写入者的配置胜出，其他线程的修改可能丢失）。本测试套件验证的是**状态一致性
//! 与无损坏**，而非"所有修改都保留"——后者在整体替换语义下无法保证。
//!
//! `sync_config_changes_to_ahk` 为私有方法，通过 `save_config_atomic` 间接触发。
//!
//! 内部 `config_state.version` 无公开访问器，版本递增通过可观察行为
//! （操作成功返回 + 状态一致）间接验证。

use asd_application::state::AppState;
use asd_test_harness::*;
use indexmap::IndexMap;
use std::sync::{Arc, Barrier};
use std::thread;

// =================================================================
// 辅助函数
// =================================================================

/// 构造包含 4 个分组（"1".."4"，均为 periodic 模式）的测试配置。
fn make_four_group_config() -> Config {
    let mut group_settings = IndexMap::new();
    for i in 1..=4u32 {
        let id = i.to_string();
        group_settings.insert(
            id.clone(),
            GroupConfig {
                hotkey: format!("F{i}"),
                key_press_duration: Some(10),
                name: Some(format!("组{id}")),
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec![id.clone()],
                    intervals: vec![50],
                }),
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
        hold_settings: None,
        last_modified: None,
        version: Some("3.0".to_string()),
    }
}

/// 构造使用 4 分组配置的 `AppState`，并绑定临时配置文件路径。
fn make_state_with_path_4groups() -> (Arc<AppState>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let config_path = dir.path().join("config.json");
    let state = Arc::new(AppState::new(
        make_four_group_config(),
        Arc::new(MockIpcSender::new()),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter::new()),
    ));
    state.set_config_path(config_path);
    (state, dir)
}

/// 验证内存状态内部一致：`config.group_settings` 与 `groups` 键集完全相同，
/// 且分组数量等于 `expected_group_count`。
fn assert_memory_consistent(state: &AppState, expected_group_count: usize) {
    let config = state.read_config().expect("read_config 应成功");
    let groups = state.read_groups().expect("read_groups 应成功");
    assert_eq!(
        config.group_settings.len(),
        groups.len(),
        "config.group_settings 与 groups 长度应一致"
    );
    assert_eq!(
        groups.len(),
        expected_group_count,
        "分组数量应为 {expected_group_count}，实际: {}",
        groups.len()
    );
    for (id, _gs) in &config.group_settings {
        assert!(groups.contains_key(id), "groups 应包含分组 {id}");
    }
    for (id, _g) in &groups {
        assert!(
            config.group_settings.contains_key(id),
            "config.group_settings 应包含分组 {id}"
        );
    }
}

/// 验证磁盘配置文件存在、可读且可解析为有效 `Config`。
fn assert_disk_valid(path: &std::path::Path) {
    let content = std::fs::read_to_string(path).expect("配置文件应存在且可读");
    let _parsed: Config = serde_json::from_str(&content).expect("配置文件应为可解析的有效 JSON");
}

// =================================================================
// 测试用例
// =================================================================

/// 并发 `save_config_atomic` 修改**不同**分组：验证无死锁、无内存损坏、状态一致。
///
/// 每个线程读取当前配置，修改分配给自己的分组的 `name` 字段，再整体写回。
/// 由于 `save_config_atomic` 是整体替换语义，最后写入者的配置胜出，
/// 但内存状态必须始终内部一致且无损坏。
#[test]
fn test_concurrent_save_config_different_groups() {
    let (state, _dir) = make_state_with_path_4groups();
    let n = 4;
    let barrier = Arc::new(Barrier::new(n));

    let mut handles = Vec::new();
    for i in 1..=n {
        let state = state.clone();
        let barrier = barrier.clone();
        handles.push(thread::spawn(move || -> Result<(), String> {
            // 屏障前准备：读取当前配置并修改分配给自己的分组名称
            let mut cfg = state.read_config().map_err(|e| e.to_string())?;
            let group_id = i.to_string();
            let new_name = format!("thread_{i}_modified");
            if let Some(gs) = cfg.group_settings.get_mut(&group_id) {
                gs.name = Some(new_name);
            }
            // 屏障同步，最大化并发
            barrier.wait();
            // 并发执行 save_config_atomic
            state.save_config_atomic(cfg).map_err(|e| e.to_string())
        }));
    }

    let mut all_ok = true;
    let mut success_count = 0;
    for h in handles {
        match h.join() {
            Ok(Ok(())) => success_count += 1,
            Ok(Err(e)) => {
                eprintln!("线程 save_config_atomic 失败: {e}");
                all_ok = false;
            }
            Err(e) => {
                eprintln!("线程 panic: {e:?}");
                all_ok = false;
            }
        }
    }
    assert!(all_ok, "所有线程应成功完成，无 panic 或错误");
    assert_eq!(
        success_count, n,
        "应有 {n} 次 save_config_atomic 成功（间接验证版本递增 {n} 次）"
    );

    // 验证内存一致性：4 个分组全部存在，config 与 groups 同步
    assert_memory_consistent(&state, n);

    // 验证 save_config_atomic 已生效（last_modified 应被设置）
    let config = state.read_config().unwrap();
    assert!(
        config.last_modified.is_some(),
        "save_config_atomic 应设置 last_modified 字段"
    );

    // 验证每个分组的 name 为有效值（原始值或本线程修改值，非损坏）
    // 由于整体替换语义，至少最后一个写入者修改的分组 name 应为 modified 值
    let groups = state.read_groups().unwrap();
    let mut modified_count = 0;
    for i in 1..=n {
        let id = i.to_string();
        let group = groups.get(&id).expect("分组应存在");
        let name = group.name.as_str();
        let original = format!("组{id}");
        let modified = format!("thread_{i}_modified");
        assert!(
            name == original || name == modified,
            "分组 {id} 的 name 应为原始值({original})或本线程修改值({modified})，实际: {name}"
        );
        if name == modified {
            modified_count += 1;
        }
    }
    // 至少一个线程的修改应存活（最后写入者的修改必然存在）
    assert!(
        modified_count >= 1,
        "至少应有一个分组的 name 被修改（最后写入者的修改应存活），实际修改数: {modified_count}"
    );

    // 验证磁盘文件有效（注：并发磁盘写入顺序不确定，仅验证文件可解析）
    assert_disk_valid(&state.get_config_path().unwrap());
}

/// 并发 `delete_group_atomic` 删除**不同**分组：验证所有删除成功、内存状态正确。
///
/// `delete_group_atomic` 对单个 `group_id` 操作，不同分组的删除通过写锁序列化，
/// 互不干扰，应全部成功。
#[test]
fn test_concurrent_delete_group_different_groups() {
    let (state, _dir) = make_state_with_path_4groups();
    let n = 4;
    let barrier = Arc::new(Barrier::new(n));

    let mut handles = Vec::new();
    for i in 1..=n {
        let state = state.clone();
        let barrier = barrier.clone();
        handles.push(thread::spawn(move || -> Result<bool, String> {
            let group_id = i.to_string();
            barrier.wait();
            state
                .delete_group_atomic(&group_id)
                .map_err(|e| e.to_string())
        }));
    }

    let mut all_ok = true;
    let mut success_count = 0;
    for h in handles {
        match h.join() {
            Ok(Ok(_was_active)) => success_count += 1,
            Ok(Err(e)) => {
                eprintln!("线程 delete_group_atomic 失败: {e}");
                all_ok = false;
            }
            Err(e) => {
                eprintln!("线程 panic: {e:?}");
                all_ok = false;
            }
        }
    }
    assert!(all_ok, "所有删除线程应成功完成，无 panic 或错误");
    assert_eq!(success_count, n, "应有 {n} 次 delete_group_atomic 成功");

    // 验证内存：所有 4 个分组均已删除
    let groups = state.read_groups().unwrap();
    assert!(
        groups.is_empty(),
        "所有分组应已删除，剩余: {:?}",
        groups.keys().collect::<Vec<_>>()
    );

    let config = state.read_config().unwrap();
    assert!(
        config.group_settings.is_empty(),
        "config.group_settings 应为空"
    );

    // active_group_ids 应为空（所有分组已删除，无活跃分组）
    assert!(
        state.active_group_ids().is_empty(),
        "active_group_ids 应为空"
    );

    // 验证磁盘文件有效
    assert_disk_valid(&state.get_config_path().unwrap());
}

/// 并发 `save_config_atomic` 与 `delete_group_atomic` 操作**同一**分组：
/// 验证最终状态一致（要么分组存在且有新配置，要么分组已删除），无半修改状态。
///
/// 运行 20 次以增加捕获竞态条件的概率。
#[test]
fn test_concurrent_save_and_delete_same_group() {
    for iteration in 0..20 {
        let dir = tempfile::tempdir().unwrap();
        let config_path = dir.path().join("config.json");
        let baseline = make_test_config(); // 2 groups: "1"(periodic), "2"(sequence)
        let state = Arc::new(AppState::new(
            baseline.clone(),
            Arc::new(MockIpcSender::new()),
            Arc::new(MockProcessWatcher),
            Arc::new(MockEventEmitter::new()),
        ));
        state.set_config_path(config_path);

        // 初始保存以建立磁盘文件
        state.save_config_atomic(baseline.clone()).unwrap();

        let barrier = Arc::new(Barrier::new(2));
        let state_a = state.clone();
        let state_b = state.clone();
        let barrier_a = barrier.clone();
        let barrier_b = barrier.clone();
        let save_marker = format!("save_iter_{iteration}");

        // 线程 A：save_config_atomic 修改 group "1" 的名称（配置中仍包含 group "1"）
        let handle_a = thread::spawn(move || -> Result<(), String> {
            let mut cfg = baseline.clone();
            if let Some(gs) = cfg.group_settings.get_mut("1") {
                gs.name = Some(save_marker);
            }
            barrier_a.wait();
            state_a.save_config_atomic(cfg).map_err(|e| e.to_string())
        });

        // 线程 B：delete_group_atomic 删除 group "1"
        let handle_b = thread::spawn(move || -> Result<bool, String> {
            barrier_b.wait();
            state_b.delete_group_atomic("1").map_err(|e| e.to_string())
        });

        let result_a = handle_a.join();
        let result_b = handle_b.join();

        // 两个线程都不应 panic
        assert!(
            result_a.is_ok(),
            "迭代 {iteration}: save 线程不应 panic: {:?}",
            result_a.as_ref().err()
        );
        assert!(
            result_b.is_ok(),
            "迭代 {iteration}: delete 线程不应 panic: {:?}",
            result_b.as_ref().err()
        );

        // 两个操作都应成功（save 写入含 group 1 的配置；delete 删除存在的 group 1）
        let save_ok = result_a.unwrap().is_ok();
        let delete_ok = result_b.unwrap().is_ok();
        assert!(save_ok, "迭代 {iteration}: save_config_atomic 应成功");
        assert!(delete_ok, "迭代 {iteration}: delete_group_atomic 应成功");

        // 验证状态一致性
        let config = state.read_config().expect("read_config 应成功");
        let groups = state.read_groups().expect("read_groups 应成功");

        // config.group_settings 与 groups 键集应完全一致（无半修改状态）
        let config_keys: std::collections::HashSet<&String> =
            config.group_settings.keys().collect();
        let group_keys: std::collections::HashSet<&String> = groups.keys().collect();
        assert_eq!(
            config_keys, group_keys,
            "迭代 {iteration}: config 与 groups 键集应一致（无半修改状态）"
        );

        // group "2" 应始终存在（未被任何线程操作）
        assert!(
            groups.contains_key("2"),
            "迭代 {iteration}: group 2 应始终存在"
        );

        // group "1" 要么存在（save 获胜：配置含 group 1），要么不存在（delete 获胜）
        // 不应出现 group 在 config 但不在 groups 的撕裂状态（已由上面键集断言保证）
        if let Some(g1) = groups.get("1") {
            // group "1" 存在：name 应为有效值（原始 "test" 或 save 线程的修改值）
            let name = g1.name.as_str();
            assert!(
                name == "test" || name == format!("save_iter_{iteration}"),
                "迭代 {iteration}: group 1 存在时 name 应为有效值，实际: {name}"
            );
        }
        // 若 group "1" 不存在，delete 获胜，也是一致状态

        // active_hotkeys 一致性：group "1" 从未激活，不应在 active_group_ids 中
        let active = state.active_group_ids();
        assert!(
            !active.contains(&"1".to_string()),
            "迭代 {iteration}: group 1 未激活，不应在 active_group_ids 中"
        );

        // 磁盘文件应有效
        assert_disk_valid(&state.get_config_path().unwrap());
    }
}

/// 并发 `save_config_atomic`（触发 `sync_config_changes_to_ahk`）修改不同分组：
/// 验证 IPC 命令被线程安全地捕获、无丢失、无 panic。
///
/// 使用 `RecordingIpcSender`（内部 `Mutex` 保证线程安全）捕获所有 IPC 命令。
/// 每个线程修改一个不同分组的 `key_press_duration`，`save_config_atomic` 内部
/// 调用 `sync_config_changes_to_ahk` 发送 `ToggleGroup` 命令。
#[test]
fn test_concurrent_sync_config_changes() {
    let sender = Arc::new(RecordingIpcSender::new());
    let state = Arc::new(AppState::new(
        make_four_group_config(),
        sender.clone(),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter::new()),
    ));
    // 不设置 config_path：纯内存操作，避免磁盘 I/O 干扰 IPC 命令捕获

    // 激活所有 4 个分组（set_group_active 不触发 sync_config_changes_to_ahk，
    // 但会使分组进入 active 状态，使后续 save_config_atomic 的 sync 检测到
    // active->active 的参数变更并发送 ToggleGroup 命令）
    for i in 1..=4 {
        state.set_group_active(&i.to_string(), true).unwrap();
    }
    // 清空之前 set_group_active 等可能产生的命令
    let _ = sender.sent_commands();
    assert!(
        state.active_group_ids().len() == 4,
        "前置条件：4 个分组应均已激活"
    );

    let n = 4;
    let barrier = Arc::new(Barrier::new(n));
    let mut handles = Vec::new();

    for i in 1..=n {
        let state = state.clone();
        let barrier = barrier.clone();
        handles.push(thread::spawn(move || -> Result<(), String> {
            // 构造配置：修改分配给自己的分组的 key_press_duration（参数变更）
            let mut cfg = state.read_config().map_err(|e| e.to_string())?;
            let group_id = i.to_string();
            if let Some(gs) = cfg.group_settings.get_mut(&group_id) {
                gs.key_press_duration = Some(99);
            }
            barrier.wait();
            state.save_config_atomic(cfg).map_err(|e| e.to_string())
        }));
    }

    let mut all_ok = true;
    let mut success_count = 0;
    for h in handles {
        match h.join() {
            Ok(Ok(())) => success_count += 1,
            Ok(Err(e)) => {
                eprintln!("线程 save_config_atomic 失败: {e}");
                all_ok = false;
            }
            Err(e) => {
                eprintln!("线程 panic: {e:?}");
                all_ok = false;
            }
        }
    }
    assert!(all_ok, "所有线程应成功完成，无 panic 或错误");
    assert_eq!(success_count, n, "应有 {n} 次 save_config_atomic 成功");

    // 验证 IPC 命令被捕获（RecordingIpcSender 的 Mutex 保证线程安全，无丢失/损坏）
    let commands = sender.sent_commands();
    assert!(
        !commands.is_empty(),
        "应捕获到 IPC 命令（sync_config_changes_to_ahk 应被触发）"
    );

    // 验证所有命令都是预期变体：
    // - ToggleGroup：参数变更触发的同步命令（预期主要类型）
    // - RegisterHotkey/UnregisterHotkey：并发 read-modify-write 竞态下，
    //   配置回退可能导致热键变更误判，属已知的 fire-and-forget 行为
    for cmd in &commands {
        match cmd {
            IpcCommand::ToggleGroup { .. }
            | IpcCommand::RegisterHotkey { .. }
            | IpcCommand::UnregisterHotkey { .. } => {}
            other => panic!("捕获到意外的 IPC 命令类型: {other:?}"),
        }
    }

    // 验证最终内存状态一致
    assert_memory_consistent(&state, n);

    // 验证所有分组仍处于激活状态（save_config_atomic 从 old_groups 保留 active 状态）
    let active = state.active_group_ids();
    for i in 1..=n {
        assert!(
            active.contains(&i.to_string()),
            "分组 {i} 应仍处于激活状态（save_config_atomic 保留 active 状态）"
        );
    }
}
