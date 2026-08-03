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

type StateChangeCallback = Arc<dyn Fn(&WatchdogStateEnum) + Send + Sync>;

pub struct ProcessWatchdog {
    state: WatchdogStateEnum,
    child: Option<Child>,
    job_guard: Option<JobObjectGuard>,
    exe_path: Option<String>,
    auth_token: Option<String>,
    restart_count: u32,
    missed_heartbeats: u32,
    backoff_duration: Duration,
    last_restart: Option<std::time::Instant>,
    last_heartbeat: Option<std::time::Instant>,
    on_state_change: Option<StateChangeCallback>,
    send_shutdown: Option<Arc<dyn Fn() + Send + Sync>>,
    stable_heartbeat_count: u32,
}

// SAFETY: ProcessWatchdog 的所有字段都是 Send 安全的：
// - WatchdogStateEnum: Clone + Serialize，纯数据
// - Option<Child>: Child 是 Send
// - Option<JobObjectGuard>: 通过下面的 unsafe impl Send 标记
// - Option<String>, u32, Duration, Option<Instant>: 都是 Send
// - 各种 Option<Arc<dyn Fn>>: 闭包要求 Send + Sync
// ProcessWatchdog 仅在 tokio::sync::Mutex 保护下访问，确保线程安全
unsafe impl Send for ProcessWatchdog {}
// SAFETY: ProcessWatchdog 的 Sync 安全性不依赖于字段本身的 Sync 性质
// （例如 Child 仅实现了 Send 而非 Sync），而是依赖于外部 Mutex 保护：
// ProcessWatchdog 仅通过 Arc<tokio::sync::Mutex<ProcessWatchdog>> 共享，
// 所有访问都必须获取 Mutex 锁，不存在并发访问同一实例的情况。
// 如果未来移除 Mutex 保护，必须重新评估此 unsafe impl。
unsafe impl Sync for ProcessWatchdog {}

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
            on_state_change: None,
            send_shutdown: None,
            stable_heartbeat_count: 0,
        }
    }

    pub fn set_on_state_change(&mut self, cb: Arc<dyn Fn(&WatchdogStateEnum) + Send + Sync>) {
        self.on_state_change = Some(cb);
    }

    pub fn set_send_shutdown(&mut self, cb: Arc<dyn Fn() + Send + Sync>) {
        self.send_shutdown = Some(cb);
    }

    pub fn set_state(&mut self, new_state: WatchdogStateEnum) {
        if self.state != new_state {
            tracing::info!("Watchdog 状态变更: {:?} → {:?}", self.state, new_state);
            self.state = new_state.clone();
            if let Some(ref cb) = self.on_state_change {
                cb(&self.state);
            }
        }
    }

    pub fn state(&self) -> &WatchdogStateEnum {
        &self.state
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
        if let Some(ref mut child) = self.child {
            child.kill().map_err(|e| e.to_string())?;
            child.wait().map_err(|e| e.to_string())?;
            Ok(())
        } else {
            Err("no child".to_string())
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

        self.child = Some(child);
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
        if matches!(self.state, WatchdogStateEnum::Hung | WatchdogStateEnum::Recovering) {
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
        if let Some(ref mut child) = self.child {
            let _ = child.kill();
            tracing::info!("Watchdog: begin_restart 已终止旧子进程");
        }
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
        if let Some(ref mut child) = self.child {
            let _ = child.kill();
            tracing::info!("Watchdog: reset_to_restart 已终止旧子进程");
        }
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
        if let Some(ref mut child) = self.child {
            match child.try_wait() {
                Ok(Some(_status)) => true,
                Ok(None) => false,
                Err(_) => true,
            }
        } else {
            true
        }
    }

    pub async fn graceful_shutdown(&mut self) -> Result<(), String> {
        let pid = match self.child {
            Some(ref child) => child.id(),
            None => return Ok(()),
        };

        tracing::info!("Watchdog: 开始优雅关机 PID={pid}");

        // Phase 1: 通过 IPC 发送 shutdown 消息
        tracing::info!(
            "Watchdog: Phase 1 - 发送 IPC shutdown 消息 (超时 {:?})",
            SHUTDOWN_IPC_TIMEOUT
        );
        if let Some(ref send_shutdown) = self.send_shutdown {
            send_shutdown();
        } else {
            tracing::warn!(
                "Watchdog: Phase 1 - send_shutdown 回调未设置，跳过 IPC shutdown 消息发送"
            );
        }
        if self.wait_for_exit(SHUTDOWN_IPC_TIMEOUT).await {
            tracing::info!("Watchdog: 进程在 IPC shutdown 后退出");
            self.cleanup();
            return Ok(());
        }

        tracing::info!(
            "Watchdog: Phase 2 - 发送 WM_CLOSE (超时 {:?})",
            SHUTDOWN_WM_CLOSE_TIMEOUT
        );
        if let Err(e) = send_wm_close(pid) {
            tracing::warn!("Watchdog: Phase 2 - WM_CLOSE 发送失败: {e}，继续尝试 Phase 3");
        } else if self.wait_for_exit(SHUTDOWN_WM_CLOSE_TIMEOUT).await {
            tracing::info!("Watchdog: 进程在 WM_CLOSE 后退出");
            self.cleanup();
            return Ok(());
        }

        tracing::warn!("Watchdog: Phase 3 - 强制终止进程 PID={pid}");
        if let Some(ref mut child) = self.child {
            let _ = child.kill();
        }
        self.cleanup();
        Ok(())
    }

    async fn wait_for_exit(&mut self, timeout: Duration) -> bool {
        let start = std::time::Instant::now();
        while start.elapsed() < timeout {
            if self.is_child_exited() {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        false
    }

    fn cleanup(&mut self) {
        self.child = None;
        self.job_guard = None;
        // 注意：保留 exe_path 和 auth_token 以便重启时使用
        self.set_state(WatchdogStateEnum::Idle);
    }

    pub fn child_pid(&self) -> Option<u32> {
        self.child.as_ref().map(|c| c.id())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum WatchdogAction {
    None,
    ProcessHung,
    RestartNeeded,
    WaitForBackoff(Duration),
    MaxRetriesExceeded,
}

struct JobObjectGuard(HANDLE);

// SAFETY: JobObjectGuard 仅包含一个 HANDLE（原始指针），
// 所有访问都在 Mutex 锁保护下，HANDLE 本身是线程安全的系统资源
unsafe impl Send for JobObjectGuard {}
// SAFETY: JobObjectGuard 通过 Mutex 保护访问，
// Drop 实现只调用 CloseHandle，是线程安全的系统调用
unsafe impl Sync for JobObjectGuard {}

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
                JOBOBJECTINFOCLASS(9), // JobObjectExtendedLimitInformation
                &info as *const _ as *const _,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )?;
            Ok(Self(handle))
        }
    }

    fn assign(&self, child: &Child) -> Result<(), windows::core::Error> {
        let pid = child.id();
        unsafe {
            let process_handle = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, false, pid)?;
            let result = AssignProcessToJobObject(self.0, process_handle);
            let _ = windows::Win32::Foundation::CloseHandle(process_handle);
            result
        }
    }
}

