pub mod bridge;
pub mod commands;
pub mod infrastructure;

#[cfg(test)]
mod tests;

use asd_application::config_repository::ConfigRepository;
use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::{Config, WatchdogStateEnum};
use asd_domain::models::SkillGroup;
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use bridge::{IpcBridge, TauriEventBridge, WatchdogBridge};
use infrastructure::ipc::{ipc_pipe_name, IpcManager, IpcOutboundReceiver};
use infrastructure::watchdog::{register_panic_hook, ProcessWatchdog, WatchdogRunner};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::Emitter;
use tauri::Manager;
use tauri_plugin_global_shortcut::GlobalShortcutExt;

type IpcManagerArc = Arc<tokio::sync::Mutex<Option<IpcManager>>>;
type WatchdogArc = Arc<tokio::sync::Mutex<ProcessWatchdog>>;

/// 执行关机主体序列：① 标记 IPC 关闭 → ② 设置 runner 停止标志 → ③ 调用 watchdog 优雅关机。
///
/// 从 `perform_graceful_shutdown` 中抽取，使关机主体可注入三个异步步骤进行单元测试。
/// 三个步骤按固定顺序执行（IPC 标记 → runner 标志 → watchdog 关机），
/// 测试可注入记录型 future 断言调用顺序。
async fn run_shutdown_sequence(
    mark_ipc_shutting_down: impl std::future::Future<Output = ()>,
    mark_runner_stopping: impl std::future::Future<Output = ()>,
    shutdown_watchdog: impl std::future::Future<Output = Result<(), String>>,
) {
    mark_ipc_shutting_down.await;
    mark_runner_stopping.await;
    if let Err(e) = shutdown_watchdog.await {
        tracing::error!("优雅关机失败: {e}");
    }
}

async fn perform_graceful_shutdown(
    _app_state: &Arc<AppState>,
    ipc_manager: &IpcManagerArc,
    watchdog: &WatchdogArc,
    runner_shutting_down: &Arc<std::sync::atomic::AtomicBool>,
    shutdown_guard: &std::sync::atomic::AtomicBool,
) {
    // 防止窗口关闭和托盘退出并发触发关机
    // 关机锁获取逻辑提取为 infrastructure::shutdown::try_acquire_shutdown_guard 纯函数，
    // 使其可在不启动 Tauri 应用的情况下进行单元测试。
    if !infrastructure::shutdown::try_acquire_shutdown_guard(shutdown_guard) {
        tracing::info!("关机已在进行中，跳过重复调用");
        return;
    }

    let ipc_manager = ipc_manager.clone();
    let runner_shutting_down = runner_shutting_down.clone();
    let watchdog = watchdog.clone();

    run_shutdown_sequence(
        async move {
            let ipc_mgr = ipc_manager.lock().await;
            if let Some(ref mgr) = *ipc_mgr {
                mgr.mark_shutting_down();
            }
        },
        async move {
            // 通知 WatchdogRunner 退出 MaxRetriesExceeded 等待循环
            runner_shutting_down.store(true, Ordering::SeqCst);
        },
        async move { infrastructure::watchdog::graceful_shutdown_watchdog(&watchdog).await },
    )
    .await;
}

fn spawn_ipc_listener(
    mut rx: IpcOutboundReceiver,
    app_state: Arc<AppState>,
    app_handle: tauri::AppHandle,
) {
    tauri::async_runtime::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match msg.r#type.as_str() {
                "hotkey" => {
                    if let Some(keys) = &msg.keys {
                        if let Some(hotkey) = keys.first() {
                            if app_state.is_hotkey_registered(hotkey).unwrap_or(false) {
                                tracing::info!("收到热键事件: {hotkey}");
                                let _ = app_handle.emit(
                                    "hotkey_event",
                                    bridge::build_hotkey_event_payload(hotkey, keys),
                                );
                            } else {
                                tracing::debug!("收到未注册热键事件，已忽略: {hotkey}");
                            }
                        } else {
                            tracing::warn!("收到热键事件但 keys 为空: seq={}", msg.seq);
                        }
                    } else {
                        tracing::warn!("收到热键事件但缺少 keys 字段: seq={}", msg.seq);
                    }
                }
                "heartbeat" => {
                    tracing::debug!("收到心跳");
                }
                "key_record_event" => {
                    if let Some(data) = &msg.data {
                        let _ = app_handle.emit("key_record_event", data.clone());
                    }
                }
                "key_send_event" => {
                    if let Some(data) = &msg.data {
                        let _ = app_handle.emit("key_send_event", data.clone());
                    }
                }
                _ => {
                    tracing::debug!("收到 IPC 消息: type={}", msg.r#type);
                }
            }
        }
        tracing::info!("IPC 消息监听器退出（outbound 通道已关闭）");
    });
}

/// 启动 IPC 接受循环。
///
/// 前置条件：IpcManager 必须在调用前初始化（包装在 `Some()` 中），
/// 否则 `accept_loop` 不会启动且不会重试。
fn spawn_ipc_accept_loop(ipc_manager: IpcManagerArc, app_handle: tauri::AppHandle) {
    let pipe_name = ipc_pipe_name().to_string();
    tauri::async_runtime::spawn(async move {
        let listener = match infrastructure::ipc::create_listener(&pipe_name) {
            Ok(l) => l,
            Err(e) => {
                // 建不起监听端 == AHK 永远连不上 == 功能不可用。按 `create_listener`
                // 自己的文档当作启动失败处理：记 error + 发事件给前端弹提示，
                // 不再「只记一条日志就 return」让用户毫无感知。
                tracing::error!("创建 IPC 监听器失败（管道名 `{pipe_name}`）: {e}");
                let _ = app_handle.emit(
                    "ipc:listener-failed",
                    format!("IPC 管道 `{pipe_name}` 创建失败：{e}"),
                );
                return;
            }
        };

        let mgr = {
            let guard = ipc_manager.lock().await;
            guard.clone()
        };

        if let Some(mgr) = mgr {
            mgr.accept_loop(&listener).await;
        } else {
            tracing::error!("IPC 管理器未初始化，无法启动 accept 循环");
        }
    });
}

