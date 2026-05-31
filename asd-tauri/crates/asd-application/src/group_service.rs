use crate::error::AppError;
use crate::state::AppState;
use asd_domain::models::SkillGroup;
use asd_ipc_protocol::IpcCommand;
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupSummary {
    pub id: String,
    pub name: String,
    pub hotkey: String,
    pub mode: String,
    pub active: bool,
}

impl From<&SkillGroup> for GroupSummary {
    fn from(g: &SkillGroup) -> Self {
        Self {
            id: g.id.clone(),
            name: g.name.clone(),
            hotkey: g.hotkey.clone(),
            mode: g.mode.clone(),
            active: g.active,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupStatus {
    pub id: String,
    pub active: bool,
}

pub fn toggle_group(state: &AppState, group_id: &str) -> Result<GroupStatus, AppError> {
    let group = state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;
    let new_active = !group.active;
    state.set_group_active(group_id, new_active)?;

    let mode_data_json = serde_json::to_value(&group.mode_data)
        .ok()
        .filter(|v| !v.is_null());

    let cmd = IpcCommand::ToggleGroup {
        group_id: group_id.to_string(),
        active: new_active,
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

    Ok(GroupStatus {
        id: group_id.to_string(),
        active: new_active,
    })
}

pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError> {
    let is_active = {
        let groups = state.read_groups()?;
        groups.get(group_id).map(|g| g.active).unwrap_or(false)
    };

    if is_active {
        let cmd = IpcCommand::ToggleGroup {
            group_id: group_id.to_string(),
            active: false,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        state.try_send_ipc_command(&cmd);
    }

    let current_config = state.read_config()?;
    let mut new_config = current_config;
    new_config.group_settings.shift_remove(group_id);
    state.save_config_atomic(new_config)?;

    if is_active {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        registry.remove(group_id);
    }

    tracing::info!("已删除分组: {}", group_id);
    Ok(())
}

pub fn toggle_all(state: &AppState, active: bool) -> Result<(), AppError> {
    let toggle_data: Vec<(String, SkillGroup)> = {
        let groups = state.read_groups()?;
        groups
            .iter()
            .filter(|(_, group)| group.active != active)
            .map(|(id, group)| (id.clone(), group.clone()))
            .collect()
    };

    for (id, group) in &toggle_data {
        let mode_data = serde_json::to_value(&group.mode_data)
            .ok()
            .filter(|v| !v.is_null());

        let cmd = IpcCommand::ToggleGroup {
            group_id: id.clone(),
            active,
            mode: Some(group.mode.clone()),
            key_press_duration: if group.key_press_duration > 0 {
                Some(group.key_press_duration)
            } else {
                None
            },
            hold_keys: group.hold_keys.clone(),
            hold_mode: group.hold_mode.clone(),
            mode_data,
        };
        state.try_send_ipc_command(&cmd);
        state.set_group_active(id, active)?;
    }

    tracing::info!("全局切换: active={}", active);
    Ok(())
}

pub fn batch_toggle_groups(
    state: &AppState,
    group_ids: &[String],
    active: bool,
) -> Result<(), AppError> {
    for id in group_ids {
        let group_data = {
            let groups = state.read_groups()?;
            groups.get(id).cloned()
        };

        if let Some(group) = group_data {
            let mode_data = serde_json::to_value(&group.mode_data)
                .ok()
                .filter(|v| !v.is_null());

            let cmd = IpcCommand::ToggleGroup {
                group_id: id.clone(),
                active,
                mode: Some(group.mode.clone()),
                key_press_duration: if group.key_press_duration > 0 {
                    Some(group.key_press_duration)
                } else {
                    None
                },
                hold_keys: group.hold_keys.clone(),
                hold_mode: group.hold_mode.clone(),
                mode_data,
            };
            state.try_send_ipc_command(&cmd);
            state.set_group_active(id, active)?;
        }
    }

    tracing::info!("批量切换: {} 个分组, active={}", group_ids.len(), active);
    Ok(())
}

pub fn batch_delete_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    for id in group_ids {
        let group_active = {
            let groups = state.read_groups()?;
            groups.get(id).map(|g| g.active).unwrap_or(false)
        };

        if group_active {
            let cmd = IpcCommand::ToggleGroup {
                group_id: id.clone(),
                active: false,
                mode: None,
                key_press_duration: None,
                hold_keys: None,
                hold_mode: None,
                mode_data: None,
            };
            state.try_send_ipc_command(&cmd);
        }
    }

    let active_ids: Vec<String> = {
        let groups = state.read_groups()?;
        group_ids
            .iter()
            .filter(|id| groups.get(*id).map(|g| g.active).unwrap_or(false))
            .cloned()
            .collect()
    };

    let current_config = state.read_config()?;
    let mut new_config = current_config;
    for id in group_ids {
        new_config.group_settings.shift_remove(id);
    }
    state.save_config_atomic(new_config)?;

    if !active_ids.is_empty() {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        for id in &active_ids {
            registry.remove(id);
        }
    }

    tracing::info!("批量删除: {} 个分组", group_ids.len());
    Ok(())
}

pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    let current_config = state.read_config()?;

    let mut new_settings = IndexMap::new();

    for id in group_ids {
        if let Some(setting) = current_config.group_settings.get(id) {
            new_settings.insert(id.clone(), setting.clone());
        }
    }

    for (id, setting) in &current_config.group_settings {
        if !group_ids.contains(id) {
            new_settings.insert(id.clone(), setting.clone());
        }
    }

    let mut new_config = current_config;
    new_config.group_settings = new_settings;

    state.save_config_atomic(new_config)?;

    tracing::info!("分组排序已更新: {} 个分组", group_ids.len());
    Ok(())
}

pub fn register_hotkey(state: &AppState, hotkey: &str, group_id: &str) -> Result<(), AppError> {
    {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;

        if let Some(existing_id) = registry.get(hotkey) {
            return Err(AppError::Validation(format!(
                "热键 '{}' 已被分组 '{}' 注册",
                hotkey, existing_id
            )));
        }

        registry.insert(hotkey.to_string(), group_id.to_string());
        tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
    }

    let cmd = IpcCommand::RegisterHotkey {
        hotkey: hotkey.to_string(),
        group_id: group_id.to_string(),
    };
    state.try_send_ipc_command(&cmd);

    Ok(())
}

pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError> {
    let removed = {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        registry.remove(hotkey).is_some()
    };

    if removed {
        tracing::info!("热键 '{}' 已注销", hotkey);
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey: hotkey.to_string(),
        };
        state.try_send_ipc_command(&cmd);
        Ok(())
    } else {
        Err(AppError::Validation(format!("热键 '{}' 未注册", hotkey)))
    }
}
