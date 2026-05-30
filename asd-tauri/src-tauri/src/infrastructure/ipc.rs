use crate::domain::models::{IpcCommand, IpcMessage};
use interprocess::local_socket::{
    tokio::{Listener, Stream},
    traits::tokio::Stream as StreamTrait,
    GenericNamespaced, ListenerOptions, ToNsName,
};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot, Mutex};

const MAX_MESSAGE_SIZE: usize = 64 * 1024;
const IPC_CHANNEL_CAPACITY: usize = 256;
const HOTKEY_MERGE_WINDOW_MS: u64 = 100;
/// C-14: Named Pipe 认证令牌，AHK 客户端连接后必须发送此令牌
const IPC_AUTH_TOKEN: &str = "ASD_IPC_AUTH_V1";

#[derive(Debug, thiserror::Error)]
pub enum IpcError {
    #[error("连接已关闭")]
    ConnectionClosed,
    #[error("消息超过大小上限: {0} > {1}")]
    MessageTooLarge(usize, usize),
    #[error("收到空行")]
    EmptyMessage,
    #[error("JSON 解析错误: {0}")]
    JsonError(String),
    #[error("IO 错误: {0}")]
    IoError(String),
    #[error("等待响应超时")]
    Timeout,
    #[error("通道已关闭")]
    ChannelClosed,
    #[error("管道断裂: {0}")]
    PipeBroken(String),
    #[error("命名管道错误: {0}")]
    NameError(String),
    /// C-14: Named Pipe 认证失败
    #[error("IPC 认证失败: {0}")]
    AuthFailed(String),
}

impl From<std::io::Error> for IpcError {
    fn from(e: std::io::Error) -> Self {
        let msg = e.to_string();
        if msg.contains("broken pipe")
            || msg.contains("Broken pipe")
            || msg.contains("远程端已关闭")
            || msg.contains("No process")
        {
            IpcError::PipeBroken(msg)
        } else {
            IpcError::IoError(msg)
        }
    }
}

impl From<serde_json::Error> for IpcError {
    fn from(e: serde_json::Error) -> Self {
        IpcError::JsonError(e.to_string())
    }
}

type RecvHalf = <Stream as StreamTrait>::RecvHalf;
type SendHalf = <Stream as StreamTrait>::SendHalf;

pub type IpcOutboundSender = mpsc::Sender<IpcMessage>;
pub type IpcOutboundReceiver = mpsc::Receiver<IpcMessage>;

struct PendingResponse {
    tx: oneshot::Sender<IpcMessage>,
    created_at: std::time::Instant,
}

type IpcCallback = Arc<dyn Fn() + Send + Sync>;

pub struct IpcManager {
    send_half: Arc<Mutex<Option<SendHalf>>>,
    recv_half: Arc<Mutex<Option<BufReader<RecvHalf>>>>,
    seq_counter: Arc<AtomicU64>,
    pending_responses: Arc<Mutex<HashMap<u64, PendingResponse>>>,
    outbound_tx: IpcOutboundSender,
    pipe_name: Arc<String>,
    on_pipe_broken: Arc<std::sync::Mutex<Option<IpcCallback>>>,
    on_heartbeat: Arc<std::sync::Mutex<Option<IpcCallback>>>,
    /// 关机标志：为 true 时抑制 pipe_broken 回调，避免关机期间误触发 Recovering 状态
    shutting_down: Arc<AtomicBool>,
}

impl Clone for IpcManager {
    fn clone(&self) -> Self {
        Self {
            send_half: self.send_half.clone(),
            recv_half: self.recv_half.clone(),
            seq_counter: self.seq_counter.clone(),
            pending_responses: self.pending_responses.clone(),
            outbound_tx: self.outbound_tx.clone(),
            pipe_name: self.pipe_name.clone(),
            on_pipe_broken: self.on_pipe_broken.clone(),
            on_heartbeat: self.on_heartbeat.clone(),
            shutting_down: self.shutting_down.clone(),
        }
    }
}

