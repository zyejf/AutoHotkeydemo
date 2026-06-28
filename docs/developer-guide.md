# ASD-Tauri 开发者文档

> 版本: 1.0 | 最后更新: 2026-05-29
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
    api.js               # Tauri invoke() 封装层（13 个已实现 + 19 个 stub）
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

### 1.2 Rust 源码结构 (`src-tauri/src/`)

```
src/
  lib.rs                 # 主入口：Tauri Builder、IPC 初始化、Watchdog 启动、系统托盘、优雅关机
  main.rs                # 二进制入口（调用 lib.rs）

  domain/                # 领域层 -- 纯业务逻辑，无外部依赖
    mod.rs
    config.rs            # Config、GroupConfig、ModeData（10 种模式）、自定义 serde
    models.rs            # SkillGroup、IpcCommand（9 变体）、IpcMessage（8 种工厂方法）
    validator.rs         # ConfigValidator：10 模式校验、重复热键检测、跨字段校验

  infrastructure/        # 基础设施层 -- 外部交互
    mod.rs
    ipc.rs               # IpcManager（Named Pipe 服务端）、HotkeyMerger、IpcError
    watchdog.rs          # ProcessWatchdog（7 状态机）、JobObjectGuard、WatchdogRunner
    logging.rs           # tracing 初始化（文件 + 控制台双输出）

  application/           # 应用层 -- 状态管理与调度
    mod.rs
    state.rs             # AppState（中央状态）、AppError（6 变体）、WatchdogState
    scheduler.rs         # SkillManager：toggle/activate/deactivate、IPC 命令发送

  commands/              # 表现层 -- Tauri Command 入口
    mod.rs
    config_cmd.rs        # get_config、save_config、validate_config
    group_cmd.rs         # get_groups、toggle_group、get_group_detail
    hotkey_cmd.rs        # register_hotkey、unregister_hotkey
    recording_cmd.rs     # start_recording、stop_recording
    system_cmd.rs        # get_executor_status、emergency_release、toggle_hold_mode

  tests/                 # 集成测试
    mod.rs
    config_compat_tests.rs  # 配置兼容性测试
    ipc_tests.rs            # IPC 通信测试
```

### 1.3 AHK 子进程结构 (`src-tauri/ahk_executor/`)

```
ahk_executor/
  executor.ahk           # 主入口：CommandDispatcher（7 个 action handler）、初始化流程
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
  api.js                 # API 层：13 个 invoke() 调用 + 16 个 stub + 3 个事件监听
  main.js                # 前端入口
  style.css              # 全局样式
```

[api.js](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src/api.js) 中的函数分为三类：

| 类别 | 数量 | 说明 |
|---|---|---|
| 已实现的 invoke() | 13 | `getGroups`、`toggleGroup`、`getGroupDetail`、`saveConfig`、`getConfig`、`validateConfig`、`emergencyRelease`、`getExecutorStatus`、`toggleHoldMode`、`registerHotkey`、`unregisterHotkey`、`startRecording`、`stopRecording` |
| Stub（未实现） | 19 | `batchToggleGroups`、`batchDeleteGroups`、`deleteGroup`、`hotReload`、`createBackup`、`restoreBackup`、`deleteBackup`、`listBackups`、`compareConfigs`、`exportConfig`、`importConfig`、`reorderGroups`、`pauseRecording`、`resumeRecording`、`exportRecording`、`importRecording`、`startValidation`、`stopValidation`、`toggleAll` |
| 事件监听 | 3 | `onStatusUpdate`、`onHotkeyEvent`、`onExecutorStatus` |

### 1.5 依赖关系图

```
                    +-----------+
                    |  main.rs  |  (二进制入口)
                    +-----+-----+
                          |
                    +-----v-----+
                    |   lib.rs   |  (Tauri Builder + 初始化)
                    +-----+-----+
                          |
          +---------------+---------------+
          |               |               |
    +-----v-----+   +-----v-----+   +-----v-----+
    | commands/ |   |application|   |infrastruct|
    | (5 文件)   |   | (2 文件)   |   | (3 文件)   |
    +-----+-----+   +-----+-----+   +-----+-----+
          |               |               |
          +---------------+---------------+
                          |
                    +-----v-----+
                    |  domain/  |  (3 文件，纯业务逻辑)
                    +-----------+
```

依赖方向：`commands/` -> `application/` -> `domain/` + `infrastructure/` -> `domain/`

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

Rust 侧通过 `#[serde(tag = "action")]` 序列化 IpcCommand：

