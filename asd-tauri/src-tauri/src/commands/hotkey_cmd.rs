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

// =================================================================
// 测试模块 — 验证 hotkey command 层行为
// =================================================================
// 设计说明：
// - 使用 `asd_test_harness::make_test_state` 构造带 Mock 依赖的 AppState
// - 由于 `tauri::State` 在 Tauri 2.11.2 中无公共构造函数（无法在单元测试中直接构造），
//   测试通过直接调用 command 函数委托的 `group_service` 函数验证等效行为。
//   command 函数体仅一行委托：`group_service::register_hotkey(&state, &hotkey, &group_id)`，
//   因此调用 `group_service` 函数与调用 command 函数行为完全一致。
// - 任务清单中的 `list_hotkeys` command 不存在，使用 `state.get_all_registered_hotkeys()`
//   验证热键列表（command 层未暴露 list 接口，但底层 state 提供）
#[cfg(test)]
mod tests {
    use super::*;
    use asd_application::group_service;
    use asd_test_harness::make_test_state;

    // ----------------------------------------------------------------
    // 正常路径测试 × 3
    // ----------------------------------------------------------------

    /// 验证 register_hotkey 对非活跃分组成功更新配置热键。
    /// 非活跃分组仅更新配置（不发送 IPC），符合 group_service::register_hotkey 设计。
    #[test]
    fn test_register_hotkey_success() {
        let state = make_test_state();
        // make_test_config 中分组 "1" 初始为非活跃，热键为 "F1"
        let result = group_service::register_hotkey(&state, "F3", "1");
        assert!(result.is_ok(), "注册热键应成功: {:?}", result.err());
        // 验证配置已更新
        let group = state.get_group("1").unwrap();
        assert_eq!(group.hotkey, "F3", "分组热键应已更新为 F3");
    }

    /// 验证 unregister_hotkey 成功注销已注册的活跃热键。
    /// 流程：先激活分组（注册热键到 active_hotkeys），再注销。
    #[test]
    fn test_unregister_hotkey_success() {
        let state = make_test_state();
        // 激活分组 "1"，使其热键 F1 注册到 active_hotkeys
        group_service::toggle_group(&state, "1").unwrap();
        assert!(!state.get_all_registered_hotkeys().unwrap().is_empty());

        let result = group_service::unregister_hotkey(&state, "F1");
        assert!(result.is_ok(), "注销热键应成功: {:?}", result.err());
        // 验证 active_hotkeys 已清空
        assert!(state.get_all_registered_hotkeys().unwrap().is_empty());
    }

    /// 验证注册后查询热键列表返回正确结果。
    /// 任务清单中的 list_hotkeys command 不存在，使用 state.get_all_registered_hotkeys()
    /// 验证 command 层注册后的热键列表状态（command 层未暴露 list 接口）。
    #[test]
    fn test_list_registered_hotkeys() {
        let state = make_test_state();
        // 初始状态：无活跃分组，热键列表为空
        assert!(state.get_all_registered_hotkeys().unwrap().is_empty());

        // 激活两个分组，注册两个热键
        group_service::toggle_group(&state, "1").unwrap(); // F1
        group_service::toggle_group(&state, "2").unwrap(); // F2

        // 验证热键列表包含两条记录
        let hotkeys = state.get_all_registered_hotkeys().unwrap();
        assert_eq!(hotkeys.len(), 2, "应有两个已注册热键");
        let hotkey_strs: Vec<String> = hotkeys.iter().map(|(h, _)| h.clone()).collect();
        assert!(hotkey_strs.contains(&"F1".to_string()), "应包含 F1");
        assert!(hotkey_strs.contains(&"F2".to_string()), "应包含 F2");
    }

    // ----------------------------------------------------------------
    // 错误路径测试 × 3
    // ----------------------------------------------------------------

    /// 验证 register_hotkey 重复注册（热键冲突）失败。
    /// 场景：两个活跃分组，尝试将分组 2 的热键改为分组 1 已注册的 F1。
    /// group_service::register_hotkey 调用 swap_hotkey 检测到冲突，返回 Validation 错误。
    #[test]
    fn test_register_hotkey_duplicate_fails() {
        let state = make_test_state();
        // 激活两个分组，使热键注册经过 active_hotkeys 重复检查
        group_service::toggle_group(&state, "1").unwrap();
        group_service::toggle_group(&state, "2").unwrap();

        // 尝试将分组 2 的热键改为分组 1 已注册的 F1
        let result = group_service::register_hotkey(&state, "F1", "2");
        assert!(result.is_err(), "重复注册热键应失败");
        let err = result.unwrap_err();
        assert!(
            matches!(err, AppError::Validation(_)),
            "重复注册应返回 Validation 错误，实际: {err:?}"
        );
    }

    /// 验证 unregister_hotkey 注销未注册的热键失败。
    /// group_service::unregister_hotkey 返回 Validation("热键 'xxx' 未注册")。
    #[test]
    fn test_unregister_hotkey_not_registered_fails() {
        let state = make_test_state();
        let result = group_service::unregister_hotkey(&state, "F99");
        assert!(result.is_err(), "注销未注册热键应失败");
        let err = result.unwrap_err();
        assert!(
            matches!(err, AppError::Validation(ref msg) if msg.contains("未注册")),
            "应返回包含'未注册'的 Validation 错误，实际: {err:?}"
        );
    }

    /// 验证 register_hotkey 空热键格式失败。
    /// group_service::register_hotkey 检查 hotkey.trim().is_empty() 返回 Validation。
    #[test]
    fn test_register_hotkey_empty_fails() {
        let state = make_test_state();
        let result = group_service::register_hotkey(&state, "   ", "1");
        assert!(result.is_err(), "空热键应注册失败");
        let err = result.unwrap_err();
        assert!(
            matches!(err, AppError::Validation(ref msg) if msg.contains("热键不能为空")),
            "应返回'热键不能为空'错误，实际: {err:?}"
        );
    }
}
