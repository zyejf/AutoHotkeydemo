# Rust 重写 AutoHotkeydemo 项目 — 全面调研分析报告

> **版本**: v8.0 | **日期**: 2026-05-28 | **状态**: 第五轮深度审查修订
> **v8.0 第五轮审查**: `tauri-plugin-tray` 错误纠正（Tauri 2.x 托盘是核心 `tray-icon` feature，不是独立插件）、8.3/13.2/15.2/15.4 正文代码与审查章节一致性修正、4.5 节移除 `parking_lot`、Tauri 插件版本号 crates.io 实查更新（dialog 2.7.1、fs 2.5.1）、12.1 `interprocess` API 修正（`to_ns_name::<GenericNamespaced>()`）、5.1 性能表添加置信度列、6.3 capabilities 补充 `global-shortcut` 权限、6.6 `AppError` 移除 `anyhow` 依赖、7.2 Cargo 版本约束修正、15.2 `GenerateConsoleCtrlEvent`→`WM_CLOSE` 正文同步、15.4 `assign_to_job` 正文同步 `OpenProcess`
> **v7.0 第四轮审查**: 完整依赖链验证（crates.io 实查）、`interprocess` 兼容性确认、`AssignProcessToJobObject` 修正（`OpenProcess` 替代 PID）、`EnumWindows` 内存泄漏修正、`tauri-plugin-updater` 版本更新至 2.10.1、`on_shortcut` API 签名验证证据
> **v6.0 第三轮审查**: `windows` crate 版本冲突修正、`global-shortcut` API 签名修正、`GenerateConsoleCtrlEvent`→`WM_CLOSE`、Job Object RAII、IPC 序列化设计修正、Mutex 类型修正、serde 类型修正
> **v5.0 第二轮审查**: serde tag+flatten 兼容性修正、跨模式共享字段重构、Tauri 插件版本锁定、parking_lot 移除论证
> **v4.0 深度审查**: IPC 协议完善、Tauri Commands 完整 API、配置兼容性 10 模式 serde 映射、子进程管理细化
> **v3.0 架构决策**: 采用 **Tauri 2.11.2** 替代裸 wry 作为 UI 框架
> **v2.0 审查修订**: 修正 Crate 版本至最新稳定版、校准代码统计数据、补充 MSRV/IPC/架构遗漏

---

## 一、执行摘要

本报告对使用 Rust 重写现有 AutoHotkey v2 项目（13,184 行代码，37 个业务文件，DDD 四层架构）进行全面调研。核心结论：**采用 Tauri 2.x 混合架构（Rust/Tauri 主进程 + AHK 执行子进程）是当前最优策略**，预计可获得 3-5 倍启动速度提升、10 倍内存安全提升、以及类型安全保障。

**v3.0 关键变更**：
- UI 框架从裸 `wry` 切换为 **Tauri 2.11.2**（最新稳定版，MSRV 1.77.2）
- 利用 Tauri 内置 IPC（invoke/command）替代手写 JS-Rust 桥接
- 利用 Tauri 内置打包（NSIS/MSI）替代手写安装脚本
- 利用 Tauri 插件系统（自动更新、系统托盘、文件对话框等）
- AHK 子进程通信仍使用 Named Pipe（Tauri 不覆盖此场景）

**v2.0 关键修订**：
- Crate 版本全部更新至 2026-05 最新稳定版
- 代码统计数据已校准至实际值
- 新增 MSRV 约束分析、IPC 协议健壮性设计
- 修正 serde "零拷贝" 描述、IPC 延迟估算

---

## 二、项目现状扫描

### 2.1 代码规模

| 层级 | 文件数 | 行数 | 占比 | 代表文件 |
|------|:------:|:----:|:----:|---------|
| domain/ | 8 | 2,926 | 22.2% | skill_manager(581)、mode_registry(472) |
| infrastructure/ | 14 | 2,717 | 20.6% | config_validator(384)、json_parser(328) |
| application/ | 2 | 667 | 5.1% | config_service(401)、group_service(266) |
| presentation/ | 6 | 3,044 | 23.1% | webview2_manager(1173)、group_editor(1133) |
| 根目录 | 7 | 3,830 | 29.1% | gui.ahk(2036)、json.ahk(1403) |
| **合计** | **37** | **13,184** | 100% | — |

### 2.2 架构特征

```
┌──────────────────────────────────────┐
│            Presentation               │
│   webview2_manager / group_editor    │
│   debug_panel / backup_ui            │
├──────────────────────────────────────┤
│            Application                │
│   config_service / group_service     │
├──────────────────────────────────────┤
│              Domain                   │
│   skill_manager / mode_registry      │
│   key_recorder / joystick_input      │
│   joystick_executor / key_validator  │
│   interfaces (依赖倒置)              │
├──────────────────────────────────────┤
│          Infrastructure               │
│   config_store / error_system        │
│   json_parser / joy_sender           │
│   ipc_channel / json_logger          │
│   backup_core / config_validator     │
│   debug_logger / migration_logger    │
└──────────────────────────────────────┘
```

### 2.3 关键技术依赖

| 依赖 | 用途 | Rust/Tauri 替代方案 |
|------|------|-------------------|
| WebView2 (COM) | UI 渲染 | **Tauri 2.11.2**（内置 WebView2） |
| vJoy SDK (DLL) | 虚拟手柄 | `windows` 0.62.2 FFI 或保留 AHK 子进程 |
| AHK Send/Click | 按键模拟 | `windows` 0.62.2 SendInput API |
| AHK Hotkey | 热键注册 | `windows` 0.62.2 RegisterHotKey |
| AHK JSON | 配置解析 | `serde_json` 1.0.150（行业标准） |
| AHK DllCall | 原生 API | `windows` 0.62.2 FFI |
| AHK GUI | 界面框架 | **Tauri WebView2**（复用现有 HTML） |
| 文件管道 IPC | 进程间通信 | `interprocess` 2.4.2 Named Pipe |
| AHK-JS Bridge | UI↔逻辑通信 | **Tauri invoke/command**（内置 IPC） |

### 2.4 现有 IPC 实现

项目已有 `infrastructure/ipc_channel.ahk`（158 行），基于文件管道的简单通道：
- 入站/出站使用 JSON 文件（`ipc/inbound.json`、`ipc/outbound.json`）
- 支持 `OnMessage` 监听 + 轮询模式
- 消息格式：`{type, target, data, timestamp, traceId}`

> **迁移注意**: 现有 IPC 是文件级通信，Rust 版升级为 Named Pipe 后性能提升显著。Tauri 内置 IPC 仅覆盖 JS↔Rust 通信，AHK 子进程仍需 Named Pipe。

---

## 三、Rust 语言特性与项目需求匹配度

### 3.1 匹配度矩阵

| 需求维度 | AHK v2 当前 | Rust/Tauri 方案 | 匹配度 | 说明 |
|---------|------------|---------------|:------:|------|
| **类型安全** | 运行时检测 | 编译期验证 | ★★★★★ | 消除 80% 的运行时类型错误 |
| **内存安全** | 无保护 | 所有权模型 | ★★★★★ | 消除 use-after-free、数据竞争 |
| **并发安全** | 不支持 | Send/Sync trait | ★★★★★ | 多线程定时器无竞态 |
| **IDE 支持** | 有限 | rust-analyzer | ★★★★★ | 自动补全、跳转、重构 |
| **错误处理** | try-catch | Result/Option | ★★★★☆ | 强制处理所有错误路径 |
| **模块化** | #Include | mod 系统 | ★★★★★ | 编译时检查依赖图 |
| **Windows API** | DllCall | windows-rs | ★★★★☆ | 类型安全的 API 绑定 |
| **热键注册** | 原生支持 | RegisterHotKey | ★★★☆☆ | 需手动管理消息循环 |
| **按键发送** | Send 命令 | SendInput API | ★★★★☆ | 更精细控制，但代码量增加 |
| **JSON 序列化** | 自研解析器 | serde_json | ★★★★★ | 业界标准，编译期派生 |
| **WebView2** | COM 互操作 | **Tauri 2.11.2** | ★★★★★ | 内置 WebView2 + JS桥接 + 打包 |
| **打包分发** | .ahk + .exe | Tauri NSIS/MSI | ★★★★★ | 内置安装包生成 |
| **自动更新** | 无 | Tauri 插件 | ★★★★★ | `tauri-plugin-updater` |

### 3.2 核心竞争力对比

```
维度              AHK v2 现状        Rust/Tauri 目标     提升倍数
─────────────────────────────────────────────────────────────
启动速度          1-2s (WebView2)    <300ms              3-5x
类型错误检测      运行时             编译时              ∞ (消除)
内存安全          无保证             编译期保证          ∞ (消除)
打包体积          ~10MB+AHK运行时    ~5-8MB (Tauri+exe)  1.5x+
JS-Rust 桥接      手写 COM 互操作    Tauri invoke        自动化
安装包            无                 NSIS/MSI            标准化
自动更新          无                 tauri-plugin-updater 新增
并发定时器        单线程模拟          真正多线程          N/A→支持
单元测试          手工编写            cargo test          自动化
CI/CD            无                  GitHub Actions      标准化
```

### 3.3 MSRV 约束分析

| Crate | 版本 | MSRV | 说明 |
|-------|------|:----:|------|
| `tauri` | **2.11.2** | 1.77.2 | Tauri 自身要求 |
| `windows` | **0.62.2** | **1.82.0** | **最高 MSRV，决定项目基线** |
| `wry` | **0.55.1** | 1.77.0 | Tauri 依赖 |
| `tokio` | **1.47.1** (LTS) | 1.70.0 | LTS 版本至 2026-09 |
| `serde_json` | **1.0.150** | 1.71.0 | — |
| `thiserror` | **2.0.18** | 1.61.0 | — |
| `interprocess` | **2.4.2** | 1.75.0 | AHK 子进程 IPC |

**结论**: 项目 MSRV 应设为 **1.82.0**（由 `windows` crate 决定，高于 Tauri 的 1.77.2）。CI 流水线需使用 `rust-toolchain.toml` 固定版本。

---

## 四、Tauri 混合架构技术方案设计

### 4.1 整体架构

```
┌──────────────────────────────────────────────────────────┐
│  Tauri 2.11 App (asd.exe ~5-8MB)                         │
│                                                           │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │  WebView2 UI      │  │  Rust Backend                │ │
│  │  (HTML/JS/CSS)    │  │  ┌────────────────────────┐ │ │
│  │                   │  │  │ Tauri Commands          │ │ │
│  │  ┌─────────────┐  │  │  │ get_config / save_config│ │ │
│  │  │ @tauri-apps │  │  │  │ get_groups / toggle_grp │ │ │
│  │  │   /api      │◄─┼──┼─►│ start_recording / ...  │ │ │
│  │  │  invoke()   │  │  │  └────────────────────────┘ │ │
│  │  └─────────────┘  │  │                              │ │
│  │                   │  │  ┌────────────────────────┐ │ │
│  │  Tauri Events:    │  │  │ Domain Layer            │ │ │
│  │  ◄── status_update│  │  │ skill_manager           │ │ │
│  │  ◄── hotkey_event │  │  │ mode_registry           │ │ │
│  │  ◄── error_notify │  │  │ executor / validator    │ │ │
│  └──────────────────┘  │  └────────────────────────┘ │ │
│                         │                              │ │
│                         │  ┌────────────────────────┐ │ │
│                         │  │ Infrastructure Layer    │ │ │
│                         │  │ config / ipc / logging  │ │ │
│                         │  │ watchdog / backup       │ │ │
│                         │  └────────────┬───────────┘ │ │
│                         │               │              │ │
│                         │  Named Pipe IPC Manager      │ │
│                         │  interprocess 2.4.2          │ │
│                         └───────────────┼──────────────┘ │
└─────────────────────────────────────────┼────────────────┘
                                          │ Pipe: \\.\pipe\asd_ipc
                                          │ Protocol: JSON Lines + 序号确认
┌─────────────────────────────────────────┼────────────────┐
│  AHK 子进程 (asd_executor.ahk)          │                │
│  ┌───────────┐ ┌──────────┐ ┌────────┐ │                │
│  │Hotkey Hook│ │Send/Click│ │vJoy    │ │                │
│  │(Register) │ │(SendInput)│ │(DllCall)│ │                │
│  └───────────┘ └──────────┘ └────────┘ │                │
│  ┌───────────┐                          │                │
│  │IPC Client │◄─────────────────────────┘                │
│  │(Named Pipe)│                                          │
│  └───────────┘                                           │
└──────────────────────────────────────────────────────────┘
```

**双层 IPC 架构**：
1. **Tauri 内置 IPC**：JS ↔ Rust 通信（`invoke`/`emit`），零配置，类型安全
2. **Named Pipe IPC**：Rust ↔ AHK 子进程通信，自定义 JSON Lines 协议

### 4.2 Tauri 项目结构

```
asd/
├── src-tauri/                    # Rust 后端 (Tauri 约定目录)
│   ├── Cargo.toml
│   ├── rust-toolchain.toml       # MSRV 1.82.0 固定
│   ├── build.rs
│   ├── tauri.conf.json           # Tauri 应用配置
│   ├── capabilities/             # Tauri 权限配置
│   │   └── default.json
│   ├── icons/                    # 应用图标
│   └── src/
│       ├── main.rs               # 入口 (<50行)
│       ├── lib.rs                # Tauri Builder + 插件注册 (<150行)
│       ├── commands/             # Tauri Commands (替代 presentation 层)
│       │   ├── mod.rs
│       │   ├── config_cmd.rs     # 配置相关命令 (~200行)
│       │   ├── group_cmd.rs      # 分组相关命令 (~250行)
│       │   ├── hotkey_cmd.rs     # 热键相关命令 (~150行)
│       │   ├── recording_cmd.rs  # 录制相关命令 (~150行)
│       │   └── system_cmd.rs     # 系统状态命令 (~100行)
│       ├── domain/               # 领域层 (纯逻辑，无 Tauri 依赖)
│       │   ├── mod.rs
│       │   ├── skill.rs          # 技能定义 (~200行)
│       │   ├── group.rs          # 分组模型 (~150行)
│       │   ├── mode_registry.rs  # 执行模式注册 (~300行)
│       │   ├── executor.rs       # 执行调度器 (~400行)
│       │   ├── joystick_input.rs # 手柄输入定义 (~120行)
│       │   ├── key_validator.rs  # 按键校验 (~300行)
│       │   └── key_recorder.rs   # 按键录制 (~250行)
│       ├── infrastructure/       # 基础设施层
│       │   ├── mod.rs
│       │   ├── config.rs         # 配置加载/保存 (~250行)
│       │   ├── config_validator.rs # 配置校验 (~350行)
│       │   ├── ipc.rs            # Named Pipe IPC 管理 (~200行)
│       │   ├── ipc_protocol.rs   # AHK 通信协议定义 (~150行)
│       │   ├── ipc_watchdog.rs   # AHK 子进程守护 (~150行)
│       │   ├── error_system.rs   # 错误日志 (~200行)
│       │   └── backup.rs         # 配置备份 (~150行)
│       ├── application/          # 应用层 (业务编排)
│       │   ├── mod.rs
│       │   ├── config_service.rs # 配置业务 (~350行)
│       │   └── group_service.rs  # 分组业务 (~300行)
│       └── state.rs              # Tauri 状态管理 (~100行)
├── src/                          # 前端 (HTML/JS/CSS)
│   ├── index.html
│   ├── css/
│   │   └── style.css
│   ├── js/
│   │   ├── app.js               # 主入口
│   │   ├── api.js               # Tauri invoke 封装
│   │   ├── dashboard.js         # 仪表盘
│   │   └── group-editor.js      # 分组编辑器
│   └── pages/
│       ├── dashboard.html
│       └── group-editor.html
├── ahk_executor/                 # AHK 子进程
│   ├── executor.ahk              # AHK 执行子进程
│   ├── hotkey_hook.ahk           # 热键钩子
│   ├── sender.ahk                # 按键发送
│   ├── joystick.ahk              # vJoy 操作
│   └── ipc_client.ahk            # Named Pipe 客户端
├── tests/
│   ├── integration/
│   │   ├── config_tests.rs
│   │   ├── skill_tests.rs
│   │   └── ipc_tests.rs
│   └── e2e/
│       └── full_flow_tests.rs
└── package.json                  # 前端构建工具 (可选)
```

