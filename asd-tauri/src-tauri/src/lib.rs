pub mod application;
pub mod bridge;
pub mod commands;
pub mod domain;
pub mod infrastructure;

#[cfg(test)]
mod tests;

use application::state::AppState;
use asd_application::config_repository::ConfigRepository;
use asd_domain::config::{Config, WatchdogStateEnum};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use bridge::{IpcBridge, TauriEventBridge, WatchdogBridge};
use domain::models::SkillGroup;
use infrastructure::ipc::{IpcManager, IpcOutboundReceiver};
use infrastructure::watchdog::{ProcessWatchdog, WatchdogRunner};
use std::sync::Arc;
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::Emitter;
use tauri::Manager;
use tauri_plugin_global_shortcut::GlobalShortcutExt;

type IpcManagerArc = Arc<tokio::sync::Mutex<Option<IpcManager>>>;
type WatchdogArc = Arc<tokio::sync::Mutex<ProcessWatchdog>>;

async fn perform_graceful_shutdown(
    _app_state: &Arc<AppState>,
    ipc_manager: &IpcManagerArc,
    watchdog: &WatchdogArc,
) {
    {
        let ipc_mgr = ipc_manager.lock().await;
        if let Some(ref mgr) = *ipc_mgr {
            mgr.mark_shutting_down();
        }
    }

    let mut wd = watchdog.lock().await;
    if let Err(e) = wd.graceful_shutdown().await {
        tracing::error!("优雅关机失败: {e}");
    }
}

fn spawn_ipc_listener(
    mut rx: IpcOutboundReceiver,
    _app_state: Arc<AppState>,
    app_handle: tauri::AppHandle,
) {
    tauri::async_runtime::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match msg.r#type.as_str() {
                "hotkey" => {
                    if let Some(keys) = &msg.keys {
                        if let Some(hotkey) = keys.first() {
                            tracing::info!("收到热键事件: {hotkey}");
                            let _ = app_handle.emit(
                                "hotkey_event",
                                serde_json::json!({
                                    "hotkey": hotkey,
                                    "keys": keys,
                                }),
                            );
                        }
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
    });
}