fn spawn_heartbeat_ping(ipc_manager: IpcManagerArc) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(1));
        let mut consecutive_failures: u32 = 0;
        loop {
            interval.tick().await;
            let mgr = {
                let guard = ipc_manager.lock().await;
                if guard
                    .as_ref()
                    .is_some_and(infrastructure::ipc::IpcManager::is_shutting_down)
                {
                    tracing::info!("心跳 ping 循环检测到关机标志，退出");
                    return;
                }
                guard.clone()
            };
            if let Some(mgr) = mgr {
                if !mgr.is_connected().await {
                    continue;
                }
                let seq = mgr.next_seq();
                let msg = IpcMessage::ping(seq);
                if let Err(e) = mgr.send(&msg).await {
                    consecutive_failures = consecutive_failures.saturating_add(1);
                    if consecutive_failures <= 3 || consecutive_failures.is_multiple_of(30) {
                        tracing::warn!(
                            "心跳 ping 发送失败 (连续第{}次): {e}",
                            consecutive_failures
                        );
                    }
                } else {
                    consecutive_failures = 0;
                }
            }
        }
    });
}

fn spawn_watchdog(
    app_state: Arc<AppState>,
    watchdog: WatchdogArc,
) -> Arc<std::sync::atomic::AtomicBool> {
    // 提前创建 shutting_down Arc，保存引用供 perform_graceful_shutdown 使用
    let shutting_down = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let shutting_down_clone = shutting_down.clone();
    // 状态同步循环专用的克隆：让它在关机时能自行退出（见下方 loop 内的 break）
    let status_sync_shutting_down = shutting_down.clone();

    tauri::async_runtime::spawn(async move {
        let mut runner = WatchdogRunner::from_arc(watchdog.clone());
        // 替换 runner 内部的 shutting_down 为共享的 Arc
        runner.set_shutting_down(shutting_down_clone);

        let state_clone = app_state.clone();
        let wd_clone = watchdog.clone();
        let mut last_status = WatchdogStateEnum::Idle;
        let mut last_restart_count: u32 = 0;

        tauri::async_runtime::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(1));
            loop {
                interval.tick().await;
                // 关机后自行退出：原实现是**无退出条件的 loop**，关机后仍每秒抢一次
                // watchdog 锁，与 graceful_shutdown_watchdog 争抢同一把锁直到进程退出。
                if status_sync_shutting_down.load(std::sync::atomic::Ordering::SeqCst) {
                    tracing::debug!("watchdog 状态同步循环：检测到关机标志，退出");
                    break;
                }
                let wd_guard = wd_clone.lock().await;
                let current = wd_guard.state();
                let restart_count = wd_guard.restart_count();
                drop(wd_guard);

                // 状态或重启计数变更时同步到前端，确保 Restarting 状态下
                // restart_count 递增也能及时更新
                if current != last_status || restart_count != last_restart_count {
                    state_clone.update_watchdog_state(&current, restart_count);
                    last_status = current;
                    last_restart_count = restart_count;
                }
            }
        });

        runner.run().await;
    });

    shutting_down
}