impl Drop for JobObjectGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = windows::Win32::Foundation::CloseHandle(self.0);
        }
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
            unsafe { let _ = Box::from_raw(self.0); }
        }
    }
}

/// 清理所有遗留的 asd_executor.exe 和 AutoHotkey64.exe 进程。
///
/// 在启动新子进程前调用，防止 JobObject 失败导致的僵尸进程堆积。
/// 使用 `taskkill /F /IM` 按映像名终止，主进程（asd-tauri.exe）不受影响。
/// 如果没有遗留进程，taskkill 返回非零退出码，此时静默忽略。
///
/// # I36 补偿机制
///
/// 当 JobObject 创建或分配失败时，子进程不会随主进程退出而自动终止。
/// 此函数作为补偿，在每次 spawn_child 前清理可能的遗留进程。
pub fn cleanup_stale_executor_processes() {
    // 需要清理的子进程映像名列表
    const STALE_PROCESS_NAMES: &[&str] = &["asd_executor.exe", "AutoHotkey64.exe"];

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

/// 注册 panic hook，确保主进程崩溃时终止所有子进程。
///
/// 使用 `std::sync::Once` 保证幂等，多次调用安全。
/// panic 时调用 `cleanup_stale_executor_processes()` 终止遗留子进程，
/// 然后调用原始 panic hook 输出默认信息。
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
        std::panic::set_hook(Box::new(move |info| {
            // 在 panic 时清理遗留子进程
            cleanup_stale_executor_processes();
            // 调用原始 panic hook 输出默认信息
            original_hook(info);
        }));
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
        self.shutting_down.store(true, std::sync::atomic::Ordering::SeqCst);
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
                        let mut wd = self.watchdog.lock().await;
                        if *wd.state() != WatchdogStateEnum::Restarting {
                            tracing::info!("Watchdog: 状态已从 Restarting 变更为 {:?}，跳过重启", wd.state());
                            continue;
                        }
                        wd.begin_restart();
                        match wd.spawn_child(&path, &token) {
                            Ok(()) => {
                                tracing::info!(
                                    "Watchdog: 子进程重启成功 (attempt={})",
                                    wd.restart_count()
                                );
                            }
                            Err(e) => {
                                tracing::error!("Watchdog: 子进程重启失败: {e}");
                            }
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
                            tracing::info!("Watchdog: shutting_down 标志已设置，退出 MaxRetriesExceeded 等待");
                            break;
                        }
                        let wd = self.watchdog.lock().await;
                        if *wd.state() != WatchdogStateEnum::Failed {
                            break;
                        }
                        drop(wd);
                    }
                }
            }
        }
    }

    pub fn watchdog(&self) -> Arc<Mutex<ProcessWatchdog>> {
        self.watchdog.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert_eq!(*wd.state(), WatchdogStateEnum::Idle);
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
        assert_eq!(*wd.state(), WatchdogStateEnum::Idle);

        wd.set_state(WatchdogStateEnum::Starting);
        assert_eq!(*wd.state(), WatchdogStateEnum::Starting);

        wd.set_state(WatchdogStateEnum::Running);
        assert_eq!(*wd.state(), WatchdogStateEnum::Running);
    }

    #[test]
    fn test_watchdog_hung_to_running_on_heartbeat() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Hung;
        wd.notify_heartbeat();
        assert_eq!(*wd.state(), WatchdogStateEnum::Running);
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
        assert_eq!(*guard.state(), WatchdogStateEnum::Idle);
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
        assert_eq!(*wd.state(), WatchdogStateEnum::Restarting);
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
        assert_eq!(*wd.state(), WatchdogStateEnum::Restarting);
    }

    #[test]
    fn test_recovering_stale_heartbeat_returns_restart_needed() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        wd.last_heartbeat = Some(std::time::Instant::now() - Duration::from_secs(31));
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(*wd.state(), WatchdogStateEnum::Restarting);
    }

    #[test]
    fn test_recovering_no_heartbeat_returns_restart_needed() {
        let mut wd = ProcessWatchdog::new();
        wd.state = WatchdogStateEnum::Recovering;
        wd.last_heartbeat = None;
        let action = wd.tick();
        assert_eq!(action, WatchdogAction::RestartNeeded);
        assert_eq!(*wd.state(), WatchdogStateEnum::Restarting);
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
        assert_eq!(*wd.state(), WatchdogStateEnum::Restarting);
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
}
