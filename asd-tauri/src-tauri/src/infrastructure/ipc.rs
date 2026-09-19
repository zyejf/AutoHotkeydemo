use asd_ipc_protocol::{IpcCommand, IpcMessage};
use interprocess::local_socket::{
    tokio::{Listener, Stream},
    traits::tokio::Stream as StreamTrait,
    GenericNamespaced, ListenerOptions, ToNsName,
};
use parking_lot::Mutex as SyncMutex;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::AsyncReadExt;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot, Mutex};

pub use asd_ipc_protocol::{HotkeyMerger, IpcError};

const MAX_MESSAGE_SIZE: usize = 64 * 1024;
const IPC_CHANNEL_CAPACITY: usize = 512;
/// 单次 IPC 写入（`write_all` + `flush`）的超时阈值。
///
/// T6-05：AHK 子进程挂死且管道写满时，无超时的写入会无限阻塞 Tauri
/// 工作线程，多命令并发可能耗尽线程池。此超时将该窗口限制在 2s 内，
/// 超时视同管道不可靠，清理连接并返回 `SendTimeout`。
const SEND_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(2);
/// `pending_responses` 周期性清理的最大存活时间。
///
/// **约束**: `send_and_wait` 的 timeout 不应超过此值，否则 pending response
/// 会在超时前被清理，导致收到 `ChannelClosed` 而非 `Timeout` 错误。
pub const PENDING_CLEANUP_MAX_AGE: std::time::Duration = std::time::Duration::from_secs(30);

/// IPC named pipe 的**基础名**（不含 `\\.\pipe\` 前缀，也不含每会话后缀）。
///
/// 只作为 [`ipc_pipe_name`] 的前缀与 AHK 侧的回退值使用；**不要**直接拿它去
/// 建监听端，否则又回到「固定管道名」的老问题（见 [`ipc_pipe_name`]）。
///
/// T5-12：从 `lib.rs` 收敛到此，避免 Rust 侧多处硬编码；AHK 执行器
/// `ahk_executor/ipc_client.ahk` 的 `DEFAULT_PIPE_NAME` 后缀必须与此一致，
/// 一致性由 `test_ipc_pipe_name_matches_ahk_client` 守护。
pub const IPC_PIPE_NAME_BASE: &str = "asd_ipc";

/// 把每会话唯一的管道名传给 AHK 子进程所用的环境变量名。
///
/// AHK 侧 `ipc_client.ahk` 用 `EnvGet` 读同名变量；两侧名称由
/// `test_ipc_pipe_name_matches_ahk_client` 守护一致。
pub const IPC_PIPE_NAME_ENV_VAR: &str = "ASD_IPC_PIPE_NAME";

/// 本进程本次会话的管道名缓存（惰性生成一次，之后不再变）。
static PIPE_NAME: std::sync::OnceLock<String> = std::sync::OnceLock::new();

/// 本进程本次会话使用的 IPC 管道名（不含 `\\.\pipe\` 前缀）。
///
/// # 为什么不再用固定名 `asd_ipc`
///
/// 固定名意味着**任何同权本地进程都可以抢先创建同名管道**（squatting）：
/// Rust 侧 `create_listener` 会静默失败（只记一条 `error!` 就 return），
/// IPC 永久不可用且用户无感知；更坏的情况是 AHK 连到冒充者，把
/// `ASD_AUTH_TOKEN` 与全部按键指令交给对方。
/// 加上 `<pid>_<随机>` 后缀后，抢注者必须**猜中**该名字 —— 而名字在每个
/// 进程启动时才生成，抢注窗口收敛到「生成之后、建监听端之前」的极短区间，
/// 且一旦撞名，`create_listener` 会返回错误（可被当作启动失败上报），
/// 不再是静默降级。
///
/// # 遗留：未显式设置 DACL
///
/// `interprocess` 2.4.2 的 `ListenerOptions` 没有暴露安全描述符（DACL）设置
/// 入口，要限定「仅当前用户可连接」得绕过该库直接调 `CreateNamedPipeW`。
/// 当前缓解手段是随机名 + 认证 token（`ASD_AUTH_TOKEN`）：连上来的进程
/// 仍必须在首条消息里回传正确 token 才被接受。DACL 收紧作为独立技术债，
/// 需评估是否替换/包装 `interprocess` 的监听端创建。
#[must_use]
pub fn ipc_pipe_name() -> &'static str {
    PIPE_NAME.get_or_init(|| {
        let mut buf = [0u8; 4];
        let rand = if getrandom::getrandom(&mut buf).is_ok() {
            u32::from_ne_bytes(buf)
        } else {
            // 随机源不可用时退化为「单调递增计数」：不加密学强度，
            // 但至少不会与上一次运行撞名（AUTH_FALLBACK_COUNTER 同理）。
            tracing::warn!("getrandom 不可用，管道名随机段退化为计数器");
            AUTH_FALLBACK_COUNTER.fetch_add(1, Ordering::Relaxed)
        };
        format!("{IPC_PIPE_NAME_BASE}_{}_{rand:08x}", std::process::id())
    })
}

static AUTH_FALLBACK_COUNTER: AtomicU32 = AtomicU32::new(0);

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
    on_pipe_broken: Arc<SyncMutex<Option<IpcCallback>>>,
    on_heartbeat: Arc<SyncMutex<Option<IpcCallback>>>,
    on_post_connect: Arc<SyncMutex<Option<IpcCallback>>>,
    shutting_down: Arc<AtomicBool>,
    hotkey_merger: Arc<Mutex<HotkeyMerger>>,
    auth_token: String,
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
            on_post_connect: self.on_post_connect.clone(),
            shutting_down: self.shutting_down.clone(),
            hotkey_merger: self.hotkey_merger.clone(),
            auth_token: self.auth_token.clone(),
        }
    }
}

impl IpcManager {
    #[must_use]
    pub fn new(pipe_name: &str) -> (Self, IpcOutboundReceiver) {
        let auth_token = generate_auth_token();
        Self::new_with_token(pipe_name, auth_token)
    }

