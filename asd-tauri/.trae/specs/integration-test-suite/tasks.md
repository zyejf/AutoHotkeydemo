# Tasks

- [x] Task 1: 创建 asd-test-harness 测试工具 crate
  - [x] SubTask 1.1: 创建 `crates/asd-test-harness/Cargo.toml`，声明对 asd-domain、asd-ipc-protocol、asd-application 的依赖和 tempfile dev-dependency
  - [x] SubTask 1.2: 创建 `crates/asd-test-harness/src/lib.rs`，将 `asd-application/tests/common/mod.rs` 中的 MockIpcSender、RecordingIpcSender、MockEventEmitter、MockProcessWatcher、make_test_config、make_test_state、make_test_state_with_recording_sender、make_test_state_with_path 提取为 pub 导出
  - [x] SubTask 1.3: 将 `src-tauri/src/tests/ipc_tests.rs` 中的 `unique_pipe_name` 函数提取到 test-harness 并 pub 导出
  - [x] SubTask 1.4: 在 workspace `Cargo.toml` 中添加 asd-test-harness 到 members 列表
  - [x] SubTask 1.5: 重构 `asd-application/tests/cross_crate_tests.rs` 和 `integration_tests.rs` 移除重复的 Mock 定义，改为 `use asd_test_harness::*`
  - [x] SubTask 1.6: 验证 `cargo test -p asd-test-harness` 和 `cargo test -p asd-application` 通过

- [x] Task 2: 新增 IPC 传输层边界条件测试
  - [x] SubTask 2.1: 在 `src-tauri/src/tests/ipc_tests.rs` 中新增 `test_message_size_limit_exceeded` 测试：发送超过 64KB 的消息，验证被拒绝且不崩溃
  - [x] SubTask 2.2: 新增 `test_message_size_boundary` 测试：发送恰好 64KB-1 字节的消息，验证正常处理
  - [x] SubTask 2.3: 新增 `test_auth_token_mismatch` 测试：模拟 AHK 发送错误的 auth token，验证连接被拒绝
  - [x] SubTask 2.4: 新增 `test_auth_wrong_message_type` 测试：模拟 AHK 首条消息发送 pong 而非 auth，验证连接被拒绝
  - [x] SubTask 2.5: 新增 `test_pipe_broken_reconnect` 测试：模拟管道断裂，验证 on_pipe_broken 回调触发
  - [x] SubTask 2.6: 新增 `test_heartbeat_timeout` 测试：模拟心跳超时，验证超时回调触发
  - [x] SubTask 2.7: 新增 `test_pending_responses_cleanup` 测试：验证 30 秒后 pending_responses 中的过期条目被清理
  - [x] SubTask 2.8: 验证 `cargo test -p asd-tauri --lib --features test-manifest` 通过

- [x] Task 3: 新增 AppState 并发安全测试
  - [x] SubTask 3.1: 在 `asd-application/tests/` 下新建 `concurrency_tests.rs`，使用 `std::thread` 和 `Arc` 创建并发测试
  - [x] SubTask 3.2: 实现 `test_concurrent_save_config_different_groups`：多线程同时修改不同分组，验证最终配置一致性
  - [x] SubTask 3.3: 实现 `test_concurrent_delete_group_different_groups`：多线程同时删除不同分组，验证所有删除生效
  - [x] SubTask 3.4: 实现 `test_concurrent_save_and_delete_same_group`：并发保存与删除同一分组，验证不出现不一致状态
  - [x] SubTask 3.5: 实现 `test_concurrent_sync_config_changes`：多线程并发触发 sync_config_changes_to_ahk，验证 IPC 命令不丢失/不重复（使用 RecordingIpcSender 断言）
  - [x] SubTask 3.6: 验证 `cargo test -p asd-application --test concurrency_tests` 通过

- [x] Task 4: 新增跨 crate 端到端数据流集成测试
  - [x] SubTask 4.1: 在 `asd-application/tests/` 下新建 `e2e_dataflow_tests.rs`
  - [x] SubTask 4.2: 实现 `test_config_change_to_ipc_command_full_flow`：验证 Config 更新 → AppState 状态变更 → sync_config_changes_to_ahk → IpcCommand 正确生成 → IpcMessage 序列化/反序列化往返
  - [x] SubTask 4.3: 实现 `test_recording_flow_full_dataflow`：验证 start_recording → key_record_event 解析 → stop_recording → RecordingResult 解析 → Config 保存
  - [x] SubTask 4.4: 实现 `test_group_toggle_to_toggle_command_flow`：验证分组激活/停用 → ToggleGroup IpcCommand 生成 → IpcMessage 封装 → AHK 端解析（模拟）
  - [x] SubTask 4.5: 实现 `test_hotkey_register_unregister_flow`：验证热键注册/注销 → RegisterHotkey/UnregisterHotkey 命令 → IpcMessage 往返
  - [x] SubTask 4.6: 验证 `cargo test -p asd-application --test e2e_dataflow_tests` 通过

