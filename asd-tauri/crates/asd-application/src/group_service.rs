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

#[must_use]
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

/// 切换单个分组的启用状态，成功时返回切换后的状态。
///
/// # Errors
/// - `Validation`：`group_id` 为空。
/// - `GroupNotFound`：`group_id` 不存在。
/// - `Ipc`：向 AHK 发送切换命令失败。此时已尽力回滚（分组状态 + 热键注册），
///   但回滚走的是 `try_send_ipc_command`，**失败只记 `warn`**，
///   所以拿到 `Err` 时 AHK 侧不保证与内存一致。
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
        if new_active {
            state.try_send_ipc_command(&IpcCommand::UnregisterHotkey {
                hotkey: group.hotkey.clone(),
            });
        } else {
            state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                hotkey: group.hotkey.clone(),
                group_id: group_id.to_string(),
            });
        }
        return Err(e);
    }

    Ok(GroupStatus {
        id: group_id.to_string(),
        active: new_active,
    })
}

/// 删除单个分组（含它在配置与内存中的状态）。
///
/// # Errors
/// - `Validation`：`group_id` 为空。
/// - `GroupNotFound`：配置中不存在该分组。
/// - `Config`：删除后写回配置文件失败 —— 此时内存中的删除**已回滚**。
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
        let Some(current_group) = state.get_group(id) else {
            state_errors.push((id.clone(), "分组已删除".to_string()));
            continue;
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
            if active {
                state.try_send_ipc_command(&IpcCommand::UnregisterHotkey {
                    hotkey: current_group.hotkey.clone(),
                });
            } else {
                state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                    hotkey: current_group.hotkey.clone(),
                    group_id: id.clone(),
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

/// 把所有分组统一切换为启用 / 停用，返回批量结果。
///
/// # Errors
/// 当前实现**不会失败**：`read_groups` 恒定返回 `Ok`，单个分组出问题也只记进
/// `BatchToggleResult` 的 `state_errors` / `ipc_rolled_back`。
/// 保留 `Result` 是为了与另外两个批量接口签名一致（将来加前置校验不用改调用方）。
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

/// 批量切换指定分组的启用 / 停用状态。
///
/// # Errors
/// `Validation`：`group_ids` 为空列表。
/// 单个分组**出问题不算整体失败**：不存在的记进 `not_found`、状态更新失败的记进
/// `state_errors`、IPC 失败且已回滚的记进 `ipc_rolled_back`。
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

/// 批量删除分组，逐个独立处理、互不影响。
///
/// # Errors
/// `Validation`：`group_ids` 为空列表。
/// ⚠️ **单个分组删除失败不会让整体失败**：失败项连同原因记进
/// `BatchDeleteResult::failed`，成功项照常删除。调用方必须看 `failed`，
/// 不能只看有没有 `Err`。
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
///
/// # Errors
/// - `Validation`：列表为空、列表含不存在的分组 id、或 id 重复。
/// - `Config`：排好序的配置写盘失败（内存中的排序**会回滚**）。
///
/// ⚠️ 未出现在列表里的分组**不会报错**，而是追加到末尾 —— 见返回值的
/// `appended_groups`。
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
/// - 活跃分组：更新配置 + `active_hotkeys` + 发送 IPC 命令到 AHK
/// - 非活跃分组：仅更新配置，激活时自动注册
///
/// # TOCTOU 权衡
///
/// `set_group_hotkey`（更新 `config_state）和` `swap_hotkey`（更新 `active_hotkeys`）
/// 使用不同的 RwLock，两者之间存在极短的 TOCTOU 窗口（微秒级），期间
/// `config_state` 中的热键已更新但 `active_hotkeys` 尚未同步。这与 `set_group_active`
/// 的 TOCTOU 权衡一致（见 state.rs 文档）。
///
/// 此外，`is_active` 在第 400 行读取后到第 409 行使用之间存在时间窗口，
/// 期间分组可能被并发 `toggle_group` 激活或停用。若分组在读取后被激活，
/// 本函数会按非活跃分组处理（仅更新配置），但该分组实际上已是活跃状态，
/// 导致 `active_hotkeys` 与 `config_state` 不一致。此不一致会在下次
/// `toggle_group` 或 `sync_config_changes_to_ahk` 时自动修复。
/// 合并 `is_active` 和 `original_hotkey` 为单次 `get_group` 读取已将窗口
/// 最小化，但无法完全消除跨锁 TOCTOU。
///
/// # Errors
/// - `Validation`：热键或分组 id 为空；热键已被**其它**分组占用（`swap_hotkey` 冲突）。
/// - `GroupNotFound`：分组不存在。
/// - `Ipc`：向 AHK 注册 / 注销热键失败。
///
/// ⚠️ 失败时会尽力回滚，但**回滚本身也可能失败**（只记 `warn` 并发
/// `hotkey_conflict` 事件给前端）。所以拿到 `Err` 时不能假定「什么都没发生过」，
/// 前端应提示用户手动刷新或重新注册。
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
                restore_active_hotkey(state, group_id, old);
                restore_config_hotkey(state, group_id, &original_hotkey);
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
        match old_hotkey.as_deref() {
            // 旧热键就是新热键：活跃表里没变过，不需要回滚
            Some(old) if old == hotkey => {}
            Some(old) => {
                restore_active_hotkey(state, group_id, old);
                // 向 AHK 重新注册旧热键，恢复 AHK 侧热键监听
                state.try_send_ipc_command(&IpcCommand::RegisterHotkey {
                    hotkey: old.to_string(),
                    group_id: group_id.to_string(),
                });
            }
            // 原本没人占着这个热键：把刚刚占住的位置撤掉
            None => {
                let _ = state.unregister_hotkey(hotkey);
            }
        }
        restore_config_hotkey(state, group_id, &original_hotkey);
        return Err(e);
    }

    tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
    Ok(())
}

