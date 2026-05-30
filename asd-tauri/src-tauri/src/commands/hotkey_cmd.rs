use crate::application::state::{AppError, AppState};
use crate::domain::models::IpcCommand;
use std::sync::Arc;

#[tauri::command]
pub async fn register_hotkey(
    state: tauri::State<'_, Arc<AppState>>,
    hotkey: String,
    group_id: String,
) -> Result<(), AppError> {
    {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;

        if let Some(existing_id) = registry.get(&hotkey) {
            return Err(AppError::Validation(format!(
                "热键 '{}' 已被分组 '{}' 注册",
                hotkey, existing_id
            )));
        }

        registry.insert(hotkey.clone(), group_id.clone());
        tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
    }

    let cmd = IpcCommand::RegisterHotkey {
        hotkey,
        group_id,
    };
    state.try_send_ipc_command(&cmd).await;

    Ok(())
}

#[tauri::command]
pub async fn unregister_hotkey(
    state: tauri::State<'_, Arc<AppState>>,
    hotkey: String,
) -> Result<(), AppError> {
    let removed = {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        registry.remove(&hotkey).is_some()
    };

    if removed {
        tracing::info!("热键 '{}' 已注销", hotkey);
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey,
        };
        state.try_send_ipc_command(&cmd).await;
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "热键 '{}' 未注册",
            hotkey
        )))
    }
}
