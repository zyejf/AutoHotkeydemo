use crate::config::WatchdogStateEnum;
use asd_ipc_protocol::{IpcCommand, IpcMessage};

pub trait IpcSender: Send + Sync {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String>;
    fn send_and_wait(
        &self,
        cmd: IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, String> {
        let _ = (cmd, timeout);
        Err("send_and_wait not supported".to_string())
    }
    fn send_message(&self, msg: &IpcMessage) -> Result<(), String> {
        let _ = msg;
        Err("send_message not supported".to_string())
    }
}

pub trait EventEmitter: Send + Sync {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool;
}

pub trait ProcessWatcher: Send + Sync {
    fn state(&self) -> WatchdogStateEnum;
    fn restart_count(&self) -> u32;
}