| IpcCommand 变体 | action 值 | data 字段 |
|---|---|---|
| `ToggleGroup { group_id, active }` | `toggle_group` | `{groupId, active}` |
| `RegisterHotkey { hotkey, group_id }` | `register_hotkey` | `{hotkey, groupId}` |
| `UnregisterHotkey { hotkey }` | `unregister_hotkey` | `{hotkey}` |
| `StartRecording { group_id, mode }` | `start_recording` | `{groupId, mode}` |
| `StopRecording` | `stop_recording` | 无 |
| `EmergencyRelease` | `emergency_release` | 无 |
| `Ping` | `ping` | 无 |
| `Shutdown` | `shutdown` | 无 |
| `HoldModeToggle { enabled }` | `hold_mode_toggle` | `{enabled}` |

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

| 模块 | 测试文件 | 测试数量 | 覆盖内容 |
|---|---|---|---|
| domain/config.rs | 内联 `#[cfg(test)]` | 20+ | 10 模式反序列化、roundtrip、缺失字段、未知模式、可选字段跳过 |
| domain/models.rs | 内联 `#[cfg(test)]` | 12+ | SkillGroup 构造、IpcCommand 9 变体 roundtrip、IpcMessage 工厂方法 |
| domain/validator.rs | 内联 `#[cfg(test)]` | 25+ | 10 模式校验、重复热键、跨字段、mode_data 类型不匹配 |
| infrastructure/ipc.rs | 内联 `#[cfg(test)]` | 20+ | HotkeyMerger、IpcMessage 构造、IpcError 转换、shutting_down 标志 |
| infrastructure/watchdog.rs | 内联 `#[cfg(test)]` | 10+ | 状态机、心跳、退避、WM_CLOSE |
| application/state.rs | 内联 `#[cfg(test)]` | 10+ | AppState 构造、分组操作、AppError 序列化 |

#### AHK 语法检查

```powershell
$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
& $ahkPath /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk" 2>&1
```

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
cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri

# Clippy 静态分析
cargo clippy -- -W clippy::all

# 格式化检查
cargo fmt -- --check

# 自动格式化
cargo fmt
```

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
cd src-tauri && cargo clippy -- -W clippy::all  # Clippy 检查
cd src-tauri && cargo fmt -- --check             # 格式化检查
cd src-tauri && cargo fmt                        # 自动格式化

# === AHK ===
.\src-tauri\build_ahk.ps1            # 编译 AHK 子进程

# === 构建 ===
npm run tauri build                  # 完整发布构建

# === 日志 ===
Get-Content "$env:APPDATA\asd-tauri\asd.log" -Tail 20 -Wait  # 实时查看日志
```

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

[config.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/domain/config.rs) 采用**方案 B（自定义 Deserialize + 手动 Serialize）**处理 10 种执行模式的 GroupConfig：

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

[lib.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/lib.rs#L363-L377) 中注册的 13 个 Tauri Command：

| Command | 源文件 | 参数 | 返回类型 |
|---|---|---|---|
| `get_config` | [config_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/config_cmd.rs) | 无 | `Config` |
| `save_config` | config_cmd.rs | `{ config: Config }` | `Result<(), AppError>` |
| `validate_config` | config_cmd.rs | `{ config: Config }` | `ValidationResult` |
| `get_groups` | [group_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/group_cmd.rs) | 无 | `Vec<GroupSummary>` |
| `toggle_group` | group_cmd.rs | `{ groupId: String }` | `Result<GroupStatus, AppError>` |
| `get_group_detail` | group_cmd.rs | `{ groupId: String }` | `Result<SkillGroup, AppError>` |
| `register_hotkey` | [hotkey_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/hotkey_cmd.rs) | `{ hotkey: String, groupId: String }` | `Result<(), AppError>` |
| `unregister_hotkey` | hotkey_cmd.rs | `{ hotkey: String }` | `Result<(), AppError>` |
| `start_recording` | [recording_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/recording_cmd.rs) | `{ groupId: String, mode: String }` | `Result<(), AppError>` |
| `stop_recording` | recording_cmd.rs | 无 | `Result<RecordingResult, AppError>` |
| `get_executor_status` | [system_cmd.rs](file:///d:/1demo/AutoHotkeydemo/asd-tauri/src-tauri/src/commands/system_cmd.rs) | 无 | `WatchdogState` |
| `emergency_release` | system_cmd.rs | 无 | `Result<(), AppError>` |
| `toggle_hold_mode` | system_cmd.rs | 无 | `Result<bool, AppError>` |