    pub fn new_with_token(pipe_name: &str, auth_token: String) -> (Self, IpcOutboundReceiver) {
        let (outbound_tx, outbound_rx) = mpsc::channel(IPC_CHANNEL_CAPACITY);
        let manager = Self {
            send_half: Arc::new(Mutex::new(None)),
            recv_half: Arc::new(Mutex::new(None)),
            seq_counter: Arc::new(AtomicU64::new(1)),
            pending_responses: Arc::new(Mutex::new(HashMap::new())),
            outbound_tx,
            pipe_name: Arc::new(pipe_name.to_string()),
            on_pipe_broken: Arc::new(SyncMutex::new(None)),
            on_heartbeat: Arc::new(SyncMutex::new(None)),
            on_post_connect: Arc::new(SyncMutex::new(None)),
            shutting_down: Arc::new(AtomicBool::new(false)),
            hotkey_merger: Arc::new(Mutex::new(HotkeyMerger::default())),
            auth_token,
        };
        (manager, outbound_rx)
    }

    #[must_use]
    pub fn auth_token(&self) -> &str {
        &self.auth_token
    }

    #[must_use]
    pub fn with_outbound_channel(pipe_name: &str) -> (Self, IpcOutboundReceiver) {
        Self::new(pipe_name)
    }

    pub fn set_pipe_broken_callback(&self, cb: Arc<dyn Fn() + Send + Sync>) {
        *self.on_pipe_broken.lock() = Some(cb);
    }

    pub fn set_heartbeat_callback(&self, cb: Arc<dyn Fn() + Send + Sync>) {
        *self.on_heartbeat.lock() = Some(cb);
    }

    pub fn set_post_connect_callback(&self, cb: Arc<dyn Fn() + Send + Sync>) {
        *self.on_post_connect.lock() = Some(cb);
    }

    /// 标记正在关机，抑制后续 `pipe_broken` 回调
    pub fn mark_shutting_down(&self) {
        self.shutting_down.store(true, Ordering::SeqCst);
        tracing::info!("IPC: shutting_down 标志已设置");
    }

    /// 查询是否正在关机
    #[must_use]
    pub fn is_shutting_down(&self) -> bool {
        self.shutting_down.load(Ordering::SeqCst)
    }

    /// 作为**客户端**主动连上 AHK 监听的命名管道（Rust 侧发起连接的路径）。
    ///
    /// # Errors
    ///
    /// - `NameError`：管道名转换失败（`to_ns_name` 拒绝非法名）。
    /// - `IoError` / `PipeBroken`：`Stream::connect` 失败 —— 典型是 AHK 侧还没
    ///   开始监听，或管道不存在。这是**可重试**的失败，连上之前状态不变。
    ///
    /// ⚠️ 连上之后**不做认证**：认证只发生在服务端侧（[`accept_from_ahk`](Self::accept_from_ahk)）。
    pub async fn connect_to_ahk(&self) -> Result<(), IpcError> {
        let name = (*self.pipe_name)
            .clone()
            .to_ns_name::<GenericNamespaced>()
            .map_err(|e| IpcError::NameError(e.to_string()))?;
        let stream = Stream::connect(name).await?;
        let (recv, send) = stream.split();

        *self.send_half.lock().await = Some(send);
        *self.recv_half.lock().await = Some(BufReader::new(recv));

        tracing::info!("IPC 已连接到 AHK 管道: {}", self.pipe_name);
        Ok(())
    }

    /// 作为**服务端**接受 AHK 的连接，并校验首条消息必须是 token 匹配的 `auth`。
    ///
    /// # Errors
    ///
    /// - `IoError`：`accept()` 失败。
    /// - `AuthFailed`：首条消息类型不是 `auth`、token 不匹配、或 5 秒内没收到首条消息。
    /// - 读取认证消息时出错则原样返回该错误（`ConnectionClosed` / `PipeBroken` 还会
    ///   额外触发 `notify_pipe_broken`）。
    ///
    /// ⚠️ **任何失败路径都会先 `cleanup_connection()` 再返回** —— 拿到 `Err` 时连接
    /// 已被清空，不能继续复用，必须重新 `accept_from_ahk`。
    /// 认证成功后才会调用 `post_connect_callback`（发送状态恢复命令）。
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
        let auth_result =
            tokio::time::timeout(std::time::Duration::from_secs(5), self.recv()).await;

        match auth_result {
            Ok(Ok(msg)) if msg.r#type == "auth" => {
                let token = msg
                    .data
                    .as_ref()
                    .and_then(|d| d.get("token"))
                    .and_then(|t| t.as_str())
                    .unwrap_or("");
                if !constant_time_eq(token, &self.auth_token) {
                    self.cleanup_connection().await;
                    tracing::warn!("IPC AHK 认证失败: token 不匹配");
                    return Err(IpcError::AuthFailed("token 不匹配".to_string()));
                }
                tracing::info!("IPC AHK 认证成功");
            }
            Ok(Ok(msg)) => {
                self.cleanup_connection().await;
                tracing::warn!("IPC AHK 认证失败: 首条消息类型为 {}，期望 auth", msg.r#type);
                return Err(IpcError::AuthFailed(format!(
                    "首条消息类型为 {}，期望 auth",
                    msg.r#type
                )));
            }
            Ok(Err(e)) => {
                self.cleanup_connection().await;
                if matches!(e, IpcError::ConnectionClosed | IpcError::PipeBroken(_)) {
                    self.notify_pipe_broken().await;
                }
                tracing::warn!("IPC AHK 认证失败: 读取认证消息出错: {e}");
                return Err(e);
            }
            Err(_) => {
                self.cleanup_connection().await;
                tracing::warn!("IPC AHK 认证超时 (5s)");
                return Err(IpcError::AuthFailed("认证超时".to_string()));
            }
        }

        tracing::info!("IPC 已接受 AHK 连接（已认证）");

        // 设计决策：post_connect_callback 在认证成功后、listen_ahk 启动前同步调用。
        // 回调内部 spawn 异步任务发送恢复命令（ToggleGroup/RegisterHotkey/HoldModeToggle），
        // 与后续 listen_ahk 存在理论竞态窗口。但 AHK 子进程在收到恢复命令前不会主动
        // 发送热键事件（钩子尚未注册），因此实际影响有限。
        let cb = self.on_post_connect.lock().clone();
        if let Some(cb) = cb {
            cb();
        }