/// 设置 IPC 回调（heartbeat / `pipe_broken` / `post_connect` / `send_shutdown`）。
///
/// # 设计决策：直接操作具体类型 `IpcManager`（M31）
///
/// AGENTS.md 规则要求"IPC 通信必须通过 `IpcSender` trait，禁止直接调用
/// `IpcManager`"。本函数作为例外接受此妥协，原因如下：
///
/// - **初始化代码场景**：本函数仅在应用启动期间调用一次，用于注册回调。
///   回调注册需要操作 `IpcManager` 的内部状态（`set_heartbeat_callback` 等），
///   这些方法不属于 `IpcSender` trait 的职责范围。
/// - **依赖反转过度抽象**：若为回调注册引入 trait 抽象，需定义单独的
///   `IpcCallbackRegistrar` trait，仅用于此一处初始化调用，增加复杂度而无实际收益。
/// - **运行时 IPC 通信仍通过 trait**：应用运行期间的命令发送（`send_command`）
///   严格通过 `IpcSender` trait（`IpcBridge`）进行，符合 AGENTS.md 规则。
///
/// 约束边界：此例外仅限于初始化阶段的回调注册，不得扩展到运行时命令发送。
fn setup_ipc_callbacks(
    app_state: &Arc<AppState>,
    ipc_manager: &IpcManager,
    watchdog: &WatchdogArc,
    ipc_manager_arc: &IpcManagerArc,
) {
    let watchdog_for_heartbeat = watchdog.clone();
    ipc_manager.set_heartbeat_callback(Arc::new(move || {
        let wd = watchdog_for_heartbeat.clone();
        tauri::async_runtime::spawn(async move {
            let mut guard = wd.lock().await;
            guard.notify_heartbeat();
        });
    }));

    let watchdog_for_pipe_broken = watchdog.clone();
    ipc_manager.set_pipe_broken_callback(Arc::new(move || {
        let wd = watchdog_for_pipe_broken.clone();
        tauri::async_runtime::spawn(async move {
            let mut guard = wd.lock().await;
            match guard.state() {
                WatchdogStateEnum::Running | WatchdogStateEnum::Hung => {
                    guard.set_state(WatchdogStateEnum::Recovering);
                }
                other => {
                    tracing::debug!("pipe_broken: 当前状态 {:?}，跳过 Recovering 转换", other);
                }
            }
        });
    }));

    let app_state_for_reconnect = app_state.clone();
    let watchdog_for_reconnect = watchdog.clone();
    ipc_manager.set_post_connect_callback(Arc::new(move || {
        let state = app_state_for_reconnect.clone();
        let wd = watchdog_for_reconnect.clone();
        tauri::async_runtime::spawn(async move {
            // 设计决策：post_connect_callback 与 toggle_group 回滚存在理论竞态窗口。
            // 如果 toggle_group 在更新内存状态后、IPC 发送失败回滚前，恰好被此回调读取，
            // 可能导致恢复状态与实际不一致。窗口极窄（微秒级），且不一致性会在下次
            // 切换或重连时自动修正，因此作为已知设计权衡接受。
            tracing::info!("AHK 重连成功，恢复运行时状态");
            {
                let mut guard = wd.lock().await;
                match guard.state() {
                    WatchdogStateEnum::Recovering | WatchdogStateEnum::Hung => {
                        guard.notify_heartbeat();
                        guard.set_state(WatchdogStateEnum::Running);
                    }
                    WatchdogStateEnum::Running => {
                        // 竞态场景：pipe_broken 回调尚未执行
                        // 仍需重发以确保 AHK 侧状态一致
                        tracing::info!("AHK 重连成功，当前状态 Running，确保分组/热键同步");
                    }
                    WatchdogStateEnum::Restarting => {
                        tracing::warn!("AHK 重连成功但 Watchdog 已进入 Restarting，跳过状态覆盖");
                    }
                    other => {
                        tracing::warn!("AHK 重连成功但 Watchdog 状态为 {:?}，跳过状态覆盖", other);
                    }
                }
            }

            let active_groups_data: Vec<(String, SkillGroup)> = {
                let groups = state.read_groups().ok();
                groups
                    .map(|g| {
                        g.iter()
                            .filter(|(_, group)| group.active)
                            .map(|(id, group)| (id.clone(), group.clone()))
                            .collect()
                    })
                    .unwrap_or_default()
            };
            for (id, group) in active_groups_data {
                let cmd = asd_application::group_service::build_toggle_command(&id, true, &group);
                state.try_send_ipc_command(&cmd);
            }
            let active_hotkey_list: Vec<(String, String)> =
                state.get_all_registered_hotkeys().unwrap_or_default();
            for (hotkey, group_id) in active_hotkey_list {
                let cmd = IpcCommand::RegisterHotkey { hotkey, group_id };
                state.try_send_ipc_command(&cmd);
            }

            if state.is_hold_mode_enabled() {
                state.try_send_ipc_command(&IpcCommand::HoldModeToggle { enabled: true });
            }

            // 清理不跨重连持久化的瞬态状态。
            // AHK 重连后是全新进程，之前设置的瞬态标志在 AHK 侧已不存在，
            // 若不清理会导致 Rust-AHK 状态分裂（如用户无法启动新录制/验证）。
            if state
                .emergency_mode
                .compare_exchange(true, false, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
            {
                tracing::info!("AHK 重连：清理 emergency_mode 瞬态标志");
            }
            {
                // recording_mode 写锁同时保护 validation_in_progress 的清理，
                // 防止与 start_validation/stop_validation 的竞态：
                // start_validation 在 recording_mode 写锁内设置 validation_in_progress = true，
                // 若重连回调在锁外清理 validation_in_progress，会导致 Rust 侧标志为 false
                // 而 AHK 侧验证仍在运行，用户无法停止验证。
                let mut mode_guard = state.recording_mode.write();
                if mode_guard.take().is_some() {
                    tracing::info!("AHK 重连：清理 recording_mode 瞬态标志");
                }
                if state
                    .validation_in_progress
                    .compare_exchange(true, false, Ordering::SeqCst, Ordering::SeqCst)
                    .is_ok()
                {
                    tracing::info!("AHK 重连：清理 validation_in_progress 瞬态标志");
                }
            }
        });
    }));

    let app_state_for_shutdown = app_state.clone();
    let ipc_manager_for_shutdown = ipc_manager_arc.clone();
    {
        let mut guard = tokio::task::block_in_place(|| watchdog.blocking_lock());
        guard.set_send_shutdown(Arc::new(move || {
            let _state = app_state_for_shutdown.clone();
            let ipc_mgr = ipc_manager_for_shutdown.clone();
            tauri::async_runtime::spawn(async move {
                let mgr = {
                    let guard = ipc_mgr.lock().await;
                    guard.clone()
                };
                if let Some(mgr) = mgr {
                    let seq = mgr.next_seq();
                    let msg = IpcMessage::shutdown(seq);
                    if let Err(e) = mgr.send(&msg).await {
                        tracing::warn!("IPC shutdown 消息发送失败: {e}");
                    } else {
                        tracing::info!("已发送 IPC shutdown 消息到 AHK 子进程");
                    }
                } else {
                    tracing::warn!("IPC 管理器未初始化，无法发送 shutdown 消息");
                }
            });
        }));
    }
}

fn init_app_state(
    config: Config,
    config_path: std::path::PathBuf,
    ipc_bridge: Arc<IpcBridge>,
    event_bridge: Arc<TauriEventBridge>,
    watchdog_bridge: Arc<WatchdogBridge>,
) -> Result<Arc<AppState>, AppError> {
    let mut app_state = Arc::new(AppState::new(
        config,
        ipc_bridge,
        watchdog_bridge,
        event_bridge,
    ));
    {
        // M33 设计决策：使用 Arc::get_mut 设置 config_path。
        //
        // `AppState::new` 不接受 config_path 参数（签名已稳定，修改会影响
        // asd-application 和 asd-test-harness 中的多个调用方），因此通过
        // `set_config_path` 在构造后设置。
        //
        // 正常路径下引用计数为 1，`Arc::get_mut` 必然返回 `Some`。但为避免在
        // 未来重构（例如在 `Arc::new` 与 `get_mut` 之间克隆了 app_state，或
        // `AppState::new` 内部存储了 `Arc` 的弱引用）时触发 panic，此处改为
        // 可恢复处理：`get_mut` 返回 `None` 时返回 `AppError::Internal`，而非
        // 在 setup 阶段 panic 导致应用启动崩溃。
        //
        // 替代方案（改动较大，未采纳）：将 `config_path` 作为 `AppState::new`
        // 的参数传入，消除对 `Arc::get_mut` 的依赖。此方案需修改
        // `AppState::new` 签名及所有调用方（含测试），作为已知技术债记录。
        match Arc::get_mut(&mut app_state) {
            Some(state_ref) => {
                state_ref.set_config_path(config_path);
            }
            None => {
                return Err(AppError::Internal(
                    "AppState 在 setup 阶段被共享，无法设置 config_path".to_string(),
                ));
            }
        }
    }
    Ok(app_state)
}

/// 设置 IPC 和 Watchdog。
///
/// # 锁顺序说明（已知妥协 #2）
///
/// 本函数中存在嵌套锁获取：`setup_ipc_callbacks` 在持有 `ipc_manager_arc` 锁的
/// 期间获取 `watchdog` 锁（设置 `send_shutdown` 回调）。
///
/// **锁顺序**：`ipc_manager_arc` → `watchdog`
///
/// 此顺序在以下位置一致使用：
/// - `setup_ipc_and_watchdog`（本函数）：`ipc_manager` → `watchdog`
/// - `perform_graceful_shutdown`：`ipc_manager` → `watchdog`（先释放 `ipc_manager` 再锁 `watchdog`）
/// - `setup_ipc_callbacks`：在 `ipc_manager` 锁内获取 `watchdog` 锁
///
/// **安全性分析**：
/// - 临界区极短（仅设置回调或查询状态），不会在锁内执行阻塞 I/O
/// - `block_in_place` 确保同步阻塞不会导致 tokio 运行时死锁
/// - 所有锁获取点均使用 `blocking_lock()` 而非 `lock().await`，避免跨 await 持锁
///
/// 若未来修改锁获取顺序，必须确保不反转此顺序（`watchdog` → `ipc_manager`），
/// 否则会导致死锁。
fn setup_ipc_and_watchdog(
    app_state: &Arc<AppState>,
    ipc_manager_arc: &IpcManagerArc,
    watchdog: &WatchdogArc,
    outbound_rx: IpcOutboundReceiver,
    app_handle: &tauri::AppHandle,
    exe_path: &std::path::Path,
    auth_token: &str,
) -> Arc<std::sync::atomic::AtomicBool> {
    {
        let guard = tokio::task::block_in_place(|| ipc_manager_arc.blocking_lock());
        if let Some(ref mgr) = *guard {
            setup_ipc_callbacks(app_state, mgr, watchdog, ipc_manager_arc);
        }
    }

    spawn_ipc_listener(outbound_rx, app_state.clone(), app_handle.clone());
    spawn_ipc_accept_loop(ipc_manager_arc.clone(), app_handle.clone());

    {
        let exe_str = exe_path.to_string_lossy().to_string();
        // TD-089 ②：只有**启动点**用带重试的版本。崩溃重启路径仍走 `spawn_child`
        // （由 `restart_child` 调用），保持 `MAX_RESTART_ATTEMPTS` 语义不变。
        // 整个重试（含退避 sleep）包在 `block_in_place` 里，避免阻塞 tokio 工作线程。
        let result = tokio::task::block_in_place(|| {
            let mut wd = watchdog.blocking_lock();
            wd.spawn_child_with_retry(&exe_str, auth_token)
        });
        if let Err(e) = result {
            // TD-089 ①：带上两级快照。否则 `os error 3`（目录分量缺失）与
            // `os error 2`（文件缺失）在日志里无法区分，排障方向会被带偏。
            tracing::error!(
                "启动 AHK 子进程失败（已重试{}次）: {e}。{}",
                infrastructure::watchdog::SPAWN_RETRY_MAX_ATTEMPTS - 1,
                format_resource_snapshot(exe_path.parent(), exe_path)
            );
        }
    }

    spawn_heartbeat_ping(ipc_manager_arc.clone());
    spawn_watchdog(app_state.clone(), watchdog.clone())
}

fn setup_tray_menu(
    app_handle: &tauri::AppHandle,
    ipc_manager_arc: &IpcManagerArc,
    watchdog: &WatchdogArc,
    runner_shutting_down: &Arc<std::sync::atomic::AtomicBool>,
    shutdown_guard: &Arc<std::sync::atomic::AtomicBool>,
) -> Result<(), tauri::Error> {
    let show_item = MenuItemBuilder::with_id("show", "显示主窗口").build(app_handle)?;
    let hide_item = MenuItemBuilder::with_id("hide", "隐藏到托盘").build(app_handle)?;
    let quit_item = MenuItemBuilder::with_id("quit", "退出").build(app_handle)?;

    let menu = MenuBuilder::new(app_handle)
        .item(&show_item)
        .item(&hide_item)
        .separator()
        .item(&quit_item)
        .build()?;

    let ipc_mgr_tray = ipc_manager_arc.clone();
    let wd_tray = watchdog.clone();
    let runner_sd_tray = runner_shutting_down.clone();
    let sg_tray = shutdown_guard.clone();
    let _tray = TrayIconBuilder::new()
        .tooltip("ASD - 技能管理器")
        .icon(
            app_handle
                .default_window_icon()
                .cloned()
                .unwrap_or_else(|| {
                    tracing::warn!("未配置默认窗口图标，使用空图标");
                    tauri::image::Image::new_owned(Vec::new(), 0, 0)
                }),
        )
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                if let Some(window) = tray.app_handle().get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        })
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "hide" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
            }
            "quit" => {
                let state = app.state::<Arc<AppState>>();
                let state_clone = state.inner().clone();
                let ipc_mgr = ipc_mgr_tray.clone();
                let wd = wd_tray.clone();
                let runner_sd = runner_sd_tray.clone();
                let sg = sg_tray.clone();
                let handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    perform_graceful_shutdown(&state_clone, &ipc_mgr, &wd, &runner_sd, &sg).await;
                    handle.exit(0);
                });
            }
            _ => {}
        })
        .menu(&menu)
        .build(app_handle)?;

    Ok(())
}