/// 把**活跃热键表**里的热键**尽量**恢复成 `old`。
///
/// 只在 `register_hotkey` 的 IPC 失败路径上调用。刻意**不返回 `Result`** ——
/// 回滚失败不该掩盖「最初那个 IPC 错误」，所以失败只 `warn`，并通过
/// `hotkey_conflict` 事件让前端提示用户手动刷新；调用方拿它补救完仍然返回自己那个 `Err`。
fn restore_active_hotkey(state: &AppState, group_id: &str, old: &str) {
    if let Err(e) = state.swap_hotkey(old, group_id) {
        tracing::warn!(
            "register_hotkey 回滚失败: 旧热键 '{}' 无法恢复 (原因: {}), active_hotkeys 可能不一致",
            old,
            e
        );
        // 通知前端热键状态不一致，用户可手动刷新或重新注册
        state.emit_event(
            "hotkey_conflict",
            serde_json::json!({
                "groupId": group_id,
                "hotkey": old,
                "reason": format!("回滚失败: {}", e),
            }),
        );
    }
}

/// 把**配置里**的热键**尽量**恢复成 `original_hotkey`。
///
/// 与 [`restore_active_hotkey`] 同理：失败只 `warn`，不返回 `Result`。
fn restore_config_hotkey(state: &AppState, group_id: &str, original_hotkey: &str) {
    if let Err(e) = state.set_group_hotkey(group_id, original_hotkey) {
        tracing::warn!(
            "register_hotkey 回滚 set_group_hotkey 失败: 分组 '{}' 热键无法恢复为 '{}' (原因: {}), config_state 可能不一致",
            group_id, original_hotkey, e
        );
    }
}

/// 注销热键，并把占用它的分组一并停用。
///
/// # Errors
/// - `Validation`：热键为空，或该热键当前未被注册。
/// - `Ipc`：向 AHK 发送注销命令失败 —— 此时会尝试把热键重新注册回去。
///
/// ⚠️ 注销成功后会把原分组置为非活跃并通知 AHK 停止执行：否则 AHK 重连后
/// 该分组会被启用、热键却已丢失。
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
        Err(AppError::Validation(format!("热键 '{hotkey}' 未注册")))
    }
}
