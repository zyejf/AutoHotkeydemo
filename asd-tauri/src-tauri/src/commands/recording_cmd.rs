use asd_application::error::AppError;
use asd_application::recording_service;
use asd_application::recording_service::{ImportedRecording, RecordingResult};
use asd_application::state::AppState;
use std::sync::Arc;

// =================================================================
// 核心逻辑辅助函数（可测试性重构）
// =================================================================
// 设计说明：
// 由于 `tauri::State` 在 Tauri 2.11.2 中无公共构造函数，无法在单元测试中
// 直接构造 `tauri::State<'_, Arc<AppState>>` 调用 command 函数。为使核心逻辑
// 可测试，将其提取到接收 `&AppState` 的同步辅助函数。command 函数仅做一行委托。
// 这是不改变外部行为的最小可测试性重构。
//
// 注意：`export_recording_impl` 和 `import_recording_impl` 不接收 state 参数，
// 因为它们是纯文件 I/O 操作，不涉及内存状态或 IPC 通信。

/// `start_recording` 的核心逻辑。
pub fn start_recording_impl(state: &AppState, group_id: &str, mode: &str) -> Result<(), AppError> {
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }
    if mode.trim().is_empty() {
        return Err(AppError::Validation("模式不能为空".to_string()));
    }
    recording_service::start_recording(state, group_id, mode)
}

/// `stop_recording` 的核心逻辑。
pub fn stop_recording_impl(state: &AppState) -> Result<RecordingResult, AppError> {
    recording_service::stop_recording(state)
}

/// `pause_recording` 的核心逻辑。
pub fn pause_recording_impl(state: &AppState) -> Result<u64, AppError> {
    recording_service::pause_recording(state)
}

/// `resume_recording` 的核心逻辑。
pub fn resume_recording_impl(state: &AppState) -> Result<u64, AppError> {
    recording_service::resume_recording(state)
}

/// `export_recording` 的核心逻辑。
///
/// 注意：此函数不需要 AppState，因为导出操作是纯文件 I/O，
/// 不涉及内存状态或 IPC 通信。
pub fn export_recording_impl(
    path: &str,
    keys: &[String],
    intervals: &[u64],
    delays: &[u64],
    mode: &str,
) -> Result<(), AppError> {
    if path.trim().is_empty() {
        return Err(AppError::Validation("导出路径不能为空".to_string()));
    }
    recording_service::export_recording(path, keys, intervals, delays, mode)
}

/// `import_recording` 的核心逻辑。
///
/// 注意：此函数不需要 AppState，因为导入仅返回数据供前端使用，
/// 不直接修改内存配置或触发 IPC 同步。
pub fn import_recording_impl(path: &str) -> Result<ImportedRecording, AppError> {
    if path.trim().is_empty() {
        return Err(AppError::Validation("导入路径不能为空".to_string()));
    }
    recording_service::import_recording(path)
}

/// `start_validation` 的核心逻辑。
pub fn start_validation_impl(state: &AppState, group_id: &str) -> Result<u64, AppError> {
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }
    recording_service::start_validation(state, group_id)
}

/// `stop_validation` 的核心逻辑。
pub fn stop_validation_impl(state: &AppState) -> Result<u64, AppError> {
    recording_service::stop_validation(state)
}

// =================================================================
// Tauri Command 函数
// =================================================================

#[tauri::command]
pub async fn start_recording(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
    mode: String,
) -> Result<(), AppError> {
    start_recording_impl(&state, &group_id, &mode)
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<RecordingResult, AppError> {
    stop_recording_impl(&state)
}

#[tauri::command]
pub async fn pause_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    pause_recording_impl(&state)
}

#[tauri::command]
pub async fn resume_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    resume_recording_impl(&state)
}

/// 导出录制数据到文件。
///
/// 注意：此命令不需要 AppState，因为导出操作是纯文件 I/O，
/// 不涉及内存状态或 IPC 通信。
#[tauri::command]
pub async fn export_recording(
    path: String,
    keys: Vec<String>,
    intervals: Vec<u64>,
    delays: Vec<u64>,
    mode: String,
) -> Result<(), AppError> {
    export_recording_impl(&path, &keys, &intervals, &delays, &mode)
}

/// 从文件导入录制数据。
///
/// 注意：此命令不需要 AppState，因为导入仅返回数据供前端使用，
/// 不直接修改内存配置或触发 IPC 同步。
#[tauri::command]
pub async fn import_recording(path: String) -> Result<ImportedRecording, AppError> {
    import_recording_impl(&path)
}

