pub mod application;
pub mod commands;
pub mod domain;
pub mod infrastructure;

#[cfg(test)]
mod tests;

use application::state::AppState;
use domain::config::Config;
use domain::models::{IpcCommand, IpcMessage, SkillGroup};
use infrastructure::ipc::{IpcManager, IpcOutboundReceiver};
use infrastructure::watchdog::{ProcessWatchdog, WatchdogRunner, WatchdogStateEnum};
use std::sync::Arc;
use tauri::Emitter;
use tauri::Manager;
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::{TrayIconBuilder, MouseButton, MouseButtonState, TrayIconEvent};
use tauri_plugin_global_shortcut::GlobalShortcutExt;

/// 执行优雅关机：通过三阶段方式关闭 AHK 子进程
async fn perform_graceful_shutdown(app_state: &Arc<AppState>) {
    // 标记正在关机，抑制 pipe_broken 回调，避免 AHK 退出后误触发 Recovering 状态
    {
        let ipc_mgr = app_state.ipc_manager.lock().await;
        if let Some(ref mgr) = *ipc_mgr {
            mgr.mark_shutting_down();
        }
    }

    let mut wd = app_state.watchdog.lock().await;
    if let Err(e) = wd.graceful_shutdown().await {
        tracing::error!("优雅关机失败: {e}");
    }
}

fn spawn_ipc_listener(mut rx: IpcOutboundReceiver, _app_state: Arc<AppState>, app_handle: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match msg.r#type.as_str() {
                "hotkey" => {
                    if let Some(keys) = &msg.keys {
                        if let Some(hotkey) = keys.first() {
                            tracing::info!("收到热键事件: {hotkey}");
                            let _ = app_handle.emit("hotkey_event", serde_json::json!({
                                "hotkey": hotkey,
                                "keys": keys,
                            }));
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

fn spawn_ipc_accept_loop(app_state: Arc<AppState>) {
    let state_clone = app_state.clone();
    tauri::async_runtime::spawn(async move {
        let listener = match infrastructure::ipc::create_listener("asd_ipc") {
            Ok(l) => l,
            Err(e) => {
                tracing::error!("创建 IPC 监听器失败: {e}");
                return;
            }
        };

        let ipc_manager = {
            let guard = state_clone.ipc_manager.lock().await;
            guard.clone()
        };

        if let Some(mgr) = ipc_manager {
            mgr.accept_loop(&listener).await;
        } else {
            tracing::error!("IPC 管理器未初始化，无法启动 accept 循环");
        }
    });
}

fn spawn_heartbeat_ping(app_state: Arc<AppState>) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(1));
        loop {
            interval.tick().await;
            let ipc_manager = {
                let guard = app_state.ipc_manager.lock().await;
                guard.clone()
            };
            if let Some(mgr) = ipc_manager {
                let seq = mgr.next_seq();
                let msg = IpcMessage::ping(seq);
                if let Err(e) = mgr.send(&msg).await {
                    tracing::warn!("心跳 ping 发送失败: {e}");
                }
            }
        }
    });
}

