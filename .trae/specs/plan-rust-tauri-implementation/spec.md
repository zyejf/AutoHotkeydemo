# Rust/Tauri 重写项目全面实施计划

## Why

基于 v8.0 调研报告（2861 行，8 轮深度审查），需要将现有 AutoHotkey v2 项目（13,184 行/37 文件/DDD 四层架构）迁移为 Tauri 2.11.2 混合架构（Rust/Tauri 主进程 + AHK 执行子进程）。本计划覆盖项目全生命周期（Phase 0-5），提供可执行、可追踪的详细路线图，确保全面覆盖调研文档中提及的技术要点、架构设计和性能要求。

## What Changes

- **Phase 0: PoC 验证** — Tauri + serde + IPC 可行性验证，Go/No-Go 决策
- **Phase 1: 基础设施** — Tauri 骨架 + 配置管理 + 日志系统 + IPC 框架 + Watchdog + AppState
- **Phase 2: 核心域模型** — 10 种模式 serde 映射 + 配置校验 + 执行调度 + Tauri Commands
- **Phase 3: Tauri UI 集成** — 前端迁移 + 系统托盘 + 全局快捷键 + 数据绑定
- **Phase 4: AHK 子进程适配** — Named Pipe 客户端 + 热键/执行/vJoy 适配 + Ahk2Exe 编译
- **Phase 5: 集成测试与打磨** — 测试体系 + 性能基准 + 构建打包 + 优雅关机 + 自动更新

## Impact

- Affected specs: `rust-tauri-migration`（全阶段）、`fix-ipc-architecture-defects`（IPC 修复）
- Affected code:
  - `asd-tauri/` — 全新 Rust/Tauri 项目
  - `ahk_executor/` — 新建 AHK 子进程目录
  - `config.json` — 100% 向后兼容

## ADDED Requirements

### Requirement: 项目背景与目标

系统 SHALL 基于 Tauri 2.11.2 混合架构完成项目迁移，达成以下目标：

| 目标维度 | AHK v2 现状 | Rust/Tauri 目标 | 提升倍数 | 置信度 |
|---------|------------|---------------|:-------:|:-----:|
| 启动速度 | 1-2s | <300ms | 3-5x | 低 |
| 类型错误检测 | 运行时 | 编译时 | ∞ | 高 |
| 内存安全 | 无保证 | 编译期保证 | ∞ | 高 |
| 配置加载 (13KB JSON) | ~120ms | <5ms | 24x | 高 |
| 按键校验 (100键) | ~50ms | ~1ms | 50x | 中 |
| 分组调度 (10组) | ~20ms | ~2ms | 10x | 中 |
| JS↔Rust IPC | ~5-10ms (COM Bridge) | <0.1ms (Tauri invoke) | 50-100x | 高 |
| 打包体积 | ~10MB+AHK运行时 | ~5-8MB | 1.5x+ | 中 |
| 内存占用 (含WebView2) | ~150-200MB | ~60-90MB | -55% | 中 |
| 安装包 | 无 | NSIS/MSI | 标准化 | 高 |
| 自动更新 | 无 | tauri-plugin-updater | 新增 | 高 |

#### Scenario: 迁移后性能达标
- **WHEN** 完成所有 Phase 并通过验收
- **THEN** criterion 基准测试确认配置加载 <5ms、JS↔Rust IPC <0.1ms、Named Pipe 往返 <1.2ms、启动速度 200-400ms

### Requirement: 架构设计

系统 SHALL 采用以下混合架构：

```
┌──────────────────────────────────────────────────────────┐
│  Tauri 2.11 App (asd.exe ~5-8MB)                         │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │  WebView2 UI      │  │  Rust Backend                │ │
│  │  (HTML/JS/CSS)    │  │  Tauri Commands (13个)       │ │
│  │  invoke()/listen()│◄─┼─►Domain Layer                │ │
│  │                   │  │  Infrastructure Layer         │ │
│  └──────────────────┘  │  Named Pipe IPC Manager       │ │
│                         └───────────────┼──────────────┘ │
└─────────────────────────────────────────┼────────────────┘
                                          │ Pipe: \\.\pipe\asd_ipc
┌─────────────────────────────────────────┼────────────────┐
│  AHK 子进程 (asd_executor.exe)          │                │
│  Hotkey Hook / SendInput / vJoy / IPC Client             │
└──────────────────────────────────────────────────────────┘
```