fn spawn_ipc_accept_loop(ipc_manager: IpcManagerArc) {
    tauri::async_runtime::spawn(async move {
        let listener = match infrastructure::ipc::create_listener("asd_ipc") {
            Ok(l) => l,
            Err(e) => {
                tracing::error!("创建 IPC 监听器失败: {e}");
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
        loop {
            interval.tick().await;
            let mgr = {
                let guard = ipc_manager.lock().await;
                guard.clone()
            };
            if let Some(mgr) = mgr {
                let seq = mgr.next_seq();
                let msg = IpcMessage::ping(seq);
                if let Err(e) = mgr.send(&msg).await {
                    tracing::warn!("心跳 ping 发送失败: {e}");
                }
            }
        }
    });
}

fn spawn_watchdog(app_state: Arc<AppState>, watchdog: WatchdogArc) {
    tauri::async_runtime::spawn(async move {
        let runner = WatchdogRunner::from_arc(watchdog.clone());

        let state_clone = app_state.clone();
        let wd_clone = watchdog.clone();
        let mut last_status = WatchdogStateEnum::Idle;

        tauri::async_runtime::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(1));
            loop {
                interval.tick().await;
                let wd_guard = wd_clone.lock().await;
                let current = wd_guard.state().clone();
                let restart_count = wd_guard.restart_count();
                drop(wd_guard);

                if current != last_status {
                    state_clone.update_watchdog_state(current.clone(), restart_count);
                    last_status = current;
                }
            }
        });

        runner.run().await;
    });
}

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
    let app_state_for_recover = app_state.clone();
    ipc_manager.set_pipe_broken_callback(Arc::new(move || {
        let wd = watchdog_for_pipe_broken.clone();
        let state = app_state_for_recover.clone();
        tauri::async_runtime::spawn(async move {
            let mut guard = wd.lock().await;
            guard.set_state(WatchdogStateEnum::Recovering);
            drop(guard);
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
                let mode_data_json = serde_json::to_value(&group.mode_data)
                    .ok()
                    .filter(|v| !v.is_null());
                let cmd = IpcCommand::ToggleGroup {
                    group_id: id,
                    active: true,
                    mode: Some(group.mode.clone()),
                    key_press_duration: if group.key_press_duration > 0 {
                        Some(group.key_press_duration)
                    } else {
                        None
                    },
                    hold_keys: group.hold_keys.clone(),
                    hold_mode: group.hold_mode.clone(),
                    mode_data: mode_data_json,
                };
                state.try_send_ipc_command(&cmd);
            }
            let active_hotkey_list: Vec<(String, String)> =
                state.get_all_registered_hotkeys().unwrap_or_default();
            for (hotkey, group_id) in active_hotkey_list {
                let cmd = IpcCommand::RegisterHotkey { hotkey, group_id };
                state.try_send_ipc_command(&cmd);
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
) -> Arc<AppState> {
    let mut app_state = Arc::new(AppState::new(
        config,
        ipc_bridge,
        watchdog_bridge,
        event_bridge,
    ));
    {
        let state_ref =
            Arc::get_mut(&mut app_state).expect("AppState should be uniquely held during setup");
        state_ref.set_config_path(config_path);
    }
    app_state
}

fn setup_ipc_and_watchdog(
    app_state: &Arc<AppState>,
    ipc_manager_arc: &IpcManagerArc,
    watchdog: &WatchdogArc,
    outbound_rx: IpcOutboundReceiver,
    app_handle: &tauri::AppHandle,
    exe_path: &std::path::Path,
) {
    {
        let guard = tokio::task::block_in_place(|| ipc_manager_arc.blocking_lock());
        if let Some(ref mgr) = *guard {
            setup_ipc_callbacks(app_state, mgr, watchdog, ipc_manager_arc);
        }
    }

    spawn_ipc_listener(outbound_rx, app_state.clone(), app_handle.clone());
    spawn_ipc_accept_loop(ipc_manager_arc.clone());

    {
        let exe_str = exe_path.to_string_lossy().to_string();
        let mut wd = tokio::task::block_in_place(|| watchdog.blocking_lock());
        if let Err(e) = wd.spawn_child(&exe_str) {
            tracing::error!("启动 AHK 子进程失败: {e}");
        }
    }

    spawn_heartbeat_ping(ipc_manager_arc.clone());
    spawn_watchdog(app_state.clone(), watchdog.clone());
}

fn setup_tray_menu(
    app_handle: &tauri::AppHandle,
    ipc_manager_arc: &IpcManagerArc,
    watchdog: &WatchdogArc,
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
                let handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    perform_graceful_shutdown(&state_clone, &ipc_mgr, &wd).await;
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
) {
    let state_for_close = app_state.clone();
    let app_handle_for_close = app_handle.clone();
    let ipc_mgr_close = ipc_manager_arc.clone();
    let wd_close = watchdog.clone();
    window.on_window_event(move |event| {
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            let state = state_for_close.clone();
            let handle = app_handle_for_close.clone();
            let ipc_mgr = ipc_mgr_close.clone();
            let wd = wd_close.clone();
            tauri::async_runtime::spawn(async move {
                perform_graceful_shutdown(&state, &ipc_mgr, &wd).await;
                handle.exit(0);
            });
        }
    });
}

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

            let config_path = app
                .path()
                .app_data_dir()
                .map(|dir| dir.join("config.json"))
                .unwrap_or_else(|e| {
                    tracing::error!("无法获取 app_data_dir: {e}，使用当前目录");
                    std::path::PathBuf::from("config.json")
                });
            let config = ConfigRepository::load_from_file(&config_path);

            let (ipc_manager, outbound_rx) = IpcManager::new("asd_ipc");
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
            );

            let exe_path = if let Ok(p) = app.path().resolve(
                "ahk_executor/asd_executor.exe",
                tauri::path::BaseDirectory::Resource,
            ) {
                if p.exists() {
                    tracing::info!("使用编译模式 AHK 子进程: {:?}", p);
                    p
                } else {
                    tracing::warn!("asd_executor.exe 不存在，尝试便携模式");
                    app.path()
                        .resolve(
                            "ahk_executor/AutoHotkey64.exe",
                            tauri::path::BaseDirectory::Resource,
                        )
                        .unwrap_or_else(|e| {
                            tracing::error!("无法解析 AutoHotkey64.exe 路径: {e}");
                            std::path::PathBuf::from("AutoHotkey64.exe")
                        })
                }
            } else {
                tracing::warn!("无法解析 asd_executor.exe 路径，尝试便携模式");
                app.path()
                    .resolve(
                        "ahk_executor/AutoHotkey64.exe",
                        tauri::path::BaseDirectory::Resource,
                    )
                    .unwrap_or_else(|e| {
                        tracing::error!("无法解析 AutoHotkey64.exe 路径: {e}");
                        std::path::PathBuf::from("AutoHotkey64.exe")
                    })
            };

            setup_ipc_and_watchdog(
                &app_state,
                &ipc_manager_arc,
                &watchdog,
                outbound_rx,
                app.handle(),
                &exe_path,
            );

            app.manage(app_state);

            setup_tray_menu(app.handle(), &ipc_manager_arc, &watchdog)?;

            let gs = app.global_shortcut();
            let _ = gs.register("Ctrl+Shift+A");

            if let Some(window) = app.get_webview_window("main") {
                setup_window_close_handler(
                    &window,
                    app.state::<Arc<AppState>>().inner(),
                    app.handle(),
                    &ipc_manager_arc,
                    &watchdog,
                );
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::config_cmd::get_config,
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
        ])
        .run(tauri::generate_context!())
        .inspect_err(|e| tracing::error!("Tauri 应用运行错误: {e}"))
        .expect("Tauri 应用启动失败");
}
