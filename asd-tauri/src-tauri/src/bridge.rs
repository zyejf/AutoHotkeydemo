use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};
use crate::infrastructure::watchdog::ProcessWatchdog;
use asd_domain::config::WatchdogStateEnum;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use std::sync::Arc;
use tokio::sync::Mutex;

/// IPC 桥接器，实现 `IpcSender` trait。
///
/// # block_in_place 使用说明（已知妥协 #2）
///
/// `IpcSender` trait 的方法签名为同步（`fn send_command(&self, ...) -> Result<...>`），
/// 但底层 `IpcManager` 使用 `tokio::sync::Mutex` 和 async 方法。
/// 为在同步方法中调用 async 代码，使用 `tokio::task::block_in_place` +
/// `tauri::async_runtime::block_on()` 模式（T5-03）。
///
/// **安全性分析**：
/// - `block_in_place` 将当前工作线程转为阻塞模式，允许其他工作线程继续执行
/// - `tauri::async_runtime::block_on` 使用 Tauri 全局异步运行时执行，
///   不依赖调用线程是否已处于 `Handle::current()` 可用的运行时上下文
/// - 临界区极短（仅 `lock().await` + `send_command().await`），不会长时间阻塞
/// - 不在 `block_on` 内再次获取同一锁，无死锁风险
///
/// **已知风险**：如果未来在 `block_on` 内引入需要同一工作线程的操作，
/// 可能导致死锁。修改时需确保 `block_on` 内的所有操作不依赖当前工作线程。
pub struct IpcBridge {
    outbound: IpcOutboundSender,
    ipc_manager: Arc<Mutex<Option<IpcManager>>>,
}

impl IpcBridge {
    pub fn new(outbound: IpcOutboundSender, ipc_manager: Arc<Mutex<Option<IpcManager>>>) -> Self {
        Self {
            outbound,
            ipc_manager,
        }
    }
}

impl IpcSender for IpcBridge {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        let ipc_manager = self.ipc_manager.clone();
        tokio::task::block_in_place(|| {
            tauri::async_runtime::block_on(async move {
                let mgr = {
                    let manager = ipc_manager.lock().await;
                    manager.clone()
                };
                if let Some(mgr) = mgr {
                    mgr.send_command(cmd).await.map_err(|e| {
                        tracing::warn!("IPC 发送命令失败: {e}");
                        format!("IPC 通信错误: {e}")
                    })
                } else {
                    tracing::warn!(
                        "IPC 管理器未初始化，无法发送命令: {:?}",
                        std::mem::discriminant(&cmd)
                    );
                    Err("IPC 管理器未初始化，请等待系统就绪".to_string())
                }
            })
        })
    }

    fn send_and_wait(
        &self,
        cmd: IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        let ipc_manager = self.ipc_manager.clone();
        tokio::task::block_in_place(|| {
            tauri::async_runtime::block_on(async move {
                let mgr = {
                    let manager = ipc_manager.lock().await;
                    manager.clone()
                };
                let (seq, rx) = if let Some(mgr) = &mgr {
                    mgr.prepare_send_and_wait(cmd).await.map_err(|e| {
                        tracing::warn!("IPC prepare_send_and_wait 失败: {e}");
                        format!("IPC 通信错误: {e}")
                    })?
                } else {
                    tracing::warn!(
                        "IPC 管理器未初始化，无法发送等待命令: {:?}",
                        std::mem::discriminant(&cmd)
                    );
                    return Err("IPC 管理器未初始化，请等待系统就绪".to_string());
                };

                match tokio::time::timeout(timeout, rx).await {
                    Ok(Ok(msg)) => {
                        // 所有错误响应统一转换为 Err，避免调用方遗漏错误检查。
                        // 错误来源包括：pipe_broken（管道断裂）、pending 超时清理等。
                        if msg.is_error() {
                            let error_str = msg
                                .data
                                .as_ref()
                                .and_then(|d| d.get("error"))
                                .and_then(|v| v.as_str())
                                .unwrap_or("未知错误");
                            if error_str == "pipe_broken" {
                                tracing::warn!(
                                    "IPC 管道断裂，收到 pipe_broken 错误响应 (seq={seq})"
                                );
                                return Err("IPC 管道断裂，请等待重连".to_string());
                            }
                            return Err(format!("IPC 错误响应: {error_str}"));
                        }
                        Ok(msg)
                    }
                    Ok(Err(_)) => {
                        // oneshot 通道关闭，主动清理 pending entry
                        if let Some(mgr) = &mgr {
                            mgr.cleanup_pending_by_seq(seq).await;
                        }
                        Err("IPC 通道已关闭".to_string())
                    }
                    Err(_) => {
                        // 超时，主动清理 pending entry
                        if let Some(mgr) = &mgr {
                            mgr.cleanup_pending_by_seq(seq).await;
                        }
                        Err("IPC 等待响应超时".to_string())
                    }
                }
            })
        })
    }

    fn send_message(&self, msg: &IpcMessage) -> Result<(), String> {
        self.outbound.try_send(msg.clone()).map_err(|e| {
            tracing::warn!("IPC outbound channel 已满，消息被丢弃: {e}");
            e.to_string()
        })
    }
}

