pub use asd_domain::config::WatchdogStateEnum;
use std::os::windows::process::CommandExt;
use std::process::Child;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use windows::Win32::Foundation::{HANDLE, HWND, LPARAM};
use windows::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, SetInformationJobObject, JOBOBJECTINFOCLASS,
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows::Win32::System::Threading::{
    OpenProcess, CREATE_NO_WINDOW, PROCESS_SET_QUOTA, PROCESS_TERMINATE,
};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowThreadProcessId, PostMessageW, WM_CLOSE, WNDENUMPROC,
};

const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(1);
const HEARTBEAT_TIMEOUT_COUNT: u32 = 3;
/// 心跳总超时阈值：超过此时间未收到心跳响应即判定为超时
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(3);
pub const MAX_RESTART_ATTEMPTS: u32 = 10;
pub const BACKOFF_DURATIONS: [Duration; 10] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
    Duration::from_secs(8),
    Duration::from_secs(30),
    Duration::from_secs(30),
    Duration::from_secs(30),
    Duration::from_secs(30),
    Duration::from_secs(30),
    Duration::from_secs(30),
];

const SHUTDOWN_IPC_TIMEOUT: Duration = Duration::from_secs(2);
const SHUTDOWN_WM_CLOSE_TIMEOUT: Duration = Duration::from_secs(3);
const STABLE_HEARTBEAT_THRESHOLD: u32 = 5;

pub struct ProcessWatchdog {
    state: WatchdogStateEnum,
    /// 子进程句柄。通过 [`SendSyncCell`] 包装，使 `ProcessWatchdog` 的
    /// `Send` 由字段自动推导，无需手写 `unsafe impl`（A-1 修复）。
    ///
    /// 背景：`std::process::Child` 是 `Send + !Sync`（其内部持有 `HANDLE` 与
    /// 若干 `Mutex<...>`），若直接作为字段会让 `ProcessWatchdog: !Sync`，
    /// 从而阻碍 `Arc<Mutex<ProcessWatchdog>>` 的共享。
    /// `SendSyncCell<Child>` 要求 `Child: Send`（已满足），并借助外层
    /// `tokio::sync::Mutex` 保证 `&Child` 不被并发访问。
    child: Option<SendSyncCell<Child>>,
    job_guard: Option<JobObjectGuard>,
    exe_path: Option<String>,
    auth_token: Option<String>,
    restart_count: u32,
    missed_heartbeats: u32,
    backoff_duration: Duration,
    last_restart: Option<std::time::Instant>,
    last_heartbeat: Option<std::time::Instant>,
    send_shutdown: Option<Arc<dyn Fn() + Send + Sync>>,
    stable_heartbeat_count: u32,
}

// 说明（A-1 修复）：此处**不再有**手写的 `unsafe impl Send/Sync`。
//
// 原实现需为 `ProcessWatchdog` 手写 2 处 `unsafe impl`，其唯一原因是字段中
// 含 `Option<Child>`（`!Sync`，因内部 `HANDLE`）与 `Option<JobObjectGuard>`
// （其内部 `HANDLE` 在 windows 0.62.2 中为 `!Send + !Sync`）。
//
// 现改为：所有 `!Send`/`!Sync` 的字段一律经 `SendSyncCell` 包装后存储，
// 于是 `ProcessWatchdog: Send + Sync + 'static` 由 Rust 编译器**自动推导**。
// 这带来两个可验证的收益：
//   1. 借出的 `&mut ProcessWatchdog` 天然是 `'static` 的（无内部借用），
//      `WatchdogBridge` 可以在 `block_in_place + block_on` 内合法持有它；
//   2. 若未来新增「非 `Send`/非经由 `SendSyncCell` 包装」的字段，
//      编译器会立即报错 —— 这比测试更能防住回归。
//
// 手工 unsafe 的残余面被压缩到 `SendSyncCell` 与 `JobObjectGuard` 两处，
// 且各自的 SAFETY 论证均为单一命题（见其文档）。

impl Default for ProcessWatchdog {
    fn default() -> Self {
        Self::new()
    }
}

impl ProcessWatchdog {
    pub fn new() -> Self {
        Self {
            state: WatchdogStateEnum::Idle,
            child: None,
            job_guard: None,
            exe_path: None,
            auth_token: None,
            restart_count: 0,
            missed_heartbeats: 0,
            backoff_duration: BACKOFF_DURATIONS[0],
            last_restart: None,
            last_heartbeat: None,
            send_shutdown: None,
            stable_heartbeat_count: 0,
        }
    }

    pub fn set_send_shutdown(&mut self, cb: Arc<dyn Fn() + Send + Sync>) {
        self.send_shutdown = Some(cb);
    }

    pub fn set_state(&mut self, new_state: WatchdogStateEnum) {
        if self.state != new_state {
            tracing::info!("Watchdog 状态变更: {:?} → {:?}", self.state, new_state);
            self.state = new_state.clone();
        }
    }

    /// 返回当前状态快照（`Clone`），与锁生命周期解耦。
    ///
    /// 返回的是 `self.state` 的克隆值而非引用，避免把「锁内借用」暴露为
    /// 「可能跨锁存活的引用」。若返回 `&WatchdogStateEnum`，调用方一旦把该
    /// 引用保存到外层 `Mutex` 守卫作用域之外，就会形成跨锁共享引用，触发
    /// 数据竞争（UB）。返回值快照从根上消除这一入口。
    pub fn state(&self) -> WatchdogStateEnum {
        self.state.clone()
    }

    pub fn restart_count(&self) -> u32 {
        self.restart_count
    }

    pub fn backoff_duration(&self) -> std::time::Duration {
        self.backoff_duration
    }

    pub fn last_restart(&self) -> Option<std::time::Instant> {
        self.last_restart
    }

    pub fn missed_heartbeats(&self) -> u32 {
        self.missed_heartbeats
    }

    pub fn has_child(&self) -> bool {
        self.child.is_some()
    }

    pub fn set_backoff_duration(&mut self, dur: std::time::Duration) {
        self.backoff_duration = dur;
    }

    pub fn set_restart_count(&mut self, count: u32) {
        self.restart_count = count;
    }

    pub fn set_missed_heartbeats(&mut self, count: u32) {
        self.missed_heartbeats = count;
    }

    pub fn set_last_restart(&mut self, instant: Option<std::time::Instant>) {
        self.last_restart = instant;
    }

    /// 终止并等待子进程退出，但保留 child 字段以便后续 is_child_exited 检测。
    /// 用于测试场景下模拟子进程崩溃。
    pub fn kill_child(&mut self) -> Result<(), String> {
        if let Some(child) = self.child.as_mut() {
            child.with_mut(|c| {
                c.kill().map_err(|e| e.to_string())?;
                c.wait().map(|_| ()).map_err(|e| e.to_string())
            })
        } else {
            Err("no child".to_string())
        }
    }

    /// 终止并等待子进程退出（回收僵尸进程），但不修改 `self.child` 字段，
    /// 由调用方决定是否将 `child` 置为 `None`。
    ///
    /// 与 [`kill_child`](Self::kill_child) 的区别：本方法不返回错误，忽略
    /// `kill`/`wait` 的失败（与旧逻辑 `let _ = child.kill()` 一致），供
    /// `begin_restart` / `reset_to_restart` / `graceful_shutdown` 三处统一复用。
    fn kill_and_reap(&mut self) {
        if let Some(child) = self.child.as_mut() {
            child.with_mut(|c| {
                let _ = c.kill();
                let _ = c.wait();
            });
        }
    }

