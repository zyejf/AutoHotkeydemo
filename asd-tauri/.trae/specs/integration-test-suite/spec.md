# 自动化集成测试套件 Spec

## Why
当前项目拥有 461 个测试函数，但存在关键覆盖缺口：无 CI/CD 自动化、无端到端 IPC 测试、无并发安全测试、IPC 边界条件（消息大小上限、认证失败、断线重连、心跳超时）未覆盖、测试工具重复定义且未跨 crate 共享。需要一套全面的自动化集成测试方案来验证系统各模块间的交互功能和数据流转的正确性，保障系统集成质量。

## What Changes
- 新建 `crates/asd-test-harness` 测试工具 crate，统一管理 Mock 实现、测试工厂函数和 IPC 测试辅助工具，消除现有代码重复
- 新增 IPC 传输层边界条件测试：64KB 消息上限、认证流程、断线重连、心跳超时、pending_responses 30s 清理
- 新增 AppState 并发安全测试：并发 save_config_atomic、并发 delete_group_atomic、sync_config_changes_to_ahk 竞态条件
- 新增跨 crate 端到端集成测试：Config → Validator → AppState → IpcCommand → IpcMessage 完整数据流
- 新增 Bridge 层 trait 实现测试：IpcBridge(IpcSender)、TauriEventBridge(EventEmitter)、WatchdogBridge(ProcessWatcher)
- 新增 Watchdog 真实进程管理集成测试：子进程启动/崩溃/重启/指数退避/10 次上限
- 新增录制服务 IPC 失败回滚测试：start_recording IPC 失败后的状态回滚验证
- 新增备份服务 I/O 错误路径测试：磁盘满、权限不足场景
- 新增 CI/CD 配置（GitHub Actions）：自动化触发、执行、覆盖率收集、结果报告
- 新增测试运行脚本：一键执行全部测试套件并生成报告

## Impact
- Affected specs: 无现有 spec
- Affected code:
  - `crates/asd-application/tests/common/mod.rs`（提取到 asd-test-harness）
  - `crates/asd-application/tests/cross_crate_tests.rs`（复用 test-harness）
  - `crates/asd-application/tests/integration_tests.rs`（复用 test-harness）
  - `src-tauri/src/tests/ipc_tests.rs`（新增边界条件测试）
  - `src-tauri/src/tests/config_compat_tests.rs`（保持不变）
  - `Cargo.toml`（新增 asd-test-harness crate）
  - `src-tauri/Cargo.toml`（新增 dev-dependency）
  - `.github/workflows/ci.yml`（新建）

## ADDED Requirements

### Requirement: 统一测试工具 crate
系统 SHALL 提供 `asd-test-harness` crate，统一管理所有跨 crate 共享的测试工具，包括 MockIpcSender、RecordingIpcSender、MockEventEmitter、MockProcessWatcher、测试配置工厂函数和 IPC 管道测试辅助函数。

#### Scenario: 跨 crate 测试复用 Mock 实现
- **WHEN** 开发者在任意 crate 的测试中需要 Mock IpcSender
- **THEN** 应能从 `asd_test_harness` crate 导入并使用 `MockIpcSender`，无需重复定义

#### Scenario: IPC 管道测试辅助
- **WHEN** 测试需要创建唯一命名的 IPC 管道
- **THEN** 应能调用 `asd_test_harness::unique_pipe_name(tag)` 获取唯一管道名

### Requirement: IPC 传输层边界条件测试
系统 SHALL 覆盖 IPC 传输层的关键边界条件和异常场景，包括消息大小上限、认证流程、断线重连、心跳超时和 pending_responses 超时清理。

#### Scenario: 64KB 消息大小上限
- **WHEN** IPC 消息大小超过 64KB (65536 字节)
- **THEN** 消息应被拒绝或截断，且不崩溃

#### Scenario: 64KB 边界消息正常处理
- **WHEN** IPC 消息大小恰好为 64KB - 1 字节
- **THEN** 消息应被正常接收和解析

#### Scenario: 认证 token 不匹配
- **WHEN** AHK 连接时发送的 auth token 与 Rust 生成的 token 不匹配
- **THEN** 连接应被拒绝，记录警告日志

#### Scenario: 认证消息类型错误
- **WHEN** AHK 连接时首条消息类型不是 auth（如 pong）
- **THEN** 连接应被拒绝，记录 "期望 auth" 警告

#### Scenario: 断线重连
- **WHEN** IPC 管道在通信过程中断裂
- **THEN** on_pipe_broken 回调应被触发，IpcManager 应进入重连状态

#### Scenario: 心跳超时检测
- **WHEN** 超过心跳超时时间未收到 heartbeat 或 pong
- **THEN** 应触发心跳超时回调