**与裸 wry 方案的关键差异**：
- `presentation/` 层被 `commands/` 替代（Tauri Command 是声明式的，代码量更少）
- 新增 `state.rs`（Tauri 状态管理，替代自定义全局状态）
- 新增 `tauri.conf.json` + `capabilities/`（Tauri 配置和权限）
- 前端代码独立于 `src/`（Tauri 约定）

### 4.3 Tauri Commands 设计（JS↔Rust IPC）

Tauri 内置的类型安全 IPC，替代原 `webview2_manager.ahk` 的手写 JS Bridge：

```rust
// src-tauri/src/commands/config_cmd.rs
#[tauri::command]
async fn get_config(state: State<'_, AppState>) -> Result<Config, String> {
    state.config_service.get_config().map_err(|e| e.to_string())
}

#[tauri::command]
async fn save_config(state: State<'_, AppState>, config: Config) -> Result<(), String> {
    state.config_service.save_config(config).map_err(|e| e.to_string())
}

#[tauri::command]
async fn validate_config(config: Config) -> Result<ValidationResult, String> {
    ConfigValidator::validate(&config).map_err(|e| e.to_string())
}
```

```rust
// src-tauri/src/commands/group_cmd.rs
#[tauri::command]
async fn get_groups(state: State<'_, AppState>) -> Result<Vec<GroupSummary>, String> {
    state.group_service.get_groups().map_err(|e| e.to_string())
}

#[tauri::command]
async fn toggle_group(state: State<'_, AppState>, group_id: String) -> Result<(), String> {
    state.group_service.toggle_group(&group_id).map_err(|e| e.to_string())
}
```

```rust
// src-tauri/src/commands/hotkey_cmd.rs
#[tauri::command]
async fn register_hotkey(state: State<'_, AppState>, hotkey: String, group_id: String) -> Result<(), String> {
    state.ipc_manager.send_command(IpcCommand::RegisterHotkey { hotkey, group_id })
        .await.map_err(|e| e.to_string())
}
```

**前端调用**：
```javascript
// src/js/api.js
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

export async function getConfig() {
    return invoke('get_config');
}

export async function toggleGroup(groupId) {
    return invoke('toggle_group', { groupId });
}

// 监听 Rust → JS 事件
listen('status_update', (event) => {
    updateDashboard(event.payload);
});

listen('hotkey_event', (event) => {
    onHotkeyTriggered(event.payload);
});
```

### 4.4 AHK 子进程 IPC 通信协议设计

基于 Named Pipe 的 JSON Lines 协议（使用 `interprocess` 2.4.2）：

```json
// Rust → AHK: 执行指令
{"id":"req-001","type":"execute","action":"send_keys","keys":["a","b"],"delay":50,"seq":1}

// AHK → Rust: 执行结果（含序号确认）
{"id":"req-001","type":"result","status":"ok","elapsed_ms":12,"ack_seq":1}

// AHK → Rust: 热键事件
{"id":"evt-001","type":"hotkey","key":"F1","timestamp":1716912000,"seq":2}

// Rust → AHK: 心跳
{"type":"ping","ts":1716912000}

// AHK → Rust: 心跳响应
{"type":"pong","ts":1716912000}

// AHK → Rust: 错误上报
{"type":"error","code":"SEND_FAILED","message":"SendInput returned 0","seq":3}
```

**协议增强**：
- `seq` 序号字段：消息排序与确认
- `ack_seq` 确认字段：请求-响应关联
- `error` 消息类型：AHK 侧错误上报通道
- 心跳 `ping/pong`：双向存活检测

**性能估算**：

| 阶段 | 延迟 | 说明 |
|------|:----:|------|
| Named Pipe 传输 | ~4μs | 理论值，265K msg/s |
| Rust 侧 JSON 序列化 | ~20-50μs | serde_json 编码 |
| AHK 侧 JSON 解析 | ~200-500μs | AHK 自研解析器较慢 |
| 进程上下文切换 | ~10-50μs | Windows 调度开销 |
| **端到端单程延迟** | **~250-600μs** | **实际估算** |
| **往返延迟 (req→resp)** | **~500-1200μs** | **含 AHK 处理时间** |

> 对于热键响应场景（人类感知阈值 50ms），延迟可接受；高频按键序列（50ms 间隔）需关注累积延迟。

### 4.5 关键 Crate 选型

| Crate | 版本 | 用途 | Stars | 维护状态 | MSRV |
|-------|------|------|:-----:|:--------:|:----:|
| **`tauri`** | **2.11.2** | 应用框架（WebView2+IPC+打包） | 92K+ | ⭐ Tauri 团队 | 1.77.2 |
| `serde` + `serde_json` | **1.0.228** / **1.0.150** | JSON 序列化 | 9K+ | ⭐ 业界标准 | 1.71 |
| `windows` | **0.62.2** | Windows API 绑定 | 5K+ | ⭐ Microsoft 官方 | **1.82** |
| `tokio` | **1.47.1** (LTS) | 异步运行时 | 27K+ | ⭐ 业界标准 | 1.70 |
| `tracing` | **0.1.44** | 结构化日志 | 5K+ | ⭐ Tokio 生态 | 1.65 |
| `interprocess` | **2.4.2** | AHK 子进程 IPC | 300+ | 可用 | 1.75 |
| `thiserror` | **2.0.18** | 错误派生宏 | 4K+ | ⭐ 业界标准 | 1.61 |
| `clap` | **4.6.1** | CLI 参数解析 | 14K+ | ⭐ 业界标准 | — |

**Tauri 内置能力（无需额外 Crate）**：

| 能力 | Tauri 内置 | 替代的裸 wry 方案 |
|------|-----------|-----------------|
| JS↔Rust IPC | `invoke`/`emit` | 手写 `evaluate_script` + `ipc_handler` |
| 窗口管理 | `Window` trait | 手写 winit/tao |
| 资源嵌入 | `include_dir!` | 手写 build.rs |
| 安装包 | NSIS/MSI | 手写 NSIS 脚本 |
| 自动更新 | `tauri-plugin-updater` | 需自建 |
| 系统托盘 | `tauri` 核心 `tray-icon` feature | 需自建 |
| 文件对话框 | `tauri-plugin-dialog` | 需自建 |
| 权限系统 | `capabilities/` | 无 |

### 4.6 Tauri vs 裸 wry 决策对比

> **v3.0 架构决策记录**

| 维度 | 裸 wry 方案 | Tauri 2.11.2 方案 ✅ |
|------|-----------|-------------------|
| JS↔Rust IPC | 手写 evaluate_script | **内置 invoke，类型安全** |
| 窗口管理 | 手写 tao | **内置多窗口、系统托盘** |
| 资源嵌入 | 手写 build.rs | **内置 include_dir** |
| 自动更新 | 需自建 | **tauri-plugin-updater** |
| 打包分发 | 手写 NSIS | **内置 NSIS/MSI** |
| JS 桥接 | 手写 JSON 序列化 | **类型安全 invoke API** |
| 学习成本 | 低（但胶水代码多） | 中（Tauri 约定） |
| 灵活性 | 高（完全控制） | 中（受框架约束） |
| 包体积 | ~4MB | ~5-8MB |
| AHK 子进程 | 需自行管理 | 需自行管理（同） |
| 社区生态 | wry 单独使用较少 | **Tauri 92K Stars，生态丰富** |
| 长期维护 | 需自行跟进 wry API 变更 | **Tauri 团队统一维护** |

**决策理由**：
1. **减少胶水代码**：Tauri 内置 IPC/窗口/打包，预计减少 ~800 行手写桥接代码
2. **类型安全**：`invoke` API 编译期检查参数类型，避免运行时 JSON 解析错误
3. **生态优势**：Tauri 92K Stars，插件生态成熟，长期维护有保障
4. **打包标准化**：内置 NSIS/MSI 安装包生成，无需手写安装脚本
5. **体积差异可接受**：5-8MB vs 4MB，多出 1-4MB 换来完整框架能力

---

## 五、性能优化分析

### 5.1 热点路径识别

> **注意**：以下提升倍数均为理论估算，需 Phase 1 后用 criterion 基准测试验证。

| 路径 | AHK 当前 | Rust/Tauri 预期 | 提升 | 置信度 | 验证方法 |
|------|---------|---------------|:----:|:------:|---------|
| 配置加载 (13KB JSON) | ~120ms (自研解析器) | ~5ms (serde) | **24x** | 高 | criterion 基准测试 |
| 按键校验 (100键) | ~50ms | ~1ms | **50x** | 中 | criterion 基准测试 |
| 分组调度 (10组) | ~20ms | ~2ms | **10x** | 中 | criterion 基准测试 |
| 日志写入 (1K条) | ~200ms | ~10ms | **20x** | 中 | criterion 基准测试 |
| 启动到可用 | 1.5-2.5s | 200-400ms | **5-8x** | 低 | 计时器测量（受 WebView2 初始化影响大） |
| WebView2 加载 | ~1s (受制于Edge) | ~1s (同) | 持平 | 高 | 不可优化 |
| JS↔Rust IPC | ~5-10ms (COM Bridge) | ~0.1ms (Tauri invoke) | **50-100x** | 高 | 延迟基准测试 |
| AHK 子进程 IPC | N/A (文件管道) | ~0.3-0.6ms | 新增 | 中 | 延迟基准测试 |

> **v3.0 新增**: Tauri invoke IPC 比原 AHK COM Bridge 快 50-100x，因为 Tauri 使用优化的二进制协议而非 COM 互操作。

### 5.2 内存占用对比

| 指标 | AHK 进程 | Tauri 进程 | 差异 |
|------|:--------:|:----------:|:----:|
| 空闲内存 | ~80-120MB | ~30-50MB | -60% |
| 含 WebView2 | ~150-200MB | ~60-90MB | -55% |
| 配置文件加载后 | +5MB | +1MB | serde 结构体反序列化 |

> `serde_json` 默认反序列化为拥有所有权的 Rust 结构体，并非零拷贝。但配置文件仅 13KB，分配开销可忽略。

---

## 六、技术挑战与解决方案

### 6.1 挑战 #1: 热键注册 🔴高风险

**问题**：AHK 的热键系统极其成熟，支持通配符、组合键、上下文敏感等。Rust 用 `RegisterHotKey` 需要手动管理消息循环。

**方案**：
- 热键注册**保留在 AHK 子进程**中（混合架构优势）
- AHK 通过 Named Pipe IPC 将热键事件上报 Rust
- Rust 通过 Tauri `emit` 将热键事件推送到前端 UI
- 热键修改通过 IPC 下发 `{"type":"reregister_hotkey",...}`

**数据流**：
```
用户按 F1 → AHK Hotkey Hook → Named Pipe → Rust IPC Manager
    → Tauri emit("hotkey_event") → JS 前端更新状态
    → Rust Executor 调度 → Named Pipe → AHK SendInput
```

### 6.2 挑战 #2: 按键模拟精度 🟡中风险

**问题**：`SendInput` API 在 Rust 中需要构造复杂的 INPUT 结构体，AHK 的 `Send` 命令已处理了各种边界情况。

**方案**：
- 核心按键模拟**保留在 AHK 子进程**中
- Rust 负责策略层（周期/序列/增强模式调度）
- AHK 负责执行层（构造 SendInput + 延时管理）

### 6.3 挑战 #3: Tauri 权限配置 🟡中风险

> **v3.0 新增/替代原 WebView2 COM 挑战**

**问题**：Tauri 2.x 采用严格的权限模型（`capabilities/`），需要显式声明每个 API 的访问权限。

**方案**：
- 在 `capabilities/default.json` 中声明所需权限：
```json
{
  "identifier": "default",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:window:default",
    "core:window:allow-show",
    "core:window:allow-hide",
    "shell:allow-open",
    "dialog:default",
    "fs:default",
    "global-shortcut:allow-register",
    "global-shortcut:allow-unregister"
  ]
}
```
- 自定义 Command 无需额外权限声明（Tauri 自动处理）
- AHK 子进程管理不涉及 Tauri 权限（纯 Rust 侧逻辑）

### 6.4 挑战 #4: vJoy SDK 集成 🟢低风险

**问题**：vJoy 提供 C DLL 接口，需要 `unsafe` FFI 调用。

**方案**：
- **推荐保留在 AHK 子进程**：vJoy DLL 加载已在 AHK 侧稳定运行
- Rust 通过 Named Pipe IPC 发送虚拟手柄指令

### 6.5 挑战 #5: 学习曲线 🟡中风险

**问题**：Rust 所有权/生命周期/异步编程 + Tauri 框架约定有学习成本。

**方案**：
- Rust 渐进策略：先用 `#[derive(Clone)]` 简化所有权管理
- Tauri 学习成本低：Command 就是普通 Rust 函数加 `#[tauri::command]`
- 前端调用 `invoke()` 类似 REST API，JS 开发者零门槛

### 6.6 挑战 #6: thiserror 2.0 迁移 🟡中风险

**问题**：`thiserror` 2.0 相比 1.x 有 Breaking Changes。

**方案**：
- 直接使用 `thiserror` 2.0.18，新项目无需迁移
- 示例：
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("配置加载失败: {0}")]
    ConfigLoad(String),
    #[error("IPC 通信错误")]
    Ipc(#[from] IpcError),
    #[error("内部错误: {0}")]
    Internal(String),
}
```

### 6.7 挑战 #7: AHK 子进程生命周期管理 🟡中风险

**问题**：AHK 子进程可能崩溃、挂起或意外退出。

**方案**：
- Rust 侧实现 `ProcessWatchdog`：
  - 心跳检测：每 2s 发送 `ping`，3 次无响应判定为挂起
  - 进程监控：`WaitForSingleObject` 检测子进程退出
  - 自动重启：崩溃后延迟 1s 重启，指数退避（1s→2s→4s→8s→30s 封顶）
  - 状态恢复：重启后重新下发当前热键注册和配置
- 优雅关机：Rust 主进程退出前发送 `{"type":"shutdown"}`，等待 3s 后强制终止
- Tauri 事件通知：子进程异常时通过 `emit("executor_status", ...)` 通知前端

---

## 七、迁移策略与工时估算

### 7.1 分阶段路线

```
Phase 0: PoC 验证 (1周)
├── Tauri 2.11.2 项目初始化 (npm create tauri-app)
├── serde_json 反序列化现有 config.json → 验证兼容性
├── interprocess Named Pipe 双向通信 → 验证 IPC 延迟
├── Tauri 最小 WebView2 窗口 + invoke 调用 → 验证渲染
└── Go/No-Go 决策点

Phase 1: 基础设施 (2周)
├── Tauri 项目骨架 + tauri.conf.json + capabilities
├── serde 配置管理 (替代 json_serializer/parser)
├── tracing 日志系统 (替代 error_system/debug_logger)
├── Named Pipe IPC 框架 (interprocess + JSON Lines)
├── ProcessWatchdog 子进程守护
└── Tauri 状态管理 (AppState)

