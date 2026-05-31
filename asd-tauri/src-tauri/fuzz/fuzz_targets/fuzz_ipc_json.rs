#![no_main]

use asd_ipc_protocol::IpcMessage;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(msg) = serde_json::from_slice::<IpcMessage>(data) {
        let _ = serde_json::to_vec(&msg);
    }
});
