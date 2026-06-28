# 补全集成测试错误路径 Spec

## Why
Tauri 集成测试套件的 Tasks 5、6、7 中，Task 5（bridge_tests.rs）与 Task 6（watchdog_integration_tests.rs）已完成。Task 7（应用层错误路径测试）尚未完成：`recording_service_tests.rs` 缺少 IPC 失败回滚测试，`backup_service_tests.rs` 缺少只读目录与损坏备份恢复测试。补全这些错误路径测试可提升 asd-application crate 的覆盖率，验证"先状态后 IPC"回滚模式与文件系统错误处理。

## What Changes
- 在 `asd-tauri/crates/asd-application/tests/recording_service_tests.rs` 添加 `test_start_recording_ipc_failure_rollback`：定义 `FailingIpcSender` mock（`send_command` 返回 `Err`），构造 AppState，调用 `start_recording`，验证返回 `Err(AppError::Ipc(_))` 且 `recording_mode` 被回滚为 `None`
- 在 `asd-tauri/crates/asd-application/tests/backup_service_tests.rs` 添加 `test_backup_to_readonly_directory`：在备份目录路径上创建文件阻塞 `create_dir_all`/写入，验证 `create_backup` 返回错误
- 在 `asd-tauri/crates/asd-application/tests/backup_service_tests.rs` 添加 `test_restore_from_corrupted_backup`：写入无效 JSON 到 `backup_xxx.json`，验证 `restore_backup` 返回错误

## Impact
- Affected specs: 无（纯测试新增，不修改生产代码）
- Affected code:
  - `asd-tauri/crates/asd-application/tests/recording_service_tests.rs`（新增 1 测试 + FailingIpcSender mock）
  - `asd-tauri/crates/asd-application/tests/backup_service_tests.rs`（新增 2 测试）

## ADDED Requirements
### Requirement: Recording IPC 失败回滚测试
测试 SHALL 验证 `start_recording` 在 IPC 发送失败时回滚 `recording_mode` 为 `None`。

#### Scenario: IPC send_command 返回错误
- **WHEN** 使用 `FailingIpcSender`（`send_command` 返回 `Err`）构造 AppState
- **AND** 调用 `start_recording(&state, "1", "periodic")`
- **THEN** 返回 `Err(AppError::Ipc(_))`
- **AND** `state.recording_mode.read().is_none()` 为 true（已回滚）

### Requirement: 备份只读目录错误测试
测试 SHALL 验证 `create_backup` 在备份目录不可写时返回错误。

#### Scenario: 备份目录路径被文件占用
- **WHEN** 在配置目录下创建名为 `backups` 的文件（非目录）
- **AND** 调用 `create_backup(&state)`
- **THEN** 返回 `Err`（写入失败）

### Requirement: 损坏备份恢复错误测试
测试 SHALL 验证 `restore_backup` 在备份文件包含无效 JSON 时返回错误。

#### Scenario: 备份文件内容为无效 JSON
- **WHEN** 创建名为 `backup_20260101_120000.json` 的文件，内容为 `{invalid json content!!!}`
- **AND** 调用 `restore_backup(&state, "backup_20260101_120000.json")`
- **THEN** 返回 `Err`（解析失败）