/// Tauri 事件桥接器，实现 `EventEmitter` trait，通过 Tauri 事件系统向前端推送事件。
pub struct TauriEventBridge {
    app_handle: tauri::AppHandle,
}

impl TauriEventBridge {
    #[must_use]
    pub fn new(app_handle: tauri::AppHandle) -> Self {
        Self { app_handle }
    }
}

impl EventEmitter for TauriEventBridge {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool {
        use tauri::Emitter;
        self.app_handle.emit(event, payload).is_ok()
    }
}

/// 构造热键事件的 emit payload。
///
/// 从 hotkey 和 keys 构造 `{ "hotkey": ..., "keys": [...] }` JSON 结构。
/// 提取为独立纯函数以便单元测试，无需依赖 `tauri::AppHandle`。
///
/// 此函数被 `spawn_ipc_listener` 调用，将 AHK 子进程上报的热键事件
/// 转换为前端可消费的 JSON payload。
#[must_use]
pub fn build_hotkey_event_payload(hotkey: &str, keys: &[String]) -> serde_json::Value {
    serde_json::json!({
        "hotkey": hotkey,
        "keys": keys,
    })
}

/// 进程监控桥接器，实现 `ProcessWatcher` trait，通过 `ProcessWatchdog` 查询 AHK 子进程状态。
///
/// # block_in_place 使用说明（已知妥协 #2）
///
/// 与 `IpcBridge` 相同的模式：`ProcessWatcher` trait 方法为同步，
/// 底层 `ProcessWatchdog` 使用 `tokio::sync::Mutex` 保护。
/// 使用 `block_in_place` + `tauri::async_runtime::block_on` 在同步方法中获取 async 锁。
///
/// **锁顺序**：仅获取 `watchdog` 锁，不嵌套获取 `ipc_manager` 锁。
/// 与 `setup_ipc_and_watchdog` 中的锁顺序（ipc_manager → watchdog）一致，
/// 不会出现锁反转死锁。
pub struct WatchdogBridge {
    watchdog: Arc<Mutex<ProcessWatchdog>>,
}

impl WatchdogBridge {
    pub fn new(watchdog: Arc<Mutex<ProcessWatchdog>>) -> Self {
        Self { watchdog }
    }
}

impl ProcessWatcher for WatchdogBridge {
    fn state(&self) -> WatchdogStateEnum {
        let watchdog = self.watchdog.clone();
        tokio::task::block_in_place(|| {
            tauri::async_runtime::block_on(async move {
                let guard = watchdog.lock().await;
                guard.state()
            })
        })
    }

    fn restart_count(&self) -> u32 {
        let watchdog = self.watchdog.clone();
        tokio::task::block_in_place(|| {
            tauri::async_runtime::block_on(async move {
                let guard = watchdog.lock().await;
                guard.restart_count()
            })
        })
    }

    fn reset(&self) -> Result<(), String> {
        let watchdog = self.watchdog.clone();
        tokio::task::block_in_place(|| {
            tauri::async_runtime::block_on(async move {
                let mut guard = watchdog.lock().await;
                let current = guard.state();
                match current {
                    WatchdogStateEnum::Failed
                    | WatchdogStateEnum::Hung
                    | WatchdogStateEnum::Recovering => {
                        guard.reset_to_restart();
                        Ok(())
                    }
                    _ => Err(format!(
                        "仅在 Failed/Hung/Recovering 状态下可重置，当前状态: {current:?}"
                    )),
                }
            })
        })
    }
}
