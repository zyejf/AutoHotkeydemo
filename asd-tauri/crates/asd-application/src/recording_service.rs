use crate::backup_service::validate_file_path;
use crate::config_repository::atomic_write;
use crate::config_repository::ConfigRepository;
use crate::error::AppError;
use crate::state::AppState;
use crate::time_format::format_datetime;
use asd_ipc_protocol::IpcCommand;
use serde::{Deserialize, Serialize};

use asd_domain::config::{PERIODIC_MODES, SEQUENCE_MODES, VALID_MODES};

fn extract_ipc_error(response: &asd_ipc_protocol::IpcMessage) -> AppError {
    let error_msg = response
        .data
        .as_ref()
        .and_then(|d| d.get("error"))
        .and_then(|v| v.as_str())
        .unwrap_or("AHK 返回错误响应");
    AppError::Ipc(error_msg.to_string())
}

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
    pub delays: Vec<u64>,
    pub mode: String,
}

/// 启动录制。
///
/// # TOCTOU 权衡
///
/// 采用"先状态后 IPC"模式：先在 `recording_mode` 写锁内设置状态，释放锁后发送 IPC。
/// 如果 IPC 失败，重新获取写锁回滚状态。在状态设置到 IPC 发送之间，
/// 其他线程会看到 `recording_mode = Some(...)` 而被拒绝，即使第一个录制即将回滚。
/// 当 AHK 子进程不可用时（IPC 超时 5 秒），此窗口可能持续数秒。
/// 这是可接受的权衡，因为加锁等待 IPC 会阻塞所有录制/验证操作。
pub fn start_recording(state: &AppState, group_id: &str, mode: &str) -> Result<(), AppError> {
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }
    if mode.trim().is_empty() {
        return Err(AppError::Validation("模式不能为空".to_string()));
    }

    if !VALID_MODES.contains(&mode) {
        return Err(AppError::Validation(format!("不支持的模式: '{}'", mode)));
    }

    {
        let mut mode_guard = state.recording_mode.write();
        if mode_guard.is_some() {
            return Err(AppError::Validation("已有录制正在进行，请先停止当前录制".to_string()));
        }
        // 在同一写锁内检查验证状态，防止录制和验证同时进行
        if state.validation_in_progress.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(AppError::Validation("验证进行中，无法启动录制".to_string()));
        }
        // 在写锁内验证分组存在性，防止与 delete_group_atomic 的 TOCTOU
        if state.get_group(group_id).is_none() {
            return Err(AppError::GroupNotFound(group_id.to_string()));
        }
        *mode_guard = Some(mode.to_string());
    }

    let cmd = IpcCommand::StartRecording {
        group_id: group_id.to_string(),
        mode: mode.to_string(),
    };
    if let Err(e) = state.send_ipc_command(&cmd) {
        {
            let mut mode_guard = state.recording_mode.write();
            *mode_guard = None;
        }
        return Err(e);
    }

    tracing::info!("开始录制: group={}, mode={}", group_id, mode);
    Ok(())
}