#### Scenario: pending_responses 超时清理
- **WHEN** pending_responses 中的条目超过 30 秒未收到响应
- **THEN** 该条目应被自动清理，对应的 oneshot 通道应被关闭

### Requirement: AppState 并发安全测试
系统 SHALL 验证 AppState 在并发访问下的线程安全和数据一致性。

#### Scenario: 并发原子保存配置
- **WHEN** 多个线程同时调用 save_config_atomic 修改不同分组
- **THEN** 最终配置应包含所有修改，且文件内容与内存一致

#### Scenario: 并发原子删除分组
- **WHEN** 多个线程同时调用 delete_group_atomic 删除不同分组
- **THEN** 所有指定分组应被删除，无残留

#### Scenario: 并发保存与删除同一分组
- **WHEN** 线程 A 调用 save_config_atomic 修改分组 X，同时线程 B 调用 delete_group_atomic 删除分组 X
- **THEN** 最终状态应为分组 X 被删除或被修改之一，不应出现不一致状态

#### Scenario: 并发配置同步到 AHK
- **WHEN** 多个配置变更同时触发 sync_config_changes_to_ahk
- **THEN** 发送的 IPC 命令不应丢失或重复

### Requirement: 跨 crate 端到端数据流测试
系统 SHALL 验证从 Config 到 IpcMessage 的完整数据流跨越所有 crate 的正确性。

#### Scenario: 配置变更到 IPC 命令完整流
- **WHEN** 用户修改分组配置（激活/停用/热键变更/参数变更）
- **THEN** Config 更新 → AppState 状态变更 → sync_config_changes_to_ahk → 正确的 IpcCommand 序列生成 → IpcMessage 序化/反序列化往返正确

#### Scenario: 录制流程完整数据流
- **WHEN** 触发 start_recording → AHK 返回 key_record_event → stop_recording → 返回录制结果
- **THEN** RecordingService 正确解析结果，AppState 状态正确更新，配置正确保存

### Requirement: Bridge 层 trait 实现测试
系统 SHALL 验证 src-tauri 中 Bridge 层对 domain trait 的实现正确性。

#### Scenario: IpcBridge send_and_wait 超时
- **WHEN** IpcBridge.send_and_wait 超过指定超时时间
- **THEN** 应返回超时错误，且清理 pending entry

#### Scenario: IpcBridge send_and_wait 管道断裂
- **WHEN** IpcBridge.send_and_wait 过程中管道断裂
- **THEN** 应返回管道断裂错误

#### Scenario: TauriEventBridge 事件发射
- **WHEN** TauriEventBridge.emit 被调用
- **THEN** 应通过 Tauri app_handle.emit 发射对应事件

#### Scenario: WatchdogBridge 状态查询
- **WHEN** WatchdogBridge.get_state 被调用
- **THEN** 应返回 ProcessWatchdog 的当前状态

### Requirement: Watchdog 真实进程管理集成测试
系统 SHALL 验证 ProcessWatchdog 对真实子进程的管理能力。

#### Scenario: 子进程正常启动
- **WHEN** Watchdog 启动子进程
- **THEN** 子进程应成功启动，状态变为 Running

#### Scenario: 子进程崩溃自动重启
- **WHEN** 子进程意外退出
- **THEN** Watchdog 应检测到退出，在指数退避后重启子进程

#### Scenario: 重启次数上限
- **WHEN** 子进程连续崩溃达到 10 次上限
- **THEN** Watchdog 应停止重启，状态变为 Failed

### Requirement: CI/CD 自动化流水线
系统 SHALL 提供 GitHub Actions CI 配置，实现测试的自动触发、执行和结果报告。

#### Scenario: PR 提交自动触发测试
- **WHEN** 开发者提交 Pull Request
- **THEN** CI 应自动运行全部测试套件（单元测试 + 集成测试 + 跨 crate 测试）

#### Scenario: 测试失败阻断合并
- **WHEN** 任何测试失败
- **THEN** CI 应标记为失败，阻止 PR 合并

#### Scenario: 测试报告生成
- **WHEN** CI 测试执行完成
- **THEN** 应生成测试覆盖率报告和测试结果摘要

### Requirement: 测试运行脚本
系统 SHALL 提供一键执行全部测试套件的脚本，并生成结果报告。

#### Scenario: 全量测试执行
- **WHEN** 执行测试脚本 `run-tests.ps1`
- **THEN** 应按顺序执行：纯逻辑 crate 测试 → 应用层测试 → 主 crate 测试 → 跨 crate 集成测试，并汇总结果

#### Scenario: 快速测试模式
- **WHEN** 执行 `run-tests.ps1 -Quick`
- **THEN** 应仅执行单元测试和快速集成测试，跳过需要真实进程的端到端测试
