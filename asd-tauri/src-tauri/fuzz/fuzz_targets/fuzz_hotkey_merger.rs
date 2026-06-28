#![no_main]

use asd_ipc_protocol::{HotkeyMerger, IpcMessage};
use libfuzzer_sys::fuzz_target;

/// 模糊测试 HotkeyMerger 的 push/flush 逻辑。
///
/// 从任意字节解析多个 IpcMessage，依次 push 到 HotkeyMerger，
/// 验证 should_flush/flush 不会 panic，且 flush 结果可安全消费。
fuzz_target!(|data: &[u8]| {
    // 尝试将输入解析为 JSON 数组（多个消息）
    if let Ok(messages) = serde_json::from_slice::<Vec<IpcMessage>>(data) {
        let mut merger = HotkeyMerger::new(50);

        for msg in messages.iter().take(100) {
            merger.push(msg.clone());
        }

        // should_flush 依赖时间，可能 true 也可能 false，确保不 panic
        let _ = merger.should_flush();

        // flush 消费所有缓冲消息
        let flushed = merger.flush();
        for m in &flushed {
            let _ = m.is_error();
            let _ = &m.r#type;
            let _ = m.seq;
        }

        // 再次 flush 应返回空
        let empty = merger.flush();
        debug_assert!(empty.is_empty(), "二次 flush 应返回空");
    } else {
        // 单消息回退路径
        if let Ok(msg) = serde_json::from_slice::<IpcMessage>(data) {
            let mut merger = HotkeyMerger::default();
            merger.push(msg.clone());
            let _ = merger.should_flush();
            let flushed = merger.flush();
            for m in &flushed {
                let _ = m.is_error();
            }
        }
    }
});
