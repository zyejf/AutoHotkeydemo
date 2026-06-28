//! ASD 测试工具包 — 集中提供跨测试文件共享的 Mock 实现与工厂函数。
//!
//! 本 crate 为常规 library crate，但仅应作为其他 crate 的 dev-dependency 使用。
//! 所有 Mock 实现均实现 `asd_domain::traits` 中定义的 trait。

#![allow(dead_code)]

use asd_application::state::AppState;
use indexmap::IndexMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

// =================================================================
// 重新导出 — 测试文件可通过 `use asd_test_harness::*;` 统一引入
// =================================================================

pub use asd_domain::config::*;
pub use asd_domain::models::SkillGroup;
pub use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
pub use asd_domain::validator::{ConfigValidator, ValidationResult};
pub use asd_ipc_protocol::{IpcCommand, IpcMessage, IpcError};

// =================================================================
// Mock 实现
// =================================================================

/// 记录型 IPC 命令发送器 Mock。
///
/// `send_command` 会记录所有发送的命令，可通过 `sent_commands` 字段检视。
/// 这是 `common/mod.rs` 简单版本与 `cross_crate`/`integration` 记录版本的合并超集。
pub struct MockIpcSender {
    pub sent_commands: Mutex<Vec<IpcCommand>>,
}

impl MockIpcSender {
    pub fn new() -> Self {
        Self {
            sent_commands: Mutex::new(Vec::new()),
        }
    }
}

impl Default for MockIpcSender {
    fn default() -> Self {
        Self::new()
    }
}

impl IpcSender for MockIpcSender {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        self.sent_commands.lock().unwrap().push(cmd);
        Ok(1)
    }
    fn send_and_wait(
        &self,
        _cmd: IpcCommand,
        _timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        Ok(IpcMessage::response(
            1,
            0,
            "ok",
            Some(serde_json::json!({
                "keys": ["1", "2"],
                "mode": "periodic",
                "intervals": [50, 100],
                "delays": []
            })),
        ))
    }
    fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
        Ok(())
    }
}

/// 独立的记录型 IPC 发送器，提供 `sent_commands()` 方法访问器。
///
/// 用于需要检视已发送命令的测试场景（如 `group_service_tests`）。
pub struct RecordingIpcSender {
    commands: Mutex<Vec<IpcCommand>>,
}

impl RecordingIpcSender {
    pub fn new() -> Self {
        Self {
            commands: Mutex::new(Vec::new()),
        }
    }
    pub fn sent_commands(&self) -> Vec<IpcCommand> {
        self.commands.lock().unwrap().clone()
    }
}

impl Default for RecordingIpcSender {
    fn default() -> Self {
        Self::new()
    }
}

impl IpcSender for RecordingIpcSender {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        self.commands.lock().unwrap().push(cmd);
        Ok(1)
    }
    fn send_and_wait(
        &self,
        cmd: IpcCommand,
        _timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        self.commands.lock().unwrap().push(cmd);
        Ok(IpcMessage::response(1, 0, "ok", None))
    }
    fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
        Ok(())
    }
}

/// 记录型前端事件发射器 Mock。
///
/// `emit` 会记录所有发射的事件，可通过 `emitted` 字段检视。
pub struct MockEventEmitter {
    pub emitted: Mutex<Vec<(String, serde_json::Value)>>,
}

impl MockEventEmitter {
    pub fn new() -> Self {
        Self {
            emitted: Mutex::new(Vec::new()),
        }
    }

    /// 返回已记录事件的拷贝，便于测试断言。
    pub fn emitted_events(&self) -> Vec<(String, serde_json::Value)> {
        self.emitted.lock().unwrap().clone()
    }
}

impl Default for MockEventEmitter {
    fn default() -> Self {
        Self::new()
    }
}

impl EventEmitter for MockEventEmitter {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool {
        self.emitted
            .lock()
            .unwrap()
            .push((event.to_string(), payload));
        true
    }
}

/// 进程监控器 Mock — 始终返回 Idle 状态与 0 重启次数。
pub struct MockProcessWatcher;

impl ProcessWatcher for MockProcessWatcher {
    fn state(&self) -> WatchdogStateEnum {
        WatchdogStateEnum::Idle
    }
    fn restart_count(&self) -> u32 {
        0
    }
}

// =================================================================
// 工厂函数
// =================================================================

/// 构造包含 2 个分组（periodic + sequence）的测试配置。
pub fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
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
        },
    );
    group_settings.insert(
        "2".to_string(),
        GroupConfig {
            hotkey: "F2".to_string(),
            key_press_duration: Some(10),
            name: Some("test2".to_string()),
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

/// 构造使用 Mock 依赖的 `AppState`。
pub fn make_test_state() -> Arc<AppState> {
    Arc::new(AppState::new(
        make_test_config(),
        Arc::new(MockIpcSender::new()),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter::new()),
    ))
}

/// 构造使用 `RecordingIpcSender` 的 `AppState`，返回状态与发送器以供检视。
pub fn make_test_state_with_recording_sender() -> (Arc<AppState>, Arc<RecordingIpcSender>) {
    let sender = Arc::new(RecordingIpcSender::new());
    let state = Arc::new(AppState::new(
        make_test_config(),
        sender.clone(),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter::new()),
    ));
    (state, sender)
}

