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
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }

    let (new_active, group) = state.toggle_group_active(group_id)?;

    // 激活时向 AHK 注册热键，停用时注销热键
    if new_active {
        state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
            hotkey: group.hotkey.clone(),
            group_id: group_id.to_string(),
        });
    } else {
        state.try_send_ipc_command(&IpcCommand::UnregisterHotkey {
            hotkey: group.hotkey.clone(),
        });
    }

    let cmd = build_toggle_command(group_id, new_active, &group);
    if let Err(e) = state.send_ipc_command(&cmd) {
        tracing::warn!("IPC 发送切换命令失败，回滚分组 {} 状态: {e}", group_id);
        // 已知设计权衡：set_group_active 会发射 status_update 事件，
        // 导致前端短暂闪烁（先 new_active 后 !new_active），但仅在 IPC 失败时触发
        let _ = state.set_group_active(group_id, !new_active);
        // 先发送 ToggleGroup 回滚命令，再调整热键注册。
        //
        // # 回滚路径 IPC 命令顺序权衡
        //
        // 正常路径顺序：热键注册/注销 -> ToggleGroup
        // 回滚路径顺序：ToggleGroup -> 热键注册/注销（与正常路径相反）
        //
        // 选择回滚路径先发 ToggleGroup 的原因：
        // - 停用回滚（重新激活）：先 ToggleGroup(true) 让 AHK 停止执行，
        //   再 RegisterHotkey 恢复热键，避免 AHK 在热键已注册但未激活时收到热键事件
        // - 激活回滚（重新停用）：先 ToggleGroup(false) 停止 AHK 执行，
        //   再 UnregisterHotkey 注销热键，避免 AHK 在执行中热键被注销
        //
        // 权衡：停用回滚路径中，AHK 收到 ToggleGroup(true) 后短暂开始执行按键序列，
        // 直到 UnregisterHotkey 注销热键。此窗口极短（同一管道中顺序发送），
        // 且 IPC 失败本身就是罕见事件，影响可接受。
        let rollback_cmd = build_toggle_command(group_id, !new_active, &group);
        state.try_send_ipc_command(&rollback_cmd);
        // 回滚热键注册状态
        if !new_active {
            state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                hotkey: group.hotkey.clone(),
                group_id: group_id.to_string(),
            });
        } else {
            state.try_send_ipc_command(&IpcCommand::UnregisterHotkey {
                hotkey: group.hotkey.clone(),
            });
        }
        return Err(e);
    }

    Ok(GroupStatus {
        id: group_id.to_string(),
        active: new_active,
    })
}

pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError> {
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }

    state.delete_group_atomic(group_id)?;
    Ok(())
}

fn batch_toggle_impl(
    state: &AppState,
    toggle_data: &[(String, SkillGroup)],
    active: bool,
    log_label: &str,
) -> BatchToggleResult {
    let mut succeeded = Vec::new();
    let mut state_errors = Vec::new();
    let mut ipc_rolled_back = Vec::new();
    for (id, _stale_group) in toggle_data {
        if let Err(e) = state.set_group_active(id, active) {
            state_errors.push((id.clone(), e.to_string()));
            continue;
        }
        // 使用当前分组数据而非快照，避免并发 register_hotkey 导致热键不一致
        let current_group = match state.get_group(id) {
            Some(g) => g,
            None => {
                state_errors.push((id.clone(), "分组已删除".to_string()));
                continue;
            }
        };
        // 激活时向 AHK 注册热键，停用时注销热键
        if active {
            state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                hotkey: current_group.hotkey.clone(),
                group_id: id.clone(),
            });
        } else {
            state.try_send_ipc_command(&IpcCommand::UnregisterHotkey {
                hotkey: current_group.hotkey.clone(),
            });
        }
        let cmd = build_toggle_command(id, active, &current_group);
        if let Err(e) = state.send_ipc_command(&cmd) {
            // 已知设计权衡：set_group_active 会发射 status_update 事件，
            // 导致前端短暂闪烁（先 active 后 !active），但仅在 IPC 失败时触发。
            // 与 toggle_group 的回滚逻辑一致（见 L-61-03/L-64-02）。
            tracing::warn!("IPC 发送切换命令失败，回滚分组 {} 状态: {e}", id);
            let _ = state.set_group_active(id, !active);
            // 先发送 ToggleGroup 回滚命令，再调整热键注册
            let rollback_cmd = build_toggle_command(id, !active, &current_group);
            state.try_send_ipc_command(&rollback_cmd);
            // 回滚热键注册状态
            if !active {
                state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                    hotkey: current_group.hotkey.clone(),
                    group_id: id.clone(),
                });
            } else {
                state.try_send_ipc_command(&IpcCommand::UnregisterHotkey {
                    hotkey: current_group.hotkey.clone(),
                });
            }
            ipc_rolled_back.push(id.clone());
        } else {
            succeeded.push(id.clone());
        }
    }

    if state_errors.is_empty() && ipc_rolled_back.is_empty() {
        tracing::info!("{}: active={}", log_label, active);
    } else {
        tracing::warn!(
            "{}部分失败: active={}, 状态失败={}, IPC回滚={}",
            log_label,
            active,
            state_errors
                .iter()
                .map(|(id, _)| id.as_str())
                .collect::<Vec<_>>()
                .join(","),
            ipc_rolled_back.join(",")
        );
    }

    BatchToggleResult {
        succeeded,
        state_errors,
        ipc_rolled_back,
        not_found: Vec::new(),
        skipped: 0,
    }
}

