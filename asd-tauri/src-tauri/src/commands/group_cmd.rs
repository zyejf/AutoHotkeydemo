//! TD-045 豁免：`#[tauri::command]` 的参数保持 owned，不按 clippy 的建议改引用。
//!
//! 2026-09-17 **实测**核实（不是推测），详见
//! `tests/command_contract_tests.rs::tauri_command_args_stay_owned`：
//! 1. `state: tauri::State<'_, Arc<AppState>>` —— Tauri 按类型从 DI 容器提取，
//!    写成 `&State` 就提取不到，必须按值。
//! 2. `group_ids: Vec<String>` —— serde 没有 `&[String]` 的 `Deserialize` 实现
//!    （clippy 那句 "consider `&[String]`" 它自己也给不出），改了编译不过。
//! 3. `group_id: String` —— 技术上**可以**改成 `&str`：Tauri 走
//!    `&'de serde_json::Value` 的 Deserializer，实测能借出 `&str`。
//!    不改是因为那是**改对外 IPC 契约**，而 E2E 覆盖不全（TD-016），
//!    一条 pedantic 告警不值得冒这个险。
//!
//! 复审触发条件：E2E 全绿、能验证契约变更之后。
#![allow(clippy::needless_pass_by_value)]

use asd_application::error::AppError;
use asd_application::group_service::{
    BatchDeleteResult, BatchToggleResult, GroupStatus, GroupSummary, ReorderResult,
};
use asd_application::state::AppState;
use asd_domain::models::SkillGroup;
use std::sync::Arc;

// =================================================================
// 核心逻辑辅助函数（可测试性重构）
// =================================================================
// 设计说明：
// 由于 `tauri::State` 在 Tauri 2.11.2 中无公共构造函数，无法在单元测试中
// 直接构造 `tauri::State<'_, Arc<AppState>>` 调用 command 函数。为使核心逻辑
// 可测试，将其提取到接收 `&AppState` 的同步辅助函数。command 函数仅做一行委托。
// 这是不改变外部行为的最小可测试性重构。

/// `get_groups` 的核心逻辑。
pub fn get_groups_impl(state: &AppState) -> Result<Vec<GroupSummary>, AppError> {
    let groups = state.read_groups()?;
    Ok(groups.values().map(GroupSummary::from).collect())
}

/// `toggle_group` 的核心逻辑。
pub fn toggle_group_impl(state: &AppState, group_id: &str) -> Result<GroupStatus, AppError> {
    // M34: command 层输入验证，与 get_group_detail_impl 保持一致。
    // service 层（group_service::toggle_group）也有相同验证，此处提前验证
    // 确保一致的错误响应，避免依赖 service 层实现细节。
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }
    asd_application::group_service::toggle_group(state, group_id)
}

/// `get_group_detail` 的核心逻辑。
pub fn get_group_detail_impl(state: &AppState, group_id: &str) -> Result<SkillGroup, AppError> {
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }
    state
        .get_group(group_id)
        .ok_or(AppError::GroupNotFound(group_id.to_string()))
}

/// `delete_group` 的核心逻辑。
pub fn delete_group_impl(state: &AppState, group_id: &str) -> Result<(), AppError> {
    // M34: command 层输入验证，与 get_group_detail_impl 保持一致。
    // service 层（group_service::delete_group）也有相同验证，此处提前验证
    // 确保一致的错误响应，避免依赖 service 层实现细节。
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }
    asd_application::group_service::delete_group(state, group_id)
}

/// `toggle_all` 的核心逻辑。
pub fn toggle_all_impl(state: &AppState, active: bool) -> Result<BatchToggleResult, AppError> {
    asd_application::group_service::toggle_all(state, active)
}

/// `batch_toggle_groups` 的核心逻辑。
pub fn batch_toggle_groups_impl(
    state: &AppState,
    group_ids: &[String],
    active: bool,
) -> Result<BatchToggleResult, AppError> {
    asd_application::group_service::batch_toggle_groups(state, group_ids, active)
}

/// `batch_delete_groups` 的核心逻辑。
pub fn batch_delete_groups_impl(
    state: &AppState,
    group_ids: &[String],
) -> Result<BatchDeleteResult, AppError> {
    asd_application::group_service::batch_delete_groups(state, group_ids)
}

/// `reorder_groups` 的核心逻辑。
pub fn reorder_groups_impl(
    state: &AppState,
    group_ids: &[String],
) -> Result<ReorderResult, AppError> {
    asd_application::group_service::reorder_groups(state, group_ids)
}

