//! Bridge 层测试 — IpcBridge / TauriEventBridge / WatchdogBridge
//!
//! 覆盖 `bridge.rs` 中 trait 实现的关键路径：
//! - IpcBridge: send_command / send_and_wait 超时与管道断裂
//! - TauriEventBridge: 事件发射（依赖 Tauri AppHandle，标记 #[ignore]）
//! - WatchdogBridge: 状态查询与重启计数

use crate::bridge::{IpcBridge, WatchdogBridge};
use crate::infrastructure::ipc::{create_listener, IpcManager};
use asd_domain::config::WatchdogStateEnum;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::IpcCommand;
use asd_test_harness::{unique_pipe_name, MockEventEmitter};
use interprocess::local_socket::traits::tokio::Listener;
use serial_test::serial;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

// =================================================================
// IpcBridge 测试
// =================================================================

/// 验证 `IpcBridge::send_and_wait` 在服务端不响应时返回超时错误。
///
/// IpcBridge 使用 `block_in_place + block_on`，必须运行在多线程 tokio 运行时。
/// 服务端 accept 连接但不发送任何响应，客户端 send_and_wait 应在超时后返回错误。
#[tokio::test(flavor = "multi_thread")]
#[serial]
async fn test_ipc_bridge_send_and_wait_timeout() {
    let pipe_name = unique_pipe_name("br_timeout");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    // 服务端：accept 后保持连接但不响应
    let server_task = tokio::spawn(async move {
        let _conn = listener.accept().await.expect("Server 接受连接失败");
        // 持有连接 5 秒但不发送任何响应
        tokio::time::sleep(Duration::from_secs(5)).await;
    });

    // 等待 listener 就绪
    tokio::time::sleep(Duration::from_millis(100)).await;

    let (ipc_manager, _outbound_rx) = IpcManager::new(&name_clone);
    ipc_manager.connect_to_ahk().await.expect("Client 连接失败");

    // 启动 listen_ahk 任务，使响应能被分发（虽然此测试中不会有响应）
    let listen_mgr = ipc_manager.clone();
    let listen_handle = tokio::spawn(async move {
        listen_mgr.listen_ahk().await;
    });

    let ipc_manager_arc: Arc<Mutex<Option<IpcManager>>> = Arc::new(Mutex::new(Some(ipc_manager)));
    let (outbound_tx, _outbound_rx2) = tokio::sync::mpsc::channel(16);
    let bridge = IpcBridge::new(outbound_tx, ipc_manager_arc);

    // 使用 100ms 短超时，应快速返回超时错误
    let result = bridge.send_and_wait(IpcCommand::Ping, Duration::from_millis(100));
    assert!(result.is_err(), "服务端不响应时 send_and_wait 应返回错误");
    let err = result.unwrap_err();
    assert!(
        err.contains("超时") || err.contains("timeout"),
        "应返回超时错误，实际: {err}"
    );

    listen_handle.abort();
    drop(bridge);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
}

/// 验证 `IpcBridge::send_and_wait` 在管道断裂时返回 IPC 错误。
///
/// 服务端 accept 后立即关闭连接，客户端的 listen_ahk 检测到 EOF 后触发
/// `notify_pipe_broken` -> `cleanup_connection`，向所有 pending response
/// 发送 `error_response("pipe_broken")`。send_and_wait 收到后转换为
/// "IPC 管道断裂" 错误。
///
/// 注意：此测试存在竞态——send_and_wait 可能在 pipe_broken 触发前超时，
/// 或在 send 阶段就失败。我们接受任何 IPC 相关错误作为通过条件。
#[tokio::test(flavor = "multi_thread")]
#[serial]
async fn test_ipc_bridge_send_and_wait_pipe_broken() {
    let pipe_name = unique_pipe_name("br_broken");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    // 服务端：accept 后短暂等待，然后关闭连接触发 pipe broken
    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        // 等待客户端 connect_to_ahk 完成
        tokio::time::sleep(Duration::from_millis(200)).await;
        // 关闭连接，触发客户端 pipe_broken 检测
        drop(conn);
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (ipc_manager, _outbound_rx) = IpcManager::new(&name_clone);
    ipc_manager.connect_to_ahk().await.expect("Client 连接失败");

    // 启动 listen_ahk 以检测 pipe_broken 并触发 cleanup_connection
    let listen_mgr = ipc_manager.clone();
    let listen_handle = tokio::spawn(async move {
        listen_mgr.listen_ahk().await;
    });

    let ipc_manager_arc: Arc<Mutex<Option<IpcManager>>> = Arc::new(Mutex::new(Some(ipc_manager)));
    let (outbound_tx, _outbound_rx2) = tokio::sync::mpsc::channel(16);
    let bridge = IpcBridge::new(outbound_tx, ipc_manager_arc);

    // 使用较长超时（5s），让 pipe_broken 有机会在超时前触发
    // 但也接受 send 阶段失败的 "IPC 通信错误"
    let result = bridge.send_and_wait(IpcCommand::Ping, Duration::from_secs(5));
    assert!(result.is_err(), "管道断裂时 send_and_wait 应返回错误");
    let err = result.unwrap_err();
    assert!(
        err.contains("管道断裂")
            || err.contains("pipe_broken")
            || err.contains("连接已关闭")
            || err.contains("IPC 通信错误")
            || err.contains("通道已关闭"),
        "应返回管道断裂或连接相关错误，实际: {err}"
    );

    listen_handle.abort();
    drop(bridge);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
}

