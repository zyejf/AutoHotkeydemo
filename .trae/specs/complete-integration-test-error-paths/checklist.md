# Checklist

- [ ] `test_start_recording_ipc_failure_rollback` 测试已添加到 recording_service_tests.rs
- [ ] FailingIpcSender mock 正确实现 IpcSender trait（send_command 返回 Err）
- [ ] 测试验证 start_recording 返回 Err(AppError::Ipc(_))
- [ ] 测试验证 recording_mode 被回滚为 None
- [ ] `test_backup_to_readonly_directory` 测试已添加到 backup_service_tests.rs
- [ ] 测试通过在 backups 路径创建文件模拟不可写目录
- [ ] 测试验证 create_backup 返回 Err
- [ ] `test_restore_from_corrupted_backup` 测试已添加到 backup_service_tests.rs
- [ ] 测试写入无效 JSON 到 backup_xxx.json
- [ ] 测试验证 restore_backup 返回 Err
- [ ] `cargo test -p asd-tauri --lib --features test-manifest --no-run` 编译通过
- [ ] `cargo test -p asd-application --test recording_service_tests --test backup_service_tests --no-run` 编译通过
- [ ] `cargo test -p asd-application --test recording_service_tests --test backup_service_tests` 非忽略测试通过