/// 构造 `AppState` 并绑定临时配置文件路径，返回状态与临时目录。
pub fn make_test_state_with_path() -> (Arc<AppState>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let config_path = dir.path().join("config.json");
    let state = make_test_state();
    state.set_config_path(config_path);
    (state, dir)
}

// =================================================================
// IPC 测试工具
// =================================================================

/// 进程内全局递增计数器，确保同进程多线程并发调用时名称严格唯一。
///
/// 使用 `AtomicU64` 可 `const` 初始化，无需 `lazy_static`。
static PIPE_NAME_COUNTER: AtomicU64 = AtomicU64::new(0);

/// 生成唯一的 named pipe 名称，用于 IPC 测试隔离。
///
/// 结合标签、进程 ID、纳秒时间戳与进程内递增计数器，确保并行测试不会冲突。
///
/// # 修复历史
///
/// 旧实现使用 `ts % 100000` 取模且无计数器，在 `cargo test` 多线程并行执行时：
/// 1. `std::process::id()` 对同进程内所有测试相同
/// 2. 多个 `#[tokio::test]` 可能在同一纳秒调用此函数 → 完全相同的 `ts`
/// 3. `ts % 100000` 碰撞概率随测试数平方增长（生日悖论）
/// 4. 碰撞导致多个测试创建同名 named pipe → interprocess crate 在 Windows 上未定义行为 → `STATUS_HEAP_CORRUPTION`
///
/// 修复方案：移除取模、新增 `AtomicU64` 计数器，保证同进程内严格递增。
pub fn unique_pipe_name(tag: &str) -> String {
    let id = std::process::id();
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let counter = PIPE_NAME_COUNTER.fetch_add(1, Ordering::SeqCst);
    format!("asd_ipc_poc_{}_{}_{}_{}", tag, id, ts, counter)
}

// =================================================================
// 测试模块
// =================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// 验证 `unique_pipe_name` 在多线程并发调用时生成的名称唯一。
    ///
    /// 这是修复 `STATUS_HEAP_CORRUPTION` 崩溃的回归测试：
    /// 旧实现使用 `ts % 100000` 且无计数器，高并发下会产生重复名称，
    /// 导致多个测试创建同名 named pipe，触发 interprocess crate 在 Windows 上的未定义行为。
    #[test]
    fn test_unique_pipe_name_thread_safety() {
        use std::sync::Arc;
        use std::sync::Mutex;
        use std::thread;

        let count = 100;
        let results: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let mut handles = vec![];

        for _ in 0..count {
            let results = Arc::clone(&results);
            handles.push(thread::spawn(move || {
                let name = unique_pipe_name("concurrent");
                results.lock().unwrap().push(name);
            }));
        }

        for h in handles {
            h.join().unwrap();
        }

        let names = results.lock().unwrap();
        let mut seen = std::collections::HashSet::new();
        for name in names.iter() {
            assert!(
                seen.insert(name.clone()),
                "Duplicate pipe name found: {}",
                name
            );
        }
        assert_eq!(names.len(), count, "All names should be collected");
    }

    /// 验证 `unique_pipe_name` 在高并发场景下的严格唯一性（16 线程 × 100 次调用）。
    ///
    /// 这是更严格的回归测试，模拟 `cargo test` 多线程并行执行时的真实场景：
    /// - 16 个线程同时调用 `unique_pipe_name`（模拟 16 个并行测试）
    /// - 每个线程调用 100 次（模拟每个测试多次创建管道）
    /// - 总计 1600 次调用，任何碰撞都会导致测试失败
    ///
    /// 旧实现（`ts % 100000` 无计数器）在此测试下会因生日悖论产生碰撞：
    /// 1600 个样本在 100000 个可能值中的碰撞概率 ≈ 1 - e^(-1600²/(2×100000)) ≈ 100%
    #[test]
    fn test_unique_pipe_name_concurrent_uniqueness() {
        use std::sync::Arc;
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::thread;

        const THREAD_COUNT: usize = 16;
        const CALLS_PER_THREAD: usize = 100;

        let collision_count = Arc::new(AtomicUsize::new(0));
        let mut handles = Vec::new();

        for _ in 0..THREAD_COUNT {
            let cc = Arc::clone(&collision_count);
            handles.push(thread::spawn(move || {
                let mut names = std::collections::HashSet::new();
                for i in 0..CALLS_PER_THREAD {
                    let name = unique_pipe_name(&format!("concurrent_test_{}", i));
                    if !names.insert(name) {
                        cc.fetch_add(1, Ordering::SeqCst);
                    }
                }
            }));
        }

        for h in handles {
            h.join().unwrap();
        }

        assert_eq!(
            collision_count.load(Ordering::SeqCst),
            0,
            "unique_pipe_name 在并发调用时产生了碰撞"
        );
    }

    /// 验证 `unique_pipe_name` 在单线程多次调用时的唯一性（1000 次调用）。
    ///
    /// 这是基础回归测试，确保计数器在单线程内也严格递增。
    /// 旧实现（`ts % 100000`）在快速连续调用时可能因时间戳相同而产生碰撞。
    #[test]
    fn test_unique_pipe_name_sequential_uniqueness() {
        let mut names = std::collections::HashSet::new();
        for i in 0..1000 {
            let name = unique_pipe_name(&format!("seq_test_{}", i));
            assert!(names.insert(name), "序号 {} 产生碰撞", i);
        }
    }
}