        Ok(())
    }

    pub async fn accept_loop(&self, listener: &Listener) {
        let mut auth_fail_count: u32 = 0;
        let mut non_auth_fail_count: u32 = 0;
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
                // 认证失败时使用指数退避，防止恶意连接洪泛
                let is_auth_fail = matches!(e, IpcError::AuthFailed(_));
                if is_auth_fail {
                    auth_fail_count += 1;
                    non_auth_fail_count = 0;
                } else {
                    auth_fail_count = 0;
                    non_auth_fail_count += 1;
                    // 连续非认证失败可能表示 listener 损坏（如管道文件系统异常），
                    // 超过阈值后增加退避避免空转消耗 CPU
                    if non_auth_fail_count >= 10 {
                        tracing::error!(
                            "IPC accept_loop 连续 {} 次非认证失败，listener 可能损坏",
                            non_auth_fail_count
                        );
                    }
                }
                // 指数退避: 1, 2, 4, 8, 16, 30 (上限30秒)
                // 使用 saturating_sub 使首次失败延迟为 1 秒 (1 << 0)
                // 限制位移量上限为 5，防止 fail_count >= 65 时位移溢出
                // (1u64 << 64 在 debug 模式 panic，release 模式回绕)
                let fail_count = if auth_fail_count > 0 {
                    auth_fail_count
                } else {
                    non_auth_fail_count
                };
                let shift = (fail_count as usize).saturating_sub(1).min(5);
                let delay_secs = (1u64 << shift).min(30);
                tokio::time::sleep(std::time::Duration::from_secs(delay_secs)).await;
                continue;
            }
            // 连接成功，重置失败计数
            auth_fail_count = 0;
            non_auth_fail_count = 0;
            self.listen_ahk().await;
            if self.shutting_down.load(Ordering::SeqCst) {
                tracing::info!("IPC: 关机中，退出 accept 循环");
                break;
            }
            tracing::warn!("IPC 管道断裂，等待重连...");
        }
    }

    #[must_use]
    pub fn next_seq(&self) -> u64 {
        self.seq_counter.fetch_add(1, Ordering::Relaxed)
    }

    #[must_use]
    pub fn seq_counter(&self) -> Arc<AtomicU64> {
        self.seq_counter.clone()
    }

    /// 把一条 `IpcMessage` 序列化成单行 JSON 写进管道（`write_all` + `flush`，
    /// 两步各自带 `SEND_TIMEOUT`）。
    ///
    /// # Errors
    ///
    /// - `JsonError`（`serde_json` 失败）：消息序列化失败，连接不受影响。
    /// - `MessageTooLarge`：单行超过 `MAX_MESSAGE_SIZE`，**发送前**就被拒，
    ///   管道里没有留下半个消息。
    /// - `ConnectionClosed`：还没有建立连接（`send_half` 为空）。
    /// - `SendTimeout`：写或 flush 超时 —— 视同管道不可靠，会清空 `send_half`
    ///   并触发 `notify_pipe_broken`。
    /// - `PipeBroken` / `IoError`：底层写失败。`PipeBroken` 会清空 `send_half`
    ///   并触发 `notify_pipe_broken`。
    ///
    /// ⚠️ `Ok(())` **只表示字节写进了管道**，不代表 AHK 收到或处理成功 ——
    /// 需要确认结果请用 [`send_and_wait`](Self::send_and_wait)。
    pub async fn send(&self, msg: &IpcMessage) -> Result<(), IpcError> {
        let mut line = serde_json::to_string(msg)?;
        line.push('\n');
        let bytes = line.as_bytes();
        if bytes.len() > MAX_MESSAGE_SIZE {
            return Err(IpcError::MessageTooLarge(bytes.len(), MAX_MESSAGE_SIZE));
        }

        let mut writer_guard = self.send_half.lock().await;
        let writer = writer_guard.as_mut().ok_or(IpcError::ConnectionClosed)?;

        // T6-05：写入（write_all + flush）加超时，避免 AHK 挂死且管道写满时
        // 无限阻塞。超时视同管道不可靠，清理连接并返回 SendTimeout。
        match tokio::time::timeout(SEND_TIMEOUT, writer.write_all(bytes)).await {
            Ok(Ok(())) => match tokio::time::timeout(SEND_TIMEOUT, writer.flush()).await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(e)) => {
                    let ipc_err = IpcError::from(e);
                    let _is_pipe_broken = matches!(ipc_err, IpcError::PipeBroken(_));
                    // flush 失败时连接可能已不可靠，无论是否为 PipeBroken 都清理
                    *writer_guard = None;
                    drop(writer_guard);
                    self.notify_pipe_broken().await;
                    Err(ipc_err)
                }
                Err(_elapsed) => {
                    tracing::warn!(
                        "IPC send flush 超时 ({}ms)，视为管道不可靠",
                        SEND_TIMEOUT.as_millis()
                    );
                    *writer_guard = None;
                    drop(writer_guard);
                    self.notify_pipe_broken().await;
                    Err(IpcError::SendTimeout)
                }
            },
            Ok(Err(e)) => {
                let ipc_err = IpcError::from(e);
                let is_pipe_broken = matches!(ipc_err, IpcError::PipeBroken(_));
                if is_pipe_broken {
                    *writer_guard = None;
                }
                drop(writer_guard);
                if is_pipe_broken {
                    self.notify_pipe_broken().await;
                }
                Err(ipc_err)
            }
            Err(_elapsed) => {
                tracing::warn!(
                    "IPC send 写超时 ({}ms)，视为管道不可靠",
                    SEND_TIMEOUT.as_millis()
                );
                *writer_guard = None;
                drop(writer_guard);
                self.notify_pipe_broken().await;
                Err(IpcError::SendTimeout)
            }
        }
    }

    /// 发送一条命令（不等响应），返回它的 `seq`。
    ///
    /// # Errors
    ///
    /// 同 [`send`](Self::send)：`JsonError` / `MessageTooLarge` /
    /// `ConnectionClosed` / `SendTimeout` / `PipeBroken` / `IoError`。
    /// 失败时 `seq` **已经被消耗掉了**（`next_seq()` 在发送前调用），
    /// 重试会拿到新的 `seq` —— 依赖 `seq` 做关联的调用方要注意。
    pub async fn send_command(&self, cmd: IpcCommand) -> Result<u64, IpcError> {
        let seq = self.next_seq();
        let msg = IpcMessage::command(seq, &cmd);
        self.send(&msg).await?;
        Ok(seq)
    }

    /// 只等**已经发出**的命令的响应（不负责发送），按 `seq` 匹配。
    ///
    /// ⚠️ 它会在 `pending_responses` 里**新登记一个条目覆盖同 `seq` 的旧条目** ——
    /// 正常用法是先 [`prepare_send_and_wait`](Self::prepare_send_and_wait)
    /// （那里面已经登记过），本函数留给「自己发了命令、只想等回包」的场景。
    ///
    /// # Errors
    ///
    /// - `Timeout`：`timeout` 内没等到响应 —— 会把 `pending` 条目移除，
    ///   **但 AHK 侧可能仍在正常处理**，迟到的响应会被丢弃。
    /// - `ChannelClosed`：oneshot 发送端被丢弃（典型是连接清理时清空了 `pending`）。
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

    /// 发送 IPC 命令并等待响应。
    ///
    /// **注意**: 返回 `Ok(msg)` 仅表示成功收到 AHK 响应消息，不代表操作成功。
    /// 响应消息可能包含错误信息（`msg.is_error() == true`），调用方应检查
    /// 响应内容而非仅依赖 `Ok`/`Err` 判断操作结果。例如 `pipe_broken` 错误
    /// 响应由 `IpcBridge::send_and_wait` 转换为 `Err`，但其他 AHK 侧错误
    /// 仍以 `Ok(msg)` 返回。
    ///
    /// # Errors
    ///
    /// - 发送阶段失败：同 [`send`](Self::send)（`JsonError` / `MessageTooLarge` /
    ///   `ConnectionClosed` / `SendTimeout` / `PipeBroken` / `IoError`），
    ///   此时 `pending` 条目已被移除，不会泄漏。
    /// - `Timeout`：`timeout` 内没有响应，同样会移除 `pending` 条目。
    ///   ⚠️ 若 `timeout` 超过 `PENDING_CLEANUP_MAX_AGE`，条目可能**先被清理任务
    ///   扫掉**，于是表现为 `ChannelClosed` 而不是 `Timeout`（只打一条 `warn`）。
    /// - `ChannelClosed`：响应通道被丢弃。
    pub async fn send_and_wait(
        &self,
        cmd: IpcCommand,
        timeout: std::time::Duration,
    ) -> Result<IpcMessage, IpcError> {
        if timeout > PENDING_CLEANUP_MAX_AGE {
            tracing::warn!(
                "send_and_wait timeout ({:?}) exceeds PENDING_CLEANUP_MAX_AGE ({:?}), pending response may be cleaned up before timeout fires",
                timeout, PENDING_CLEANUP_MAX_AGE,
            );
        }
        let (seq, rx) = self.prepare_send_and_wait(cmd).await?;
        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(msg)) => Ok(msg),
            Ok(Err(_)) => {
                // oneshot 通道关闭，主动清理 pending entry
                let mut pending = self.pending_responses.lock().await;
                pending.remove(&seq);
                Err(IpcError::ChannelClosed)
            }
            Err(_) => {
                // 超时，主动清理 pending entry，与 wait_response 行为一致
                let mut pending = self.pending_responses.lock().await;
                pending.remove(&seq);
                Err(IpcError::Timeout)
            }
        }
    }

    /// 登记 `pending` 条目**并**发出命令，返回 `(seq, 响应接收端)`。
    ///
    /// 把「登记 + 发送」和「等待」拆开，是为了让调用方能先拿到 `seq` 再决定
    /// 等多久（[`send_and_wait`](Self::send_and_wait) 内部就是这么用的）。
    ///
    /// # Errors
    ///
    /// 只在**发送失败**时返回（错误同 [`send`](Self::send)），并且会先把刚登记的
    /// `pending` 条目移除 —— 不会留下永远收不到响应的悬挂条目。
    /// 返回 `Ok` 只表示「已发出并登记」，响应内容要自己 `await` 接收端去看。
    pub async fn prepare_send_and_wait(
        &self,
        cmd: IpcCommand,
    ) -> Result<(u64, tokio::sync::oneshot::Receiver<IpcMessage>), IpcError> {
        let seq = self.next_seq();

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

        let msg = IpcMessage::command(seq, &cmd);
        if let Err(e) = self.send(&msg).await {
            let mut pending = self.pending_responses.lock().await;
            pending.remove(&seq);
            return Err(e);
        }

        Ok((seq, rx))
    }

    /// 从管道读一行并解析成 `IpcMessage`（读取上限 `MAX_MESSAGE_SIZE`）。
    ///
    /// # Errors
    ///
    /// - `ConnectionClosed`：没有连接，或读到 EOF（0 字节，`Ok(0)` 分支会把
    ///   `recv_half` 清空）。
    /// - `EmptyMessage`：读到的行是空的。
    /// - `MessageTooLarge`：单行超过 `MAX_MESSAGE_SIZE`，或读满上限仍无换行。
    /// - `PipeBroken`：超大消息的残余数据超过 1MB 丢弃上限，管道已无法对齐，
    ///   会清空 `recv_half` —— **这个连接不能再用**。
    /// - `JsonError` / `IoError`：解析失败或底层读失败。
    ///
    /// ⚠️ 持 `recv_half` 锁期间会 `await` 读，所以**并发调用会串行化**；
    /// 监听循环里同一时刻只应有一个 `recv`。
    pub async fn recv(&self) -> Result<IpcMessage, IpcError> {
        let mut reader_guard = self.recv_half.lock().await;
        let reader = reader_guard.as_mut().ok_or(IpcError::ConnectionClosed)?;

        // 使用 take() 限制读取大小，避免恶意/异常大消息耗尽内存
        let mut line = String::with_capacity(256);
        match reader
            .take(MAX_MESSAGE_SIZE as u64)
            .read_line(&mut line)
            .await
        {
            Ok(0) => {
                *reader_guard = None;
                Err(IpcError::ConnectionClosed)
            }
            Ok(_) => {
                let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
                if trimmed.is_empty() {
                    return Err(IpcError::EmptyMessage);
                }
                // take() 在达到限制时截断读取，此时行末尾无换行符，
                // 可判定为超大消息
                if !line.ends_with('\n') && line.len() >= MAX_MESSAGE_SIZE {
                    // 消耗掉剩余数据直到换行符，防止后续读取错位。
                    // 使用 take() 限制最大读取量（1MB），防止异常 AHK 进程
                    // 发送超长无换行数据导致 OOM。
                    const MAX_DISCARD_SIZE: u64 = 1024 * 1024;
                    let mut discard = String::new();
                    if let Err(discard_err) =
                        reader.take(MAX_DISCARD_SIZE).read_line(&mut discard).await
                    {
                        tracing::debug!(
                            "消耗超大消息残余数据失败（可能是管道断裂）: {discard_err}"
                        );
                    }
                    if !discard.ends_with('\n') {
                        tracing::error!(
                            "超大消息残余数据超过 {} 字节限制，管道状态可能不一致，断开连接",
                            MAX_DISCARD_SIZE
                        );
                        *reader_guard = None;
                        return Err(IpcError::PipeBroken(
                            "残余数据超限，管道状态不一致".to_string(),
                        ));
                    }
                    return Err(IpcError::MessageTooLarge(line.len(), MAX_MESSAGE_SIZE));
                }
                if trimmed.len() > MAX_MESSAGE_SIZE {
                    return Err(IpcError::MessageTooLarge(trimmed.len(), MAX_MESSAGE_SIZE));
                }
                let msg = parse_message(trimmed)?;
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
            if msg.is_error() {
                tracing::warn!("收到错误响应: ack_seq={}, type={}", ack, msg.r#type);
            }
            let mut pending = self.pending_responses.lock().await;
            if let Some(p) = pending.remove(&ack) {
                if p.tx.send(msg).is_err() {
                    tracing::debug!(
                        "dispatch_response: oneshot 发送失败 (ack_seq={ack})，接收方可能已超时"
                    );
                }
                return true;
            }
        }
        false
    }

    /// 将非关键消息转发到 outbound 通道。
    ///
    /// T6-06：非关键消息（heartbeat / `key_send_event` / `key_record_event` 等）
    /// 用 `try_send`，通道满时丢弃而非 await 阻塞监听循环，避免经 recv →
    /// OS 管道 → AHK 同步 `WriteFile` 反向压死。
    fn forward_to_outbound(&self, msg: IpcMessage) {
        match self.outbound_tx.try_send(msg) {
            Ok(()) => {}
            Err(mpsc::error::TrySendError::Full(dropped)) => {
                tracing::debug!(
                    "IPC outbound 通道已满，丢弃非关键消息 type={}",
                    dropped.r#type
                );
            }
            Err(mpsc::error::TrySendError::Closed(_)) => {
                tracing::debug!("IPC outbound 通道已关闭，丢弃非关键消息");
            }
        }
    }

    pub async fn listen_ahk(&self) {
        tracing::info!("IPC 开始监听 AHK 消息");

        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::channel::<Result<IpcMessage, IpcError>>(64);

        let recv_manager = self.clone();
        let recv_handle = tokio::spawn(async move {
            loop {
                let result = recv_manager.recv().await;
                let is_fatal = matches!(
                    result,
                    Err(IpcError::ConnectionClosed | IpcError::PipeBroken(_))
                );
                if msg_tx.send(result).await.is_err() {
                    break;
                }
                if is_fatal {
                    break;
                }
            }
        });

        let merge_window = self.hotkey_merger.lock().await.merge_window();
        let mut flush_interval = tokio::time::interval(merge_window);

        loop {
            tokio::select! {
                result = msg_rx.recv() => {
                    let msg = match result {
                        Some(Ok(msg)) => msg,
                        Some(Err(IpcError::ConnectionClosed | IpcError::PipeBroken(_))) => {
                            tracing::warn!("IPC 管道断裂，等待重连");
                            self.notify_pipe_broken().await;
                            break;
                        }
                        Some(Err(e)) => {
                            tracing::warn!("IPC 接收错误: {e}");
                            continue;
                        }
                        None => {
                            break;
                        }
                    };

                    // T8-01：消息分类逻辑抽取为纯函数 classify_message，分发语义与原内联实现等价。
                    match classify_message(&msg) {
                        MessageKind::Response => {
                            // T6-06：仅当消息携带 ack_seq 时才可能是响应，才需要 clone 深拷贝。
                            if self.dispatch_response(msg.clone()).await {
                                continue;
                            }
                            // 响应未匹配到 pending（如超时后被清理），按非关键消息转发兜底。
                            self.forward_to_outbound(msg);
                        }
                        MessageKind::Pong => {
                            let cb = self.on_heartbeat.lock().clone();
                            if let Some(cb) = cb {
                                cb();
                            }
                        }
                        MessageKind::Hotkey => {
                            let messages = {
                                let mut merger = self.hotkey_merger.lock().await;
                                merger.push(msg);
                                if merger.should_flush() {
                                    merger.flush()
                                } else {
                                    Vec::new()
                                }
                            };
                            for msg in messages {
                                self.forward_to_outbound(msg); // T6-06：热键是高频消息，通道满时丢弃而非阻塞监听循环
                            }
                        }
                        MessageKind::Forward => {
                            self.forward_to_outbound(msg);
                        }
                    }
                }
                _ = flush_interval.tick() => {
                    let messages = {
                        let mut merger = self.hotkey_merger.lock().await;
                        if merger.should_flush() {
                            merger.flush()
                        } else {
                            Vec::new()
                        }
                    };
                    for msg in messages {
                        self.forward_to_outbound(msg); // T6-06：热键是高频消息，通道满时丢弃而非阻塞监听循环
                    }
                    self.cleanup_stale_pending(PENDING_CLEANUP_MAX_AGE).await;
                }
            }
        }

        recv_handle.abort();
    }

    async fn notify_pipe_broken(&self) {
        self.cleanup_connection().await;
        if self.shutting_down.load(Ordering::SeqCst) {
            tracing::info!("IPC: 关机期间管道断裂，跳过 pipe_broken 回调");
            return;
        }
        let cb = self.on_pipe_broken.lock().clone();
        if let Some(cb) = cb {
            cb();
        }
    }

    async fn cleanup_connection(&self) {
        *self.send_half.lock().await = None;
        *self.recv_half.lock().await = None;
        {
            let mut merger = self.hotkey_merger.lock().await;
            let flushed = merger.flush();
            if !flushed.is_empty() {
                tracing::debug!("cleanup_connection: 丢弃 {} 条缓冲热键事件", flushed.len());
            }
        }
        let mut pending = self.pending_responses.lock().await;
        for (seq, p) in pending.drain() {
            let _ =
                p.tx.send(IpcMessage::error_response(seq, seq, "pipe_broken"));
        }
    }

    pub async fn is_connected(&self) -> bool {
        self.send_half.lock().await.is_some()
    }

    #[must_use]
    pub fn outbound_sender(&self) -> IpcOutboundSender {
        self.outbound_tx.clone()
    }

    /// 按 seq 清理指定的 pending response 条目。
    /// 用于 `IpcBridge` 超时/通道关闭后主动清理，避免等待周期性 `cleanup_stale_pending`。
    pub async fn cleanup_pending_by_seq(&self, seq: u64) {
        let mut pending = self.pending_responses.lock().await;
        pending.remove(&seq);
    }

    pub async fn cleanup_stale_pending(&self, max_age: std::time::Duration) {
        let mut pending = self.pending_responses.lock().await;
        let now = std::time::Instant::now();
        let stale_ids: Vec<u64> = pending
            .iter()
            .filter(|(_, p)| now.duration_since(p.created_at) >= max_age)
            .map(|(seq, _)| *seq)
            .collect();
        for seq in stale_ids {
            if let Some(p) = pending.remove(&seq) {
                let error_msg = format!("pending response 超时清理 (seq={seq})");
                let _ = p.tx.send(IpcMessage::error_response(seq, seq, &error_msg));
                tracing::warn!("清理超时 pending response: seq={seq}");
            }
        }
    }
}

/// 生成 32 字节随机认证 token，并 hex 编码为 64 字符字符串。
///
/// T5-08：原实现用 `SystemTime::now()` 时间戳派生 token，攻击者可结合进程启动
/// 时间缩小猜测空间。改为随机字节后 token 不可预测。
///
/// 随机源不可用时（理论上极罕见）回退为 PID + 计数器 + 时间戳，仍保持纯
/// 十六进制格式，保证 token 通过环境变量跨语言传递时不引入特殊字符。
fn generate_auth_token() -> String {
    let mut buf = [0u8; 32];
    match getrandom::getrandom(&mut buf) {
        Ok(()) => {
            use std::fmt::Write as _;
            let mut hex = String::with_capacity(64);
            for byte in &buf {
                // 写入 String 不会失败，故忽略 Result。用 write! 而不是
                // push_str(&format!(..))：后者每字节都会临时分配一个 String
                // （clippy::format_push_string）。
                let _ = write!(hex, "{byte:02x}");
            }
            hex
        }
        Err(e) => {
            let pid = std::process::id();
            let counter = AUTH_FALLBACK_COUNTER.fetch_add(1, Ordering::Relaxed);
            let ts = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |d| d.as_nanos());
            tracing::warn!(
                "系统随机源不可用，使用 PID+计数器+时间戳作为 auth token 兜底: pid={pid}, counter={counter}, err={e}"
            );
            format!("{pid:08x}{counter:08x}{ts:016x}")
        }
    }
}