**双层 IPC 架构**：
1. **Tauri 内置 IPC**：JS ↔ Rust（`invoke`/`emit`），类型安全，零配置
2. **Named Pipe IPC**：Rust ↔ AHK 子进程，JSON Lines 协议 + seq/ack_seq 确认

#### Scenario: IPC 通信正常
- **WHEN** 前端调用 `invoke('toggle_group', { groupId: '1' })`
- **THEN** Rust Tauri Command → IpcManager → Named Pipe → AHK 执行 → 结果上报 → 前端状态更新

### Requirement: 主要实施阶段划分

系统 SHALL 按 6 个阶段实施：

| 阶段 | 名称 | 状态 | 工时估算 | 关键交付物 |
|------|------|:----:|:-------:|-----------|
| Phase 0 | PoC 验证 | ✅ 完成 | 1 周 | Go/No-Go 决策：GO |
| Phase 1 | 基础设施 | ✅ 完成 | 2 周 | Config/IpcManager/Watchdog/AppState |
| Phase 2 | 核心域模型 | ✅ 完成 | 3 周 | 10 种模式 serde + 13 个 Commands + SkillManager |
| Phase 3 | Tauri UI 集成 | ✅ 完成 | 2 周 | 前端迁移 + 系统托盘 + 全局快捷键 |
| Phase 4 | AHK 子进程适配 | ⏳ 待实施 | 1 周 | ipc_client.ahk + 热键/执行适配 + asd_executor.exe |
| Phase 5 | 集成测试与打磨 | ⏳ 待实施 | 2 周 | 测试报告 + 性能基准 + NSIS 安装包 |

**剩余总工时**：3.5 周（单人全职）或 2 周（2 人协作）

#### Scenario: 阶段完成判定
- **WHEN** 某阶段所有任务完成且验收清单全部勾选
- **THEN** 该阶段标记为完成，进入下一阶段

### Requirement: IPC 协议规范

系统 SHALL 使用以下 Named Pipe JSON Lines 协议：

**协议参数**：

| 参数 | 值 | 说明 |
|------|-----|------|
| 管道名称 | `\\.\pipe\asd_ipc` | Rust 为 Listener（服务端），AHK 为 Client |
| 帧分隔符 | `\n` (0x0A) | 每条消息一行 |
| 最大消息尺寸 | 64KB | 超过则丢弃并重连 |
| 编码 | UTF-8 | JSON Lines 标准约定 |
| seq 类型 | `u64` | 理论上限 1.8×10¹⁹，不会溢出 |
| ack_seq 语义 | 最近成功处理的消息 seq | 非累积确认 |
| 重复检测 | AHK 侧忽略 seq ≤ 最近 ack_seq 的消息 | 简单有效 |
| 超时重传 | 不实现 | IPC 为局域通信，丢包概率极低 |
| 乱序处理 | AHK 侧按 seq 排序执行（仅 execute 类型） | hotkey 事件不排序 |

**消息格式**：

```json
// Rust → AHK: 执行指令
{"id":"req-001","type":"execute","action":"send_keys","keys":["a","b"],"delay":50,"seq":1}

// AHK → Rust: 执行结果
{"id":"req-001","type":"result","status":"ok","elapsed_ms":12,"ack_seq":1}

// AHK → Rust: 热键事件
{"id":"evt-001","type":"hotkey","key":"F1","timestamp":1716912000,"seq":2}

// 心跳: ping/pong
{"type":"ping","ts":1716912000}
{"type":"pong","ts":1716912000}

// 错误上报
{"type":"error","code":"SEND_FAILED","message":"SendInput returned 0","seq":3}
```

**IpcCommand 枚举**（Rust 侧）：
- `ToggleGroup { group_id, active }`
- `RegisterHotkey { hotkey, group_id }`
- `UnregisterHotkey { hotkey }`
- `StartRecording { group_id, mode }`
- `StopRecording`
- `EmergencyRelease`
- `Ping`
- `Shutdown`
- `HoldModeToggle { enabled }`

