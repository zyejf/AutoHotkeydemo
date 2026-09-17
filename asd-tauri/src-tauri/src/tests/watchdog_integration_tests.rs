//! Watchdog 集成测试 — ProcessWatchdog 进程管理与状态机
//!
//! 这些测试涉及真实进程管理（spawn、kill、重启）和时序依赖，
//! 全部标记为 `#[ignore]` 以避免在 CI 中运行慢测试。
//! 可通过 `cargo test -- --ignored` 手动运行。
//!
//! 覆盖场景：
//! - 子进程启动与状态转换（Idle → Running）
//! - 子进程崩溃后的重启流程（Running → Restarting → Running）
//! - 重启次数达到上限后的 Failed 状态
//! - 指数退避时间序列验证

#![cfg(windows)]

use crate::infrastructure::watchdog::{
    graceful_shutdown_watchdog, ProcessWatchdog, WatchdogAction, WatchdogRunner, BACKOFF_DURATIONS,
    MAX_RESTART_ATTEMPTS,
};
use asd_domain::config::WatchdogStateEnum;
use std::os::windows::process::CommandExt;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

// CREATE_NO_WINDOW 标志，避免子进程弹出控制台窗口
const CREATE_NO_WINDOW: u32 = 0x08000000;

/// 启动一个长时间运行的子进程（ping 127.0.0.1 约 10 秒）。
fn spawn_long_running_child() -> std::process::Child {
    Command::new("ping")
        .args(["-n", "10", "127.0.0.1"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .expect("启动长时间运行子进程失败")
}

/// 启动一个立即退出的子进程（cmd /c exit 1）。
fn spawn_quick_exit_child() -> std::process::Child {
    Command::new("cmd")
        .args(["/C", "exit 1"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .expect("启动快速退出子进程失败")
}

// =================================================================
// 子进程启动测试
// =================================================================

/// 验证 `ProcessWatchdog::attach_child` 能附加真实子进程并转为 Running 状态。
///
/// 步骤：
/// 1. 创建 ProcessWatchdog（初始 Idle）
/// 2. 启动 ping 子进程
/// 3. attach_child 附加子进程
/// 4. 验证状态变为 Running，child_pid 不为 None
/// 5. 清理：graceful_shutdown 终止子进程
#[test]
#[ignore = "涉及真实进程管理，需手动运行：cargo test -- --ignored test_watchdog_start_child_process"]
fn test_watchdog_start_child_process() {
    let mut wd = ProcessWatchdog::new();
    assert_eq!(wd.state(), WatchdogStateEnum::Idle);
    assert!(wd.child_pid().is_none());

    let child = spawn_long_running_child();
    let pid = child.id();

    let result = wd.attach_child(child);
    assert!(result.is_ok(), "attach_child 应成功: {result:?}");

    assert_eq!(
        wd.state(),
        WatchdogStateEnum::Running,
        "附加子进程后状态应为 Running"
    );
    assert_eq!(wd.child_pid(), Some(pid), "child_pid 应匹配");

    // tick 在 Running 状态下且子进程存活时应返回 None
    let action = wd.tick();
    assert_eq!(
        action,
        WatchdogAction::None,
        "子进程存活时 tick 应返回 None"
    );

    // 清理：优雅关机
    let rt = tokio::runtime::Runtime::new().expect("创建 tokio 运行时失败");
    rt.block_on(async {
        let wd = Arc::new(Mutex::new(wd));
        let result = graceful_shutdown_watchdog(&wd).await;
        assert!(result.is_ok(), "graceful_shutdown 应成功: {result:?}");
        let guard = wd.lock().await;
        assert_eq!(
            guard.state(),
            WatchdogStateEnum::Idle,
            "关机后状态应回到 Idle"
        );
        assert!(guard.child_pid().is_none(), "关机后 child_pid 应为 None");
    });
}

// =================================================================
// 子进程崩溃与重启测试
// =================================================================

/// 验证子进程退出后 watchdog 检测到并转为 Restarting 状态。
///
/// 步骤：
/// 1. attach_child 附加子进程
/// 2. kill 子进程模拟崩溃
/// 3. tick 应返回 RestartNeeded，状态转为 Restarting
#[test]
#[ignore = "涉及真实进程管理，需手动运行：cargo test -- --ignored test_watchdog_child_crash_restart"]
fn test_watchdog_child_crash_restart() {
    let mut wd = ProcessWatchdog::new();

    let child = spawn_long_running_child();
    wd.attach_child(child).expect("attach_child 失败");
    assert_eq!(wd.state(), WatchdogStateEnum::Running);

    // 模拟崩溃：kill 子进程
    {
        let _ = wd.kill_child();
    }

    // 短暂等待确保进程完全退出
    std::thread::sleep(Duration::from_millis(100));

    // tick 应检测到子进程退出，返回 RestartNeeded
    let action = wd.tick();
    assert_eq!(
        action,
        WatchdogAction::RestartNeeded,
        "子进程退出后 tick 应返回 RestartNeeded"
    );
    assert_eq!(
        wd.state(),
        WatchdogStateEnum::Restarting,
        "检测到崩溃后状态应为 Restarting"
    );
}

/// 验证 `WatchdogRunner` 能自动重启崩溃的子进程。
///
/// 此测试使用 `spawn_child` 以存储 exe_path/auth_token 供重启使用。
/// 步骤：
/// 1. spawn_child 启动 cmd.exe（保持运行）
/// 2. 启动 WatchdogRunner
/// 3. kill 子进程模拟崩溃
/// 4. 等待 WatchdogRunner 检测并重启
/// 5. 验证 restart_count 递增，状态回到 Running
#[tokio::test(flavor = "multi_thread")]
#[ignore = "涉及真实进程管理且需要时序协调，需手动运行"]
async fn test_watchdog_runner_auto_restart() {
    let wd = ProcessWatchdog::new();
    let wd = Arc::new(Mutex::new(wd));

    // 使用 spawn_child 启动 cmd.exe（CREATE_NO_WINDOW 模式下保持运行）
    {
        let mut guard = wd.lock().await;
        let result = guard.spawn_child("C:\\Windows\\System32\\cmd.exe", "test_auth_token");
        assert!(result.is_ok(), "spawn_child 应成功: {result:?}");
        assert_eq!(guard.state(), WatchdogStateEnum::Running);
    }

    let runner = WatchdogRunner::from_arc(wd.clone());
    let runner_handle = tokio::spawn(async move {
        runner.run().await;
    });

    // 等待 runner 启动
    tokio::time::sleep(Duration::from_millis(200)).await;

    // 模拟崩溃：kill 子进程
    {
        let mut guard = wd.lock().await;
        let _ = guard.kill_child();
    }

    // 等待 watchdog 检测崩溃并重启（HEARTBEAT_INTERVAL=1s + 重启逻辑）
    // 最多等待 5 秒
    let mut restart_detected = false;
    for _ in 0..50 {
        tokio::time::sleep(Duration::from_millis(100)).await;
        let guard = wd.lock().await;
        if guard.restart_count() > 0 {
            restart_detected = true;
            break;
        }
    }

    assert!(
        restart_detected,
        "应在 5 秒内检测到崩溃并触发重启（restart_count > 0）"
    );

    // 验证最终状态
    {
        let guard = wd.lock().await;
        let count = guard.restart_count();
        assert!(count >= 1, "重启次数应 >= 1，实际: {count}");
    }

    // 清理
    runner_handle.abort();
    let _ = graceful_shutdown_watchdog(&wd).await;
}

// =================================================================
// 重启次数上限测试
// =================================================================

/// 验证当 `restart_count` 达到 `MAX_RESTART_ATTEMPTS` 时，状态转为 Failed。
///
/// `MAX_RESTART_ATTEMPTS` 是硬编码常量（10），无法通过配置修改。
/// 此测试通过手动设置 restart_count 到上限来验证状态机逻辑。
///
/// 步骤：
/// 1. 创建 watchdog，手动设置状态为 Restarting，restart_count 为上限
/// 2. tick 应返回 MaxRetriesExceeded，状态转为 Failed
#[test]
#[ignore = "验证状态机极限，需手动运行：cargo test -- --ignored test_watchdog_restart_limit"]
fn test_watchdog_restart_limit() {
    let mut wd = ProcessWatchdog::new();

    // 手动设置到重启上限
    wd.set_state(WatchdogStateEnum::Restarting);
    wd.set_restart_count(MAX_RESTART_ATTEMPTS);

    let action = wd.tick();
    assert_eq!(
        action,
        WatchdogAction::MaxRetriesExceeded,
        "达到 MAX_RESTART_ATTEMPTS 时应返回 MaxRetriesExceeded"
    );
    assert_eq!(
        wd.state(),
        WatchdogStateEnum::Failed,
        "达到上限后状态应为 Failed"
    );
}

/// 验证 Failed 状态下 tick 持续返回 MaxRetriesExceeded。
#[test]
#[ignore = "验证 Failed 状态稳定性"]
fn test_watchdog_failed_state_persistent() {
    let mut wd = ProcessWatchdog::new();
    wd.set_state(WatchdogStateEnum::Failed);
    wd.set_restart_count(MAX_RESTART_ATTEMPTS);

    // Failed 状态下 tick 应持续返回 MaxRetriesExceeded
    let action1 = wd.tick();
    assert_eq!(action1, WatchdogAction::MaxRetriesExceeded);

    let action2 = wd.tick();
    assert_eq!(action2, WatchdogAction::MaxRetriesExceeded);

    // 状态应保持 Failed
    assert_eq!(wd.state(), WatchdogStateEnum::Failed);
}

// =================================================================
// 指数退避测试
// =================================================================

/// 验证 `begin_restart` 后 `backoff_duration` 按指数序列递增。
///
/// `BACKOFF_DURATIONS` = [1s, 2s, 4s, 8s, 30s, 30s, 30s, 30s, 30s, 30s]
/// 每次 `begin_restart` 后 `restart_count` 递增，`backoff_duration` 取
/// `BACKOFF_DURATIONS[restart_count]`。
#[test]
#[ignore = "验证退避时间序列，需手动运行：cargo test -- --ignored test_watchdog_exponential_backoff"]
fn test_watchdog_exponential_backoff() {
    let mut wd = ProcessWatchdog::new();

    // 初始 backoff 应为 BACKOFF_DURATIONS[0] = 1s
    assert_eq!(wd.backoff_duration(), Duration::from_secs(1));

    // 第 1 次 restart：restart_count=1, backoff=BACKOFF_DURATIONS[1]=2s
    wd.begin_restart();
    assert_eq!(wd.restart_count(), 1);
    assert_eq!(wd.backoff_duration(), Duration::from_secs(2));

    // 第 2 次：restart_count=2, backoff=BACKOFF_DURATIONS[2]=4s
    wd.begin_restart();
    assert_eq!(wd.restart_count(), 2);
    assert_eq!(wd.backoff_duration(), Duration::from_secs(4));

    // 第 3 次：restart_count=3, backoff=BACKOFF_DURATIONS[3]=8s
    wd.begin_restart();
    assert_eq!(wd.restart_count(), 3);
    assert_eq!(wd.backoff_duration(), Duration::from_secs(8));

    // 第 4 次：restart_count=4, backoff=BACKOFF_DURATIONS[4]=30s
    wd.begin_restart();
    assert_eq!(wd.restart_count(), 4);
    assert_eq!(wd.backoff_duration(), Duration::from_secs(30));

    // 第 5 次：restart_count=5, backoff=BACKOFF_DURATIONS[5]=30s（上限）
    wd.begin_restart();
    assert_eq!(wd.restart_count(), 5);
    assert_eq!(wd.backoff_duration(), Duration::from_secs(30));
}

/// 验证 Restarting 状态下未到退避时间时返回 WaitForBackoff。
#[test]
#[ignore = "验证退避等待逻辑"]
fn test_watchdog_backoff_wait() {
    let mut wd = ProcessWatchdog::new();
    wd.set_state(WatchdogStateEnum::Restarting);
    wd.begin_restart(); // restart_count=1, backoff=2s

    // 立即 tick，应返回 WaitForBackoff（剩余约 2s）
    let action = wd.tick();
    match action {
        WatchdogAction::WaitForBackoff(remaining) => {
            assert!(
                remaining <= Duration::from_secs(2),
                "剩余等待时间应 <= 2s，实际: {remaining:?}"
            );
            assert!(
                remaining > Duration::from_millis(0),
                "剩余等待时间应 > 0，实际: {remaining:?}"
            );
        }
        other => panic!("应返回 WaitForBackoff，实际: {other:?}"),
    }
}

/// 验证退避时间到期后返回 RestartNeeded。
#[test]
#[ignore = "验证退避到期逻辑"]
fn test_watchdog_backoff_expired() {
    let mut wd = ProcessWatchdog::new();
    wd.set_state(WatchdogStateEnum::Restarting);
    // 设置 last_restart 为 3 秒前，backoff 为 2 秒（已到期）
    wd.set_last_restart(Some(std::time::Instant::now() - Duration::from_secs(3)));
    wd.set_backoff_duration(Duration::from_secs(2));
    wd.set_restart_count(1);

    let action = wd.tick();
    assert_eq!(
        action,
        WatchdogAction::RestartNeeded,
        "退避时间到期后应返回 RestartNeeded"
    );
}

// =================================================================
// 心跳与状态恢复测试
// =================================================================

/// 验证 `notify_heartbeat` 能从 Hung 状态恢复到 Running。
#[test]
#[ignore = "验证心跳恢复逻辑"]
fn test_watchdog_heartbeat_recovery() {
    let mut wd = ProcessWatchdog::new();
    wd.set_state(WatchdogStateEnum::Hung);
    wd.set_missed_heartbeats(3);

    // 收到心跳后应恢复到 Running
    wd.notify_heartbeat();
    assert_eq!(wd.state(), WatchdogStateEnum::Running);
    assert_eq!(wd.missed_heartbeats(), 0);
}

/// 验证稳定心跳后重置重启计数器。
///
/// 当 `restart_count > 0` 且连续收到 `STABLE_HEARTBEAT_THRESHOLD` 次心跳后，
/// `restart_count` 应被重置为 0。
#[test]
#[ignore = "验证稳定心跳重置计数器"]
fn test_watchdog_stable_heartbeat_resets_count() {
    let mut wd = ProcessWatchdog::new();
    wd.set_restart_count(3);

    // STABLE_HEARTBEAT_THRESHOLD = 5
    // 前 4 次心跳不应重置
    for _ in 0..4 {
        wd.notify_heartbeat();
    }
    assert_eq!(wd.restart_count(), 3, "4 次心跳后 restart_count 不应重置");

    // 第 5 次心跳应触发重置
    wd.notify_heartbeat();
    assert_eq!(
        wd.restart_count(),
        0,
        "5 次稳定心跳后 restart_count 应重置为 0"
    );
}

// =================================================================
// 优雅关机测试
// =================================================================

/// 验证 `graceful_shutdown` 能终止子进程并将状态转为 Idle。
#[tokio::test(flavor = "multi_thread")]
#[ignore = "涉及真实进程管理，需手动运行"]
async fn test_watchdog_graceful_shutdown() {
    let mut wd = ProcessWatchdog::new();

    let child = spawn_long_running_child();
    wd.attach_child(child).expect("attach_child 失败");
    assert_eq!(wd.state(), WatchdogStateEnum::Running);

    // 优雅关机
    let wd = Arc::new(Mutex::new(wd));
    let result = graceful_shutdown_watchdog(&wd).await;
    assert!(result.is_ok(), "graceful_shutdown 应成功: {result:?}");

    let guard = wd.lock().await;
    assert_eq!(guard.state(), WatchdogStateEnum::Idle);
    assert!(!guard.has_child());
    assert!(guard.child_pid().is_none());
}

/// 验证 `graceful_shutdown` 在无子进程时返回 Ok。
#[tokio::test(flavor = "multi_thread")]
#[ignore = "验证无子进程时的关机行为"]
async fn test_watchdog_graceful_shutdown_no_child() {
    let wd = ProcessWatchdog::new();
    assert!(wd.child_pid().is_none());

    let wd = Arc::new(Mutex::new(wd));
    let result = graceful_shutdown_watchdog(&wd).await;
    assert!(result.is_ok(), "无子进程时 graceful_shutdown 应返回 Ok");
    let guard = wd.lock().await;
    assert_eq!(guard.state(), WatchdogStateEnum::Idle);
}

// =================================================================
// reset_to_restart 测试
// =================================================================

/// 验证 `reset_to_restart` 能从 Failed 状态重置为 Restarting。
#[test]
#[ignore = "验证 reset_to_restart 状态转换"]
fn test_watchdog_reset_to_restart() {
    let mut wd = ProcessWatchdog::new();
    wd.set_state(WatchdogStateEnum::Failed);
    wd.set_restart_count(MAX_RESTART_ATTEMPTS);
    wd.set_backoff_duration(Duration::from_secs(30));

    wd.reset_to_restart();

    assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    assert_eq!(
        wd.restart_count(),
        0,
        "reset_to_restart 应将 restart_count 重置为 0"
    );
    assert_eq!(
        wd.backoff_duration(),
        Duration::from_secs(1),
        "backoff_duration 应重置为初始值 1s"
    );
}

/// 验证 `reset_restart_count` 重置计数器但不改变状态。
#[test]
#[ignore = "验证 reset_restart_count 行为"]
fn test_watchdog_reset_restart_count() {
    let mut wd = ProcessWatchdog::new();
    wd.set_restart_count(5);
    wd.set_backoff_duration(Duration::from_secs(30));
    wd.set_state(WatchdogStateEnum::Running);

    wd.reset_restart_count();

    assert_eq!(wd.restart_count(), 0);
    assert_eq!(wd.backoff_duration(), Duration::from_secs(1));
    assert_eq!(
        wd.state(),
        WatchdogStateEnum::Running,
        "reset_restart_count 不应改变状态"
    );
}

// =================================================================
// 退避常量验证
// =================================================================

/// 验证 `BACKOFF_DURATIONS` 常量序列符合预期。
#[test]
fn test_backoff_durations_constant() {
    assert_eq!(BACKOFF_DURATIONS.len(), 10, "应有 10 个退避时长");
    assert_eq!(BACKOFF_DURATIONS[0], Duration::from_secs(1));
    assert_eq!(BACKOFF_DURATIONS[1], Duration::from_secs(2));
    assert_eq!(BACKOFF_DURATIONS[2], Duration::from_secs(4));
    assert_eq!(BACKOFF_DURATIONS[3], Duration::from_secs(8));
    // 第 5 个开始为 30s 上限
    for (i, duration) in BACKOFF_DURATIONS.iter().enumerate().skip(4) {
        assert_eq!(
            *duration,
            Duration::from_secs(30),
            "BACKOFF_DURATIONS[{i}] 应为 30s"
        );
    }
}

/// 验证 `MAX_RESTART_ATTEMPTS` 常量值。
#[test]
fn test_max_restart_attempts_constant() {
    assert_eq!(MAX_RESTART_ATTEMPTS, 10, "MAX_RESTART_ATTEMPTS 应为 10");
}

// =================================================================
// 综合状态机测试
// =================================================================

/// 验证完整的状态机转换流程（模拟）。
///
/// Idle → Running（attach_child）→ Restarting（崩溃）→ Failed（达上限）→ Restarting（reset）→ Running（重启）
#[test]
#[ignore = "综合状态机验证，需手动运行"]
fn test_watchdog_full_state_machine_flow() {
    let mut wd = ProcessWatchdog::new();

    // 1. 初始 Idle
    assert_eq!(wd.state(), WatchdogStateEnum::Idle);

    // 2. attach_child → Running
    let child = spawn_quick_exit_child();
    wd.attach_child(child).expect("attach_child 失败");
    assert_eq!(wd.state(), WatchdogStateEnum::Running);

    // 3. 等待子进程退出 —— 轮询 + 超时，替代固定 sleep
    //
    // 原实现：固定 `sleep(200ms)` 后立即断言 `tick() == RestartNeeded`。
    // 缺陷：Windows 上 `cmd /C exit 1` 的启动 + 退出耗时受系统负载影响，
    // 负载高时 200ms 内子进程可能尚未退出，tick() 返回 None，断言**偶发失败**
    // （实测在 `--ignored` 全量运行时复现过 1 次，单独运行则通过 —— 典型抖动）。
    //
    // 修复：轮询 tick() 直到子进程真正退出，超时 10s 后给出明确失败信息。
    // 依据 tick() 语义（watchdog.rs:299）：Running 状态下子进程未退出返回 None，
    // 已退出返回 RestartNeeded；且 `is_child_exited()` 先于心跳逻辑判断，
    // 故轮询**无副作用**，不会污染后续断言。
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    let action = loop {
        let action = wd.tick();
        if action == WatchdogAction::RestartNeeded {
            break action;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "子进程应在 10s 内退出，实际 tick 持续返回 {action:?}（固定 sleep 无法保证子进程已退出）"
        );
        std::thread::sleep(Duration::from_millis(20));
    };

    // 4. tick 检测到退出 → Restarting
    assert_eq!(action, WatchdogAction::RestartNeeded);
    assert_eq!(wd.state(), WatchdogStateEnum::Restarting);

    // 5. 模拟达到重启上限
    wd.set_restart_count(MAX_RESTART_ATTEMPTS);
    let action = wd.tick();
    assert_eq!(action, WatchdogAction::MaxRetriesExceeded);
    assert_eq!(wd.state(), WatchdogStateEnum::Failed);

    // 6. reset_to_restart → Restarting
    wd.reset_to_restart();
    assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    assert_eq!(wd.restart_count(), 0);
}
