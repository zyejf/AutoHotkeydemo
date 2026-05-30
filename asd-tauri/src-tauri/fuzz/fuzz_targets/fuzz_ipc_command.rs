#![no_main]

use asd_tauri_lib::domain::models::IpcCommand;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(cmd) = serde_json::from_slice::<IpcCommand>(data) {
        let _ = serde_json::to_vec(&cmd);
    }
});