**背压与流控**：

| 场景 | 策略 |
|------|------|
| AHK → Rust 高频热键事件 | 合并窗口：100ms 内同组热键事件合并为一条 |
| Rust → AHK 执行指令堆积 | 指令去重：同组 toggle 指令只保留最新一条 |
| Named Pipe 缓冲区满 | `write_all` 阻塞等待，天然背压 |
| IPC 通道容量 | `mpsc::channel(256)` |

**错误恢复路径**：

| 错误类型 | 检测方式 | 恢复动作 |
|---------|---------|---------|
| 管道断裂 | `read_line` 返回 0 或 `BrokenPipe` | 关闭连接，触发 Watchdog 重启 |
| 消息格式错误 | `serde_json::from_str` 失败 | 记录日志，丢弃该消息 |
| 消息超尺寸 | `len() > 65536` | 丢弃，记录错误日志 |
| AHK 无响应 | 心跳超时（3 次 × 1s = 3s） | Watchdog 判定挂起，强制终止并重启 |
| AHK 崩溃退出 | `WaitForSingleObject` 检测 | Watchdog 自动重启，指数退避 |

#### Scenario: IPC 通信健壮性
- **WHEN** AHK 子进程崩溃或管道断裂
- **THEN** Rust 侧 Watchdog 检测 → 指数退避重启 → 状态恢复 → 重新建立 IPC 连接

### Requirement: 配置兼容性 10 模式 serde 映射

系统 SHALL 100% 兼容现有 `config.json`，支持 10 种执行模式：

| 模式 | 必需字段 | 可选字段 | 结构类型 |
|------|---------|---------|---------|
| `periodic` | `keys`, `intervals` | — | 扁平 |
| `sequence` | `keys`, `delays` | — | 扁平 |
| `hybrid` | `groups` | `seqInterval` | 嵌套 |
| `hold` | `holdKeys` | `holdDuration`, `autoRepeat`, `repeatInterval` | 扁平 |
| `enhanced_periodic` | `pressKeys`, `intervals` | `pressDelays`, `holdPattern`, `holdTriggers` | 扁平 |
| `enhanced_sequence` | `pressKeys`, `pressDelays` | `delays`/`intervals`(fallback), `holdTriggers`, `holdPattern` | 扁平 |
| `enhanced_hybrid` | `groups` | `holdTriggers`, `holdPattern` | 嵌套 |
| `joystick_periodic` | `joyKeys`, `joyIntervals` | `joySendMethod`, `joyKeyDuration` | 扁平 |
| `joystick_sequence` | `joyKeys`, `joyDelays` | `joySendMethod`, `joyKeyDuration` | 扁平 |
| `joystick_hold` | `joyKeys` | `joySendMethod`, `joyKeyDuration`, `holdDuration` | 扁平 |

**serde 映射策略**：采用方案 B（`untagged` + `flatten`），与现有 config.json 完全兼容：
- `GroupConfig` 结构体包含公共字段（`hotkey`/`name`/`keyPressDuration`/`mode`）+ 跨模式共享字段（`holdKeys`/`holdMode`/`holdPattern`/`holdTriggers`）
- `ModeData` 枚举使用 `#[serde(untagged)]` 按顺序匹配各模式特有字段
- `groups` 数组内部元素使用 `#[serde(tag = "type")]` 鉴别 `periodic`/`sequence`

**关键陷阱规避**：

| 陷阱 | 解决方案 |
|------|---------|
| `tag` + `flatten` 兼容性 | 使用 `untagged` + `flatten` 方案 B |
| `keys` vs `pressKeys` 命名不一致 | 不同 Variant 使用不同字段名，serde 自动处理 |
| `delays` fallback 到 `intervals` | `#[serde(default)]` + 自定义反序列化器 |
| `GroupSettings` key 混合类型 | `HashMap<String, GroupConfig>` 统一处理 |
| 未知 mode 值 | `#[serde(untagged)]` fallback 或 `serde_json::Value` |
| `holdPattern`/`holdTriggers` 结构未明 | `Vec<serde_json::Value>` 占位 |
| `HoldSettings` 可能不存在 | `Option<HoldSettings>` + `#[serde(default)]` |