Phase 2: 核心域模型 (3周)
├── skill/group/mode 数据模型 (serde Deserialize)
├── 配置校验引擎 (config_validator → Rust)
├── 执行调度器 (skill_manager → Rust)
├── 手柄输入模型 (joystick_input → Rust)
└── Tauri Commands 暴露 (config_cmd / group_cmd)

Phase 3: Tauri UI 集成 (2周)
├── 现有 HTML/CSS/JS 资产迁移到 src/ 目录
├── JS 调用从 AHK COM Bridge 改为 Tauri invoke
├── Tauri Events 替代 AHK 定时器推送
├── 仪表盘/分组编辑器数据绑定
└── 系统托盘 (tauri tray-icon feature + TrayIconBuilder)

Phase 4: AHK 子进程适配 (1周)
├── Named Pipe IPC 客户端 (替代文件管道方案)
├── 热键转发适配
├── Send/Click/vJoy 执行接口对齐
└── 错误上报通道

Phase 5: 集成测试与打磨 (2周)
├── 端到端集成测试
├── 性能基准测试 (criterion)
├── Tauri 打包 (NSIS/MSI)
├── 优雅关机流程验证
├── 自动更新配置 (tauri-plugin-updater)
└── 文档与迁移指南
```

**总工时估算**：11 周（单人全职）或 7 周（2 人协作）

### 7.2 风险缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|:----:|:----:|---------|
| Tauri 权限配置遗漏 | 中 | 中 | capabilities 逐步添加，Phase 1 建立完整清单 |
| IPC 性能瓶颈 | 低 | 中 | Phase 0 基准测试；可升级到共享内存 |
| AHK 子进程崩溃 | 中 | 高 | ProcessWatchdog + 指数退避重启 + 状态恢复 |
| 工时超预期 | 中 | 中 | 分阶段交付，每阶段有独立验收标准 |
| config.json 兼容性 | 低 | 高 | Phase 0 serde 反序列化验证 |
| thiserror 2.0 迁移 | 低 | 低 | 新项目直接使用 2.0 |
| Tauri 版本升级 | 低 | 中 | 锁定 Tauri 2.11.x，Cargo.toml 用 `"2.11"` 精确约束 |

---

## 八、与现有系统的集成方案

### 8.1 配置兼容性

```
现有 config.json ──→ serde Deserialize ──→ Rust 内部模型
                                           │
                          AHK 子进程 ←───── JSON (Named Pipe IPC)
                                           │
                          JS 前端 ←──────── Tauri invoke (自动序列化)
```

- Rust 直接读取现有 `config.json`（目标 100% 兼容）
- JS 前端通过 Tauri `invoke('get_config')` 获取配置（自动 JSON 序列化）
- AHK 子进程需要配置时通过 Named Pipe IPC 获取

**config.json 兼容性验证**：

现有 `config.json` 结构：
```json
{
  "CONTROL_HOTKEYS": { "emergency": "F10", "releaseAllHolds": "^r", ... },
  "GroupSettings": {
    "1": { "hotkey": "F1", "mode": "hybrid", "groups": [...], ... },
    "test_cycle": { "hotkey": "F2", "intervals": [...], ... }
  }
}
```

Rust serde 模型需注意：
- `GroupSettings` 的 key 是混合类型（数字字符串 + 普通字符串），需用 `HashMap<String, GroupConfig>`
- `groups` 数组内元素有 `type` 鉴别字段（`periodic`/`sequence`），需用 `#[serde(tag = "type")]` 内部标签
- `intervals`/`delays`/`pressKeys` 均为数组，可直接映射 `Vec<u64>`/`Vec<String>`
- **Phase 0 必须验证**: 用 serde_json 反序列化实际 config.json，确认无数据丢失

### 8.2 双轨运行期

在 Phase 3 完成后、Phase 5 完成前，可支持双轨运行：

```
asd.exe (Tauri) ──→ Named Pipe ──→ executor.ahk    (新模式)
asd.ahk                                            (旧模式, 回退)
```

### 8.3 快捷键打开 UI

**Tauri 实现**（比裸 wry 更简洁）：
```rust
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

app.plugin(tauri_plugin_global_shortcut::Builder::new().build())?;

let shortcut: Shortcut = "Ctrl+Shift+A".parse()?;
let app_handle = app.handle().clone();
app.global_shortcut().on_shortcut(shortcut, move |app, _shortcut, event| {
    if event.state == ShortcutState::Pressed {
        if let Some(window) = app.get_webview_window("main") {
            if window.is_visible().unwrap_or(false) {
                let _ = window.hide();
            } else {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
    }
});
```

> **v3.0 优势**: Tauri 提供了 `tauri-plugin-global-shortcut` 插件，比手写 `RegisterHotKey` + 消息循环简单得多。

---

## 九、维护策略

### 9.1 代码质量保障

| 工具 | 用途 |
|------|------|
| `cargo fmt` | 统一代码格式 |
| `cargo clippy` | Lint 检查 |
| `cargo test` | 单元测试 + 集成测试 |
| `cargo bench` (criterion) | 性能回归检测 |
| `cargo audit` | 依赖安全漏洞扫描 |
| `cargo deny` | 许可证合规检查 |
| `rust-analyzer` | IDE 实时检查 |
| `tauri dev` | 热重载开发服务器 |