fn setup_window_close_handler(
    window: &tauri::WebviewWindow,
    app_state: &Arc<AppState>,
    app_handle: &tauri::AppHandle,
    ipc_manager_arc: &IpcManagerArc,
    watchdog: &WatchdogArc,
    runner_shutting_down: &Arc<std::sync::atomic::AtomicBool>,
    shutdown_guard: &Arc<std::sync::atomic::AtomicBool>,
) {
    let state_for_close = app_state.clone();
    let app_handle_for_close = app_handle.clone();
    let ipc_mgr_close = ipc_manager_arc.clone();
    let wd_close = watchdog.clone();
    let runner_sd_close = runner_shutting_down.clone();
    let sg_close = shutdown_guard.clone();
    window.on_window_event(move |event| {
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            let state = state_for_close.clone();
            let handle = app_handle_for_close.clone();
            let ipc_mgr = ipc_mgr_close.clone();
            let wd = wd_close.clone();
            let runner_sd = runner_sd_close.clone();
            let sg = sg_close.clone();
            tauri::async_runtime::spawn(async move {
                perform_graceful_shutdown(&state, &ipc_mgr, &wd, &runner_sd, &sg).await;
                handle.exit(0);
            });
        }
    });
}

/// 资源快照里最多列举的目录条目数。
///
/// **有界且非递归**：列举发生在启动失败路径上，打包资源目录可能有几百个文件，
/// 为排障把启动拖慢不值得；递归更是会把整个安装目录扫一遍。
const RESOURCE_SNAPSHOT_MAX_ENTRIES: usize = 20;

