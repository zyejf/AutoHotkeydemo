#![no_main]

use asd_ipc_protocol::IpcMessage;
use libfuzzer_sys::fuzz_target;

/// 模糊测试 IpcMessage 解析逻辑。
///
/// 与 `fuzz_ipc_json` 不同，此 target 专注于解析后的字段访问和方法调用，
/// 确保任意输入解析后不会在字段访问、is_error() 判断、序列化往返中 panic。
fuzz_target!(|data: &[u8]| {
    if let Ok(msg) = serde_json::from_slice::<IpcMessage>(data) {
        // 访问所有字段，确保不会 panic
        let _ = &msg.id;
        let _ = &msg.r#type;
        let _ = msg.seq;
        let _ = msg.ack_seq;
        let _ = &msg.action;
        let _ = &msg.keys;
        let _ = msg.delay;
        let _ = &msg.status;
        let _ = &msg.data;

        // 调用 is_error() 方法，确保任意字段组合下不 panic
        let _ = msg.is_error();

        // 验证序列化往返不会 panic
        if let Ok(json) = serde_json::to_string(&msg) {
            if let Ok(reparsed) = serde_json::from_str::<IpcMessage>(&json) {
                let _ = reparsed.is_error();
            }
        }

        // 模拟 HotkeyMerger.push 的字段访问模式
        let hotkey = msg
            .keys
            .as_ref()
            .and_then(|k| k.first())
            .cloned()
            .unwrap_or_default();
        let _ = hotkey.is_empty();
    }
});
