mod common;

use asd_application::error::AppError;
use asd_application::recording_service;
use common::*;

#[test]
fn test_start_recording() {
    let state = make_test_state();
    let result = recording_service::start_recording(&state, "1", "periodic");
    assert!(result.is_ok(), "开始录制应成功: {:?}", result);
}

#[test]
fn test_start_recording_group_not_found() {
    let state = make_test_state();
    let result = recording_service::start_recording(&state, "999", "periodic");
    assert!(
        matches!(result, Err(AppError::GroupNotFound(_))),
        "不存在的分组应返回 GroupNotFound 错误"
    );
}

#[test]
fn test_stop_recording() {
    let state = make_test_state();
    recording_service::start_recording(&state, "1", "periodic").unwrap();
    let result = recording_service::stop_recording(&state);
    assert!(result.is_ok(), "停止录制应成功: {:?}", result);
    let recording = result.unwrap();
    assert_eq!(recording.seq, 1);
    assert_eq!(recording.keys, vec!["1", "2"]);
    assert_eq!(recording.mode, "periodic");
    assert_eq!(recording.intervals, vec![50, 100]);
    assert!(recording.delays.is_empty());
}

#[test]
fn test_pause_recording() {
    let state = make_test_state();
    recording_service::start_recording(&state, "1", "periodic").unwrap();
    let result = recording_service::pause_recording(&state);
    assert!(result.is_ok(), "暂停录制应成功: {:?}", result);
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_resume_recording() {
    let state = make_test_state();
    recording_service::start_recording(&state, "1", "periodic").unwrap();
    recording_service::pause_recording(&state).unwrap();
    let result = recording_service::resume_recording(&state);
    assert!(result.is_ok(), "恢复录制应成功: {:?}", result);
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_export_import_recording() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("recording.json");
    let path_str = path.to_str().unwrap();

    let keys = vec!["1".to_string(), "2".to_string()];
    let intervals = vec![50, 100];
    let delays: Vec<u64> = vec![];
    let mode = "periodic";

    let export_result =
        recording_service::export_recording(path_str, &keys, &intervals, &delays, mode);
    assert!(export_result.is_ok(), "导出录制应成功: {:?}", export_result);

    let import_result = recording_service::import_recording(path_str);
    assert!(import_result.is_ok(), "导入录制应成功: {:?}", import_result);
    let imported = import_result.unwrap();
    assert_eq!(imported.keys, vec!["1", "2"]);
    assert_eq!(imported.intervals, vec![50, 100]);
    assert_eq!(imported.mode, "periodic");
}

#[test]
fn test_import_recording_not_found() {
    let result = recording_service::import_recording("/nonexistent/path/recording.json");
    assert!(result.is_err(), "导入不存在的文件应返回错误");
}

#[test]
fn test_import_recording_invalid_json() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("bad.json");
    std::fs::write(&path, "{invalid json!!!}").unwrap();
    let result = recording_service::import_recording(path.to_str().unwrap());
    assert!(result.is_err(), "导入无效 JSON 应返回错误");
}

#[test]
fn test_start_validation() {
    let state = make_test_state();
    let result = recording_service::start_validation(&state, "1");
    assert!(result.is_ok(), "启动验证应成功: {:?}", result);
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_stop_validation() {
    let state = make_test_state();
    recording_service::start_validation(&state, "1").unwrap();
    let result = recording_service::stop_validation(&state);
    assert!(result.is_ok(), "停止验证应成功: {:?}", result);
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_start_recording_ipc_failure_rollback() {
    use asd_application::state::AppState;
    use std::sync::Arc;

    /// 总是返回错误的 IPC 发送器 Mock，用于测试 IPC 失败时的回滚逻辑。
    ///
    /// `start_recording` 采用"先状态后 IPC"模式：先在 recording_mode 写锁内
    /// 设置状态，释放锁后发送 IPC。如果 IPC 失败，重新获取写锁回滚状态。
    /// 此测试验证回滚逻辑正确执行，recording_mode 在 IPC 失败后为 None。
    struct FailingIpcSender;
    impl IpcSender for FailingIpcSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Err("模拟 IPC 通信失败：AHK 子进程不可用".to_string())
        }
        fn send_and_wait(
            &self,
            _cmd: IpcCommand,
            _timeout: std::time::Duration,
        ) -> Result<IpcMessage, String> {
            Err("模拟 IPC 通信失败：AHK 子进程不可用".to_string())
        }
        fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> {
            Err("模拟 IPC 通信失败：AHK 子进程不可用".to_string())
        }
    }

    let config = make_test_config();
    let state = Arc::new(AppState::new(
        config,
        Arc::new(FailingIpcSender),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter::new()),
    ));

    // 前置验证：recording_mode 初始为 None
    assert!(
        state.recording_mode.read().is_none(),
        "录制模式初始应为 None"
    );

    // 调用 start_recording，IPC 应失败
    let result = recording_service::start_recording(&state, "1", "periodic");
    assert!(result.is_err(), "IPC 失败时 start_recording 应返回错误");
    assert!(
        matches!(result, Err(AppError::Ipc(_))),
        "应返回 Ipc 错误，实际: {:?}",
        result
    );

    // 关键验证：IPC 失败后 recording_mode 应被回滚为 None
    // 防止状态泄漏导致后续录制/验证操作被永久阻塞
    assert!(
        state.recording_mode.read().is_none(),
        "IPC 失败后 recording_mode 应被回滚为 None（防止状态泄漏）"
    );
}
