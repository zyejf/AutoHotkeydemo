use asd_application::error::AppError;
use asd_application::state::{AppState, WatchdogState};
use asd_ipc_protocol::IpcCommand;
use std::sync::atomic::Ordering;
use std::sync::Arc;

// =================================================================
// 核心逻辑辅助函数（可测试性重构）
// =================================================================
// 设计说明：
// 由于 `tauri::State` 在 Tauri 2.11.2 中无公共构造函数，无法在单元测试中
// 直接构造 `tauri::State<'_, Arc<AppState>>` 调用 command 函数。为使核心逻辑
// 可测试，将其提取到接收 `&AppState` 的同步辅助函数。command 函数仅做一行委托。
// 这是不改变外部行为的最小可测试性重构。

/// `get_executor_status` 的核心逻辑。
pub fn get_executor_status_impl(state: &AppState) -> Result<WatchdogState, AppError> {
    let ws = state.watchdog_state.read();
    Ok(ws.clone())
}

/// `emergency_release` 的核心逻辑。
///
/// 紧急释放是安全关键操作，始终发送 IPC 命令，即使已处于紧急模式。
/// 原因：AHK 子进程可能已重启（post_connect_callback 清除了 Rust 侧标志），
/// 但 AHK 侧可能仍持有按键。重发 IPC 确保按键释放。
pub fn emergency_release_impl(state: &AppState) -> Result<(), AppError> {
    let already_active = state
        .emergency_mode
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err();

    if already_active {
        tracing::warn!("紧急释放已激活（重复调用），仍发送 IPC 命令确保 AHK 侧释放");
    }

    if let Err(e) = state.send_ipc_command(&IpcCommand::EmergencyRelease) {
        // 仅在首次设置（非重复调用）时回滚，避免覆盖并发的 clear_emergency
        if !already_active {
            let _ = state.emergency_mode.compare_exchange(
                true,
                false,
                Ordering::SeqCst,
                Ordering::SeqCst,
            );
        }
        return Err(e);
    }
    tracing::warn!("紧急释放已激活");
    Ok(())
}