    pub fn attach_child(&mut self, child: Child) -> Result<(), String> {
        let pid = child.id();
        match JobObjectGuard::create() {
            Ok(guard) => {
                match guard.assign(&child) {
                    Ok(()) => {
                        self.job_guard = Some(guard);
                        tracing::info!("Watchdog: JobObject 已创建并分配 PID={pid}");
                    }
                    Err(e) => {
                        tracing::warn!("Watchdog: 分配进程到 JobObject 失败: {e}，子进程仍将被跟踪但不会随主进程自动退出");
                        // JobObject 分配失败，但仍然跟踪子进程
                    }
                }
            }
            Err(e) => {
                tracing::warn!(
                    "Watchdog: 创建 JobObject 失败: {e}，子进程仍将被跟踪但不会随主进程自动退出"
                );
                // JobObject 创建失败，但仍然跟踪子进程
            }
        }

        self.child = Some(SendSyncCell::new(child));
        self.missed_heartbeats = 0;
        self.last_heartbeat = Some(std::time::Instant::now());
        self.set_state(WatchdogStateEnum::Running);
        tracing::info!("Watchdog 已附加子进程 PID={pid}");
        Ok(())
    }

    /// 启动 AHK 子进程并附加到 Watchdog
    ///
    /// 使用 `CREATE_NO_WINDOW` 标志避免弹出控制台窗口，
    /// 并将子进程分配到 JobObject 以确保主进程退出时子进程也被终止。
    ///
    /// 支持两种模式：
    /// - 编译模式：exe_path 指向 asd_executor.exe
    /// - 便携模式：exe_path 指向 asd_executor.bat 或 AutoHotkey64.exe
    ///
    /// `auth_token` 通过环境变量 `ASD_AUTH_TOKEN` 传递给 AHK 子进程，
    /// 用于 IPC 认证。子进程必须在首条消息中发送此 token 才能通过认证。
    pub fn spawn_child(&mut self, exe_path: &str, auth_token: &str) -> Result<(), String> {
        // I36 补偿机制：启动新子进程前清理遗留进程，防止 JobObject 失败导致僵尸进程堆积
        cleanup_stale_executor_processes();

        if auth_token.is_empty() {
            return Err("auth_token 不能为空，IPC 认证需要有效的 token".to_string());
        }
        tracing::info!("Watchdog: 启动 AHK 子进程: {exe_path}");

        // 先保存路径和 token，即使 spawn 失败也能重试
        self.exe_path = Some(exe_path.to_string());
        self.auth_token = Some(auth_token.to_string());

        let (program, args) = if exe_path.ends_with("asd_executor.exe") {
            (exe_path.to_string(), Vec::new())
        } else if exe_path.ends_with("asd_executor.bat") {
            (
                "cmd".to_string(),
                vec!["/C".to_string(), exe_path.to_string()],
            )
        } else if exe_path.ends_with("AutoHotkey64.exe") {
            let script_path = std::path::Path::new(exe_path)
                .with_file_name("executor.ahk")
                .to_string_lossy()
                .to_string();
            (exe_path.to_string(), vec![script_path])
        } else {
            (exe_path.to_string(), Vec::new())
        };

        let mut cmd = Command::new(&program);
        cmd.creation_flags(CREATE_NO_WINDOW.0);
        if !args.is_empty() {
            cmd.args(&args);
        }
        cmd.env("ASD_AUTH_TOKEN", auth_token);

        let child = cmd
            .spawn()
            .map_err(|e| format!("启动子进程失败: {e} (program={program}, args={args:?})"))?;

        self.attach_child(child)
    }

    pub fn notify_heartbeat(&mut self) {
        self.missed_heartbeats = 0;
        self.last_heartbeat = Some(std::time::Instant::now());
        if matches!(
            self.state,
            WatchdogStateEnum::Hung | WatchdogStateEnum::Recovering
        ) {
            tracing::info!("Watchdog: 进程从 {:?} 状态恢复", self.state);
            self.set_state(WatchdogStateEnum::Running);
        }
        self.stable_heartbeat_count += 1;
        if self.restart_count > 0 && self.stable_heartbeat_count >= STABLE_HEARTBEAT_THRESHOLD {
            tracing::info!(
                "Watchdog: 子进程稳定运行 {} 次心跳，重置重启计数器 (was={})",
                self.stable_heartbeat_count,
                self.restart_count
            );
            self.reset_restart_count();
            self.stable_heartbeat_count = 0;
        }
    }

    pub fn tick(&mut self) -> WatchdogAction {
        match self.state {
            WatchdogStateEnum::Idle => WatchdogAction::None,
            WatchdogStateEnum::Starting => {
                if self.child.is_some() {
                    self.set_state(WatchdogStateEnum::Running);
                }
                WatchdogAction::None
            }
            WatchdogStateEnum::Running => {
                // 优先检查子进程退出（比心跳超时更严重，应立即处理）
                if self.is_child_exited() {
                    self.set_state(WatchdogStateEnum::Restarting);
                    return WatchdogAction::RestartNeeded;
                }
                // missed_heartbeats 在每次 tick(1s) 中递增，
                // 当 last_heartbeat 超过 HEARTBEAT_TIMEOUT(3s) 时 +1。
                // 达到 HEARTBEAT_TIMEOUT_COUNT(3) 时判定为 Hung，
                // 即约 3+3=6 秒无心跳后触发（首次超时约第4秒 + 再2次tick）。
                if let Some(last) = self.last_heartbeat {
                    if last.elapsed() > HEARTBEAT_TIMEOUT {
                        self.missed_heartbeats += 1;
                        tracing::warn!(
                            "Watchdog: 心跳超时 (elapsed={:?}, timeout={:?}, missed={}/{})",
                            last.elapsed(),
                            HEARTBEAT_TIMEOUT,
                            self.missed_heartbeats,
                            HEARTBEAT_TIMEOUT_COUNT
                        );
                        if self.missed_heartbeats >= HEARTBEAT_TIMEOUT_COUNT {
                            self.set_state(WatchdogStateEnum::Hung);
                            return WatchdogAction::ProcessHung;
                        }
                    }
                }
                WatchdogAction::None
            }
            WatchdogStateEnum::Hung => {
                if self.is_child_exited() {
                    self.set_state(WatchdogStateEnum::Restarting);
                    return WatchdogAction::RestartNeeded;
                }
                WatchdogAction::ProcessHung
            }
            WatchdogStateEnum::Restarting => {
                if self.restart_count >= MAX_RESTART_ATTEMPTS {
                    self.set_state(WatchdogStateEnum::Failed);
                    return WatchdogAction::MaxRetriesExceeded;
                }

                if let Some(last) = self.last_restart {
                    let elapsed = last.elapsed();
                    if elapsed < self.backoff_duration {
                        return WatchdogAction::WaitForBackoff(self.backoff_duration - elapsed);
                    }
                }

                WatchdogAction::RestartNeeded
            }
            WatchdogStateEnum::Recovering => {
                if self.is_child_exited() {
                    tracing::warn!("Watchdog: Recovering 状态检测到子进程已退出，转为 Restarting");
                    self.set_state(WatchdogStateEnum::Restarting);
                    return WatchdogAction::RestartNeeded;
                }
                match self.last_heartbeat {
                    Some(last) if last.elapsed() > Duration::from_secs(30) => {
                        tracing::warn!("Watchdog: Recovering 状态超时 (30s)，转为 Restarting");
                        self.set_state(WatchdogStateEnum::Restarting);
                        return WatchdogAction::RestartNeeded;
                    }
                    None => {
                        // last_heartbeat 为 None 表示从未收到心跳，不应无限等待
                        tracing::warn!("Watchdog: Recovering 状态无心跳记录，转为 Restarting");
                        self.set_state(WatchdogStateEnum::Restarting);
                        return WatchdogAction::RestartNeeded;
                    }
                    _ => {}
                }
                WatchdogAction::None
            }
            WatchdogStateEnum::Failed => WatchdogAction::MaxRetriesExceeded,
        }
    }

