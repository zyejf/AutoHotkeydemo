# Tasks

- [ ] Task 1: 添加 recording_service IPC 失败回滚测试
  - [ ] SubTask 1.1: 在 `asd-tauri/crates/asd-application/tests/recording_service_tests.rs` 末尾定义 `FailingIpcSender` struct，实现 `IpcSender` trait（`send_command` 返回 `Err("IPC 发送失败".to_string())`，`send_and_wait`/`send_message` 返回 `Err`）
  - [ ] SubTask 1.2: 添加 `test_start_recording_ipc_failure_rollback` 测试：用 `FailingIpcSender` 构造 AppState（需 `use asd_application::state::AppState;` + `use asd_domain::traits::IpcSender;` + `use std::sync::Arc;`），调用 `recording_service::start_recording(&state, "1", "periodic")`，断言 `matches!(result, Err(AppError::Ipc(_)))` 且 `state.recording_mode.read().is_none()`

- [ ] Task 2: 添加 backup_service 只读目录错误测试
  - [ ] SubTask 2.1: 在 `asd-tauri/crates/asd-application/tests/backup_service_tests.rs` 添加 `test_backup_to_readonly_directory`：用 `make_test_state_with_path()` 获取临时目录，在 `dir.path().join("backups")` 路径上用 `std::fs::write` 创建文件（内容 "not a directory"），调用 `create_backup(&state)`，断言 `result.is_err()`

- [ ] Task 3: 添加 backup_service 损坏备份恢复测试
  - [ ] SubTask 3.1: 在 `asd-tauri/crates/asd-application/tests/backup_service_tests.rs` 添加 `test_restore_from_corrupted_backup`：用 `make_test_state_with_path()`，手动 `std::fs::create_dir_all(dir.path().join("backups"))`，写入无效 JSON `{invalid json content!!!}` 到 `backup_20260101_120000.json`，调用 `restore_backup(&state, "backup_20260101_120000.json")`，断言 `result.is_err()`

- [ ] Task 4: 验证编译与非忽略测试通过
  - [ ] SubTask 4.1: 运行 `cargo test -p asd-tauri --lib --features test-manifest --no-run` 确认 bridge + watchdog 测试编译通过
  - [ ] SubTask 4.2: 运行 `cargo test -p asd-application --test recording_service_tests --test backup_service_tests --no-run` 确认错误路径测试编译通过
  - [ ] SubTask 4.3: 运行 `cargo test -p asd-application --test recording_service_tests --test backup_service_tests` 确认非忽略测试通过

# Task Dependencies

- [Task 1, Task 2, Task 3] 互相独立，可并行执行
- [Task 4] 依赖 [Task 1, Task 2, Task 3] 全部完成