impl IpcManager {
    pub fn new(pipe_name: &str) -> (Self, IpcOutboundReceiver) {
        let (outbound_tx, outbound_rx) = mpsc::channel(IPC_CHANNEL_CAPACITY);
        let manager = Self {
            send_half: Arc::new(Mutex::new(None)),
            recv_half: Arc::new(Mutex::new(None)),
            seq_counter: Arc::new(AtomicU64::new(1)),
            pending_responses: Arc::new(Mutex::new(HashMap::new())),
            outbound_tx,
            pipe_name: Arc::new(pipe_name.to_string()),
            on_pipe_broken: Arc::new(std::sync::Mutex::new(None)),
            on_heartbeat: Arc::new(std::sync::Mutex::new(None)),
            shutting_down: Arc::new(AtomicBool::new(false)),
        };
        (manager, outbound_rx)
    }

    pub fn with_outbound_channel(pipe_name: &str) -> (Self, IpcOutboundReceiver) {
        Self::new(pipe_name)
    }

    pub fn set_pipe_broken_callback(&self, cb: Arc<dyn Fn() + Send + Sync>) {
        *self.on_pipe_broken.lock().unwrap() = Some(cb);
    }

    pub fn set_heartbeat_callback(&self, cb: Arc<dyn Fn() + Send + Sync>) {
        *self.on_heartbeat.lock().unwrap() = Some(cb);
    }

    /// 标记正在关机，抑制后续 pipe_broken 回调
    pub fn mark_shutting_down(&self) {
        self.shutting_down.store(true, Ordering::SeqCst);
        tracing::info!("IPC: shutting_down 标志已设置");
    }

    /// 查询是否正在关机
    pub fn is_shutting_down(&self) -> bool {
        self.shutting_down.load(Ordering::SeqCst)
    }

    pub async fn connect_to_ahk(&self) -> Result<(), IpcError> {
        let name = (*self.pipe_name).clone().to_ns_name::<GenericNamespaced>()
            .map_err(|e| IpcError::NameError(e.to_string()))?;
        let stream = Stream::connect(name).await?;
        let (recv, send) = stream.split();

        *self.send_half.lock().await = Some(send);
        *self.recv_half.lock().await = Some(BufReader::new(recv));

        tracing::info!("IPC 已连接到 AHK 管道: {}", self.pipe_name);
        Ok(())
    }

    pub async fn accept_from_ahk(&self, listener: &Listener) -> Result<(), IpcError> {
        use interprocess::local_socket::traits::tokio::Listener as ListenerTrait;
        let stream = listener
            .accept()
            .await
            .map_err(|e| IpcError::IoError(e.to_string()))?;
        let (recv, send) = stream.split();

        *self.send_half.lock().await = Some(send);
        *self.recv_half.lock().await = Some(BufReader::new(recv));

        // C-14: 验证认证消息 — 首条消息必须是 auth 类型且 token 匹配
        match self.recv().await {
            Ok(msg) if msg.r#type == "auth" => {
                let token = msg
                    .data
                    .as_ref()
                    .and_then(|d| d.get("token"))
                    .and_then(|t| t.as_str())
                    .unwrap_or("");
                if token != IPC_AUTH_TOKEN {
                    self.cleanup_connection().await;
                    tracing::warn!("IPC AHK 认证失败: token 不匹配");
                    return Err(IpcError::AuthFailed("token 不匹配".to_string()));
                }
                tracing::info!("IPC AHK 认证成功");
            }
            Ok(msg) => {
                self.cleanup_connection().await;
                tracing::warn!(
                    "IPC AHK 认证失败: 首条消息类型为 {}，期望 auth",
                    msg.r#type
                );
                return Err(IpcError::AuthFailed(format!(
                    "首条消息类型为 {}，期望 auth",
                    msg.r#type
                )));
            }
            Err(e) => {
                self.cleanup_connection().await;
                tracing::warn!("IPC AHK 认证失败: 读取认证消息出错: {e}");
                return Err(e);
            }
        }