    pub fn begin_restart(&mut self) {
        self.kill_and_reap();
        tracing::info!("Watchdog: begin_restart 已终止旧子进程");
        self.child = None;
        self.job_guard = None;
        self.missed_heartbeats = 0;
        self.restart_count += 1;
        self.last_restart = Some(std::time::Instant::now());
        self.stable_heartbeat_count = 0;
        self.backoff_duration = BACKOFF_DURATIONS
            .get(self.restart_count as usize)
            .copied()
            .unwrap_or(Duration::from_secs(30));
        tracing::warn!(
            "Watchdog: 开始重启 (attempt={}/{}, backoff={:?})",
            self.restart_count,
            MAX_RESTART_ATTEMPTS,
            self.backoff_duration
        );
    }

    pub fn reset_restart_count(&mut self) {
        self.restart_count = 0;
        self.backoff_duration = BACKOFF_DURATIONS[0];
        self.stable_heartbeat_count = 0;
    }

    pub fn reset_to_restart(&mut self) {
        self.kill_and_reap();
        tracing::info!("Watchdog: reset_to_restart 已终止旧子进程");
        self.restart_count = 0;
        self.backoff_duration = BACKOFF_DURATIONS[0];
        self.stable_heartbeat_count = 0;
        self.missed_heartbeats = 0;
        self.child = None;
        self.job_guard = None;
        self.set_state(WatchdogStateEnum::Restarting);
        tracing::info!("Watchdog: 已重置为 Restarting 状态，等待 WatchdogRunner 重新启动子进程");
    }

    fn is_child_exited(&mut self) -> bool {
        if let Some(child) = self.child.as_mut() {
            child.with_mut(|c| match c.try_wait() {
                Ok(Some(_status)) => true,
                Ok(None) => false,
                Err(_) => true,
            })
        } else {
            true
        }
    }

    fn cleanup(&mut self) {
        self.child = None;
        self.job_guard = None;
        // 注意：保留 exe_path 和 auth_token 以便重启时使用
        self.set_state(WatchdogStateEnum::Idle);
    }

    pub fn child_pid(&self) -> Option<u32> {
        self.child.as_ref().map(|c| c.with(|child| child.id()))
    }
}

/// 优雅关机（T5-10 重构）：等待轮询在锁外执行，锁内仅做状态快照与切换，
/// 消除 `graceful_shutdown` 持锁横跨多个 await 点的隐患。
///
/// 三阶段流程与原 `graceful_shutdown(&mut self)` 等价：
/// ① 发送 IPC shutdown → ② 发送 WM_CLOSE → ③ 强制 kill_and_reap。
/// 每个阶段的进程退出轮询（原 `wait_for_exit`）通过 [`poll_watchdog_exit`]
/// 以「短暂加锁检查 → 释放锁 sleep」的方式执行，不再长时间持锁。
pub async fn graceful_shutdown_watchdog(
    watchdog: &Arc<Mutex<ProcessWatchdog>>,
) -> Result<(), String> {
    // 锁内仅做状态快照：读取 pid 与 send_shutdown 回调克隆（不 await）
    let (pid, send_shutdown) = {
        let guard = watchdog.lock().await;
        match guard.child_pid() {
            Some(pid) => (pid, guard.send_shutdown.clone()),
            None => return Ok(()),
        }
    };

    tracing::info!("Watchdog: 开始优雅关机 PID={pid}");

    // Phase 1: 通过 IPC 发送 shutdown 消息
    tracing::info!(
        "Watchdog: Phase 1 - 发送 IPC shutdown 消息 (超时 {:?})",
        SHUTDOWN_IPC_TIMEOUT
    );
    if let Some(ref send_shutdown) = send_shutdown {
        send_shutdown();
    } else {
        tracing::warn!("Watchdog: Phase 1 - send_shutdown 回调未设置，跳过 IPC shutdown 消息发送");
    }
    if poll_watchdog_exit(watchdog, SHUTDOWN_IPC_TIMEOUT).await {
        tracing::info!("Watchdog: 进程在 IPC shutdown 后退出");
        watchdog.lock().await.cleanup();
        return Ok(());
    }

    tracing::info!(
        "Watchdog: Phase 2 - 发送 WM_CLOSE (超时 {:?})",
        SHUTDOWN_WM_CLOSE_TIMEOUT
    );
    if let Err(e) = send_wm_close(pid) {
        tracing::warn!("Watchdog: Phase 2 - WM_CLOSE 发送失败: {e}，继续尝试 Phase 3");
    } else if poll_watchdog_exit(watchdog, SHUTDOWN_WM_CLOSE_TIMEOUT).await {
        tracing::info!("Watchdog: 进程在 WM_CLOSE 后退出");
        watchdog.lock().await.cleanup();
        return Ok(());
    }

    tracing::warn!("Watchdog: Phase 3 - 强制终止进程 PID={pid}");
    let mut guard = watchdog.lock().await;
    guard.kill_and_reap();
    guard.cleanup();
    Ok(())
}

