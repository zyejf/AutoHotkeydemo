use asd_application::error::AppError;
use asd_application::recording_service;
use asd_application::recording_service::{ImportedRecording, RecordingResult};
use asd_application::state::AppState;
use std::sync::Arc;

#[cfg(test)]
mod tests {
    use super::*;

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
}

#[tauri::command]
pub async fn start_recording(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
    mode: String,
) -> Result<(), AppError> {
    recording_service::start_recording(&state, &group_id, &mode)
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<RecordingResult, AppError> {
    recording_service::stop_recording(&state)
}

#[tauri::command]
pub async fn pause_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    recording_service::pause_recording(&state)
}

#[tauri::command]
pub async fn resume_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    recording_service::resume_recording(&state)
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
    recording_service::export_recording(&path, &keys, &intervals, &delays, &mode)
}

/// 从文件导入录制数据。
///
/// 注意：此命令不需要 AppState，因为导入仅返回数据供前端使用，
/// 不直接修改内存配置或触发 IPC 同步。
#[tauri::command]
pub async fn import_recording(path: String) -> Result<ImportedRecording, AppError> {
    recording_service::import_recording(&path)
}

#[tauri::command]
pub async fn start_validation(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<u64, AppError> {
    recording_service::start_validation(&state, &group_id)
}

#[tauri::command]
pub async fn stop_validation(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    recording_service::stop_validation(&state)
}
