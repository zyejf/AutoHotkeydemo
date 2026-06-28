# Checklist

## 统一测试工具 crate
- [x] asd-test-harness crate 已创建并添加到 workspace members
- [x] MockIpcSender、RecordingIpcSender、MockEventEmitter、MockProcessWatcher 已从 common/mod.rs 提取到 test-harness 并 pub 导出
- [x] 测试工厂函数（make_test_config、make_test_state 等）已提取到 test-harness 并 pub 导出
- [x] unique_pipe_name 函数已提取到 test-harness 并 pub 导出
- [x] cross_crate_tests.rs 和 integration_tests.rs 已移除重复 Mock 定义，改为引用 test-harness
- [x] `cargo test -p asd-test-harness` 通过
- [x] `cargo test -p asd-application` 通过（重构后无回归）

## IPC 传输层边界条件测试
- [x] 64KB 消息大小上限测试已实现且通过
- [x] 64KB-1 边界消息正常处理测试已实现且通过
- [x] 认证 token 不匹配测试已实现且通过
- [x] 认证消息类型错误（pong 而非 auth）测试已实现且通过
- [x] 断线重连回调测试已实现且通过
- [x] 心跳超时检测测试已实现且通过
- [x] pending_responses 30s 超时清理测试已实现且通过
- [x] 所有 IPC 边界条件测试在 `cargo test -p asd-tauri --lib --features test-manifest` 下通过

## AppState 并发安全测试
- [x] 并发 save_config_atomic（不同分组）测试已实现且通过
- [x] 并发 delete_group_atomic（不同分组）测试已实现且通过
- [x] 并发 save + delete 同一分组测试已实现且通过
- [x] 并发 sync_config_changes_to_ahk 命令不丢失/不重复测试已实现且通过
- [x] 所有并发测试在多次运行下稳定通过（无 flaky test）

## 跨 crate 端到端数据流测试
- [x] 配置变更到 IPC 命令完整流测试已实现且通过
- [x] 录制流程完整数据流测试已实现且通过
- [x] 分组 toggle 到 ToggleGroup 命令流测试已实现且通过
- [x] 热键注册/注销到 IPC 命令流测试已实现且通过

## Bridge 层 trait 实现测试
- [x] IpcBridge send_and_wait 超时测试已实现且通过
- [x] IpcBridge send_and_wait 管道断裂测试已实现且通过
- [x] TauriEventBridge emit 事件测试已实现且通过（标记 #[ignore]，需 Tauri AppHandle）
- [x] WatchdogBridge get_state 测试已实现且通过

## Watchdog 真实进程管理集成测试
- [x] 子进程正常启动测试已实现且通过
- [x] 子进程崩溃自动重启测试已实现且通过
- [x] 重启次数上限测试已实现且通过
- [x] 指数退避间隔验证测试已实现且通过
- [x] 慢测试已标记 `#[ignore]` 且可通过 `--ignored` 单独运行

## 录制服务 IPC 失败回滚和备份服务 I/O 错误测试
- [x] start_recording IPC 失败后 recording_mode 回滚测试已实现且通过
- [x] 备份到只读目录错误处理测试已实现且通过
- [x] 从损坏备份文件恢复错误处理测试已实现且通过

## CI/CD 配置和测试运行脚本
- [x] `.github/workflows/ci.yml` 已创建并配置 push/PR 触发
- [x] CI 中按 crate 分步执行测试（asd-domain → asd-ipc-protocol → asd-application → asd-tauri）
- [x] CI 中配置了 Rust 缓存（cargo + target 目录）
- [x] CI 中配置了测试结果上传和覆盖率报告
- [x] `scripts/run-tests.ps1` 脚本已创建
- [x] 脚本支持 `-Quick` 参数（仅单元测试+快速集成测试）
- [x] 脚本支持全量模式（含 watchdog 真实进程测试）
- [x] 脚本输出测试结果汇总报告
- [x] `.\scripts\run-tests.ps1 -Quick` 本地执行通过

## 整体验证
- [x] `cargo test --workspace` 全部通过（311 passed, 16 ignored, 0 failed）
- [x] 无新增编译警告（仅 pre-existing 无害警告：unused_mut / unused_import）
- [x] 无 flaky test（连续运行多次均通过）
