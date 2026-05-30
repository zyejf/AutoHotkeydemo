use crate::application::scheduler::SkillManager;
use crate::application::state::{AppError, AppState};
use crate::infrastructure::watchdog::WatchdogStateEnum;
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
    SkillManager::emergency_release(&state.ipc_manager)
        .await
        .map_err(AppError::Executor)?;
    tracing::warn!("紧急释放已激活");
    Ok(())
}

#[tauri::command]
pub async fn toggle_hold_mode(state: tauri::State<'_, Arc<AppState>>) -> Result<bool, AppError> {
    let current = state.is_hold_mode_enabled();
    let new_value = !current;
    state.set_hold_mode_enabled(new_value);

    SkillManager::hold_mode_toggle(&state.ipc_manager, new_value)
        .await
        .map_err(AppError::Executor)?;

    tracing::info!("长按模式已{}", if new_value { "开启" } else { "关闭" });
    Ok(new_value)
}
