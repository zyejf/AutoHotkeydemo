# Rust/Tauri 重写 AutoHotkeydemo 项目实施计划 Spec

## Why

现有 AutoHotkey v2 项目（13,184 行代码/37 个业务文件）存在性能瓶颈、缺乏类型安全、部署困难等问题。经过 v1.0→v8.0 共 8 轮深度审查的调研报告论证，采用 Tauri 2.11.2 混合架构（Rust/Tauri 主进程 + AHK 执行子进程）是当前最优迁移策略，预计可获得 3-5 倍启动速度提升、10 倍内存安全提升和编译期类型安全保障。

## What Changes

- **新建 Rust/Tauri 项目骨架**：基于 Tauri 2.11.2 框架，MSRV 1.95.0，DDD 四层架构适配
- **实现双层 IPC 通信**：Tauri invoke/emit（JS↔Rust）+ Named Pipe JSON Lines（Rust↔AHK）
- **迁移配置管理**：serde 反序列化 10 种执行模式的 config.json，兼容现有格式
- **实现子进程管理**：ProcessWatchdog 状态机 + Windows Job Object 孤儿防护 + WM_CLOSE 优雅关机
- **迁移前端 UI**：现有 HTML/CSS/JS 资产迁移至 Tauri WebView2，JS 调用改为 invoke
- **适配 AHK 子进程**：Named Pipe IPC 客户端替代文件管道，保留热键/按键模拟/vJoy 能力
- **构建打包部署**：Tauri NSIS 安装包 + 双 exe 分发 + 自动更新

## Impact

- Affected specs: 整体架构从纯 AHK 迁移为 Rust/Tauri + AHK 混合架构
- Affected code: 全部 37 个业务文件需评估迁移路径；核心域模型重写为 Rust；前端 JS API 层重写
- 依赖变更: 新增 tauri 2.11.2、windows 0.62.2、interprocess 2.4.2 等 Rust crate 生态

## ADDED Requirements

### Requirement: Phase 0 PoC 验证

系统 SHALL 在正式迁移前完成 PoC 验证，确认 Tauri + serde + IPC 技术栈可行。

#### Scenario: PoC 验证通过
- **WHEN** 完成 Tauri 项目初始化、config.json 反序列化、Named Pipe 双向通信、最小 WebView2 窗口四项验证
- **THEN** 输出 Go/No-Go 决策报告，所有验证项通过方可进入 Phase 1

#### Scenario: PoC 验证失败
- **WHEN** 任一验证项失败（如 serde 反序列化不兼容、IPC 延迟超标）
- **THEN** 记录失败原因，评估替代方案或终止迁移

### Requirement: Tauri 2.11.2 项目骨架

系统 SHALL 基于 Tauri 2.11.2 框架建立项目骨架，MSRV 设为 1.95.0。

#### Scenario: 项目初始化
- **WHEN** 执行 `npm create tauri-app` 初始化项目
- **THEN** 生成符合 Tauri 约定的目录结构（src-tauri/src/commands/、src-tauri/src/domain/ 等），Cargo.toml 包含所有必需依赖且版本锁定

### Requirement: 双层 IPC 通信

系统 SHALL 实现 Tauri invoke/emit（JS↔Rust）和 Named Pipe JSON Lines（Rust↔AHK）双层 IPC。

#### Scenario: JS↔Rust IPC
- **WHEN** 前端调用 `invoke('get_config')` 
- **THEN** Rust 侧 Tauri Command 处理请求并返回序列化结果，延迟 <0.1ms

#### Scenario: Rust↔AHK IPC
- **WHEN** Rust 通过 Named Pipe 发送 `{"type":"execute","action":"send_keys","keys":["a"],"seq":1}`
- **THEN** AHK 子进程接收并执行，返回 `{"type":"result","status":"ok","ack_seq":1}`，往返延迟 <1.2ms

#### Scenario: IPC 错误恢复
- **WHEN** Named Pipe 断裂
- **THEN** 检测断开 → 关闭旧连接 → 通知 Watchdog → 重启 AHK → 重建连接 → 恢复状态

### Requirement: 配置兼容性

系统 SHALL 完全兼容现有 config.json 格式，支持 10 种执行模式的 serde 反序列化。

#### Scenario: 反序列化现有配置
- **WHEN** 加载现有 config.json（含 hybrid/periodic/hold/enhanced_*/joystick_* 模式）
- **THEN** 所有 10 种模式正确反序列化，字段映射无丢失，roundtrip 序列化结果一致