pub fn stop_recording(state: &AppState) -> Result<RecordingResult, AppError> {
    // 前置检查：是否正在录制
    {
        let mode_guard = state.recording_mode.read();
        if mode_guard.is_none() {
            return Err(AppError::Validation("没有正在进行的录制".to_string()));
        }
    }
    let cmd = IpcCommand::StopRecording;
    let response = match state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5)) {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("stop_recording IPC 失败，强制清理录制状态: {e}");
            // 先发送 StopRecording，再清除状态，避免 recording_mode 清除后
            // 并发 start_recording 成功但被后续 StopRecording 误停
            state.try_send_ipc_command(&IpcCommand::StopRecording);
            // 在 recording_mode 写锁内清理，与 stop_validation 保持一致的模式
            {
                let mut mode_guard = state.recording_mode.write();
                *mode_guard = None;
            }
            return Err(e);
        }
    };

    if response.is_error() {
        {
            let mut mode_guard = state.recording_mode.write();
            *mode_guard = None;
        }
        return Err(extract_ipc_error(&response));
    }

    tracing::info!("停止录制: seq={}", response.seq);

    // 解析响应数据。AHK 已停止录制，若解析失败需清理 Rust 侧 recording_mode，
    // 否则后续录制/验证操作会被永久阻塞
    let parse_result: Result<RecordingResult, AppError> = (|| {
        let keys = response
            .data
            .as_ref()
            .and_then(|d| d.get("keys"))
            .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
            .filter(|k| !k.is_empty())
            .ok_or_else(|| AppError::Ipc("录制响应缺少有效的按键序列".to_string()))?;

        let mode = response
            .data
            .as_ref()
            .and_then(|d| d.get("mode"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| AppError::Ipc("录制响应缺少 mode 字段".to_string()))?
            .to_string();

        if !VALID_MODES.contains(&mode.as_str()) {
            return Err(AppError::Ipc(format!("AHK 返回无效模式: '{}'", mode)));
        }

        let requested_mode = {
            let mut mode_guard = state.recording_mode.write();
            mode_guard.take()
        };
        if let Some(ref req_mode) = requested_mode {
            if req_mode != &mode {
                tracing::warn!(
                    "录制模式不一致: 请求='{}', AHK 返回='{}'，使用 AHK 返回值",
                    req_mode, mode
                );
            }
        }

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
    })();

    if let Err(e) = parse_result {
        // AHK 已停止录制，但响应数据异常，清理 Rust 侧状态
        {
            let mut mode_guard = state.recording_mode.write();
            *mode_guard = None;
        }
        return Err(e);
    }

    parse_result
}

/// # TOCTOU 权衡
///
/// `pause_recording` 和 `resume_recording` 使用 `recording_mode` 读锁做前置检查，
/// 释放锁后再发送 IPC 命令。在读锁释放到 IPC 发送之间的窗口内，并发的
/// `stop_recording` + `start_recording` 可能替换了录制会话，导致 pause/resume
/// 命令作用于新录制而非原始录制。此窗口极窄（微秒级），且影响有限
///（用户可手动恢复），当前作为已知权衡接受。
pub fn pause_recording(state: &AppState) -> Result<u64, AppError> {
    // 前置检查：是否正在录制
    {
        let mode_guard = state.recording_mode.read();
        if mode_guard.is_none() {
            return Err(AppError::Validation("没有正在进行的录制".to_string()));
        }
    }
    let cmd = IpcCommand::PauseRecording;
    let response = state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))?;

    if response.is_error() {
        return Err(extract_ipc_error(&response));
    }

    tracing::info!("暂停录制: seq={}", response.seq);
    Ok(response.seq)
}

pub fn resume_recording(state: &AppState) -> Result<u64, AppError> {
    // 前置检查：是否正在录制
    {
        let mode_guard = state.recording_mode.read();
        if mode_guard.is_none() {
            return Err(AppError::Validation("没有正在进行的录制".to_string()));
        }
    }
    let cmd = IpcCommand::ResumeRecording;
    let response = state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))?;

    if response.is_error() {
        return Err(extract_ipc_error(&response));
    }

    tracing::info!("恢复录制: seq={}", response.seq);
    Ok(response.seq)
}

fn validate_recording_data(mode: &str, keys: &[String], intervals: &[u64], delays: &[u64]) -> Result<(), AppError> {
    if keys.iter().any(|k| k.trim().is_empty()) {
        return Err(AppError::Validation("按键序列中不能包含空字符串".to_string()));
    }

    let needs_intervals = PERIODIC_MODES.contains(&mode);
    let needs_delays = SEQUENCE_MODES.contains(&mode);

    if needs_intervals && intervals.is_empty() {
        return Err(AppError::Validation("periodic 模式需要至少一个间隔".to_string()));
    }

    if needs_delays && delays.is_empty() {
        return Err(AppError::Validation("sequence 模式需要至少一个延迟".to_string()));
    }

    if intervals.contains(&0) {
        return Err(AppError::Validation("间隔不能为 0".to_string()));
    }

    if delays.contains(&0) {
        return Err(AppError::Validation("延迟不能为 0".to_string()));
    }

    Ok(())
}

