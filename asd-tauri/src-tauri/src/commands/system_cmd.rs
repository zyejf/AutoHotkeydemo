use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::WatchdogStateEnum;
use asd_ipc_protocol::IpcCommand;
use std::sync::atomic::Ordering;
use std::sync::Arc;

#[tauri::command]
pub fn get_executor_status(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<WatchdogStateEnum, AppError> {
    let ws = state.watchdog_state.read();
    Ok(ws.status.clone())
}

#[tauri::command]
pub async fn emergency_release(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    state.set_emergency_mode(true);
    state.try_send_ipc_command(&IpcCommand::EmergencyRelease);
    tracing::warn!("紧急释放已激活");
    Ok(())
}

#[tauri::command]
pub async fn clear_emergency(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    state.set_emergency_mode(false);
    tracing::info!("紧急释放模式已清除");
    Ok(())
}

#[tauri::command]
pub async fn toggle_hold_mode(state: tauri::State<'_, Arc<AppState>>) -> Result<bool, AppError> {
    let old_value = state.hold_mode_enabled.fetch_xor(true, Ordering::SeqCst);
    let new_value = !old_value;

    if let Err(e) = state.send_ipc_command(&IpcCommand::HoldModeToggle { enabled: new_value }) {
        state.hold_mode_enabled.fetch_xor(true, Ordering::SeqCst);
        return Err(e);
    }

    tracing::info!("长按模式已{}", if new_value { "开启" } else { "关闭" });
    Ok(new_value)
}

#[tauri::command]
pub async fn reset_watchdog(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    state.reset_watchdog()?;
    tracing::info!("看门狗已重置，将尝试重新启动子进程");
    Ok(())
}
