use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};
use crate::infrastructure::watchdog::ProcessWatchdog;
use asd_domain::config::WatchdogStateEnum;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use std::sync::Arc;
use tokio::sync::Mutex;

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
        let seq = {
            let manager = self.ipc_manager.blocking_lock();
            manager.as_ref().map(|m| m.next_seq()).unwrap_or(0)
        };
        let msg = IpcMessage::command(seq, &cmd);
        self.outbound.try_send(msg).map_err(|e| e.to_string())?;
        Ok(seq)
    }

    fn send_and_wait(
        &self,
        cmd: IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        let _ = (cmd, timeout);
        Err("send_and_wait requires async context, use try_send_ipc_command instead".to_string())
    }

    fn send_message(&self, msg: &IpcMessage) -> Result<(), String> {
        let seq = {
            let manager = self.ipc_manager.blocking_lock();
            manager.as_ref().map(|m| m.next_seq()).unwrap_or(0)
        };
        let mut msg_with_seq = msg.clone();
        msg_with_seq.seq = seq;
        self.outbound
            .try_send(msg_with_seq)
            .map_err(|e| e.to_string())
    }
}

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
        let guard = self.watchdog.blocking_lock();
        guard.state().clone()
    }

    fn restart_count(&self) -> u32 {
        let guard = self.watchdog.blocking_lock();
        guard.restart_count()
    }
}