#### Scenario: 配置兼容性验证
- **WHEN** 使用实际 `config.json` 进行 serde 反序列化
- **THEN** 所有 10 种模式正确解析，roundtrip 序列化后数据一致

### Requirement: ProcessWatchdog 状态机

系统 SHALL 实现 7 状态 Watchdog：

```
Idle → Starting → Running ⇄ Hung → Restarting → Recovering → Running
                                         ↓ (max retries)
                                       Failed
```

| 状态 | 触发条件 | 动作 |
|------|---------|------|
| Idle | 初始状态 | 等待 `start()` |
| Starting | `start()` 调用 | 启动 AHK 子进程 |
| Running | IPC 连接成功 | 心跳检测（1s 间隔） |
| Hung | 3 次心跳超时（共 3s） | 强制终止子进程 |
| Restarting | Hung 后延迟 | 指数退避等待（1s→2s→4s→8s→30s） |
| Recovering | 子进程重启成功 | 重新下发热键注册和配置 |
| Failed | 重启超过 10 次 | 放弃重启，通知前端 |

**心跳参数**：

| 参数 | 值 | 说明 |
|------|-----|------|
| 心跳间隔 | 1s | 更快检测异常 |
| 最大丢失次数 | 3 | 保持不变 |
| 判定挂起总时间 | 3s | 热键应用需要快速恢复 |
| 重启后首次心跳超时 | 5s | AHK 启动需要初始化时间 |
| 最大重启次数 | 10 | 超过则放弃 |

#### Scenario: 崩溃恢复
- **WHEN** AHK 子进程崩溃
- **THEN** Watchdog 检测 → Hung → Restarting（指数退避）→ Recovering（状态恢复）→ Running

### Requirement: 优雅关机三阶段

系统 SHALL 实现三阶段优雅关机：

| 阶段 | 方法 | 超时 | 说明 |
|------|------|:----:|------|
| Phase 1 | IPC `shutdown` 消息 | 2s | 给 AHK 清理时间 |
| Phase 2 | `WM_CLOSE`（PostMessage） | 3s | 替代 `GenerateConsoleCtrlEvent`（对 GUI 进程无效） |
| Phase 3 | `TerminateProcess` | 立即 | 强制终止 |

**孤儿进程防护**：使用 Windows Job Object + `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`，Rust 主进程退出时 Windows 自动终止子进程。使用 RAII 包装器 `JobObjectGuard` 防止句柄泄漏。

#### Scenario: 优雅关机
- **WHEN** Rust 主进程正常退出
- **THEN** Phase 1 发送 shutdown → 等待 2s → Phase 2 WM_CLOSE → 等待 3s → Phase 3 强制终止

### Requirement: 关键里程碑设定

系统 SHALL 设定以下关键里程碑：

| 里程碑 | 触发条件 | 交付物 | 状态 |
|--------|---------|--------|:----:|
| M0: PoC 通过 | Tauri + serde + IPC 全部验证 | Go/No-Go 决策 | ✅ |
| M1: 基础设施就绪 | Config/IpcManager/Watchdog 编译通过 | Rust 后端骨架 | ✅ |
| M2: 域模型完成 | 10 种模式 serde + 13 个 Commands | 核心业务逻辑 | ✅ |
| M3: UI 集成完成 | 前端迁移 + 托盘 + 快捷键 | 可交互的 Tauri App | ✅ |
| M4: IPC 修复完成 | cargo check + test + clippy 全部通过 | 可编译的 Rust 后端 | ✅ |
| M5: AHK IPC 客户端就绪 | AHK 连接 Rust Named Pipe + ping/pong | ahk_executor/ipc_client.ahk | ⏳ |
| M6: 热键执行链路贯通 | 前端 toggle → IPC → AHK → 结果上报 | 端到端热键功能 | ⏳ |
| M7: AHK 编译完成 | asd_executor.exe 编译成功且 IPC 正常 | asd_executor.exe | ⏳ |
| M8: 集成测试通过 | 单元/集成/E2E 测试全部通过 | 测试报告 | ⏳ |
| M9: 性能基准达标 | criterion 确认所有性能目标达成 | 基准测试报告 | ⏳ |
| M10: 安装包生成 | NSIS 安装包安装/卸载正常 | asd-setup.exe | ⏳ |
| M11: 项目交付 | 所有验收标准满足 | 完整交付物 | ⏳ |