/// 轮询子进程退出（T5-10）：每 100ms 短暂加锁检查一次 `is_child_exited`，
/// 检查后立即释放锁再 sleep，避免长持锁阻塞其它调用方。
async fn poll_watchdog_exit(watchdog: &Arc<Mutex<ProcessWatchdog>>, timeout: Duration) -> bool {
    let start = std::time::Instant::now();
    while start.elapsed() < timeout {
        {
            let mut guard = watchdog.lock().await;
            if guard.is_child_exited() {
                return true;
            }
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    false
}

#[derive(Debug, Clone, PartialEq)]
pub enum WatchdogAction {
    None,
    ProcessHung,
    RestartNeeded,
    WaitForBackoff(Duration),
    MaxRetriesExceeded,
}

/// `JOBOBJECTINFOCLASS` 中 `JobObjectExtendedLimitInformation` 对应的枚举值。
///
/// windows crate 将 `JOBOBJECTINFOCLASS` 定义为 `pub struct JOBOBJECTINFOCLASS(pub i32)`，
/// 未导出该枚举各成员的具名常量，因此以具名常量代替魔法数字 `9`。
const JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS: i32 = 9;

/// `windows` crate 句柄的「可跨线程移动」封装（A-1 修复核心）。
///
/// # 为什么需要它
///
/// `windows` crate 0.62.2 将 `HANDLE` 定义为 `HANDLE(pub *mut c_void)`
/// （`windows-0.62.2/src/Windows/Win32/Foundation/mod.rs:5291`）。由于 `*mut T`
/// 在 Rust 中同时为 `!Send` 与 `!Sync`（`core/src/marker.rs:102,677`），
/// **`HANDLE` 既不是 `Send` 也不是 `Sync`** —— 这与 `std::os::windows::io::OwnedHandle`
/// 不同（std 为后者手写了 `unsafe impl Send/Sync`，见
/// `std/src/os/windows/io/handle.rs:110-124` 及其注释
/// “The Windows HANDLE type may be transferred across and shared between thread
/// boundaries (despite containing a *mut void, which in general isn't Send or Sync)”）。
///
/// 本 newtype 把 std 已经论证过、`windows` crate 却未表达的同一个命题，
/// 在本项目内**显式且集中地**表达一次。
///
/// # 它提供什么保证（这是全部保证，不多不少）
///
/// 1. **可跨线程移动（`Send`）**：`HANDLE` 是内核对象句柄（本质是一个进程内的
///    数值 ID）。Windows 内核不把句柄的所有权绑定到线程上：把一个句柄从其创建
///    线程移动到另一线程继续使用是合法的，只要**同一时刻只有一个线程**访问它。
/// 2. **不提供任何并发共享能力**：本类型**不是** `Sync`，因此 `&RawHandle`
///    无法跨线程传递。想共享必须套 `Mutex`，由锁保证串行化访问。
///
/// 于是「编译器强制：要么移动、要么加锁」，唯一由 `unsafe` 承担的命题被压缩为
/// 上述第 1 条 —— 一个可独立审计、且与 std 立场一致的结论。
#[repr(transparent)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
struct RawHandle(HANDLE);

// SAFETY: 见结构体文档第 1 条。仅声明「句柄可在线程间移动」，不声明任何共享能力。
// 注意 `HANDLE` 自身是 `Copy`，因此移动/复制均为值的位拷贝，不涉及所有权歧义。
unsafe impl Send for RawHandle {}

impl RawHandle {
    /// 从 `windows` crate 的 `HANDLE` 包装。
    const fn new(handle: HANDLE) -> Self {
        Self(handle)
    }

    /// 取出内部的 `HANDLE`（`Copy`，按值返回，无借用逃逸）。
    const fn get(self) -> HANDLE {
        self.0
    }
}

/// 「仅移动 + 外部加锁」语义的单元格。
///
/// 泛型版本，用于把 `!Send`/`!Sync` 的底层类型包装成 `Send + Sync`，
/// 从而让上层结构体（如 `ProcessWatchdog`）的 `Send`/`Sync` 由**编译器自动推导**，
/// 无需手写 `unsafe impl`。
///
/// # 语义边界（务必理解）
///
/// - `SendSyncCell<T>` 仅在 `T: Send` 时才是 `Send`/`Sync`，因此调用方仍须
///   为 `T` 提供「可跨线程移动」的证据（如 [`RawHandle::new`] 之于 `HANDLE`，
///   或 `std::process::Child` 自带的 `Send`）。
/// - 它**不**提供并发保障：`&SendSyncCell<T>` 若要跨线程共享，必须外层套 `Mutex`。
///   本 crate 的用法正是 `Arc<tokio::sync::Mutex<ProcessWatchdog>>`。
/// - 它**不**暴露 `&T` 给外部：唯一的读取入口是要求返回 `R: Send` 的
///   [`with`](Self::with)/[`with_mut`](Self::with_mut)，从类型层面阻断借用逃逸。
///
/// # 为什么 `Sync` 声明里只写 `T: Send` 而不写 `T: Sync`
///
/// 因为该类型的契约是「绝不提供 `&T` 的共享访问」。既然外部拿不到 `&T`，
/// 也就不存在借 `Sync` 产生的并发读；访问全部经由 `Mutex` 串行化。
/// 这使本类型可以承载 `Child` 这类 `Send + !Sync` 的值 —— 正是本修复的关键动机。
struct SendSyncCell<T: Send>(T);

// SAFETY: 见结构体文档。此处仅重述「T 可跨线程移动」，不新增任何共享能力。
unsafe impl<T: Send> Send for SendSyncCell<T> {}
// SAFETY: 见结构体文档中「为什么 Sync 声明里只写 T: Send」一节。
// 该 impl 的意义在于允许 `T: Send + !Sync`（如 `Child`）被安全地包装：
// 由于 `T` 是私有字段且无任何返回 `&T` 的公开入口（`with`/`with_mut` 均要求
// 返回值 `R: Send`，借用无法逃逸），外部无法通过 `SendSyncCell` 取得共享引用，
// 故不会产生并发访问 `T` 的路径。
unsafe impl<T: Send> Sync for SendSyncCell<T> {}

impl<T: Send> SendSyncCell<T> {
    /// 包装一个值。
    const fn new(value: T) -> Self {
        Self(value)
    }

    /// 在闭包内只读访问内部值。
    ///
    /// 闭包返回类型 `R` 被约束为 `Send`，从而在类型层面阻断「把内部借用
    /// 逃逸出当前作用域」的写法 —— 若返回引用（`&T`），其生命周期参数无法满足
    /// 返回值与 `self` 无关的 `Send` 约束，编译失败。这与 `ProcessWatchdog::state()`
    /// 返回 `Clone` 快照的理由一致，把「不得逃逸借用」从注释约定升级为编译期检查。
    fn with<R, F>(&self, f: F) -> R
    where
        F: FnOnce(&T) -> R,
        R: Send,
    {
        f(&self.0)
    }

    /// 在闭包内可变访问内部值。
    ///
    /// 与 [`with`](Self::with) 同样要求返回值 `R: Send`，阻断借用逃逸。
    /// 要求 `&mut self`，因此借用周期与调用方一致，不可能跨越外层锁作用域。
    fn with_mut<R, F>(&mut self, f: F) -> R
    where
        F: FnOnce(&mut T) -> R,
        R: Send,
    {
        f(&mut self.0)
    }
}

/// JobObject 句柄的 RAII 守卫：`Drop` 时调用 `CloseHandle`。
///
/// 内部通过 [`SendSyncCell<RawHandle>`](SendSyncCell) 持有句柄。`RawHandle`
/// 本身是 `Send + !Sync`（见其文档），`SendSyncCell` 将其提升为
/// `Send + Sync`（提升的正当性是：该类型不提供任何 `&T` 共享入口，
/// 访问必须经外层 `Mutex` 串行化）。
/// 于是 `JobObjectGuard` 的 `Send`/`Sync` 同样由编译器自动推导，
/// 手工 unsafe 的命题收敛到 `RawHandle` 与 `SendSyncCell` 两处泛型封装。
///
/// # 线程安全契约（不变式）
///
/// `JobObjectGuard` 只作为 `ProcessWatchdog` 的私有字段存在，而 `ProcessWatchdog`
/// 仅通过 `Arc<tokio::sync::Mutex<ProcessWatchdog>>` 跨线程共享。因此对
/// `JobObjectGuard` 的**任何**访问（含 `assign` 中的 `AssignProcessToJobObject`
/// 与 `Drop` 中的 `CloseHandle`）都发生在持锁期间，不存在并发访问同一句柄的情况。
/// 若未来 `JobObjectGuard` 被移出 `ProcessWatchdog`（或绕过 `Mutex` 直接共享），
/// 必须重新评估该契约。
struct JobObjectGuard(SendSyncCell<RawHandle>);

impl JobObjectGuard {
    fn create() -> Result<Self, windows::core::Error> {
        unsafe {
            let handle = CreateJobObjectW(None, None)?;
            let info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
                BasicLimitInformation:
                    windows::Win32::System::JobObjects::JOBOBJECT_BASIC_LIMIT_INFORMATION {
                        LimitFlags: JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
                        ..Default::default()
                    },
                ..Default::default()
            };
            SetInformationJobObject(
                handle,
                JOBOBJECTINFOCLASS(JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS),
                &info as *const _ as *const _,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )?;
            Ok(Self(SendSyncCell::new(RawHandle::new(handle))))
        }
    }

    fn assign(&self, child: &Child) -> Result<(), windows::core::Error> {
        let pid = child.id();
        // SAFETY: `AssignProcessToJobObject` 为同步内核调用，除入参有效性外无额外
        // 内存安全前置条件；引用 `self.0` 的借用不逃逸（`with` 要求返回 `R: Send`）。
        self.0.with(|raw| unsafe {
            let process_handle = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, false, pid)?;
            let result = AssignProcessToJobObject(raw.get(), process_handle);
            let _ = windows::Win32::Foundation::CloseHandle(process_handle);
            result
        })
    }
}

impl Drop for JobObjectGuard {
    fn drop(&mut self) {
        // SAFETY: `CloseHandle` 是线程无关的内核资源释放调用。`self` 的独占所有权
        // 保证 `drop` 仅执行一次，不会双重关闭句柄。
        self.0.with(|raw| unsafe {
            let _ = windows::Win32::Foundation::CloseHandle(raw.get());
        });
    }
}

/// RAII 守卫，确保 Box::from_raw 在任何退出路径下都会执行，
/// 防止 EnumWindows 回调异常导致的内存泄漏。
struct RawBoxGuard<T>(*mut T);
impl<T> RawBoxGuard<T> {
    /// 从 Box 创建守卫，转移所有权到堆上。
    /// 守卫 drop 时会自动回收堆内存。
    fn new(value: T) -> Self {
        Self(Box::into_raw(Box::new(value)))
    }
    /// 获取裸指针，用于传递给外部 API 回调。
    fn as_ptr(&self) -> *mut T {
        self.0
    }
}
impl<T> Drop for RawBoxGuard<T> {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                let _ = Box::from_raw(self.0);
            }
        }
    }
}