- [x] Task 5: 新增 Bridge 层 trait 实现测试
  - [x] SubTask 5.1: 在 `src-tauri/src/tests/` 下新建 `bridge_tests.rs`
  - [x] SubTask 5.2: 实现 `test_ipc_bridge_send_and_wait_timeout`：验证 IpcBridge 超时返回错误并清理 pending entry
  - [x] SubTask 5.3: 实现 `test_ipc_bridge_send_and_wait_pipe_broken`：验证管道断裂时返回正确错误
  - [x] SubTask 5.4: 实现 `test_tauri_event_bridge_emit`：验证 TauriEventBridge.emit 正确转发事件（标记 #[ignore] 需 Tauri AppHandle）
  - [x] SubTask 5.5: 实现 `test_watchdog_bridge_get_state`：验证 WatchdogBridge.get_state 返回正确状态
  - [x] SubTask 5.6: 验证 `cargo test -p asd-tauri --lib --features test-manifest --test bridge_tests` 通过

- [x] Task 6: 新增 Watchdog 真实进程管理集成测试
  - [x] SubTask 6.1: 在 `src-tauri/src/tests/` 下新建 `watchdog_integration_tests.rs`
  - [x] SubTask 6.2: 实现 `test_watchdog_start_child_process`：使用简单的测试子进程（如 `cmd /c timeout 10`），验证子进程启动且状态为 Running
  - [x] SubTask 6.3: 实现 `test_watchdog_child_crash_restart`：启动短命子进程，验证 Watchdog 检测到退出并重启
  - [x] SubTask 6.4: 实现 `test_watchdog_restart_limit`：配置低重启上限（如 3 次），验证达到上限后状态变为 Failed
  - [x] SubTask 6.5: 实现 `test_watchdog_exponential_backoff`：验证重启间隔遵循指数退避（1s/2s/4s...）
  - [x] SubTask 6.6: 验证 `cargo test -p asd-tauri --lib --features test-manifest --test watchdog_integration_tests` 通过（标记 `#[ignore]` 避免在 CI 中默认运行慢测试）

- [x] Task 7: 新增录制服务 IPC 失败回滚和备份服务 I/O 错误测试
  - [x] SubTask 7.1: 在 `asd-application/tests/recording_service_tests.rs` 中新增 `test_start_recording_ipc_failure_rollback`：使用返回错误的 MockIpcSender，验证 recording_mode 被回滚为 None
  - [x] SubTask 7.2: 在 `asd-application/tests/backup_service_tests.rs` 中新增 `test_backup_to_readonly_directory`：使用只读目录验证备份写入失败的错误处理
  - [x] SubTask 7.3: 新增 `test_restore_from_corrupted_backup`：使用损坏的备份文件验证恢复失败的错误处理
  - [x] SubTask 7.4: 验证 `cargo test -p asd-application --test recording_service_tests --test backup_service_tests` 通过

- [x] Task 8: 创建 CI/CD 配置和测试运行脚本
  - [x] SubTask 8.1: 创建 `.github/workflows/ci.yml`，配置 push/PR 触发、Rust toolchain、缓存、测试执行步骤
  - [x] SubTask 8.2: 在 CI 中配置按 crate 分步执行测试：asd-domain → asd-ipc-protocol → asd-application → asd-tauri（带 test-manifest feature）
  - [x] SubTask 8.3: 在 CI 中配置测试结果上传和覆盖率报告（cargo-tarpaulin 或 llvm-cov）
  - [x] SubTask 8.4: 创建 `scripts/run-tests.ps1` 脚本：支持 `-Quick` 参数，按顺序执行各层测试，汇总结果并输出报告
  - [x] SubTask 8.5: 在脚本中支持区分快速测试（单元+快速集成）和全量测试（含 watchdog 真实进程测试）
  - [x] SubTask 8.6: 验证 `.\scripts\run-tests.ps1 -Quick` 本地执行通过

# Task Dependencies
- [Task 2] depends on [Task 1]（IPC 边界条件测试需要 test-harness 的 unique_pipe_name）
- [Task 3] depends on [Task 1]（并发测试需要 test-harness 的 Mock 工具）
- [Task 4] depends on [Task 1]（端到端测试需要 test-harness 的测试工厂函数）
- [Task 5] depends on [Task 1]（Bridge 测试需要 test-harness 的 Mock 工具）
- [Task 6] 依赖 [Task 1]（watchdog 集成测试可能需要 test-harness 工具）
- [Task 7] 依赖 [Task 1]（录制/备份测试需要 test-harness 的 Mock 工具）
- [Task 8] 可与 Task 2-7 并行（CI 配置和脚本不依赖具体测试内容）
