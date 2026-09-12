# AHK v2 -> Rust/Tauri 迁移指南

> 版本: 1.1 | 最后更新: 2026-09-13
>
> 本文档面向从 AutoHotkey v2 架构迁移到 Rust/Tauri 混合架构的开发者，提供完整的接口映射、IPC 协议规范和配置兼容性说明。

---

## 目录

1. [架构概览](#1-架构概览)
2. [AHK -> Rust/Tauri 接口映射表](#2-ahk--rusttauri-接口映射表)
3. [IPC 协议文档](#3-ipc-协议文档)
4. [配置兼容性说明](#4-配置兼容性说明)
5. [已知差异与注意事项](#5-已知差异与注意事项)

---

## 1. 架构概览

### 1.1 迁移前后架构对比

**迁移前（纯 AHK v2）**：

```
asd.ahk (主入口)
  +-- domain/          (SkillGroup, SkillManager, ModeRegistry, KeyValidator)
  +-- infrastructure/  (ConfigStore, JsonParser, DebugLogger, ErrorSystem, IpcChannel)
  +-- application/     (ConfigService, GroupService)
  +-- presentation/    (WebView2Manager, UiManager, GuiManager)
  +-- config.json      (运行时配置)
```

**迁移后（Rust/Tauri + AHK 子进程）**：

```
asd.exe (Tauri 主进程)
  +-- Rust Workspace (asd-tauri/, 5 crates)
  |   +-- asd-domain/         (Config, Models, Validator, Traits)
  |   +-- asd-ipc-protocol/   (IpcCommand, IpcMessage, IpcError, HotkeyMerger)
  |   +-- asd-application/    (AppState, ConfigRepository, services)
  |   +-- asd-test-harness/   (测试固件 + Mock 工具)
  |   +-- src-tauri/          (34 Tauri Commands, IpcManager, Watchdog, Logging)
  +-- WebView2 UI (HTML/JS/CSS)
      +-- api.js           (invoke() 调用 Tauri Commands)

asd_executor.exe (AHK 子进程, 由 Watchdog 管理)
  +-- executor.ahk     (主入口, CommandDispatcher)
  +-- ipc_client.ahk   (Named Pipe 客户端)
  +-- hotkey_hook.ahk  (热键注册/注销)
  +-- sender.ahk       (按键发送)
  +-- joystick.ahk     (vJoy 操作)
```

### 1.2 双层 IPC 架构

```
前端 (JS)  <-- invoke()/emit() -->  Rust Backend  <-- Named Pipe -->  AHK 子进程
   |                                     |                              |
   |  Tauri 内置 IPC (<0.1ms)           |  JSON Lines IPC (<1.2ms)    |
   |                                     |                              |
   v                                     v                              v
 api.js                            Tauri Commands              CommandDispatcher
```

- **第一层**：JS <-> Rust，通过 Tauri 内置 `invoke()`/`emit()` 通信，类型安全，零配置
- **第二层**：Rust <-> AHK，通过 Named Pipe JSON Lines 协议通信，seq/ack_seq 确认

---

## 2. AHK -> Rust/Tauri 接口映射表

### 2.1 AHK 函数/方法 -> Rust/Tauri Command 映射

#### 2.1.1 配置管理

| 原 AHK 函数/方法 | 新 Rust/Tauri Command | 说明 |
|---|---|---|
| `ConfigStore.Load()` | `get_config` | 读取配置，Rust 侧用 `serde_json` 反序列化 |
| `ConfigService.SaveConfig()` | `save_config` | 保存配置，Rust 侧先校验再写入 |
| `ConfigValidator.Validate()` | `validate_config` | 配置校验，Rust 侧 `ConfigValidator::validate()` |
| `ConfigStore.GetGroup(id)` | `get_group_detail` | 获取分组详情，返回 `SkillGroup` 结构体 |
| `ConfigStore.GetAllGroups()` | `get_groups` | 获取所有分组摘要，返回 `Vec<GroupSummary>` |

#### 2.1.2 分组操作

| 原 AHK 函数/方法 | 新 Rust/Tauri Command | 说明 |
|---|---|---|
| `SkillManager.ToggleGroup(id)` | `toggle_group` | 切换分组激活状态，同时通过 IPC 通知 AHK |
| `SkillManager.ActivateGroup(id)` | `toggle_group` (active=true) | 激活分组，内部调用 `set_group_active(id, true)` |
| `SkillManager.DeactivateGroup(id)` | `toggle_group` (active=false) | 停用分组，内部调用 `set_group_active(id, false)` |
| `GroupService.GetActiveGroups()` | `get_groups` (前端过滤) | 获取活跃分组，前端通过 `active` 字段过滤 |

#### 2.1.3 热键注册

| 原 AHK 函数/方法 | 新 Rust/Tauri Command | 说明 |
|---|---|---|
| `SkillManager.RegisterHotkey(hk, id)` | `register_hotkey` | 注册热键，Rust 侧维护 `active_hotkeys` Map |
| `SkillManager.UnregisterHotkey(hk)` | `unregister_hotkey` | 注销热键，同时通过 IPC 通知 AHK |

#### 2.1.4 录制控制

| 原 AHK 函数/方法 | 新 Rust/Tauri Command | 说明 |
|---|---|---|
| `KeyRecorder.Start(id, mode)` | `start_recording` | 开始录制，通过 IPC 转发到 AHK |
| `KeyRecorder.Stop()` | `stop_recording` | 停止录制，返回 `RecordingResult` |

#### 2.1.5 系统命令

| 原 AHK 函数/方法 | 新 Rust/Tauri Command | 说明 |
|---|---|---|
| `SkillManager.EmergencyRelease()` | `emergency_release` | 紧急释放所有按键 |
| `SkillManager.ToggleHoldMode()` | `toggle_hold_mode` | 切换长按模式 |
| `Watchdog.GetStatus()` | `get_executor_status` | 获取执行器（AHK 子进程）状态 |

### 2.2 AHK COM Bridge 调用 -> Tauri invoke() 调用映射

原 AHK 项目使用 WebView2 COM Bridge 进行 JS <-> AHK 通信：

```javascript
// 旧方式：COM Bridge (postMessage)
window.chrome.webview.postMessage({action: "GetGroupList", requestId: "req-001"});
// 通过 window.chrome.webview.addEventListener("message", handler) 接收响应
```

新 Tauri 项目使用 `invoke()` 直接调用 Rust Command：

```javascript
// 新方式：Tauri invoke
import { invoke } from '@tauri-apps/api/core';

const groups = await invoke('get_groups');
const status = await invoke('toggle_group', { groupId: '1' });
```

#### 完整映射表

| 原 JS Bridge 调用 | 新 Tauri invoke() 调用 | 返回类型 |
|---|---|---|
| `ahkCall("GetGroupList")` | `invoke('get_groups')` | `Vec<GroupSummary>` |
| `ahkCall("GetConfig")` | `invoke('get_config')` | `Config` |
| `ahkCall("SaveConfig", config)` | `invoke('save_config', { config })` | `void` |
| `ahkCall("ToggleGroup", {id})` | `invoke('toggle_group', { groupId: id })` | `GroupStatus` |
| `ahkCall("GetGroupDetail", {id})` | `invoke('get_group_detail', { groupId: id })` | `SkillGroup` |
| `ahkCall("RegisterHotkey", {hk, id})` | `invoke('register_hotkey', { hotkey: hk, groupId: id })` | `void` |
| `ahkCall("UnregisterHotkey", {hk})` | `invoke('unregister_hotkey', { hotkey: hk })` | `void` |
| `ahkCall("StartRecording", {id, mode})` | `invoke('start_recording', { groupId: id, mode })` | `void` |
| `ahkCall("StopRecording")` | `invoke('stop_recording')` | `RecordingResult` |
| `ahkCall("EmergencyRelease")` | `invoke('emergency_release')` | `void` |
| `ahkCall("ToggleHoldMode")` | `invoke('toggle_hold_mode')` | `bool` |
| `ahkCall("GetExecutorStatus")` | `invoke('get_executor_status')` | `WatchdogStateEnum` |
| `ahkCall("ValidateConfig", config)` | `invoke('validate_config', { config })` | `ValidationResult` |

#### 事件监听映射

| 原 JS 事件监听 | 新 Tauri 事件监听 | 说明 |
|---|---|---|
| `window.chrome.webview.addEventListener("message", handler)` | `listen('status_update', handler)` | 状态更新事件 |
| (无对应) | `listen('hotkey_event', handler)` | 热键触发事件 |
| (无对应) | `listen('executor_status', handler)` | 执行器状态变更事件 |

### 2.3 AHK 全局变量 -> Rust AppState 映射

| 原 AHK 全局变量 | 新 Rust AppState 字段 | 类型 | 说明 |
|---|---|---|---|
| `global GroupSettings` (Map) | `AppState.config` | `RwLock<Config>` | 配置数据，含 `group_settings` |
| `SkillManager._groups` (Map) | `AppState.config_state.groups` | `RwLock<ConfigState>`（内 `groups: IndexMap<String, SkillGroup>`） | 技能分组运行时状态（保留分组顺序） |
| `SkillManager._activeHotkeys` (Map) | `AppState.active_hotkeys` | `RwLock<HashMap<String, String>>` | 热键注册表 (groupId -> hotkey) |
| `SkillManager._emergencyMode` | `AppState.emergency_mode` | `AtomicBool` | 紧急模式标志 |
| `SkillManager._holdModeEnabled` | `AppState.hold_mode_enabled` | `AtomicBool` | 长按模式开关 |
| (无对应) | `AppState.ipc_manager` | `tokio::sync::Mutex<Option<IpcManager>>` | IPC 管理器 |
| (无对应) | `AppState.watchdog` | `Arc<tokio::sync::Mutex<ProcessWatchdog>>` | 子进程看门狗 |
| (无对应) | `AppState.watchdog_state` | `RwLock<WatchdogState>` | 看门狗状态快照 |
| `DebugLogger.enabled` | `tracing` 环境变量 | `EnvFilter` | 日志级别由 `RUST_LOG` 控制 |

---

## 3. IPC 协议文档

### 3.1 通信架构

```
Rust 主进程 (asd.exe)                    AHK 子进程 (asd_executor.exe)
+------------------------+              +------------------------+
|  IpcManager            |              |  IpcClient             |
|  (服务端/Listener)      |    Pipe      |  (客户端)               |
|  create_listener()     |<============>|  DllCall CreateFileW   |
|  accept_loop()         |              |  PeekNamedPipe/ReadFile|
|  send() / recv()       |              |  WriteFile             |
+------------------------+              +------------------------+
        |                                        |
        v                                        v
  Tauri Commands                          CommandDispatcher
  (业务逻辑入口)                           (命令分发器)
```

- **Rust 为服务端**：通过 `interprocess` crate 创建 Named Pipe Listener，等待 AHK 连接
- **AHK 为客户端**：通过 `DllCall("CreateFileW", ...)` 连接到 Named Pipe
- **连接方向**：AHK 主动连接 Rust（Rust 先启动 Listener，AHK 后启动连接）

### 3.2 协议参数

| 参数 | 值 | 说明 |
|---|---|---|
| 管道名称 | `\\.\pipe\asd_ipc` | Windows Named Pipe 路径 |
| Rust 侧 API | `interprocess::local_socket` | `to_ns_name::<GenericNamespaced>()` |
| AHK 侧 API | `DllCall("CreateFileW", ...)` | Windows API 直接调用 |
| 帧分隔符 | `\n` (0x0A) | 每条消息一行（JSON Lines 格式） |
| 最大消息尺寸 | 64KB (65536 bytes) | 超过则丢弃并记录错误 |
| 编码 | UTF-8 | JSON Lines 标准约定 |
| 通道容量 | 256 | `mpsc::channel(256)` |

### 3.3 消息格式

#### 3.3.1 通用消息结构 (IpcMessage)

```json
{
  "id": "req-001",          // 可选，请求标识
  "type": "command",        // 消息类型：command/response/ping/pong/execute/result/hotkey/shutdown/error/heartbeat
  "seq": 42,                // 序列号，单调递增
  "ack_seq": 10,            // 可选，确认的请求 seq
  "action": "toggle_group", // 可选，命令动作
  "keys": ["1", "2"],       // 可选，按键列表
  "delay": 50,              // 可选，延迟（毫秒）
  "status": "ok",           // 可选，状态
  "data": { ... }           // 可选，附加数据
}
```

字段省略规则：`id`、`ack_seq`、`action`、`keys`、`delay`、`status`、`data` 为 `None` 时不序列化，减少消息体积。

#### 3.3.2 消息类型详解

**Rust -> AHK：执行指令**

```json
{"type":"command","seq":1,"action":"toggle_group","data":{"groupId":"1","active":true}}
{"type":"command","seq":2,"action":"register_hotkey","data":{"hotkey":"F1","groupId":"1"}}
{"type":"command","seq":3,"action":"unregister_hotkey","data":{"hotkey":"F1"}}
{"type":"command","seq":4,"action":"start_recording","data":{"groupId":"3","mode":"periodic"}}
{"type":"command","seq":5,"action":"stop_recording"}
{"type":"command","seq":6,"action":"emergency_release"}
{"type":"command","seq":7,"action":"hold_mode_toggle","data":{"enabled":true}}
```

**AHK -> Rust：执行结果**

```json
{"type":"result","seq":100,"ack_seq":1,"data":{"status":"ok","groupId":"1","active":true}}
{"type":"result","seq":101,"ack_seq":2,"data":{"status":"ok","hotkey":"F1","groupId":"1"}}
```

**AHK -> Rust：热键事件**

```json
{"type":"hotkey","seq":200,"action":"hotkey_event","keys":["F1"]}
```

**心跳协议**

```json
// Rust -> AHK: ping
{"type":"ping","seq":50}

// AHK -> Rust: pong
{"type":"pong","seq":51,"ack_seq":50}
```

**关机指令**

```json
// Rust -> AHK: shutdown
{"type":"shutdown","seq":99,"action":"shutdown"}
```

**错误上报**

```json
{"type":"error","seq":300,"action":"error","data":{"code":"SEND_FAILED","message":"SendInput returned 0"}}
```

**按键执行**

```json
// Rust -> AHK: 执行按键
{"type":"execute","seq":10,"action":"keypress","keys":["1","2"],"delay":50}

// AHK -> Rust: 执行结果
{"type":"result","seq":11,"ack_seq":10,"data":{"status":"ok","elapsed_ms":12}}
```

### 3.4 IpcCommand 枚举

Rust 侧定义的 IPC 命令枚举，通过 `#[serde(tag = "action")]` 序列化：

| IpcCommand 变体 | action 值 | data 字段 | 说明 |
|---|---|---|---|
| `ToggleGroup { group_id, active }` | `toggle_group` | `{groupId, active}` | 切换技能组 |
| `RegisterHotkey { hotkey, group_id }` | `register_hotkey` | `{hotkey, groupId}` | 注册热键 |
| `UnregisterHotkey { hotkey }` | `unregister_hotkey` | `{hotkey}` | 注销热键 |
| `StartRecording { group_id, mode }` | `start_recording` | `{groupId, mode}` | 开始录制 |
| `StopRecording` | `stop_recording` | 无 | 停止录制 |
| `PauseRecording` | `pause_recording` | 无 | 暂停录制 |
| `ResumeRecording` | `resume_recording` | 无 | 恢复录制 |
| `EmergencyRelease` | `emergency_release` | 无 | 紧急释放 |
| `Ping` | `ping` | 无 | 心跳检测 |
| `Shutdown` | `shutdown` | 无 | 关机指令 |
| `HoldModeToggle { enabled }` | `hold_mode_toggle` | `{enabled}` | 长按模式切换 |
| `StartValidation { group_id }` | `start_validation` | `{groupId}` | 开始校验 |
| `StopValidation` | `stop_validation` | 无 | 停止校验 |

### 3.5 seq/ack_seq 确认机制

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

**关键规则**：

| 规则 | 说明 |
|---|---|
| seq 单调递增 | Rust 侧 `AtomicU64`，从 1 开始递增 |
| ack_seq 语义 | 最近成功处理的消息 seq，非累积确认 |
| 重复检测 | AHK 侧忽略 `seq <= lastAckSeq` 的消息（ping 除外） |
| 超时重传 | 不实现（IPC 为本机通信，丢包概率极低） |
| 乱序处理 | AHK 侧按 seq 排序执行（仅 execute 类型） |
| 等待响应 | Rust 侧 `wait_response(seq, timeout)` 使用 oneshot channel |

### 3.6 心跳协议

| 参数 | 值 | 说明 |
|---|---|---|
| 心跳间隔 | 1s | Rust 侧定时发送 ping |
| 判定超时 | 3s (3 次未响应) | Watchdog 判定子进程挂起 |
| 重启后首次超时 | 5s | AHK 启动需要初始化时间 |
| AHK 侧超时 | 5s | AHK 侧检测 Rust 无响应后断线重连 |

**心跳流程**：

```
Rust (每 1s)                     AHK
  |                                 |
  |--- ping seq=N ----------------->|
  |                                 |
  |<-- pong seq=M, ack_seq=N -------|
  |                                 |
  |  (Watchdog notify_heartbeat)    |
  |  (重置 missed_heartbeats = 0)    |
```

**超时检测**：

```
Rust Watchdog (每 1s tick)
  |
  |-- 检查 last_heartbeat elapsed
  |   |-- < 3s: 正常
  |   |-- >= 3s: missed_heartbeats++
  |       |-- missed < 3: 继续等待
  |       |-- missed >= 3: 状态 -> Hung, 触发重启
```

### 3.7 背压与流控

| 场景 | 策略 |
|---|---|
| AHK -> Rust 高频热键事件 | 合并窗口：100ms 内同组热键事件合并为一条（`HotkeyMerger`） |
| Rust -> AHK 执行指令堆积 | 指令去重：同组 toggle 指令只保留最新一条 |
| Named Pipe 缓冲区满 | `write_all` 阻塞等待，天然背压 |
| IPC 通道容量 | `mpsc::channel(256)` |

### 3.8 错误恢复路径

| 错误类型 | 检测方式 | 恢复动作 |
|---|---|---|
| 管道断裂 | `read_line` 返回 0 或 `BrokenPipe` | 关闭连接 -> 触发 Watchdog -> 重启 AHK |
| 消息格式错误 | `serde_json::from_str` 失败 | 记录日志，丢弃该消息 |
| 消息超尺寸 | `len() > 65536` | 丢弃，记录错误日志 |
| AHK 无响应 | 心跳超时（3 次 x 1s = 3s） | Watchdog 判定挂起，强制终止并重启 |
| AHK 崩溃退出 | `child.try_wait()` 检测 | Watchdog 自动重启，指数退避 |
| AHK 连接失败 | `CreateFileW` 返回 INVALID_HANDLE | 指数退避重连（1s -> 2s -> 4s -> ... -> 30s） |

### 3.9 AHK 侧 IPC 客户端实现要点

AHK 子进程使用 Windows API 直接操作 Named Pipe，无第三方依赖：

```autohotkey
; 连接管道
hPipe := DllCall("CreateFileW",
    "Str", "\\.\pipe\asd_ipc",
    "UInt", 0xC0000000,  ; GENERIC_READ | GENERIC_WRITE
    "UInt", 0,            ; SHARE_NONE
    "Ptr", 0,
    "UInt", 3,            ; OPEN_EXISTING
    "UInt", 0x80,         ; FILE_ATTRIBUTE_NORMAL
    "Ptr", 0, "Ptr")

; 轮询读取
DllCall("PeekNamedPipe", "Ptr", hPipe, ...)
DllCall("ReadFile", "Ptr", hPipe, ...)

; 写入消息
DllCall("WriteFile", "Ptr", hPipe, ...)
```

AHK 内置精简 JSON 解析器（`MiniJson` 类），支持 IPC 协议所需的所有 JSON 结构，无需外部 JSON 库。

---

## 4. 配置兼容性说明

### 4.1 config.json 100% 向后兼容

Rust 侧使用 `serde_json` 反序列化，完全兼容现有 `config.json` 格式。关键兼容性措施：

1. **BOM 处理**：`ConfigRepository::load_from_file()`（推荐 `load_from_file_checked()`）自动去除 UTF-8 BOM（`\u{feff}`）
2. **字段重命名**：使用 `#[serde(rename = "...")]` 映射 camelCase JSON 字段到 snake_case Rust 字段
3. **可选字段**：使用 `Option<T>` + `#[serde(default)]` + `#[serde(skip_serializing_if = "Option::is_none")]`
4. **缺失字段**：反序列化时缺失的可选字段自动填充为 `None` 或默认值
5. **Roundtrip 一致**：反序列化 -> 序列化后 JSON 结构一致（可选字段为 None 时不输出）

### 4.2 10 种执行模式 serde 映射

#### 4.2.1 映射策略

采用**方案 B（自定义 Deserialize + 手动 Serialize）**，而非 `#[serde(untagged)]` + `#[serde(flatten)]`：

- `GroupConfig` 使用自定义 `Deserialize` 实现：先提取 `mode` 字段，再根据 mode 值选择对应的 `ModeData` 变体反序列化
- `GroupConfig` 使用自定义 `Serialize` 实现：将公共字段和 `ModeData` 内部字段合并输出为扁平 JSON 对象
- `GroupItem`（hybrid 内部子组）使用 `#[serde(tag = "type")]` 鉴别 `periodic`/`sequence`

#### 4.2.2 模式字段映射

| 模式 | ModeData 变体 | 必需字段 (JSON名) | 可选字段 (JSON名) |
|---|---|---|---|
| `periodic` | `Periodic(PeriodicData)` | `keys`, `intervals` | -- |
| `sequence` | `Sequence(SequenceData)` | `keys`, `delays` | -- |
| `hybrid` | `Hybrid(HybridData)` | `groups` | `seqInterval` |
| `hold` | `Hold(HoldData)` | `holdDuration` | `autoRepeat`, `repeatInterval` |
| `enhanced_periodic` | `EnhancedPeriodic(EnhancedPeriodicData)` | `pressKeys`, `intervals` | -- |
| `enhanced_sequence` | `EnhancedSequence(EnhancedSequenceData)` | `pressKeys`, `pressDelays` | -- |
| `enhanced_hybrid` | `EnhancedHybrid(EnhancedHybridData)` | `groups` | `seqInterval` |
| `joystick_periodic` | `JoystickPeriodic(JoystickPeriodicData)` | `pressKeys`, `intervals` | `joystickId` |
| `joystick_sequence` | `JoystickSequence(JoystickSequenceData)` | `pressKeys`, `delays` | `joystickId` |
| `joystick_hold` | `JoystickHold(JoystickHoldData)` | -- | `holdDuration`, `autoRepeat`, `repeatInterval`, `joystickId` |

#### 4.2.3 公共字段

所有模式共享以下公共字段（位于 `GroupConfig` 层级）：

| JSON 字段 | Rust 字段 | 类型 | 必需 |
|---|---|---|---|
| `hotkey` | `hotkey` | `String` | 是 |
| `mode` | `mode` | `String` | 是 |
| `keyPressDuration` | `key_press_duration` | `Option<u64>` | 否 |
| `name` | `name` | `Option<String>` | 否 |
| `holdKeys` | `hold_keys` | `Option<Vec<String>>` | 否 |
| `holdMode` | `hold_mode` | `Option<String>` | 否 |
| `holdPattern` | `hold_pattern` | `Option<String>` | 否 |
| `holdTriggers` | `hold_triggers` | `Option<Vec<serde_json::Value>>` | 否 |

#### 4.2.4 Hybrid 内部子组 (GroupItem)

```json
{
  "type": "periodic",
  "pressKeys": ["1", "2"],
  "intervals": [50, 60]
}
```

```json
{
  "type": "sequence",
  "pressKeys": ["A", "S"],
  "delays": [100, 200],
  "seqInterval": 50
}
```

使用 `#[serde(tag = "type")]` 自动根据 `type` 字段鉴别变体。

### 4.3 顶层配置结构

```json
{
  "CONTROL_HOTKEYS": {
    "emergency": "F10",
    "releaseAllHolds": "^r",
    "showStatus": "^0",
    "toggleAll": "^1",
    "toggleHoldMode": "^h"
  },
  "GroupSettings": {
    "1": { "hotkey": "F1", "mode": "periodic", ... },
    "2": { "hotkey": "F2", "mode": "hold", ... }
  },
  "HoldSettings": {
    "allowOverlap": false,
    "checkInterval": 50,
    "debounceDelay": 25,
    "pressSpeed": 80,
    "releaseOnEmergency": true
  },
  "lastModified": "2026-05-29T12:00:00",
  "version": "3.0"
}
```

| JSON 字段 | Rust 字段 | 类型 | 必需 |
|---|---|---|---|
| `CONTROL_HOTKEYS` | `control_hotkeys` | `ControlHotkeys` | 是 |
| `GroupSettings` | `group_settings` | `IndexMap<String, GroupConfig>` | 是 |
| `HoldSettings` | `hold_settings` | `Option<HoldSettings>` | 否 |
| `lastModified` | `last_modified` | `Option<String>` | 否 |
| `version` | `version` | `Option<String>` | 否 |

---

## 5. 已知差异与注意事项

### 5.1 通信方式变更

| 差异点 | AHK v2 (旧) | Rust/Tauri (新) | 影响 |
|---|---|---|---|
| JS <-> 后端通信 | COM Bridge postMessage | Tauri invoke() | 前端 API 层需重写 |
| 后端 <-> 执行层 | 直接函数调用 | Named Pipe IPC | 引入 IPC 延迟 (<1.2ms) |
| 错误传播 | try-catch + ErrorSystem | AppError 枚举 + thiserror | 错误类型更精确 |
| 状态管理 | 全局变量 + Map | AppState (RwLock + AtomicBool) | 线程安全保证 |

### 5.2 功能差异

| 功能 | AHK v2 原接口 | Rust/Tauri IPC action | 状态 |
|---|---|---|---|
| 批量操作 | `BatchToggleGroups` | `batch_toggle`（`group_cmd.rs`） | ✅ 已实现 |
| 备份管理 | `CreateBackup` / `RestoreBackup` | `create_backup` / `restore_backup`（`config_cmd.rs`） | ✅ 已实现 |
| 配置导入导出 | `ExportConfig` / `ImportConfig` | `export_config` / `import_config`（`config_cmd.rs`） | ✅ 已实现 |
| 分组排序 | `ReorderGroups` | `reorder_groups`（`group_cmd.rs`） | ✅ 已实现 |
| 分组删除 | `DeleteGroup` | `delete_group`（`group_cmd.rs`） | ✅ 已实现 |
| 配置热重载 | `HotReload` | `hot_reload`（`config_cmd.rs`） | ✅ 已实现 |

### 5.3 性能差异

| 指标 | AHK v2 | Rust/Tauri | 提升 |
|---|---|---|---|
| 配置加载 (13KB JSON) | ~120ms | <5ms | 24x |
| 按键校验 (100键) | ~50ms | ~1ms | 50x |
| JS <-> 后端 IPC | ~5-10ms (COM Bridge) | <0.1ms (Tauri invoke) | 50-100x |
| 启动到可用 | 1-2s | 200-400ms | 3-5x |

### 5.4 关键注意事项

1. **Named Pipe 连接顺序**：Rust 必须先启动 Listener（`spawn_ipc_accept_loop`），再启动 AHK 子进程（`wd.spawn_child()`），否则 AHK 连接会失败
2. **关机标志**：Rust 关机时必须先设置 `shutting_down` 标志（`mgr.mark_shutting_down()`），避免 AHK 退出后误触发 `pipe_broken` 回调导致 Recovering 状态
3. **RwLock 跨 await**：`RwLockReadGuard` 不是 `Send`，不能跨 `.await` 持有。必须先收集数据再跨 await（参考 `setup_ipc_callbacks` 中的 `active_group_ids` 收集模式）
4. **windows crate 双版本**：项目使用 `windows` 0.62.2，Tauri 依赖链使用 `windows` 0.61.x，两者类型完全隔离，无互传场景
5. **AHK 子进程模式**：支持编译模式（`asd_executor.exe`）和便携模式（`AutoHotkey64.exe executor.ahk`），优先使用编译模式
6. **config.json 写入**：Rust 侧 `ConfigRepository::save_to_path()` 使用 `serde_json::to_string_pretty()` 格式化输出并原子写入（先写临时文件再重命名），与 AHK 侧输出格式可能略有差异（缩进/排序），但语义完全一致
7. **未知 mode 值**：Rust 侧反序列化遇到未知 mode 会返回错误（`unknown mode: xxx`），不会静默忽略。这是与 AHK 侧的行为差异（AHK 侧可能忽略未知模式）
8. **HoldSettings 缺失**：`HoldSettings` 为 `Option<HoldSettings>`，缺失时 Rust 侧使用 `None`，不影响运行
