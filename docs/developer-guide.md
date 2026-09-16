# ASD-Tauri 开发者文档

> 版本: 1.1 | 最后更新: 2026-08-20
>
> 本文档面向参与 ASD-Tauri 项目开发的工程师，提供项目结构说明、IPC 协议规范、调试策略和构建/发布工作流。
>
> 相关文档：[迁移指南](migration-guide.md) | [架构规格](../.trae/specs/rust-tauri-migration/spec.md) | [实现计划](../.trae/specs/plan-rust-tauri-implementation/spec.md) | [AGENTS.md](../AGENTS.md)

---

## 目录

1. [项目结构](#1-项目结构)
2. [IPC 协议规范](#2-ipc-协议规范)
3. [调试策略](#3-调试策略)
4. [构建与发布工作流](#4-构建与发布工作流)

---

## 1. 项目结构

### 1.1 顶层目录

```
asd-tauri/
  dist/                  # Vite 构建产物（前端静态资源）
  public/                # 前端公共资源
  src/                   # 前端源码
    api.js               # Tauri invoke() 封装层（34 个 invoke 调用 + 5 个事件监听）
    main.js              # 前端入口
    style.css            # 全局样式
  src-tauri/             # Tauri/Rust 后端
    ahk_executor/        # AHK 子进程源码
    benches/             # Rust 基准测试
    capabilities/        # Tauri 权限配置
    gen/                 # Tauri 代码生成（自动）
    icons/               # 应用图标
    src/                 # Rust 源码
    target/              # Cargo 构建产物
    build.rs             # Tauri 构建脚本
    build_ahk.ps1        # AHK 子进程编译脚本
    Cargo.toml           # Rust 依赖配置
    config.json          # 运行时配置文件
    rust-toolchain.toml  # Rust 工具链配置
  index.html             # 前端 HTML 入口
  package.json           # Node.js 依赖配置
```

### 1.2 Rust 源码结构（5-Crate Workspace）

Rust 部分采用 5-crate workspace 架构（`asd-tauri/Cargo.toml`，`resolver = "2"`）：

```
asd-tauri/
├── Cargo.toml              # workspace root（5 members）
├── crates/                 # 纯逻辑 crate（无 tauri/tokio/interprocess/windows 依赖）
│   ├── asd-domain/         # 领域层 —— 模型 + trait + 验证
│   │   └── src/
│   │       config.rs       # Config、GroupConfig、ModeData（10 种模式）、自定义 serde
│   │       models.rs       # SkillGroup 领域模型
│   │       validator.rs    # ConfigValidator：10 模式校验、重复热键检测、跨字段校验
│   │       traits.rs       # IpcSender / EventEmitter / ProcessWatcher trait 定义
│   │       lib.rs
│   ├── asd-ipc-protocol/   # IPC 协议 —— 命令 / 消息 / 错误
│   │   └── src/
│   │       command.rs      # IpcCommand（13 变体）
│   │       message.rs      # IpcMessage（9 字段）+ 10 种工厂方法
│   │       error.rs        # IpcError
│   │       hotkey_merger.rs# HotkeyMerger
│   │       lib.rs
│   ├── asd-application/    # 应用层 —— 状态 + 配置仓库 + 服务
│   │   └── src/
│   │       state.rs        # AppState（RwLock + AtomicBool，trait objects）
│   │       config_repository.rs # ConfigRepository（文件 I/O）
│   │       group_service.rs / recording_service.rs / backup_service.rs
│   │       time_format.rs  # 时间格式化
│   │       error.rs        # AppError
│   │       lib.rs
│   └── asd-test-harness/   # 测试支持 crate —— 测试固件 + mock 工具
│       └── src/lib.rs      # TestHarness
└── src-tauri/              # 表现层 + 基础设施 —— Tauri 主 crate
    ├── src/
    │   lib.rs              # 34 个 Tauri commands + 应用初始化
    │   main.rs             # 二进制入口（调用 lib.rs）
    │   bridge.rs           # IpcBridge / TauriEventBridge / WatchdogBridge（trait 实现）
    │   infrastructure/     # ipc.rs / watchdog.rs / logging.rs
    │   commands/           # config_cmd / group_cmd / hotkey_cmd / recording_cmd / system_cmd
    │   tests/              # ipc_tests / config_compat_tests / bridge_tests / command_contract_tests / watchdog_integration_tests / mod
    ├── ahk_executor/       # AHK 子进程源码
    ├── benches/            # criterion 基准测试
    └── fuzz/               # cargo-fuzz 模糊测试
```

Crate 依赖关系（`asd-domain` 仅依赖 `asd-ipc-protocol` 的数据结构类型，纯逻辑 crate 可通过 Miri 验证 0 UB）：

```
asd-domain ──→ asd-ipc-protocol
asd-application ──→ asd-domain ──→ asd-ipc-protocol
asd-test-harness ──→ asd-application ──→ asd-domain ──→ asd-ipc-protocol
src-tauri ──→ asd-application ──→ asd-domain ──→ asd-ipc-protocol
         └──→ asd-test-harness（dev-dependency，仅测试用）
```

### 1.3 AHK 子进程结构 (`src-tauri/ahk_executor/`)

```
ahk_executor/
  executor.ahk           # 主入口：CommandDispatcher（11 个 action handler）、初始化流程
  ipc_client.ahk         # IpcClient：Named Pipe 客户端、MiniJson 解析器、心跳检查
  hotkey_hook.ahk        # HotkeyHook：热键注册/注销、IPC 热键事件上报
  sender.ahk             # Sender：按键发送（periodic/sequence/hold/hybrid/enhanced 模式）
  joystick.ahk           # Joystick：vJoy 操作（periodic/sequence/hold 模式）
  asd_executor.bat       # 便携模式启动器（cmd /C AutoHotkey64.exe executor.ahk）
  .gitkeep               # 占位文件
```

### 1.4 前端结构 (`src/`)

```
src/
  api.js                 # API 层：34 个 invoke() 调用 + 5 个事件监听
  main.js                # 前端入口
  style.css              # 全局样式
```

[api.js](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src/api.js) 中的函数分为两类，共 34 个 `invoke()` 调用，与 [lib.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/lib.rs) 注册的 34 个 Tauri commands 一一对应：

| 类别 | 数量 | 说明 |
|---|---|---|
| invoke() 调用 | 34 | config/backup 11 + group 8 + hotkey 2 + recording 8 + system 5（详见附录 E） |
| 事件监听 | 5 | `onStatusUpdate`、`onHotkeyEvent`、`onExecutorStatus`、`onKeyRecordEvent`、`onKeySendEvent` |

### 1.5 依赖关系图

```
                    +----------------+
                    |     main.rs    |  (二进制入口)
                    +-------+--------+
                            |
                    +-------v--------+
                    |     lib.rs     |  (Tauri Builder + 初始化 + 34 commands)
                    +-------+--------+
                            |
                   +--------+---------+
                   |                  |
          +--------v---------+   +----v----------------+
          |    commands/     |   |  bridge.rs          |
          |   (5 模块)        |   |  (Ipc/Event/Watchdog)|
          +--------+---------+   +----+----------------+
                   |                  |
                   |      +-----------v------------+
                   |      |     infrastructure/     |
                   |      |   (ipc/watchdog/logging)|
                   |      +-----------+------------+
                   |                  |
          +--------v------------------v--------+
          |         asd-application             |  (状态/配置仓库/备份/分组/录制服务)
          +----------------+--------------------+
                           |
          +----------------v--------------------+
          |           asd-domain                |  (模型 + trait + 验证)
          +----------------+--------------------+
                           |
          +----------------v--------------------+
          |        asd-ipc-protocol             |  (IpcCommand/IpcMessage/IpcError)
          +--------------------------------------+
```

依赖方向（自顶向下）：

`src-tauri(commands/bridge/infrastructure)` → `asd-application` → `asd-domain` → `asd-ipc-protocol`

`asd-test-harness` 仅作为 `src-tauri` 的 dev-dependency 用于测试。

> **📖 延伸阅读**：本节的 ASCII 框图是**概览版**（面向快速浏览）。
> **依赖关系的权威分层版**（含 Mermaid 图、分层 depth 语义、AHK 反向边白名单、图谱脚本链说明）见
> [`docs/graph-driven-workflow.md`](./graph-driven-workflow.md) §2。
> 逐文件的入边/出边清单见 [`docs/module-adjacency.md`](./module-adjacency.md)。
> 若本节与上述文档不一致，**以图谱规范为准**。

---

## 2. IPC 协议规范

### 2.1 通信架构总览

```
前端 (JS)                     Rust 主进程                      AHK 子进程
  |                              |                                |
  | invoke('toggle_group',...)   |                                |
  |----------------------------->|                                |
  |                              | IpcCommand::ToggleGroup        |
  |                              | IpcMessage::command(seq, &cmd) |
  |                              |------------------------------- >|
  |                              |                                |
  |                              |         CommandDispatcher      |
  |                              |              .Dispatch()       |
  |                              |                                |
  |                              | IpcMessage::result(...)        |
  |                              |<-------------------------------|
  |                              |                                |
  | <--- GroupStatus ---         |                                |
  |                              |                                |
```

三层通信路径：

1. **JS -> Rust**：Tauri `invoke()` 内置 IPC，类型安全，延迟 < 0.1ms
2. **Rust -> AHK**：Named Pipe JSON Lines，`IpcMessage::command()`，延迟 < 1.2ms
3. **AHK -> Rust**：Named Pipe JSON Lines，`IpcMessage::result()` / `hotkey_event()`

### 2.2 Named Pipe 参数

| 参数 | 值 | 说明 |
|---|---|---|
| 管道路径 | `\\.\pipe\asd_ipc` | Windows Named Pipe |
| Rust 侧 API | `interprocess::local_socket` | `to_ns_name::<GenericNamespaced>()` |
| AHK 侧 API | `DllCall("CreateFileW", ...)` | Windows API 直接调用 |
| 帧分隔符 | `\n` (0x0A) | JSON Lines 格式 |
| 最大消息尺寸 | 64KB (65536 bytes) | 超过则丢弃并记录错误 |
| 编码 | UTF-8 | |
| 通道容量 | 256 | `mpsc::channel(256)` |

### 2.3 消息格式

#### 2.3.1 IpcMessage 结构

```rust
pub struct IpcMessage {
    pub id: Option<String>,          // 可选，请求标识
    pub r#type: String,              // 必需，消息类型
    pub seq: u64,                    // 必需，序列号
    pub ack_seq: Option<u64>,        // 可选，确认的请求 seq
    pub action: Option<String>,      // 可选，命令动作
    pub keys: Option<Vec<String>>,   // 可选，按键列表
    pub delay: Option<u64>,          // 可选，延迟（毫秒）
    pub status: Option<String>,      // 可选，状态
    pub data: Option<serde_json::Value>, // 可选，附加数据
}
```

字段省略规则：`None` 值的字段不序列化，减少消息体积。

#### 2.3.2 消息类型与工厂方法

| type 值 | 工厂方法 | 方向 | 说明 |
|---|---|---|---|
| `command` | `IpcMessage::command(seq, &cmd)` | Rust -> AHK | 执行指令 |
| `result` | `IpcMessage::result(seq, ack_seq, data)` | AHK -> Rust | 执行结果 |
| `ping` | `IpcMessage::ping(seq)` | Rust -> AHK | 心跳检测 |
| `pong` | `IpcMessage::pong(seq, ack_seq)` | AHK -> Rust | 心跳响应 |
| `execute` | `IpcMessage::execute(seq, keys, delay)` | Rust -> AHK | 按键执行 |
| `hotkey` | `IpcMessage::hotkey_event(seq, hotkey)` | AHK -> Rust | 热键事件 |
| `shutdown` | `IpcMessage::shutdown(seq)` | Rust -> AHK | 关机指令 |
| `heartbeat` | `IpcMessage::heartbeat(seq)` | AHK -> Rust | 心跳上报 |
| `response` | `IpcMessage::response(seq, ack_seq, status, data)` | 双向 | 通用响应 |
| `error` | -- | AHK -> Rust | 错误上报 |

#### 2.3.3 IpcCommand 枚举

Rust 侧通过 `#[serde(tag = "action")]` 序列化 IpcCommand，共 13 个变体：

| IpcCommand 变体 | action 值 | data 字段 |
|---|---|---|
| `ToggleGroup { group_id, active, mode, key_press_duration, hold_keys, hold_mode, mode_data }` | `toggle_group` | `{groupId, active, ...}` |
| `RegisterHotkey { hotkey, group_id }` | `register_hotkey` | `{hotkey, groupId}` |
| `UnregisterHotkey { hotkey }` | `unregister_hotkey` | `{hotkey}` |
| `StartRecording { group_id, mode }` | `start_recording` | `{groupId, mode}` |
| `StopRecording` | `stop_recording` | 无 |
| `PauseRecording` | `pause_recording` | 无 |
| `ResumeRecording` | `resume_recording` | 无 |
| `EmergencyRelease` | `emergency_release` | 无 |
| `Ping` | `ping` | 无 |
| `Shutdown` | `shutdown` | 无 |
| `HoldModeToggle { enabled }` | `hold_mode_toggle` | `{enabled}` |
| `StartValidation { group_id }` | `start_validation` | `{groupId}` |
| `StopValidation` | `stop_validation` | 无 |

> **说明**：`Ping` 与 `Shutdown` 在 Rust 侧不通过 `IpcMessage::command()` 发送，而是经由 `IpcMessage::ping(seq)` / `IpcMessage::shutdown(seq)` 直接发送（`type` 字段路由），AHK 执行器在 `ipc_client.ahk` 按 `type` 字段路由至 `_HandlePing` / `_HandleShutdown`。

### 2.4 消息示例

#### 切换技能组

```json
// Rust -> AHK
{"type":"command","seq":1,"action":"toggle_group","data":{"groupId":"1","active":true}}

// AHK -> Rust
{"type":"result","seq":100,"ack_seq":1,"data":{"status":"ok","groupId":"1","active":true}}
```

#### 注册热键

```json
// Rust -> AHK
{"type":"command","seq":2,"action":"register_hotkey","data":{"hotkey":"F1","groupId":"1"}}

// AHK -> Rust
{"type":"result","seq":101,"ack_seq":2,"data":{"status":"ok","hotkey":"F1","groupId":"1"}}
```

#### 热键事件上报

```json
// AHK -> Rust（用户按下 F1 时）
{"type":"hotkey","seq":200,"action":"hotkey_event","keys":["F1"]}
```

#### 心跳协议

```json
// Rust -> AHK (每 1s)
{"type":"ping","seq":50}

// AHK -> Rust
{"type":"pong","seq":51,"ack_seq":50}
```

#### 关机指令

```json
// Rust -> AHK
{"type":"shutdown","seq":99,"action":"shutdown"}
```

#### 按键执行

```json
// Rust -> AHK
{"type":"execute","seq":10,"action":"keypress","keys":["1","2"],"delay":50}

// AHK -> Rust
{"type":"result","seq":11,"ack_seq":10,"data":{"status":"ok","elapsed_ms":12}}
```

#### 错误上报

```json
// AHK -> Rust
{"type":"error","seq":300,"action":"error","data":{"code":"SEND_FAILED","message":"SendInput returned 0"}}
```

### 2.5 seq/ack_seq 确认机制

```
Rust                              AHK
  |                                 |
  |--- command seq=1 -------------->|  (Rust 发送命令)
  |                                 |
  |<-- result seq=100, ack_seq=1 ---|  (AHK 确认并回复)
  |                                 |
  |--- command seq=2 -------------->|  (Rust 发送下一个命令)
  |                                 |
  |<-- result seq=101, ack_seq=2 ---|  (AHK 确认并回复)
```

| 规则 | 说明 |
|---|---|
| seq 单调递增 | Rust 侧 `AtomicU64`，从 1 开始递增 |
| ack_seq 语义 | 最近成功处理的消息 seq，非累积确认 |
| 重复检测 | AHK 侧忽略 `seq <= lastAckSeq` 的消息（ping 除外） |
| 等待响应 | Rust 侧 `wait_response(seq, timeout)` 使用 oneshot channel |
| 超时处理 | 等待响应超时后移除 pending entry，返回 `IpcError::Timeout` |

### 2.6 心跳协议

| 参数 | 值 | 说明 |
|---|---|---|
| 心跳间隔 | 1s | Rust 侧定时发送 ping |
| 判定超时 | 3s (3 次未响应) | Watchdog 判定子进程挂起 |
| 重启后首次超时 | 5s | AHK 启动需要初始化时间 |
| AHK 侧超时 | 5s | AHK 侧检测 Rust 无响应后断线重连 |

心跳流程：

1. Rust 侧 `spawn_heartbeat_ping` 每 1s 发送 `IpcMessage::ping(seq)`
2. AHK 侧收到 ping 后回复 `IpcMessage::pong(seq, ack_seq)`
3. Rust 侧 `listen_ahk` 收到 pong 后触发 `heartbeat_callback`
4. `heartbeat_callback` 调用 `Watchdog::notify_heartbeat()`，重置 `missed_heartbeats`
5. `WatchdogRunner::run()` 每 1s tick，检查 `last_heartbeat` elapsed
6. 超过 3s 未收到心跳 -> `missed_heartbeats++` -> 达到 3 次 -> 状态变为 `Hung`

### 2.7 错误恢复路径

| 错误类型 | 检测方式 | 恢复动作 |
|---|---|---|
| 管道断裂 | `read_line` 返回 0 或 `BrokenPipe` | 关闭连接 -> 触发 `pipe_broken` 回调 -> Watchdog 进入 Recovering -> 重新下发活跃配置 |
| 消息格式错误 | `serde_json::from_str` 失败 | 记录日志，丢弃该消息 |
| 消息超尺寸 | `len() > 65536` | 丢弃，记录错误日志 |
| AHK 无响应 | 心跳超时（3 次 x 1s = 3s） | Watchdog 判定挂起 -> 强制终止 -> 指数退避重启 |
| AHK 崩溃退出 | `child.try_wait()` 检测 | Watchdog 自动重启，指数退避 |
| AHK 连接失败 | `CreateFileW` 返回 INVALID_HANDLE | 指数退避重连（1s -> 2s -> 4s -> ... -> 30s） |

### 2.8 背压与流控

| 场景 | 策略 |
|---|---|
| AHK -> Rust 高频热键事件 | `HotkeyMerger`：100ms 合并窗口，同组热键只保留最新一条 |
| Rust -> AHK 执行指令堆积 | 指令去重：同组 toggle 指令只保留最新一条 |
| Named Pipe 缓冲区满 | `write_all` 阻塞等待，天然背压 |
| IPC 通道容量 | `mpsc::channel(256)` |

### 2.9 关机流程

三阶段优雅关机（[lib.rs:perform_graceful_shutdown](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/lib.rs#L21-L34)）：

```
Phase 1: IPC shutdown 消息 (超时 2s)
  |
  |-- mark_shutting_down()  // 抑制 pipe_broken 回调
  |-- send IpcMessage::shutdown(seq)
  |-- wait_for_exit(2s)
  |
  v  进程未退出?
Phase 2: WM_CLOSE (超时 3s)
  |
  |-- EnumWindows + PostMessageW(WM_CLOSE)
  |-- wait_for_exit(3s)
  |
  v  进程未退出?
Phase 3: TerminateProcess
  |
  |-- child.kill()
  |-- cleanup()
```

关键注意事项：

- **shutting_down 标志**：关机前必须调用 `mgr.mark_shutting_down()`，否则 AHK 退出后 `pipe_broken` 回调会误触发 Recovering 状态
- **JobObjectGuard**：RAII 模式，主进程退出时自动终止子进程（`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`）
- **窗口关闭事件**：`CloseRequested` 事件被拦截，触发 `perform_graceful_shutdown` 后再 `handle.exit(0)`

---

## 3. 调试策略

### 3.1 Rust 后端调试

#### 3.1.1 日志系统

[logging.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/infrastructure/logging.rs) 使用 `tracing_subscriber` 双输出：

| 输出目标 | 位置 | 详细程度 |
|---|---|---|
| 控制台 | stdout | 简洁（无线程 ID、无文件/行号） |
| 文件 | `{app_data_dir}/asd.log` | 详细（含线程 ID、文件名、行号） |

日志级别由 `RUST_LOG` 环境变量控制，默认 `info`：

```powershell
# 设置调试级别
$env:RUST_LOG = "debug"

# 设置特定模块调试
$env:RUST_LOG = "asd_tauri_lib::infrastructure::ipc=trace"

# 只看错误
$env:RUST_LOG = "error"
```

#### 3.1.2 关键日志点

| 模块 | 日志内容 | 级别 |
|---|---|---|
| `lib.rs` | IPC 监听器创建、AHK 子进程启动、Watchdog 启动 | info |
| `ipc.rs` | 连接建立/断开、消息收发、管道断裂 | info/warn |
| `watchdog.rs` | 状态变更、心跳超时、重启尝试、关机阶段 | info/warn/error |
| `state.rs` | 分组激活/停用、IPC 命令发送 | info/warn |
| `config.rs` | 配置加载/保存/解析失败 | info/error |

#### 3.1.3 运行时调试

```powershell
# 启动应用（开发模式，控制台可见）
cd d:\1demo\AutoHotkeydemo\asd-tauri
npm run tauri dev

# 查看日志文件
Get-Content "$env:APPDATA\asd-tauri\asd.log" -Tail 20 -Wait

# 过滤特定模块日志
Select-String -Path "$env:APPDATA\asd-tauri\asd.log" -Pattern "Watchdog"

# 过滤错误日志
Select-String -Path "$env:APPDATA\asd-tauri\asd.log" -Pattern "ERROR"
```

#### 3.1.4 Watchdog 状态机调试

[watchdog.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/infrastructure/watchdog.rs) 的 7 状态机：

```
Idle -> Starting -> Running <-> Hung -> Restarting -> Running
                    |                        |
                    v                        v
                Recovering                Failed
```

状态变更时自动记录日志：`Watchdog 状态变更: {old} -> {new}`

通过 Tauri Command 查询当前状态：

```javascript
const status = await invoke('get_executor_status');
// 返回: { status: "Running", restart_count: 0 }
```

### 3.2 前端调试

#### 3.2.1 DevTools

Tauri 开发模式下，右键点击窗口 -> "检查元素" 打开 DevTools。

```javascript
// 在 DevTools Console 中直接调用 API
const groups = await window.__TAURI__.core.invoke('get_groups');
console.log(groups);

// 监听事件
await window.__TAURI__.event.listen('executor_status', (event) => {
    console.log('Executor status:', event.payload);
});
```

#### 3.2.2 API 调用调试

[api.js](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src/api.js) 中的 invoke 调用可通过 DevTools Network 面板观察。

常见错误排查：

| 错误信息 | 原因 | 解决方案 |
|---|---|---|
| `IPC 管理器未初始化` | IPC 连接未建立 | 检查 AHK 子进程是否启动，查看 Watchdog 状态 |
| `功能开发中: xxx` | 调用了 stub 函数 | 参考 [api.js](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src/api.js) 中的 stub 列表 |
| `分组不存在: xxx` | groupId 无效 | 检查 groupId 是否在 GroupSettings 中定义 |
| `配置错误: xxx` | 配置校验失败 | 调用 `validateConfig` 获取详细错误 |

#### 3.2.3 事件监听

```javascript
// 监听执行器状态变更
import { onExecutorStatus } from './api.js';
const unlisten = await onExecutorStatus((status) => {
    console.log('Executor:', status);
});

// 监听热键事件
import { onHotkeyEvent } from './api.js';
const unlisten = await onHotkeyEvent((event) => {
    console.log('Hotkey pressed:', event);
});
```

### 3.3 AHK 子进程调试

#### 3.3.1 OutputDebug 日志

AHK 子进程使用 `OutputDebug` 输出调试信息（不弹窗）：

```powershell
# 使用 DebugView 查看（推荐）
# 下载 Sysinternals DebugView: https://learn.microsoft.com/en-us/sysinternals/downloads/debugview

# 或使用 Visual Studio 的 Output 窗口

# 或通过 PowerShell 读取（需要 DebugView 工具）
```

#### 3.3.2 AHK 语法检查

```powershell
# 检查单个 AHK 文件语法
$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
& $ahkPath /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk" 2>&1

# 检查所有 AHK 文件
Get-ChildItem "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\*.ahk" | ForEach-Object {
    $result = & $ahkPath /ErrorStdOut $_.FullName 2>&1
    if ($LASTEXITCODE -eq 2) {
        Write-Host "FAIL: $($_.Name) - $result" -ForegroundColor Red
    } else {
        Write-Host "PASS: $($_.Name)" -ForegroundColor Green
    }
}
```

#### 3.3.3 IPC 通信调试

手动测试 Named Pipe 通信：

```powershell
# 检查 Named Pipe 是否存在
[System.IO.Directory]::GetFiles("\\.\pipe\") | Where-Object { $_ -match "asd_ipc" }

# 使用 PowerShell 读写 Named Pipe（高级）
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", "asd_ipc", [System.IO.Pipes.PipeDirection]::InOut)
$pipe.Connect(5000)
$reader = New-Object System.IO.StreamReader($pipe)
$writer = New-Object System.IO.StreamWriter($pipe)
$writer.AutoFlush = $true

# 发送测试消息
$writer.WriteLine('{"type":"ping","seq":1}')
$writer.Flush()

# 读取响应
$response = $reader.ReadLine()
Write-Host "Response: $response"

$pipe.Close()
```

#### 3.3.4 子进程独立运行

```powershell
# 便携模式独立启动（用于调试 AHK 侧逻辑）
$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$executorPath = "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk"
& $ahkPath $executorPath
# 注意：独立运行时 IPC 连接会失败（没有 Rust 服务端），但可以验证 AHK 逻辑
```

### 3.4 跨端联合调试

#### 3.4.1 完整链路追踪

从用户操作到按键执行的完整链路：

```
用户点击 UI 按钮
  -> JS: invoke('toggle_group', {groupId: '1'})
    -> Rust: toggle_group command
      -> AppState::set_group_active("1", true)
      -> AppState::send_ipc_command(IpcCommand::ToggleGroup{...})
        -> IpcManager::send_command(cmd)
          -> Named Pipe write
            -> AHK: IpcClient 收到消息
              -> CommandDispatcher::Dispatch("toggle_group", data, seq)
                -> Sender::ToggleGroup(groupId, true)
                  -> Sender::StartPeriodic / StartSequence / ...
                    -> SendInput (按键发送)
              -> IpcClient::SendResult(seq, result)
                -> Named Pipe write
                  -> Rust: IpcManager::recv()
                    -> dispatch_response (oneshot channel resolve)
                    -> outbound_tx (forward to listener)
```

#### 3.4.2 常见问题排查

| 症状 | 可能原因 | 排查步骤 |
|---|---|---|
| 按键不发送 | AHK 子进程未启动 | 检查 `get_executor_status` 返回值 |
| 按键不发送 | IPC 连接断开 | 检查 Watchdog 状态是否为 Recovering |
| 热键不响应 | 热键未注册 | 检查 `active_hotkeys` Map 内容 |
| 配置保存失败 | JSON 序列化错误 | 查看 Rust 日志中的 serde 错误 |
| 子进程反复重启 | AHK 脚本崩溃 | 查看 AHK OutputDebug 日志 |
| 管道断裂误触发 | 关机时未设 shutting_down | 确认 `mark_shutting_down()` 在关机前调用 |

---

## 4. 构建与发布工作流

### 4.1 开发环境搭建

#### 前置条件

| 工具 | 版本 | 说明 |
|---|---|---|
| Rust | stable (见 `rust-toolchain.toml`) | Rust 工具链 |
| Node.js | 18+ | 前端构建 |
| AutoHotkey v2 | 2.0+ | AHK 子进程 |
| WebView2 | Edge Chromium 内核 | Windows 10+ 内置 |

#### 初始化

```powershell
# 安装前端依赖
cd d:\1demo\AutoHotkeydemo\asd-tauri
npm install

# 验证 Rust 工具链
cd src-tauri
cargo check

# 编译 AHK 子进程
.\build_ahk.ps1
```

### 4.2 开发模式

```powershell
# 启动 Tauri 开发模式（前端热重载 + Rust 自动重编译）
cd d:\1demo\AutoHotkeydemo\asd-tauri
npm run tauri dev
```

开发模式特性：
- 前端 Vite 热重载（修改 JS/CSS 即时生效）
- Rust 代码修改后自动重编译（约 10-30s）
- DevTools 可用（右键 -> 检查元素）
- 控制台日志可见

### 4.3 构建命令

#### 前端构建

```powershell
cd d:\1demo\AutoHotkeydemo\asd-tauri
npm run build          # Vite 构建前端到 dist/
```

#### Rust 构建

```powershell
cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri

# Debug 构建
cargo build

# Release 构建
cargo build --release
```

#### AHK 子进程构建

```powershell
# 编译为独立 exe（需要 Ahk2Exe）
cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri
.\build_ahk.ps1

# 构建脚本会：
# 1. 语法检查 executor.ahk
# 2. 尝试编译为 asd_executor.exe（编译模式）
# 3. 编译失败则降级为便携模式（复制 AutoHotkey64.exe + 创建 asd_executor.bat）
```

[build_ahk.ps1](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/build_ahk.ps1) 注意事项：
- Ahk2Exe v1.1.37+ 存在 `/bin` 参数路径含空格的 bug，脚本已内置 workaround
- 编译模式优先（`asd_executor.exe`），便携模式为降级方案

#### Tauri 完整构建

```powershell
cd d:\1demo\AutoHotkeydemo\asd-tauri
npm run tauri build
# 产物位置: src-tauri/target/release/bundle/
```

### 4.4 测试

#### Rust 单元测试

```powershell
cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri

# 运行所有测试
cargo test

# 运行特定模块测试
cargo test -- domain::config
cargo test -- infrastructure::ipc
cargo test -- application::state

# 运行测试并显示输出
cargo test -- --nocapture

# 运行单个测试
cargo test test_ipc_command_all_variants -- --nocapture
```

#### 测试覆盖范围

| Crate | 测试文件 | 覆盖内容 |
|---|---|---|
| asd-domain | 内联 `#[cfg(test)]` + `tests/` | 模式反序列化/roundtrip、校验、SkillGroup、trait |
| asd-ipc-protocol | 内联 `#[cfg(test)]` + `tests/` | IpcCommand 13 变体 roundtrip、IpcMessage 工厂方法、HotkeyMerger |
| asd-application | 内联 `#[cfg(test)]` + `tests/` | 调度、状态、配置仓库、服务、并发 |
| asd-tauri (src-tauri) | 内联 `#[cfg(test)]` + `src/tests/` | IPC 通信、配置兼容、优雅关机 |

> **口径说明**：具体测试数量以 [test-map.md](../asd-tauri/docs/test-map.md) 为准（单一权威来源），此处不复制数字以免漂移。

#### AHK 语法检查

```powershell
$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
& $ahkPath /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk" 2>&1
```

#### AHK 完整测试套件与「宿主时延类断言」门控

```bash
# 本机（默认）：全跑，含 7 条绝对墙钟时延断言
"/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe" tests/run_all_tests.ahk

# CI / 争用不可控的机器：跳过宿主时延类断言
ASD_HOST_TIMING=0 "/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe" tests/run_all_tests.ahk
```

结果写在 `tests/test_results.log`，汇总含 `总计 / 通过 / 失败 / 跳过` 四行。
跳过走框架的 `assert.skip()`（新增 `AhuSkip`，见 `tests/AutoHotUnit.ahk`）：**计入总计、不计入失败、
单独计数并写出原因**，不是静默 `return` —— 静默跳过会让用例变绿却什么都没测。

**为什么需要这个开关**：定刻走 **QPC 忙等**（见 §1.3 / `high_res_clock.ahk`），CPU 一被争用不是
「变慢一点」而是量级崩塌。本机 12 线程施加 N 个满载进程实测：

| 争用 | SleepUntil 误差 p50 | SleepUntil 误差 p95 | periodic 端到端 p50 | periodic 端到端 p95 |
|---|---|---|---|---|
| 空载 | 0.005 ms | 0.006 ms | 15.015 ms | 15.03 ms |
| 11 进程 | 0.005 ms | 0.05 ~ 1.76 ms | 15.015 ms | 15.02 ~ 15.49 ms |
| 14 进程 | **19.22 ms** | **28.45 ms** | **28.45 ms** | **44.90 ms** |

注意 11 与 14 之间是一条**悬崖**：中位数前一档毫无变化，后一档直接崩。GitHub 共享 runner
（2 vCPU）实测正落在这条带上（run 34971335578：SleepUntil p95 = **11.15** ms、periodic p95 =
**31.86** ms，均超阈值），按插值其中位数也已越线 —— **CI 上放宽 P95 阈值并不能解决**。

更关键的一条实测：本机注入「定刻退化成 AHK 网格 `Sleep`」缺陷后，periodic 端到端 P95 =
**31.76** ms，与 CI 那个 31.86 几乎相同。也就是说 **在共享 runner 上，「实现退化」与「宿主忙」
在数值上无法区分** —— 硬判必然 flaky，放宽则测不出回归。故 CI 显式跳过这 7 条，真正的守护点是
争用可控的本机四闸门（注入缺陷实测 4 条立即变红）。

被门控的 7 条（均在 `SenderPreciseTimingTests`）：SleepUntil 误差、PressPrecise 保持时长对齐 kpd、
periodic 端到端 P95、MultiKey 同刻保持时长、sequence 端到端 P95、sequence 步进不漂移、hybrid
子组节奏。**未**被门控的（争用免疫）：QPC 分辨率（取 min delta）、`droppedTriggers == 0`、
间隔取整比例、T6 合并遍历等价性（确定性形态比对）。

CI 侧还有一道保险：G3b 解析出跳过数后会校验「必须 ≥ 1 条」，否则判定门控失效而失败 ——
防止环境变量没传进去或用例被改名后，跳过悄悄变成 0 而没人发现。

**Rust 侧同一类坑（换统计量即可，不需要跳过）**：`asd-tauri/src-tauri/src/tests/ipc_tests.rs`
的 `test_roundtrip_latency` 原先断言「**平均**往返 < 1200 μs」，CI 上失败过一次：

| | 本机 | CI |
|---|---|---|
| 平均 | 69.4 μs | **2454.2** μs |
| 最小 / 最大 | 64.7 / 349 | 121.8 / **158073** μs |
| **P50** | 65.8 | **153.8** μs |

一次 158 ms 的宿主调度停顿就给 100 个样本的平均值贡献约 1580 μs —— 平均值测的同样是宿主抖动。
已改为断言 **P50 < 1200 μs**（本机 ≈ 66 μs、CI ≈ 154 μs，**7.8× 余量**）并补打 P95。
阳性对照：在服务端回包路径注入 2 ms 固定延时 → P50 = 15969 μs，立即失败。
这条不用跳过 —— 单换统计量就足以在共享 runner 上稳定，CI 覆盖得以保留。

### 4.5 基准测试

```powershell
cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri

# 运行基准测试
cargo bench

# 基准测试内容
# - ipc_command: IpcCommand 序列化/反序列化性能
# - ipc_message: IpcMessage 构造和序列化性能

# 查看报告
# 产物位置: target/criterion/report/index.html
```

### 4.6 代码质量检查

```powershell
# 注意：工作目录是 workspace 根 asd-tauri（不是 src-tauri），否则 --all 只覆盖单个包
cd d:\1demo\AutoHotkeydemo\asd-tauri

# Clippy 静态分析（与 CI 一致：全 workspace + 全 target + 告警即失败）
cargo clippy --workspace --all-targets -- -D warnings

# 格式化检查
cargo fmt --all --check

# 自动格式化
cargo fmt --all
```

> ⚠️ 旧写法 `cargo fmt -- --check`（多一个 `--`）会把 `--check` 传给 rustfmt 而报错；
> `cargo clippy -- -W clippy::all` 既不覆盖全部 target 也不会让告警失败。请以本节为准。

#### 排障：`cargo clippy` 报 `the compiler unexpectedly panicked`（ICE）

**症状**：`cargo clippy` 或 `cargo test` 在 `asd-tauri` lib 上崩溃，输出
`error: the compiler unexpectedly panicked`、`query stack during panic`、
`note: rustc 1.95.0 ...`（或 `note: Clippy version: ...`），退出码 101。
崩溃点常见于 `rustc_metadata::rmeta::encoder::encode_metadata`。

**判定**：这是 **编译器缺陷 / 增量缓存损坏**，**不是代码告警，也不是测试失败**。
先确认 `git status` 里没有 `.rs` 改动；若确实没改 Rust 代码，则与本次改动无关。

**解法**：关闭增量编译重跑即可通过（实测对 clippy 与 test 均有效）：

```powershell
cd d:\1demo\AutoHotkeydemo\asd-tauri
$env:CARGO_INCREMENTAL = 0
cargo clippy -p asd-tauri --all-targets -- -D warnings
cargo test --workspace
```

也可先单独验证未受影响的纯逻辑 crate，确认告警面干净：

```powershell
cargo clippy -p asd-domain -p asd-ipc-protocol -p asd-application -p asd-test-harness --all-targets -- -D warnings
```

> 若关闭增量后仍 ICE，再考虑 `cargo clean -p asd-tauri`。

### 4.6.1 DoD 四闸门一键校验

提交/提 PR 前建议跑一次，等价于 CI 的 `gates` job：

```bash
# Git Bash / Linux
scripts/check-gates.sh            # 全量
scripts/check-gates.sh --quick    # 只跑 G1 图谱 + G2 fmt/clippy（秒级）

# Windows
scripts\check-gates.ps1 -Quick
```

| 闸门 | 校验内容 |
|------|---------|
| G1 | 图谱基线：无新增环、无白名单外依赖违规（`scripts/check-graph-baseline.py`） |
| | 另有「豁免卫生检查」：`allowed_violations` 的每条**必须有非空 `reason` 与未过期的 `expires`**，缺一或过期即硬失败（TD-009 起强制）。若某条其实不是违规，正确做法是改 `build_graph.py` 的 `ALLOWED_CRATE_DEPS`，而不是加一条豁免 |
| | ⚠️ **图谱节点用 git 口径**：`build_graph.py` 只把「已跟踪 + 未跟踪但未被 `.gitignore` 忽略」的文件当节点（与 C6 同口径）。被忽略的本地临时脚本 / 构建产物**不计入**，所以开发机与 CI 的数字应当一致；若不一致，先查是不是有文件该提交或该忽略（TD-025） |
| G2 | `cargo fmt --all --check`(a) + `cargo clippy -- -D warnings`(b) + **ESLint 棘轮(c)** |
| G3 | `cargo test --workspace`(a) / AHK 完整套件(b) / JS 单测(c) + `test-map.md` 数字对账(d) + **技术债度量(e)** + **覆盖率棘轮(f)** |
| G4 | 文档同步（无法自动化，脚本输出人工核对清单） |

> **G3f 跑在 CI 的 coverage job（ubuntu）**，不在本地 `check-gates.sh` 里 ——
> 它需要 `cargo-llvm-cov` 且只覆盖三个纯逻辑 crate，本机跑法见 §4.6.1.2。
>
> ⚠️ **别在本机 Windows 上对 G3f 的基线做判定，更不要在那里 `--update-baseline`**：
> 基线是 CI（ubuntu）取的，`cfg(windows)` 分支会让统计行数整体变多而命中数不动
> （2026-09-16 实测：`group_service.rs` 367→710、+93.5%，命中 232→232 **一个没变**；
> `validator.rs` 1856→2622），`check-coverage.py` 会正确地判为「口径漂移」并 FAIL。
> 这是**环境差异不是回归** —— 拿它去 `--update-baseline` 等于把一把更长的尺子当成覆盖率提升，
> 正是 TD-024 要防的事。要在本机看覆盖率趋势，只能**同文件纵向比**，且必须用同一条命令。
>
> **G2c 跑在 CI 的 `js-lint` job**（独立 job，与主 job 并行），不在本地 `check-gates.sh` 里 ——
> 它需要 `node_modules`（`npm ci`）。本机跑法见 §4.6.6。

另有 `scripts/install-hooks.ps1`（或 `.sh`）用于安装版本化 git 钩子——
`.git/hooks/` 不进版本库，新克隆后必须执行一次。

> 闸门定义、判定策略与基线更新方式详见 `docs/graph-driven-workflow.md` §5.4。

#### 4.6.1.1 技术债度量（`scripts/check-tech-debt.py`，G3e，2026-09-16 起在四闸门内）

**静态**检查（不编译、不执行被测程序，约 2.5s），已作为 **G3e** 接入四闸门。
C1a/C1b/C1c/C2/C3b 走**棘轮**：基线内的存量债只登记不报错，**只有新增项才 FAIL**；
**C3、C4、C5、C6 恒 0 硬阻断** —— 它们守的是**规则**（文档与代码必须一致 / 空占位目录不得放文件 / 成员目录不得有冗余 lock / vendored 引擎树必须与上游一致），
不是存量债，没有「先登记、以后再说」的余地。

```bash
python scripts/check-tech-debt.py                # 全检 + 与基线比对
python scripts/check-tech-debt.py --show         # 只看现状
python scripts/check-tech-debt.py --only c6      # 只跑某一检（c1/c2/c3/c3b/c4/c5/c6）
python scripts/check-tech-debt.py --update-baseline   # 清理后收紧水位
```

| 检 | 内容 |
|----|------|
| C1a/C1b/C1c | 孤儿文件 / 同名重复 / 代码误放 `docs/` 等目录 |
| C2 | `tests/` 下从 `run_all_tests` / `run_tests` 不可达（写了但永不执行） |
| C3 | `baselines.json` 的 `k`/`warn_k`/`_baseline_runs` 与 `developer-guide.md`、`test-map.md` 是否一致（**不做棘轮**） |
| C3b | `docs/` 下硬写的 AHK 基线数字（形态「`642 / 642`」）是否与 `test-map.md` 的实跑总数一致 |
| C4 | 空占位目录 `src-tauri/src/{application,domain}/` 是否被写入文件（**不做棘轮**，TD-008）。判「目录里**有没有文件**」而非「目录存不存在」—— git 不跟踪空目录，用存在性判定的话 CI（全新 checkout）与本机（老 clone）结论会相反 |
| C5 | workspace 成员目录下的冗余 `Cargo.lock`（**不做棘轮**，TD-019）。独立 workspace（如 `src-tauri/fuzz/` 自带 `[workspace]`）的 lock 合法。cargo 只读根那一份，成员这份永不更新，会误导 `cargo audit` / dependabot 的安全结论 |
| C6 | vendored 引擎树 `AutoHotkey-2.0.26/` 必须与官方 v2.0.26 **不多、不少、不改**（**不做棘轮**，TD-010）。基线在 `scripts/vendor-baseline-ahk-2.0.26.txt`，刻意取自**上游**而非本地快照 —— 取本地快照的话，一旦本地已被污染，污染就会被固化进基线、从此永远通过。⚠️ 内容口径是**工作区**哈希（`git hash-object`），不是索引 —— 用索引的话「改了引擎源码但还没 `git add`」完全抓不到，而那正是本条要防的。被 `.gitignore` 忽略的本机产物（`AutoHotkey.exe`、`*.log`）不在管辖范围，否则会出现「本地恒红、CI 恒绿」 |

> **C3b 的写法约定**：文档里**不要复写 AHK 用例总数**，一律写
> 「见 `asd-tauri/docs/test-map.md`（当前 N）」这类指针。
> 带日期的历史报告里的数字是当日实测快照，合法，由棘轮基线登记豁免 ——
> 但**新写的文档再硬编码数字就会被拦下**。
>
> ⚠️ **举例要写在反引号里**：写「形如 `642 / 642`」是在举例，不是声明基线数字，
> 反引号包裹的片段会被豁免。**裸数字**才会被检查。
> （这条是上线第一天被自己的台账触发才补的 —— 文档要解释什么叫「硬写 N / N」，
> 就得举一个 N / N 的例子，而举的例子必然是陈旧数字。）

基线在 `.review-analysis/tech-debt-baseline.json`；债项台账见 `docs/tech-debt-register.md`。
G3e **不随 `--quick` 运行**（quick 只跑 G1/G2）。

#### 4.6.1.2 覆盖率棘轮门禁（`scripts/check-coverage.py`，G3f，2026-09-16 起）

只覆盖三个纯逻辑 crate（`asd-domain` / `asd-ipc-protocol` / `asd-application`；
`src-tauri` 依赖 windows / tauri 系列，在 Linux 上编译不了）。

```bash
# 在 asd-tauri/ 下生成 lcov（约 1 分钟，首次含编译）
cargo llvm-cov --package asd-domain --package asd-ipc-protocol \
    --package asd-application --lcov --output-path coverage/lcov.info

# 回到仓库根跑门禁
python scripts/check-coverage.py --lcov asd-tauri/coverage/lcov.info
python scripts/check-coverage.py --lcov ... --show              # 只看现状
python scripts/check-coverage.py --lcov ... --update-baseline   # 补完测试后钉住新水位
```

| 阈值 | 值 | 理由 |
|------|----|----|
| 整体行覆盖率 | 基线 **− 0.5pp** | 防「总体稀释」：A 掉 20% 被 B 涨 5% 盖过去 |
| 单文件行覆盖率 | 基线 **− 2.0pp** | 防「丢车保帅」；小文件天然波动大，故容差比整体宽 |
| 新文件 | 只登记不判 | 新代码第一次不背历史包袱，第二次起有基线 |

**为什么是棘轮而不是「≥ 80%」**：凭空定的目标只有两种下场 —— 一上线就红
（于是大家加无断言的「跑一遍就算覆盖」测试刷数字），或低到形同虚设。
两种都比没有门禁更糟，因为它们会**污染覆盖率这个指标本身的可信度**。
棘轮只保证「不会比昨天更差」。

当前基线与逐文件数字见 `asd-tauri/docs/test-map.md`「覆盖率」一节（该表是
`.review-analysis/coverage-baseline.json` 的可读镜像，冲突时以 JSON 为准）。

⚠️ 基线在**本机（Windows）**实测。若 CI（ubuntu）因 cfg 分支系统性偏离，
下载 CI 的 `coverage-report` artifact 重跑一次 `--update-baseline` 校准即可。

#### 口径漂移检测（2026-09-16 补）

**背景教训**：2026-09-16 想把水位从 81.64% 收紧时，发现同一份代码、同一条 CI 命令下
`validator.rs` 的统计行数是 **1856**，而旧基线记的是 **2367**（-21.6%），
命中数却几乎没变 —— 整体「涨」了 7pp。**那不是覆盖率提升，是量程变了**
（旧基线的生成命令已无从查证）。旧基线只存百分比，这种漂移完全看不出来，
棘轮就会拿两个不可比的数字互相比。

所以基线现在存每个文件的 `lines` / `hits` 作为**口径指纹**，并新增判定：

| 条件 | 结果 |
|------|------|
| 某文件统计行数变化 **> 10%** 且 **≥ 20 行**，**且命中数没跟着变**（`\|Δhits/Δlines\| < 0.5`） | **FAIL**（口径漂移，数字不可比） |
| 行数剧变但**命中数同步变化** | **[NOTE]** 真实代码增减（多半是补测试），按棘轮判定 |
| 否则 | 按上面的棘轮判定 |

绝对量下限是为了不让小文件动一行就报警。

**为什么加「命中数是否同步变化」这一条**（2026-09-16 实测修正）：给 `traits.rs` 补 11 个
用例后，它的统计行数 15 → 146（+873%），漂移检测直接 FAIL —— 但那不是换尺子，是我真的
加了 131 行代码，而且这些行几乎全被执行了（命中数 0 → 140）。**换尺子的特征是代码没变：
命中数几乎不动，只有行数动**（`validator.rs` 那次 2367→1856 时命中数只变了 1）。
若不区分，以后每次补测试都会撞一个红色 FAIL，人会养成「无脑 `--update-baseline`」的习惯，
棘轮就此失效。

⚠️ **重取基线必须用同一条命令**：`--workspace` 与 `-p a -p b -p c` 的统计行数**不一样**
（实测 9595 vs 5861，且 `--workspace` 会带进 `src-tauri` 的 27 个文件）。
换命令 = 换量程，此时百分比的任何涨跌都没有意义。

阳性对照（4 组，脚本判定可复现）：行数大减 + 命中数不动 → FAIL；
行数与命中数同步增长（补测试）→ PASS 且降级 NOTE；行数暴涨但命中数不动 → FAIL
（这种情况与换尺子**从数字上无法区分**，保守要求人工确认）；
行数不变而命中数大减（覆盖率真跌）→ FAIL。

### ⚠️ 已知口径缺陷：分母含 `#[cfg(test)]` 测试代码（TD-026，豁免不修）

cargo-llvm-cov 测的是**测试二进制**，所以 `src/*.rs` 里的 `#[cfg(test)] mod tests`
会一并进分母。实测测试代码占比：`time_format.rs` **83.9%** / `traits.rs` **77.9%** /
`validator.rs` **60.9%** / `config.rs` **58.0%** / `state.rs` **51.7%**，
而 `group_service.rs`、`recording_service.rs`、`backup_service.rs` 是 **0%**。

后果：**跨文件的百分比不可比** —— `time_format.rs` 的 100% 里六成在测测试自己，
`group_service.rs` 的 63.22% 反倒是纯生产代码。所以「最低的 5 个文件」只能看
**同一个文件的纵向趋势**，不能当横向排名；想看某文件的生产代码覆盖率，
只能在该文件 `LF` 与逐行 `DA` 记录一致时人工按行核对。

两条修法实测均堵死，别再重复踩：

1. `#[coverage(off)]` 官方标记 —— rustc 1.95.0 上仍是实验特性
   （`error[E0658]: the #[coverage] attribute is an experimental feature`，issue #84605），
   CI 跑 stable；
2. 按源码定位 `#[cfg(test)]` 区间后逐行剔除 —— llvm-cov 的 `LF` 与逐行 `DA`
   **不是一套口径**（实测 15 个文件里 10 个不一致：`validator.rs` 1856/1805、
   `config.rs` 704/682、`models.rs` 142/128），硬剔等于再叠一层更难解释的误差。

加上「换口径 = 15 个文件全部重取基线、历史数字从此不可比」，故登记为豁免（TD-026）。

### 4.6.2 AHK 引擎探针（`tools/ahk-probes/`）

用于**量化 AHK v2 引擎行为**的独立探针集（启动/解析开销、定时器网格、主线程占用、热键、
内存、长路径、Unicode、异常、UAC）。与本项目生产代码解耦，**不参与四闸门**。

```bash
# Git Bash（必须走 run.sh：AutoHotkey64.exe 是 GUI 子系统进程，
# 直接调用不会等待，且未捕获错误会弹模态框导致静默挂起）
bash tools/ahk-probes/run.sh p0_version
bash tools/ahk-probes/run.sh p2_timer

# 结果：CSV 落在 %TEMP%\ahkprobe\<id>.csv，run.sh 轮询 <id>.done 哨兵后返回
cat "$TEMP/ahkprobe/p2_timer.csv"
```

| 文件 | 用途 |
|------|------|
| `run.sh` | 唯一入口：转换 Windows 路径 + 后台拉起 + 轮询 `.done` |
| `_harness.ahk` | 探针框架：输出目录 / CSV 写出 / `.done` 哨兵 / `OnError` 守卫（防模态框挂起） |
| `../_ahk_common.ahk` | 与 ahk-bench **共用**的纯计算原语：QPC 时钟、快排、分位数、mean·max·min（TD-004） |
| `p0_version.ahk` ~ `p10_uac.ahk` | 10 组探针，逐一对应报告章节 |
| `gen_fixtures.py` + `bench_startup.py` | 启动/解析开销的外部墙钟基准 |

> **结论落点**：探针只产出原始数据，解读与改进清单见
> `docs/research/ahk-engine-architecture-2026-09-14.md`（调研结论的唯一权威）。
> AHK v2 编写陷阱（如 `Array` 无 `Sort()`、`catch as e`、回调必须是函数对象）见
> `tools/ahk-probes/README.md`。

### 4.6.3 AHK 重构基准（`tools/ahk-bench/`）

用于**量化「优化前 vs 优化后」差异**的新旧双实现基准集（JSON 转义、tick 遍历、键名校验、
定时器策略、异常容错、循环引用泄漏）。**生产代码一行不改** ——
每个脚本内置旧实现（原样复刻生产逻辑）与新实现，同进程同数据对比并做等价性校验。

```bash
# Git Bash（必须走 run.sh，理由同 4.6.2）
bash tools/ahk-bench/run.sh json_escape

# 全部（cycle_leak 除外 —— 内存类基准必须每用例独立进程，否则基线漂移）
for id in json_escape tick_traversal key_regex timer_storm stability; do \
    bash tools/ahk-bench/run.sh $id; \
done
bash tools/ahk-bench/cycle_leak_all.sh

# 汇总成对比报告（--prev 可给多个历史轮次目录做多轮波动对比）
python tools/ahk-bench/report.py            # → docs/refactor/bench-report-<date>.md
```

#### 调度序列生成基准（L1 纯生成 + L3 端到端）

针对 `src-autohotkey/lib/sender.ahk` 的调度内核另有一套**分层**基准，规模口径与上面 6 组不同：

- **L1（纯生成）**：只跑"生成到期事件序列"，不含真实按键与定时器，可压到 **100K** 事件量；
- **L3（端到端）**：含 `SleepUntil` 忙等 + 真实唤醒，受 15.625 ms 定时器网格限制，实际只到 **1K** 量级。

```bash
# 单轮：L1（七阶段：规模吞吐 / tick 时延分解 / enhanced 别名 / 新旧等价性 / 分桶漂移 / 键数扫描 / 排序消融）
bash tools/ahk-bench/run.sh seqgen

# 单轮：L3 端到端
bash tools/ahk-bench/run.sh schedule_e2e

# 三轮可复现（推荐 —— 单轮结论不可信）
bash tools/ahk-bench/run_3rounds.sh

# 环境信息采集（OS / CPU / 内存 / QPC 频率 / AHK 版本）
python tools/ahk-bench/envinfo.py
```

| 文件 | 用途 |
|------|------|
| `run.sh` | 运行器：显式传 `AHK_BENCH_OUT`（Windows 路径）+ 轮询 `.done` |
| `_harness.ahk` | 基准框架：`AHK_BENCH_OUT` 输出目录、`GetProcessMemoryInfo` / `GetProcessTimes` 采样、`OnError` 守卫 |
| `../_ahk_common.ahk` | 与 ahk-probes **共用**的纯计算原语：QPC 时钟、快排、分位数、mean·max·min（TD-004） |
| `bench_*.ahk` | 7 组双实现基准，均含旧/新对照与等价性校验 |
| `cycle_leak_all.sh` | 逐个用例独立进程跑 `cycle_leak`（含阳性对照） |
| `report.py` | CSV → Markdown 对比报告 |
| `lib/seqgen.ahk` | 调度内核**新**实现原型（策略接口 + 惰性滑动窗口 `EventWindow`） |
| `lib/seqgen_legacy.ahk` | 旧实现复刻（含浮点分桶的 `dueBuckets` 行为），供 A/B 对照 |
| `lib/seqgen_test.ahk` | 原型单元测试（**原型自测，非生产测试套件**，不登记进 `test-map.md`） |
| `bench_seqgen.ahk` | L1 纯生成基准（A~G 七阶段，G 为排序消融） |
| `bench_schedule_e2e.ahk` | L3 端到端基准（含 `SleepUntil` 忙等与真实唤醒） |
| `run_3rounds.sh` | 三轮 runner，**每轮独立输出目录** |
| `envinfo.py` | 环境信息采集（含 QPC 频率 —— AHK 侧无 JVM 等价物，必须报此项） |

> ⚠️ **`run_3rounds.sh` 为什么要每轮独立目录**：本环境 `rm` 会被 safe-delete 钩子拦截
> （`genie-trash` 无法处理 `/d/...` 与 `C:\...` 混写路径），清不掉 `.done` 哨兵 →
> 轮询立刻返回 → **跑出上一轮的陈旧 CSV**。独立目录是最省事的绕法。

> ⚠️ **`_ahk_common.ahk` 的重名禁区**：AHK v2 同名函数重复定义是**加载期报错**（不是覆盖）。
> 该文件占用 `HighResNow` / `SleepUntil` / `SortNums` / `QSort` / `Pct` / `Mean` / `ArrMax` /
> `ArrMin` 八个名字，include 链上任何脚本都不得再定义一份 —— 包括 `bench_prod_*.ahk`
> 直接 include 的**生产代码**。往里加函数前先确认 22 个 `bench_*/p*_*.ahk` 没有同名定义。
>
> **分位数语义**：`Pct` **只做索引、不排序**，入参必须先 `SortNums`。此前 bench 与 probes
> 各有一份 `Pct`，一个要求入参已升序、一个内部自排序 —— 同名不同义，改其中一份时没人会
> 想到另一份，而错的那份不会报任何错（TD-004 的由来）。probes 侧保留 `_Pct` 薄包装
> （内部先排）是**刻意的**，避免动 11 个探针脚本的 40+ 处调用点。

> **两条内存类基准的硬纪律**：① 必须带**阳性对照**，否则「没测出来」和「没有泄漏」无法区分；
> ② 必须**每用例独立进程**，同进程连续跑时基线会漂移（实测 3216 → 4696 KB）。
>
> **统计口径**：用 p50 判定不用 max；P95 需足量样本（n=54 时只容忍 2 个离群点）；
> **P999 需 ≥1000 样本**，否则 `Ceil(n*0.999)` 恒等于 max；
> CPU 类结论必须给多轮区间并检查是否重叠。
>
> **结论落点**：`docs/refactor/`（重构方案与实测对比的唯一权威）。
> 其中调度专题三份：
> `scheduling-design.md`（算法设计 / 契约 / 边界矩阵）、
> `scheduling-bench-2026-09-14.md`（实测基准报告）、
> `plan-C-evaluation.md`（方案 C 深度评测）。

### 4.6.4 AHK 生产基准门禁（`tools/ahk-bench/gate.py`，T11）

4.6.3 那套 `bench_*.ahk` 是**选型期**的「双实现对照」基准：old/new 两份实现都复刻在脚本内，
用来量化「改造值不值得做」。**它测的不是生产代码** —— T1/T6 落地后，脚本里的 new 侧是副本，
生产代码再改也不会跟着变，对生产回归**零防护力**。

所以另有**生产基准**（`bench_prod_*.ahk`）：直接 `#Include` 生产代码并测它，由 `gate.py`
做门禁，跑在 CI 的 `ahk-bench` job（**会阻断合并**，与 `bench` job 的「仅观测」不同）。

目前有两个，各守一处已落地的优化：

| `--bench` | 守什么 | 被测生产代码 | K |
|---|---|---:|---:|
| `prod_escape`（默认） | T1 · JSON 转义快路径 | `JSONSerializer._EscapeString` | **1.5**（p50 自 2026-09-15 起也是归一化值） |
| `prod_tick` | T6 · 周期 tick 遍历合并 | `Sender._ExecutePeriodic` | **1.4**（p50 是归一化值） |

两个 K **不一样是有意的** —— K 按各自信噪比定：T1 回退信号 41~49×，可以松；
T6 信号只有 ~1.7×，必须紧（详见下方两节）。

CI 的 `ahk-bench` job **依次跑两个、全部跑完再统一判定** —— 否则第一个失败会让第二个
根本不跑，静默丢掉一整处防护。

```bash
# 跑门禁（默认 3 轮，与基线比对；退出码 0=PASS 1=回归 2=运行期错误）
python tools/ahk-bench/gate.py                    # 默认 prod_escape
python tools/ahk-bench/gate.py --bench prod_tick  # 跑 tick 那个
python tools/ahk-bench/gate.py --rounds 5         # 定基线时用更多轮

# 确认是真实劣化后，重设基线（改完 baselines.json 要随 PR 一起提交并说明原因）
python tools/ahk-bench/gate.py --rounds 5 --update-baseline

# AHK 不在默认路径时
AHK_EXE="D:/Program Files/AutoHotkey/v2/AutoHotkey64.exe" python tools/ahk-bench/gate.py
```

**判据（只设上界 + 多轮中位数）**：每个 metric 每轮跑若干次采样取 p50，跨轮再取 **p50 的中位数**，
断言 `中位数 ≤ 基线 × K`（`baselines.json` 里每个 bench 各自的 `k`：`prod_escape` **1.5**、
`prod_tick` **1.4**；`warn_k` 分别是 **1.25** / **1.2** —— 见下方两节「为什么要归一化」）。

- **只设上界**：变快不会失败 —— 只有变慢超过 K 倍才红；
- **多轮中位数**：p50 滤单次离群，中位数再滤整轮异常（宿主抖动常整轮偏移）；
- 另有 **WARN 带**：`prod_escape` 1.25×~1.5×、`prod_tick` 1.2×~1.4×，只告警不阻断。

**⚠️ 基线取自 CI，不是开发机。** 首版基线用的是开发机实测值，结果 CI 上 5 个 metric
全部落在 **1.20~1.44×**（GitHub 托管 runner 比开发机慢 30~40%）—— 每次跑都刷满 WARN，
警告带等于失效。故 `baselines.json` 里的数值来自 **CI 实测**（见文件内 `_baseline_source`
/ `_baseline_run`）。**重设基线请在 CI 上做**，不要拿本地数字覆盖。

```bash
# 在 CI 上重设基线：Actions → CI → Run workflow → 勾 update_ahk_bench_baseline
# 跑完下载 artifact `ahk-bench-baseline`，人工确认后提交（基线是门禁锚点，不自动提交）
```

> ⚠️ **更正（2026-09-15）**：早期记录的「runner 池 ±10~17% 波动」是**严重低估**，勿再引用。
> 同一份代码、5 次 CI 运行，相对固定绝对值基线的倍率如下 —— 跨 run 散布达 **3.7~3.9 倍**，
> 且每次都是 5 个 metric **同步**移动（整机速度因子，不是某条代码路径退化）：
>
> | run | 时间 | 相对基线倍率 |
> |---|---|---:|
> | 34968820407 | 12:26 | 0.79~0.82× |
> | 34975780100 | 13:33 | 0.92~0.96× |
> | 34976964638 | 13:44 | 1.07~1.15× |
> | 34978303684 | 13:56 | **0.52~0.53×** |
> | 34981552999 | 14:25 | **1.87~2.09× → FAIL** |
>
> 绝对值基线在这种散布上**两头不讨好**：慢机器上没有变化也 FAIL（34981552999 就是）；
> 快机器上真实的 2× 回退会读成 0.52×2 = **1.04× 而 PASS** —— 漏报比误报更危险。
> 结论：**绝对毫秒不能作为跨 run 的判据**，两个 bench 的 p50 都已改成归一化值。
> （取「两次独立 CI 运行的均值居中」的做法不变。）

**实测依据（prod_escape）**：单轮内是稳的（开发机跨会话中位数波动 ≤2.4%、CI 单轮内跨轮范围
约 0.4~2.7%），但**跨 run 整机散布 3.7~3.9×**（见上表）—— 故必须归一化。归一化后
「T1 被完整回退」的信号是 `escape_mixed_2k` **41.8×**、`escape_plain_*` **44~49×**，
而 `escape_ctrl_512`（兜底路径，T1 未触碰）保持 **0.99×** —— 信号比残留噪声高一个
数量级以上，K=1.4 留足余量。

> 💡 **本地跑门禁会显示 0.7× 左右（比基线快），这是正常的** —— 判据只有上界，变快不失败。

#### prod_escape：p50 为什么也从毫秒改成归一化值（2026-09-15）

**触发事件**：run `34981552999` 上 5 个 metric 全部落在 1.87~2.09×，`plain_2k`/`plain_8k`
判 FAIL。但该 PR 只动了 Rust 侧 IPC 时延的统计口径与记忆文件，**与 AHK 的 JSON 转义毫无关系**。

**定性依据**：5 个倍率挤在 1.87~2.09 的窄带里。若真是快路径退化，全 ASCII 的 `plain_*`
会暴涨、而本就走慢路径的 `mixed`/`ctrl` 几乎不动 —— 倍率应当**严重分化**；同步移动说明是
整机速度因子。再拉历史倍率序列（见上表）确认：同代码跨 run 散布 3.7~3.9×。

**处置**：与 `prod_tick` 同机制 —— `bench_prod_escape.ahk` 在每个 case 之后**紧邻**测一份
与被测代码路径无关的纯 AHK 参考负载（预分配 Array 上的算术循环，`REF_OPS=8192 × REF_LOOPS=4`
≈ 13 ms/采样），输出 `p50 = 批耗时 ÷ 参考负载耗时`（无量纲；原始毫秒仍在 `raw_ms=`，门禁不判）。
`gate.py` **无需改动**：它只认 `metric` 行的 `p50`，`info,ref_*` 行自动忽略。

> 参考负载刻意**不**复用 `bench_prod_tick.ahk` 里那份同名的 `RefBatch`/`MeasureRef`：
> 放进共享的 `_harness.ahk` 会与 prod_tick 的本地定义重名（AHK v2 报重复定义），而改
> prod_tick 去用共享版会动到一个已有有效基线的基准 —— 不值得。待它下次重取基线时一并统一。

**效果**：用同批 CI 数据、拿兜底路径 `ctrl_512` 做分母粗算，散布从 **3.7~3.9× 降到 1.10~1.17×**。

**⚠️ 已知副作用：参考负载对 CPU 争用「过度校正」，但方向是安全的。** 本机 20 个满载进程
（12 线程，超订 1.67×）实测：

| metric | raw 变化 | 参考负载变化 | 归一化变化 |
|---|---:|---:|---:|
| `plain_2k` | 1.43× | 1.40× | 1.02× |
| `plain_8k` | 1.06× | 1.38× | 0.77× |
| `plain_64k` | 1.02× | 1.04× | 0.98× |
| `mixed_2k` | 0.99× | 1.40× | 0.71× |
| `ctrl_512` | 1.16× | 1.37× | 0.85× |

纯 CPU 的参考负载对争用**比转义负载更敏感**（转义负载越大越偏内存/GC，对 CPU 争用越不敏感），
所以归一化会把读数**压低**（0.71~1.02×，全部 ≤1）。这意味着：**争用只会降低灵敏度，不会
造成误报** —— 对门禁是安全方向。反过来说，别再据此收紧 K，也别指望它在争用下仍有标称灵敏度。
（CI 上 3.7~3.9× 的散布若是争用造成的，转义最多只动 1.4×，所以那个散布主要来自**时钟/硬件
代际** —— 归一化对这部分是准确校正。）

**基线来源**：CI 两次独立运行各 5 轮取中位数、再取两次均值居中（run `34986114982` /
`34986950001`）。两次相差仅 **1.018~1.101×**（相对各自均值 ±5%）—— 相比改造前绝对值的
3.7~3.9×，收敛了一个数量级。本机拿这份 CI 基线实跑 **1.00~1.17×**（`plain_64k` 最高，
残余差异偏向内存带宽），跨机器成立。

**K 为什么是 1.5**：CI 噪声 ±5% → warn 带 1.25 是它的 2.5× 余量；实测最差值 1.17×
→ K=1.5 是它的 1.28× 余量；而 T1 回退信号 41~49×，检出余量仍有 27× 以上。
比 `prod_tick` 的 1.4 **松是有意的**：T1 信噪比远高于 T6（~1.7×），松一点换稳健性
不损失检出能力；反过来 `prod_tick` 再松就抓不住了。

#### prod_tick：为什么 K 是 1.4、且 p50 是归一化值

T6 的信号比 T1 **弱一个数量级**，K 必须跟着收紧，否则门禁形同虚设：

| 指标 | 形态 | 无变异噪声 | 「完全回退 T6」倍率 | 能否抓住回退 |
|---|---|---:|---:|:--:|
| `tick_onedue_n64` | 64 键中只有 1 个到期 | 0.96~1.02× | **1.65~1.81×** | ✅ |
| `tick_onedue_n128` | 128 键中只有 1 个到期 | 0.98~1.06× | **1.68~1.79×** | ✅ |
| `tick_alldue_n64` | 64 键全部到期 | 0.98~1.02× | 1.18~1.21× | ❌ 只守复杂度回归 |

`onedue`（n 个键只有第 1 个到期）是**生产最常见形态**，且每 tick 只有 2 次发送 ——
发送开销不稀释遍历耗时，所以信号最强。`alldue` 有 2n 次发送会稀释，但覆盖了「按计划时刻
分桶」这条 `onedue` 走不到的路径，保留它专门守**复杂度回归**（O(n²)）。

**为什么 p50 要归一化**：CI 托管 runner 的硬件代际差异会让绝对值整体偏移 —— 实测同一个
`prod_escape` 基线在两次 CI 运行上分别读到 **1.04× 与 0.80×（相差 30%）**（后续跨 5 次运行
实测远不止 30%，见上节更正表）。T6 的回退信号
只有 ~1.7×，一旦某次落在「比基线采集时更快的机器」上，1.65× 会被压到 ~1.3× 而**漏掉**。
所以 `bench_prod_tick.ahk` 在每个被测项之后**紧邻**测一份与被测代码路径无关的纯 AHK
参考负载，输出 `p50 = tick 每 tick 毫秒 ÷ 参考负载毫秒`（无量纲；原始毫秒仍在 `raw_ms=`
里，门禁不判它）。

实测（本机人为加 8 个 CPU 满载进程）：tick 原始值 **+48%**、参考负载 **+57%**、
归一化后的比值只变 **-5.7%** —— 机器/负载差异被抵消掉约 7/8。效果是：

| 场景 | 归一化值 | 判定 |
|---|---:|:--:|
| 无变异 · 空载 | 0.96~1.00× | PASS |
| 无变异 · **满载** | 0.87~0.90× | PASS（不误报） |
| 完全回退 T6 · 空载 | 1.67 / 1.79× | **FAIL** |
| 完全回退 T6 · **满载** | 1.69 / 1.69× | **FAIL**（最不利情形仍抓住） |

> 参考负载用**预分配 Array 上的算术循环**：不分配 → 不触发 GC。别换成 Map 版 ——
> 实测 Map 版残差 -9.6%，比 Array 版的 -5.7% 更差（Map 里混了哈希与扩容，
> 与 tick 的负载结构反而不匹配）。

**基线来源**：CI 两次独立运行的均值（run 34975780100 / 34976964638，各 5 轮取中位数），
两次相差仅 **1.06~1.07×** —— 归一化后跨运行波动明显小于 `prod_escape` 未归一化时的
1.10~1.17×。本地拿这份 CI 基线跑实测 **1.02~1.06×**，与 CI 同量级，说明归一化跨机器成立。
（注意 `p50` 是归一化后的无量纲值，`raw_ms=` 里的原始毫秒只作参考、门禁不判。）

**为什么不测 prescan（提前返回路径）**：实测合并版与旧版在该路径上**区间重叠、测不出差异**
（n=8 1.02× / n=64 0.82× / n=128 0.93×），放进去只会得到一条永远 PASS 的虚线。

**为什么不测 n≤32**：每 tick 存在一档约 **13 µs、与 n 无关的固定开销抖动**，n=16 时它占总
耗时 26% → 同一份代码连跑 5 轮出现 **0.042 / 0.053 双峰（±32%）**；而 n=16 的回退信号只有
1.26~1.48× —— **信噪比 <1，无法用于门禁**。n=64 起该抖动降到 <10%，n=128 约 5%。
代价是失去「真实规模（十几键）」覆盖，属已知盲区。

**为什么不测 hybrid**：`_ExecuteHybrid*` 每 tick 都要重建 `items` 数组（n 个 7 元子数组），
分配开销会淹没遍历差异，信号同样不可靠；其等价性由单测 `Test_TickMerge_*` 覆盖。

#### 已知盲区汇总（不是 bug，是取舍）

| 盲区 | 影响 | 靠什么兜底 |
|---|---|---|
| 「只删快路径、保留 `StrReplace`」（prod_escape） | 仅劣化 1.16~1.22×，与跨机器波动同量级 | code review + `JSONSerializerEscapeTests` |
| 该倍数不随负载长度放大（2K/8K/64K 一致） | 64K 档拦不住它 | 保留 64K 档是为了放大 **O(n²)** 回归 |
| `tick_alldue_n64` 抓不住 T6 回退 | 只进 WARN 带 | `tick_onedue_n64/n128` 兜住 |
| 无 n≤32 的 tick 指标 | 真实规模覆盖缺失 | 单测 + review |
| 无 hybrid tick 指标 | hybrid 侧无性能门禁 | 单测 `Test_TickMerge_*`（等价性） |
| MERGE_TICK_SCAN 被翻回 false | —— | **单测 `Test_MergeTickScan_DefaultOn_And_DispatchHonorsIt` 已钉住**（门禁是第二道） |
| CI 不跑 7 条宿主时延断言 | 定刻回归在 CI 上看不出来 | 本机四闸门（默认全跑，注入缺陷实测 4 条变红）+ CI 校验「跳过数 ≥ 1」防门控失效 |
| 参考负载对 CPU 争用过度校正（prod_escape） | 争用下读数被压低 → 灵敏度下降，可能漏报 | 方向只向下、不会误报；T1 信号 41~49×，余量充足 |

**基准自身的「阳性对照」**（防门禁静默失效）：

| 校验 | 失败条件 | 拦住什么 |
|---|---|---|
| 形态自描述 `len=` / `calls=` / `keys=` / `sends=` | 与基线记录不一致 | 负载/形态构造被改坏，耗时结构变了却仍在 PASS |
| `equiv,ascii_scan,diffs=0`（prod_escape） | 快路径与逐字符版不等价 | 为了快而改错 |
| `equiv,tick_onedue_n*,diffs=0`（prod_tick） | 合并版与旧版状态推进不一致 | 同上（确定性形态下逐项比对） |

prod_escape 已做 6 项阳性对照：C0 无变异保持绿；C1 完全回退 T1（41.7×）、
C2 兜底集合写宽（41.8×）、C3 等价性被破坏、C4 payload 长度被改 —— 全部变红；
**C5 归一化改造后重做 C1**：4 条快路径档 **41.8~49.2× FAIL**，而 `ctrl_512`
（T1 未触碰的兜底路径）**0.99× PASS** —— 证明归一化后门禁仍抓得住回退，且没有把
无关档位带歪。
prod_tick 已做 4 项：T0 无变异保持绿（0.96~1.00×，满载亦 0.87~0.90× 不误报）；
T1 完全回退 T6（n=64 **1.67×**、n=128 **1.79×** → FAIL，满载下仍是 1.69× → FAIL）；
T2 合并版推进基准 +1（等价性 diffs≠0 → FAIL）；
T3 把基线里的 `keys`/`sends` 伪造成别的值（形态不匹配 → FAIL）。

| 文件 | 用途 |
|------|------|
| `bench_prod_escape.ahk` | 生产基准：直接测 `JSONSerializer._EscapeString`（T1） |
| `bench_prod_tick.ahk` | 生产基准：直接测 `Sender._ExecutePeriodic`（T6） |
| `gate.py` | 门禁：多轮 → 中位数 → 与基线比对 → 退出码 |
| `baselines.json` | 基线（含 `k` / `warn_k` / 每个 metric 的 p50 与形态自描述） |

### 4.6.5 依赖治理（dependabot + 安全审计，TD-014）

依赖这块此前**完全无人看守**：没有自动更新、没有漏洞扫描，靠人想起来才 `npm audit` 一次。
2026-09-16 补上两道：**自动更新**（dependabot）+ **CI 安全审计**（`security-audit` job）。

#### 自动更新：`.github/dependabot.yml`

| ecosystem | directory | 说明 |
|---|---|---|
| cargo | `/asd-tauri` | 只配 workspace 根；`src-tauri` 是 member，不该有自己的 lock |
| npm | `/asd-tauri` | 前端 |
| npm | `/asd-tauri/e2e` | E2E（独立 package.json，必须单独配） |
| github-actions | `/` | CI 里 pin 的 action 版本 |

每周一 03:00（Asia/Shanghai）开跑，Actions 用 monthly（action 版本变动频率低）。
每类 `open-pull-requests-limit: 5` —— 放任 dependabot 一次开 20 个 PR 的结果是
**全部被无视**，限流才能逼出「每周消化一批」的节奏。

> ⚠️ 已知冗余：`asd-tauri/src-tauri/Cargo.lock` 是多余的（member 不该有 lock），
> 已登记为 TD-019，清理时 dependabot 无需改动。

#### CI 安全审计：`security-audit` job

**核心取舍：生产依赖阻断，dev 依赖只报告不阻断。**

| 检查 | 范围 | 阻断？ |
|---|---|---|
| `npm audit --package-lock-only --omit=dev --audit-level=high` | 前端 **生产**依赖 | ✅ 阻断 |
| 同上 | E2E **生产**依赖 | ✅ 阻断 |
| `npm audit --package-lock-only`（**不带** `--omit=dev`，即含 dev） | dev 依赖 | ❌ `continue-on-error`，只打日志 |
| `rustsec/audit-check@v2` | Rust 依赖 | ✅ 阻断 |

为什么要分开：**生产依赖进交付物**，有 CVE 就该拦；dev 依赖不进交付物，且
`npm audit fix` 常常需要 breaking change（vite 大版本升级会连带插件生态）。
一刀切阻断的现实结果不是「大家去修依赖」，而是**把这个 job 关掉** —— 那就连生产依赖
也一起失守了。所以 dev 这边保留数字可见（不静默），存量漏洞单独登记排期（TD-020）。

> `--package-lock-only` 是为了**不装 node_modules** 直接审 lock 文件，省掉几分钟安装时间；
> 代价是只信 lock 里记录的版本，与 `npm ci` 的实际结果一致，可以接受。

#### 首轮基线（2026-09-16 实测）与 TD-020 处置后的现值

| 范围 | 首轮（2026-09-16） | 现值 |
|---|---:|---:|
| 前端生产依赖 | **0** | **0** |
| E2E 生产依赖 | **0** | **0** |
| 前端 dev 依赖 | 3（vite `server.fs.deny` bypass） | **0** |
| E2E dev 依赖 | 28（6 low / 3 moderate / 19 high） | **29**（5 / 3 / 21） |

生产依赖干净，说明**当前交付物没有已知 CVE**。

⚠️ **E2E 那两栏数字不可直接相比**：首轮的 28 是在**不完整的 `node_modules`** 上测出来的 ——
当时 committed 的 `e2e/package-lock.json` 缺了 `@wdio/local-runner`（TD-016），`npm ci`
装不出 runner，审计自然也扫不到它的子树。补齐 lock 后的完整依赖树真实值是 **33**，
经「删未使用的 `@wdio/allure-reporter` + 两轮非破坏性 `npm audit fix`」降到 **29**，
且剩余 29 项**全部**要求 WDIO 8→9 major 升级 → 阻塞于 TD-016，见台账 TD-020。

> ⚠️ **Rust 侧结果以 CI 首轮为准**：本机 `cargo audit` 拉不到 RustSec advisory-db
> （与推送 502 同源的代理问题），无法本地取证。若 CI 首轮红，按需加 allowlist 或升级，
> 不要直接把 job 设成 `continue-on-error`。

```bash
# 本地复现（CI 同命令）
cd asd-tauri      && npm audit --package-lock-only --omit=dev --audit-level=high
cd asd-tauri/e2e  && npm audit --package-lock-only --omit=dev --audit-level=high
```

### 4.7 E2E 本地跑起来（Windows）

CI 的 E2E job **默认关闭**（`workflow_dispatch` 且 `run_e2e` 为真才跑，见 TD-016）。
要在本机实跑，四个前提缺一不可：

| 前提 | 怎么确认 / 怎么装 |
|------|------------------|
| Tauri debug 二进制 | `asd-tauri/target/debug/asd-tauri.exe`（`npm run tauri build -- --debug`） |
| `tauri-driver` | `cargo install tauri-driver` → `%USERPROFILE%\.cargo\bin\tauri-driver.exe` |
| **`msedgedriver.exe`** | 版本须与本机 Edge **完全一致**，放在 `asd-tauri/e2e/drivers/`（该目录已被 .gitignore 忽略，不会误提交） |
| Vite dev server | `wdio.conf.js` 会自动拉起 5173；已运行时则复用 |

msedgedriver 的取法（版本号看 `C:\Program Files (x86)\Microsoft\Edge\Application\<版本>\`）：

```bash
mkdir -p asd-tauri/e2e/drivers
curl -sSL -o asd-tauri/e2e/drivers/edriver.zip \
  "https://msedgedriver.microsoft.com/<EDGE_VERSION>/edgedriver_win64.zip"
python -c "import zipfile;zipfile.ZipFile('asd-tauri/e2e/drivers/edriver.zip').extract('msedgedriver.exe','asd-tauri/e2e/drivers')"
```

然后 `cd asd-tauri/e2e && npx wdio run wdio.conf.js --spec ./specs/smoke.spec.js`。

> ⚠️ **看起来像「`getTitle()` 超时」的失败，真因往往是 Vite 冷转换，不是窗口没起来。**
> 本机实测：Vite 首次转换 `/src/styles.css` 要 **51166ms**（热缓存 0.68ms）→ 首屏 load 约 54s →
> WebDriver 的 `getTitle()` / `execute()` **都会阻塞到页面 load 完成**（页面就绪后实测均为 5ms）
> → 首个命令吃满 mocha 的 60s 预算。**窗口标题其实是正确的、页面也是好的。**
> `wdio.conf.js` 的 `onPrepare` 已在建会话前预热（顺序请求 `/`、`/@vite/client`、`/src/main.js`、
> `/src/styles.css`），所以每次跑会先付约 60s 预热成本 —— 诊断行见
> `asd-tauri/e2e/reports/e2e-diagnostic.log` 里的「预热」字样。完整定位过程（含被推翻的
> 「应用启动慢 / 代理作祟 / getTitle 本身慢」三个错误假设）见
> `asd-tauri/e2e/docs/e2e-known-issues.md` 的 **ISSUE-018**。

> ⚠️ **改完 `e2e/package.json` 必须重生成 `package-lock.json` 并提交**。曾经 lock 里漏了
> `@wdio/local-runner`，而 CI 用 `npm ci`（严格按 lock 装）→ runner 缺失 → `wdio` 直接起不来。
> `npm ls --depth=0` 应能看到全部声明的依赖且无 `missing/invalid`。
>
> ⚠️ 若报 `Cannot find module '.../node_modules/<pkg>/index.js'` 之类，是 **node_modules 半损坏**
> （安装过程中途被中断）。`npm install` 往往自愈不了 —— 删掉那个具体目录再 `npm install` 即可。
cd asd-tauri      && cargo audit        # 需要能访问 RustSec advisory-db
```

### 4.6.6 静态分析档位（TD-012，2026-09-16 起）

此前 lint 只有「默认档」：clippy 跑 `correctness/style/complexity/perf`（默认 warn 组），
前端**根本没有 lint**。2026-09-16 收紧为两档，并把「哪些开、哪些不开、为什么」写进配置。

#### Rust：纯逻辑 crate 开 `clippy::pedantic`

| 范围 | 档位 | 理由 |
|---|---|---|
| `asd-domain` / `asd-ipc-protocol` / `asd-application` / `asd-test-harness` | **pedantic**（`[lints] workspace = true`） | 业务逻辑与调度在这里，最需要护栏 |
| `src-tauri` | 默认档 | 实测 pedantic 有 **587** 项，其中 **476** 项是 Tauri 样板代码的文档类噪声。开了等于把真信号淹掉 —— 先守住业务逻辑，入口层另行排期 |

- **阈值**只放 `asd-tauri/clippy.toml`；**启停**只放根 `Cargo.toml` 的 `[workspace.lints]`。
  两处都能改级别，分散了就没人看得全，最后变成「不知道某条 lint 到底开没开」。
- 组 lint 用 `priority = -1`，好让下面逐条的 `allow` 稳稳盖住它。
- 两条**有意暂缓**（登记 TD-021）：`missing_errors_doc` / `missing_panics_doc`
  —— 它们要的是给 59 个公开函数补 `# Errors` / `# Panics` 小节，属于文档工程，
  混在「收紧 lint」里做只会让这次改动失去焦点。
- 测试代码豁免 4 条（`similar_names` / `match_wildcard_for_single_variants` /
  `match_same_arms` / `case_sensitive_file_extension_comparisons`）：
  它们在**生产代码里是信号，在测试里是噪声**（对照组命名本就要相似、
  `_ => panic!("Expected X")` 就是断言意图）。豁免写在各 lib.rs 与集成测试文件顶部，
  逐条注明了理由，不是无脑 `allow`。

> 💡 **收紧的第一个回报**：`#[must_use]` 上线后立刻报出
> `src-tauri/benches/benchmarks.rs` 里 `ConfigValidator::validate(&groups);` 丢弃了返回值 ——
> 那是个**纯函数**，优化器可以把整段调用删掉，也就是说那个基准可能一直在测空转。
> 已改为 `black_box(...)`。这正是「加 lint 不是仪式」的意思。

#### 前端：ESLint 9（flat config）

```bash
cd asd-tauri && npm run lint     # = eslint src --max-warnings 70
```

- **只 lint `src/`**：前端就 `api.js` / `main.js` 两个文件（约 1500 行），
  而 JS 单测只覆盖 `e2e/helpers` —— **main.js 是零测试覆盖的**。
  对没有测试兜底的代码，静态分析是唯一一道自动检查。
- **棘轮，不是清零**：存量 70 项（`no-redeclare` 42 / `no-unused-vars` 18 /
  `no-empty` 6 / `no-prototype-builtins` 4）**全是风格债，无一为真缺陷**。
  main.js 没有测试，在这种代码上批量改名/删变量的收益远小于风险，
  所以这 4 条降为 `warn`，用 `--max-warnings 70` 把水位钉在 `package.json`：
  **新增一处立刻红**（71 > 70），修好一处就把数字减一（见 §4.6.1 同款棘轮语义）。
- 其余 recommended 规则保持 `error`：`no-undef` 这类「写了就一定错」的不留余地。
- 走独立 job（`js-lint`），与主 job 并行，不占用 Rust 构建的关键路径。

**阳性对照（4 组）**：探针文件注入 1 处 `no-redeclare` + 1 处 `no-undef`
→ 72 problems（1 error / 71 warnings）、退出码 1；删除探针 → 回到 70 / 退出码 0。
clippy 侧：pedantic 从 248 项收干到 0（`cargo clippy --workspace --all-targets -- -D warnings`
退出码 0），Rust 全量测试 602 项通过。

### 4.7 发布构建

```powershell
# 完整发布构建（前端 + Rust + AHK）
cd d:\1demo\AutoHotkeydemo\asd-tauri

# 1. 编译 AHK 子进程
cd src-tauri
.\build_ahk.ps1

# 2. Tauri 完整构建
cd ..
npm run tauri build

# 产物位置
# MSI 安装包: src-tauri/target/release/bundle/msi/
# NSIS 安装包: src-tauri/target/release/bundle/nsis/
```

### 4.8 配置文件位置

| 环境 | config.json 位置 | 日志文件位置 |
|---|---|---|
| 开发模式 | `src-tauri/config.json` | `{app_data_dir}/asd.log` |
| 生产环境 | `{app_data_dir}/config.json` | `{app_data_dir}/asd.log` |

`{app_data_dir}` 通常为 `C:\Users\{username}\AppData\Roaming\asd-tauri\`

### 4.9 常用开发命令速查

```powershell
# === 开发 ===
npm run tauri dev                    # 启动开发模式

# === 测试 ===
cd src-tauri && cargo test           # 运行所有 Rust 测试
cd src-tauri && cargo test -- --nocapture  # 显示测试输出
cd src-tauri && cargo bench           # 运行基准测试

# === 代码质量 ===
# 注意：工作目录为 workspace 根 asd-tauri（不是 src-tauri）
cargo clippy --workspace --all-targets -- -D warnings  # Clippy 检查（与 CI 一致）
cargo fmt --all --check                          # 格式化检查
cargo fmt --all                                  # 自动格式化
scripts/check-gates.sh                           # 一键跑 DoD 四闸门

# === AHK ===
.\src-tauri\build_ahk.ps1            # 编译 AHK 子进程

# === 构建 ===
npm run tauri build                  # 完整发布构建

# === 日志 ===
Get-Content "$env:APPDATA\asd-tauri\asd.log" -Tail 20 -Wait  # 实时查看日志
```

### 4.10 推送与 CI 结论核查（TD-028）

⚠️ 本地 `scripts/check-gates.sh` 全绿 **不等于 CI 绿** —— 两者连被测平台都不一样：
本机只有 Windows，CI 跑 ubuntu + windows-latest，另有 coverage（G3f）、miri、依赖审计、
ESLint（G2c）等本机不跑的检查项。2026-09-16 的实测后果：**连续 9 次 main 推送 CI 全红、
跨度约 3 小时无人发现** —— 因为没有任何环节会去看 CI 结论。

**推送后必须查结论**（成本一行命令）：

```bash
# 推送（撞 502 时交替直连/代理重试，并以远端 sha 核验 —— 见下）
bash scripts/push-and-verify.sh main

# 取最近一次 run 的 id，然后阻塞等它跑完并看每个 job 的结论
id=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$id"

# 只要结论（非阻塞）
gh run view "$id" --json conclusion,jobs \
  --jq '{conclusion, jobs: [.jobs[] | {name, conclusion}]}'
```

⚠️ **判「红在哪」之前，先分辨是不是账户级故障**：

| 现象 | 结论 |
|---|---|
| job 的 **steps 为空**、**1～3 秒内失败**、ubuntu 与 windows **一起挂**、连 miri / 依赖审计这些与改动无关的 job 也挂 | **账户级（额度/账单）**。注解为 `The job was not started because recent account payments have failed or your spending limit needs to be increased` → 去 Settings → Billing & plans 处理。**不要改代码、不要改 workflow** |
| 只有某几个 job 红，steps 有内容、失败落在具体步骤上 | 真实失败，按 job 名定位 |

两个推送侧的坑（都踩过，详见 `.workbuddy-ai/memory/env-and-ci.md`）：

- ⚠️ **别用 `git push ... | tail` 判退出码** —— `if` 取到的是 `tail` 的 0，502 失败也会打印
  `PUSH_OK`。用 `> /tmp/p.log 2>&1; rc=$?`。
- ⚠️ **`rc=0` 也不够**：实测过一次「打印 `PUSH_OK`、但 `rc` 取的是上一条残留值、远端根本没动」。
  唯一可信的判据是**比对远端 sha**：
  ```bash
  LOCAL=$(git rev-parse HEAD)
  R=$(git ls-remote https://github.com/zyejf/AutoHotkeydemo.git main | awk '{print $1}')
  [ "$R" = "$LOCAL" ] && echo "VERIFIED" || echo "NOT PUSHED"
  ```
  （`gh api repos/.../commits/main` 也能查，但 `ls-remote` 更轻、不依赖 API 配额。）
- ⚠️ **E2E 在 CI 上默认关闭**（`.github/workflows/ci.yml` 里 `workflow_dispatch` 手动触发），
  所以「CI 绿」**不包含**端到端链路。要验 E2E 必须手动触发或按 §4.7 本地跑。

---

## 附录 A：关键类型速查

### AppError 枚举

```rust
pub enum AppError {
    Config(String),        // 配置错误
    Ipc(String),           // IPC 通信错误
    GroupNotFound(String), // 分组不存在
    Validation(String),    // 验证失败
    Executor(String),      // 执行器错误
    Internal(String),      // 内部错误
}
```

### IpcError 枚举

```rust
pub enum IpcError {
    ConnectionClosed,              // 连接已关闭
    MessageTooLarge(usize, usize), // 消息超过大小上限
    EmptyMessage,                  // 收到空行
    JsonError(String),             // JSON 解析错误
    IoError(String),               // IO 错误
    Timeout,                       // 等待响应超时
    ChannelClosed,                 // 通道已关闭
    PipeBroken(String),            // 管道断裂
    NameError(String),             // 命名管道错误
}
```

### WatchdogStateEnum 枚举

```rust
pub enum WatchdogStateEnum {
    Idle,        // 初始状态
    Starting,    // 正在启动
    Running,     // 正常运行
    Hung,        // 心跳超时，挂起
    Restarting,  // 正在重启
    Recovering,  // 正在恢复（重新下发配置）
    Failed,      // 超过最大重启次数
}
```

### AppState 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `config` | `RwLock<Config>` | 配置数据 |
| `groups` | `RwLock<HashMap<String, SkillGroup>>` | 技能分组运行时状态 |
| `ipc_manager` | `tokio::sync::Mutex<Option<IpcManager>>` | IPC 管理器 |
| `ipc_outbound` | `IpcOutboundSender` | IPC 出站消息发送端 |
| `active_hotkeys` | `RwLock<HashMap<String, String>>` | 热键注册表 (groupId -> hotkey) |
| `emergency_mode` | `AtomicBool` | 紧急模式标志 |
| `hold_mode_enabled` | `AtomicBool` | 长按模式开关 |
| `watchdog_state` | `RwLock<WatchdogState>` | 看门狗状态快照 |
| `watchdog` | `Arc<tokio::sync::Mutex<ProcessWatchdog>>` | 看门狗实例 |

---

## 附录 B：RwLock 跨 await 注意事项

`RwLockReadGuard` 和 `RwLockWriteGuard`（来自 `std::sync`）不是 `Send`，不能跨 `.await` 持有。这是 Rust 并发编程中的常见陷阱。

**错误写法**：

```rust
// 编译错误：RwLockReadGuard 不是 Send，不能跨 await
let groups = state.groups.read().unwrap();
for (id, group) in groups.iter() {
    state.try_send_ipc_command(&cmd).await;  // .await 时仍持有 guard
}
```

**正确写法**（参考 [lib.rs:setup_ipc_callbacks](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/lib.rs#L130-L181)）：

```rust
// 先收集数据，再跨 await
let active_group_ids: Vec<String> = {
    let groups = state.groups.read().ok();
    groups.map(|g| {
        g.iter()
            .filter(|(_, group)| group.active)
            .map(|(id, _)| id.clone())
            .collect()
    }).unwrap_or_default()
};  // guard 在此释放

for id in active_group_ids {
    state.try_send_ipc_command(&cmd).await;  // 安全：guard 已释放
}
```

---

## 附录 C：windows Crate 双版本隔离

项目使用 `windows` 0.62.2，Tauri 依赖链使用 `windows` 0.61.x。两个版本的类型完全隔离，不能互传。

```
项目 (windows 0.62.2)          Tauri 依赖链 (windows 0.61.x)
  |                                  |
  +-- Win32_Foundation               +-- Win32_Foundation (不同版本)
  +-- Win32_System_JobObjects        +-- Win32_System_Threading
  +-- Win32_System_Threading         +-- ...
  +-- Win32_UI_WindowsAndMessaging
```

**约束**：两个版本的 `HANDLE`、`HWND` 等类型不能直接互传。如果需要跨版本传递，必须通过原始值（如 `isize`、`u32`）中转。

---

## 附录 D：配置 serde 策略详解

[config.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/crates/asd-domain/src/config.rs) 采用**方案 B（自定义 Deserialize + 手动 Serialize）**处理 10 种执行模式的 GroupConfig：

### 反序列化流程

1. 先将 JSON 反序列化为 `serde_json::Value`
2. 提取 `mode` 字段
3. 根据 `mode` 值选择对应的 `ModeData` 变体反序列化
4. 提取公共字段（`hotkey`、`name`、`holdKeys` 等）
5. 组装 `GroupConfig`

### 序列化流程

1. 先序列化公共字段到 `serde_json::Map`
2. 将 `ModeData` 序列化为 `serde_json::Value`
3. 将 `ModeData` 的字段合并（flatten）到 `serde_json::Map`
4. 输出扁平 JSON 对象

### 为什么不用 `#[serde(untagged)]` + `#[serde(flatten)]`

- `untagged` 尝试每个变体的反序列化顺序不确定
- `flatten` 与 `untagged` 组合在 serde 中有已知 bug
- 自定义实现可以精确控制字段提取和合并逻辑

---

## 附录 E：Tauri Command 注册清单

[lib.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/lib.rs) 中注册的 34 个 Tauri Command（`generate_handler!` 与 `EXPECTED_TAURI_COMMAND_COUNT == 34` 编译时断言保持一致）：

| Command | 源文件 | 参数 | 返回类型 |
|---|---|---|---|
| `get_config` | [config_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/config_cmd.rs) | 无 | `Result<Config, AppError>` |
| `save_config` | config_cmd.rs | `{ config: Config }` | `Result<(), AppError>` |
| `validate_config` | config_cmd.rs | `{ config: Config }` | `Result<ValidationResult, AppError>` |
| `list_backups` | config_cmd.rs | 无 | `Result<Vec<BackupInfo>, AppError>` |
| `create_backup` | config_cmd.rs | 无 | `Result<String, AppError>` |
| `restore_backup` | config_cmd.rs | `{ filename: String }` | `Result<(), AppError>` |
| `delete_backup` | config_cmd.rs | `{ filename: String }` | `Result<(), AppError>` |
| `hot_reload` | config_cmd.rs | 无 | `Result<Config, AppError>` |
| `export_config` | config_cmd.rs | `{ path: String }` | `Result<(), AppError>` |
| `import_config` | config_cmd.rs | `{ path: String }` | `Result<(), AppError>` |
| `compare_configs` | config_cmd.rs | `{ backupFilename: String }` | `Result<ConfigDiff, AppError>` |
| `get_groups` | [group_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/group_cmd.rs) | 无 | `Result<Vec<GroupSummary>, AppError>` |
| `toggle_group` | group_cmd.rs | `{ groupId: String }` | `Result<GroupStatus, AppError>` |
| `get_group_detail` | group_cmd.rs | `{ groupId: String }` | `Result<SkillGroup, AppError>` |
| `delete_group` | group_cmd.rs | `{ groupId: String }` | `Result<(), AppError>` |
| `toggle_all` | group_cmd.rs | `{ active: bool }` | `Result<BatchToggleResult, AppError>` |
| `batch_toggle_groups` | group_cmd.rs | `{ groupIds: Vec<String>, active: bool }` | `Result<BatchToggleResult, AppError>` |
| `batch_delete_groups` | group_cmd.rs | `{ groupIds: Vec<String> }` | `Result<BatchDeleteResult, AppError>` |
| `reorder_groups` | group_cmd.rs | `{ groupIds: Vec<String> }` | `Result<ReorderResult, AppError>` |
| `register_hotkey` | [hotkey_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/hotkey_cmd.rs) | `{ hotkey: String, groupId: String }` | `Result<(), AppError>` |
| `unregister_hotkey` | hotkey_cmd.rs | `{ hotkey: String }` | `Result<(), AppError>` |
| `start_recording` | [recording_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/recording_cmd.rs) | `{ groupId: String, mode: String }` | `Result<(), AppError>` |
| `stop_recording` | recording_cmd.rs | 无 | `Result<RecordingResult, AppError>` |
| `pause_recording` | recording_cmd.rs | 无 | `Result<u64, AppError>` |
| `resume_recording` | recording_cmd.rs | 无 | `Result<u64, AppError>` |
| `export_recording` | recording_cmd.rs | `{ path, keys, intervals, delays, mode }` | `Result<(), AppError>` |
| `import_recording` | recording_cmd.rs | `{ path: String }` | `Result<ImportedRecording, AppError>` |
| `start_validation` | recording_cmd.rs | `{ groupId: String }` | `Result<u64, AppError>` |
| `stop_validation` | recording_cmd.rs | 无 | `Result<u64, AppError>` |
| `get_executor_status` | [system_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/system_cmd.rs) | 无 | `Result<WatchdogState, AppError>` |
| `emergency_release` | system_cmd.rs | 无 | `Result<(), AppError>` |
| `clear_emergency` | system_cmd.rs | 无 | `Result<(), AppError>` |
| `toggle_hold_mode` | system_cmd.rs | 无 | `Result<bool, AppError>` |
| `reset_watchdog` | system_cmd.rs | 无 | `Result<(), AppError>` |