        tracing::info!("IPC 已接受 AHK 连接（已认证）");
        Ok(())
    }

    pub async fn accept_loop(&self, listener: &Listener) {
        loop {
            if self.shutting_down.load(Ordering::SeqCst) {
                tracing::info!("IPC: 关机中，退出 accept 循环");
                break;
            }
            tracing::info!("IPC 等待 AHK 连接...");
            if let Err(e) = self.accept_from_ahk(listener).await {
                if self.shutting_down.load(Ordering::SeqCst) {
                    tracing::info!("IPC: 关机中，退出 accept 循环");
                    break;
                }
                tracing::error!("IPC 接受连接失败: {e}");
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                continue;
            }
            self.listen_ahk().await;
            if self.shutting_down.load(Ordering::SeqCst) {
                tracing::info!("IPC: 关机中，退出 accept 循环");
                break;
            }
            tracing::warn!("IPC 管道断裂，等待重连...");
        }
    }

    pub fn next_seq(&self) -> u64 {
        self.seq_counter.fetch_add(1, Ordering::Relaxed)
    }

    pub async fn send(&self, msg: &IpcMessage) -> Result<(), IpcError> {
        let mut line = serde_json::to_string(msg)?;
        line.push('\n');
        let bytes = line.as_bytes();
        if bytes.len() > MAX_MESSAGE_SIZE {
            return Err(IpcError::MessageTooLarge(bytes.len(), MAX_MESSAGE_SIZE));
        }

        let mut writer_guard = self.send_half.lock().await;
        let writer = writer_guard
            .as_mut()
            .ok_or(IpcError::ConnectionClosed)?;

        match writer.write_all(bytes).await {
            Ok(()) => {
                let _ = writer.flush().await;
                Ok(())
            }
            Err(e) => {
                let ipc_err = IpcError::from(e);
                if matches!(ipc_err, IpcError::PipeBroken(_)) {
                    *writer_guard = None;
                    self.notify_pipe_broken().await;
                }
                Err(ipc_err)
            }
        }
    }

    pub async fn send_command(&self, cmd: IpcCommand) -> Result<u64, IpcError> {
        let seq = self.next_seq();
        let msg = IpcMessage::command(seq, &cmd);
        self.send(&msg).await?;
        Ok(seq)
    }

    pub async fn wait_response(
        &self,
        seq: u64,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, IpcError> {
        let (tx, rx) = oneshot::channel();
        {
            let mut pending = self.pending_responses.lock().await;
            pending.insert(
                seq,
                PendingResponse {
                    tx,
                    created_at: std::time::Instant::now(),
                },
            );
        }

        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(msg)) => Ok(msg),
            Ok(Err(_)) => {
                let mut pending = self.pending_responses.lock().await;
                pending.remove(&seq);
                Err(IpcError::ChannelClosed)
            }
            Err(_) => {
                let mut pending = self.pending_responses.lock().await;
                pending.remove(&seq);
                Err(IpcError::Timeout)
            }
        }
    }

    pub async fn send_and_wait(
        &self,
        cmd: IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, IpcError> {
        let seq = self.send_command(cmd).await?;
        self.wait_response(seq, timeout).await
    }

    pub async fn recv(&self) -> Result<IpcMessage, IpcError> {
        let mut reader_guard = self.recv_half.lock().await;
        let reader = reader_guard
            .as_mut()
            .ok_or(IpcError::ConnectionClosed)?;

        let mut line = String::with_capacity(256);
        match reader.read_line(&mut line).await {
            Ok(0) => {
                *reader_guard = None;
                Err(IpcError::ConnectionClosed)
            }
            Ok(_) => {
                let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
                if trimmed.is_empty() {
                    return Err(IpcError::EmptyMessage);
                }
                if trimmed.len() > MAX_MESSAGE_SIZE {
                    return Err(IpcError::MessageTooLarge(trimmed.len(), MAX_MESSAGE_SIZE));
                }
                let msg: IpcMessage = serde_json::from_str(trimmed)?;
                Ok(msg)
            }
            Err(e) => {
                let ipc_err = IpcError::from(e);
                if matches!(ipc_err, IpcError::PipeBroken(_)) {
                    *reader_guard = None;
                }
                Err(ipc_err)
            }
        }
    }

    async fn dispatch_response(&self, msg: IpcMessage) -> bool {
        if let Some(ack) = msg.ack_seq {
            let mut pending = self.pending_responses.lock().await;
            if let Some(p) = pending.remove(&ack) {
                let _ = p.tx.send(msg);
                return true;
            }
        }
        false
    }

    pub async fn listen_ahk(&self) {
        tracing::info!("IPC 开始监听 AHK 消息");
        loop {
            match self.recv().await {
                Ok(msg) => {
                    if self.dispatch_response(msg.clone()).await {
                        continue;
                    }

                    if msg.r#type == "pong" {
                        let cb = self.on_heartbeat.lock().unwrap().clone();
                        if let Some(cb) = cb {
                            cb();
                        }
                        continue;
                    }

                    if msg.r#type == "hotkey" {
                        if let Err(e) = self.handle_hotkey_with_merge(msg).await {
                            tracing::warn!("热键消息处理失败: {e}");
                        }
                    } else {
                        let _ = self.outbound_tx.send(msg).await;
                    }
                }
                Err(IpcError::ConnectionClosed) | Err(IpcError::PipeBroken(_)) => {
                    tracing::warn!("IPC 管道断裂，等待重连");
                    self.notify_pipe_broken().await;
                    break;
                }
                Err(e) => {
                    tracing::warn!("IPC 接收错误: {e}");
                }
            }
        }
    }

    async fn handle_hotkey_with_merge(&self, msg: IpcMessage) -> Result<(), IpcError> {
        let hotkey = msg
            .keys
            .as_ref()
            .and_then(|k| k.first())
            .cloned()
            .unwrap_or_default();

        let merged_msg = IpcMessage {
            id: None,
            r#type: "hotkey".to_string(),
            seq: msg.seq,
            ack_seq: msg.ack_seq,
            action: msg.action.clone(),
            keys: Some(vec![hotkey]),
            delay: None,
            status: None,
            data: msg.data.clone(),
        };

        let _ = self.outbound_tx.send(merged_msg).await;
        Ok(())
    }

    async fn notify_pipe_broken(&self) {
        self.cleanup_connection().await;
        if self.shutting_down.load(Ordering::SeqCst) {
            tracing::info!("IPC: 关机期间管道断裂，跳过 pipe_broken 回调");
            return;
        }
        let cb = self.on_pipe_broken.lock().unwrap().clone();
        if let Some(cb) = cb {
            cb();
        }
    }

    async fn cleanup_connection(&self) {
        *self.send_half.lock().await = None;
        *self.recv_half.lock().await = None;
        let mut pending = self.pending_responses.lock().await;
        for (_, p) in pending.drain() {
            let _ = p.tx.send(IpcMessage {
                id: None,
                r#type: "error".to_string(),
                seq: 0,
                ack_seq: None,
                action: None,
                keys: None,
                delay: None,
                status: None,
                data: Some(serde_json::json!({"error": "pipe_broken"})),
            });
        }
    }

    pub async fn is_connected(&self) -> bool {
        self.send_half.lock().await.is_some()
    }

    pub fn outbound_sender(&self) -> IpcOutboundSender {
        self.outbound_tx.clone()
    }

    pub async fn cleanup_stale_pending(&self, max_age: std::time::Duration) {
        let mut pending = self.pending_responses.lock().await;
        let now = std::time::Instant::now();
        pending.retain(|_, p| now.duration_since(p.created_at) < max_age);
    }
}