### 9.2 CI/CD 流水线

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: 1.82.0
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: cargo fmt --check
      - run: cargo clippy -- -D warnings
      - run: cargo test
      - name: Build Tauri App
        run: |
          npm install
          npm run tauri build
      - uses: actions/upload-artifact@v4
        with:
          name: asd-windows
          path: |
            src-tauri/target/release/bundle/nsis/*.exe
            src-tauri/target/release/asd.exe
            ahk_executor/
```

### 9.3 构建与打包策略

**Tauri 内置打包**（替代手写 NSIS 脚本）：

```json
// src-tauri/tauri.conf.json (打包配置)
{
  "bundle": {
    "active": true,
    "targets": ["nsis", "msi"],
    "icon": ["icons/icon.ico"],
    "resources": ["ahk_executor/*"],
    "externalBin": [],
    "windows": {
      "webviewInstallMode": {
        "type": "downloadBootstrapper"
      }
    }
  }
}
```

| 组件 | 打包方式 | 说明 |
|------|---------|------|
| asd.exe | Tauri `cargo tauri build` | Rust 主进程 + WebView2 |
| ahk_executor/ | Tauri `resources` 字段 | 自动打包进安装目录 |
| AutoHotkey.exe | Tauri `resources` 或 Ahk2Exe | AHK 运行时或编译后的 .exe |
| web/ | Tauri 自动嵌入 | HTML/CSS/JS 编译进 asd.exe |
| config.json | 首次运行生成 | 默认配置模板 |

**分发方案**：
- **推荐**: Tauri NSIS 安装包（自动处理 WebView2 运行时安装）
- AHK 子进程用 Ahk2Exe 编译为 `asd_executor.exe`
- 最终产物：NSIS 安装包（含 asd.exe + asd_executor.exe + WebView2 Bootstrapper）

### 9.4 长期维护优势

| 维度 | AHK 当前 | Tauri 迁移后 |
|------|---------|------------|
| 重构安全性 | 手动测试 | 编译器保证 |
| 依赖管理 | 手动 #Include | `cargo update` + Tauri 版本 |
| 版本升级 | 无机制 | `semver` + `cargo` + Tauri CLI |
| 新成员上手 | 熟悉 AHK 语法 | Tauri 文档 + 编译器引导 |
| 安全审计 | 人工 | `cargo audit` + Tauri 权限模型 |
| 自动更新 | 无 | `tauri-plugin-updater` |
| 系统托盘 | 手动实现 | Tauri 核心 `tray-icon` feature |

---

## 十、调试策略

### 10.1 多进程调试方案

| 场景 | 工具 | 方法 |
|------|------|------|
| Rust 后端调试 | `rust-analyzer` + VS Code | 标准 Rust 调试流程 |
| 前端调试 | Chrome DevTools | `tauri dev` 自动开启 |
| AHK 子进程调试 | `OutputDebug` + DebugView | AHK 原生调试输出 |
| IPC 通信调试 | `tracing` + 自定义 Subscriber | 记录所有 IPC 消息 |
| Tauri invoke 调试 | `tracing` + 浏览器控制台 | 双侧日志对照 |
| 性能分析 | `tracing-flame` + `inferno` | 火焰图分析 |

### 10.2 Tauri 开发模式

```bash
# 启动热重载开发服务器
npm run tauri dev

# 前端改动自动热重载
# Rust 改动自动重新编译
# AHK 子进程需手动重启
```

### 10.3 集成测试策略

```
单元测试 (cargo test)
  ├── domain 层: 纯逻辑，无 Tauri 依赖
  ├── infrastructure 层: mock IPC/配置
  ├── application 层: mock domain
  └── commands 层: Tauri Command 单元测试

集成测试 (tests/integration/)
  ├── config_tests: 实际 config.json 反序列化
  ├── ipc_tests: 本地 Named Pipe 回环测试
  └── tauri_command_tests: Tauri invoke 集成测试

端到端测试 (tests/e2e/)
  └── full_flow_tests: Tauri App + AHK 子进程
      └── 需要 AHK 运行时环境
```

---

## 十一、总结与建议

### 11.1 核心优势

1. **类型与内存安全**：Rust 编译器在编译期消除数据竞争和内存错误
2. **性能跃升**：配置加载 24x、按键校验 50x、启动速度 5-8x（需 criterion 验证）
3. **Tauri 生态**：内置 IPC/窗口/打包/自动更新/系统托盘，减少 ~800 行胶水代码
4. **部署简化**：Tauri NSIS 安装包 + 双 exe 分发
5. **开发体验**：`tauri dev` 热重载 + Chrome DevTools 前端调试

### 11.2 核心风险

1. **Tauri 权限模型**：需正确配置 `capabilities/`，遗漏会导致运行时错误
2. **IPC 复杂度**：双层 IPC（Tauri invoke + Named Pipe）增加理解成本
3. **学习曲线**：Rust + Tauri 框架约定需要 2-3 周适应期
4. **AHK 特殊能力**：部分高级热键功能可能难以完全迁移
5. **MSRV 约束**：`windows` 0.62.2 要求 Rust 1.82+，限制工具链灵活性

### 11.3 最终建议

| 建议 | 说明 | 优先级 |
|------|------|:------:|
| ✅ **先做 Phase 0 PoC** | 验证 Tauri + serde + IPC，1 周内 Go/No-Go | 🔴 P0 |
| ✅ **使用 Tauri 2.11.2** | 内置 IPC/打包/插件，减少胶水代码 | 🔴 P0 |
| ✅ **保留混合架构** | Rust/Tauri 做策略层，AHK 做执行层 | 🟡 P1 |
| ✅ **使用 thiserror 2.0** | 新项目直接使用 2.0，避免迁移成本 | 🟡 P1 |
| ✅ **实现 ProcessWatchdog** | AHK 子进程崩溃自动恢复 | 🟡 P1 |
| ✅ **配置 Tauri 权限** | Phase 1 建立完整 capabilities 清单 | 🟡 P1 |
| ⚠️ **性能数据需验证** | 所有性能倍数为估算值，Phase 1 后用 criterion 验证 | 🟢 P2 |
| ⚠️ **评估 Tauri 插件** | 按需引入已验证版本插件（global-shortcut 2.3.1、updater 2.10.1、dialog 2.7.1、fs 2.5.1） | 🟢 P2 |

---

---

## 十二、深度审查：IPC 协议完善（4.3-4.4 补充）

> **v4.0 新增** — 针对 4.3-4.4 节 IPC 设计的深度审查与补充

### 12.1 Named Pipe API 选型

`interprocess` 2.4.2 提供两种 Windows IPC API：

| API | 特点 | 适用场景 |
|-----|------|---------|
| `local_socket` (跨平台) | `LocalSocketListener`/`LocalSocketStream`，Windows 底层用 Named Pipe | **推荐**：跨平台抽象，API 简洁 |
| `named_pipe` (Windows 专属) | `NamedPipeServer`/`NamedPipeClient`，暴露 Windows 特有选项 | 需要消息模式/安全描述符时 |

**决策**：使用 `local_socket` API（跨平台抽象），原因：
1. API 更简洁，与 `tokio` 异步集成开箱即用
2. Windows 底层自动使用 Named Pipe，无需手动管理
3. 未来若需 Linux 支持无需修改代码
4. 需启用 `interprocess` 的 `tokio` feature：`interprocess = { version = "2.4.2", features = ["tokio"] }`

```rust
use interprocess::local_socket::{LocalSocketListener, LocalSocketStream, NameType};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

const PIPE_NAME: &str = "asd_ipc";

struct IpcManager {
    writer: tokio::sync::Mutex<LocalSocketStream>,
    seq_counter: std::sync::atomic::AtomicU64,
}

impl IpcManager {
    async fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let name = PIPE_NAME.to_ns_name::<interprocess::local_socket::GenericNamespaced>()?;
        let stream = LocalSocketStream::connect(name).await?;
        Ok(Self {
            writer: tokio::sync::Mutex::new(stream),
            seq_counter: std::sync::atomic::AtomicU64::new(1),
        })
    }

    async fn send_command(&self, cmd: IpcCommand) -> Result<u64, IpcError> {
        let seq = self.seq_counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let msg = IpcMessage::command(seq, cmd);
        let json = serde_json::to_string(&msg).map_err(IpcError::Serialization)?;
        let mut writer = self.writer.lock().await;
        writer.write_all(json.as_bytes()).await.map_err(IpcError::Io)?;
        writer.write_all(b"\n").await.map_err(IpcError::Io)?;
        writer.flush().await.map_err(IpcError::Io)?;
        Ok(seq)
    }
}
```

### 12.2 JSON Lines 帧协议细化

**v3.0 遗漏**：未指定帧分隔符、最大消息尺寸、部分读取处理。

**v4.0 补充**：

| 协议参数 | 值 | 说明 |
|---------|-----|------|
| 帧分隔符 | `\n` (0x0A) | 每条消息一行，以换行符结尾 |
| 最大消息尺寸 | 64KB | 超过此尺寸的消息视为协议错误，丢弃并重连 |
| 编码 | UTF-8 | JSON Lines 标准约定 |
| 部分读取处理 | `BufReader` + `read_line()` | tokio AsyncBufReadExt 自动处理 |
| 消息校验 | `serde_json::from_str` | 反序列化失败则丢弃该行 |

```rust
async fn listen_ahk(
    listener: LocalSocketListener,
    app_handle: tauri::AppHandle,
) -> Result<(), Box<dyn std::error::Error>> {
    loop {
        let stream = listener.accept().await?;
        let (reader, _writer) = stream.split();
        let mut reader = BufReader::new(reader);
        let mut line = String::new();

        loop {
            line.clear();
            match reader.read_line(&mut line).await {
                Ok(0) => {
                    tracing::warn!("AHK 子进程断开连接");
                    break;
                }
                Ok(_) => {
                    let trimmed = line.trim_end();
                    if trimmed.is_empty() { continue; }
                    if trimmed.len() > 65536 {
                        tracing::error!("IPC 消息超过 64KB 限制，丢弃");
                        continue;
                    }
                    match serde_json::from_str::<IpcMessage>(trimmed) {
                        Ok(msg) => handle_ahk_message(&app_handle, msg).await,
                        Err(e) => tracing::warn!("IPC 消息解析失败: {}", e),
                    }
                }
                Err(e) => {
                    tracing::error!("IPC 读取错误: {}", e);
                    break;
                }
            }
        }
    }
}
```

### 12.3 背压与流控

**v3.0 遗漏**：无背压机制。若 AHK 发送消息快于 Rust 处理速度，可能导致内存膨胀。

**v4.0 补充**：

| 场景 | 风险 | 背压策略 |
|------|------|---------|
| AHK → Rust 高频热键事件 | 热键连按（如 50ms 间隔）产生大量消息 | **合并窗口**：100ms 内同组热键事件合并为一条 |
| Rust → AHK 执行指令 | 快速切换分组时指令堆积 | **指令去重**：同组 toggle 指令只保留最新一条 |
| Named Pipe 缓冲区满 | 理论上 Windows Named Pipe 缓冲区 64KB | `write_all` 阻塞等待，天然背压 |

```rust
use tokio::sync::mpsc;

const IPC_CHANNEL_CAPACITY: usize = 256;

struct IpcOutbound {
    tx: mpsc::Sender<IpcMessage>,
}

struct IpcInbound {
    rx: mpsc::Receiver<IpcMessage>,
}

fn create_ipc_channels() -> (IpcOutbound, IpcInbound) {
    let (tx, rx) = mpsc::channel(IPC_CHANNEL_CAPACITY);
    (IpcOutbound { tx }, IpcInbound { rx })
}
```

### 12.4 seq/ack_seq 序号机制细化

**v3.0 遗漏**：未指定 seq 溢出策略、重复检测、超时重传。

**v4.0 补充**：

| 参数 | 值 | 说明 |
|------|-----|------|
| seq 类型 | `u64` | 理论上限 1.8×10¹⁹，不会溢出 |
| ack_seq 语义 | 最近成功处理的消息 seq | 非累积确认，而是最新确认 |
| 重复检测 | AHK 侧忽略 seq ≤ 最近 ack_seq 的消息 | 简单有效 |
| 超时重传 | **不实现** | IPC 为局域通信，丢包概率极低；重传增加复杂度且热键场景无意义 |
| 乱序处理 | AHK 侧按 seq 排序执行 | 仅对 execute 类型消息排序，hotkey 事件不排序 |

### 12.5 错误恢复路径

**v3.0 遗漏**：未指定管道断裂后的恢复策略。

**v4.0 补充**：

```
管道断裂检测 → 关闭旧连接 → 通知 Watchdog → Watchdog 重启 AHK → 重新建立连接 → 恢复状态
```

| 错误类型 | 检测方式 | 恢复动作 |
|---------|---------|---------|
| 管道断裂 | `read_line` 返回 0 或 `BrokenPipe` 错误 | 关闭连接，触发 Watchdog 重启 |
| 消息格式错误 | `serde_json::from_str` 失败 | 记录日志，丢弃该消息，继续运行 |
| 消息超尺寸 | `trimmed.len() > 65536` | 丢弃该消息，记录错误日志 |
| AHK 无响应 | 心跳超时（3 次 × 2s = 6s） | Watchdog 判定挂起，强制终止并重启 |
| AHK 崩溃退出 | `WaitForSingleObject` 检测 | Watchdog 自动重启，指数退避 |

---

## 十三、深度审查：Tauri Commands 完整 API（4.3 补充）

> **v4.0 新增** — 完整的 Tauri Commands API 设计、状态管理、错误处理

### 13.1 统一错误类型

**v3.0 问题**：所有 Command 返回 `Result<T, String>`，丢失错误分类信息。

**v4.0 修正**：定义 `AppError` 枚举，实现 `Serialize` 以支持 Tauri 自动序列化：

```rust
use thiserror::Error;
use serde::Serialize;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("配置错误: {0}")]
    Config(String),
    #[error("IPC 通信错误: {0}")]
    Ipc(String),
    #[error("分组不存在: {0}")]
    GroupNotFound(String),
    #[error("验证失败: {0}")]
    Validation(String),
    #[error("执行器错误: {0}")]
    Executor(String),
    #[error("内部错误: {0}")]
    Internal(String),
}

impl Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where S: serde::Serializer {
        serializer.serialize_str(&self.to_string())
    }
}
```

> **注意**：Tauri 2.x 的 `#[tauri::command]` 要求返回类型实现 `Serialize`。`thiserror` 的 `Error` trait 不自动实现 `Serialize`，需手动实现或使用 `serde` 的 `impl Serialize`。此处选择手动序列化为字符串，前端通过前缀匹配分类。

### 13.2 AppState 完整设计

**v3.0 问题**：`state.rs` 仅标注 ~100 行，未指定内部结构。

**v4.0 补充**：

```rust
use std::sync::RwLock;
use tokio::sync::{Mutex, mpsc};

pub struct AppState {
    pub config: RwLock<Config>,
    pub groups: RwLock<HashMap<String, SkillGroup>>,
    pub ipc_manager: Mutex<Option<IpcManager>>,
    pub ipc_outbound: mpsc::Sender<IpcMessage>,
    pub active_hotkeys: RwLock<HashMap<String, String>>,
    pub emergency_mode: std::sync::atomic::AtomicBool,
    pub hold_mode_enabled: std::sync::atomic::AtomicBool,
    pub watchdog_state: RwLock<WatchdogState>,
}

pub struct WatchdogState {
    pub status: ExecutorStatus,
    pub restart_count: u32,
    pub last_restart: Option<std::time::Instant>,
    pub backoff_duration: std::time::Duration,
}

#[derive(Debug, Clone, serde::Serialize)]
pub enum ExecutorStatus {
    Starting,
    Running,
    Hung,
    Crashed,
    Stopped,
}
```

**同步原语选型依据**（参考 Tauri 官方 + Tokio 文档）：

| 字段 | 原语 | 理由 |
|------|------|------|
| `config` | `RwLock` | 读多写少（前端频繁读取配置，仅保存时写入） |
| `groups` | `RwLock` | 同上，前端频繁查询分组状态 |
| `ipc_manager` | `tokio::sync::Mutex` | 跨 `.await` 持有锁（IPC 读写），必须用 tokio Mutex |
| `ipc_outbound` | `mpsc::Sender` | tokio 异步通道，天然线程安全 |
| `active_hotkeys` | `RwLock` | 读多写少 |
| `emergency_mode` | `AtomicBool` | 简单布尔标志，原子操作即可 |
| `hold_mode_enabled` | `AtomicBool` | 同上 |
| `watchdog_state` | `RwLock` | 读多写少 |

> **关键原则**：根据 Tauri 官方文档和 Tokio 建议，优先使用 `std::sync::Mutex` 而非 `tokio::sync::Mutex`，除非需要跨 `.await` 持有锁（如 IPC 读写场景）。

### 13.3 完整 Commands API 清单

```rust
// commands/config_cmd.rs
#[tauri::command]
async fn get_config(state: State<'_, AppState>) -> Result<Config, AppError> {
    state.config.read().map_err(|e| AppError::Internal(e.to_string()))
        .map(|c| c.clone())
}

#[tauri::command]
async fn save_config(
    state: State<'_, AppState>,
    config: Config,
) -> Result<(), AppError> {
    ConfigValidator::validate(&config)?;
    let json = serde_json::to_string_pretty(&config)
        .map_err(|e| AppError::Config(e.to_string()))?;
    std::fs::write("config.json", json)
        .map_err(|e| AppError::Config(e.to_string()))?;
    *state.config.write().map_err(|e| AppError::Internal(e.to_string()))? = config;
    Ok(())
}

#[tauri::command]
async fn validate_config(config: Config) -> Result<ValidationResult, AppError> {
    ConfigValidator::validate(&config)
}

// commands/group_cmd.rs
#[tauri::command]
async fn get_groups(state: State<'_, AppState>) -> Result<Vec<GroupSummary>, AppError> {
    let groups = state.groups.read().map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(groups.values().map(|g| g.summary()).collect())
}

#[tauri::command]
async fn toggle_group(
    state: State<'_, AppState>,
    group_id: String,
) -> Result<GroupStatus, AppError> {
    let mut groups = state.groups.write().map_err(|e| AppError::Internal(e.to_string()))?;
    let group = groups.get_mut(&group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.clone()))?;
    group.toggle();
    let status = group.status();
    let msg = IpcMessage::command(0, &IpcCommand::ToggleGroup { group_id, active: group.active });
    state.ipc_outbound.send(msg).await
        .map_err(|e| AppError::Ipc(e.to_string()))?;
    Ok(status)
}

#[tauri::command]
async fn get_group_detail(
    state: State<'_, AppState>,
    group_id: String,
) -> Result<SkillGroup, AppError> {
    let groups = state.groups.read().map_err(|e| AppError::Internal(e.to_string()))?;
    groups.get(&group_id).cloned()
        .ok_or_else(|| AppError::GroupNotFound(group_id.clone()))
}

// commands/hotkey_cmd.rs
#[tauri::command]
async fn register_hotkey(
    state: State<'_, AppState>,
    hotkey: String,
    group_id: String,
) -> Result<(), AppError> {
    let msg = IpcCommand::RegisterHotkey { hotkey, group_id };
    state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
        .map_err(|e| AppError::Ipc(e.to_string()))
}

#[tauri::command]
async fn unregister_hotkey(
    state: State<'_, AppState>,
    hotkey: String,
) -> Result<(), AppError> {
    let msg = IpcCommand::UnregisterHotkey { hotkey };
    state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
        .map_err(|e| AppError::Ipc(e.to_string()))
}

// commands/recording_cmd.rs
#[tauri::command]
async fn start_recording(
    state: State<'_, AppState>,
    group_id: String,
    mode: String,
) -> Result<(), AppError> {
    let msg = IpcCommand::StartRecording { group_id, mode };
    state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
        .map_err(|e| AppError::Ipc(e.to_string()))
}

#[tauri::command]
async fn stop_recording(state: State<'_, AppState>) -> Result<RecordingResult, AppError> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    let msg = IpcCommand::StopRecording { reply_to: tx };
    state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
        .map_err(|e| AppError::Ipc(e.to_string()))?;
    rx.await.map_err(|e| AppError::Ipc(e.to_string()))
}

// commands/system_cmd.rs
#[tauri::command]
async fn get_executor_status(
    state: State<'_, AppState>,
) -> Result<ExecutorStatus, AppError> {
    let ws = state.watchdog_state.read().map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(ws.status.clone())
}

#[tauri::command]
async fn emergency_release(state: State<'_, AppState>) -> Result<(), AppError> {
    state.emergency_mode.store(true, std::sync::atomic::Ordering::SeqCst);
    let msg = IpcCommand::EmergencyRelease;
    state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
        .map_err(|e| AppError::Ipc(e.to_string()))
}

#[tauri::command]
async fn toggle_hold_mode(state: State<'_, AppState>) -> Result<bool, AppError> {
    let current = state.hold_mode_enabled.load(std::sync::atomic::Ordering::SeqCst);
    state.hold_mode_enabled.store(!current, std::sync::atomic::Ordering::SeqCst);
    Ok(!current)
}
```

### 13.4 Tauri Builder 注册

```rust
// src-tauri/src/lib.rs
use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let (ipc_tx, ipc_rx) = tokio::sync::mpsc::channel(256);
            let state = AppState {
                config: RwLock::new(Config::load_default()),
                groups: RwLock::new(HashMap::new()),
                ipc_manager: tokio::sync::Mutex::new(None),
                ipc_outbound: ipc_tx,
                active_hotkeys: RwLock::new(HashMap::new()),
                emergency_mode: std::sync::atomic::AtomicBool::new(false),
                hold_mode_enabled: std::sync::atomic::AtomicBool::new(true),
                watchdog_state: RwLock::new(WatchdogState::default()),
            };
            app.manage(state);

            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                start_ipc_listener(handle, ipc_rx).await;
            });

            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                start_watchdog(handle).await;
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::config_cmd::get_config,
            commands::config_cmd::save_config,
            commands::config_cmd::validate_config,
            commands::group_cmd::get_groups,
            commands::group_cmd::toggle_group,
            commands::group_cmd::get_group_detail,
            commands::hotkey_cmd::register_hotkey,
            commands::hotkey_cmd::unregister_hotkey,
            commands::recording_cmd::start_recording,
            commands::recording_cmd::stop_recording,
            commands::system_cmd::get_executor_status,
            commands::system_cmd::emergency_release,
            commands::system_cmd::toggle_hold_mode,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run app");
}
```

### 13.5 前端 API 封装

```javascript
// src/js/api.js
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

export const api = {
    config: {
        get: () => invoke('get_config'),
        save: (config) => invoke('save_config', { config }),
        validate: (config) => invoke('validate_config', { config }),
    },
    group: {
        list: () => invoke('get_groups'),
        toggle: (groupId) => invoke('toggle_group', { groupId }),
        detail: (groupId) => invoke('get_group_detail', { groupId }),
    },
    hotkey: {
        register: (hotkey, groupId) => invoke('register_hotkey', { hotkey, groupId }),
        unregister: (hotkey) => invoke('unregister_hotkey', { hotkey }),
    },
    recording: {
        start: (groupId, mode) => invoke('start_recording', { groupId, mode }),
        stop: () => invoke('stop_recording'),
    },
    system: {
        executorStatus: () => invoke('get_executor_status'),
        emergencyRelease: () => invoke('emergency_release'),
        toggleHoldMode: () => invoke('toggle_hold_mode'),
    },
};

export function onStatusUpdate(callback) {
    return listen('status_update', (event) => callback(event.payload));
}

export function onHotkeyEvent(callback) {
    return listen('hotkey_event', (event) => callback(event.payload));
}

export function onExecutorStatus(callback) {
    return listen('executor_status', (event) => callback(event.payload));
}
```

---

## 十四、深度审查：配置兼容性 10 模式 serde 映射（8.1 补充）

> **v4.0 新增** — 修正 v3.0 中 serde 映射的重大错误，完整覆盖 10 种执行模式

### 14.1 🔴 严重问题：v3.0 serde 映射错误

**v3.0 原文**：
> `groups` 数组内元素有 `type` 鉴别字段（`periodic`/`sequence`），需用 `#[serde(tag = "type")]` 内部标签

**问题**：
1. `type` 鉴别字段仅存在于 `hybrid`/`enhanced_hybrid` 模式的 `groups` 数组内部元素中
2. **顶层 GroupConfig 的鉴别字段是 `mode`，不是 `type`**
3. 不同 `mode` 对应完全不同的字段结构（扁平 vs 嵌套）
4. 实际存在 **10 种执行模式**，而非 2 种

**实际 config.json 结构对比**：

```json
// 模式 A：hybrid 模式（嵌套 groups 数组）
{
  "1": {
    "groups": [
      { "intervals": [50,50,50], "pressKeys": ["1","2","3"], "type": "periodic" },
      { "delays": [200,500,2000], "pressKeys": ["A","S","D"], "type": "sequence" }
    ],
    "hotkey": "F1",
    "keyPressDuration": 10,
    "mode": "hybrid",
    "name": "示例混合",
    "seqInterval": 100
  }
}

// 模式 B：periodic 模式（扁平结构）
{
  "test_cycle": {
    "hotkey": "F2",
    "intervals": [100],
    "keyPressDuration": 20,
    "keys": ["a"],
    "mode": "periodic",
    "name": "测试周期按键"
  }
}
```

### 14.2 完整 10 模式字段矩阵

基于 [mode_registry.ahk](file:///d:/1demo/AutoHotkeydemo/domain/mode_registry.ahk) 和 [skill_group.ahk](file:///d:/1demo/AutoHotkeydemo/domain/skill_group.ahk) 的分析：

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

**groups 数组内部元素的 type 鉴别**：

| type | 必需字段 | 可选字段 |
|------|---------|---------|
| `periodic` | `pressKeys`, `intervals` | — |
| `sequence` | `pressKeys`, `delays` | — |

### 14.3 修正后的 serde 模型

```rust
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(rename = "CONTROL_HOTKEYS")]
    pub control_hotkeys: ControlHotkeys,
    #[serde(rename = "GroupSettings")]
    pub group_settings: HashMap<String, GroupConfig>,
    #[serde(rename = "HoldSettings")]
    pub hold_settings: HoldSettings,
    #[serde(rename = "lastModified")]
    pub last_modified: Option<String>,
    pub version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ControlHotkeys {
    pub emergency: String,
    #[serde(rename = "releaseAllHolds")]
    pub release_all_holds: String,
    #[serde(rename = "showStatus")]
    pub show_status: String,
    #[serde(rename = "toggleAll")]
    pub toggle_all: String,
    #[serde(rename = "toggleHoldMode")]
    pub toggle_hold_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "mode")]
pub enum GroupConfig {
    #[serde(rename = "periodic")]
    Periodic(PeriodicConfig),
    #[serde(rename = "sequence")]
    Sequence(SequenceConfig),
    #[serde(rename = "hybrid")]
    Hybrid(HybridConfig),
    #[serde(rename = "hold")]
    Hold(HoldConfig),
    #[serde(rename = "enhanced_periodic")]
    EnhancedPeriodic(EnhancedPeriodicConfig),
    #[serde(rename = "enhanced_sequence")]
    EnhancedSequence(EnhancedSequenceConfig),
    #[serde(rename = "enhanced_hybrid")]
    EnhancedHybrid(EnhancedHybridConfig),
    #[serde(rename = "joystick_periodic")]
    JoystickPeriodic(JoystickPeriodicConfig),
    #[serde(rename = "joystick_sequence")]
    JoystickSequence(JoystickSequenceConfig),
    #[serde(rename = "joystick_hold")]
    JoystickHold(JoystickHoldConfig),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommonGroupFields {
    pub hotkey: String,
    #[serde(rename = "keyPressDuration")]
    pub key_press_duration: u64,
    pub name: String,
}

// 扁平模式：periodic
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeriodicConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    pub keys: Vec<String>,
    pub intervals: Vec<u64>,
}

// 扁平模式：sequence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    pub keys: Vec<String>,
    pub delays: Vec<u64>,
}

// 嵌套模式：hybrid
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HybridConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    pub groups: Vec<GroupItem>,
    #[serde(rename = "seqInterval", default)]
    pub seq_interval: u64,
}

// groups 数组内部元素（type 鉴别）
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum GroupItem {
    #[serde(rename = "periodic")]
    Periodic(PeriodicGroupItem),
    #[serde(rename = "sequence")]
    Sequence(SequenceGroupItem),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeriodicGroupItem {
    #[serde(rename = "pressKeys")]
    pub press_keys: Vec<String>,
    pub intervals: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceGroupItem {
    #[serde(rename = "pressKeys")]
    pub press_keys: Vec<String>,
    pub delays: Vec<u64>,
}

// 增强周期模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedPeriodicConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    #[serde(rename = "pressKeys")]
    pub press_keys: Vec<String>,
    pub intervals: Vec<u64>,
    #[serde(rename = "pressDelays", default)]
    pub press_delays: Vec<u64>,
    #[serde(rename = "holdPattern", default)]
    pub hold_pattern: Vec<serde_json::Value>,
    #[serde(rename = "holdTriggers", default)]
    pub hold_triggers: Vec<serde_json::Value>,
}

// 增强序列模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedSequenceConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    #[serde(rename = "pressKeys")]
    pub press_keys: Vec<String>,
    #[serde(rename = "pressDelays")]
    pub press_delays: Vec<u64>,
    #[serde(default, rename = "delays")]
    pub delays: Vec<u64>,
    #[serde(rename = "holdTriggers", default)]
    pub hold_triggers: Vec<serde_json::Value>,
    #[serde(rename = "holdPattern", default)]
    pub hold_pattern: Vec<serde_json::Value>,
}

// 增强混合模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedHybridConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    pub groups: Vec<GroupItem>,
    #[serde(rename = "holdTriggers", default)]
    pub hold_triggers: Vec<serde_json::Value>,
    #[serde(rename = "holdPattern", default)]
    pub hold_pattern: Vec<serde_json::Value>,
}

// 长按模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoldConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    #[serde(rename = "holdKeys")]
    pub hold_keys: Vec<String>,
    #[serde(rename = "holdDuration", default)]
    pub hold_duration: u64,
    #[serde(rename = "autoRepeat", default)]
    pub auto_repeat: bool,
    #[serde(rename = "repeatInterval", default = "default_repeat_interval")]
    pub repeat_interval: u64,
}

fn default_repeat_interval() -> u64 { 1000 }

// 手柄模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoystickPeriodicConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    #[serde(rename = "joyKeys")]
    pub joy_keys: Vec<String>,
    #[serde(rename = "joyIntervals")]
    pub joy_intervals: Vec<u64>,
    #[serde(rename = "joySendMethod", default = "default_send_method")]
    pub joy_send_method: String,
    #[serde(rename = "joyKeyDuration", default = "default_key_duration")]
    pub joy_key_duration: u64,
}

fn default_send_method() -> String { "auto".to_string() }
fn default_key_duration() -> u64 { 50 }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoystickSequenceConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    #[serde(rename = "joyKeys")]
    pub joy_keys: Vec<String>,
    #[serde(rename = "joyDelays")]
    pub joy_delays: Vec<u64>,
    #[serde(rename = "joySendMethod", default = "default_send_method")]
    pub joy_send_method: String,
    #[serde(rename = "joyKeyDuration", default = "default_key_duration")]
    pub joy_key_duration: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoystickHoldConfig {
    #[serde(flatten)]
    pub common: CommonGroupFields,
    #[serde(rename = "joyKeys")]
    pub joy_keys: Vec<String>,
    #[serde(rename = "joySendMethod", default = "default_send_method")]
    pub joy_send_method: String,
    #[serde(rename = "joyKeyDuration", default = "default_key_duration")]
    pub joy_key_duration: u64,
    #[serde(rename = "holdDuration", default)]
    pub hold_duration: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoldSettings {
    #[serde(rename = "allowOverlap")]
    pub allow_overlap: bool,
    #[serde(rename = "checkInterval")]
    pub check_interval: u64,
    #[serde(rename = "debounceDelay")]
    pub debounce_delay: u64,
    #[serde(rename = "pressSpeed")]
    pub press_speed: u64,
    #[serde(rename = "releaseOnEmergency")]
    pub release_on_emergency: bool,
}
```

### 14.4 serde 映射关键陷阱

| 陷阱 | 说明 | 解决方案 |
|------|------|---------|
| `#[serde(tag = "mode")]` 与 `#[serde(flatten)]` 冲突 | 内部标签枚举 + flatten 在 serde 中有已知限制 | **Phase 0 必须验证**：用实际 config.json 测试反序列化 |
| `keys` vs `pressKeys` 命名不一致 | `periodic`/`sequence` 用 `keys`，`enhanced_*` 用 `pressKeys` | 不同 Variant 使用不同字段名，serde 自动处理 |
| `delays` fallback 到 `intervals` | AHK 代码 `delays := _GetProp(config, "delays", _GetProp(config, "intervals", []))` | Rust 侧用 `#[serde(default)]` + 自定义反序列化器 |
| `GroupSettings` key 混合类型 | `"1"` (数字字符串) + `"test_cycle"` (普通字符串) | `HashMap<String, GroupConfig>` 统一处理 |
| 未知 mode 值 | 未来可能新增模式 | `GroupConfig` 添加 `#[serde(untagged)]` fallback Variant 或用 `serde_json::Value` |
| `holdPattern`/`holdTriggers` 结构未明 | AHK 代码中仅传递，未解析内部结构 | 先用 `Vec<serde_json::Value>` 占位，后续细化 |

### 14.5 Phase 0 验证清单

```rust
#[cfg(test)]
mod config_compat_tests {
    use super::*;

    #[test]
    fn test_deserialize_actual_config() {
        let json = include_str!("../../config.json");
        let config: Config = serde_json::from_str(json)
            .expect("config.json 反序列化失败");
        assert!(config.group_settings.contains_key("1"));
        assert!(config.group_settings.contains_key("test_cycle"));
    }

    #[test]
    fn test_hybrid_mode_groups() {
        let config: Config = serde_json::from_str(include_str!("../../config.json")).unwrap();
        let group = &config.group_settings["1"];
        match group {
            GroupConfig::Hybrid(h) => {
                assert_eq!(h.groups.len(), 2);
                assert!(matches!(&h.groups[0], GroupItem::Periodic(_)));
                assert!(matches!(&h.groups[1], GroupItem::Sequence(_)));
            }
            _ => panic!("Expected Hybrid mode"),
        }
    }

    #[test]
    fn test_periodic_mode_flat() {
        let config: Config = serde_json::from_str(include_str!("../../config.json")).unwrap();
        let group = &config.group_settings["test_cycle"];
        match group {
            GroupConfig::Periodic(p) => {
                assert_eq!(p.keys, vec!["a"]);
                assert_eq!(p.intervals, vec![100]);
            }
            _ => panic!("Expected Periodic mode"),
        }
    }

    #[test]
    fn test_roundtrip_serialization() {
        let json = include_str!("../../config.json");
        let config: Config = serde_json::from_str(json).unwrap();
        let re_json = serde_json::to_string_pretty(&config).unwrap();
        let re_config: Config = serde_json::from_str(&re_json).unwrap();
        assert_eq!(config.group_settings.len(), re_config.group_settings.len());
    }
}
```

---

## 十五、深度审查：子进程管理细化（6.7 补充）

> **v4.0 新增** — 完整的 ProcessWatchdog 设计、Windows 优雅关机、崩溃恢复

### 15.1 进程启动机制

**v3.0 遗漏**：未指定使用 `std::process::Command` 还是 `tokio::process::Command`。

**v4.0 决策**：使用 `tokio::process::Command`，原因：
1. 与 Tauri 的 tokio 运行时一致
2. 异步等待子进程退出，不阻塞主线程
3. 可与 `interprocess` 的 tokio 异步 IPC 配合

```rust
use tokio::process::{Command, Child};
use std::process::Stdio;

async fn spawn_ahk_executor() -> Result<Child, std::io::Error> {
    Command::new("./ahk_executor/asd_executor.exe")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
}
```

### 15.2 Windows 优雅关机流程

**v3.0 遗漏**：仅提到发送 `{"type":"shutdown"}` 后等待 3s 强制终止，未考虑 Windows 特有的信号机制。

**v4.0 补充**：

Windows 没有类似 Unix 的 SIGTERM 信号。优雅关机流程如下：

```
阶段 1: 发送 shutdown IPC 消息（给 AHK 2s 清理时间）
    ↓ 超时 2s
阶段 2: 发送 WM_CLOSE 消息（PostMessage 到子进程主窗口）
    ↓ 超时 3s
阶段 3: TerminateProcess（强制终止）
```

> **v8.0 修正**：Phase 2 原使用 `GenerateConsoleCtrlEvent`，但对 GUI 进程无效（Windows 文档明确指出）。改用 `WM_CLOSE`，详见 17.4 节。

```rust
async fn graceful_shutdown(child: &mut Child) -> Result<(), WatchdogError> {
    // Phase 1: IPC shutdown 消息
    let shutdown_msg = r#"{"type":"shutdown"}"#;
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(shutdown_msg.as_bytes()).await;
        let _ = stdin.write_all(b"\n").await;
        let _ = stdin.flush().await;
    }

    match tokio::time::timeout(
        std::time::Duration::from_secs(2),
        child.wait()
    ).await {
        Ok(Ok(_)) => return Ok(()),
        _ => {}
    }

    // Phase 2: WM_CLOSE（替代 GenerateConsoleCtrlEvent，后者对 GUI 进程无效）
    if let Some(pid) = child.id() {
        let _ = send_wm_close(pid).await;
    }

    match tokio::time::timeout(
        std::time::Duration::from_secs(3),
        child.wait()
    ).await {
        Ok(Ok(_)) => return Ok(()),
        _ => {}
    }

    // Phase 3: 强制终止
    let _ = child.kill().await;
    Ok(())
}
```

### 15.3 完整 Watchdog 状态机

**v3.0 遗漏**：Watchdog 仅有文字描述，无状态机定义。

**v4.0 补充**：

```
                    ┌──────────┐
                    │  Idle    │
                    └────┬─────┘
                         │ start()
                    ┌────▼─────┐
              ┌────►│ Starting │
              │     └────┬─────┘
              │          │ IPC connected
              │     ┌────▼─────┐
              │     │ Running  │◄──────────────┐
              │     └────┬─────┘               │
              │          │ heartbeat timeout   │ state recovered
              │     ┌────▼─────┐               │
              │     │  Hung    │               │
              │     └────┬─────┘               │
              │          │ kill + restart      │
              │     ┌────▼─────┐          ┌────┴─────┐
              │     │ Restarting├─────────►│Recovering│
              │     └────┬─────┘          └──────────┘
              │          │ max retries
              │     ┌────▼─────┐
              └─────┤ Failed   │
                    └──────────┘
```

```rust
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub enum WatchdogStateEnum {
    Idle,
    Starting,
    Running,
    Hung,
    Restarting,
    Recovering,
    Failed,
}

pub struct ProcessWatchdog {
    state: WatchdogStateEnum,
    child: Option<Child>,
    restart_count: u32,
    max_restarts: u32,
    backoff: ExponentialBackoff,
    last_heartbeat: std::time::Instant,
    heartbeat_timeout: std::time::Duration,
    missed_heartbeats: u32,
    max_missed_heartbeats: u32,
}

impl ProcessWatchdog {
    pub fn new() -> Self {
        Self {
            state: WatchdogStateEnum::Idle,
            child: None,
            restart_count: 0,
            max_restarts: 10,
            backoff: ExponentialBackoff::new(
                std::time::Duration::from_secs(1),
                std::time::Duration::from_secs(30),
            ),
            last_heartbeat: std::time::Instant::now(),
            heartbeat_timeout: std::time::Duration::from_secs(2),
            missed_heartbeats: 0,
            max_missed_heartbeats: 3,
        }
    }

    pub async fn tick(&mut self, app_handle: &tauri::AppHandle) {
        match self.state {
            WatchdogStateEnum::Running => {
                if self.last_heartbeat.elapsed() > self.heartbeat_timeout {
                    self.missed_heartbeats += 1;
                    if self.missed_heartbeats >= self.max_missed_heartbeats {
                        tracing::warn!("AHK 子进程心跳超时 {} 次，判定挂起", self.missed_heartbeats);
                        self.transition(WatchdogStateEnum::Hung, app_handle);
                    }
                }
            }
            WatchdogStateEnum::Hung => {
                if let Some(child) = self.child.as_mut() {
                    let _ = child.kill().await;
                }
                self.restart_count += 1;
                if self.restart_count > self.max_restarts {
                    tracing::error!("AHK 子进程重启次数超过上限 ({})，放弃", self.max_restarts);
                    self.transition(WatchdogStateEnum::Failed, app_handle);
                    return;
                }
                let delay = self.backoff.next();
                tracing::info!("等待 {:?} 后重启 AHK 子进程 (第 {} 次)", delay, self.restart_count);
                tokio::time::sleep(delay).await;
                self.transition(WatchdogStateEnum::Restarting, app_handle);
            }
            WatchdogStateEnum::Restarting => {
                match spawn_ahk_executor().await {
                    Ok(child) => {
                        self.child = Some(child);
                        self.missed_heartbeats = 0;
                        self.last_heartbeat = std::time::Instant::now();
                        self.transition(WatchdogStateEnum::Recovering, app_handle);
                    }
                    Err(e) => {
                        tracing::error!("AHK 子进程启动失败: {}", e);
                        self.transition(WatchdogStateEnum::Hung, app_handle);
                    }
                }
            }
            WatchdogStateEnum::Recovering => {
                // 恢复状态：重新下发热键注册和配置
                if let Err(e) = self.recover_state(app_handle).await {
                    tracing::error!("状态恢复失败: {}", e);
                    self.transition(WatchdogStateEnum::Hung, app_handle);
                } else {
                    tracing::info!("AHK 子进程状态恢复成功");
                    self.transition(WatchdogStateEnum::Running, app_handle);
                }
            }
            _ => {}
        }
    }

    fn transition(&mut self, new_state: WatchdogStateEnum, app_handle: &tauri::AppHandle) {
        tracing::info!("Watchdog: {:?} → {:?}", self.state, new_state);
        self.state = new_state.clone();
        let _ = app_handle.emit("executor_status", &new_state);
    }

    pub fn on_heartbeat(&mut self) {
        self.last_heartbeat = std::time::Instant::now();
        self.missed_heartbeats = 0;
    }

    async fn recover_state(&self, app_handle: &tauri::AppHandle) -> Result<(), WatchdogError> {
        let state = app_handle.state::<AppState>();
        let config = state.config.read().map_err(|e| WatchdogError::State(e.to_string()))?;
        let hotkeys = state.active_hotkeys.read().map_err(|e| WatchdogError::State(e.to_string()))?;

        // 重新下发所有热键注册
        for (hotkey, group_id) in hotkeys.iter() {
            let msg = IpcCommand::RegisterHotkey {
                hotkey: hotkey.clone(),
                group_id: group_id.clone(),
            };
            state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
                .map_err(|e| WatchdogError::Ipc(e.to_string()))?;
        }

        // 重新下发当前活跃分组
        let groups = state.groups.read().map_err(|e| WatchdogError::State(e.to_string()))?;
        for (id, group) in groups.iter() {
            if group.active {
                let msg = IpcCommand::ToggleGroup {
                    group_id: id.clone(),
                    active: true,
                };
                state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
                    .map_err(|e| WatchdogError::Ipc(e.to_string()))?;
            }
        }

        Ok(())
    }
}

struct ExponentialBackoff {
    current: std::time::Duration,
    max: std::time::Duration,
}

impl ExponentialBackoff {
    fn new(initial: std::time::Duration, max: std::time::Duration) -> Self {
        Self { current: initial, max }
    }
    fn next(&mut self) -> std::time::Duration {
        let delay = self.current;
        self.current = (self.current * 2).min(self.max);
        delay
    }
}
```

### 15.4 孤儿进程防护

**v3.0 遗漏**：若 Rust 主进程崩溃，AHK 子进程成为孤儿。

**v4.0 补充**：

| 方案 | 实现 | 可靠性 |
|------|------|:------:|
| **Job Object** (推荐) | Windows Job Object + `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` | ★★★★★ |
| AHK 侧心跳检测 | AHK 定时检查 Rust 进程是否存在 | ★★★☆☆ |
| PID 文件 | AHK 读取 PID 文件检查父进程 | ★★☆☆☆ |

```rust
use windows::Win32::System::JobObjects::{
    CreateJobObjectW, SetInformationJobObject, AssignProcessToJobObject,
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows::core::PCWSTR;

fn create_job_object() -> Result<isize, windows::core::Error> {
    unsafe {
        let job = CreateJobObjectW(None, None)?;

        let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

        SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &info as *const _ as *const _,
            std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        )?;

        Ok(job.0)
    }
}

fn assign_to_job(job: isize, child: &Child) -> Result<(), windows::core::Error> {
    use windows::Win32::System::Threading::{OpenProcess, PROCESS_SET_QUOTA, PROCESS_TERMINATE};
    unsafe {
        let proc_handle = OpenProcess(
            PROCESS_SET_QUOTA | PROCESS_TERMINATE,
            false,
            child.id(),
        )?;
        AssignProcessToJobObject(
            windows::Win32::Foundation::HANDLE(job),
            proc_handle,
        )
    }
}
```

> **效果**：当 Rust 主进程退出（无论正常还是崩溃），Windows 自动终止 Job Object 中的所有子进程。这是 Windows 上最可靠的孤儿进程防护机制。

### 15.5 心跳参数调优

**v3.0 问题**：3 次心跳超时 × 2s = 6s 判定挂起，对热键应用太长。

**v4.0 调优**：

| 参数 | v3.0 | v4.0 | 理由 |
|------|:----:|:----:|------|
| 心跳间隔 | 2s | **1s** | 更快检测异常 |
| 最大丢失次数 | 3 | **3** | 保持不变 |
| 判定挂起总时间 | 6s | **3s** | 热键应用需要快速恢复 |
| 重启后首次心跳超时 | 6s | **5s** | AHK 启动需要初始化时间 |

---

## 十六、第二轮深度审查：跨章节问题与修正

> **v4.0 新增** — 三省吾身后的系统性审查，覆盖 serde 兼容性、Tauri 插件版本、架构风险

### 16.1 🔴 严重：serde `tag` + `flatten` 兼容性问题

**问题**：v4.0 第十四章的 serde 模型使用 `#[serde(tag = "mode")]` + `#[serde(flatten)]` 组合。根据 serde 官方文档和社区实践，此组合有以下限制：

1. **内部标签枚举的 Variant 必须是结构体变体**（named fields），不能是元组变体 → v4.0 模型已满足
2. **`flatten` 在内部标签枚举中使用时，serde 使用 Content 反序列化器**，性能比直接反序列化慢约 2-3 倍
3. **`deny_unknown_fields` 不能与 `flatten` 一起使用** → 无法严格校验未知字段
4. **`flatten` + 内部标签枚举在嵌套场景下可能产生反序列化歧义** → 当 `CommonGroupFields` 和模式特有字段有重名时

**修正方案**：采用 **adjacently tagged**（相邻标签）替代 internally tagged：

```rust
// 方案 A（推荐）：adjacently tagged — 将 mode 和内容分离
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "mode", content = "config")]
pub enum GroupConfig {
    #[serde(rename = "periodic")]
    Periodic(PeriodicConfig),
    // ...
}
// JSON 输出: {"mode": "periodic", "config": {"hotkey": "F1", ...}}
// ❌ 不兼容现有 config.json（现有格式是扁平的，mode 和其他字段同级）
```

**方案 A 不兼容**：现有 `config.json` 中 `mode` 和其他字段在同级，不是嵌套结构。

```rust
// 方案 B（推荐）：自定义 Deserialize — 完全控制反序列化逻辑
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupConfig {
    pub hotkey: String,
    #[serde(rename = "keyPressDuration")]
    pub key_press_duration: u64,
    pub name: String,
    pub mode: String,
    #[serde(flatten)]
    pub mode_data: ModeData,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ModeData {
    Periodic(PeriodicData),
    Sequence(SequenceData),
    Hybrid(HybridData),
    Hold(HoldData),
    EnhancedPeriodic(EnhancedPeriodicData),
    EnhancedSequence(EnhancedSequenceData),
    EnhancedHybrid(EnhancedHybridData),
    JoystickPeriodic(JoystickPeriodicData),
    JoystickSequence(JoystickSequenceData),
    JoystickHold(JoystickHoldData),
}

// 每个模式数据只包含模式特有字段（不含 hotkey/name/keyPressDuration/mode）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeriodicData {
    pub keys: Vec<String>,
    pub intervals: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HybridData {
    pub groups: Vec<GroupItem>,
    #[serde(rename = "seqInterval", default)]
    pub seq_interval: u64,
}
// ... 其他模式类似
```

**方案 B 优势**：
1. 与现有 `config.json` 完全兼容（扁平结构）
2. `hotkey`/`name`/`keyPressDuration`/`mode` 不再重复定义
3. `holdKeys`/`holdMode`/`holdPattern`/`holdTriggers` 作为跨模式共享字段，放在 `GroupConfig` 顶层

**方案 B 风险**：
1. `#[serde(untagged)]` 的 `ModeData` 在反序列化时按 Variant 顺序尝试匹配，第一个匹配的 Variant 生效
2. 如果 `PeriodicData` 和 `EnhancedPeriodicData` 字段重叠（都有 `intervals`），需要确保顺序正确
3. `untagged` 的错误信息不友好

**最终推荐**：方案 B + Phase 0 验证。理由：
- 与现有 config.json 完全兼容
- 消除字段重复
- `untagged` 的风险可通过测试覆盖

### 16.2 🟡 中等：跨模式共享字段遗漏

**问题**：v4.0 的 serde 模型将 `holdKeys`/`holdMode`/`holdPattern`/`holdTriggers` 分散到各 Variant 中，但实际上这些字段在 4 种模式中共享：

| 字段 | 使用的模式 | v4.0 位置 |
|------|-----------|----------|
| `holdKeys` | enhanced_periodic, enhanced_sequence, enhanced_hybrid, hold | 各 Variant 重复定义 |
| `holdMode` | enhanced_periodic, enhanced_sequence, enhanced_hybrid | 各 Variant 重复定义 |
| `holdPattern` | enhanced_periodic, enhanced_sequence, enhanced_hybrid | 各 Variant 重复定义 |
| `holdTriggers` | enhanced_sequence, enhanced_hybrid | 各 Variant 重复定义 |

**修正**：在方案 B 中，将这些字段提升到 `GroupConfig` 顶层：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupConfig {
    pub hotkey: String,
    #[serde(rename = "keyPressDuration")]
    pub key_press_duration: u64,
    pub name: String,
    pub mode: String,
    #[serde(rename = "holdKeys", default)]
    pub hold_keys: Vec<String>,
    #[serde(rename = "holdMode", default = "default_hold_mode")]
    pub hold_mode: String,
    #[serde(rename = "holdPattern", default)]
    pub hold_pattern: Vec<serde_json::Value>,
    #[serde(rename = "holdTriggers", default)]
    pub hold_triggers: Vec<serde_json::Value>,
    #[serde(flatten)]
    pub mode_data: ModeData,
}

fn default_hold_mode() -> String { "continuous".to_string() }
```

### 16.3 🟡 中等：Tauri 插件版本未锁定

**问题**：报告中多次引用 `tauri-plugin-global-shortcut`、`tauri-plugin-updater`、`tauri-plugin-dialog`、`tauri-plugin-fs`，但未指定版本号。此外，错误引用了 `tauri-plugin-tray`（Tauri 2.x 托盘是核心功能，不是独立插件）。

**修正**：

| 插件 | 版本 | 说明 |
|------|------|------|
| `tauri-plugin-global-shortcut` | **2.3.1** | 全局快捷键 |
| `tauri-plugin-updater` | **2.10.1** | 自动更新 |
| `tauri-plugin-dialog` | **2.7.1** | 文件对话框 |
| `tauri-plugin-fs` | **2.5.1** | 文件系统 |

> **注意**：Tauri 2.x 的系统托盘**不是独立插件**，而是核心功能，通过 `tauri = { features = ["tray-icon"] }` 启用，使用 `tauri::tray::TrayIconBuilder` API。报告中此前引用的 `tauri-plugin-tray` 是错误的。

### 16.4 🟡 中等：`tauri-plugin-global-shortcut` API 变更

**问题**：8.3 节中的快捷键代码使用了旧版 API：

```rust
// v3.0 旧代码（可能已过时）
app.global_shortcut().on_shortcut("Ctrl+Shift+A", |app, _shortcut, event| {
```

**修正**：Tauri 2.x 的 `tauri-plugin-global-shortcut` 2.3.1 API：

```rust
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutEvent, ShortcutState};

fn setup_global_shortcut(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let shortcut: Shortcut = "Ctrl+Shift+A".parse()?;

    app.plugin(tauri_plugin_global_shortcut::Builder::new().build())?;

    let app_handle = app.handle().clone();
    app.global_shortcut().on_shortcut(shortcut, move |app, _shortcut, event| {
        if event.state == ShortcutState::Pressed {
            if let Some(window) = app.get_webview_window("main") {
                if window.is_visible().unwrap_or(false) {
                    let _ = window.hide();
                } else {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        }
    })?;

    app.global_shortcut().register(shortcut)?;
    Ok(())
}
```

### 16.5 🟡 中等：WebView2 离线安装场景

**问题**：9.3 节的 `tauri.conf.json` 使用 `downloadBootstrapper` 模式安装 WebView2，但未考虑离线场景。

**修正**：

```json
{
  "bundle": {
    "windows": {
      "webviewInstallMode": {
        "type": "downloadBootstrapper",
        "silent": true
      },
      "webviewFixedRuntimePath": ""
    }
  }
}
```

| 安装模式 | 适用场景 | 包体积影响 |
|---------|---------|-----------|
| `downloadBootstrapper` | 在线安装（推荐） | +0MB（运行时下载） |
| `embedBootstrapper` | 半离线（嵌入引导程序） | +2MB |
| `offlineInstaller` | 离线安装（嵌入完整运行时） | +150MB |
| `fixedRuntime` | 捆绑固定版本 | +150MB |

**建议**：默认使用 `downloadBootstrapper`，在 NSIS 安装脚本中检测网络状态，离线时提示用户手动安装 WebView2。

### 16.6 🟢 轻微：`parking_lot` vs `std::sync` 选型论证缺失

**问题**：4.5 节列出了 `parking_lot` 0.12.5，但未说明为何选用它而非 `std::sync::RwLock`/`Mutex`。

**补充论证**：

| 维度 | `std::sync` | `parking_lot` | 本项目选择 |
|------|------------|--------------|-----------|
| 公平性 | 公平锁（FIFO） | 不公平锁（可能饥饿） | `std::sync`（热键场景不能饥饿） |
| 性能 | 略慢（系统调用） | 略快（用户态自旋） | 差异 <1μs，不敏感 |
| Poison | 锁中毒（panic 时） | 无中毒 | `parking_lot` 更简单 |
| TryLock | 需要 `try_lock()` | 同 | 同 |
| API 兼容 | 标准库，零依赖 | 额外依赖 | `std::sync` 更少依赖 |

**结论**：**移除 `parking_lot` 依赖**，使用 `std::sync::RwLock`/`Mutex`。理由：
1. 本项目锁持有时间极短（<1ms），`parking_lot` 的性能优势可忽略
2. 减少一个外部依赖，降低供应链风险
3. `std::sync` 的锁中毒机制在 debug 阶段更有价值

### 16.7 🟢 轻微：`serde` 版本不一致

**问题**：4.5 节表格中 `serde` 版本写为 `1.0.227`，但 `serde_json` 依赖的 `serde` 版本可能不同。

**修正**：`serde` 最新稳定版为 **1.0.228**，`serde_json` 1.0.150 依赖 `serde` 1.0.x，版本兼容。Cargo.toml 中应写：

```toml
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
```

无需锁定小版本号，Cargo 自动解析兼容版本。

### 16.8 问题严重程度汇总

| # | 严重程度 | 问题 | 影响 | 修正方案 |
|---|:-------:|------|------|---------|
| 16.1 | 🔴 严重 | `tag`+`flatten` serde 兼容性 | 反序列化可能失败 | 改用 `untagged` + `flatten` 方案 B |
| 16.2 | 🟡 中等 | 跨模式共享字段重复 | DRY 违反、维护困难 | 提升到 `GroupConfig` 顶层 |
| 16.3 | 🟡 中等 | Tauri 插件版本未锁定 | 构建不可复现 | 锁定插件版本 |
| 16.4 | 🟡 中等 | `global-shortcut` API 过时 | 编译失败 | 更新为 2.3.1 API |
| 16.5 | 🟡 中等 | WebView2 离线场景缺失 | 离线用户无法安装 | 补充离线安装策略 |
| 16.6 | 🟢 轻微 | `parking_lot` 选型无论证 | 不必要的依赖 | 移除，改用 `std::sync` |
| 16.7 | 🟢 轻微 | `serde` 版本不一致 | 混淆 | 统一为 `1.0` |

---

## 十七、第三轮深度审查：系统性问题与架构风险

> **v5.0 新增** — 全文逐章审查，覆盖版本兼容性、API 正确性、架构一致性、遗漏风险

### 17.1 🟡 中等：`windows` crate 双版本共存

**问题**：项目使用 `windows` **0.62.2**，但 Tauri 2.11.2 的依赖链锁定 `windows` **^0.61**。Cargo 将解析为两个不同版本：

```
windows 0.62.2 (项目直接依赖)
windows 0.61.x (Tauri → tao → windows 0.61.x)
```

**影响评估**：
1. **类型不兼容**：`windows::Win32::Foundation::HANDLE` 在 0.61 和 0.62 中是不同类型，无法互传 — **但项目代码不需要将 `windows` 类型传递给 Tauri API**，两者使用场景完全隔离
2. **编译体积增大**：两个版本各自编译，增加 ~2-3MB 二进制体积 — **可接受**
3. **API 行为差异**：0.62 可能有 0.61 不存在的 API — **正是选择 0.62 的理由**

**决策：接受双版本共存**（方案 B）

| 方案 | 操作 | 优劣 |
|------|------|------|
| A | 降级项目 `windows` 依赖到 **0.61.x**，与 Tauri 保持一致 | 零冲突，但失去 0.62 新 API |
| **B（采纳）** | **保持 `windows` 0.62.2，接受双版本共存** | **获得最新 API，体积增 2-3MB，类型隔离无冲突** |
| C | 仅在 AHK 子进程管理中使用 `windows-sys` 0.61.x | `windows-sys` 是 FFI 绑定，无类型冲突 |

**可行性论证**：
- 项目使用 `windows` 0.62.2 的场景：`WM_CLOSE`/`PostMessageW`（子进程管理）、`CreateJobObjectW`/`AssignProcessToJobObject`（Job Object）、`SendInput`（按键模拟）、`RegisterHotKey`（热键注册）
- Tauri 使用 `windows` 0.61.x 的场景：WebView2 窗口管理、消息循环
- **两者无类型交互**，各自独立使用，不存在互传 `HANDLE` 等类型的场景

**验证证据**（crates.io API 实查）：

| Crate | 版本 | `windows` 依赖 | Features |
|-------|------|:--------------:|----------|
| `tauri` | 2.11.2 | `^0.61` | `Win32_Foundation, Win32_UI, Win32_UI_WindowsAndMessaging` |
| `tauri-runtime` | 2.11.2 | `^0.61` | 2 extra features |
| `tauri-runtime-wry` | 2.11.2 | `^0.61` | 2 extra features |
| `tao` | 0.35.0 | `^0.61` | (via tauri-runtime-wry) |

**完整依赖链**：`tauri 2.11.2` → `tauri-runtime 2.11.2` → `windows ^0.61`；`tauri 2.11.2` → `tauri-runtime-wry 2.11.2` → `tao ^0.35.0` → `windows ^0.61`。**三层依赖全部锁定在 0.61.x**。

**`interprocess` 兼容性验证**：`interprocess` 2.4.2 依赖 `windows-sys ^0.61.0`（纯 FFI 绑定），而非 `windows` crate。两者不冲突——`windows-sys` 仅提供函数声明和类型定义，不与 `windows` crate 的类型系统交互。因此 `interprocess` 2.4.2 完全兼容项目依赖方案。

**MSRV 修正**：

| Crate | 版本 | MSRV | 备注 |
|-------|------|:----:|------|
| `tauri` | 2.11.2 | 1.77.2 | 不变 |
| `windows` | **0.62.2** | **1.82.0** | 项目直接依赖 |
| `interprocess` | 2.4.2 | 1.75.0 | 不变 |
| **项目 MSRV** | — | **1.82.0** | 由 `windows` 0.62.2 决定（最高） |

### 17.2 🔴 严重：`tauri-plugin-global-shortcut` API 签名错误

**问题**：16.4 节修正后的 `on_shortcut` API 签名仍然有误。根据 `tauri-plugin-global-shortcut` 2.3.1 的官方文档，`on_shortcut` 方法签名是：

```rust
pub fn on_shortcut<S, F>(&self, shortcut: S, handler: F) -> Result<(), Error>
where
    S: TryInto<ShortcutWrapper>,
    S::Error: Error,
    F: Fn(&AppHandle<R>, &Shortcut, ShortcutEvent) + Send + Sync + 'static,
```

**关键差异**：
1. handler 接收 `(&AppHandle, &Shortcut, ShortcutEvent)` **三个参数**，不是 `(shortcut, event, _)`
2. `ShortcutEvent` 不是 `ShortcutState`（`ShortcutEvent` 包含 `.state` 字段，类型为 `ShortcutState`）
3. `on_shortcut` 是**按快捷键注册**的，不是全局回调
4. `register` 和 `on_shortcut` 是**分开调用**的

**验证证据**（docs.rs/tauri-plugin-global-shortcut/2.3.1 实查）：

```rust
// GlobalShortcut::on_shortcut 官方签名
pub fn on_shortcut<S, F>(&self, shortcut: S, handler: F) -> Result<(), Error>
where
    S: TryInto<ShortcutWrapper>,
    S::Error: Error,
    F: Fn(&AppHandle<R>, &Shortcut, ShortcutEvent) + Send + Sync + 'static,
//  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//  注意：3 个参数，不是 2 个

// ShortcutEvent 结构体
pub struct ShortcutEvent {
    pub id: u32,           // 关联的快捷键 ID
    pub state: ShortcutState,  // Pressed / Released
}
```

**修正代码**：

```rust
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutEvent};

fn setup_global_shortcut(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let shortcut: Shortcut = "Ctrl+Shift+A".parse()?;

    app.plugin(tauri_plugin_global_shortcut::Builder::new().build())?;

    let app_handle = app.handle().clone();
    app.global_shortcut().on_shortcut(shortcut, move |app, shortcut, event| {
        if event.state == tauri_plugin_global_shortcut::ShortcutState::Pressed {
            if let Some(window) = app.get_webview_window("main") {
                if window.is_visible().unwrap_or(false) {
                    let _ = window.hide();
                } else {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        }
    })?;

    Ok(())
}
```

**8.3 节的旧代码同样需要修正**。

### 17.3 🟡 中等：Tauri 插件版本号修正

**问题**：16.3 节的插件版本号需要更新为实际最新版：

| 插件 | 16.3 版本 | 实际最新版 | 修正 |
|------|:---------:|:---------:|------|
| `tauri-plugin-global-shortcut` | 2.3.1 | **2.3.1** | ✅ 已正确 |
| `tauri-plugin-updater` | 2.10.1 | **2.10.1** | ✅ 已正确 |
| `tauri-plugin-dialog` | 2.7.1 | **2.7.1** | ✅ 已正确 |
| `tauri-plugin-fs` | 2.5.1 | **2.5.1** | ✅ 已正确 |
| ~~`tauri-plugin-tray`~~ | ~~2.3.0~~ | **不存在** | ❌ 移除，Tauri 2.x 托盘是核心 `tray-icon` feature |

### 17.4 🟡 中等：`GenerateConsoleCtrlEvent` 对 GUI 进程无效

**问题**：15.2 节的优雅关机流程中，Phase 2 使用 `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, ...)` 发送信号给 AHK 子进程。但 Windows 文档明确指出：

> `GenerateConsoleCtrlEvent` only works with console processes. If the target process is a GUI process (no console), the function has no effect.

AHK 编译后的 `asd_executor.exe` 可能是 GUI 进程（取决于编译方式），此时 `GenerateConsoleCtrlEvent` 无效。

**修正**：

```
阶段 1: 发送 shutdown IPC 消息（给 AHK 2s 清理时间）
    ↓ 超时 2s
阶段 2: 发送 WM_CLOSE 消息（PostMessage 到子进程主窗口）
    ↓ 超时 3s
阶段 3: TerminateProcess（强制终止）
```

```rust
async fn graceful_shutdown(child: &mut Child) -> Result<(), WatchdogError> {
    // Phase 1: IPC shutdown 消息
    // ...（同 v4.0）

    // Phase 2: WM_CLOSE（替代 GenerateConsoleCtrlEvent）
    if let Ok(pid) = child.id().ok_or(WatchdogError::NoPid) {
        let _ = send_wm_close(pid).await;
    }

    match tokio::time::timeout(
        std::time::Duration::from_secs(3),
        child.wait()
    ).await {
        Ok(Ok(_)) => return Ok(()),
        _ => {}
    }

    // Phase 3: 强制终止
    let _ = child.kill().await;
    Ok(())
}

async fn send_wm_close(pid: u32) -> Result<(), windows::core::Error> {
    use windows::Win32::UI::WindowsAndMessaging::{EnumWindows, GetWindowThreadProcessId, PostMessageW, WM_CLOSE};
    use windows::Win32::Foundation::{BOOL, HWND, LPARAM, WPARAM};

    unsafe {
        let pid_ptr = Box::into_raw(Box::new(pid));
        let result = EnumWindows(
            Some(enum_callback),
            LPARAM(pid_ptr as isize),
        );
        let _ = Box::from_raw(pid_ptr);
        result
    }
    Ok(())
}

unsafe extern "system" fn enum_callback(hwnd: HWND, lparam: LPARAM) -> BOOL {
    let pid = &*(lparam.0 as *const u32);
    let mut window_pid: u32 = 0;
    GetWindowThreadProcessId(hwnd, Some(&mut window_pid));
    if window_pid == *pid {
        let _ = PostMessageW(hwnd, WM_CLOSE, WPARAM(0), LPARAM(0));
    }
    BOOL(1)
}
```

### 17.5 🟡 中等：Job Object 句柄泄漏

**问题**：15.4 节的 `create_job_object` 返回 `isize`（原始句柄），但未提供关闭机制。当 Rust 主进程正常退出时，Windows 自动关闭句柄并终止子进程，但如果 Watchdog 重启子进程时需要重新创建 Job Object，旧句柄会泄漏。

**修正**：使用 RAII 包装器：

```rust
use windows::Win32::Foundation::HANDLE;
use windows::Win32::System::JobObjects::{CreateJobObjectW, SetInformationJobObject, AssignProcessToJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE};

struct JobObjectGuard(HANDLE);

impl JobObjectGuard {
    fn create() -> Result<Self, windows::core::Error> {
        unsafe {
            let job = CreateJobObjectW(None, None)?;
            let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                &info as *const _ as *const _,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )?;
            Ok(Self(job))
        }
    }

    fn assign(&self, child: &Child) -> Result<(), windows::core::Error> {
        use windows::Win32::System::Threading::{OpenProcess, PROCESS_SET_QUOTA, PROCESS_TERMINATE};
        unsafe {
            let proc_handle = OpenProcess(
                PROCESS_SET_QUOTA | PROCESS_TERMINATE,
                false,
                child.id(),
            )?;
            AssignProcessToJobObject(self.0, proc_handle)
        }
    }
}

impl Drop for JobObjectGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = windows::Win32::Foundation::CloseHandle(self.0);
        }
    }
}
```

### 17.6 🟡 中等：`stop_recording` Command 设计缺陷

**问题**：13.3 节的 `stop_recording` Command 使用 `oneshot::channel` 作为 `IpcCommand::StopRecording` 的参数，但 `IpcCommand` 需要通过 Named Pipe 发送给 AHK 子进程，而 `oneshot::Sender` 无法序列化。

```rust
// ❌ 错误：oneshot::Sender 无法跨 IPC 传递
let (tx, rx) = tokio::sync::oneshot::channel();
let msg = IpcCommand::StopRecording { reply_to: tx };
state.ipc_outbound.send(IpcMessage::command(0, &msg)).await
```

**修正**：使用 `seq` 关联请求-响应：

```rust
#[tauri::command]
async fn stop_recording(state: State<'_, AppState>) -> Result<RecordingResult, AppError> {
    let seq = state.ipc_manager.send_command(&IpcCommand::StopRecording).await
        .map_err(|e| AppError::Ipc(e.to_string()))?;
    // 等待 AHK 返回 ack_seq == seq 的响应
    let result = state.ipc_manager.wait_response(seq).await
        .map_err(|e| AppError::Ipc(e.to_string()))?;
    Ok(result)
}
```

### 17.7 🟡 中等：`IpcManager` 结构体缺少 `tokio::sync::Mutex` 导入

**问题**：12.1 节的 `IpcManager` 使用 `tokio::sync::Mutex<LocalSocketStream>`，但 `send_command` 方法中 `self.writer.lock().await` 需要确保 `Mutex` 是 `tokio::sync::Mutex`（跨 `.await`），而非 `std::sync::Mutex`。

**修正**：明确导入路径，并在注释中说明选择理由：

```rust
use tokio::sync::Mutex; // 跨 .await 持有锁，必须用 tokio Mutex

struct IpcManager {
    writer: Mutex<LocalSocketStream>,
    seq_counter: std::sync::atomic::AtomicU64,
}
```

### 17.8 🟡 中等：`AppState` 中 `ipc_manager` 使用 `std::sync::Mutex` 的风险

**问题**：13.2 节的 `AppState.ipc_manager: Mutex<Option<IpcManager>>` 使用 `std::sync::Mutex`，但 `IpcManager` 内部的 `writer: tokio::sync::Mutex<LocalSocketStream>` 需要 `.await`。如果外部 `std::sync::Mutex` 的锁跨越 `.await` 点，会导致编译错误。

**修正**：`ipc_manager` 应使用 `tokio::sync::Mutex`：

```rust
pub struct AppState {
    pub config: std::sync::RwLock<Config>,
    pub groups: std::sync::RwLock<HashMap<String, SkillGroup>>,
    pub ipc_manager: tokio::sync::Mutex<Option<IpcManager>>, // 改为 tokio Mutex
    pub ipc_outbound: tokio::sync::mpsc::Sender<IpcMessage>,
    pub active_hotkeys: std::sync::RwLock<HashMap<String, String>>,
    pub emergency_mode: std::sync::atomic::AtomicBool,
    pub hold_mode_enabled: std::sync::atomic::AtomicBool,
    pub watchdog_state: std::sync::RwLock<WatchdogState>,
}
```

### 17.9 🟢 轻微：`enhanced_periodic` 的 `intervals` 类型应为 `Vec<u64>`

**问题**：14.3 节 `EnhancedPeriodicConfig` 的 `intervals` 字段类型为 `u64`（单个值），但根据 AHK 源码和 `tests/config.json`，`intervals` 始终是数组。

```json
"5": {
  "intervals": [50],
  "mode": "enhanced_periodic"
}
```

**修正**：`intervals: Vec<u64>` 而非 `intervals: u64`。

### 17.10 🟢 轻微：`Config` 结构体缺少 `HoldSettings` 可选处理

**问题**：14.3 节的 `Config` 结构体中 `HoldSettings` 是必需字段，但根 `config.json` 中可能没有 `HoldSettings` 键（仅在 `tests/config.json` 中存在）。

**修正**：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(rename = "CONTROL_HOTKEYS")]
    pub control_hotkeys: ControlHotkeys,
    #[serde(rename = "GroupSettings")]
    pub group_settings: HashMap<String, GroupConfig>,
    #[serde(rename = "HoldSettings", default)]
    pub hold_settings: Option<HoldSettings>,
    #[serde(rename = "lastModified", default)]
    pub last_modified: Option<String>,
    #[serde(default)]
    pub version: Option<String>,
}
```

### 17.11 🟢 轻微：性能估算缺少置信度标注

**问题**：5.1 节的性能提升倍数（24x、50x 等）均为理论估算，但未标注置信度。读者可能误以为是实测数据。

**修正**：在表格标题添加"理论估算"标注，并增加置信度列：

| 路径 | 提升 | 置信度 | 验证方法 |
|------|:----:|:------:|---------|
| 配置加载 | 24x | 高 | serde vs AHK 自研解析器，差异明确 |
| 按键校验 | 50x | 中 | 取决于校验逻辑复杂度 |
| JS↔Rust IPC | 50-100x | 高 | Tauri 二进制协议 vs COM Bridge |
| 启动速度 | 5-8x | 低 | 受 WebView2 初始化影响大 |

### 17.12 问题严重程度汇总

| # | 严重程度 | 问题 | 影响 | 修正方案 |
|---|:-------:|------|------|---------|
| 17.1 | 🟡 中等 | `windows` crate 双版本共存 | 体积增 2-3MB | 接受共存，MSRV 升至 1.82.0 |
| 17.2 | 🔴 严重 | `global-shortcut` API 签名错误 | 编译失败 | 修正为 `on_shortcut(shortcut, handler)` |
| 17.3 | 🟡 中等 | 插件版本号过时 | 使用旧版 | 更新 `global-shortcut` 到 2.3.1、`updater` 到 2.10.1 |
| 17.4 | 🟡 中等 | `GenerateConsoleCtrlEvent` 对 GUI 进程无效 | 优雅关机失败 | 改用 `WM_CLOSE` |
| 17.5 | 🟡 中等 | Job Object 句柄泄漏 | 资源泄漏 | RAII 包装器 + `Drop` |
| 17.5a | 🔴 严重 | `AssignProcessToJobObject` 使用 PID 而非句柄 | 编译错误/运行时崩溃 | 使用 `OpenProcess` 获取进程句柄 |
| 17.4a | 🟡 中等 | `EnumWindows` 回调内存泄漏 | 堆内存泄漏 | `Box::from_raw` 回收 |
| 17.3a | 🟡 中等 | `interprocess` 与 `windows` crate 兼容性未验证 | 潜在冲突 | 已验证：`interprocess` 用 `windows-sys`，不冲突 |
| 17.6 | 🟡 中等 | `stop_recording` oneshot 无法序列化 | 编译失败 | 改用 `seq` 关联请求-响应 |
| 17.7 | 🟡 中等 | `IpcManager` Mutex 类型歧义 | 编译错误/死锁 | 明确 `tokio::sync::Mutex` |
| 17.8 | 🟡 中等 | `AppState.ipc_manager` 锁类型错误 | 跨 `.await` 编译失败 | 改为 `tokio::sync::Mutex` |
| 17.9 | 🟢 轻微 | `enhanced_periodic.intervals` 类型错误 | 反序列化失败 | 改为 `Vec<u64>` |
| 17.10 | 🟢 轻微 | `HoldSettings` 缺少 `Option` | 无 `HoldSettings` 时崩溃 | 改为 `Option<HoldSettings>` |
| 17.11 | 🟢 轻微 | 性能估算缺置信度 | 误导读者 | 添加置信度列 |

---

## 十八、第五轮深度审查：正文一致性修正与遗漏补充

> **v8.0 新增** — 全文正文代码与审查章节的一致性修正、`tauri-plugin-tray` 错误纠正、插件版本更新

### 18.1 🔴 严重：`tauri-plugin-tray` 不存在

**问题**：报告多处引用 `tauri-plugin-tray` 作为独立插件，但 Tauri 2.x 的系统托盘**不是独立插件**，而是 Tauri 核心功能，通过 `tauri` crate 的 `tray-icon` feature 启用。

**影响**：
1. 读者在 `Cargo.toml` 中添加 `tauri-plugin-tray` 会导致编译错误（crate 不存在）
2. 架构设计文档与实际 API 不一致
3. 误导读者对 Tauri 2.x 插件生态的理解

**修正**：
- 4.5 节 Tauri 内置能力表：`tauri-plugin-tray` → `tauri` 核心 `tray-icon` feature
- 7.1 Phase 3：`tauri-plugin-tray` → `tauri tray-icon feature + TrayIconBuilder`
- 16.3 节插件版本表：移除 `tauri-plugin-tray`，添加说明
- 17.3 节版本对比表：标记为不存在

**正确用法**：
```toml
# Cargo.toml
[dependencies]
tauri = { version = "2.11.2", features = ["tray-icon"] }
```
```rust
use tauri::tray::TrayIconBuilder;
// 在 setup 中创建托盘
let tray = TrayIconBuilder::new()
    .icon(app.default_window_icon().unwrap().clone())
    .build(app)?;
```

### 18.2 🔴 严重：8.3 节 `global_shortcut` API 与 17.2 修正不一致

**问题**：17.2 节已修正 `on_shortcut` API 签名（3 参数 + `Shortcut` 类型解析），但 8.3 节正文仍使用旧版 API（字符串参数 + 2 参数回调）。

**修正**：8.3 节代码已同步更新为 17.2 的修正版本。

### 18.3 🟡 中等：13.2 节 `ipc_manager` Mutex 类型与 17.8 修正不一致

**问题**：17.8 节已论证 `ipc_manager` 应使用 `tokio::sync::Mutex`（跨 `.await` 持有锁），但 13.2 节正文仍使用 `std::sync::Mutex`，导入为 `use std::sync::{Arc, Mutex, RwLock}`。

**修正**：
- 导入改为 `use std::sync::RwLock; use tokio::sync::{Mutex, mpsc};`
- 同步原语表 `ipc_manager` 行改为 `tokio::sync::Mutex`
- 13.4 Tauri Builder 初始化改为 `tokio::sync::Mutex::new(None)`

### 18.4 🟡 中等：4.5 节 `parking_lot` 仍列出但 16.6 已论证移除

**问题**：16.6 节已论证移除 `parking_lot`（性能优势可忽略、减少外部依赖），但 4.5 节 Crate 选型表仍列出 `parking_lot 0.12.5`。

**修正**：从 4.5 节表格中移除 `parking_lot` 行。

### 18.5 🟡 中等：Tauri 插件版本号过时

**问题**：16.3 节的插件版本号经过 crates.io 实查，多个插件版本过时：

| 插件 | 修正前 | 修正后 | 验证来源 |
|------|:------:|:------:|---------|
| `tauri-plugin-global-shortcut` | 2.2.2 | **2.3.1** | crates.io |
| `tauri-plugin-updater` | 2.7.1 | **2.10.1** | crates.io |
| `tauri-plugin-dialog` | 2.2.2 | **2.7.1** | crates.io |
| `tauri-plugin-fs` | 2.3.0 | **2.5.1** | crates.io |

**修正**：16.3 节和 17.3 节版本号已更新。

### 18.6 🟡 中等：9.4 长期维护优势表引用 `tauri-plugin-tray`

**问题**：9.4 节"自动更新"行引用 `tauri-plugin-updater`，但系统托盘能力未正确标注来源。

**修正**：系统托盘使用 `tauri` 核心 `tray-icon` feature，而非独立插件。

### 18.7 🟢 轻微：`serde` 版本号已修正

**问题**：4.5 节 `serde` 版本写为 1.0.227，实际最新为 1.0.228。

**修正**：已更新为 1.0.228。但建议 `Cargo.toml` 中使用 `serde = "1.0"` 而非锁定小版本号，由 Cargo 自动解析兼容版本。

### 18.8 问题严重程度汇总

| # | 严重程度 | 问题 | 影响 | 修正方案 |
|---|:-------:|------|------|---------|
| 18.1 | 🔴 严重 | `tauri-plugin-tray` 不存在 | 编译错误、架构误导 | 改为 `tauri` 核心 `tray-icon` feature |
| 18.2 | 🔴 严重 | 8.3 节 API 与 17.2 修正不一致 | 代码示例不可用 | 同步更新 8.3 节代码 |
| 18.3 | 🟡 中等 | 13.2 节 Mutex 类型与 17.8 修正不一致 | 编译错误/死锁 | 同步更新 13.2 节代码和导入 |
| 18.4 | 🟡 中等 | 4.5 节仍列出 `parking_lot` | 依赖混淆 | 从选型表移除 |
| 18.5 | 🟡 中等 | 插件版本号过时 | 构建不可复现 | 更新至 crates.io 最新版 |
| 18.6 | 🟡 中等 | 9.4 节托盘来源标注错误 | 误导读者 | 修正为核心 feature |
| 18.7 | 🟢 轻微 | `serde` 版本号过时 | 混淆 | 更新为 1.0.228 |
| 18.8a | 🔴 严重 | 12.1 `PIPE_NAME.to_ns()` API 不存在 | 编译失败 | 改为 `to_ns_name::<GenericNamespaced>()` |
| 18.8b | 🟡 中等 | 12.1 `send_command` 参数应为 owned | API 不一致 | `&IpcCommand` → `IpcCommand` |
| 18.8c | 🟡 中等 | 15.2 正文仍用 `GenerateConsoleCtrlEvent` | 优雅关机失败 | 同步 17.4 修正为 `WM_CLOSE` |
| 18.8d | 🟡 中等 | 15.4 正文 `assign_to_job` 用 PID 转句柄 | 编译错误/运行时崩溃 | 同步 17.5 修正为 `OpenProcess` |
| 18.8e | 🟡 中等 | 5.1 性能表缺置信度 | 误导读者 | 添加置信度列 |
| 18.8f | 🟡 中等 | 6.3 capabilities 缺 `global-shortcut` 权限 | 运行时权限错误 | 添加 `global-shortcut:allow-register/unregister` |
| 18.8g | 🟡 中等 | 6.6 `AppError` 使用 `anyhow::Error` | 不必要的依赖 | 改为 `Internal(String)` |
| 18.8h | 🟢 轻微 | 7.2 Cargo 版本约束 `~2.11` 语义不当 | 版本锁定过宽 | 改为 `"2.11"` 精确约束 |
| 18.8i | 🟢 轻微 | 11.3 插件评估建议缺版本号 | 执行时需重新查证 | 补充已验证版本号 |

---

## 附录 A: 版本变更日志

| 版本 | 日期 | 变更摘要 |
|------|------|---------|
| v1.0 | 2026-05-28 | 初始报告，裸 wry 架构 |
| v2.0 | 2026-05-28 | 审查修订：Crate 版本更新、MSRV 分析、IPC 修正、补充遗漏章节 |
| v3.0 | 2026-05-28 | 架构决策：裸 wry → Tauri 2.11.2，双层 IPC 设计，Tauri Commands 替代 presentation 层 |
| **v4.0** | **2026-05-28** | **深度审查：IPC 协议完善（帧协议/背压/错误恢复）、Tauri Commands 完整 API（统一错误/状态管理）、配置兼容性 10 模式 serde 映射（修正 mode 鉴别）、子进程管理细化（状态机/优雅关机/Job Object）** |
| **v5.0** | **2026-05-28** | **第二轮审查：serde tag+flatten 兼容性修正（方案B untyped+flatten）、跨模式共享字段提升、Tauri 插件版本锁定、global-shortcut API 更新、WebView2 离线策略、parking_lot 移除论证** |
| **v6.0** | **2026-05-28** | **第三轮审查：`windows` crate 0.62→0.61 版本冲突修正、MSRV 1.82→1.77.2、`global-shortcut` 2.3.1 API 签名修正、`GenerateConsoleCtrlEvent`→`WM_CLOSE`、Job Object RAII、`stop_recording` 序列化修正、Mutex 类型修正、`intervals` Vec 修正、`HoldSettings` Option 修正、性能置信度标注** |
| **v7.0** | **2026-05-28** | **第四轮审查：完整依赖链验证（crates.io 实查 `tauri`/`tauri-runtime`/`tauri-runtime-wry`/`tao` 均锁定 `windows ^0.61`）、`interprocess` 2.4.2 兼容性确认（`windows-sys ^0.61`，不与 `windows` crate 冲突）、`AssignProcessToJobObject` 修正（`OpenProcess` 替代 PID 直接转换）、`EnumWindows` 回调内存泄漏修正（`Box::from_raw` 回收）、`tauri-plugin-updater` 版本更新至 2.10.1、`on_shortcut` API 签名验证证据补充** |
| **v8.0** | **2026-05-28** | **第五轮审查：`tauri-plugin-tray` 错误纠正（Tauri 2.x 托盘是核心 `tray-icon` feature）、8.3/13.2/15.2/15.4 正文代码与审查章节一致性修正、4.5 节移除 `parking_lot`、Tauri 插件版本 crates.io 实查更新（dialog 2.7.1、fs 2.5.1、global-shortcut 2.3.1）、`serde` 1.0.228、12.1 `interprocess` API 修正（`to_ns_name`）、5.1 性能表置信度、6.3 capabilities 补充 `global-shortcut` 权限、6.6 `AppError` 移除 `anyhow` 依赖、7.2 Cargo 版本约束修正、15.2 `GenerateConsoleCtrlEvent`→`WM_CLOSE` 正文同步、15.4 `assign_to_job` 正文同步 `OpenProcess`** |

## 附录 B: 审查变更日志（v1.0→v2.0）

| 章节 | 变更类型 | 说明 |
|------|---------|------|
| 2.1 代码规模 | 修正 | 实际统计 13,184 行/37 文件（原 13,220/40） |
| 2.3 技术依赖 | 补充 | 新增 ipc_channel、Tauri |
| 2.4 现有 IPC | 新增 | 记录现有 ipc_channel.ahk 实现 |
| 3.3 MSRV 约束 | 新增 | 各 Crate MSRV 分析，项目基线 1.82.0 |
| 4.3 IPC 协议 | 修正 | 新增 seq/ack_seq/error 消息；修正延迟估算 |
| 5.2 内存对比 | 修正 | 修正 "serde 零拷贝" 描述 |
| 6.6 thiserror | 新增 | 2.0 迁移挑战与方案 |
| 6.7 子进程管理 | 新增 | ProcessWatchdog 设计 |
| 8.1 配置兼容性 | 补充 | config.json 结构分析与 serde 映射注意事项 |
| 十、调试策略 | 新增 | 多进程调试、IPC 日志、集成测试策略 |

## 附录 C: v2.0→v3.0 变更日志

| 章节 | 变更类型 | 说明 |
|------|---------|------|
| 4.1 整体架构 | 重构 | 裸 wry → Tauri 2.11.2，双层 IPC 架构 |
| 4.2 项目结构 | 重构 | Tauri 约定目录结构，commands/ 替代 presentation/ |
| 4.3 Tauri Commands | 新增 | JS↔Rust IPC 设计（invoke/emit） |
| 4.4 AHK IPC | 保留 | Named Pipe 协议不变 |
| 4.5 Crate 选型 | 修正 | 新增 tauri 2.11.2，移除 wry/webview2-com 独立项 |
| 4.6 Tauri vs wry | 新增 | 架构决策记录 |
| 6.3 权限配置 | 替代 | 原 WebView2 COM → Tauri capabilities |
| 8.3 快捷键 | 修正 | 使用 tauri-plugin-global-shortcut |
| 9.2 CI/CD | 修正 | Tauri 构建流程 |
| 9.3 构建打包 | 重构 | Tauri 内置 NSIS/MSI 打包 |

---

*报告撰写人：AI 首席架构师 | v1.0 → v2.0 审查修订 → v3.0 Tauri 架构 → v4.0 深度审查 → v5.0 第二轮审查 → v6.0 第三轮审查 → v7.0 第四轮审查 → v8.0 第五轮审查 | 审核状态：待用户审核*
