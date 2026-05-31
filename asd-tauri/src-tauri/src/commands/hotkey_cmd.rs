use asd_application::error::AppError;
use asd_application::state::AppState;
use std::sync::Arc;

#[tauri::command]
pub async fn register_hotkey(
    state: tauri::State<'_, Arc<AppState>>,
    hotkey: String,
    group_id: String,
) -> Result<(), AppError> {
    asd_application::group_service::register_hotkey(&state, &hotkey, &group_id)
}

#[tauri::command]
pub async fn unregister_hotkey(
    state: tauri::State<'_, Arc<AppState>>,
    hotkey: String,
) -> Result<(), AppError> {
    asd_application::group_service::unregister_hotkey(&state, &hotkey)
}
