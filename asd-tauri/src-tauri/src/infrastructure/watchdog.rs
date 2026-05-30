use serde::Serialize;
use std::os::windows::process::CommandExt;
use std::process::Child;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use windows::Win32::Foundation::{HANDLE, HWND, LPARAM};
use windows::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, SetInformationJobObject,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
    JOBOBJECTINFOCLASS,
};
use windows::Win32::System::Threading::{CREATE_NO_WINDOW, OpenProcess, PROCESS_SET_QUOTA, PROCESS_TERMINATE};
use windows::Win32::UI::WindowsAndMessaging::{EnumWindows, GetWindowThreadProcessId, PostMessageW, WNDENUMPROC, WM_CLOSE};

const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(1);
const HEARTBEAT_TIMEOUT_COUNT: u32 = 3;
/// 心跳总超时阈值：超过此时间未收到心跳响应即判定为超时
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(3);
const MAX_RESTART_ATTEMPTS: u32 = 10;
const BACKOFF_DURATIONS: [Duration; 10] = [
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

#[derive(Debug, Clone, PartialEq, Serialize)]
pub enum WatchdogStateEnum {
    Idle,
    Starting,
    Running,
    Hung,
    Restarting,
    Recovering,
    Failed,
}

type StateChangeCallback = Arc<dyn Fn(&WatchdogStateEnum) + Send + Sync>;

pub struct ProcessWatchdog {
    state: WatchdogStateEnum,
    child: Option<Child>,
    job_guard: Option<JobObjectGuard>,
    exe_path: Option<String>,
    restart_count: u32,
    missed_heartbeats: u32,
    backoff_duration: Duration,
    last_restart: Option<std::time::Instant>,
    last_heartbeat: Option<std::time::Instant>,
    on_state_change: Option<StateChangeCallback>,
    on_recover: Option<Arc<dyn Fn() + Send + Sync>>,
    send_shutdown: Option<Arc<dyn Fn() + Send + Sync>>,
}

// SAFETY: ProcessWatchdog 的所有字段都是 Send 安全的：
// - WatchdogStateEnum: Clone + Serialize，纯数据
// - Option<Child>: Child 是 Send
// - Option<JobObjectGuard>: 通过下面的 unsafe impl Send 标记
// - Option<String>, u32, Duration, Option<Instant>: 都是 Send
// - 各种 Option<Arc<dyn Fn>>: 闭包要求 Send + Sync
// ProcessWatchdog 仅在 tokio::sync::Mutex 保护下访问，确保线程安全
unsafe impl Send for ProcessWatchdog {}
// SAFETY: ProcessWatchdog 通过 Arc<Mutex<ProcessWatchdog>> 共享，
// 所有访问都在 Mutex 锁保护下，不存在并发访问
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
            restart_count: 0,
            missed_heartbeats: 0,
            backoff_duration: BACKOFF_DURATIONS[0],
            last_restart: None,
            last_heartbeat: None,
            on_state_change: None,
            on_recover: None,
            send_shutdown: None,
        }
    }

    pub fn set_on_state_change(&mut self, cb: Arc<dyn Fn(&WatchdogStateEnum) + Send + Sync>) {
        self.on_state_change = Some(cb);
    }

    pub fn set_on_recover(&mut self, cb: Arc<dyn Fn() + Send + Sync>) {
        self.on_recover = Some(cb);
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
                tracing::warn!("Watchdog: 创建 JobObject 失败: {e}，子进程仍将被跟踪但不会随主进程自动退出");
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
    pub fn spawn_child(&mut self, exe_path: &str) -> Result<(), String> {
        tracing::info!("Watchdog: 启动 AHK 子进程: {exe_path}");

        // Determine if this is portable mode (AutoHotkey64.exe or .bat launcher)
        let (program, args) = if exe_path.ends_with("asd_executor.exe") {
            // Compiled mode: run the exe directly
            (exe_path.to_string(), Vec::new())
        } else if exe_path.ends_with("asd_executor.bat") {
            // Portable mode via batch launcher: cmd /C launcher.bat
            ("cmd".to_string(), vec!["/C".to_string(), exe_path.to_string()])
        } else if exe_path.ends_with("AutoHotkey64.exe") {
            // Portable mode: AutoHotkey64.exe executor.ahk
            let script_path = exe_path.replace("AutoHotkey64.exe", "executor.ahk");
            (exe_path.to_string(), vec![script_path])
        } else {
            // Fallback: try to run as-is
            (exe_path.to_string(), Vec::new())
        };

        let mut cmd = Command::new(&program);
        cmd.creation_flags(CREATE_NO_WINDOW.0);
        if !args.is_empty() {
            cmd.args(&args);
        }

        let child = cmd
            .spawn()
            .map_err(|e| format!("启动子进程失败: {e} (program={program}, args={args:?})"))?;

        self.exe_path = Some(exe_path.to_string());
        self.attach_child(child)
    }

    pub fn notify_heartbeat(&mut self) {
        self.missed_heartbeats = 0;
        self.last_heartbeat = Some(std::time::Instant::now());
        if self.state == WatchdogStateEnum::Hung {
            self.set_state(WatchdogStateEnum::Running);
            tracing::info!("Watchdog: 进程从挂起状态恢复");
        }
        // 子进程成功发送心跳，说明运行稳定，重置重启计数器
        if self.restart_count > 0 {
            tracing::info!("Watchdog: 子进程运行稳定，重置重启计数器 (was={})", self.restart_count);
            self.reset_restart_count();
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
                if self.is_child_exited() {
                    self.set_state(WatchdogStateEnum::Restarting);
                    return WatchdogAction::RestartNeeded;
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
                if let Some(ref cb) = self.on_recover {
                    cb();
                }
                self.set_state(WatchdogStateEnum::Running);
                WatchdogAction::None
            }
            WatchdogStateEnum::Failed => WatchdogAction::MaxRetriesExceeded,
        }
    }

    pub fn begin_restart(&mut self) {
        self.restart_count += 1;
        self.last_restart = Some(std::time::Instant::now());
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
        tracing::info!("Watchdog: Phase 1 - 发送 IPC shutdown 消息 (超时 {:?})", SHUTDOWN_IPC_TIMEOUT);
        if let Some(ref send_shutdown) = self.send_shutdown {
            send_shutdown();
        } else {
            tracing::warn!("Watchdog: Phase 1 - send_shutdown 回调未设置，跳过 IPC shutdown 消息发送");
        }
        if self.wait_for_exit(SHUTDOWN_IPC_TIMEOUT).await {
            tracing::info!("Watchdog: 进程在 IPC shutdown 后退出");
            self.cleanup();
            return Ok(());
        }

        tracing::info!("Watchdog: Phase 2 - 发送 WM_CLOSE (超时 {:?})", SHUTDOWN_WM_CLOSE_TIMEOUT);
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
        // 注意：保留 exe_path 以便重启时使用
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
                BasicLimitInformation: windows::Win32::System::JobObjects::JOBOBJECT_BASIC_LIMIT_INFORMATION {
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
            AssignProcessToJobObject(self.0, process_handle)?;
            let _ = windows::Win32::Foundation::CloseHandle(process_handle);
            Ok(())
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

pub fn send_wm_close(pid: u32) -> Result<(), String> {
    let pid_ptr = Box::into_raw(Box::new(pid));
    unsafe {
        let callback: WNDENUMPROC = Some(enum_windows_callback);
        let result = EnumWindows(callback, LPARAM(pid_ptr as isize));
        let _ = Box::from_raw(pid_ptr);
        if let Err(e) = result {
            Err(format!("EnumWindows 失败 for PID={pid}: {e}"))
        } else {
            Ok(())
        }
    }
}

unsafe extern "system" fn enum_windows_callback(hwnd: HWND, lparam: LPARAM) -> windows::core::BOOL {
    let pid_ptr = lparam.0 as *mut u32;
    let target_pid = *pid_ptr;

    let mut window_pid: u32 = 0;
    GetWindowThreadProcessId(hwnd, Some(&mut window_pid));

    if window_pid == target_pid {
        let _ = PostMessageW(Some(hwnd), WM_CLOSE, windows::Win32::Foundation::WPARAM(0), windows::Win32::Foundation::LPARAM(0));
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
}

impl WatchdogRunner {
    pub fn new(watchdog: ProcessWatchdog) -> Self {
        Self {
            watchdog: Arc::new(Mutex::new(watchdog)),
        }
    }

    pub fn from_arc(watchdog: Arc<Mutex<ProcessWatchdog>>) -> Self {
        Self {
            watchdog,
        }
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
                    wd.begin_restart();
                    // 实际重启子进程：使用保存的 exe_path
                    if let Some(ref exe_path) = wd.exe_path {
                        let path_clone = exe_path.clone();
                        // 先清理旧进程资源
                        wd.child = None;
                        wd.job_guard = None;
                        // 尝试重新启动子进程
                        // 注意：不在此处 reset_restart_count()，避免子进程持续崩溃时
                        // 退避计数器被反复重置导致无限重启循环。restart_count 只在
                        // 子进程稳定运行一段时间后由外部逻辑重置。
                        match wd.spawn_child(&path_clone) {
                            Ok(()) => {
                                tracing::info!("Watchdog: 子进程重启成功 (attempt={})", wd.restart_count());
                            }
                            Err(e) => {
                                tracing::error!("Watchdog: 子进程重启失败: {e}");
                            }
                        }
                    } else {
                        tracing::error!("Watchdog: 无法重启子进程，exe_path 未设置");
                    }
                }
                WatchdogAction::WaitForBackoff(remaining) => {
                    tracing::info!("Watchdog: 等待退避 {:?}", remaining);
                }
                WatchdogAction::MaxRetriesExceeded => {
                    tracing::error!("Watchdog: 超过最大重启次数");
                    break;
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
}