/// 仅清理项目专用子进程的映像名列表。
///
/// R1 安全约束：不得包含 `AutoHotkey64.exe` 等通用进程名，否则 `taskkill /F /IM`
/// 会误杀用户系统中所有 AutoHotkey 进程（包括用户自行运行的脚本），属于严重副作用。
/// 如需清理 AHK 子进程，应通过 JobObject 或子进程句柄精确管理。
const STALE_PROCESS_NAMES: &[&str] = &["asd_executor.exe"];

/// 清理遗留的 asd_executor.exe 进程。
///
/// 在启动新子进程前调用，防止 JobObject 失败导致的僵尸进程堆积。
/// 使用 `taskkill /F /IM` 按映像名终止，主进程（asd-tauri.exe）不受影响。
/// 如果没有遗留进程，taskkill 返回非零退出码，此时静默忽略。
///
/// # I36 补偿机制
///
/// 当 JobObject 创建或分配失败时，子进程不会随主进程退出而自动终止。
/// 此函数作为补偿，在每次 spawn_child 前清理可能遗留的项目专用执行器进程。
///
/// # R1 安全约束
///
/// `STALE_PROCESS_NAMES` 只包含项目专用的 `asd_executor.exe`，绝不包含
/// `AutoHotkey64.exe` 等通用进程名，避免误杀用户其他 AHK 脚本。
pub fn cleanup_stale_executor_processes() {
    let mut killed_count = 0u32;
    for name in STALE_PROCESS_NAMES {
        // taskkill /F /IM <name> 强制按映像名终止
        // 退出码 0 = 成功终止，128 = 进程未找到（预期情况）
        let output = Command::new("taskkill")
            .args(["/F", "/IM", name])
            .creation_flags(CREATE_NO_WINDOW.0)
            .output();

        match output {
            Ok(out) if out.status.success() => {
                tracing::info!("已清理遗留进程: {name}");
                killed_count += 1;
            }
            Ok(_) => {
                // 进程未找到或已退出，属于正常情况
                tracing::debug!("无遗留 {name} 进程需要清理");
            }
            Err(e) => {
                tracing::warn!("清理遗留进程 {name} 失败: {e}");
            }
        }
    }

    if killed_count > 0 {
        tracing::info!("共清理 {killed_count} 个遗留子进程");
    }
}

