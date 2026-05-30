#![no_main]

use asd_tauri_lib::domain::config::Config;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = serde_json::from_slice::<Config>(data);
});