pub fn toggle_all(state: &AppState, active: bool) -> Result<BatchToggleResult, AppError> {
    let (toggle_data, skipped) = {
        let groups = state.read_groups()?;
        let total = groups.len();
        let toggle_data: Vec<(String, SkillGroup)> = groups
            .iter()
            .filter(|(_, group)| group.active != active)
            .map(|(id, group)| (id.clone(), group.clone()))
            .collect();
        let skipped = total - toggle_data.len();
        (toggle_data, skipped)
    };
    let mut result = batch_toggle_impl(state, &toggle_data, active, "全局切换");
    result.skipped = skipped;
    Ok(result)
}

pub fn batch_toggle_groups(
    state: &AppState,
    group_ids: &[String],
    active: bool,
) -> Result<BatchToggleResult, AppError> {
    if group_ids.is_empty() {
        return Err(AppError::Validation("分组 ID 列表不能为空".to_string()));
    }

    let groups = state.read_groups()?;
    let mut toggle_data = Vec::new();
    let mut not_found = Vec::new();
    for id in group_ids {
        if let Some(g) = groups.get(id) {
            toggle_data.push((id.clone(), g.clone()));
        } else {
            not_found.push(id.clone());
        }
    }
    let mut result = batch_toggle_impl(
        state,
        &toggle_data,
        active,
        &format!("批量切换({} 个分组)", group_ids.len()),
    );
    result.not_found = not_found;
    Ok(result)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchToggleResult {
    pub succeeded: Vec<String>,
    pub state_errors: Vec<(String, String)>,
    pub ipc_rolled_back: Vec<String>,
    #[serde(rename = "notFound")]
    pub not_found: Vec<String>,
    #[serde(default)]
    pub skipped: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchDeleteResult {
    pub deleted: Vec<String>,
    pub failed: Vec<(String, String)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReorderResult {
    #[serde(rename = "reorderedCount")]
    pub reordered_count: usize,
    #[serde(rename = "appendedGroups")]
    pub appended_groups: Vec<String>,
}

pub fn batch_delete_groups(
    state: &AppState,
    group_ids: &[String],
) -> Result<BatchDeleteResult, AppError> {
    if group_ids.is_empty() {
        return Err(AppError::Validation("分组 ID 列表不能为空".to_string()));
    }

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
        tracing::warn!("批量删除: {} 成功, {} 失败", deleted.len(), failed.len());
    }

    Ok(BatchDeleteResult { deleted, failed })
}

/// 重排分组顺序。
///
/// # TOCTOU 注意
///
/// 调用方在读取配置（`read_config`）和调用 `save_config_atomic` 之间，
/// 配置可能已被其他线程修改（如添加/删除分组、修改热键）。
/// 此方法基于读取时的配置构建排序，可能覆盖并发修改的结果。
/// 实际场景中排序操作极少与修改操作同时发生，风险较低。
pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<ReorderResult, AppError> {
    if group_ids.is_empty() {
        return Err(AppError::Validation("分组 ID 列表不能为空".to_string()));
    }

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
    let missing_from_input: Vec<String> = existing_ids
        .difference(&group_ids_set)
        .map(|s| (*s).clone())
        .collect();
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

    state.save_config_atomic(new_config).map_err(|e| {
        if let AppError::Config(msg) = &e {
            if msg.contains("保存配置到磁盘失败") {
                tracing::warn!("reorder_groups: 配置在排序期间被修改或保存失败，请重试: {e}");
            }
        }
        e
    })?;

    tracing::info!("分组排序已更新: {} 个分组", group_ids.len());
    Ok(ReorderResult {
        reordered_count: group_ids.len(),
        appended_groups: missing_from_input,
    })
}

/// 注册热键到指定分组。
///
/// # 活跃 vs 非活跃分组
///
/// - 活跃分组：更新配置 + active_hotkeys + 发送 IPC 命令到 AHK
/// - 非活跃分组：仅更新配置，激活时自动注册
///
/// # TOCTOU 权衡
///
/// `set_group_hotkey`（更新 config_state）和 `swap_hotkey`（更新 active_hotkeys）
/// 使用不同的 RwLock，两者之间存在极短的 TOCTOU 窗口（微秒级），期间
/// config_state 中的热键已更新但 active_hotkeys 尚未同步。这与 `set_group_active`
/// 的 TOCTOU 权衡一致（见 state.rs 文档）。
///
/// 此外，`is_active` 在第 400 行读取后到第 409 行使用之间存在时间窗口，
/// 期间分组可能被并发 `toggle_group` 激活或停用。若分组在读取后被激活，
/// 本函数会按非活跃分组处理（仅更新配置），但该分组实际上已是活跃状态，
/// 导致 active_hotkeys 与 config_state 不一致。此不一致会在下次
/// `toggle_group` 或 `sync_config_changes_to_ahk` 时自动修复。
/// 合并 `is_active` 和 `original_hotkey` 为单次 `get_group` 读取已将窗口
/// 最小化，但无法完全消除跨锁 TOCTOU。
pub fn register_hotkey(state: &AppState, hotkey: &str, group_id: &str) -> Result<(), AppError> {
    if hotkey.trim().is_empty() {
        return Err(AppError::Validation("热键不能为空".to_string()));
    }
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }

    // 读取分组状态（活跃/非活跃）和原始热键，合并为单次读取避免 TOCTOU 竞态
    let (is_active, original_hotkey) = state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))
        .map(|g| (g.active, g.hotkey.clone()))?;

    // 先更新配置状态（"先状态后IPC"模式），失败时无需回滚 IPC
    state.set_group_hotkey(group_id, hotkey)?;

    // 非活跃分组：仅更新配置，不修改 active_hotkeys 也不发送 IPC
    // 下次 toggle_group 激活时会自动注册热键到 AHK 和 active_hotkeys
    if !is_active {
        tracing::info!(
            "非活跃分组 '{}' 热键已更新为 '{}'（配置层面），激活时将注册到 AHK",
            group_id,
            hotkey
        );
        // 通知前端热键已变更，避免 UI 显示旧值
        state.emit_event(
            "hotkey_updated",
            serde_json::json!({
                "groupId": group_id,
                "hotkey": hotkey,
            }),
        );
        return Ok(());
    }

    // 活跃分组：同步更新 active_hotkeys 并发送 IPC 命令到 AHK
    let old_hotkey = state.swap_hotkey(hotkey, group_id).inspect_err(|_e| {
        // swap_hotkey 失败（热键冲突），回滚 set_group_hotkey
        if let Err(rollback_err) = state.set_group_hotkey(group_id, &original_hotkey) {
            tracing::warn!(
                "register_hotkey 回滚 set_group_hotkey 失败: 分组 '{}' 热键无法恢复为 '{}' (原因: {}), config_state 可能不一致",
                group_id, original_hotkey, rollback_err
            );
        }
    })?;

    if let Some(ref old) = old_hotkey {
        if old != hotkey {
            tracing::info!("分组 '{}' 已有旧热键 '{}'，先注销", group_id, old);
            let unreg_cmd = IpcCommand::UnregisterHotkey {
                hotkey: old.clone(),
            };
            if let Err(e) = state.send_ipc_command(&unreg_cmd) {
                // IPC 注销旧热键失败，回滚 swap_hotkey 和 set_group_hotkey
                if let Err(rollback_err) = state.swap_hotkey(old, group_id) {
                    tracing::warn!(
                        "register_hotkey 回滚失败: 旧热键 '{}' 无法恢复 (原因: {}), active_hotkeys 可能不一致",
                        old, rollback_err
                    );
                    // 通知前端热键状态不一致，用户可手动刷新或重新注册
                    state.emit_event(
                        "hotkey_conflict",
                        serde_json::json!({
                            "groupId": group_id,
                            "hotkey": old,
                            "reason": format!("回滚失败: {}", rollback_err),
                        }),
                    );
                }
                if let Err(rollback_err) = state.set_group_hotkey(group_id, &original_hotkey) {
                    tracing::warn!(
                        "register_hotkey 回滚 set_group_hotkey 失败: 分组 '{}' 热键无法恢复为 '{}' (原因: {}), config_state 可能不一致",
                        group_id, original_hotkey, rollback_err
                    );
                }
                return Err(e);
            }
        }
    }

    let cmd = IpcCommand::RegisterHotkey {
        hotkey: hotkey.to_string(),
        group_id: group_id.to_string(),
    };
    if let Err(e) = state.send_ipc_command(&cmd) {
        // IPC 注册新热键失败，回滚 swap_hotkey 和 set_group_hotkey
        if let Some(ref old) = old_hotkey {
            if old != hotkey {
                if let Err(rollback_err) = state.swap_hotkey(old, group_id) {
                    tracing::warn!(
                        "register_hotkey 回滚失败: 旧热键 '{}' 无法恢复 (原因: {}), active_hotkeys 可能不一致",
                        old, rollback_err
                    );
                    // 通知前端热键状态不一致，用户可手动刷新或重新注册
                    state.emit_event(
                        "hotkey_conflict",
                        serde_json::json!({
                            "groupId": group_id,
                            "hotkey": old,
                            "reason": format!("回滚失败: {}", rollback_err),
                        }),
                    );
                }
                // 向 AHK 重新注册旧热键，恢复 AHK 侧热键监听
                state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                    hotkey: old.clone(),
                    group_id: group_id.to_string(),
                });
            }
        } else {
            let _ = state.unregister_hotkey(hotkey);
        }
        if let Err(rollback_err) = state.set_group_hotkey(group_id, &original_hotkey) {
            tracing::warn!(
                "register_hotkey 回滚 set_group_hotkey 失败: 分组 '{}' 热键无法恢复为 '{}' (原因: {}), config_state 可能不一致",
                group_id, original_hotkey, rollback_err
            );
        }
        return Err(e);
    }

    tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
    Ok(())
}

pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError> {
    if hotkey.trim().is_empty() {
        return Err(AppError::Validation("热键不能为空".to_string()));
    }

    let group_id = state.unregister_hotkey_return_group(hotkey)?;

    if let Some(gid) = group_id {
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey: hotkey.to_string(),
        };
        if let Err(e) = state.send_ipc_command(&cmd) {
            let _ = state.register_hotkey(hotkey, &gid);
            return Err(e);
        }
        // 同步将分组设为非活跃，避免 AHK 重连后分组被启用但热键丢失
        // 同时通知 AHK 停止按键执行，否则 AHK 侧仍会继续发送按键
        if let Some(group) = state.get_group(&gid) {
            if group.active {
                let toggle_cmd = build_toggle_command(&gid, false, &group);
                state.try_send_ipc_command(&toggle_cmd);
                let _ = state.set_group_active(&gid, false);
            }
        }
        tracing::info!("热键 '{}' 已注销 (原分组: {})", hotkey, gid);
        Ok(())
    } else {
        Err(AppError::Validation(format!("热键 '{}' 未注册", hotkey)))
    }
}
