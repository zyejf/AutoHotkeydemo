use crate::backup_service::validate_file_path;
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
/// # Errors
///
/// - `Validation`：`group_id` / `mode` 为空（含纯空白）、`mode` 不在 `VALID_MODES` 内、
///   已有录制正在进行，或验证进行中（录制与验证互斥）。
/// - `GroupNotFound`：分组不存在（在写锁内检查，防止与删除操作的 TOCTOU）。
/// - `Ipc`：IPC 发送失败，**此时 `recording_mode` 已回滚为 `None`**，可直接重试。
///
/// ⚠️ 本函数走的是 `send_ipc_command`（**不等响应**），所以 `Ok(())` 只表示
/// 「命令已发出」，**不代表 AHK 侧真的开始了录制** —— AHK 侧处理失败不会反映到
/// 返回值里，只有传输层失败才会。这是本文件里唯一一个不等响应的接口。
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
        return Err(AppError::Validation(format!("不支持的模式: '{mode}'")));
    }

    {
        let mut mode_guard = state.recording_mode.write();
        if mode_guard.is_some() {
            return Err(AppError::Validation(
                "已有录制正在进行，请先停止当前录制".to_string(),
            ));
        }
        // 在同一写锁内检查验证状态，防止录制和验证同时进行
        if state
            .validation_in_progress
            .load(std::sync::atomic::Ordering::SeqCst)
        {
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

/// 停止录制，返回 AHK 侧采集到的录制结果。
///
/// # Errors
///
/// - `Validation`：没有正在进行的录制。
/// - `Ipc`：三种情形，**三种都会把 `recording_mode` 清成 `None`**：
///   - IPC 通信失败（超时 5 秒）—— 会先尽力补发一次 `StopRecording`（走
///     `try_send_ipc_command`，失败只记日志）再清理；
///   - AHK 返回错误响应；
///   - AHK 已停止录制但响应数据无法解析（缺少按键序列 / 缺少 `mode` / 模式无效）。
///
/// ⚠️ 拿到 `Err` 时录制状态**已被清空**，所以不要用 `Err` 去重试 `stop_recording`
/// —— 重试只会得到 `Validation`（没有正在进行的录制）。此时应按「Rust 侧状态已清、
/// AHK 侧可能仍在录」处理，用户角度需要一次人工确认。
///
/// 另：请求时的模式与 AHK 返回的模式不一致时**不报错**，只记 `warn` 并以 AHK 的
/// 返回值为准（`RecordingResult::mode` 取自响应）。
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
            return Err(AppError::Ipc(format!("AHK 返回无效模式: '{mode}'")));
        }

        let requested_mode = {
            let mut mode_guard = state.recording_mode.write();
            mode_guard.take()
        };
        if let Some(ref req_mode) = requested_mode {
            if req_mode != &mode {
                tracing::warn!(
                    "录制模式不一致: 请求='{}', AHK 返回='{}'，使用 AHK 返回值",
                    req_mode,
                    mode
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
///
/// # Errors
///
/// - `Validation`：没有正在进行的录制。
/// - `Ipc`：IPC 通信失败（超时 5 秒）或 AHK 返回错误响应。
///
/// ⚠️ 与 `stop_recording` 不同：失败时**不会**清理 `recording_mode` ——
/// 暂停失败不意味着录制会话结束，调用方仍可重试，或改用 `stop_recording` 兜底。
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

/// 恢复被 [`pause_recording`] 暂停的录制。
///
/// 与 `pause_recording` 共享同一份 TOCTOU 权衡（见该函数上方说明）。
///
/// # Errors
///
/// - `Validation`：没有正在进行的录制。
/// - `Ipc`：IPC 通信失败（超时 5 秒）或 AHK 返回错误响应。
///
/// ⚠️ 与 `stop_recording` 不同：失败时**不会**清理 `recording_mode`，可安全重试。
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

fn validate_recording_data(
    mode: &str,
    keys: &[String],
    intervals: &[u64],
    delays: &[u64],
) -> Result<(), AppError> {
    if keys.iter().any(|k| k.trim().is_empty()) {
        return Err(AppError::Validation(
            "按键序列中不能包含空字符串".to_string(),
        ));
    }

    let needs_intervals = PERIODIC_MODES.contains(&mode);
    let needs_delays = SEQUENCE_MODES.contains(&mode);

    if needs_intervals && intervals.is_empty() {
        return Err(AppError::Validation(
            "periodic 模式需要至少一个间隔".to_string(),
        ));
    }

    if needs_delays && delays.is_empty() {
        return Err(AppError::Validation(
            "sequence 模式需要至少一个延迟".to_string(),
        ));
    }

    if intervals.contains(&0) {
        return Err(AppError::Validation("间隔不能为 0".to_string()));
    }

    if delays.contains(&0) {
        return Err(AppError::Validation("延迟不能为 0".to_string()));
    }

    Ok(())
}

/// 把一条录制结果导出成 JSON 文件。
///
/// # Errors
///
/// - `Validation`：`keys` 为空、`mode` 不在 `VALID_MODES` 内，或录制数据本身不合法
///   （按键含空串、periodic 缺间隔、sequence 缺延迟、间隔或延迟为 0）。
/// - `Config`：路径不合法（非绝对路径、含 `..`、UNC 或设备路径前缀、扩展名不是
///   `.json`），或录制数据序列化失败。
/// - `Internal`：写盘失败。
///
/// 三个变体是刻意区分的：`Config` 属于「调用方传错了，重试也一样错」，
/// `Internal` 属于「文件系统这一刻出了问题，可以重试」。写盘走 `atomic_write`，
/// **不会留下半成品文件** —— 失败时目标文件保持导出前的状态。
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
            mode,
            VALID_MODES.join(", ")
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
    ConfigRepository::atomic_write(p, &json)
        .map_err(|e| AppError::Internal(format!("导出录制数据失败: {e}")))?;

    tracing::info!("录制结果已导出: {}", path);
    Ok(())
}

/// 从 JSON 文件导入一条录制结果（读取时会自动剥离 BOM）。
///
/// # Errors
///
/// - `Config`：路径不合法（同 [`export_recording`]）、文件读取失败，或内容不是合法
///   JSON。
/// - `Validation`：文件里没有可用的 `keys`（字段缺失或为空数组）、缺少 `mode` 字段、
///   `mode` 不在 `VALID_MODES` 内，或数据不合法（判据同 [`export_recording`]）。
///
/// ⚠️ `keys` / `intervals` / `delays` 的**类型不匹配会静默降级为空数组**，而不是报
/// 类型错误 —— 例如 `"keys": [1, 2]` 会得到空的 `keys`，最终报成「录制数据缺少
/// 按键序列」。排查导入失败时不能只看错误信息，要看原始 JSON。
pub fn import_recording(path: &str) -> Result<ImportedRecording, AppError> {
    validate_file_path(path)?;

    // I26: 通过 ConfigRepository 委托文件 I/O（含 BOM 剥离）
    let cleaned = ConfigRepository::read_file_to_string(path).map_err(AppError::Config)?;
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
            mode,
            VALID_MODES.join(", ")
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

/// 启动验证（与录制互斥）。
///
/// # Errors
///
/// - `Validation`：`group_id` 为空（含纯空白）、已有录制正在进行，或已有验证正在
///   进行（并发保护靠 `validation_in_progress` 的 `compare_exchange`，后到者失败）。
/// - `GroupNotFound`：分组不存在（在写锁内检查，防止与删除操作的 TOCTOU）。
/// - `Ipc`：IPC 通信失败或 AHK 返回错误响应。
///
/// ⚠️ 上面两种 `Ipc` 情形**都会把 `validation_in_progress` 回滚为 `false`**，
/// 所以拿到 `Err` 时可以直接重试，不存在「标志卡死导致永远报已有验证正在进行」。
/// 回滚本身走 `compare_exchange(...).ok()`：若已被并发清除（如 AHK 重连回调）
/// 则跳过，不影响返回值。
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
        state
            .validation_in_progress
            .compare_exchange(
                false,
                true,
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
                state
                    .validation_in_progress
                    .compare_exchange(
                        true,
                        false,
                        std::sync::atomic::Ordering::SeqCst,
                        std::sync::atomic::Ordering::SeqCst,
                    )
                    .ok();
            }
            return Err(e);
        }
    };
    // AHK 侧处理失败时回滚 validation_in_progress
    if response.is_error() {
        {
            let _guard = state.recording_mode.write();
            state
                .validation_in_progress
                .compare_exchange(
                    true,
                    false,
                    std::sync::atomic::Ordering::SeqCst,
                    std::sync::atomic::Ordering::SeqCst,
                )
                .ok();
        }
        return Err(extract_ipc_error(&response));
    }
    tracing::info!("启动验证: groupId={}, seq={}", group_id, response.seq);
    Ok(response.seq)
}

/// 停止验证。
///
/// # Errors
///
/// - `Validation`：`validation_in_progress` 为 `false`，即没有正在进行的验证。
/// - `Ipc`：IPC 通信失败（超时 5 秒）或 AHK 返回错误响应。
///
/// ⚠️ 与 [`stop_recording`] 同构：**无论成功还是失败都强制清理
/// `validation_in_progress`** —— 宁可让 Rust 侧标志与实际状态不一致，也不能让
/// 标志卡住使后续 `start_validation` 永远失败。AHK 侧是否真的停下来无法从这里确认。
///
/// 另：`compare_exchange` 失败（例如 AHK 重连回调已并发清除）**不算错误**，只记
/// `warn` —— 那时 IPC 已成功，验证确实停了。
pub fn stop_validation(state: &AppState) -> Result<u64, AppError> {
    // 前置检查：验证是否正在进行
    if !state
        .validation_in_progress
        .load(std::sync::atomic::Ordering::SeqCst)
    {
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
            state
                .validation_in_progress
                .compare_exchange(
                    true,
                    false,
                    std::sync::atomic::Ordering::SeqCst,
                    std::sync::atomic::Ordering::SeqCst,
                )
                .ok();
            return Err(e);
        }
    };
    // AHK 侧返回错误时仍强制清理验证状态
    if response.is_error() {
        tracing::warn!("stop_validation AHK 返回错误，强制清理验证状态");
        let _guard = state.recording_mode.write();
        state
            .validation_in_progress
            .compare_exchange(
                true,
                false,
                std::sync::atomic::Ordering::SeqCst,
                std::sync::atomic::Ordering::SeqCst,
            )
            .ok();
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
        if state
            .validation_in_progress
            .compare_exchange(
                true,
                false,
                std::sync::atomic::Ordering::SeqCst,
                std::sync::atomic::Ordering::SeqCst,
            )
            .is_err()
        {
            tracing::warn!("stop_validation: validation_in_progress 已被并发清除（如 AHK 重连回调），IPC 已成功，验证已停止");
        }
    }
    tracing::info!("停止验证: seq={}", response.seq);
    Ok(response.seq)
}