#### Scenario: 里程碑延期处理
- **WHEN** 里程碑未按计划达成
- **THEN** 记录延期原因，评估影响，调整后续计划

### Requirement: 资源需求分析

系统 SHALL 明确以下资源需求：

| 资源类型 | 需求 | 说明 |
|---------|------|------|
| 开发人员 | 1-2 人 | Rust + AHK v2 双技能优先 |
| Rust 工具链 | 1.95.0+ | rust-toolchain.toml 已配置 |
| AHK 运行时 | v2.0 | `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` |
| Node.js | 20+ | 前端构建 |
| WebView2 | Edge Chromium | Windows 10+ 内置 |
| Tauri CLI | 2.x | `npm install @tauri-apps/cli` |
| vJoy SDK | 可选 | 虚拟手柄测试 |
| Windows | 10+ | 目标平台 |

**关键 Crate 依赖**：

| Crate | 版本 | 用途 | MSRV |
|-------|------|------|:----:|
| `tauri` | 2.11.2 | 应用框架 | 1.77.2 |
| `windows` | 0.62.2 | Windows API 绑定 | **1.82.0** |
| `serde` + `serde_json` | 1.0 / 1.0 | JSON 序列化 | 1.71 |
| `tokio` | 1.47.1 (LTS) | 异步运行时 | 1.70 |
| `interprocess` | 2.4.2 | AHK 子进程 IPC | 1.75 |
| `thiserror` | 2.0.18 | 错误派生宏 | 1.61 |
| `tracing` | 0.1.44 | 结构化日志 | 1.65 |
| `clap` | 4.6.1 | CLI 参数解析 | — |

**Tauri 插件**：

| 插件 | 版本 | 用途 |
|------|------|------|
| `tauri-plugin-global-shortcut` | 2.3.1 | 全局快捷键 |
| `tauri-plugin-updater` | 2.10.1 | 自动更新 |
| `tauri-plugin-dialog` | 2.7.1 | 文件对话框 |
| `tauri-plugin-fs` | 2.5.1 | 文件系统 |

**已知架构决策**：
- 系统托盘使用 `tauri` 核心 `tray-icon` feature（非独立插件 `tauri-plugin-tray`，该插件不存在）
- 不使用 `parking_lot`（性能优势可忽略，使用 `std::sync` + `tokio::sync`）
- 不使用 `anyhow`（AppError 使用 `thiserror` + 手动 `Serialize`）
- `windows` crate 0.62.2 与 Tauri 依赖的 0.61.x 双版本共存（类型隔离，无冲突）
- `interprocess` 使用 `local_socket` API + `to_ns_name::<GenericNamespaced>()`
- 项目 MSRV 为 1.95.0（实际由 `windows` 0.62.2 决定为 1.82.0，但 rust-toolchain.toml 配置为 1.95.0）

#### Scenario: 开发环境就绪
- **WHEN** 开发人员开始工作
- **THEN** 所有工具链和依赖已安装，`cargo build` 和 `npm run tauri dev` 可正常执行

### Requirement: 风险评估与应对策略

系统 SHALL 识别并应对以下风险：

