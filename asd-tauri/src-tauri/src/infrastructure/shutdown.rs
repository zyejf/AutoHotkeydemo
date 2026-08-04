//! 优雅关机模块 — 提取关机逻辑的纯函数部分。
//!
//! `perform_graceful_shutdown` 函数中的关机锁获取逻辑被提取为
//! `try_acquire_shutdown_guard` 纯函数，使其可在不启动 Tauri 应用的
//! 情况下进行单元测试。
//!
//! # 设计动机
//!
//! `perform_graceful_shutdown` 原本是一个 async 函数，依赖 `AppState`、
//! `IpcManager`、`Watchdog` 等运行时状态，无法在纯单元测试中验证。
//! 将关机锁获取的原子操作逻辑提取为独立纯函数后，可以仅凭
//! `AtomicBool` 进行测试，无需任何外部依赖。

use std::sync::atomic::{AtomicBool, Ordering};

/// 尝试获取关机锁，防止窗口关闭和托盘退出并发触发关机。
///
/// 使用 `compare_exchange` 原子操作，将 `shutdown_guard` 从 `false`
/// 设置为 `true`。如果已经是 `true`（关机已在进行中），返回 `false`。
///
/// # 参数
///
/// - `shutdown_guard`: 关机保护标志，`false` 表示未在关机，`true` 表示正在关机
///
/// # 返回值
///
/// - `true`: 成功获取关机锁，调用方应继续执行关机逻辑
/// - `false`: 关机已在进行中，调用方应跳过
///
/// # 内存序
///
/// 使用 `SeqCst` 内存序确保全序一致性，防止关机逻辑与其他原子操作
/// 之间的指令重排。
///
/// # 示例
///
/// ```
/// use std::sync::atomic::AtomicBool;
/// use asd_tauri_lib::infrastructure::shutdown::try_acquire_shutdown_guard;
///
/// let guard = AtomicBool::new(false);
/// assert!(try_acquire_shutdown_guard(&guard));  // 首次调用成功
/// assert!(!try_acquire_shutdown_guard(&guard)); // 第二次调用失败
/// ```
pub fn try_acquire_shutdown_guard(shutdown_guard: &AtomicBool) -> bool {
    shutdown_guard
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
}
