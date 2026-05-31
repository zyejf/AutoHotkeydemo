use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};
use crate::infrastructure::watchdog::ProcessWatchdog;
use asd_domain::config::WatchdogStateEnum;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use std::sync::Arc;
use tokio::sync::Mutex;

/// IPC 桥接器，实现 `IpcSender` trait，连接 Rust 主进程与 AHK 子进程。
///
/// 通过 `interprocess` named pipe 向 AHK 子进程发送命令，
/// 并通过 outbound mpsc 通道转发 AHK→Rust 方向的消息到前端。
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

    pub fn is_pipe_connected(&self) -> bool {
        let ipc_manager = self.ipc_manager.clone();
        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(async move {
                let manager = ipc_manager.lock().await;
                match *manager {
                    Some(ref mgr) => mgr.is_connected().await,
                    None => false,
                }
            })
        })
    }
}

impl IpcSender for IpcBridge {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        let ipc_manager = self.ipc_manager.clone();
        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(async move {
                let manager = ipc_manager.lock().await;
                match *manager {
                    Some(ref mgr) => {
                        if !mgr.is_connected().await {
                            tracing::warn!(
                                "IPC 管道未连接，无法发送命令: {:?}",
                                std::mem::discriminant(&cmd)
                            );
                            return Err("IPC 管道未连接，AHK 执行器可能未启动".to_string());
                        }
                        mgr.send_command(cmd).await.map_err(|e| {
                            tracing::warn!("IPC 发送命令失败: {e}");
                            format!("IPC 通信错误: {e}")
                        })
                    }
                    None => {
                        tracing::warn!("IPC 管理器未初始化，无法发送命令: {:?}", std::mem::discriminant(&cmd));
                        Err("IPC 管理器未初始化，请等待系统就绪".to_string())
                    }
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
            tokio::runtime::Handle::current().block_on(async move {
                let manager = ipc_manager.lock().await;
                match *manager {
                    Some(ref mgr) => {
                        if !mgr.is_connected().await {
                            tracing::warn!(
                                "IPC 管道未连接，无法发送等待命令: {:?}",
                                std::mem::discriminant(&cmd)
                            );
                            return Err("IPC 管道未连接，AHK 执行器可能未启动".to_string());
                        }
                        mgr.send_and_wait(cmd, timeout).await.map_err(|e| {
                            tracing::warn!("IPC send_and_wait 失败: {e}");
                            format!("IPC 通信错误: {e}")
                        })
                    }
                    None => {
                        tracing::warn!("IPC 管理器未初始化，无法发送等待命令: {:?}", std::mem::discriminant(&cmd));
                        Err("IPC 管理器未初始化，请等待系统就绪".to_string())
                    }
                }
            })
        })
    }

    fn send_message(&self, msg: &IpcMessage) -> Result<(), String> {
        let seq = {
            let ipc_manager = self.ipc_manager.clone();
            tokio::task::block_in_place(|| {
                tokio::runtime::Handle::current().block_on(async move {
                    let manager = ipc_manager.lock().await;
                    manager.as_ref().map(|m| m.next_seq()).unwrap_or(0)
                })
            })
        };
        let mut msg_with_seq = msg.clone();
        msg_with_seq.seq = seq;
        self.outbound
            .try_send(msg_with_seq)
            .map_err(|e| e.to_string())
    }
}

/// Tauri 事件桥接器，实现 `EventEmitter` trait，通过 Tauri 事件系统向前端推送事件。
pub struct TauriEventBridge {
    app_handle: tauri::AppHandle,
}

impl TauriEventBridge {
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

/// 进程监控桥接器，实现 `ProcessWatcher` trait，通过 `ProcessWatchdog` 查询 AHK 子进程状态。
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
            tokio::runtime::Handle::current().block_on(async move {
                let guard = watchdog.lock().await;
                guard.state().clone()
            })
        })
    }

    fn restart_count(&self) -> u32 {
        let watchdog = self.watchdog.clone();
        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(async move {
                let guard = watchdog.lock().await;
                guard.restart_count()
            })
        })
    }
}
