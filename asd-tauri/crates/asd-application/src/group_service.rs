use crate::error::AppError;
use crate::state::AppState;
use asd_domain::models::SkillGroup;
use asd_ipc_protocol::IpcCommand;
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

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

fn build_toggle_command(group_id: &str, active: bool, group: &SkillGroup) -> IpcCommand {
    let mode_data = serde_json::to_value(&group.mode_data)
        .ok()
        .filter(|v| !v.is_null());
    IpcCommand::ToggleGroup {
        group_id: group_id.to_string(),
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
    }
}

pub fn toggle_group(state: &AppState, group_id: &str) -> Result<GroupStatus, AppError> {
    let group = state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;
    let new_active = !group.active;
    state.set_group_active(group_id, new_active)?;

    let cmd = build_toggle_command(group_id, new_active, &group);
    state.try_send_ipc_command(&cmd);

    Ok(GroupStatus {
        id: group_id.to_string(),
        active: new_active,
    })
}

pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError> {
    state.delete_group_atomic(group_id)?;
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

    let mut errors = Vec::new();
    for (id, group) in &toggle_data {
        let cmd = build_toggle_command(id, active, group);
        state.try_send_ipc_command(&cmd);
        if let Err(e) = state.set_group_active(id, active) {
            errors.push(format!("分组 {}: {}", id, e));
        }
    }

    if errors.is_empty() {
        tracing::info!("全局切换: active={}", active);
        Ok(())
    } else {
        tracing::warn!("全局切换部分失败: active={}, 错误: {:?}", active, errors);
        Err(AppError::Internal(format!(
            "部分分组切换失败: {}",
            errors.join("; ")
        )))
    }
}

pub fn batch_toggle_groups(
    state: &AppState,
    group_ids: &[String],
    active: bool,
) -> Result<(), AppError> {
    let toggle_data: Vec<(String, SkillGroup)> = {
        let groups = state.read_groups()?;
        group_ids
            .iter()
            .filter_map(|id| groups.get(id).map(|g| (id.clone(), g.clone())))
            .collect()
    };

    let mut errors = Vec::new();
    for (id, group) in &toggle_data {
        let cmd = build_toggle_command(id, active, group);
        state.try_send_ipc_command(&cmd);
        if let Err(e) = state.set_group_active(id, active) {
            errors.push(format!("分组 {}: {}", id, e));
        }
    }

    if errors.is_empty() {
        tracing::info!("批量切换: {} 个分组, active={}", group_ids.len(), active);
        Ok(())
    } else {
        tracing::warn!(
            "批量切换部分失败: {} 个分组, active={}, 错误: {:?}",
            group_ids.len(),
            active,
            errors
        );
        Err(AppError::Internal(format!(
            "部分分组切换失败: {}",
            errors.join("; ")
        )))
    }
}

pub fn batch_delete_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    for id in group_ids {
        state.delete_group_atomic(id)?;
    }

    tracing::info!("批量删除: {} 个分组", group_ids.len());
    Ok(())
}

pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    let current_config = state.read_config()?;

    let group_ids_set: HashSet<&String> = group_ids.iter().collect();

    let mut new_settings = IndexMap::new();

    for id in group_ids {
        if let Some(setting) = current_config.group_settings.get(id) {
            new_settings.insert(id.clone(), setting.clone());
        }
    }

    for (id, setting) in &current_config.group_settings {
        if !group_ids_set.contains(id) {
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
    if state.is_hotkey_registered(hotkey)? {
        let existing = state.get_hotkey_group(hotkey)?.unwrap_or_default();
        return Err(AppError::Validation(format!(
            "热键 '{}' 已被分组 '{}' 注册",
            hotkey, existing
        )));
    }

    state.register_hotkey(hotkey, group_id)?;
    tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);

    let cmd = IpcCommand::RegisterHotkey {
        hotkey: hotkey.to_string(),
        group_id: group_id.to_string(),
    };
    state.try_send_ipc_command(&cmd);

    Ok(())
}

pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError> {
    let removed = state.unregister_hotkey(hotkey)?;

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