pub fn export_recording(
    path: &str,
    keys: &[String],
    intervals: &[u64],
    delays: &[u64],
    mode: &str,
) -> Result<(), AppError> {
    validate_file_path(path)?;

    if keys.is_empty() {
        return Err(AppError::Validation("按键序列不能为空".to_string()));
    }

    if !VALID_MODES.contains(&mode) {
        return Err(AppError::Validation(format!(
            "不支持的模式: '{}'，有效模式: {}",
            mode, VALID_MODES.join(", ")
        )));
    }

    validate_recording_data(mode, keys, intervals, delays)?;

    let recording_data = serde_json::json!({
        "keys": keys,
        "intervals": intervals,
        "delays": delays,
        "mode": mode,
        "exportedAt": format_datetime(),
    });

    let json = serde_json::to_string_pretty(&recording_data)
        .map_err(|e| AppError::Config(format!("序列化录制数据失败: {e}")))?;

    let p = std::path::Path::new(path);
    atomic_write(p, &json).map_err(|e| AppError::Internal(format!("导出录制数据失败: {e}")))?;

    tracing::info!("录制结果已导出: {}", path);
    Ok(())
}

pub fn import_recording(path: &str) -> Result<ImportedRecording, AppError> {
    validate_file_path(path)?;

    // I26: 通过 ConfigRepository 委托文件 I/O（含 BOM 剥离）
    let cleaned = ConfigRepository::read_file_to_string(path)
        .map_err(AppError::Config)?;
    let data: serde_json::Value = serde_json::from_str(&cleaned)
        .map_err(|e| AppError::Config(format!("解析录制数据失败: {e}")))?;

    let keys = data
        .get("keys")
        .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
        .unwrap_or_default();

    if keys.is_empty() {
        return Err(AppError::Validation("录制数据缺少按键序列".to_string()));
    }

    let intervals = data
        .get("intervals")
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();

    let delays = data
        .get("delays")
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();

    let mode = data
        .get("mode")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::Validation("录制数据缺少 mode 字段".to_string()))?
        .to_string();

    if !VALID_MODES.contains(&mode.as_str()) {
        return Err(AppError::Validation(format!(
            "不支持的模式: '{}'，有效模式: {}",
            mode, VALID_MODES.join(", ")
        )));
    }

    validate_recording_data(&mode, &keys, &intervals, &delays)?;

    Ok(ImportedRecording {
        keys,
        intervals,
        delays,
        mode,
    })
}