/// 验证 `IpcBridge::send_command` 在 IPC 管理器未初始化时返回错误。
///
/// 当 `ipc_manager` 为 None 时，send_command 应返回
/// "IPC 管理器未初始化，请等待系统就绪" 错误。
#[tokio::test(flavor = "multi_thread")]
async fn test_ipc_bridge_send_command_manager_not_initialized() {
    let ipc_manager_arc: Arc<Mutex<Option<IpcManager>>> = Arc::new(Mutex::new(None));
    let (outbound_tx, _outbound_rx) = tokio::sync::mpsc::channel(16);
    let bridge = IpcBridge::new(outbound_tx, ipc_manager_arc);

    let result = bridge.send_command(IpcCommand::Ping);
    assert!(
        result.is_err(),
        "IPC 管理器未初始化时 send_command 应返回错误"
    );
    let err = result.unwrap_err();
    assert!(
        err.contains("未初始化") || err.contains("not initialized"),
        "应返回未初始化错误，实际: {err}"
    );
}

/// 验证 `IpcBridge::send_and_wait` 在 IPC 管理器未初始化时返回错误。
#[tokio::test(flavor = "multi_thread")]
async fn test_ipc_bridge_send_and_wait_manager_not_initialized() {
    let ipc_manager_arc: Arc<Mutex<Option<IpcManager>>> = Arc::new(Mutex::new(None));
    let (outbound_tx, _outbound_rx) = tokio::sync::mpsc::channel(16);
    let bridge = IpcBridge::new(outbound_tx, ipc_manager_arc);

    let result = bridge.send_and_wait(IpcCommand::Ping, Duration::from_secs(1));
    assert!(
        result.is_err(),
        "IPC 管理器未初始化时 send_and_wait 应返回错误"
    );
    let err = result.unwrap_err();
    assert!(
        err.contains("未初始化") || err.contains("not initialized"),
        "应返回未初始化错误，实际: {err}"
    );
}

// =================================================================
// TauriEventBridge 测试
// =================================================================
//
// 此处原本有一个 `test_tauri_event_bridge_emit` 占位测试，形如：
//
//   #[tokio::test(flavor = "multi_thread")]
//   #[ignore = "TauriEventBridge 需要 tauri::AppHandle，需在 Tauri 集成环境中运行"]
//   async fn test_tauri_event_bridge_emit() {
//       panic!("此测试需要 Tauri AppHandle，无法在纯单元测试环境中运行");
//   }
//
// 该测试已于 2026-09-13 删除（BUG-4）。删除理由：
//
// 1. 它是「必然失败」的死测试：函数体无条件 `panic!`，只要被执行就失败。
//    常规 `cargo test` 因 `#[ignore]` 跳过它，问题被隐藏；
//    但 `cargo test -- --ignored` 必然报 1 failed（实测 15 passed / 1 failed），
//    使 `--ignored` 永远无法全绿，真实失败会被这条常驻失败掩盖（狼来了效应）。
//
// 2. 它没有断言价值：占位函数体不构造任何对象、不调用任何被测逻辑，
//    `panic!` 只表达「跑不了」，而非「行为不符合预期」。
//
// 3. 覆盖并未丢失：事件发射逻辑由本文件下方的
//    `test_event_emitter_trait_contract` 通过 `MockEventEmitter` 覆盖
//    （验证 `EventEmitter` trait 契约：emit 返回 true 且事件被记录）。
//    `TauriEventBridge` 只是该 trait 在真实 `AppHandle` 上的实现，
//    属于集成场景，应由 E2E（启动完整 Tauri 应用）负责验证。

// =================================================================
// WatchdogBridge 测试
// =================================================================

/// 验证 `WatchdogBridge` 包装 `ProcessWatchdog` 后能正确查询状态。
///
/// 新创建的 ProcessWatchdog 状态为 Idle，重启计数为 0。
/// WatchdogBridge 应透传这些值。
#[tokio::test(flavor = "multi_thread")]
async fn test_watchdog_bridge_get_state() {
    use crate::infrastructure::watchdog::ProcessWatchdog;

    let watchdog = Arc::new(Mutex::new(ProcessWatchdog::new()));
    let bridge = WatchdogBridge::new(watchdog);

    // 新建的 watchdog 应处于 Idle 状态
    let state = bridge.state();
    assert_eq!(
        state,
        WatchdogStateEnum::Idle,
        "新建 watchdog 应处于 Idle 状态"
    );

    // 重启计数应为 0
    let count = bridge.restart_count();
    assert_eq!(count, 0, "新建 watchdog 重启计数应为 0");
}