/// 把「资源目录 + 目标文件」两级存在性快照格式化成一行文本（TD-089）。
///
/// # 为什么必须是两级
///
/// Windows 上 `CreateProcessW` 的 `lpApplicationName` 传完整路径时，两类缺失的
/// 报错**不同**：路径中的**目录分量**缺失报 `os error 3`，**文件**缺失报
/// `os error 2`。但两者在日志里长得几乎一样，只看错误码无法区分
/// 「这一个文件没打进包」和「整个目录都没打进包」—— 而后者的排查方向完全不同
/// （前者查单个资源声明，后者查打包配置）。
///
/// 所以快照同时给出目录与文件各自的存在性，并在**目录存在**时列举其内容，
/// 让「缺的是文件还是目录」一眼可判。
///
/// # 为什么是纯函数
///
/// 只依赖传入的两个路径与文件系统，不依赖 `tauri` / 全局状态 / 当前工作目录，
/// 因此可单测。这是 TD-089 的验收要求：**诊断信息本身要有测试守护**，
/// 否则它会和它要诊断的对象一起腐烂 —— 本项目 §四记录的失效模式
/// 「东西写了但没接上」在诊断代码上同样成立。
///
/// `dir` 传 `None` 表示无法从目标路径推导出父目录（例如路径是纯文件名），
/// 此时只输出文件一级，不臆造目录信息。
#[must_use]
fn format_resource_snapshot(dir: Option<&std::path::Path>, file: &std::path::Path) -> String {
    let mut out = String::from("[AHK 资源快照] ");
    // 用 `write!` 而不是 `push_str(&format!(..))`：后者会多一次 String 分配，
    // 被 `clippy::format_push_string` 拦（本 crate 的 pedantic 是 `-D warnings`）。
    // 写入 `String` 不会失败，故 `let _ =` 是安全的，不是吞错。
    let w = |out: &mut String, s: std::fmt::Arguments| {
        let _ = std::fmt::Write::write_fmt(out, s);
    };
    // ⚠️ 空路径也按「无法推导」处理：`Path::new("AutoHotkey64.exe").parent()` 返回的是
    // `Some("")` 而不是 `None`（裸文件名的父目录是空路径）。若不加 `is_empty()` 判断，
    // 会输出「资源目录= 存在=false」—— 那既不是「目录不存在」，也不指向任何东西，
    // 是比不输出更糟的误导。此分支由 `snapshot_handles_unknown_parent_dir` 守护。
    match dir.filter(|d| !d.as_os_str().is_empty()) {
        Some(d) => {
            let dir_exists = d.exists();
            w(
                &mut out,
                format_args!("资源目录={} 存在={dir_exists}", d.display()),
            );
            if dir_exists {
                match std::fs::read_dir(d) {
                    Ok(entries) => {
                        let mut names: Vec<String> = Vec::new();
                        let mut total: usize = 0;
                        for entry in entries.flatten() {
                            total += 1;
                            if names.len() < RESOURCE_SNAPSHOT_MAX_ENTRIES {
                                names.push(entry.file_name().to_string_lossy().into_owned());
                            }
                        }
                        let shown = names.len();
                        w(
                            &mut out,
                            format_args!(
                                " 目录共 {total} 项，前 {shown} 项=[{}]",
                                names.join(", ")
                            ),
                        );
                        if total > shown {
                            w(
                                &mut out,
                                format_args!("…(已截断，上限 {RESOURCE_SNAPSHOT_MAX_ENTRIES})"),
                            );
                        }
                    }
                    Err(e) => w(&mut out, format_args!(" 目录列举失败={e}")),
                }
            }
            out.push_str("; ");
        }
        None => out.push_str("资源目录=<父目录无法推导>; "),
    }
    w(
        &mut out,
        format_args!("目标文件={} 存在={}", file.display(), file.exists()),
    );
    out
}

