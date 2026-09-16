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
    fn state(&self) -> WatchdogStateEnum;

    fn restart_count(&self) -> u32;

    fn reset(&self) -> Result<(), String> {
        Err("reset not supported".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
    use std::sync::Mutex;
    use std::time::Duration;

    fn sample_cmd() -> IpcCommand {
        IpcCommand::RegisterHotkey {
            hotkey: "F1".to_string(),
            group_id: "g1".to_string(),
        }
    }

    // ------------------------------------------------------------ IpcSender
    // 只实现必选方法 —— 用来验证三个**默认实现**的契约：它们必须是「明确拒绝」
    // 而不是 panic，调用方才能据此降级。

    struct MinimalSender;

    impl IpcSender for MinimalSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Ok(42)
        }
    }

    #[test]
    fn test_send_and_wait_default_rejects() {
        let err = MinimalSender
            .send_and_wait(sample_cmd(), Duration::from_millis(10))
            .unwrap_err();
        assert_eq!(err, "send_and_wait not supported");
    }

    #[test]
    fn test_send_message_default_rejects() {
        let msg = IpcMessage::command(1, &sample_cmd());
        let err = MinimalSender.send_message(&msg).unwrap_err();
        assert_eq!(err, "send_message not supported");
    }

    /// 覆写全部默认方法 —— 证明默认实现**可被覆盖**，不是永远失败的死代码。
    struct FullSender {
        seq: AtomicU64,
    }

    impl IpcSender for FullSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Ok(self.seq.fetch_add(1, Ordering::SeqCst) + 1)
        }

        fn send_and_wait(
            &self,
            cmd: IpcCommand,
            _timeout: std::time::Duration,
        ) -> Result<IpcMessage, String> {
            let seq = self.send_command(cmd)?;
            Ok(IpcMessage::command(seq, &sample_cmd()))
        }

        fn send_message(&self, msg: &IpcMessage) -> Result<(), String> {
            if msg.r#type.is_empty() {
                return Err("empty message type".to_string());
            }
            Ok(())
        }
    }

    #[test]
    fn test_send_command_returns_monotonic_seq() {
        let s = FullSender {
            seq: AtomicU64::new(0),
        };
        assert_eq!(s.send_command(sample_cmd()).unwrap(), 1);
        assert_eq!(s.send_command(sample_cmd()).unwrap(), 2);
    }

    #[test]
    fn test_overridden_send_and_wait_returns_message() {
        let s = FullSender {
            seq: AtomicU64::new(0),
        };
        let msg = s
            .send_and_wait(sample_cmd(), Duration::from_millis(0))
            .unwrap();
        assert_eq!(msg.seq, 1);
    }

    #[test]
    fn test_overridden_send_message_rejects_empty_type() {
        let s = FullSender {
            seq: AtomicU64::new(0),
        };
        let mut msg = IpcMessage::command(1, &sample_cmd());
        msg.r#type = String::new();
        assert!(s.send_message(&msg).is_err());

        msg.r#type = "hotkey".to_string();
        assert!(s.send_message(&msg).is_ok());
    }

    #[test]
    fn test_ipc_sender_is_object_safe_and_send_sync() {
        // 钉住 trait 的 `Send + Sync` 超trait 约束与对象安全性：
        // 谁把这两条改掉，这里就编译不过。
        fn assert_send_sync<T: ?Sized + Send + Sync>() {}
        assert_send_sync::<dyn IpcSender>();

        let boxed: Box<dyn IpcSender> = Box::new(MinimalSender);
        assert_eq!(boxed.send_command(sample_cmd()).unwrap(), 42);
    }

    // ---------------------------------------------------------- EventEmitter

    struct RecordingEmitter {
        events: Mutex<Vec<(String, serde_json::Value)>>,
    }

    impl EventEmitter for RecordingEmitter {
        fn emit(&self, event: &str, payload: serde_json::Value) -> bool {
            self.events
                .lock()
                .unwrap()
                .push((event.to_string(), payload));
            true
        }
    }

    struct NoListenerEmitter;

    impl EventEmitter for NoListenerEmitter {
        fn emit(&self, _event: &str, _payload: serde_json::Value) -> bool {
            false
        }
    }

    #[test]
    fn test_emit_records_event_and_payload() {
        let e = RecordingEmitter {
            events: Mutex::new(Vec::new()),
        };
        assert!(e.emit("config-changed", serde_json::json!({ "id": 1 })));

        let events = e.events.lock().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].0, "config-changed");
        assert_eq!(events[0].1, serde_json::json!({ "id": 1 }));
    }

    #[test]
    fn test_emit_returns_false_when_no_listener() {
        assert!(!NoListenerEmitter.emit("config-changed", serde_json::json!(null)));
    }

    // --------------------------------------------------------- ProcessWatcher

    struct FakeWatcher {
        state: WatchdogStateEnum,
        restarts: u32,
    }

    impl ProcessWatcher for FakeWatcher {
        fn state(&self) -> WatchdogStateEnum {
            self.state.clone()
        }

        fn restart_count(&self) -> u32 {
            self.restarts
        }
    }

    #[test]
    fn test_process_watcher_reports_state_and_restart_count() {
        let w = FakeWatcher {
            state: WatchdogStateEnum::Running,
            restarts: 3,
        };
        assert_eq!(w.state(), WatchdogStateEnum::Running);
        assert_eq!(w.restart_count(), 3);
    }

    #[test]
    fn test_process_watcher_default_reset_rejects() {
        let w = FakeWatcher {
            state: WatchdogStateEnum::Idle,
            restarts: 0,
        };
        assert_eq!(w.reset().unwrap_err(), "reset not supported");
    }

    struct ResettableWatcher {
        resets: AtomicU32,
    }

    impl ProcessWatcher for ResettableWatcher {
        fn state(&self) -> WatchdogStateEnum {
            WatchdogStateEnum::Idle
        }

        fn restart_count(&self) -> u32 {
            0
        }

        fn reset(&self) -> Result<(), String> {
            self.resets.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
    }

    #[test]
    fn test_overridden_reset_succeeds_and_counts() {
        let w = ResettableWatcher {
            resets: AtomicU32::new(0),
        };
        assert!(w.reset().is_ok());
        assert!(w.reset().is_ok());
        assert_eq!(w.resets.load(Ordering::SeqCst), 2);
    }
}