| # | 风险 | 概率 | 影响 | 应对策略 |
|---|------|:----:|:----:|---------|
| R1 | IPC 架构缺陷修复后仍有编译错误 | 中→低 | 高 | 逐个修复编译错误，每修一个立即 cargo check 验证。**已缓解：M4 已达成** |
| R2 | AHK Named Pipe 客户端实现困难 | 中 | 高 | AHK DllCall 调用 Windows API，参考现有 ipc_channel.ahk；备选方案：使用文件管道过渡 |
| R3 | AHK 编译后 IPC 通信异常 | 低 | 高 | 编译前充分测试 .ahk 源码 IPC，编译后逐项验证 |
| R4 | 热键注册在 AHK 子进程中不工作 | 中 | 高 | 保留 AHK 原生热键能力，仅通过 IPC 下发注册/注销指令 |
| R5 | 性能基准测试未达标 | 低 | 中 | 识别瓶颈，优化热点路径；部分目标为理论估算，允许调整 |
| R6 | Tauri 权限配置遗漏 | 中 | 中 | 参照 tauri.conf.json 文档逐步配置，capabilities 包含 `global-shortcut:allow-register/unregister` |
| R7 | AHK 子进程崩溃恢复不完整 | 中 | 高 | ProcessWatchdog + 指数退避重启 + 状态恢复，Phase 5 专项验证 |
| R8 | config.json 兼容性问题 | 低→极低 | 高 | Phase 0 已验证 10 种模式反序列化，roundtrip 一致 |
| R9 | `windows` crate 双版本共存冲突 | 低 | 中 | 已验证类型隔离，无互传场景；体积增 2-3MB 可接受 |
| R10 | serde `untagged` + `flatten` 反序列化歧义 | 中 | 高 | Phase 0 验证 + 完整测试覆盖；`untagged` 按 Variant 顺序匹配 |
| R11 | `global-shortcut` API 变更 | 低 | 中 | 已锁定 2.3.1 版本，API 签名已验证 |
| R12 | WebView2 离线安装场景 | 低 | 中 | 默认 `downloadBootstrapper`，离线时提示用户手动安装 |

#### Scenario: 风险触发
- **WHEN** 识别到风险实际发生
- **THEN** 记录风险事件，执行应对策略，评估对里程碑的影响

### Requirement: 质量保障措施

系统 SHALL 实施以下质量保障措施：

| 措施 | 工具 | 频率 | 说明 |
|------|------|------|------|
| 编译检查 | `cargo check` | 每次代码修改 | 零编译错误 |
| 单元测试 | `cargo test --lib` | 每次代码修改 | 零测试失败 |
| Lint 检查 | `cargo clippy` | 每次代码修改 | 零警告 |
| 格式检查 | `cargo fmt --check` | 每次提交 | 统一代码风格 |
| 集成测试 | `cargo test` | 每阶段完成 | 覆盖 config/ipc/commands |
| E2E 测试 | 手动 + 自动 | Phase 5 | Tauri App + AHK 子进程全流程 |
| 性能基准 | criterion | Phase 5 | 回归检测 |
| 安全审计 | `cargo audit` | Phase 5 | 依赖漏洞扫描 |
| 许可证合规 | `cargo deny` | Phase 5 | 许可证检查 |
| AHK 语法检查 | `/ErrorStdOut` | 每次 AHK 代码修改 | 零语法错误 |
| AHK 错误接管 | `#ErrorStdOut` + `#Warn` + `OnError` | 所有 .ahk 文件 | 强制，无例外 |

**测试策略**：

```
单元测试 (cargo test --lib)
  ├── domain 层: 纯逻辑，无 Tauri 依赖
  │   ├── SkillManager toggle/activate/deactivate
  │   ├── ConfigValidator 10 种模式校验
  │   └── KeyValidator 按键校验
  ├── infrastructure 层: mock IPC/配置
  │   ├── IpcManager send_command/listen_ahk mock
  │   └── ProcessWatchdog 状态转换
  ├── application 层: mock domain
  │   ├── ConfigService 业务逻辑
  │   └── GroupService 业务逻辑
  └── commands 层: Tauri Command 单元测试
      └── mock AppState

集成测试 (tests/)
  ├── config_tests: 实际 config.json 反序列化 + roundtrip
  ├── ipc_tests: 本地 Named Pipe 回环测试（Rust 服务端 + 模拟客户端）
  └── tauri_command_tests: Tauri invoke 集成测试

端到端测试 (tests/e2e/)
  └── full_flow_tests: Tauri App + AHK 子进程
      ├── 完整热键流程：注册 → 触发 → 执行 → 结果上报
      ├── 分组 toggle 流程
      ├── 配置保存/加载流程
      └── EmergencyRelease 流程
```