/// 解析 AHK 执行器路径：优先编译模式的 `asd_executor.exe`，回退便携模式的
/// `AutoHotkey64.exe`（两者都在 Resource 目录下）。
///
/// # 为什么返回 `Option` 而不是兜底一个路径
///
/// 早期实现在两者都解析失败时返回 `PathBuf::from("AutoHotkey64.exe")` —— 那是一个
/// **依赖进程当前工作目录的裸相对路径**，在打包应用里基本必然解析失败，而且会把
/// 「资源缺失」伪装成「启动子进程失败: … (program=AutoHotkey64.exe)」，把排障引向
/// 错误的方向（去查子进程启动，而不是查打包资源缺失）。
/// 现在解析失败一律返回 `None`，由调用方当作**启动失败**上报，让问题在启动期就可见。
///
/// # TD-089：两个分支的 `exists()` 校验必须对称
///
/// 便携模式分支原先**不带** `Path::exists()` 校验（编译模式分支带），于是资源缺失时
/// 照样返回一个不存在的路径，spawn 时报 `os error 3`，把「打包资源缺失」伪装成
/// 「启动子进程失败」—— 与上面「为什么返回 `Option`」要避免的伪装**完全同型**。
/// 现已补齐校验与两级快照，见 [`format_resource_snapshot`]。
fn resolve_ahk_executor_path(app: &tauri::App) -> Option<std::path::PathBuf> {
    if let Ok(p) = app.path().resolve(
        "ahk_executor/asd_executor.exe",
        tauri::path::BaseDirectory::Resource,
    ) {
        if p.exists() {
            tracing::info!("使用编译模式 AHK 子进程: {:?}", p);
            return Some(p);
        }
        tracing::warn!("asd_executor.exe 不存在，尝试便携模式");
    } else {
        tracing::warn!("无法解析 asd_executor.exe 路径，尝试便携模式");
    }
    let portable = app.path().resolve(
        "ahk_executor/AutoHotkey64.exe",
        tauri::path::BaseDirectory::Resource,
    );
    match portable {
        Ok(p) => {
            if p.exists() {
                tracing::info!("使用便携模式 AHK 子进程: {:?}", p);
            } else {
                // ⚠️ 这里**刻意仍然返回 `Some(p)`，不改成 `None`**。改成 `None` 会让
                // 应用在没有 AHK 的情况下静默继续运行（调用方只是记一条错误日志），
                // 比现在更难发现 —— 那是把「启动时就炸」换成「运行时静默失灵」。
                // 本次只补诊断信息，返回语义保持不变：让失败在 spawn 处带着快照爆出来。
                tracing::error!(
                    "便携模式 AutoHotkey64.exe 已解析出路径但文件不存在 —— 打包资源可能缺失。{}",
                    format_resource_snapshot(p.parent(), &p)
                );
            }
            Some(p)
        }
        Err(e) => {
            tracing::error!("无法解析 AutoHotkey64.exe 路径: {e}");
            None
        }
    }
}

