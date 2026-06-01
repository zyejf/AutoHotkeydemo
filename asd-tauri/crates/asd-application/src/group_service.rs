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

pub fn build_toggle_command(group_id: &str, active: bool, group: &SkillGroup) -> IpcCommand {
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
    let new_active = state.toggle_group_active(group_id)?;

    let group = state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;
    let cmd = build_toggle_command(group_id, new_active, &group);
    if let Err(e) = state.send_ipc_command(&cmd) {
        tracing::warn!("IPC 发送切换命令失败，回滚分组 {} 状态: {e}", group_id);
        let _ = state.set_group_active(group_id, !new_active);
        return Err(e);
    }

    Ok(GroupStatus {
        id: group_id.to_string(),
        active: new_active,
    })
}

pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError> {
    state.delete_group_atomic(group_id)?;
    Ok(())
}

fn batch_toggle_impl(
    state: &AppState,
    toggle_data: &[(String, SkillGroup)],
    active: bool,
    log_label: &str,
) -> Result<(), AppError> {
    let mut errors = Vec::new();
    let mut rolled_back = Vec::new();
    for (id, group) in toggle_data {
        if let Err(e) = state.set_group_active(id, active) {
            errors.push(format!("分组 {}: {}", id, e));
            continue;
        }
        let cmd = build_toggle_command(id, active, group);
        if let Err(e) = state.send_ipc_command(&cmd) {
            tracing::warn!("IPC 发送切换命令失败，回滚分组 {} 状态: {e}", id);
            let _ = state.set_group_active(id, !active);
            let rollback_cmd = build_toggle_command(id, !active, group);
            state.try_send_ipc_command(&rollback_cmd);
            rolled_back.push(id.clone());
        }
    }

    if errors.is_empty() && rolled_back.is_empty() {
        tracing::info!("{}: active={}", log_label, active);
        Ok(())
    } else {
        let mut parts = Vec::new();
        if !errors.is_empty() {
            parts.push(format!("状态更新失败: {}", errors.join("; ")));
        }
        if !rolled_back.is_empty() {
            parts.push(format!("IPC 失败已回滚: {}", rolled_back.join(", ")));
        }
        tracing::warn!("{}部分失败: active={}, 问题: {:?}", log_label, active, parts);
        Err(AppError::Internal(parts.join("；")))
    }
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
    batch_toggle_impl(state, &toggle_data, active, "全局切换")
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
    batch_toggle_impl(
        state,
        &toggle_data,
        active,
        &format!("批量切换({} 个分组)", group_ids.len()),
    )
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchDeleteResult {
    pub deleted: Vec<String>,
    pub failed: Vec<(String, String)>,
}

pub fn batch_delete_groups(state: &AppState, group_ids: &[String]) -> Result<BatchDeleteResult, AppError> {
    let mut deleted = Vec::new();
    let mut failed = Vec::new();

    for id in group_ids {
        match state.delete_group_atomic(id) {
            Ok(_) => deleted.push(id.clone()),
            Err(e) => failed.push((id.clone(), e.to_string())),
        }
    }

    if failed.is_empty() {
        tracing::info!("批量删除: {} 个分组全部成功", deleted.len());
    } else {
        tracing::warn!(
            "批量删除: {} 成功, {} 失败",
            deleted.len(),
            failed.len()
        );
    }

    Ok(BatchDeleteResult { deleted, failed })
}

pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    let current_config = state.read_config()?;

    let mut seen = std::collections::HashSet::new();
    let mut not_found = Vec::new();
    let mut duplicates = Vec::new();
    for id in group_ids {
        if !current_config.group_settings.contains_key(id) {
            not_found.push(id.clone());
        }
        if !seen.insert(id) {
            duplicates.push(id.clone());
        }
    }
    if !not_found.is_empty() {
        return Err(AppError::Validation(format!(
            "分组不存在: {}",
            not_found.join(", ")
        )));
    }
    if !duplicates.is_empty() {
        return Err(AppError::Validation(format!(
            "分组 ID 重复: {}",
            duplicates.join(", ")
        )));
    }

    let group_ids_set: HashSet<&String> = group_ids.iter().collect();
    let existing_ids: HashSet<&String> = current_config.group_settings.keys().collect();
    let missing_from_input: Vec<&&String> = existing_ids.difference(&group_ids_set).collect();
    if !missing_from_input.is_empty() {
        tracing::warn!(
            "reorder_groups: 以下分组未包含在排序列表中，将追加到末尾: {:?}",
            missing_from_input
        );
    }

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
    let existing = state.register_hotkey(hotkey, group_id)?;
    if let Some(existing_group_id) = existing {
        return Err(AppError::Validation(format!(
            "热键 '{}' 已被分组 '{}' 注册",
            hotkey, existing_group_id
        )));
    }

    let cmd = IpcCommand::RegisterHotkey {
        hotkey: hotkey.to_string(),
        group_id: group_id.to_string(),
    };
    if let Err(e) = state.send_ipc_command(&cmd) {
        let _ = state.unregister_hotkey(hotkey);
        return Err(e);
    }

    tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
    Ok(())
}

pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError> {
    let group_id = state.get_hotkey_group(hotkey)?.filter(|_| {
        state.unregister_hotkey(hotkey).unwrap_or(false)
    });

    if let Some(gid) = group_id {
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey: hotkey.to_string(),
        };
        if let Err(e) = state.send_ipc_command(&cmd) {
            let _ = state.register_hotkey(hotkey, &gid);
            return Err(e);
        }
        tracing::info!("热键 '{}' 已注销", hotkey);
        Ok(())
    } else {
        Err(AppError::Validation(format!("热键 '{}' 未注册", hotkey)))
    }
}