pub fn create_listener(
    pipe_name: &str,
) -> Result<Listener, Box<dyn std::error::Error + Send + Sync>> {
    let name = pipe_name.to_ns_name::<GenericNamespaced>()?;
    let opts = ListenerOptions::new().name(name);
    let listener = opts.create_tokio()?;
    Ok(listener)
}

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
    use crate::domain::models::IpcCommand;
    use std::time::Duration;

    // ---- HotkeyMerger 测试 ----

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
        merger.push(IpcMessage::hotkey_event(3, "F1")); // 覆盖 F1 的旧消息

        // 还未到合并窗口，不应 flush
        assert!(!merger.should_flush());

        // 等待合并窗口过期
        std::thread::sleep(Duration::from_millis(60));
        assert!(merger.should_flush());

        let flushed = merger.flush();
        assert_eq!(flushed.len(), 2, "F1 和 F2 各一条，F1 被覆盖后只有最新的一条");

        // flush 后 buffer 应为空
        let flushed_again = merger.flush();
        assert!(flushed_again.is_empty());
    }

    #[test]
    fn test_hotkey_merger_should_flush_empty_buffer() {
        let merger = HotkeyMerger::new(10);
        // 即使时间过了，空 buffer 也不应 flush
        assert!(!merger.should_flush());
    }

    #[test]
    fn test_hotkey_merger_flush_resets_timer() {
        let mut merger = HotkeyMerger::new(50);
        merger.push(IpcMessage::hotkey_event(1, "F1"));

        std::thread::sleep(Duration::from_millis(60));
        assert!(merger.should_flush());

        merger.flush();

        // flush 后重新 push，需要再等一个窗口
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
        assert_eq!(flushed.len(), 1, "同一热键应只保留最新一条");

        let msg = &flushed[0];
        assert_eq!(msg.seq, 3, "应保留 seq=3 的消息");
    }

    // ---- IpcMessage 构造方法测试 ----

    #[test]
    fn test_ipc_message_command_toggle_group() {
        let cmd = IpcCommand::ToggleGroup {
            group_id: "1".to_string(),
            active: true,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        let msg = IpcMessage::command(42, &cmd);

        assert_eq!(msg.r#type, "command");
        assert_eq!(msg.seq, 42);
        assert_eq!(msg.action.as_deref(), Some("toggle_group"));
        assert!(msg.data.is_some());
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "1");
        assert_eq!(msg.data.as_ref().unwrap()["active"], true);
        assert!(msg.ack_seq.is_none());
    }

    #[test]
    fn test_ipc_message_command_register_hotkey() {
        let cmd = IpcCommand::RegisterHotkey {
            hotkey: "F1".to_string(),
            group_id: "1".to_string(),
        };
        let msg = IpcMessage::command(10, &cmd);

        assert_eq!(msg.action.as_deref(), Some("register_hotkey"));
        assert_eq!(msg.data.as_ref().unwrap()["hotkey"], "F1");
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "1");
    }

    #[test]
    fn test_ipc_message_command_unregister_hotkey() {
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey: "F2".to_string(),
        };
        let msg = IpcMessage::command(11, &cmd);

        assert_eq!(msg.action.as_deref(), Some("unregister_hotkey"));
        assert_eq!(msg.data.as_ref().unwrap()["hotkey"], "F2");
    }

    #[test]
    fn test_ipc_message_command_start_recording() {
        let cmd = IpcCommand::StartRecording {
            group_id: "3".to_string(),
            mode: "periodic".to_string(),
        };
        let msg = IpcMessage::command(12, &cmd);

        assert_eq!(msg.action.as_deref(), Some("start_recording"));
        assert_eq!(msg.data.as_ref().unwrap()["groupId"], "3");
        assert_eq!(msg.data.as_ref().unwrap()["mode"], "periodic");
    }

    #[test]
    fn test_ipc_message_command_no_data_variants() {
        // 这些命令不应携带 data 字段
        let no_data_cmds = vec![
            IpcCommand::StopRecording,
            IpcCommand::EmergencyRelease,
            IpcCommand::Ping,
            IpcCommand::Shutdown,
        ];
        for (i, cmd) in no_data_cmds.into_iter().enumerate() {
            let msg = IpcMessage::command(i as u64, &cmd);
            assert!(msg.data.is_none(), "命令 {:?} 不应有 data", cmd);
        }
    }

    #[test]
    fn test_ipc_message_command_hold_mode_toggle() {
        let cmd = IpcCommand::HoldModeToggle { enabled: true };
        let msg = IpcMessage::command(20, &cmd);

        assert_eq!(msg.action.as_deref(), Some("hold_mode_toggle"));
        assert_eq!(msg.data.as_ref().unwrap()["enabled"], true);
    }

    #[test]
    fn test_ipc_message_response() {
        let msg = IpcMessage::response(
            100,
            42,
            "ok",
            Some(serde_json::json!({"result": "success"})),
        );

        assert_eq!(msg.r#type, "response");
        assert_eq!(msg.seq, 100);
        assert_eq!(msg.ack_seq, Some(42));
        assert_eq!(msg.status.as_deref(), Some("ok"));
        assert!(msg.data.is_some());
        assert!(msg.action.is_none());
    }

    #[test]
    fn test_ipc_message_response_no_data() {
        let msg = IpcMessage::response(100, 42, "error", None);
        assert!(msg.data.is_none());
    }

    #[test]
    fn test_ipc_message_ping() {
        let msg = IpcMessage::ping(1);
        assert_eq!(msg.r#type, "ping");
        assert_eq!(msg.seq, 1);
        assert!(msg.ack_seq.is_none());
        assert!(msg.action.is_none());
        assert!(msg.keys.is_none());
    }

    #[test]
    fn test_ipc_message_pong() {
        let msg = IpcMessage::pong(2, 1);
        assert_eq!(msg.r#type, "pong");
        assert_eq!(msg.seq, 2);
        assert_eq!(msg.ack_seq, Some(1));
    }

    #[test]
    fn test_ipc_message_execute() {
        let msg = IpcMessage::execute(5, vec!["1".to_string(), "2".to_string()], 100);
        assert_eq!(msg.r#type, "execute");
        assert_eq!(msg.seq, 5);
        assert_eq!(msg.action.as_deref(), Some("keypress"));
        assert_eq!(msg.keys.as_deref(), Some(&["1".to_string(), "2".to_string()][..]));
        assert_eq!(msg.delay, Some(100));
    }

    #[test]
    fn test_ipc_message_result() {
        let data = serde_json::json!({"status": "ok", "count": 2});
        let msg = IpcMessage::result(10, 5, data.clone());
        assert_eq!(msg.r#type, "result");
        assert_eq!(msg.seq, 10);
        assert_eq!(msg.ack_seq, Some(5));
        assert_eq!(msg.data.as_ref().unwrap()["status"], "ok");
        assert_eq!(msg.data.as_ref().unwrap()["count"], 2);
    }

    #[test]
    fn test_ipc_message_shutdown() {
        let msg = IpcMessage::shutdown(99);
        assert_eq!(msg.r#type, "shutdown");
        assert_eq!(msg.seq, 99);
        assert_eq!(msg.action.as_deref(), Some("shutdown"));
    }

    #[test]
    fn test_ipc_message_hotkey_event() {
        let msg = IpcMessage::hotkey_event(1, "F1");
        assert_eq!(msg.r#type, "hotkey");
        assert_eq!(msg.action.as_deref(), Some("hotkey_event"));
        assert_eq!(msg.keys.as_deref(), Some(&["F1".to_string()][..]));
    }

    #[test]
    fn test_ipc_message_heartbeat() {
        let msg = IpcMessage::heartbeat(50);
        assert_eq!(msg.r#type, "heartbeat");
        assert_eq!(msg.seq, 50);
        assert!(msg.action.is_none());
    }

    // ---- IpcError 测试 ----

    #[test]
    fn test_ipc_error_from_broken_pipe() {
        let err = std::io::Error::new(std::io::ErrorKind::BrokenPipe, "broken pipe");
        let ipc_err = IpcError::from(err);
        assert!(matches!(ipc_err, IpcError::PipeBroken(_)));
    }

    #[test]
    fn test_ipc_error_from_other_io() {
        let err = std::io::Error::new(std::io::ErrorKind::Other, "some error");
        let ipc_err = IpcError::from(err);
        assert!(matches!(ipc_err, IpcError::IoError(_)));
    }

    #[test]
    fn test_ipc_error_from_json() {
        let json_str = "{invalid}";
        let result: Result<serde_json::Value, _> = serde_json::from_str(json_str);
        if let Err(e) = result {
            let ipc_err = IpcError::from(e);
            assert!(matches!(ipc_err, IpcError::JsonError(_)));
        }
    }

    #[test]
    fn test_ipc_error_display_messages() {
        assert_eq!(format!("{}", IpcError::ConnectionClosed), "连接已关闭");
        assert_eq!(format!("{}", IpcError::EmptyMessage), "收到空行");
        assert_eq!(format!("{}", IpcError::Timeout), "等待响应超时");
        assert_eq!(format!("{}", IpcError::ChannelClosed), "通道已关闭");

        let size_err = IpcError::MessageTooLarge(100, 64);
        assert!(format!("{size_err}").contains("100"));

        let json_err = IpcError::JsonError("parse error".to_string());
        assert!(format!("{json_err}").contains("parse error"));
    }

    // ---- C-14: AuthFailed 错误测试 ----

    #[test]
    fn test_ipc_error_auth_failed() {
        let err = IpcError::AuthFailed("token 不匹配".to_string());
        let msg = format!("{err}");
        assert!(msg.contains("认证失败"), "AuthFailed 显示消息应包含'认证失败': {msg}");
        assert!(msg.contains("token 不匹配"), "AuthFailed 显示消息应包含具体原因: {msg}");
    }

    // ---- IpcManager 基础测试 ----

    #[test]
    fn test_ipc_manager_new() {
        let (manager, _rx) = IpcManager::new("test_pipe");
        assert_eq!(*manager.pipe_name, "test_pipe");
    }

    #[test]
    fn test_ipc_manager_next_seq_monotonic() {
        let (manager, _rx) = IpcManager::new("test_seq");
        let s1 = manager.next_seq();
        let s2 = manager.next_seq();
        let s3 = manager.next_seq();
        assert!(s2 > s1, "seq 应单调递增");
        assert!(s3 > s2, "seq 应单调递增");
    }

    #[test]
    fn test_ipc_manager_clone() {
        let (manager, _rx) = IpcManager::new("test_clone");
        let cloned = manager.clone();
        assert_eq!(*cloned.pipe_name, "test_clone");
    }

    #[tokio::test]
    async fn test_ipc_manager_not_connected_initially() {
        let (manager, _rx) = IpcManager::new("test_not_connected");
        assert!(!manager.is_connected().await);
    }

    // ---- shutting_down 标志测试 ----

    #[test]
    fn test_shutting_down_initially_false() {
        let (manager, _rx) = IpcManager::new("test_shutting_down_init");
        assert!(!manager.is_shutting_down(), "shutting_down 初始值应为 false");
    }

    #[test]
    fn test_mark_shutting_down_sets_flag() {
        let (manager, _rx) = IpcManager::new("test_mark_shutting_down");
        assert!(!manager.is_shutting_down());
        manager.mark_shutting_down();
        assert!(manager.is_shutting_down(), "mark_shutting_down() 后应为 true");
    }

    #[test]
    fn test_shutting_down_shared_across_clones() {
        let (manager, _rx) = IpcManager::new("test_shutting_down_clone");
        let cloned = manager.clone();
        assert!(!manager.is_shutting_down());
        assert!(!cloned.is_shutting_down());

        manager.mark_shutting_down();
        assert!(manager.is_shutting_down(), "原实例标记后应为 true");
        assert!(cloned.is_shutting_down(), "克隆实例应共享同一 Arc<AtomicBool>，也应为 true");
    }

    #[tokio::test]
    async fn test_notify_pipe_broken_suppressed_during_shutdown() {
        let (manager, _rx) = IpcManager::new("test_pipe_broken_suppressed");

        // 设置一个 pipe_broken 回调，如果被调用则 panic
        let called = Arc::new(AtomicBool::new(false));
        let called_clone = called.clone();
        manager.set_pipe_broken_callback(Arc::new(move || {
            called_clone.store(true, Ordering::SeqCst);
        }));

        // 标记关机
        manager.mark_shutting_down();

        // 触发 notify_pipe_broken
        manager.notify_pipe_broken().await;

        assert!(!called.load(Ordering::SeqCst), "关机期间 pipe_broken 回调不应被触发");
    }

    #[tokio::test]
    async fn test_notify_pipe_broken_fires_when_not_shutdown() {
        let (manager, _rx) = IpcManager::new("test_pipe_broken_fires");

        let called = Arc::new(AtomicBool::new(false));
        let called_clone = called.clone();
        manager.set_pipe_broken_callback(Arc::new(move || {
            called_clone.store(true, Ordering::SeqCst);
        }));

        // 不标记关机，直接触发
        manager.notify_pipe_broken().await;

        assert!(called.load(Ordering::SeqCst), "非关机期间 pipe_broken 回调应被触发");
    }
}