// =================================================================
// Tauri Command 函数
// =================================================================

#[tauri::command]
pub fn get_groups(state: tauri::State<'_, Arc<AppState>>) -> Result<Vec<GroupSummary>, AppError> {
    get_groups_impl(&state)
}

#[tauri::command]
pub async fn toggle_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<GroupStatus, AppError> {
    toggle_group_impl(&state, &group_id)
}

#[tauri::command]
pub fn get_group_detail(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<SkillGroup, AppError> {
    get_group_detail_impl(&state, &group_id)
}

#[tauri::command]
pub async fn delete_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<(), AppError> {
    delete_group_impl(&state, &group_id)
}

#[tauri::command]
pub async fn toggle_all(
    state: tauri::State<'_, Arc<AppState>>,
    active: bool,
) -> Result<BatchToggleResult, AppError> {
    toggle_all_impl(&state, active)
}

#[tauri::command]
pub async fn batch_toggle_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
    active: bool,
) -> Result<BatchToggleResult, AppError> {
    batch_toggle_groups_impl(&state, &group_ids, active)
}

#[tauri::command]
pub async fn batch_delete_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<BatchDeleteResult, AppError> {
    batch_delete_groups_impl(&state, &group_ids)
}

#[tauri::command]
pub fn reorder_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<ReorderResult, AppError> {
    reorder_groups_impl(&state, &group_ids)
}