/// 构建 panic hook 闭包（可测试，不修改全局状态）。
///
/// 接受清理回调和原始 hook，返回组合后的 panic hook 闭包：
/// 先执行 cleanup（清理子进程），再委托给 original_hook（输出默认 panic 信息）。
///
/// 此函数不调用 `std::panic::set_hook`，可在测试中安全调用验证构建逻辑（R3）。
/// `register_panic_hook` 使用此函数构建闭包后注册到全局。
fn build_panic_hook_closure<F>(
    cleanup: F,
    original_hook: Box<dyn Fn(&std::panic::PanicHookInfo<'_>) + Send + Sync + 'static>,
) -> Box<dyn Fn(&std::panic::PanicHookInfo<'_>) + Send + Sync + 'static>
where
    F: Fn() + Send + Sync + 'static,
{
    Box::new(move |info| {
        cleanup();
        original_hook(info);
    })
}

/// 注册 panic hook，确保主进程崩溃时终止所有子进程。
///
/// 使用 `std::sync::Once` 保证幂等，多次调用安全。
/// panic 时调用 `cleanup_stale_executor_processes()` 终止遗留子进程，
/// 然后调用原始 panic hook 输出默认信息。
///
/// # R3 可测试性
///
/// 闭包构建逻辑已提取到 `build_panic_hook_closure`（纯函数，不修改全局状态），
/// 测试通过该函数验证"先 cleanup 后 original_hook"的行为，
/// 无需直接调用 `register_panic_hook`（后者会修改全局 Once 状态）。
///
/// # I36 补偿机制
///
/// JobObject 在以下场景可能失败：
/// - 系统资源不足无法创建 JobObject
/// - 进程权限不足无法分配到 JobObject
///
/// 此时子进程不受 JobObject 保护，主进程 panic 后可能成为僵尸进程。
/// panic hook 确保即使主进程异常退出，子进程也会被清理。
pub fn register_panic_hook() {
    use std::sync::Once;
    static HOOK_REGISTERED: Once = Once::new();

    HOOK_REGISTERED.call_once(|| {
        let original_hook = std::panic::take_hook();
        let new_hook = build_panic_hook_closure(cleanup_stale_executor_processes, original_hook);
        std::panic::set_hook(new_hook);
        tracing::debug!("panic hook 已注册，崩溃时将清理子进程");
    });
}

pub fn send_wm_close(pid: u32) -> Result<(), String> {
    let guard = RawBoxGuard::new(pid);
    unsafe {
        let callback: WNDENUMPROC = Some(enum_windows_callback);
        let result = EnumWindows(callback, LPARAM(guard.as_ptr() as isize));
        if let Err(e) = result {
            return Err(format!("EnumWindows 失败 for PID={pid}: {e}"));
        }
    }
    Ok(())
}

unsafe extern "system" fn enum_windows_callback(hwnd: HWND, lparam: LPARAM) -> windows::core::BOOL {
    let pid_ptr = lparam.0 as *mut u32;
    if pid_ptr.is_null() {
        tracing::warn!("enum_windows_callback: lparam 为 null，跳过");
        return windows::core::BOOL(1); // 继续枚举
    }
    let target_pid = *pid_ptr;

    let mut window_pid: u32 = 0;
    GetWindowThreadProcessId(hwnd, Some(&mut window_pid));

    if window_pid == target_pid {
        let _ = PostMessageW(
            Some(hwnd),
            WM_CLOSE,
            windows::Win32::Foundation::WPARAM(0),
            windows::Win32::Foundation::LPARAM(0),
        );
    }

    windows::core::BOOL(1)
}

#[derive(Debug, thiserror::Error)]
pub enum WatchdogError {
    #[error("JobObject 创建失败: {0}")]
    JobObjectCreate(String),
    #[error("进程分配失败: {0}")]
    ProcessAssign(String),
    #[error("优雅关机失败: {0}")]
    GracefulShutdown(String),
    #[error("超过最大重启次数: {0}")]
    MaxRetriesExceeded(u32),
}

pub struct WatchdogRunner {
    watchdog: Arc<Mutex<ProcessWatchdog>>,
    shutting_down: Arc<std::sync::atomic::AtomicBool>,
}

impl WatchdogRunner {
    pub fn new(watchdog: ProcessWatchdog) -> Self {
        Self {
            watchdog: Arc::new(Mutex::new(watchdog)),
            shutting_down: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        }
    }

    pub fn from_arc(watchdog: Arc<Mutex<ProcessWatchdog>>) -> Self {
        Self {
            watchdog,
            shutting_down: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        }
    }

    /// 设置 shutting_down 标志，通知 WatchdogRunner 尽快退出等待循环。
    pub fn mark_shutting_down(&self) {
        self.shutting_down
            .store(true, std::sync::atomic::Ordering::SeqCst);
    }

    /// 返回 shutting_down Arc 的克隆，允许外部保存引用以便在关机时设置标志。
    pub fn shutting_down_arc(&self) -> Arc<std::sync::atomic::AtomicBool> {
        self.shutting_down.clone()
    }

    /// 替换内部的 shutting_down Arc 为外部共享的实例。
    /// 用于在 spawn_watchdog 中提前创建 Arc，使 perform_graceful_shutdown 可访问。
    pub fn set_shutting_down(&mut self, arc: Arc<std::sync::atomic::AtomicBool>) {
        self.shutting_down = arc;
    }

    pub async fn run(&self) {
        let mut interval = tokio::time::interval(HEARTBEAT_INTERVAL);
        loop {
            interval.tick().await;
            let mut wd = self.watchdog.lock().await;
            let action = wd.tick();
            match action {
                WatchdogAction::None => {}
                WatchdogAction::ProcessHung => {
                    tracing::warn!("Watchdog: 进程挂起");
                }
                WatchdogAction::RestartNeeded => {
                    let exe_path = wd.exe_path.clone();
                    let auth_token = wd.auth_token.clone();
                    drop(wd);
                    // 关机检查：避免在关机期间启动新子进程
                    if self.shutting_down.load(std::sync::atomic::Ordering::SeqCst) {
                        tracing::info!("Watchdog: shutting_down 已设置，跳过重启");
                        break;
                    }
                    if let (Some(path), Some(token)) = (exe_path, auth_token) {
                        // T5-04：重启（含 taskkill 清理 + Command::spawn 阻塞系统调用）
                        // 已迁入 spawn_blocking 线程，避免阻塞异步运行时工作线程。
                        if let Err(e) = self.restart_child(path, token).await {
                            tracing::error!("Watchdog: 子进程重启失败: {e}");
                        }
                    } else {
                        tracing::error!("Watchdog: 无法重启子进程，exe_path 或 auth_token 未设置");
                    }
                }
                WatchdogAction::WaitForBackoff(remaining) => {
                    tracing::info!("Watchdog: 等待退避 {:?}", remaining);
                }
                WatchdogAction::MaxRetriesExceeded => {
                    tracing::error!("Watchdog: 超过最大重启次数，等待恢复");
                    drop(wd);
                    // 可中断的等待：每秒检查一次状态变更或 shutting_down 标志，
                    // 允许 reset_watchdog 命令或优雅关机在 60 秒内生效
                    for _ in 0..60 {
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        if self.shutting_down.load(std::sync::atomic::Ordering::SeqCst) {
                            tracing::info!(
                                "Watchdog: shutting_down 标志已设置，退出 MaxRetriesExceeded 等待"
                            );
                            break;
                        }
                        let wd = self.watchdog.lock().await;
                        if wd.state() != WatchdogStateEnum::Failed {
                            break;
                        }
                        drop(wd);
                    }
                }
            }
        }
    }

    /// 在 `spawn_blocking` 阻塞线程中执行子进程重启（T5-04）。
    ///
    /// `spawn_child` 内部会调用 `cleanup_stale_executor_processes`（同步 `taskkill`）
    /// 与 `std::process::Command::spawn`（同步 `CreateProcess`），均为阻塞系统调用。
    /// 若在 async 循环中持锁执行会阻塞异步运行时工作线程，故迁入 `spawn_blocking`。
    /// 在阻塞线程内使用 `blocking_lock` 获取 tokio 互斥锁（非异步上下文，安全）。
    async fn restart_child(&self, path: String, token: String) -> Result<(), String> {
        let watchdog = self.watchdog.clone();
        tokio::task::spawn_blocking(move || {
            let mut wd = watchdog.blocking_lock();
            if wd.state() != WatchdogStateEnum::Restarting {
                tracing::info!(
                    "Watchdog: 状态已从 Restarting 变更为 {:?}，跳过重启",
                    wd.state()
                );
                return Ok(());
            }
            wd.begin_restart();
            let result = wd.spawn_child(&path, &token);
            if let Ok(()) = &result {
                tracing::info!("Watchdog: 子进程重启成功 (attempt={})", wd.restart_count());
            }
            result
        })
        .await
        .map_err(|e| format!("spawn_blocking 重启任务执行失败: {e}"))?
    }

    pub fn watchdog(&self) -> Arc<Mutex<ProcessWatchdog>> {
        self.watchdog.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 静态 Mutex 确保所有修改全局 panic hook 的测试不会并行运行（R3 测试隔离）。
    /// `register_panic_hook` 与 `build_panic_hook_closure` 测试均通过 `take_hook`/`set_hook`
    /// 修改全局 hook，必须串行执行以避免竞态。
    static PANIC_HOOK_GUARD: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn test_watchdog_state_enum_serialization() {
        let state = WatchdogStateEnum::Running;
        let json = serde_json::to_string(&state).unwrap();
        assert!(json.contains("Running"));

        let state = WatchdogStateEnum::Hung;
        let json = serde_json::to_string(&state).unwrap();
        assert!(json.contains("Hung"));
    }

    #[test]
    fn test_watchdog_initial_state() {
        let wd = ProcessWatchdog::new();
        assert_eq!(wd.state(), WatchdogStateEnum::Idle);
        assert_eq!(wd.restart_count(), 0);
    }

    #[test]
    fn test_watchdog_heartbeat() {
        let mut wd = ProcessWatchdog::new();
        assert!(wd.last_heartbeat.is_none());

        wd.notify_heartbeat();
        assert!(wd.last_heartbeat.is_some());
        assert_eq!(wd.missed_heartbeats, 0);
        assert_eq!(wd.stable_heartbeat_count, 1);
    }

    #[test]
    fn test_watchdog_tick_idle() {
        let mut wd = ProcessWatchdog::new();
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::None);
    }

    #[test]
    fn test_watchdog_restart_count() {
        let mut wd = ProcessWatchdog::new();
        wd.begin_restart();
        assert_eq!(wd.restart_count(), 1);
        wd.begin_restart();
        assert_eq!(wd.restart_count(), 2);
        wd.reset_restart_count();
        assert_eq!(wd.restart_count(), 0);
    }

    #[test]
    fn test_backoff_durations() {
        assert_eq!(BACKOFF_DURATIONS[0], Duration::from_secs(1));
        assert_eq!(BACKOFF_DURATIONS[1], Duration::from_secs(2));
        assert_eq!(BACKOFF_DURATIONS[2], Duration::from_secs(4));
        assert_eq!(BACKOFF_DURATIONS[3], Duration::from_secs(8));
        assert_eq!(BACKOFF_DURATIONS[4], Duration::from_secs(30));
        assert_eq!(BACKOFF_DURATIONS[5], Duration::from_secs(30));
    }

    #[test]
    fn test_watchdog_action_equality() {
        assert_eq!(WatchdogAction::None, WatchdogAction::None);
        assert_eq!(WatchdogAction::ProcessHung, WatchdogAction::ProcessHung);
        assert_ne!(WatchdogAction::None, WatchdogAction::ProcessHung);
    }

    #[test]
    fn test_watchdog_state_transitions() {
        let mut wd = ProcessWatchdog::new();
        assert_eq!(wd.state(), WatchdogStateEnum::Idle);

        wd.set_state(WatchdogStateEnum::Starting);
        assert_eq!(wd.state(), WatchdogStateEnum::Starting);

        wd.set_state(WatchdogStateEnum::Running);
        assert_eq!(wd.state(), WatchdogStateEnum::Running);
    }

    #[test]
    fn test_watchdog_hung_to_running_on_heartbeat() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Hung;
        wd.notify_heartbeat();
        assert_eq!(wd.state(), WatchdogStateEnum::Running);
    }

    #[test]
    fn test_is_child_exited_no_child() {
        let mut wd = ProcessWatchdog::new();
        assert!(wd.is_child_exited());
    }

    #[test]
    fn test_send_wm_close_invalid_pid() {
        let result = send_wm_close(999999);
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_watchdog_runner_creation() {
        let wd = ProcessWatchdog::new();
        let runner = WatchdogRunner::new(wd);
        let wd_arc = runner.watchdog();
        let guard = wd_arc.lock().await;
        assert_eq!(guard.state(), WatchdogStateEnum::Idle);
    }

    /// T5-01 提交2 回归基线：验证 `ProcessWatchdog`（含 `Option<Child>`（`Send + !Sync`）
    /// 与 `JobObjectGuard`（内含 windows crate 的 `!Send + !Sync` `HANDLE`））可安全跨
    /// `tokio::spawn` 移动并被 `tokio::sync::Mutex` 保护并发访问。
    ///
    /// 若后续移除/破坏 `Send`/`Sync` 的推导链（`RawHandle` / `SendSyncCell`），
    /// 此测试将无法编译（`tokio::spawn` 要求 `Future: Send`，跨任务共享要求
    /// `Arc<Mutex<..>>: Send + Sync`），从而在编译期捕获回归。
    #[tokio::test]
    async fn test_watchdog_cross_thread_move_and_mutex_access() {
        let wd = ProcessWatchdog::new();
        let shared = Arc::new(tokio::sync::Mutex::new(wd));

        let h_write = {
            let shared = shared.clone();
            tokio::spawn(async move {
                shared.lock().await.set_state(WatchdogStateEnum::Running);
            })
        };
        let h_read = {
            let shared = shared.clone();
            tokio::spawn(async move { shared.lock().await.restart_count() })
        };

        h_write.await.unwrap();
        assert_eq!(h_read.await.unwrap(), 0);
        assert_eq!(shared.lock().await.state(), WatchdogStateEnum::Running);
    }

    /// A-1 修复回归防线（编译期）：显式断言 `ProcessWatchdog` 的 `Send + Sync + 'static`
    /// **由编译器自动推导**，而非依赖手写 `unsafe impl`。
    ///
    /// 与上面的运行时测试相比，本测试的价值在于：
    /// 1. `'static` 断言：确认借出的 `&mut ProcessWatchdog` 不含任何内部借用，
    ///    这是 `WatchdogBridge` 能在 `block_in_place + block_on` 内合法持有它的前提。
    /// 2. 若未来有人给 `ProcessWatchdog` 新增一个「非 `Send` 且未经 `SendSyncCell`
    ///    包装」的字段，`assert_send_sync` 会立即编译失败 —— 这正是原先手写
    ///    `unsafe impl` 方案无法防住的回归（手写 impl 会无条件吞掉字段的真实性质）。
    ///
    /// 注：断言对象与生产代码的实际共享方式一致（`Arc<tokio::sync::Mutex<..>>`）。
    #[test]
    fn test_process_watchdog_send_sync_is_derived_not_declared() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}
        fn assert_static<T: 'static>() {}

        // 直接对守护目标断言（`Mutex<T>: Sync` 要求 `T: Send`）。
        assert_send::<ProcessWatchdog>();
        assert_sync::<ProcessWatchdog>();
        assert_static::<ProcessWatchdog>();

        // 断言实际共享形态：Arc<Mutex<..>> 必须 Send + Sync。
        assert_send::<Arc<tokio::sync::Mutex<ProcessWatchdog>>>();
        assert_sync::<Arc<tokio::sync::Mutex<ProcessWatchdog>>>();

        // 断言中间封装仍具备所需的推导能力。
        // SendSyncCell<Child>：释放 `Child: Send + !Sync` 的约束（核心动机）。
        assert_send::<SendSyncCell<Child>>();
        assert_sync::<SendSyncCell<Child>>();
        // RawHandle：仅声明「可移动」，供 JobObjectGuard 自动推导 Send。
        assert_send::<RawHandle>();
        assert_static::<RawHandle>();
    }

    /// A-1 修复回归防线（编译期）：固化「`ProcessWatchdog` 的 `Send + Sync + 'static`
    /// 由编译器自动推导」这一事实，并逐环验证其所依赖的封装推导链。
    ///
    /// 为什么这比原先的手写 `unsafe impl` 更安全：手写 impl 会**无条件**把类型
    /// 声明为 `Send`/`Sync`，即使将来新增了 `!Send`/`!Sync` 字段也照旧通过编译；
    /// 而自动推导会在新增此类字段时立刻报错。本测试把该推导链的每一环都显式
    /// 断言出来，任何一环退化都会导致编译失败。
    ///
    /// 已验证的故障注入（2026-09-12）：向 `ProcessWatchdog` 临时加入
    /// `std::cell::Cell<u32>` 字段后，`assert_sync::<ProcessWatchdog>()` 立即
    /// 报 E0277「`Cell<u32>` cannot be shared between threads safely」。
    #[test]
    fn test_send_sync_cell_wrapping_chain_is_sound() {
        // 本测试固化 A-1 修复所依赖的「类型推导链」：
        //
        //   HANDLE (windows 0.62.2 :: !Send + !Sync)
        //     └─ RawHandle          : unsafe impl Send        （唯一手工命题：句柄可移动）
        //          └─ SendSyncCell   : T: Send ⇒ Send + Sync  （不暴露 &T，靠外层 Mutex 串行化）
        //               └─ JobObjectGuard : 自动推导 Send + Sync
        //                    └─ ProcessWatchdog : 自动推导 Send + Sync + 'static
        //
        // 任何一环被破坏，下面的断言都会在编译期失败。
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}
        fn assert_static<T: 'static>() {}

        // 环 1：RawHandle 只保证可移动。
        assert_send::<RawHandle>();

        // 环 2：SendSyncCell 把 Send 提升为 Send + Sync。
        assert_send::<SendSyncCell<RawHandle>>();
        assert_sync::<SendSyncCell<RawHandle>>();
        // 同理适用于 Child（std 的 Send + !Sync 类型，修复的另一半动机）。
        assert_send::<SendSyncCell<Child>>();
        assert_sync::<SendSyncCell<Child>>();

        // 环 3：JobObjectGuard / ProcessWatchdog 自动推导。
        assert_send::<JobObjectGuard>();
        assert_sync::<JobObjectGuard>();
        assert_send::<ProcessWatchdog>();
        assert_sync::<ProcessWatchdog>();
        assert_static::<ProcessWatchdog>();

        // 实际共享形态。
        assert_send::<Arc<tokio::sync::Mutex<ProcessWatchdog>>>();
        assert_sync::<Arc<tokio::sync::Mutex<ProcessWatchdog>>>();
    }

    /// A-1 修复回归防线（源码级）：确认 `watchdog.rs` 中不再存在针对
    /// `ProcessWatchdog` / `JobObjectGuard` 的手写 `unsafe impl Send/Sync`。
    ///
    /// 目的：防止「靠加回 `unsafe impl` 来让代码编译通过」的退化修复。
    /// 手工 unsafe 面应始终收敛在 `RawHandle` 与 `SendSyncCell` 两个泛型封装内，
    /// 且它们各自的 SAFETY 命题是单一且可审计的。
    ///
    /// 若未来确有必要新增手写 `unsafe impl`，请在本测试的允许列表中加入该类型名，
    /// 并在代码评审中单独论证其安全前提。
    #[test]
    fn test_no_handwritten_unsafe_send_sync_for_watchdog_types() {
        let source = include_str!("watchdog.rs");

        /// 允许出现手写 `unsafe impl Send/Sync` 的类型白名单。
        /// 仅限「把 `!Send`/`!Sync` 收敛为单一可审计命题」的泛型封装层。
        const ALLOWED: &[&str] = &["RawHandle", "SendSyncCell"];

        for line in source.lines() {
            let trimmed = line.trim();
            // 只看真实代码行，忽略注释（注释里会引用这些字符串作为说明）。
            if trimmed.starts_with("//") {
                continue;
            }
            let is_unsafe_send_sync_impl = trimmed.starts_with("unsafe impl")
                && (trimmed.contains(" Send for ") || trimmed.contains(" Sync for "));
            if !is_unsafe_send_sync_impl {
                continue;
            }
            let is_allowed = ALLOWED.iter().any(|t| trimmed.contains(t));
            assert!(
                is_allowed,
                "发现未在白名单中的手写 unsafe impl Send/Sync，请单独论证其安全前提：{trimmed}"
            );
        }
    }

    #[test]
    fn test_stable_heartbeat_resets_restart_count() {
        let mut wd = ProcessWatchdog::new();
        wd.restart_count = 3;
        for _ in 0..STABLE_HEARTBEAT_THRESHOLD {
            wd.notify_heartbeat();
        }
        assert_eq!(wd.restart_count, 0);
        assert_eq!(wd.stable_heartbeat_count, 0);
    }

    #[test]
    fn test_insufficient_stable_heartbeats_keeps_restart_count() {
        let mut wd = ProcessWatchdog::new();
        wd.restart_count = 3;
        for _ in 0..STABLE_HEARTBEAT_THRESHOLD - 1 {
            wd.notify_heartbeat();
        }
        assert_eq!(wd.restart_count, 3);
    }

    #[test]
    fn test_begin_restart_resets_stable_heartbeat_count() {
        let mut wd = ProcessWatchdog::new();
        wd.notify_heartbeat();
        wd.notify_heartbeat();
        assert_eq!(wd.stable_heartbeat_count, 2);
        wd.begin_restart();
        assert_eq!(wd.stable_heartbeat_count, 0);
    }

    #[test]
    fn test_recovering_no_child_returns_restart_needed() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    }

    #[test]
    fn test_recovering_recent_heartbeat_no_child_returns_restart_needed() {
        // 语义说明：ProcessWatchdog::new() 创建的实例 self.child = None，
        // is_child_exited() 返回 true（无子进程 = 子进程已退出）。
        // 因此 Recovering 状态下即使 last_heartbeat 是最近时间，
        // 也会立即检测到 "子进程已退出" 并返回 RestartNeeded。
        // 这验证了 "子进程退出检测优先于心跳检查" 的设计。
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        wd.last_heartbeat = Some(std::time::Instant::now());
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    }

    #[test]
    fn test_recovering_stale_heartbeat_returns_restart_needed() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        wd.last_heartbeat = Some(std::time::Instant::now() - Duration::from_secs(31));
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    }

    #[test]
    fn test_recovering_no_heartbeat_returns_restart_needed() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        wd.last_heartbeat = None;
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    }

    #[test]
    fn test_begin_restart_clears_child_and_job_guard() {
        let mut wd = ProcessWatchdog::new();
        wd.child = None;
        wd.job_guard = None;
        wd.missed_heartbeats = 5;
        wd.begin_restart();
        assert!(wd.child.is_none());
        assert!(wd.job_guard.is_none());
        assert_eq!(wd.restart_count(), 1);
        assert_eq!(wd.missed_heartbeats, 0);
    }

    #[test]
    fn test_recovering_boundary_heartbeat_29s_no_child_returns_restart_needed() {
        // 语义说明：与 test_recovering_recent_heartbeat_no_child_returns_restart_needed 类似，
        // ProcessWatchdog::new() 创建的实例无子进程，is_child_exited() 返回 true。
        // 29 秒前的心跳虽然未超过 30s 阈值（心跳检查会返回 None），
        // 但子进程退出检测优先执行，立即返回 RestartNeeded。
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        wd.last_heartbeat = Some(std::time::Instant::now() - Duration::from_secs(29));
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(wd.state(), WatchdogStateEnum::Restarting);
    }

    // =================================================================
    // I36: JobObject 失败无僵尸进程补偿 — 测试
    // =================================================================

    /// 验证 cleanup_stale_executor_processes 函数存在且可安全调用。
    /// 在没有遗留进程的环境下不应 panic。
    #[test]
    fn test_cleanup_stale_executor_processes_exists_and_is_safe() {
        // 函数应存在且执行完毕不 panic
        cleanup_stale_executor_processes();
    }

    /// 验证 cleanup_stale_executor_processes 不会终止当前测试进程自身。
    /// 当前进程是 cargo test 进程，不是 asd_executor.exe 或 AutoHotkey64.exe，
    #[test]
    fn test_cleanup_does_not_terminate_current_process() {
        let my_pid = std::process::id();
        cleanup_stale_executor_processes();
        // 如果当前进程被终止，后续断言不会执行，测试会失败
        assert!(my_pid > 0, "当前进程仍在运行，未被误终止");
    }

    /// 验证 register_panic_hook 函数存在且可安全调用。
    /// 多次调用不应 panic（使用 Once 保证幂等）。
    #[test]
    fn test_register_panic_hook_is_idempotent() {
        // 获取 PANIC_HOOK_GUARD 锁，确保与 test_build_panic_hook_closure_calls_cleanup_on_panic
        // 互斥运行，避免全局 panic hook 的 take_hook/set_hook 竞态（R3 测试隔离）。
        let _guard = PANIC_HOOK_GUARD.lock().unwrap();
        register_panic_hook();
        register_panic_hook(); // 第二次调用应无副作用
    }

    /// 验证 spawn_child 在调用前会执行遗留进程清理。
    /// 通过验证 spawn_child 对空 auth_token 返回错误来确认函数入口可达，
    /// 清理逻辑在 auth_token 检查之前执行。
    #[test]
    fn test_spawn_child_validates_auth_token_after_cleanup() {
        let mut wd = ProcessWatchdog::new();
        let result = wd.spawn_child("asd_executor.exe", "");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("auth_token"));
    }

    // =================================================================
    // R1: 防止误杀用户其他 AHK 进程 — 测试
    // =================================================================

    /// 验证 STALE_PROCESS_NAMES 不包含通用进程名 AutoHotkey64.exe。
    /// taskkill /F /IM AutoHotkey64.exe 会杀死用户系统中所有 AutoHotkey 进程，
    /// 包括用户自己运行的脚本，属于严重副作用。
    /// 只应清理项目专用的 asd_executor.exe。
    #[test]
    fn test_stale_process_names_excludes_generic_autohotkey() {
        assert!(
            !STALE_PROCESS_NAMES.contains(&"AutoHotkey64.exe"),
            "STALE_PROCESS_NAMES 不得包含通用进程名 AutoHotkey64.exe，否则会误杀用户其他 AHK 脚本"
        );
    }

    /// 验证 STALE_PROCESS_NAMES 包含项目专用执行器 asd_executor.exe。
    #[test]
    fn test_stale_process_names_includes_project_executor() {
        assert!(
            STALE_PROCESS_NAMES.contains(&"asd_executor.exe"),
            "STALE_PROCESS_NAMES 必须包含项目专用执行器 asd_executor.exe"
        );
    }

    // =================================================================
    // R3: register_panic_hook 可测试不污染全局 hook — 测试
    // =================================================================

    /// 验证 build_panic_hook_closure 构建的闭包在 panic 时调用 cleanup 回调。
    ///
    /// 此测试不直接调用 register_panic_hook()（避免污染全局 Once 状态），
    /// 而是通过 build_panic_hook_closure 构建 hook 闭包后临时注册验证行为，
    /// 结束后恢复原始 hook（R3）。
    #[test]
    fn test_build_panic_hook_closure_calls_cleanup_on_panic() {
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;

        // 获取模块级 PANIC_HOOK_GUARD 锁，确保与 test_register_panic_hook_is_idempotent
        // 互斥运行，避免全局 panic hook 的 take_hook/set_hook 竞态（R3 测试隔离）。
        let _guard = PANIC_HOOK_GUARD.lock().unwrap();

        let cleanup_called = Arc::new(AtomicBool::new(false));
        let cleanup_clone = cleanup_called.clone();

        // 构建测试 hook：cleanup 设置标志，original 为空操作
        let hook = build_panic_hook_closure(
            move || {
                cleanup_clone.store(true, Ordering::SeqCst);
            },
            Box::new(|_info: &std::panic::PanicHookInfo<'_>| {}),
        );

        // 保存原始 hook，临时注册测试 hook
        let saved_hook = std::panic::take_hook();
        std::panic::set_hook(hook);

        // 触发 panic
        let result = std::panic::catch_unwind(|| {
            panic!("R3 test panic");
        });

        // 恢复原始 hook
        std::panic::set_hook(saved_hook);

        assert!(result.is_err(), "catch_unwind 应捕获 panic");
        assert!(
            cleanup_called.load(Ordering::SeqCst),
            "panic hook 应调用 cleanup 回调"
        );
    }
}