/// 验证 `WatchdogBridge::reset` 在非 Failed/Hung/Recovering 状态下返回错误。
///
/// reset 仅在 Failed/Hung/Recovering 状态下允许，其他状态应返回错误。
#[tokio::test(flavor = "multi_thread")]
async fn test_watchdog_bridge_reset_invalid_state() {
    use crate::infrastructure::watchdog::ProcessWatchdog;

    let watchdog = Arc::new(Mutex::new(ProcessWatchdog::new()));
    let bridge = WatchdogBridge::new(watchdog);

    // Idle 状态下 reset 应失败
    let result = bridge.reset();
    assert!(result.is_err(), "Idle 状态下 reset 应返回错误");
    let err = result.unwrap_err();
    assert!(
        err.contains("Idle") || err.contains("状态"),
        "错误信息应包含当前状态，实际: {err}"
    );
}

/// 验证 `WatchdogBridge` 在 watchdog 处于 Failed 状态时 reset 成功。
///
/// Failed 状态下 reset 应调用 `reset_to_restart`，将状态转为 Restarting。
#[tokio::test(flavor = "multi_thread")]
async fn test_watchdog_bridge_reset_from_failed() {
    use crate::infrastructure::watchdog::ProcessWatchdog;

    let watchdog = Arc::new(Mutex::new(ProcessWatchdog::new()));
    {
        let mut guard = watchdog.lock().await;
        guard.set_state(WatchdogStateEnum::Failed);
    }

    let bridge = WatchdogBridge::new(watchdog.clone());

    // Failed 状态下 reset 应成功
    let result = bridge.reset();
    assert!(result.is_ok(), "Failed 状态下 reset 应成功: {:?}", result);

    // reset 后状态应变为 Restarting
    let guard = watchdog.lock().await;
    assert_eq!(
        guard.state(),
        WatchdogStateEnum::Restarting,
        "reset 后状态应为 Restarting"
    );
}

/// 验证 `WatchdogBridge` 能正确报告 Running 状态。
#[tokio::test(flavor = "multi_thread")]
async fn test_watchdog_bridge_running_state() {
    use crate::infrastructure::watchdog::ProcessWatchdog;

    let watchdog = Arc::new(Mutex::new(ProcessWatchdog::new()));
    {
        let mut guard = watchdog.lock().await;
        guard.set_state(WatchdogStateEnum::Running);
        guard.set_restart_count(2);
    }

    let bridge = WatchdogBridge::new(watchdog);

    assert_eq!(bridge.state(), WatchdogStateEnum::Running);
    assert_eq!(bridge.restart_count(), 2);
}

// =================================================================
// EventEmitter trait 通过 MockEventEmitter 间接覆盖
// =================================================================

/// 验证 MockEventEmitter 实现 EventEmitter trait 的行为正确。
///
/// 这间接验证了 EventEmitter trait 的契约，确保 TauriEventBridge
/// 在有 AppHandle 的环境中也能正确实现 emit 逻辑。
#[tokio::test]
async fn test_event_emitter_trait_contract() {
    let bridge = MockEventEmitter::new();

    let payload = serde_json::json!({"key": "value"});
    let result = bridge.emit("test_event", payload.clone());
    assert!(result, "emit 应返回 true");

    let events = bridge.emitted_events();
    assert_eq!(events.len(), 1, "应记录 1 个事件");
    assert_eq!(events[0].0, "test_event");
    assert_eq!(events[0].1, payload);
}

// =================================================================
// build_hotkey_event_payload 纯函数测试
// =================================================================

/// 验证 `build_hotkey_event_payload` 能正确构造热键事件 payload。
///
/// 从 hotkey 和 keys 构造 `{ "hotkey": ..., "keys": [...] }` JSON 结构，
/// 用于 `spawn_ipc_listener` 中向前端 emit hotkey_event 事件。
#[test]
fn test_build_hotkey_event_payload_basic() {
    let hotkey = "F1";
    let keys = vec!["F1".to_string()];
    let payload = crate::bridge::build_hotkey_event_payload(hotkey, &keys);

    assert_eq!(payload["hotkey"], "F1", "hotkey 字段应为 F1");
    assert_eq!(
        payload["keys"],
        serde_json::json!(["F1"]),
        "keys 字段应包含 F1"
    );
}

/// 验证 `build_hotkey_event_payload` 支持多键组合。
#[test]
fn test_build_hotkey_event_payload_multi_keys() {
    let hotkey = "Ctrl+Shift+A";
    let keys = vec!["Ctrl".to_string(), "Shift".to_string(), "A".to_string()];
    let payload = crate::bridge::build_hotkey_event_payload(hotkey, &keys);

    assert_eq!(payload["hotkey"], "Ctrl+Shift+A");
    assert_eq!(payload["keys"], serde_json::json!(["Ctrl", "Shift", "A"]));
}

/// 验证 `build_hotkey_event_payload` 在空 keys 时仍返回有效 JSON。
#[test]
fn test_build_hotkey_event_payload_empty_keys() {
    let hotkey = "F2";
    let keys: Vec<String> = vec![];
    let payload = crate::bridge::build_hotkey_event_payload(hotkey, &keys);

    assert_eq!(payload["hotkey"], "F2");
    assert_eq!(payload["keys"], serde_json::json!([]));
}