// =================================================================
// 测试模块
// =================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;
    use asd_test_harness::{make_test_state, make_test_state_with_path};

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

    // ----------------------------------------------------------------
    // 原有测试（数据结构序列化验证）
    // ----------------------------------------------------------------

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

    // ----------------------------------------------------------------
    // _impl 函数测试 — 正常路径 + 错误路径
    // ----------------------------------------------------------------

    // --- get_groups_impl ---

    /// 验证 get_groups_impl 返回正确的分组列表。
    #[test]
    fn test_get_groups_impl_success() {
        let state = make_test_state();
        let result = get_groups_impl(&state);
        assert!(result.is_ok(), "获取分组列表应成功: {:?}", result.err());
        let groups = result.unwrap();
        assert_eq!(groups.len(), 2, "测试配置应包含 2 个分组");
        assert_eq!(groups[0].id, "1");
        assert_eq!(groups[1].id, "2");
    }

    /// 验证 get_groups_impl 反映删除分组后的状态。
    #[test]
    fn test_get_groups_impl_after_delete() {
        let (state, _dir) = make_test_state_with_path();
        // 删除分组 "1"
        delete_group_impl(&state, "1").unwrap();
        // 验证剩余分组
        let result = get_groups_impl(&state);
        assert!(result.is_ok());
        let groups = result.unwrap();
        assert_eq!(groups.len(), 1, "删除后应剩余 1 个分组");
        assert_eq!(groups[0].id, "2");
    }

    // --- toggle_group_impl ---

    /// 验证 toggle_group_impl 成功切换分组激活状态。
    #[test]
    fn test_toggle_group_impl_success() {
        let state = make_test_state();
        let result = toggle_group_impl(&state, "1");
        assert!(result.is_ok(), "切换分组应成功: {:?}", result.err());
        let status = result.unwrap();
        assert_eq!(status.id, "1");
        assert!(status.active, "首次切换应激活分组");
    }

    /// 验证 toggle_group_impl 拒绝空分组 ID。
    #[test]
    fn test_toggle_group_impl_empty_id() {
        let state = make_test_state();
        let result = toggle_group_impl(&state, "");
        assert!(result.is_err(), "空分组 ID 应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- get_group_detail_impl ---

    /// 验证 get_group_detail_impl 返回正确的分组详情。
    #[test]
    fn test_get_group_detail_impl_success() {
        let state = make_test_state();
        let result = get_group_detail_impl(&state, "1");
        assert!(result.is_ok(), "获取分组详情应成功: {:?}", result.err());
        let group = result.unwrap();
        assert_eq!(group.id, "1");
        assert_eq!(group.hotkey, "F1");
        assert_eq!(group.mode, "periodic");
    }

    /// 验证 get_group_detail_impl 拒绝空分组 ID。
    #[test]
    fn test_get_group_detail_impl_empty_id() {
        let state = make_test_state();
        let result = get_group_detail_impl(&state, "");
        assert!(result.is_err(), "空分组 ID 应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- delete_group_impl ---

    /// 验证 delete_group_impl 成功删除存在的分组。
    #[test]
    fn test_delete_group_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        let result = delete_group_impl(&state, "1");
        assert!(result.is_ok(), "删除分组应成功: {:?}", result.err());
        // 验证分组已被删除
        assert!(state.get_group("1").is_none(), "分组应已被删除");
    }

    /// 验证 delete_group_impl 拒绝空分组 ID。
    #[test]
    fn test_delete_group_impl_empty_id() {
        let state = make_test_state();
        let result = delete_group_impl(&state, "");
        assert!(result.is_err(), "空分组 ID 应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- toggle_all_impl ---

    /// 验证 toggle_all_impl 成功切换所有分组。
    #[test]
    fn test_toggle_all_impl_success() {
        let state = make_test_state();
        let result = toggle_all_impl(&state, true);
        assert!(result.is_ok(), "全局切换应成功: {:?}", result.err());
        let batch_result = result.unwrap();
        assert_eq!(batch_result.succeeded.len(), 2, "2 个分组应全部成功切换");
        assert!(batch_result.state_errors.is_empty(), "不应有状态错误");
    }

    /// 验证 toggle_all_impl 对已激活分组正确计算 skipped。
    #[test]
    fn test_toggle_all_impl_skips_active() {
        let state = make_test_state();
        // 先激活分组 "1"
        toggle_group_impl(&state, "1").unwrap();
        // 全部激活：分组 "1" 已激活应跳过
        let result = toggle_all_impl(&state, true);
        assert!(result.is_ok());
        let batch_result = result.unwrap();
        assert_eq!(batch_result.succeeded.len(), 1, "仅 1 个分组需要切换");
        assert_eq!(batch_result.skipped, 1, "1 个分组已被跳过");
    }

    // --- batch_toggle_groups_impl ---

    /// 验证 batch_toggle_groups_impl 成功批量切换指定分组。
    #[test]
    fn test_batch_toggle_groups_impl_success() {
        let state = make_test_state();
        let group_ids = vec!["1".to_string(), "2".to_string()];
        let result = batch_toggle_groups_impl(&state, &group_ids, true);
        assert!(result.is_ok(), "批量切换应成功: {:?}", result.err());
        let batch_result = result.unwrap();
        assert_eq!(batch_result.succeeded.len(), 2, "2 个分组应全部成功");
        assert!(batch_result.not_found.is_empty(), "不应有未找到的分组");
    }

    /// 验证 batch_toggle_groups_impl 拒绝空分组列表。
    #[test]
    fn test_batch_toggle_groups_impl_empty_ids() {
        let state = make_test_state();
        let result = batch_toggle_groups_impl(&state, &[], true);
        assert!(result.is_err(), "空分组列表应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- batch_delete_groups_impl ---

    /// 验证 batch_delete_groups_impl 成功批量删除分组。
    #[test]
    fn test_batch_delete_groups_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        let group_ids = vec!["1".to_string(), "2".to_string()];
        let result = batch_delete_groups_impl(&state, &group_ids);
        assert!(result.is_ok(), "批量删除应成功: {:?}", result.err());
        let batch_result = result.unwrap();
        assert_eq!(batch_result.deleted.len(), 2, "2 个分组应全部删除");
        assert!(batch_result.failed.is_empty(), "不应有失败");
    }

    /// 验证 batch_delete_groups_impl 拒绝空分组列表。
    #[test]
    fn test_batch_delete_groups_impl_empty_ids() {
        let state = make_test_state();
        let result = batch_delete_groups_impl(&state, &[]);
        assert!(result.is_err(), "空分组列表应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- reorder_groups_impl ---

    /// 验证 reorder_groups_impl 成功重排序分组。
    #[test]
    fn test_reorder_groups_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        // 原始顺序 ["1", "2"]，重排为 ["2", "1"]
        let group_ids = vec!["2".to_string(), "1".to_string()];
        let result = reorder_groups_impl(&state, &group_ids);
        assert!(result.is_ok(), "重排序应成功: {:?}", result.err());
        let reorder_result = result.unwrap();
        assert_eq!(reorder_result.reordered_count, 2, "2 个分组已重排序");
        assert!(reorder_result.appended_groups.is_empty(), "不应有追加分组");
    }

    /// 验证 reorder_groups_impl 拒绝空分组列表。
    #[test]
    fn test_reorder_groups_impl_empty_ids() {
        let state = make_test_state();
        let result = reorder_groups_impl(&state, &[]);
        assert!(result.is_err(), "空分组列表应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }
}