/// 恒定时间字符串比较，避免认证 token 比较的时序侧信道（T5-08）。
///
/// 逐字节 XOR 累积差异，不提前返回；长度差异也纳入 `diff` 计算，
/// 屏蔽「长度不等立即返回 false」的短路径时序泄露。
fn constant_time_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    let mut diff = a.len() ^ b.len();
    let max_len = a.len().max(b.len());
    for i in 0..max_len {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        diff |= (x ^ y) as usize;
    }
    diff == 0
}

/// IPC 消息分发分类。
///
/// T8-01：从 `listen_ahk` 的内联分发逻辑抽出，便于单元测试。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MessageKind {
    /// 携带 `ack_seq` 的响应消息，需尝试匹配 pending response
    Response,
    /// 心跳 pong 响应
    Pong,
    /// 热键事件
    Hotkey,
    /// 其它消息，转发到 outbound 通道
    Forward,
}

/// 将一行 JSON 解析为 `IpcMessage`。
///
/// T8-01：从 `recv` 内联的 `serde_json::from_str` 抽出，便于单元测试。
fn parse_message(line: &str) -> Result<IpcMessage, IpcError> {
    let msg: IpcMessage = serde_json::from_str(line)?;
    Ok(msg)
}

/// 按消息内容分类，供 `listen_ahk` 分发分支复用。
///
/// 分类优先级与原内联实现等价：
/// 1. `pong` 心跳消息 —— `pong` 也携带 `ack_seq`，但 Rust 侧 ping 永不注册
///    pending（走 `send` 而非 `send_and_wait`），因此 `dispatch_response` 对
///    `pong` 始终返回 false，将其直接归为 `Pong` 不改变运行行为；
/// 2. 其它携带 `ack_seq` 的消息 → `Response`；
/// 3. `hotkey` → `Hotkey`；
/// 4. 其余 → `Forward`（含 heartbeat / `key_send_event` 等非关键消息）。
fn classify_message(msg: &IpcMessage) -> MessageKind {
    if msg.r#type == "pong" {
        MessageKind::Pong
    } else if msg.ack_seq.is_some() {
        MessageKind::Response
    } else if msg.r#type == "hotkey" {
        MessageKind::Hotkey
    } else {
        MessageKind::Forward
    }
}

