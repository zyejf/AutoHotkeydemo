use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::WatchdogStateEnum;
use asd_ipc_protocol::IpcCommand;
use std::sync::Arc;

#[tauri::command]
pub fn get_executor_status(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<WatchdogStateEnum, AppError> {
    let ws = state
        .watchdog_state
        .read()
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(ws.status.clone())
}

#[tauri::command]
pub async fn emergency_release(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    state.set_emergency_mode(true);
    state.send_ipc_command(&IpcCommand::EmergencyRelease)?;
    tracing::warn!("紧急释放已激活");
    Ok(())
}

#[tauri::command]
pub async fn toggle_hold_mode(state: tauri::State<'_, Arc<AppState>>) -> Result<bool, AppError> {
    let current = state.is_hold_mode_enabled();
    let new_value = !current;
    state.set_hold_mode_enabled(new_value);

    state.send_ipc_command(&IpcCommand::HoldModeToggle { enabled: new_value })?;

    tracing::info!("长按模式已{}", if new_value { "开启" } else { "关闭" });
    Ok(new_value)
}