fn spawn_watchdog(app_state: Arc<AppState>) {
    tauri::async_runtime::spawn(async move {
        let runner = WatchdogRunner::from_arc(app_state.watchdog.clone());

        let state_clone = app_state.clone();
        let wd_clone = app_state.watchdog.clone();
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

fn setup_ipc_callbacks(app_state: &Arc<AppState>, ipc_manager: &IpcManager) {
    let watchdog_for_heartbeat = app_state.watchdog.clone();
    ipc_manager.set_heartbeat_callback(Arc::new(move || {
        let wd = watchdog_for_heartbeat.clone();
        tauri::async_runtime::spawn(async move {
            let mut guard = wd.lock().await;
            guard.notify_heartbeat();
        });
    }));

    let watchdog_for_pipe_broken = app_state.watchdog.clone();
    let app_state_for_recover = app_state.clone();
    ipc_manager.set_pipe_broken_callback(Arc::new(move || {
        let wd = watchdog_for_pipe_broken.clone();
        let state = app_state_for_recover.clone();
        tauri::async_runtime::spawn(async move {
            let mut guard = wd.lock().await;
            guard.set_state(WatchdogStateEnum::Recovering);
            drop(guard);
            // 状态恢复：重新下发所有活跃的热键注册和分组配置
            // 注意：必须先收集数据再跨 await，因为 RwLockReadGuard 不是 Send
            let active_groups_data: Vec<(String, SkillGroup)> = {
                let groups = state.read_groups().ok();
                groups.map(|g| {
                    g.iter()
                        .filter(|(_, group)| group.active)
                        .map(|(id, group)| (id.clone(), group.clone()))
                        .collect()
                }).unwrap_or_default()
            };
            for (id, group) in active_groups_data {
                // C-1 修复: 恢复时也发送完整模式配置
                let mode_data_json = serde_json::to_value(&group.mode_data)
                    .ok()
                    .filter(|v| !v.is_null());
                let cmd = IpcCommand::ToggleGroup {
                    group_id: id,
                    active: true,
                    mode: Some(group.mode.clone()),
                    key_press_duration: if group.key_press_duration > 0 { Some(group.key_press_duration) } else { None },
                    hold_keys: group.hold_keys.clone(),
                    hold_mode: group.hold_mode.clone(),
                    mode_data: mode_data_json,
                };
                state.try_send_ipc_command(&cmd).await;
            }
            let active_hotkey_list: Vec<(String, String)> = {
                let hotkeys = state.active_hotkeys.read().ok();
                hotkeys.map(|h| {
                    h.iter().map(|(id, hotkey)| (id.clone(), hotkey.clone())).collect()
                }).unwrap_or_default()
            };
            for (id, hotkey) in active_hotkey_list {
                let cmd = IpcCommand::RegisterHotkey {
                    hotkey,
                    group_id: id,
                };
                state.try_send_ipc_command(&cmd).await;
            }
        });
    }));

    // 设置 send_shutdown 回调：Phase 1 通过 IPC 发送 shutdown 消息
    let app_state_for_shutdown = app_state.clone();
    {
        // 使用 block_in_place 避免 blocking_lock 在 tokio 异步上下文中导致死锁
        let mut guard = tokio::task::block_in_place(|| app_state.watchdog.blocking_lock());
        guard.set_send_shutdown(Arc::new(move || {
            let state = app_state_for_shutdown.clone();
            tauri::async_runtime::spawn(async move {
                let ipc_manager = {
                    let guard = state.ipc_manager.lock().await;
                    guard.clone()
                };
                if let Some(mgr) = ipc_manager {
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

            let config_path = app.path().app_data_dir()
                .expect("无法获取 app_data_dir")
                .join("config.json");
            let config = Config::load_from_path(&config_path).unwrap_or_else(|e| {
                tracing::warn!("加载配置失败: {e}，使用默认配置");
                Config::default()
            });
            let (ipc_manager, outbound_rx) = IpcManager::new("asd_ipc");

            let watchdog = Arc::new(tokio::sync::Mutex::new(ProcessWatchdog::new()));
            let mut app_state = Arc::new(AppState::new(config, ipc_manager.outbound_sender(), watchdog));

            // 设置 AppHandle 和 config_path（必须在 app.manage() 之前，因为 Arc::get_mut 要求独占引用）
            {
                let state_ref = Arc::get_mut(&mut app_state).expect("AppState should be uniquely held during setup");
                state_ref.set_app_handle(app.handle().clone());
                state_ref.set_config_path(config_path);
            }

            setup_ipc_callbacks(&app_state, &ipc_manager);

            {
                // 使用 block_in_place 避免 blocking_lock 在 tokio 异步上下文中导致死锁
                let mut ipc_mgr = tokio::task::block_in_place(|| app_state.ipc_manager.blocking_lock());
                *ipc_mgr = Some(ipc_manager);
            }

            spawn_ipc_listener(outbound_rx, app_state.clone(), app.handle().clone());
            spawn_ipc_accept_loop(app_state.clone());

            // 启动 AHK 子进程
            // 必须在 spawn_ipc_accept_loop 之后调用，因为 AHK 子进程启动后会立即
            // 尝试连接 Named Pipe，而 Rust 侧必须先开始监听
            {
                // 优先使用编译后的 asd_executor.exe，若不存在则降级到便携模式
                let exe_path = if let Ok(p) = app.path().resolve("ahk_executor/asd_executor.exe", tauri::path::BaseDirectory::Resource) {
                    if p.exists() {
                        tracing::info!("使用编译模式 AHK 子进程: {:?}", p);
                        p
                    } else {
                        tracing::warn!("asd_executor.exe 不存在，尝试便携模式");
                        app.path().resolve("ahk_executor/AutoHotkey64.exe", tauri::path::BaseDirectory::Resource)
                            .expect("无法解析 AutoHotkey64.exe 路径")
                    }
                } else {
                    tracing::warn!("无法解析 asd_executor.exe 路径，尝试便携模式");
                    app.path().resolve("ahk_executor/AutoHotkey64.exe", tauri::path::BaseDirectory::Resource)
                        .expect("无法解析 AutoHotkey64.exe 路径")
                };
                let exe_str = exe_path.to_string_lossy().to_string();
                // 使用 block_in_place 避免 blocking_lock 在 tokio 异步上下文中导致死锁
                let mut wd = tokio::task::block_in_place(|| app_state.watchdog.blocking_lock());
                if let Err(e) = wd.spawn_child(&exe_str) {
                    tracing::error!("启动 AHK 子进程失败: {e}");
                }
            }

            spawn_heartbeat_ping(app_state.clone());
            spawn_watchdog(app_state.clone());

            app.manage(app_state);

            let show_item = MenuItemBuilder::with_id("show", "显示主窗口").build(app)?;
            let hide_item = MenuItemBuilder::with_id("hide", "隐藏到托盘").build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "退出").build(app)?;

            let menu = MenuBuilder::new(app)
                .item(&show_item)
                .item(&hide_item)
                .separator()
                .item(&quit_item)
                .build()?;

            let _tray = TrayIconBuilder::new()
                .tooltip("ASD - 技能管理器")
                .icon(app.default_window_icon().unwrap().clone())
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        } = event {
                        if let Some(window) = tray.app_handle().get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .on_menu_event(|app, event| {
                    match event.id().as_ref() {
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
                            // 优雅关机：触发三阶段关闭 AHK 子进程
                            // 必须等待关机完成后再退出，否则 tauri::async_runtime::spawn 的关机任务会被取消
                            let state = app.state::<Arc<AppState>>();
                            let state_clone = state.inner().clone();
                            let handle = app.clone();
                            tauri::async_runtime::spawn(async move {
                                perform_graceful_shutdown(&state_clone).await;
                                handle.exit(0);
                            });
                        }
                        _ => {}
                    }
                })
                .menu(&menu)
                .build(app)?;

            let gs = app.global_shortcut();
            let _ = gs.register("Ctrl+Shift+A");

            // 设置窗口关闭事件处理：触发优雅关机
            if let Some(window) = app.get_webview_window("main") {
                let state_for_close = app.state::<Arc<AppState>>().inner().clone();
                let app_handle_for_close = app.handle().clone();
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let state = state_for_close.clone();
                        let handle = app_handle_for_close.clone();
                        tauri::async_runtime::spawn(async move {
                            perform_graceful_shutdown(&state).await;
                            handle.exit(0);
                        });
                    }
                });
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
            commands::system_cmd::toggle_hold_mode,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