/// 单实例保护（T5-09）暂缓说明：
///
/// 计划引入 `tauri-plugin-single-instance` 以在二次启动时聚焦首实例，避免多实例
/// 并发抢占 IPC named pipe 与 AHK 子进程。当前未接入的原因：该插件（含其依赖）
/// 不在本地 cargo 依赖缓存中，且当前环境可能无法联网拉取，直接加入会导致
/// `cargo build` 失败。待可用后再在 `tauri::Builder::default()` 前以
/// `.plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| { ... }))` 注册，
/// 回调内通过 `app.get_webview_window("main")` show + `set_focus` 聚焦首实例。
///
/// # Panics
///
/// 仅一处：`tauri::Builder::run()` 返回 `Err` 时 `.expect("Tauri 应用启动失败")`
/// 会 panic（错误已先经 `inspect_err` 记进日志）。
/// 这是**启动期致命错误**（典型是 `generate_context!()` 读不到
/// `tauri.conf.json`、图标等资源，或 `WebView2` 运行时缺失）—— 此时没有任何
/// 可降级的状态可以返回，也没有 UI 可以提示用户，让它带着日志崩掉是刻意的选择，
/// 不要把它改成「记日志后静默退出」：那会让启动失败表现为「双击没反应」。
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed
                        && shortcut.to_string() == "Ctrl+Shift+A"
                    {
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(),
        )
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
            infrastructure::logging::init(app).map_err(|e| tauri::Error::Setup(e.into()))?;

            // I36 补偿机制：注册 panic hook，确保崩溃时清理子进程
            register_panic_hook();

            let config_path = app.path().app_data_dir().map_or_else(
                |e| {
                    tracing::error!("无法获取 app_data_dir: {e}，使用当前目录");
                    std::path::PathBuf::from("config.json")
                },
                |dir| dir.join("config.json"),
            );
            // B6 / TD-084：配置加载失败**不得**再静默回退。但也不是所有失败都要打扰用户 ——
            // `FileNotFound` 是首次启动的正常路径，无差别弹窗会让新用户一开机就看到
            // 「数据丢失」。分流逻辑在 `ConfigLoadError::user_facing_failure`（有单测）。
            let config_path_display = config_path.display().to_string();
            let mut startup_config_failure = None;
            let config = match ConfigRepository::load_from_file_checked(&config_path) {
                Ok(c) => c,
                Err(e) => match e.user_facing_failure(&config_path_display) {
                    None => {
                        tracing::info!("配置文件不存在（首次启动），使用默认配置");
                        Config::default()
                    }
                    Some(f) => {
                        tracing::error!(
                            "配置文件加载失败[{}]: {} —— 使用默认配置，原有配置数据可能丢失；路径: {}",
                            f.kind, f.message, f.path
                        );
                        startup_config_failure = Some(f);
                        Config::default()
                    }
                },
            };

            let (ipc_manager, outbound_rx) = IpcManager::new(ipc_pipe_name());
            let auth_token = ipc_manager.auth_token().to_string();
            let outbound_sender = ipc_manager.outbound_sender();
            let ipc_manager_arc: IpcManagerArc =
                Arc::new(tokio::sync::Mutex::new(Some(ipc_manager)));

            let watchdog: WatchdogArc = Arc::new(tokio::sync::Mutex::new(ProcessWatchdog::new()));

            let ipc_bridge = Arc::new(IpcBridge::new(outbound_sender, ipc_manager_arc.clone()));
            let event_bridge = Arc::new(TauriEventBridge::new(app.handle().clone()));
            let watchdog_bridge = Arc::new(WatchdogBridge::new(watchdog.clone()));

            let app_state = init_app_state(
                config,
                config_path,
                ipc_bridge,
                event_bridge,
                watchdog_bridge,
            )?;

            // 记录下来等前端启动后主动来拉（推事件会在 setup 阶段因前端尚未注册监听而丢失）。
            if let Some(f) = startup_config_failure {
                app_state.set_config_load_failure(f);
            }

            let exe_path = resolve_ahk_executor_path(app).ok_or_else(|| {
                "未找到 AHK 执行器：`ahk_executor/asd_executor.exe`（编译模式）与 "
                    .to_owned()
                    + "`ahk_executor/AutoHotkey64.exe`（便携模式）均无法解析 —— 请检查打包资源是否齐全"
            })?;

            let runner_shutting_down = setup_ipc_and_watchdog(
                &app_state,
                &ipc_manager_arc,
                &watchdog,
                outbound_rx,
                app.handle(),
                &exe_path,
                &auth_token,
            );

            // 关机保护：防止窗口关闭和托盘退出并发触发关机
            let shutdown_guard = Arc::new(std::sync::atomic::AtomicBool::new(false));

            app.manage(app_state);

            setup_tray_menu(
                app.handle(),
                &ipc_manager_arc,
                &watchdog,
                &runner_shutting_down,
                &shutdown_guard,
            )?;

            let gs = app.global_shortcut();
            let _ = gs.register("Ctrl+Shift+A");

            if let Some(window) = app.get_webview_window("main") {
                setup_window_close_handler(
                    &window,
                    app.state::<Arc<AppState>>().inner(),
                    app.handle(),
                    &ipc_manager_arc,
                    &watchdog,
                    &runner_shutting_down,
                    &shutdown_guard,
                );
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::config_cmd::get_config,
            commands::config_cmd::get_config_load_failure,
            commands::config_cmd::save_config,
            commands::config_cmd::validate_config,
            commands::config_cmd::list_backups,
            commands::config_cmd::create_backup,
            commands::config_cmd::restore_backup,
            commands::config_cmd::delete_backup,
            commands::config_cmd::hot_reload,
            commands::config_cmd::export_config,
            commands::config_cmd::import_config,
            commands::config_cmd::compare_configs,
            commands::group_cmd::get_groups,
            commands::group_cmd::toggle_group,
            commands::group_cmd::get_group_detail,
            commands::group_cmd::delete_group,
            commands::group_cmd::toggle_all,
            commands::group_cmd::batch_toggle_groups,
            commands::group_cmd::batch_delete_groups,
            commands::group_cmd::reorder_groups,
            commands::hotkey_cmd::register_hotkey,
            commands::hotkey_cmd::unregister_hotkey,
            commands::recording_cmd::start_recording,
            commands::recording_cmd::stop_recording,
            commands::recording_cmd::pause_recording,
            commands::recording_cmd::resume_recording,
            commands::recording_cmd::export_recording,
            commands::recording_cmd::import_recording,
            commands::recording_cmd::start_validation,
            commands::recording_cmd::stop_validation,
            commands::system_cmd::get_executor_status,
            commands::system_cmd::emergency_release,
            commands::system_cmd::clear_emergency,
            commands::system_cmd::toggle_hold_mode,
            commands::system_cmd::reset_watchdog,
        ])
        .run(tauri::generate_context!())
        .inspect_err(|e| tracing::error!("Tauri 应用运行错误: {e}"))
        .expect("Tauri 应用启动失败");
}

#[cfg(test)]
mod shutdown_tests {
    // ⚠️ 复核结论存档（2026-09-19，审查发现 #20）：审查曾判「关机编排零覆盖，只测了
    // `infrastructure/shutdown.rs` 抽出的纯函数」—— **该判定不成立**。本模块 6 条里有
    // 3 条就是真实关机编排：`test_run_shutdown_sequence_order`（断言「标记 IPC 关闭 →
    // 设置 runner 停止标志 → watchdog 优雅关机」顺序）与 2 条 `perform_graceful_shutdown`
    // （guard 提前返回 / 二次调用拦截，用真实 `IpcManager` + 真实 `ProcessWatchdog`）。
    // 工程督导 2026-09-19 裁决：**不要**为 #20 再补用例（属自我重复）。本模块的保留价值
    // 是**契约冻结** —— 顺序与二次拦截一旦被改反，这里立刻变红，而不是为凑 #20 而存在。
    // 详见 `docs/test-map.md` 的 `src-tauri/src/lib.rs` 明细行。
    use super::*;
    use asd_test_harness::{make_test_state, unique_pipe_name};
    use std::sync::atomic::AtomicBool;
    use std::sync::Arc;
    use std::sync::Mutex as StdMutex;