#### Scenario: 未知模式处理
- **WHEN** config.json 包含未识别的 mode 值
- **THEN** 不崩溃，记录警告日志，保留原始 JSON 值供后续处理

### Requirement: 子进程生命周期管理

系统 SHALL 实现 ProcessWatchdog 状态机管理 AHK 子进程的完整生命周期。

#### Scenario: 正常运行
- **WHEN** AHK 子进程正常运行
- **THEN** 心跳检测（1s 间隔，3 次超时判定挂起），状态实时推送到前端

#### Scenario: 子进程崩溃恢复
- **WHEN** AHK 子进程崩溃或挂起
- **THEN** Watchdog 检测 → 指数退避重启（1s→2s→4s→8s→30s）→ 状态恢复（重新下发热键注册和活跃分组）→ 最多重启 10 次

#### Scenario: 优雅关机
- **WHEN** Rust 主进程退出
- **THEN** Phase 1: IPC shutdown 消息（2s 超时）→ Phase 2: WM_CLOSE（3s 超时）→ Phase 3: TerminateProcess

#### Scenario: 孤儿进程防护
- **WHEN** Rust 主进程异常退出
- **THEN** Windows Job Object（JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE）自动终止所有子进程

### Requirement: Tauri Commands API

系统 SHALL 暴露完整的 Tauri Commands API 覆盖配置管理、分组操作、热键注册、录制控制、系统命令。

#### Scenario: 统一错误处理
- **WHEN** 任何 Tauri Command 返回错误
- **THEN** 返回 `AppError` 枚举（Config/Ipc/GroupNotFound/Validation/Executor/Internal），序列化为字符串供前端解析

### Requirement: 性能目标

系统 SHALL 达到以下性能目标（需 criterion 基准测试验证）：

| 路径 | 目标 | 置信度 |
|------|------|:------:|
| 配置加载 (13KB JSON) | <5ms (24x 提升) | 高 |
| 按键校验 (100键) | <1ms (50x 提升) | 中 |
| JS↔Rust IPC | <0.1ms (50-100x 提升) | 高 |
| 启动到可用 | 200-400ms (5-8x 提升) | 低 |

### Requirement: 构建打包

系统 SHALL 通过 Tauri 内置打包生成 NSIS 安装包。

#### Scenario: 安装包生成
- **WHEN** 执行 `npm run tauri build`
- **THEN** 生成 NSIS 安装包，包含 asd.exe + asd_executor.exe + WebView2 Bootstrapper，AHK 子进程通过 Ahk2Exe 编译

### Requirement: windows crate 双版本共存

系统 SHALL 接受 `windows` 0.62.2（项目直接依赖）与 `windows` 0.61.x（Tauri 依赖链）的双版本共存。

#### Scenario: 类型隔离
- **WHEN** 项目代码使用 `windows` 0.62.2 的 API（WM_CLOSE/PostMessageW/CreateJobObjectW/SendInput/RegisterHotKey）
- **THEN** 与 Tauri 内部使用的 `windows` 0.61.x 类型完全隔离，无互传场景

## MODIFIED Requirements

### Requirement: DDD 四层架构适配

原 AHK 的 Domain/Application/Infrastructure/Presentation 四层架构 SHALL 适配为 Tauri 命令式架构：
- Domain 层：Rust 结构体 + serde 模型（替代 AHK 类）
- Application 层：Rust 服务逻辑（替代 AHK 函数）
- Infrastructure 层：Rust IPC/配置/日志（替代 AHK 文件操作）
- Presentation 层：Tauri Commands + JS 前端（替代 AHK GUI）

## REMOVED Requirements

### Requirement: 裸 wry 架构
**Reason**: v3.0 架构决策已从裸 wry 切换为 Tauri 2.11.2，内置 IPC/打包/插件减少约 800 行胶水代码
**Migration**: 无需迁移，Tauri 完全替代 wry 功能

### Requirement: parking_lot 依赖
**Reason**: v5.0 审查论证移除，本项目锁持有时间极短（<1ms），std::sync 性能差异可忽略
**Migration**: 使用 std::sync::RwLock + tokio::sync::Mutex 替代

### Requirement: tauri-plugin-tray 插件
**Reason**: Tauri 2.x 系统托盘是核心功能（tray-icon feature），不是独立插件
**Migration**: 使用 `tauri = { features = ["tray-icon"] }` + `TrayIconBuilder` API