/// 创建命名管道监听端（服务端侧）。
///
/// # Errors
///
/// - 管道名非法（`to_ns_name`）→ 返回其错误。
/// - `create_tokio()` 失败 → 典型是**同名管道已被占用**（上一实例没退出干净，
///   或同类应用抢先建了同名管道）。
///
/// 调用方通常要把这个错误当成「启动失败」直接上报给用户，因为监听端建不起来
/// 意味着 AHK 永远连不上，重试同一个名字大概率还是同样的结果。
pub fn create_listener(
    pipe_name: &str,
) -> Result<Listener, Box<dyn std::error::Error + Send + Sync>> {
    let name = pipe_name.to_ns_name::<GenericNamespaced>()?;
    let opts = ListenerOptions::new().name(name);
    let listener = opts.create_tokio()?;
    Ok(listener)
}

#[cfg(test)]
mod tests {
    use super::*;
    use asd_ipc_protocol::IpcCommand;
    use asd_test_harness::unique_pipe_name;
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
        assert_eq!(
            flushed.len(),
            2,
            "F1 和 F2 各一条，F1 被覆盖后只有最新的一条"
        );

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
            assert!(msg.data.is_none(), "命令 {cmd:?} 不应有 data");
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
        assert_eq!(
            msg.keys.as_deref(),
            Some(&["1".to_string(), "2".to_string()][..])
        );
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
        let err = std::io::Error::other("some error");
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
        assert!(
            msg.contains("认证失败"),
            "AuthFailed 显示消息应包含'认证失败': {msg}"
        );
        assert!(
            msg.contains("token 不匹配"),
            "AuthFailed 显示消息应包含具体原因: {msg}"
        );
    }

    // ---- IpcManager 基础测试 ----

    #[test]
    fn test_ipc_manager_new() {
        let pipe_name = unique_pipe_name("test_pipe");
        let (manager, _rx) = IpcManager::new(&pipe_name);
        assert_eq!(*manager.pipe_name, pipe_name);
    }

    #[test]
    fn test_ipc_manager_next_seq_monotonic() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_seq"));
        let s1 = manager.next_seq();
        let s2 = manager.next_seq();
        let s3 = manager.next_seq();
        assert!(s2 > s1, "seq 应单调递增");
        assert!(s3 > s2, "seq 应单调递增");
    }

    #[test]
    fn test_ipc_manager_clone() {
        let pipe_name = unique_pipe_name("test_clone");
        let (manager, _rx) = IpcManager::new(&pipe_name);
        let cloned = manager.clone();
        assert_eq!(*cloned.pipe_name, pipe_name);
    }

    #[tokio::test]
    async fn test_ipc_manager_not_connected_initially() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_not_connected"));
        assert!(!manager.is_connected().await);
    }

    // ---- shutting_down 标志测试 ----

    #[test]
    fn test_shutting_down_initially_false() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_shutting_down_init"));
        assert!(
            !manager.is_shutting_down(),
            "shutting_down 初始值应为 false"
        );
    }

    #[test]
    fn test_mark_shutting_down_sets_flag() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_mark_shutting_down"));
        assert!(!manager.is_shutting_down());
        manager.mark_shutting_down();
        assert!(
            manager.is_shutting_down(),
            "mark_shutting_down() 后应为 true"
        );
    }

    #[test]
    fn test_shutting_down_shared_across_clones() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_shutting_down_clone"));
        let cloned = manager.clone();
        assert!(!manager.is_shutting_down());
        assert!(!cloned.is_shutting_down());

        manager.mark_shutting_down();
        assert!(manager.is_shutting_down(), "原实例标记后应为 true");
        assert!(
            cloned.is_shutting_down(),
            "克隆实例应共享同一 Arc<AtomicBool>，也应为 true"
        );
    }

    #[tokio::test]
    async fn test_notify_pipe_broken_suppressed_during_shutdown() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_pipe_broken_suppressed"));

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

        assert!(
            !called.load(Ordering::SeqCst),
            "关机期间 pipe_broken 回调不应被触发"
        );
    }

    #[tokio::test]
    async fn test_notify_pipe_broken_fires_when_not_shutdown() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_pipe_broken_fires"));

        let called = Arc::new(AtomicBool::new(false));
        let called_clone = called.clone();
        manager.set_pipe_broken_callback(Arc::new(move || {
            called_clone.store(true, Ordering::SeqCst);
        }));

        // 不标记关机，直接触发
        manager.notify_pipe_broken().await;

        assert!(
            called.load(Ordering::SeqCst),
            "非关机期间 pipe_broken 回调应被触发"
        );
    }

    // ---- T6-05: send() 写超时兜底 — 测试 ----

    /// 验证单次 IPC 写超时阈值固定为 2000ms（T6-05 兜底上限）。
    #[test]
    fn test_send_timeout_configured_to_2000ms() {
        assert_eq!(
            SEND_TIMEOUT,
            std::time::Duration::from_secs(2),
            "SEND_TIMEOUT 应为 2000ms，避免 AHK 挂死时无限阻塞工作线程"
        );
    }

    /// 验证未连接时 `send()` 不阻塞、立即返回 `ConnectionClosed` 错误，
    /// 而非挂起工作线程（T6-05 错误路径确定性回归）。
    #[tokio::test]
    async fn test_send_returns_connection_closed_when_disconnected() {
        let (manager, _rx) = IpcManager::new(&unique_pipe_name("test_send_disconnected"));
        let msg = IpcMessage::ping(1);
        let result = manager.send(&msg).await;
        assert!(
            matches!(result, Err(IpcError::ConnectionClosed)),
            "未连接时 send() 应返回 ConnectionClosed，实际: {result:?}"
        );
    }

    // ---- T8-01: parse_message 纯函数测试 ----

    #[test]
    fn test_parse_message_valid_line() {
        let json = r#"{"type":"pong","seq":2,"ack_seq":1}"#;
        let msg = parse_message(json).expect("应成功解析合法 JSON");
        assert_eq!(msg.r#type, "pong");
        assert_eq!(msg.seq, 2);
        assert_eq!(msg.ack_seq, Some(1));
    }

    #[test]
    fn test_parse_message_malformed_json() {
        let result = parse_message("{invalid json");
        assert!(
            matches!(result, Err(IpcError::JsonError(_))),
            "畸形 JSON 应返回 JsonError，实际: {result:?}"
        );
    }

    #[test]
    fn test_parse_message_missing_optional_fields() {
        // 缺少 keys/data 等可选字段时仍应成功解析，且对应字段为 None
        let json = r#"{"type":"heartbeat","seq":50}"#;
        let msg = parse_message(json).expect("缺少可选字段不应导致解析失败");
        assert_eq!(msg.r#type, "heartbeat");
        assert_eq!(msg.seq, 50);
        assert!(msg.keys.is_none(), "keys 应为 None");
        assert!(msg.data.is_none(), "data 应为 None");
    }

    // ---- T8-01: classify_message 纯函数测试 ----

    #[test]
    fn test_classify_message_response_with_ack_seq() {
        let msg = IpcMessage::response(100, 42, "ok", None);
        assert_eq!(classify_message(&msg), MessageKind::Response);
    }

    #[test]
    fn test_classify_message_pong() {
        let msg = IpcMessage::pong(2, 1);
        assert_eq!(classify_message(&msg), MessageKind::Pong);
    }

    #[test]
    fn test_classify_message_hotkey() {
        let msg = IpcMessage::hotkey_event(1, "F1");
        assert_eq!(classify_message(&msg), MessageKind::Hotkey);
    }

    #[test]
    fn test_classify_message_forward_unknown_type() {
        // 未知 type 消息应落入 forward 兜底分支
        let msg = IpcMessage {
            r#type: "unknown_type".to_string(),
            seq: 7,
            ..Default::default()
        };
        assert_eq!(classify_message(&msg), MessageKind::Forward);
    }

    #[test]
    fn test_classify_message_forward_heartbeat() {
        let msg = IpcMessage::heartbeat(50);
        assert_eq!(classify_message(&msg), MessageKind::Forward);
    }

    // ---- T5-08: auth token 随机生成 + 恒定时间比较 测试 ----

    /// 验证 `IpcManager::new` 生成的 auth token 为 64 字符纯十六进制，
    /// 且两次生成结果不同（随机性），杜绝时间戳可预测性。
    #[test]
    fn test_auth_token_is_random_64_hex() {
        let (mgr1, _) = IpcManager::new(&unique_pipe_name("auth_hex_1"));
        let (mgr2, _) = IpcManager::new(&unique_pipe_name("auth_hex_2"));
        let t1 = mgr1.auth_token();
        let t2 = mgr2.auth_token();
        assert_eq!(t1.len(), 64, "auth token 应为 64 字符 hex");
        assert!(
            t1.bytes().all(|b| b.is_ascii_hexdigit()),
            "auth token 应为纯十六进制，实际: {t1}"
        );
        assert_ne!(t1, t2, "两次生成的 token 应不同（随机性）");
    }

    #[test]
    fn test_constant_time_eq_same() {
        assert!(constant_time_eq("abc123", "abc123"));
    }

    #[test]
    fn test_constant_time_eq_different_same_length() {
        assert!(!constant_time_eq("abc123", "abc124"));
    }

    #[test]
    fn test_constant_time_eq_different_length() {
        assert!(!constant_time_eq("abc", "ab"));
        assert!(!constant_time_eq("ab", "abc"));
    }

    #[test]
    fn test_constant_time_eq_empty() {
        assert!(constant_time_eq("", ""));
        assert!(!constant_time_eq("", "a"));
    }

    // ---- T5-12: 管道名单一权威 + 跨语言一致守护 测试 ----

    /// 验证 `IPC_PIPE_NAME_BASE` 单一权威常量存在且值为 "`asd_ipc`"。
    ///
    /// 该测试原位于 `lib.rs` 的 `pipe_name_tests` 模块，随常量收敛到 `ipc.rs`
    /// 后一并迁移至此，保证权威定义与测试同处一文件。
    #[test]
    fn test_ipc_pipe_name_constant_value() {
        assert_eq!(IPC_PIPE_NAME_BASE, "asd_ipc");
    }

    /// 验证每会话管道名**带**随机后缀、且同进程内稳定（发现 #6 的核心防护）。
    ///
    /// 阳性对照：若把 `ipc_pipe_name()` 改回返回固定的 `IPC_PIPE_NAME_BASE`，
    /// 本测试应立即失败 —— 防止「改回固定名」的回归。
    #[test]
    fn test_ipc_pipe_name_is_per_session_and_stable() {
        let first = ipc_pipe_name();
        assert!(
            first.starts_with(IPC_PIPE_NAME_BASE),
            "管道名必须以基础名开头: {first}"
        );
        assert_ne!(
            first, IPC_PIPE_NAME_BASE,
            "管道名不得等于固定基础名 —— 那正是可被抢注的老问题"
        );
        assert_eq!(first, ipc_pipe_name(), "同进程内管道名必须稳定");
        assert!(
            first.contains(&format!("_{}_", std::process::id())),
            "管道名应包含当前进程 PID: {first}"
        );
    }

    /// 验证 AHK 执行器 `ipc_client.ahk` 的管道名与 Rust 侧一致（T5-12 跨语言
    /// 单一权威守护），覆盖两条路径：
    ///
    /// 1. **回退路径**：AHK `DEFAULT_PIPE_NAME` 的后缀必须等于 `IPC_PIPE_NAME_BASE`；
    /// 2. **动态路径**：AHK 必须读与 `IPC_PIPE_NAME_ENV_VAR` **同名**的环境变量
    ///    （Rust 侧把它注入子进程，两侧变量名漂移即 IPC 连不上）。
    ///
    /// 若任一侧改名而另一侧未同步，本测试会在 CI 中失败。
    #[test]
    fn test_ipc_pipe_name_matches_ahk_client() {
        let ahk_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("ahk_executor")
            .join("ipc_client.ahk");
        let content = std::fs::read_to_string(&ahk_path)
            .unwrap_or_else(|e| panic!("无法读取 AHK 客户端文件 {}: {e}", ahk_path.display()));

        // 1) 回退基础名
        let re = regex::Regex::new(r#"DEFAULT_PIPE_NAME\s*:=\s*"[^"]*\\pipe\\([A-Za-z0-9_]+)""#)
            .expect("IPC 管道名正则表达式应为合法");
        let caps = re.captures(&content).unwrap_or_else(|| {
            panic!(
                "AHK 客户端 {} 中未找到 DEFAULT_PIPE_NAME 定义",
                ahk_path.display()
            )
        });
        assert_eq!(
            &caps[1], IPC_PIPE_NAME_BASE,
            "AHK 侧回退管道名后缀必须与 Rust 常量 IPC_PIPE_NAME_BASE 一致（Rust={IPC_PIPE_NAME_BASE}，AHK={}）",
            &caps[1]
        );

        // 2) 环境变量名
        let expected_env_read = format!("EnvGet(\"{IPC_PIPE_NAME_ENV_VAR}\")");
        assert!(
            content.contains(&expected_env_read),
            "AHK 客户端必须用 `{expected_env_read}` 读取管道名，与 Rust 侧注入的 \
             `IPC_PIPE_NAME_ENV_VAR` 保持一致"
        );
    }

    /// 阳性对照：管道名已被占用时 `create_listener` 必须返回 `Err`。
    ///
    /// 这是「抢注（squatting）可被检出」的证据 —— 老实现撞名后只记日志就 return，
    /// 静默降级为 IPC 永久不可用；现在调用方可以把它当成启动失败上报。
    ///
    /// 用 `#[tokio::test]`：`create_tokio()` 需要在 Tokio 运行时内注册 IO 驱动。
    #[tokio::test]
    async fn test_create_listener_reports_name_conflict() {
        let name = asd_test_harness::unique_pipe_name("conflict");
        let first = create_listener(&name);
        assert!(first.is_ok(), "首次创建监听端应成功: {name}");
        let second = create_listener(&name);
        assert!(
            second.is_err(),
            "同名管道已被占用时 create_listener 必须返回 Err —— 否则抢注会静默降级"
        );
        drop(first);
    }
}