**调试策略**：

| 场景 | 工具 | 方法 |
|------|------|------|
| Rust 后端调试 | `rust-analyzer` + VS Code | 标准 Rust 调试流程 |
| 前端调试 | Chrome DevTools | `tauri dev` 自动开启 |
| AHK 子进程调试 | `OutputDebug` + DebugView | AHK 原生调试输出 |
| IPC 通信调试 | `tracing` + 自定义 Subscriber | 记录所有 IPC 消息 |
| 性能分析 | `tracing-flame` + `inferno` | 火焰图分析 |

#### Scenario: 质量门禁
- **WHEN** 提交代码或完成阶段
- **THEN** cargo check + cargo test + cargo clippy 全部通过方可标记完成

### Requirement: 验收标准

系统 SHALL 满足以下验收标准方可标记项目完成：

**功能验收**：
- [F1] 前端通过 Tauri invoke 调用所有 13 个 Commands 正常
- [F2] AHK 子进程通过 Named Pipe IPC 与 Rust 通信正常
- [F3] 热键注册/注销通过 IPC 指令控制
- [F4] 按键模拟（Send/SendInput）通过 IPC 指令执行
- [F5] vJoy 调用通过 IPC 指令执行
- [F6] 10 种执行模式配置兼容
- [F7] ProcessWatchdog 崩溃恢复正常
- [F8] 优雅关机三阶段正常
- [F9] Job Object 孤儿进程防护正常
- [F10] 系统托盘 + 全局快捷键正常

**性能验收**：
- [P1] 配置加载 <5ms
- [P2] JS↔Rust IPC <0.1ms
- [P3] Named Pipe 往返 <1.2ms
- [P4] 启动到可用 200-400ms

**交付物验收**：
- [D1] NSIS 安装包生成成功
- [D2] 干净 Windows 环境安装/卸载正常
- [D3] asd_executor.exe 编译成功
- [D4] 所有测试通过（单元/集成/E2E）

#### Scenario: 项目交付
- **WHEN** 所有验收标准 [F1-F10]、[P1-P4]、[D1-D4] 满足
- **THEN** 项目标记为完成，输出交付物清单

## MODIFIED Requirements

### Requirement: IPC 架构缺陷修复纳入计划

原 `fix-ipc-architecture-defects` spec 中的编译修复工作 SHALL 纳入本计划作为 Phase 3 完成后的前置任务，在 Phase 4 实施前必须完成。

**已完成修复**：
- `Arc<String>` 所有权：`(*self.pipe_name).clone().to_ns_name::<GenericNamespaced>()`
- `RwLockWriteGuard` 跨 await：内层 `{}` 块确保 drop
- IpcCallback/StateChangeCallback 类型别名：消除 `type_complexity` 警告
- `JOBOBJECT_BASIC_LIMIT_INFORMATION` 初始化：`..Default::default()` 模式
- 6 个 clippy 自动修复

**验证结果**：`cargo check` ✅ / `cargo test --lib` 94 passed ✅ / `cargo clippy` 0 warnings ✅

## REMOVED Requirements

### Requirement: 裸 wry 架构
**Reason**: v3.0 架构决策已从裸 wry 切换为 Tauri 2.11.2
**Migration**: 无需迁移

### Requirement: parking_lot 依赖
**Reason**: v5.0 审查论证移除（性能优势可忽略，减少外部依赖）
**Migration**: 使用 std::sync + tokio::sync

### Requirement: tauri-plugin-tray 插件
**Reason**: Tauri 2.x 托盘是核心 tray-icon feature，tauri-plugin-tray 不存在
**Migration**: 使用 `tauri = { features = ["tray-icon"] }` + TrayIconBuilder

### Requirement: GenerateConsoleCtrlEvent 关机
**Reason**: 对 GUI 进程无效（Windows 文档明确指出）
**Migration**: 使用 WM_CLOSE（PostMessage 到子进程主窗口）

### Requirement: anyhow 错误处理
**Reason**: AppError 使用 thiserror + 手动 Serialize 更合适
**Migration**: 使用 `thiserror` 2.0.18 + 手动 `impl Serialize`
