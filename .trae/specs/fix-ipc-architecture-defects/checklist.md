# 修复 IPC 架构缺陷验收清单

## 编译阻塞修复

- [ ] `WatchdogRunner::from_arc()` 方法已添加到 `infrastructure/watchdog.rs`，接受 `Arc<Mutex<ProcessWatchdog>>` 参数
- [ ] `ProcessWatchdog::set_state()` 已从 `fn` 改为 `pub fn`，允许外部模块调用
- [ ] `lib.rs` 中 `WatchdogRunner::from_arc(app_state.watchdog.clone())` 编译通过
- [ ] `lib.rs` 中 `guard.set_state(WatchdogStateEnum::Recovering)` 编译通过

## 缺陷 #5: IPC 测试方向修复

- [ ] `tests/ipc_tests.rs` 中不再使用旧 `IpcCommand` struct 字面量语法（`IpcCommand { action: ..., keys: ..., delay: ..., data: ... }`）
- [ ] 所有 IPC 集成测试使用服务端模式：`create_listener()` + `accept_from_ahk()`（而非 `connect_to_ahk()`）
- [ ] 测试中模拟的 AHK 客户端使用 `Stream::connect()` 连接到 Rust 监听的管道
- [ ] `test_ipc_command_send_via_server` 测试验证 IpcCommand enum 通过服务端模式发送和接收
- [ ] `test_accept_loop_reconnect` 测试验证 accept_loop 在管道断裂后重连
- [ ] 纯单元测试保留不变（序列化、错误转换、HotkeyMerger 等）

## 缺陷 #1-#4 验证（已完成代码，需编译验证）

- [ ] `infrastructure/ipc.rs` 不包含重复的 `IpcMessage` 或 `IpcCommand` 定义，仅从 `domain/models.rs` 导入
- [ ] `lib.rs` 包含 IPC 监听器创建（`create_listener("asd_ipc")`）和 accept 循环（`spawn_ipc_accept_loop`）
- [ ] `lib.rs` 包含心跳 ping 任务（`spawn_heartbeat_ping`）和 IPC 回调接线（`setup_ipc_callbacks`）
- [ ] `toggle_group` 命令在本地状态更新后发送 `IpcCommand::ToggleGroup`
- [ ] `register_hotkey` 命令在本地注册后发送 `IpcCommand::RegisterHotkey`
- [ ] `unregister_hotkey` 命令在本地注销后发送 `IpcCommand::UnregisterHotkey`
- [ ] Watchdog 心跳回调已接线（`set_heartbeat_callback` → `notify_heartbeat`）
- [ ] Watchdog pipe-broken 回调已接线（`set_pipe_broken_callback` → `set_state(Recovering)`）

## 编译与测试验证

- [ ] `cargo check` 编译通过，退出码 0
- [ ] `cargo test --lib` 全部测试通过，退出码 0
- [ ] `cargo clippy` 无警告，退出码 0
