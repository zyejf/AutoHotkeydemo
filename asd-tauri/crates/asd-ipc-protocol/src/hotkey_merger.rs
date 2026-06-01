use crate::message::IpcMessage;
use std::collections::HashMap;

const HOTKEY_MERGE_WINDOW_MS: u64 = 100;

pub struct HotkeyMerger {
    buffer: HashMap<String, IpcMessage>,
    merge_window: std::time::Duration,
    last_flush: std::time::Instant,
}

impl HotkeyMerger {
    pub fn new(merge_window_ms: u64) -> Self {
        Self {
            buffer: HashMap::new(),
            merge_window: std::time::Duration::from_millis(merge_window_ms),
            last_flush: std::time::Instant::now(),
        }
    }

    pub fn merge_window(&self) -> std::time::Duration {
        self.merge_window
    }

    pub fn push(&mut self, msg: IpcMessage) {
        let hotkey = msg
            .keys
            .as_ref()
            .and_then(|k| k.first())
            .cloned()
            .unwrap_or_default();
        if hotkey.is_empty() {
            return;
        }
        self.buffer.insert(hotkey, msg);
    }

    pub fn should_flush(&self) -> bool {
        self.last_flush.elapsed() >= self.merge_window && !self.buffer.is_empty()
    }

    pub fn flush(&mut self) -> Vec<IpcMessage> {
        self.last_flush = std::time::Instant::now();
        self.buffer.drain().map(|(_, v)| v).collect()
    }
}

impl Default for HotkeyMerger {
    fn default() -> Self {
        Self::new(HOTKEY_MERGE_WINDOW_MS)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn test_hotkey_merger_new_custom_window() {
        let merger = HotkeyMerger::new(200);
        assert_eq!(merger.merge_window(), Duration::from_millis(200));
    }

    #[test]
    fn test_hotkey_merger_default_window() {
        let merger = HotkeyMerger::default();
        assert_eq!(merger.merge_window(), Duration::from_millis(100));
    }

    #[test]
    fn test_hotkey_merger_push_and_flush() {
        let mut merger = HotkeyMerger::new(50);
        merger.push(IpcMessage::hotkey_event(1, "F1"));
        merger.push(IpcMessage::hotkey_event(2, "F2"));
        merger.push(IpcMessage::hotkey_event(3, "F1"));

        assert!(!merger.should_flush());

        std::thread::sleep(Duration::from_millis(60));
        assert!(merger.should_flush());

        let flushed = merger.flush();
        assert_eq!(
            flushed.len(),
            2,
            "F1 and F2 each one, F1 overwritten with latest"
        );

        let flushed_again = merger.flush();
        assert!(flushed_again.is_empty());
    }

    #[test]
    fn test_hotkey_merger_should_flush_empty_buffer() {
        let merger = HotkeyMerger::new(10);
        assert!(!merger.should_flush());
    }

    #[test]
    fn test_hotkey_merger_flush_resets_timer() {
        let mut merger = HotkeyMerger::new(50);
        merger.push(IpcMessage::hotkey_event(1, "F1"));

        std::thread::sleep(Duration::from_millis(60));
        assert!(merger.should_flush());

        merger.flush();

        merger.push(IpcMessage::hotkey_event(2, "F2"));
        assert!(!merger.should_flush());
    }

    #[test]
    fn test_hotkey_merger_same_key_overwrite() {
        let mut merger = HotkeyMerger::new(50);
        merger.push(IpcMessage::hotkey_event(1, "F1"));
        merger.push(IpcMessage::hotkey_event(2, "F1"));
        merger.push(IpcMessage::hotkey_event(3, "F1"));

        std::thread::sleep(Duration::from_millis(60));
        let flushed = merger.flush();
        assert_eq!(flushed.len(), 1, "same hotkey should keep only latest");

        let msg = &flushed[0];
        assert_eq!(msg.seq, 3, "should keep seq=3 message");
    }
}