pub fn start_validation(state: &AppState, group_id: &str) -> Result<u64, AppError> {
    if group_id.trim().is_empty() {
        return Err(AppError::Validation("分组 ID 不能为空".to_string()));
    }

    // 在 recording_mode 写锁保护下原子地检查录制状态、分组存在性并设置验证标志，
    // 消除与 start_recording/delete_group_atomic 的 TOCTOU 窗口。
    // 使用写锁而非读锁，因为 start_recording 也使用写锁，两者互斥。
    {
        let mode_guard = state.recording_mode.write();
        if mode_guard.is_some() {
            return Err(AppError::Validation("录制进行中，无法启动验证".to_string()));
        }
        // 在写锁内验证分组存在性，防止与 delete_group_atomic 的 TOCTOU
        if state.get_group(group_id).is_none() {
            return Err(AppError::GroupNotFound(group_id.to_string()));
        }
        // recording_mode 为 None 时，在释放写锁前设置 validation_in_progress
        // 注意：此处使用 compare_exchange 而非直接 store，防止并发验证
        state.validation_in_progress
            .compare_exchange(
                false, true,
                std::sync::atomic::Ordering::SeqCst,
                std::sync::atomic::Ordering::SeqCst,
            )
            .map_err(|_| AppError::Validation("已有验证正在进行，请先停止当前验证".to_string()))?;
    }

    let cmd = IpcCommand::StartValidation {
        group_id: group_id.to_string(),
    };
    let response = match state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5)) {
        Ok(r) => r,
        Err(e) => {
            // IPC 失败时回滚 validation_in_progress（"先状态后IPC"模式）
            // 在 recording_mode 写锁内回滚，与 stop_validation 和重连回调保持一致，
            // 防止并发 stop_validation 或重连回调同时操作 validation_in_progress
            {
                let _guard = state.recording_mode.write();
                state.validation_in_progress.compare_exchange(
                    true, false,
                    std::sync::atomic::Ordering::SeqCst,
                    std::sync::atomic::Ordering::SeqCst,
                ).ok();
            }
            return Err(e);
        }
    };
    // AHK 侧处理失败时回滚 validation_in_progress
    if response.is_error() {
        {
            let _guard = state.recording_mode.write();
            state.validation_in_progress.compare_exchange(
                true, false,
                std::sync::atomic::Ordering::SeqCst,
                std::sync::atomic::Ordering::SeqCst,
            ).ok();
        }
        return Err(extract_ipc_error(&response));
    }
    tracing::info!("启动验证: groupId={}, seq={}", group_id, response.seq);
    Ok(response.seq)
}

pub fn stop_validation(state: &AppState) -> Result<u64, AppError> {
    // 前置检查：验证是否正在进行
    if !state.validation_in_progress.load(std::sync::atomic::Ordering::SeqCst) {
        return Err(AppError::Validation("没有正在进行的验证".to_string()));
    }
    let cmd = IpcCommand::StopValidation;
    let response = match state.send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5)) {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("stop_validation IPC 失败，强制清理验证状态: {e}");
            // 在 recording_mode 写锁内清除 validation_in_progress，
            // 防止并发 start_validation 在此窗口内设置 true 被错误清除
            let _guard = state.recording_mode.write();
            state.validation_in_progress.compare_exchange(
                true, false,
                std::sync::atomic::Ordering::SeqCst,
                std::sync::atomic::Ordering::SeqCst,
            ).ok();
            return Err(e);
        }
    };
    // AHK 侧返回错误时仍强制清理验证状态
    if response.is_error() {
        tracing::warn!("stop_validation AHK 返回错误，强制清理验证状态");
        let _guard = state.recording_mode.write();
        state.validation_in_progress.compare_exchange(
            true, false,
            std::sync::atomic::Ordering::SeqCst,
            std::sync::atomic::Ordering::SeqCst,
        ).ok();
        return Err(extract_ipc_error(&response));
    }
    // 在 recording_mode 写锁内清除 validation_in_progress，
    // 防止并发 start_validation 在此窗口内设置 true 被错误清除。
    // start_validation 在同一写锁内检查 validation_in_progress，
    // 两者互斥，不会同时执行。
    //
    // 注意：compare_exchange 失败时（如 AHK 重连回调已并发清除），
    // IPC 已成功，验证确实已停止，因此不返回错误，仅记录警告。
    {
        let _guard = state.recording_mode.write();
        if state.validation_in_progress.compare_exchange(
            true, false,
            std::sync::atomic::Ordering::SeqCst,
            std::sync::atomic::Ordering::SeqCst,
        ).is_err() {
            tracing::warn!("stop_validation: validation_in_progress 已被并发清除（如 AHK 重连回调），IPC 已成功，验证已停止");
        }
    }
    tracing::info!("停止验证: seq={}", response.seq);
    Ok(response.seq)
}
