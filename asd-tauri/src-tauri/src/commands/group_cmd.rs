use crate::application::state::{AppError, AppState};
use crate::domain::models::IpcCommand;
use crate::domain::models::SkillGroup;
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::config::*;

    fn make_skill_group() -> SkillGroup {
        SkillGroup {
            id: "1".to_string(),
            name: "测试组".to_string(),
            hotkey: "F1".to_string(),
            active: true,
            mode: "periodic".to_string(),
            key_press_duration: 10,
            hold_keys: Some(vec!["Shift".to_string()]),
            hold_mode: Some("continuous".to_string()),
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        }
    }

    #[test]
    fn test_group_summary_from_skill_group() {
        let group = make_skill_group();
        let summary = GroupSummary::from(&group);

        assert_eq!(summary.id, "1");
        assert_eq!(summary.name, "测试组");
        assert_eq!(summary.hotkey, "F1");
        assert_eq!(summary.mode, "periodic");
        assert!(summary.active);
    }

    #[test]
    fn test_group_summary_from_inactive_group() {
        let mut group = make_skill_group();
        group.active = false;
        let summary = GroupSummary::from(&group);
        assert!(!summary.active);
    }

    #[test]
    fn test_group_summary_serialization() {
        let group = make_skill_group();
        let summary = GroupSummary::from(&group);
        let json = serde_json::to_string(&summary).unwrap();
        let decoded: GroupSummary = serde_json::from_str(&json).unwrap();

        assert_eq!(decoded.id, "1");
        assert_eq!(decoded.name, "测试组");
        assert_eq!(decoded.hotkey, "F1");
        assert_eq!(decoded.mode, "periodic");
        assert!(decoded.active);
    }

    #[test]
    fn test_group_status_serialization() {
        let status = GroupStatus {
            id: "2".to_string(),
            active: false,
        };
        let json = serde_json::to_string(&status).unwrap();
        let decoded: GroupStatus = serde_json::from_str(&json).unwrap();

        assert_eq!(decoded.id, "2");
        assert!(!decoded.active);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupStatus {
    pub id: String,
    pub active: bool,
}

#[tauri::command]
pub fn get_groups(state: tauri::State<'_, Arc<AppState>>) -> Result<Vec<GroupSummary>, AppError> {
    let groups = state.read_groups()?;
    Ok(groups.values().map(GroupSummary::from).collect())
}

#[tauri::command]
pub async fn toggle_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<GroupStatus, AppError> {
    let group = state
        .get_group(&group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.clone()))?;
    let new_active = !group.active;
    state.set_group_active(&group_id, new_active)?;

    // C-1 修复: 发送完整模式配置，AHK 侧需要知道按什么键、用什么模式
    let mode_data_json = serde_json::to_value(&group.mode_data)
        .ok()
        .filter(|v| !v.is_null());

    let cmd = IpcCommand::ToggleGroup {
        group_id: group_id.clone(),
        active: new_active,
        mode: Some(group.mode.clone()),
        key_press_duration: if group.key_press_duration > 0 { Some(group.key_press_duration) } else { None },
        hold_keys: group.hold_keys.clone(),
        hold_mode: group.hold_mode.clone(),
        mode_data: mode_data_json,
    };
    state.try_send_ipc_command(&cmd).await;

    Ok(GroupStatus {
        id: group_id,
        active: new_active,
    })
}

#[tauri::command]
pub fn get_group_detail(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<SkillGroup, AppError> {
    state
        .get_group(&group_id)
        .ok_or(AppError::GroupNotFound(group_id))
}

#[tauri::command]
pub async fn delete_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<(), AppError> {
    // 1. 如果分组是活跃的，先发送 IPC 命令停止
    let is_active = {
        let groups = state.read_groups()?;
        groups.get(&group_id).map(|g| g.active).unwrap_or(false)
    };

    if is_active {
        let cmd = IpcCommand::ToggleGroup {
            group_id: group_id.clone(),
            active: false,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        state.try_send_ipc_command(&cmd).await;
    }

    // 2. 读取当前配置，移除该分组，原子保存
    let current_config = state.read_config()?;

    let mut new_config = current_config;
    new_config.group_settings.shift_remove(&group_id);

    state.save_config_atomic(new_config)?;

    // 3. 如果分组是活跃的，从 active_hotkeys 中移除
    if is_active {
        let mut registry = state.active_hotkeys.write().map_err(|e| AppError::Internal(e.to_string()))?;
        registry.remove(&group_id);
    }

    tracing::info!("已删除分组: {}", group_id);
    Ok(())
}

#[tauri::command]
pub async fn toggle_all(
    state: tauri::State<'_, Arc<AppState>>,
    active: bool,
) -> Result<(), AppError> {
    // 收集需要切换的分组数据，避免跨 await 持有锁
    let toggle_data: Vec<(String, SkillGroup)> = {
        let groups = state.read_groups()?;
        groups.iter()
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
            key_press_duration: if group.key_press_duration > 0 { Some(group.key_press_duration) } else { None },
            hold_keys: group.hold_keys.clone(),
            hold_mode: group.hold_mode.clone(),
            mode_data,
        };
        state.try_send_ipc_command(&cmd).await;
        state.set_group_active(id, active)?;
    }

    tracing::info!("全局切换: active={}", active);
    Ok(())
}

#[tauri::command]
pub async fn batch_toggle_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
    active: bool,
) -> Result<(), AppError> {
    for id in &group_ids {
        // 收集分组数据，避免跨 await 持有锁
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
                key_press_duration: if group.key_press_duration > 0 { Some(group.key_press_duration) } else { None },
                hold_keys: group.hold_keys.clone(),
                hold_mode: group.hold_mode.clone(),
                mode_data,
            };
            state.try_send_ipc_command(&cmd).await;
            state.set_group_active(id, active)?;
        }
    }

    tracing::info!("批量切换: {} 个分组, active={}", group_ids.len(), active);
    Ok(())
}

#[tauri::command]
pub async fn batch_delete_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<(), AppError> {
    // 1. 停止所有活跃的待删除分组
    for id in &group_ids {
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
            state.try_send_ipc_command(&cmd).await;
        }
    }

    // 2. 收集哪些分组是活跃的（用于后续清理 active_hotkeys）
    let active_ids: Vec<String> = {
        let groups = state.read_groups()?;
        group_ids.iter()
            .filter(|id| groups.get(*id).map(|g| g.active).unwrap_or(false))
            .cloned()
            .collect()
    };

    // 3. 读取当前配置，批量移除，原子保存
    let current_config = state.read_config()?;

    let mut new_config = current_config;
    for id in &group_ids {
        new_config.group_settings.shift_remove(id);
    }

    state.save_config_atomic(new_config)?;

    // 4. 从 active_hotkeys 中移除已删除的活跃分组
    if !active_ids.is_empty() {
        let mut registry = state.active_hotkeys.write().map_err(|e| AppError::Internal(e.to_string()))?;
        for id in &active_ids {
            registry.remove(id);
        }
    }

    tracing::info!("批量删除: {} 个分组", group_ids.len());
    Ok(())
}

#[tauri::command]
pub fn reorder_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<(), AppError> {
    let current_config = state.read_config()?;

    // 按 group_ids 的顺序重建 group_settings（IndexMap 保序）
    let mut new_settings = IndexMap::new();

    // 先添加 group_ids 中指定的分组（按指定顺序）
    for id in &group_ids {
        if let Some(setting) = current_config.group_settings.get(id) {
            new_settings.insert(id.clone(), setting.clone());
        }
    }

    // 再添加不在 group_ids 中的分组（保持原顺序）
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