#[tauri::command]
pub async fn start_validation(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<u64, AppError> {
    start_validation_impl(&state, &group_id)
}

#[tauri::command]
pub async fn stop_validation(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    stop_validation_impl(&state)
}

// =================================================================
// 测试模块
// =================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use asd_test_harness::{make_test_state, make_test_state_with_path};

    // ----------------------------------------------------------------
    // 原有测试（RecordingResult 序列化验证）
    // ----------------------------------------------------------------

    #[test]
    fn test_recording_result_serialization() {
        let result = RecordingResult {
            seq: 42,
            keys: vec!["1".to_string(), "2".to_string()],
            mode: "periodic".to_string(),
            intervals: vec![50, 100],
            delays: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        let decoded: RecordingResult = serde_json::from_str(&json).unwrap();

        assert_eq!(decoded.seq, 42);
        assert_eq!(decoded.keys, vec!["1", "2"]);
        assert_eq!(decoded.mode, "periodic");
        assert_eq!(decoded.intervals, vec![50, 100]);
        assert!(decoded.delays.is_empty());
    }

    #[test]
    fn test_recording_result_empty_keys() {
        let result = RecordingResult {
            seq: 1,
            keys: vec![],
            mode: String::new(),
            intervals: vec![],
            delays: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        let decoded: RecordingResult = serde_json::from_str(&json).unwrap();

        assert!(decoded.keys.is_empty());
        assert!(decoded.mode.is_empty());
    }

    #[test]
    fn test_recording_result_skip_empty_intervals_and_delays() {
        let result = RecordingResult {
            seq: 1,
            keys: vec!["Space".to_string()],
            mode: "periodic".to_string(),
            intervals: vec![],
            delays: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(!json.contains("intervals"));
        assert!(!json.contains("delays"));
    }

    // ----------------------------------------------------------------
    // _impl 函数测试 — 正常路径 + 错误路径
    // ----------------------------------------------------------------

    // --- start_recording_impl ---

    /// 验证 start_recording_impl 成功启动录制。
    #[test]
    fn test_start_recording_impl_success() {
        let state = make_test_state();
        let result = start_recording_impl(&state, "1", "periodic");
        assert!(result.is_ok(), "启动录制应成功: {:?}", result.err());
    }

    /// 验证 start_recording_impl 拒绝空分组 ID。
    #[test]
    fn test_start_recording_impl_empty_group_id() {
        let state = make_test_state();
        let result = start_recording_impl(&state, "", "periodic");
        assert!(result.is_err(), "空分组 ID 应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- stop_recording_impl ---

    /// 验证 stop_recording_impl 成功停止录制并返回结果。
    #[test]
    fn test_stop_recording_impl_success() {
        let state = make_test_state();
        // 先启动录制
        start_recording_impl(&state, "1", "periodic").unwrap();
        // 停止录制
        let result = stop_recording_impl(&state);
        assert!(result.is_ok(), "停止录制应成功: {:?}", result.err());
        let recording = result.unwrap();
        assert!(!recording.keys.is_empty(), "录制结果应包含按键");
        assert_eq!(recording.mode, "periodic", "录制模式应为 periodic");
    }

    /// 验证 stop_recording_impl 在未录制时返回错误。
    #[test]
    fn test_stop_recording_impl_not_recording() {
        let state = make_test_state();
        let result = stop_recording_impl(&state);
        assert!(result.is_err(), "未录制时停止应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- pause_recording_impl ---

    /// 验证 pause_recording_impl 成功暂停录制。
    #[test]
    fn test_pause_recording_impl_success() {
        let state = make_test_state();
        // 先启动录制
        start_recording_impl(&state, "1", "periodic").unwrap();
        // 暂停录制
        let result = pause_recording_impl(&state);
        assert!(result.is_ok(), "暂停录制应成功: {:?}", result.err());
    }

    /// 验证 pause_recording_impl 在未录制时返回错误。
    #[test]
    fn test_pause_recording_impl_not_recording() {
        let state = make_test_state();
        let result = pause_recording_impl(&state);
        assert!(result.is_err(), "未录制时暂停应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- resume_recording_impl ---

    /// 验证 resume_recording_impl 成功恢复录制。
    #[test]
    fn test_resume_recording_impl_success() {
        let state = make_test_state();
        // 先启动录制
        start_recording_impl(&state, "1", "periodic").unwrap();
        // 暂停录制
        pause_recording_impl(&state).unwrap();
        // 恢复录制
        let result = resume_recording_impl(&state);
        assert!(result.is_ok(), "恢复录制应成功: {:?}", result.err());
    }

    /// 验证 resume_recording_impl 在未录制时返回错误。
    #[test]
    fn test_resume_recording_impl_not_recording() {
        let state = make_test_state();
        let result = resume_recording_impl(&state);
        assert!(result.is_err(), "未录制时恢复应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- export_recording_impl ---

    /// 验证 export_recording_impl 成功导出录制数据到文件。
    #[test]
    fn test_export_recording_impl_success() {
        let (_state, dir) = make_test_state_with_path();
        let export_path = dir.path().join("recording_export.json");
        let result = export_recording_impl(
            export_path.to_str().unwrap(),
            &["1".to_string(), "2".to_string()],
            &[50, 100],
            &[],
            "periodic",
        );
        assert!(result.is_ok(), "导出录制应成功: {:?}", result.err());
        assert!(export_path.exists(), "导出文件应存在");
    }

    /// 验证 export_recording_impl 拒绝空路径。
    ///
    /// 空路径应在 _impl 层被 `AppError::Validation` 拦截，
    /// 不应进入 `validate_file_path` 返回 `AppError::Config`。
    #[test]
    fn test_export_recording_impl_empty_path() {
        let result = export_recording_impl("", &["1".to_string()], &[50], &[], "periodic");
        assert!(result.is_err(), "空路径应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    /// 验证 export_recording_impl 拒绝纯空白路径。
    #[test]
    fn test_export_recording_impl_whitespace_path() {
        let result = export_recording_impl("   ", &["1".to_string()], &[50], &[], "periodic");
        assert!(result.is_err(), "纯空白路径应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- import_recording_impl ---

    /// 验证 import_recording_impl 成功从文件导入录制数据。
    #[test]
    fn test_import_recording_impl_success() {
        let (_state, dir) = make_test_state_with_path();
        let export_path = dir.path().join("recording_import.json");
        // 先导出录制数据
        export_recording_impl(
            export_path.to_str().unwrap(),
            &["1".to_string(), "2".to_string()],
            &[50, 100],
            &[],
            "periodic",
        )
        .unwrap();
        // 再导入
        let result = import_recording_impl(export_path.to_str().unwrap());
        assert!(result.is_ok(), "导入录制应成功: {:?}", result.err());
        let imported = result.unwrap();
        assert_eq!(imported.keys, vec!["1", "2"], "导入的按键应匹配");
        assert_eq!(imported.mode, "periodic", "导入的模式应为 periodic");
    }

    /// 验证 import_recording_impl 拒绝空路径。
    ///
    /// 空路径应在 _impl 层被 `AppError::Validation` 拦截，
    /// 不应进入 `validate_file_path` 返回 `AppError::Config`。
    #[test]
    fn test_import_recording_impl_empty_path() {
        let result = import_recording_impl("");
        assert!(result.is_err(), "空路径应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    /// 验证 import_recording_impl 拒绝纯空白路径。
    #[test]
    fn test_import_recording_impl_whitespace_path() {
        let result = import_recording_impl("   ");
        assert!(result.is_err(), "纯空白路径应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- start_validation_impl ---

    /// 验证 start_validation_impl 成功启动验证。
    #[test]
    fn test_start_validation_impl_success() {
        let state = make_test_state();
        let result = start_validation_impl(&state, "1");
        assert!(result.is_ok(), "启动验证应成功: {:?}", result.err());
    }

    /// 验证 start_validation_impl 拒绝空分组 ID。
    #[test]
    fn test_start_validation_impl_empty_group_id() {
        let state = make_test_state();
        let result = start_validation_impl(&state, "");
        assert!(result.is_err(), "空分组 ID 应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }

    // --- stop_validation_impl ---

    /// 验证 stop_validation_impl 成功停止验证。
    #[test]
    fn test_stop_validation_impl_success() {
        let state = make_test_state();
        // 先启动验证
        start_validation_impl(&state, "1").unwrap();
        // 停止验证
        let result = stop_validation_impl(&state);
        assert!(result.is_ok(), "停止验证应成功: {:?}", result.err());
    }

    /// 验证 stop_validation_impl 在未验证时返回错误。
    #[test]
    fn test_stop_validation_impl_not_validating() {
        let state = make_test_state();
        let result = stop_validation_impl(&state);
        assert!(result.is_err(), "未验证时停止应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {:?}", other),
        }
    }
}
