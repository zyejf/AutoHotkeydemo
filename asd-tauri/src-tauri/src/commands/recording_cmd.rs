use crate::application::state::{AppError, AppState};
use crate::domain::models::IpcCommand;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingResult {
    pub seq: u64,
    pub keys: Vec<String>,
    pub mode: String,
    #[serde(rename = "intervals", skip_serializing_if = "Vec::is_empty", default)]
    pub intervals: Vec<u64>,
    #[serde(rename = "delays", skip_serializing_if = "Vec::is_empty", default)]
    pub delays: Vec<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ImportedRecording {
    pub keys: Vec<String>,
    pub intervals: Vec<u64>,
    pub mode: String,
}

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
        // skip_serializing_if 应省略空的 intervals 和 delays
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
    state
        .get_group(&group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.clone()))?;

    let cmd = IpcCommand::StartRecording {
        group_id: group_id.clone(),
        mode: mode.clone(),
    };
    state.send_ipc_command(&cmd).await?;

    tracing::info!("开始录制: group={}, mode={}", group_id, mode);
    Ok(())
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<RecordingResult, AppError> {
    let cmd = IpcCommand::StopRecording;
    let response = state
        .send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))
        .await?;

    tracing::info!("停止录制: seq={}", response.seq);

    let keys = response
        .data
        .as_ref()
        .and_then(|d| d.get("keys"))
        .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
        .unwrap_or_default();

    let mode = response
        .data
        .as_ref()
        .and_then(|d| d.get("mode"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let intervals = response
        .data
        .as_ref()
        .and_then(|d| d.get("intervals"))
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();

    let delays = response
        .data
        .as_ref()
        .and_then(|d| d.get("delays"))
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();

    Ok(RecordingResult {
        seq: response.seq,
        keys,
        mode,
        intervals,
        delays,
    })
}

#[tauri::command]
pub async fn pause_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    let cmd = IpcCommand::PauseRecording;
    let seq = state.send_ipc_command(&cmd).await?;
    tracing::info!("暂停录制: seq={}", seq);
    Ok(seq)
}

#[tauri::command]
pub async fn resume_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    let cmd = IpcCommand::ResumeRecording;
    let seq = state.send_ipc_command(&cmd).await?;
    tracing::info!("恢复录制: seq={}", seq);
    Ok(seq)
}

#[tauri::command]
pub async fn export_recording(
    path: String,
    keys: Vec<String>,
    intervals: Vec<u64>,
    mode: String,
) -> Result<(), AppError> {
    let recording_data = serde_json::json!({
        "keys": keys,
        "intervals": intervals,
        "mode": mode,
        "exportedAt": chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
    });

    let json = serde_json::to_string_pretty(&recording_data)
        .map_err(|e| AppError::Config(format!("序列化录制数据失败: {e}")))?;

    std::fs::write(&path, json).map_err(|e| AppError::Config(format!("写入文件失败: {e}")))?;

    tracing::info!("录制结果已导出: {}", path);
    Ok(())
}

#[tauri::command]
pub async fn import_recording(path: String) -> Result<ImportedRecording, AppError> {
    let content = std::fs::read_to_string(&path)
        .map_err(|e| AppError::Config(format!("读取文件失败: {e}")))?;

    let data: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| AppError::Config(format!("解析录制数据失败: {e}")))?;

    let keys = data
        .get("keys")
        .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
        .unwrap_or_default();

    let intervals = data
        .get("intervals")
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();

    let mode = data
        .get("mode")
        .and_then(|v| v.as_str())
        .unwrap_or("periodic")
        .to_string();

    Ok(ImportedRecording {
        keys,
        intervals,
        mode,
    })
}

#[tauri::command]
pub async fn start_validation(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<u64, AppError> {
    let cmd = IpcCommand::StartValidation {
        group_id: group_id.clone(),
    };
    let seq = state.send_ipc_command(&cmd).await?;
    tracing::info!("启动验证: groupId={}, seq={}", group_id, seq);
    Ok(seq)
}

#[tauri::command]
pub async fn stop_validation(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    let cmd = IpcCommand::StopValidation;
    let seq = state.send_ipc_command(&cmd).await?;
    tracing::info!("停止验证: seq={}", seq);
    Ok(seq)
}
