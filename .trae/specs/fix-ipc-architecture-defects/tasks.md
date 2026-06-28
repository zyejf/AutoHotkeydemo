# Tasks

- [x] Task 1: 修复 WatchdogRunner::from_arc() 缺失 — 编译阻塞 #1
  - [x] SubTask 1.1: 在 `infrastructure/watchdog.rs` 的 `WatchdogRunner` impl 块中添加 `pub fn from_arc(watchdog: Arc<Mutex<ProcessWatchdog>>) -> Self` 方法
  - [x] SubTask 1.2: 验证 `lib.rs` 编译通过

- [x] Task 2: 修复 ProcessWatchdog::set_state() 可见性 — 编译阻塞 #2
  - [x] SubTask 2.1: 将 `fn set_state(&mut self, ...)` 改为 `pub fn set_state(&mut self, ...)`
  - [x] SubTask 2.2: 验证 pipe-broken 回调编译通过

- [x] Task 3: 重写 tests/ipc_tests.rs — 缺陷 #5 + 编译阻塞 #3
  - [x] SubTask 3.1-3.10: 所有测试已重写为服务端模式 + IpcCommand enum 语法

- [x] Task 4: 验证 cargo check 编译通过
  - [x] SubTask 4.1: cargo check 通过（修复了 Arc<String> 所有权、RwLockWriteGuard 跨 await、to_ns_name API 3 个额外错误）

- [x] Task 5: 验证 cargo test --lib 全部通过
  - [x] SubTask 5.1: 94 个测试全部通过

- [x] Task 6: 验证 cargo clippy 无警告
  - [x] SubTask 6.1: 零警告（修复了 10 个 clippy 警告）

# Task Dependencies

- [Task 1, Task 2] 可并行执行（无依赖关系）
- [Task 3] 依赖 [Task 1, Task 2]
- [Task 4] 依赖 [Task 1, Task 2, Task 3]
- [Task 5] 依赖 [Task 4]
- [Task 6] 依赖 [Task 5]
