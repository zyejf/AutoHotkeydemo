use crate::config::WatchdogStateEnum;
use asd_ipc_protocol::{IpcCommand, IpcMessage};

/// IPC 命令发送器 trait，用于向 AHK 子进程发送命令。
///
/// 此 trait 在 `asd-domain` crate 中定义，在 `src-tauri/bridge.rs` 中由 `IpcBridge` 实现。
/// 纯逻辑 crate 通过此 trait 抽象 IPC 通信，不依赖具体的传输实现。
pub trait IpcSender: Send + Sync {
    /// 向 AHK 子进程发送 IPC 命令。
    ///
    /// 返回命令的序列号（单调递增），用于关联响应消息。
    /// 如果管道未连接或管理器未初始化，返回错误描述字符串。
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String>;

    /// 发送 IPC 命令并等待 AHK 子进程的响应。
    ///
    /// 在指定的超时时间内等待与命令序列号匹配的响应消息。
    /// 默认实现返回错误，表示当前实现不支持等待响应。
    fn send_and_wait(
        &self,
        cmd: IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        let _ = (cmd, timeout);
        Err("send_and_wait not supported".to_string())
    }

    /// 转发 AHK→Rust 方向的 IPC 消息到前端。
    ///
    /// 用于将 AHK 子进程产生的消息（如热键事件）通过 outbound 通道转发。
    /// 默认实现返回错误，表示当前实现不支持消息转发。
    fn send_message(&self, msg: &IpcMessage) -> Result<(), String> {
        let _ = msg;
        Err("send_message not supported".to_string())
    }
}

/// 前端事件发射器 trait，用于向前端推送事件。
///
/// 此 trait 在 `asd-domain` crate 中定义，在 `src-tauri/bridge.rs` 中由 `TauriEventBridge` 实现。
/// 通过 Tauri 的事件系统将状态变更通知前端 UI。
pub trait EventEmitter: Send + Sync {
    /// 向前端发射事件。
    ///
    /// 返回 `true` 表示事件成功发送，`false` 表示发送失败（如无监听者）。
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool;
}

/// 进程监控器 trait，用于查询 AHK 子进程的状态。
///
/// 此 trait 在 `asd-domain` crate 中定义，在 `src-tauri/bridge.rs` 中由 `WatchdogBridge` 实现。
/// 通过 `ProcessWatchdog` 查询子进程的运行状态和重启次数。
pub trait ProcessWatcher: Send + Sync {
    /// 获取 AHK 子进程的当前状态。
    fn state(&self) -> WatchdogStateEnum;

    /// 获取 AHK 子进程的累计重启次数。
    fn restart_count(&self) -> u32;
}