/// `toggle_hold_mode` 的核心逻辑。
pub fn toggle_hold_mode_impl(state: &AppState) -> Result<bool, AppError> {
    let new_value;
    let mut attempts = 0;
    loop {
        let current = state.hold_mode_enabled.load(Ordering::SeqCst);
        let candidate = !current;
        if state
            .hold_mode_enabled
            .compare_exchange(current, candidate, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
        {
            new_value = candidate;
            break;
        }
        attempts += 1;
        if attempts >= 10 {
            return Err(AppError::Internal(
                "toggle_hold_mode CAS 竞争超限".to_string(),
            ));
        }
    }

    if let Err(e) = state.send_ipc_command(&IpcCommand::HoldModeToggle { enabled: new_value }) {
        // 回滚 compare_exchange: 仅当值仍为 new_value 时才翻转为 !new_value。
        let _ = state.hold_mode_enabled.compare_exchange(
            new_value,
            !new_value,
            Ordering::SeqCst,
            Ordering::SeqCst,
        );
        return Err(e);
    }

    tracing::info!("长按模式已{}", if new_value { "开启" } else { "关闭" });
    Ok(new_value)
}

// =================================================================
// Tauri Command 函数
// =================================================================

#[tauri::command]
pub fn get_executor_status(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<WatchdogState, AppError> {
    get_executor_status_impl(&state)
}

#[tauri::command]
pub async fn emergency_release(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    emergency_release_impl(&state)
}

#[tauri::command]
pub async fn clear_emergency(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    // 使用 compare_exchange 而非 store，与 emergency_release 对称，
    // 避免覆盖并发 emergency_release 设置的 true
    if state
        .emergency_mode
        .compare_exchange(true, false, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        tracing::info!("紧急释放模式已清除");
    } else {
        tracing::debug!("紧急释放模式已处于关闭状态");
    }
    Ok(())
}

#[tauri::command]
pub async fn toggle_hold_mode(state: tauri::State<'_, Arc<AppState>>) -> Result<bool, AppError> {
    toggle_hold_mode_impl(&state)
}

#[tauri::command]
pub async fn reset_watchdog(state: tauri::State<'_, Arc<AppState>>) -> Result<(), AppError> {
    state.reset_watchdog()?;
    tracing::info!("看门狗已重置，将尝试重新启动子进程");
    Ok(())
}

// =================================================================
// 测试模块 — 验证 system command 层行为
// =================================================================
// 设计说明：
// - 使用 `asd_test_harness::make_test_state` 构造带 Mock 依赖的 AppState
// - 由于 `tauri::State` 无公共构造函数，测试通过调用提取的 `_impl` 辅助函数
//   验证 command 函数的核心逻辑（command 函数仅一行委托）
// - 任务清单中的 `get_system_status` 实际为 `get_executor_status`
// - 任务清单中的 `emergency_release 在无效状态下失败` 适配为 IPC 失败时回滚
// - 任务清单中的 `toggle_hold_mode 无效参数失败` 适配为 IPC 失败时回滚
//   （toggle_hold_mode 无参数，不存在"无效参数"场景）
#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::WatchdogStateEnum;
    use asd_domain::traits::IpcSender;
    use asd_ipc_protocol::{IpcCommand, IpcMessage};
    use asd_test_harness::{
        make_test_config, make_test_state, MockEventEmitter, MockProcessWatcher,
    };
    use std::sync::Arc;
    use std::time::Duration;

    /// 失败型 IPC 发送器 Mock — 用于测试 IPC 失败时的回滚逻辑。
    /// 所有 send 方法返回错误，模拟 AHK 子进程通信失败场景。
    struct FailingIpcSender;
    impl IpcSender for FailingIpcSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Err("IPC 发送失败（测试模拟）".to_string())
        }
        fn send_and_wait(
            &self,
            _cmd: IpcCommand,
            _timeout: Duration,
        ) -> Result<IpcMessage, String> {
            Err("IPC 发送失败（测试模拟）".to_string())
        }
        fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
            Err("IPC 发送失败（测试模拟）".to_string())
        }
    }

    /// 构造使用 `FailingIpcSender` 的 AppState，用于测试 IPC 失败路径。
    fn make_failing_state() -> Arc<AppState> {
        Arc::new(AppState::new(
            make_test_config(),
            Arc::new(FailingIpcSender),
            Arc::new(MockProcessWatcher),
            Arc::new(MockEventEmitter::new()),
        ))
    }

    // ----------------------------------------------------------------
    // 正常路径测试 × 3
    // ----------------------------------------------------------------

    /// 验证 get_executor_status 返回正确的初始状态。
    /// 任务清单中的 `get_system_status` 实际函数名为 `get_executor_status`。
    #[test]
    fn test_get_executor_status_returns_correct_state() {
        let state = make_test_state();
        let result = get_executor_status_impl(&state);
        assert!(result.is_ok(), "获取状态应成功: {:?}", result.err());
        let ws = result.unwrap();
        assert_eq!(ws.status, WatchdogStateEnum::Idle, "初始状态应为 Idle");
        assert_eq!(ws.restart_count, 0, "初始重启次数应为 0");
    }

    /// 验证 emergency_release 成功设置紧急模式。
    /// 成功路径：CAS(false→true) 成功 + IPC 发送成功 → emergency_mode = true。
    #[test]
    fn test_emergency_release_success() {
        let state = make_test_state();
        // 前置条件：emergency_mode 未激活
        assert!(!state.is_emergency_mode(), "初始 emergency_mode 应为 false");

        let result = emergency_release_impl(&state);
        assert!(result.is_ok(), "紧急释放应成功: {:?}", result.err());
        // 验证 emergency_mode 已设置为 true
        assert!(
            state.is_emergency_mode(),
            "紧急释放后 emergency_mode 应为 true"
        );
    }

    /// 验证 toggle_hold_mode 成功翻转长按模式。
    /// 初始 false → 翻转为 true → 返回新值 true。
    #[test]
    fn test_toggle_hold_mode_toggles() {
        let state = make_test_state();
        // 前置条件：hold_mode_enabled 未开启
        assert!(
            !state.is_hold_mode_enabled(),
            "初始 hold_mode_enabled 应为 false"
        );

        let result = toggle_hold_mode_impl(&state);
        assert!(result.is_ok(), "切换长按模式应成功: {:?}", result.err());
        let new_value = result.unwrap();
        assert!(new_value, "首次切换应返回 true（false→true）");
        assert!(
            state.is_hold_mode_enabled(),
            "切换后 hold_mode_enabled 应为 true"
        );

        // 再次切换：true → false
        let result2 = toggle_hold_mode_impl(&state);
        assert!(result2.is_ok(), "第二次切换应成功: {:?}", result2.err());
        let new_value2 = result2.unwrap();
        assert!(!new_value2, "第二次切换应返回 false（true→false）");
        assert!(
            !state.is_hold_mode_enabled(),
            "二次切换后 hold_mode_enabled 应为 false"
        );
    }

    // ----------------------------------------------------------------
    // 错误路径测试 × 3
    // ----------------------------------------------------------------

    /// 验证 emergency_release 在 IPC 失败时回滚 emergency_mode。
    /// 任务清单中的 `emergency_release 在无效状态下失败` 适配为 IPC 失败回滚场景。
    /// 场景：首次调用（already_active=false）+ IPC 失败 → 回滚 emergency_mode 为 false。
    #[test]
    fn test_emergency_release_ipc_failure_rolls_back() {
        let state = make_failing_state();
        // 前置条件：emergency_mode 未激活
        assert!(!state.is_emergency_mode());

        let result = emergency_release_impl(&state);
        assert!(result.is_err(), "IPC 失败时紧急释放应返回错误");
        // 验证 emergency_mode 已回滚为 false（首次调用 + IPC 失败 → 回滚）
        assert!(
            !state.is_emergency_mode(),
            "IPC 失败时 emergency_mode 应回滚为 false，实际: {}",
            state.is_emergency_mode()
        );
    }

    /// 验证 toggle_hold_mode 在 IPC 失败时回滚 hold_mode_enabled。
    /// 任务清单中的 `toggle_hold_mode 无效参数失败` 适配为 IPC 失败回滚场景
    /// （toggle_hold_mode 无参数，不存在"无效参数"场景）。
    /// 场景：CAS 成功翻转 false→true + IPC 失败 → 回滚 hold_mode_enabled 为 false。
    #[test]
    fn test_toggle_hold_mode_ipc_failure_rolls_back() {
        let state = make_failing_state();
        // 前置条件：hold_mode_enabled 未开启
        assert!(!state.is_hold_mode_enabled());

        let result = toggle_hold_mode_impl(&state);
        assert!(result.is_err(), "IPC 失败时切换长按模式应返回错误");
        // 验证 hold_mode_enabled 已回滚为 false（CAS 翻转 + IPC 失败 → 回滚）
        assert!(
            !state.is_hold_mode_enabled(),
            "IPC 失败时 hold_mode_enabled 应回滚为 false，实际: {}",
            state.is_hold_mode_enabled()
        );
    }

    /// 验证 get_executor_status 反映状态更新。
    /// 任务清单中的 `get_system_status 状态查询` — 更新 watchdog_state 后应反映新状态。
    #[test]
    fn test_get_executor_status_reflects_updates() {
        let state = make_test_state();
        // 初始状态
        let initial = get_executor_status_impl(&state).unwrap();
        assert_eq!(initial.status, WatchdogStateEnum::Idle);
        assert_eq!(initial.restart_count, 0);

        // 更新 watchdog_state
        state.update_watchdog_state(&WatchdogStateEnum::Running, 3);
        let updated = get_executor_status_impl(&state).unwrap();
        assert_eq!(
            updated.status,
            WatchdogStateEnum::Running,
            "更新后状态应为 Running"
        );
        assert_eq!(updated.restart_count, 3, "更新后重启次数应为 3");
    }
}