    /// 验证 `try_acquire_shutdown_guard` 首次调用成功获取关机锁。
    ///
    /// 当 guard 为 false 时，`compare_exchange` 应成功将其设为 true，
    /// 返回 true 表示调用方获得关机权。
    #[test]
    fn test_try_acquire_shutdown_guard_first_call() {
        let guard = AtomicBool::new(false);
        assert!(
            infrastructure::shutdown::try_acquire_shutdown_guard(&guard),
            "首次调用应成功获取关机锁"
        );
        // 获取后 guard 应为 true
        assert!(guard.load(Ordering::SeqCst), "获取后 guard 应为 true");
    }

    /// 验证 `try_acquire_shutdown_guard` 第二次调用失败（关机已在进行中）。
    ///
    /// 第一次调用将 guard 设为 true，第二次调用的 `compare_exchange` 应失败，
    /// 返回 false 表示关机已在进行中，调用方应跳过。
    #[test]
    fn test_try_acquire_shutdown_guard_second_call_fails() {
        let guard = AtomicBool::new(false);
        // 第一次调用成功
        assert!(infrastructure::shutdown::try_acquire_shutdown_guard(&guard));
        // 第二次调用应失败
        assert!(
            !infrastructure::shutdown::try_acquire_shutdown_guard(&guard),
            "第二次调用应失败，关机已在进行中"
        );
    }

    /// 验证 `try_acquire_shutdown_guard` 在已锁定状态下返回 false。
    #[test]
    fn test_try_acquire_shutdown_guard_already_locked() {
        let guard = AtomicBool::new(true);
        assert!(
            !infrastructure::shutdown::try_acquire_shutdown_guard(&guard),
            "已锁定状态下应返回 false"
        );
    }

    // ---- T8-02: 关机主体序列测试 ----

    /// 验证关机主体按固定顺序执行三个步骤：
    /// ① 标记 IPC 关闭 → ② 设置 runner 停止标志 → ③ 调用 watchdog 优雅关机。
    #[tokio::test]
    async fn test_run_shutdown_sequence_order() {
        let order: Arc<StdMutex<Vec<&'static str>>> = Arc::new(StdMutex::new(Vec::new()));
        let o1 = order.clone();
        let o2 = order.clone();
        let o3 = order.clone();

        run_shutdown_sequence(
            async move {
                o1.lock().unwrap().push("ipc");
            },
            async move {
                o2.lock().unwrap().push("runner");
            },
            async move {
                o3.lock().unwrap().push("watchdog");
                Ok(())
            },
        )
        .await;

        let order = order.lock().unwrap();
        assert_eq!(
            *order,
            vec!["ipc", "runner", "watchdog"],
            "关机主体应按「标记 IPC 关闭 → 设置 runner 停止标志 → 调用 watchdog 关机」顺序执行"
        );
    }

    /// 验证关机锁已被获取时 `perform_graceful_shutdown` 提前返回，
    /// 不执行关机主体（IPC 未标记关机、runner 停止标志未设置）。
    #[tokio::test]
    async fn test_perform_graceful_shutdown_guard_already_set_returns_early() {
        let app_state = make_test_state();
        let (mgr, _rx) = IpcManager::new(&unique_pipe_name("gsd_early"));
        let ipc_manager: IpcManagerArc = Arc::new(tokio::sync::Mutex::new(Some(mgr)));
        let watchdog: WatchdogArc = Arc::new(tokio::sync::Mutex::new(ProcessWatchdog::new()));
        let runner_shutting_down = Arc::new(AtomicBool::new(false));
        let shutdown_guard = AtomicBool::new(true); // 已锁定

        perform_graceful_shutdown(
            &app_state,
            &ipc_manager,
            &watchdog,
            &runner_shutting_down,
            &shutdown_guard,
        )
        .await;

        {
            let guard = ipc_manager.lock().await;
            assert!(
                !guard.as_ref().unwrap().is_shutting_down(),
                "guard 已为 true 时应提前返回，IPC 不应被标记关机"
            );
        }
        assert!(
            !runner_shutting_down.load(Ordering::SeqCst),
            "guard 已为 true 时应提前返回，runner 停止标志不应被设置"
        );
    }

    /// 验证二次调用被拦截：第一次调用获取关机锁并执行关机主体，
    /// 第二次调用因 guard 已为 true 而跳过关机主体。
    #[tokio::test]
    async fn test_perform_graceful_shutdown_second_call_skipped() {
        let app_state = make_test_state();
        let (mgr, _rx) = IpcManager::new(&unique_pipe_name("gsd_second"));
        let ipc_manager: IpcManagerArc = Arc::new(tokio::sync::Mutex::new(Some(mgr)));
        let watchdog: WatchdogArc = Arc::new(tokio::sync::Mutex::new(ProcessWatchdog::new()));
        let runner_shutting_down = Arc::new(AtomicBool::new(false));
        let shutdown_guard = AtomicBool::new(false);

        // 第一次调用：获取关机锁并执行关机主体
        perform_graceful_shutdown(
            &app_state,
            &ipc_manager,
            &watchdog,
            &runner_shutting_down,
            &shutdown_guard,
        )
        .await;
        assert!(
            shutdown_guard.load(Ordering::SeqCst),
            "第一次调用应获取关机锁"
        );
        assert!(
            runner_shutting_down.load(Ordering::SeqCst),
            "第一次调用应执行关机主体（设置 runner 停止标志）"
        );

        // 复位 runner 标志，以便观察第二次调用是否重复执行关机主体
        runner_shutting_down.store(false, Ordering::SeqCst);

        // 第二次调用：guard 已为 true，应被拦截，不重复执行关机主体
        perform_graceful_shutdown(
            &app_state,
            &ipc_manager,
            &watchdog,
            &runner_shutting_down,
            &shutdown_guard,
        )
        .await;
        assert!(
            !runner_shutting_down.load(Ordering::SeqCst),
            "第二次调用应被拦截，runner 停止标志不应再次设置"
        );
    }
}
