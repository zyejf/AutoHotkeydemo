use crate::backup_service::validate_file_path;
use crate::error::AppError;
use crate::state::AppState;
use crate::time_format::format_datetime;
use asd_ipc_protocol::IpcCommand;
use serde::{Deserialize, Serialize};

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

pub fn start_recording(state: &AppState, group_id: &str, mode: &str) -> Result<(), AppError> {
    state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;

    let cmd = IpcCommand::StartRecording {
        group_id: group_id.to_string(),
        mode: mode.to_string(),
    };
    state.send_ipc_command(&cmd)?;

    tracing::info!("开始录制: group={}, mode={}", group_id, mode);
    Ok(())
}

pub fn stop_recording(state: &AppState) -> Result<RecordingResult, AppError> {
    let cmd = IpcCommand::StopRecording;
    let response = state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))?;

    tracing::info!("停止录制: seq={}", response.seq);

    let keys = response
        .data
        .as_ref()
        .and_then(|d| d.get("keys"))
        .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
        .ok_or_else(|| AppError::Ipc("录制响应缺少 keys 字段".to_string()))?;

    let mode = response
        .data
        .as_ref()
        .and_then(|d| d.get("mode"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::Ipc("录制响应缺少 mode 字段".to_string()))?
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

pub fn pause_recording(state: &AppState) -> Result<u64, AppError> {
    let cmd = IpcCommand::PauseRecording;
    let response = state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))?;
    tracing::info!("暂停录制: seq={}", response.seq);
    Ok(response.seq)
}

pub fn resume_recording(state: &AppState) -> Result<u64, AppError> {
    let cmd = IpcCommand::ResumeRecording;
    let response = state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))?;
    tracing::info!("恢复录制: seq={}", response.seq);
    Ok(response.seq)
}

pub fn export_recording(
    path: &str,
    keys: &[String],
    intervals: &[u64],
    mode: &str,
) -> Result<(), AppError> {
    validate_file_path(path)?;

    let recording_data = serde_json::json!({
        "keys": keys,
        "intervals": intervals,
        "mode": mode,
        "exportedAt": format_datetime(),
    });

    let json = serde_json::to_string_pretty(&recording_data)
        .map_err(|e| AppError::Config(format!("序列化录制数据失败: {e}")))?;

    std::fs::write(path, json).map_err(|e| AppError::Config(format!("写入文件失败: {e}")))?;

    tracing::info!("录制结果已导出: {}", path);
    Ok(())
}

pub fn import_recording(path: &str) -> Result<ImportedRecording, AppError> {
    validate_file_path(path)?;

    let content = std::fs::read_to_string(path)
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

pub fn start_validation(state: &AppState, group_id: &str) -> Result<u64, AppError> {
    let cmd = IpcCommand::StartValidation {
        group_id: group_id.to_string(),
    };
    let seq = state.send_ipc_command(&cmd)?;
    tracing::info!("启动验证: groupId={}, seq={}", group_id, seq);
    Ok(seq)
}

pub fn stop_validation(state: &AppState) -> Result<u64, AppError> {
    let cmd = IpcCommand::StopValidation;
    let seq = state.send_ipc_command(&cmd)?;
    tracing::info!("停止验证: seq={}", seq);
    Ok(seq)
}
