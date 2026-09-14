<!-- Generated: 2026-03-24T20:45:00+08:00 | Updated: 2026-08-20T00:00:00+08:00 -->

# ASD 技能管理器 v4.0

## Purpose

ASD 技能管理器 - 支持多种执行模式的按键连招管理系统。v4.0 采用 **Rust/Tauri + AHK 混合架构**：Rust 负责核心逻辑与 GUI，AHK 执行器作为子进程负责按键模拟与热键钩子。

- **AHK v2 部分**（项目根目录）：v3.0 采用严格 DDD 四层架构，作为独立运行模式保留
- **Rust/Tauri 部分**（`asd-tauri/`）：v4.0 采用 5-crate workspace 架构，通过 IPC 管理 AHK 子进程

## Key Files

### AHK v2 部分（项目根目录）

| File                          | Description                                 |
| ----------------------------- | ------------------------------------------- |
| `main.ahk`                    | 主入口 + 依赖注入 + 初始化                        |
| `asd.ahk`                     | 兼容别名入口 → `#Include "main.ahk"`            |
| `config.json`                 | 运行时配置文件                                   |
| `presentation/app_ui.html`    | WebView2 现代化 GUI 界面（HTML/CSS/JS）         |
| `presentation/webview2_manager.ahk` | WebView2 表现层管理器 + AHK-JS Bridge    |

### Rust/Tauri 部分（asd-tauri/）

| File | Description |
|------|-------------|
| `asd-tauri/Cargo.toml` | Workspace root（resolver = "2"，5 members） |
| `asd-tauri/crates/asd-domain/src/config.rs` | Config, GroupConfig, ModeData, WatchdogStateEnum |
| `asd-tauri/crates/asd-domain/src/models.rs` | SkillGroup 领域模型 |
| `asd-tauri/crates/asd-domain/src/validator.rs` | ConfigValidator |
| `asd-tauri/crates/asd-domain/src/traits.rs` | IpcSender, EventEmitter, ProcessWatcher trait |
| `asd-tauri/crates/asd-ipc-protocol/src/command.rs` | IpcCommand（13 variants） |
| `asd-tauri/crates/asd-ipc-protocol/src/message.rs` | IpcMessage + constructors |
| `asd-tauri/crates/asd-ipc-protocol/src/error.rs` | IpcError |
| `asd-tauri/crates/asd-ipc-protocol/src/hotkey_merger.rs` | HotkeyMerger |
| `asd-tauri/crates/asd-application/src/state.rs` | AppState + trait objects |
| `asd-tauri/crates/asd-application/src/config_repository.rs` | ConfigRepository（file I/O） |
| `asd-tauri/crates/asd-application/src/error.rs` | AppError |
| `asd-tauri/crates/asd-application/src/backup_service.rs` | BackupService（备份创建与恢复） |
| `asd-tauri/crates/asd-application/src/group_service.rs` | GroupService（分组增删改查） |
| `asd-tauri/crates/asd-application/src/recording_service.rs` | RecordingService（按键录制） |
| `asd-tauri/crates/asd-application/src/time_format.rs` | 时间格式化工具 |
| `asd-tauri/src-tauri/src/lib.rs` | 34 Tauri commands + 应用初始化 |
| `asd-tauri/src-tauri/src/bridge.rs` | IpcBridge, TauriEventBridge, WatchdogBridge（trait 实现） |
| `asd-tauri/src-tauri/src/infrastructure/ipc.rs` | IpcManager（interprocess 通信） |
| `asd-tauri/src-tauri/src/infrastructure/watchdog.rs` | ProcessWatchdog + WatchdogRunner |
| `asd-tauri/src-tauri/src/infrastructure/logging.rs` | tracing 日志初始化 |
| `asd-tauri/src-tauri/src/infrastructure/shutdown.rs` | 关机锁 `try_acquire_shutdown_guard` 纯函数 |
| `asd-tauri/src-tauri/src/commands/` | config_cmd, group_cmd, hotkey_cmd, recording_cmd, system_cmd |
| `asd-tauri/src-tauri/src/tests/` | ipc_tests, config_compat_tests, bridge_tests, command_contract_tests, watchdog_integration_tests, mod |
| `asd-tauri/src-tauri/ahk_executor/` | AHK 子进程执行器（executor.ahk, ipc_client.ahk, hotkey_hook.ahk, sender.ahk, joystick.ahk, high_res_clock.ahk 等） |
| `asd-tauri/src/main.js` | Vite 前端入口 |
| `asd-tauri/src/api.js` | 前端 API 封装（Tauri invoke） |

## Architecture

### AHK v2 架构（DDD 四层）

| Layer            | Directory          | Modules                                     |
| ---------------- | ------------------ | ------------------------------------------- |
| 领域层 (domain)     | `domain/`          | `interfaces`, `joystick_input`, `joystick_executor`, `key_recorder`, `key_validator`, `skill_group`, `skill_manager`, `mode_registry` |
| 基础设施层 (infra)    | `infrastructure/`  | `config_store`, `json_parser`, `json_serializer`, `config_validator`, `debug_logger`, `json_logger`, `error_system`, `error_handler`, `backup_core`, `utils`, `ipc_channel`, `joy_hotkey_manager`, `config_io`, `joy_sender`, `migration_logger` |
| 应用层 (application) | `application/`     | `group_service`, `config_service`, `backup_service` |
| 表现层 (presentation) | `presentation/`    | `webview2_manager`, `ui_manager`, `gui_manager`, `group_editor`, `backup_ui`, `debug_panel` |
| 测试层 (tests)       | `tests/`           | `test_webview2_bridge`, `test_error_system`, `test_integration_error_system`, `test_result_reporter`, `test_joy_hotkey_manager`, `test_joystick`, `test_key_recorder`, `test_key_validator`, `test_key_test_integration`, `test_ahk_executor/*`, `suites/*`, `run_all_tests`, `run_tests`, `AutoHotUnit`, `run_tests.ps1`；归档于 `tests/archive/` |

#### AHK 已知架构妥协（Known Architecture Compromises）

以下妥协是在 AHK v2 无原生依赖注入（DI）容器的环境下，经过审慎评估后接受的务实决策。每个妥协都记录了原因和约束边界，以防止退化。

| # | 妥协 | 影响文件 | 说明 | 约束边界 |
|---|------|---------|------|---------|
| 1 | **DDD 层依赖违规** | `domain/mode_registry.ahk` → `infrastructure/error_system.ahk` | 领域层直接依赖基础设施层的 `ErrorSystem`。在严格 DDD 中领域层应通过接口使用日志服务，但 AHK v2 无 DI 容器，通过接口注入会导致过度复杂化。 | 仅允许 `domain/` 引用 `infrastructure/error_system.ahk` 的 `LogError` 方法。禁止领域层引用 `infrastructure/` 中的其他模块。此外，允许 `infrastructure/joy_hotkey_manager.ahk` 引用 `domain/joystick_input.ahk` 的纯工具函数（`JoystickInput` 类，无副作用、无状态），以消除代码重复（A1 修复：删除冗余的 `infrastructure/joystick_input_utils.ahk`，该文件曾为避免反向依赖而复制 `JoystickInput` 的全部方法）。同样允许 `infrastructure/joy_sender.ahk` 反向 `#Include "../domain/interfaces.ahk"`（`JoySender` 实现 `IJoySender` 抽象接口，依赖倒置）；该引用仅用于类型继承、无副作用无状态，仅限「domain 定义接口 / joy_sender 实现接口」这一边界。此外，允许 `infrastructure/config_validator.ahk` 引用 `domain/joystick_input.ahk` 的 `JoystickInput.IsJoystickKey()` 纯静态方法（无副作用、无状态），用于摇杆按键名的合法性校验（`config_validator.ahk:167`）。 |
| 2 | **`BackupCore` 隐式依赖** | `application/config_service.ahk` → `infrastructure/backup_core.ahk` | 应用层通过全局 `BackupCore` 类名隐式引用基础设施层模块。应通过显式 `#Include` 或接口抽象化。 | `ConfigService` 内部仅通过 `BackupCore.CreateBackup()` 静态方法调用，不直接访问其内部状态。未来若引入 DI 机制应重构为接口注入。 |

#### AHK 内部工具函数迁移

以下函数已从各模块迁移至 `infrastructure/utils.ahk`（v3.1+），作为跨层共享的统一入口：

| 函数 | 原位置 | 迁移至 | 说明 |
|------|--------|--------|------|
| `_GetProp(obj, key, default)` | — | `infrastructure/utils.ahk` | Map/Object 统一属性访问 |
| `_GetField(obj, key, default)` | `webview2_manager.ahk` | `infrastructure/utils.ahk` | 含 JSON 字符串解析的属性访问 |

### Rust/Tauri 架构（5-Crate Workspace）

```
asd-tauri/
├── Cargo.toml              (workspace root)
├── crates/
│   ├── asd-domain/         (纯逻辑 crate — 领域模型 + trait + 验证)
│   │   ├── src/config.rs   (Config, GroupConfig, ModeData, WatchdogStateEnum)
│   │   ├── src/models.rs   (SkillGroup)
│   │   ├── src/validator.rs (ConfigValidator)
│   │   └── src/traits.rs   (IpcSender, EventEmitter, ProcessWatcher)
│   ├── asd-ipc-protocol/   (纯逻辑 crate — IPC 协议定义)
│   │   ├── src/command.rs  (IpcCommand, 13 variants)
│   │   ├── src/message.rs  (IpcMessage + constructors)
│   │   ├── src/error.rs    (IpcError)
│   │   └── src/hotkey_merger.rs (HotkeyMerger)
│   ├── asd-application/    (应用逻辑 crate — 状态 + 配置仓库 + 服务层)
│   │   ├── src/state.rs     (AppState, trait objects)
│   │   ├── src/config_repository.rs (ConfigRepository, file I/O)
│   │   ├── src/backup_service.rs    (BackupService)
│   │   ├── src/group_service.rs     (GroupService)
│   │   ├── src/recording_service.rs (RecordingService)
│   │   ├── src/time_format.rs       (时间格式化)
│   │   ├── src/error.rs     (AppError)
│   │   └── tests/           (backup/group/recording/cross_crate/e2e_dataflow/concurrency/integration)
│   └── asd-test-harness/   (测试支持 crate — 测试固件 + mock 工具)
│       └── src/lib.rs      (TestHarness, 测试辅助)
└── src-tauri/              (表现层 + 基础设施 — Tauri 主 crate)
    ├── src/lib.rs           (34 Tauri commands)
    ├── src/bridge.rs        (IpcBridge, TauriEventBridge, WatchdogBridge)
    ├── src/infrastructure/  (IpcManager, ProcessWatchdog, Logging, Shutdown)
    ├── src/commands/        (config_cmd, group_cmd, hotkey_cmd, recording_cmd, system_cmd)
    ├── src/tests/           (ipc_tests, config_compat_tests, bridge_tests, command_contract_tests, watchdog_integration_tests, mod)
    ├── ahk_executor/        (AHK 子进程执行器)
    ├── benches/             (criterion 基准测试)
    └── fuzz/                (cargo-fuzz 模糊测试)
```

#### Crate 依赖关系

```
asd-domain ──→ asd-ipc-protocol
asd-application ──→ asd-domain ──→ asd-ipc-protocol
asd-test-harness ──→ asd-application ──→ asd-domain ──→ asd-ipc-protocol
asd-tauri (src-tauri) ──→ asd-application ──→ asd-domain ──→ asd-ipc-protocol
                   └──→ asd-test-harness（dev-dependency，仅测试用）
```

#### 关键设计决策

| # | 决策 | 说明 |
|---|------|------|
| 1 | **Trait 抽象解耦** | IpcSender/EventEmitter/ProcessWatcher trait 在 asd-domain 中定义，在 src-tauri/bridge.rs 中实现。纯逻辑 crate 不依赖 Tauri 或 tokio。 |
| 2 | **I/O 泄漏修复** | Config 的 I/O 方法从 domain 层移到 application 层的 ConfigRepository，确保 domain crate 无文件 I/O。 |
| 3 | **Miri 兼容** | asd-domain, asd-ipc-protocol, asd-application 可通过 Miri 验证（0 UB），不含 unsafe 代码。 |
| 4 | **AHK 子进程隔离** | AHK 执行器（asd_executor.exe）作为子进程由 Rust 主进程管理，通过 interprocess named pipe 通信。 |
| 5 | **测试覆盖** | 测试数量与分布的**唯一权威为 `asd-tauri/docs/test-map.md`**（Rust / AHK 完整套件 / AHK 执行器 / E2E / criterion bench / fuzz target 全覆盖）。本文档**只写指针、不复制数字**——数字一旦复制就会过期（此处曾长期滞留已失效的旧值）。纯逻辑 crate 覆盖率 96.57%（2026-09-12 实测）。 |
| 6 | **进程清理与 panic hook 补偿** | watchdog.rs 的 `cleanup_stale_executor_processes` 仅清理项目专用的 `asd_executor.exe`，**绝不**清理 `AutoHotkey64.exe` 等通用进程名，避免误杀用户其他 AHK 脚本（R1 安全约束）。`build_panic_hook_closure` 纯函数将 panic hook 的构建逻辑与全局 `set_hook` 注册分离，使测试可验证 hook 行为（先 cleanup 后 original_hook）而不污染全局 `Once` 状态（R3 可测试性）。JobObject 失败时，`register_panic_hook` 作为补偿机制确保主进程崩溃时子进程被清理（I36）。 |

#### Rust/Tauri 已知架构妥协

| # | 妥协 | 影响文件 | 说明 | 约束边界 |
|---|------|---------|------|---------|
| 1 | **asd-domain 依赖 asd-ipc-protocol** | `crates/asd-domain/Cargo.toml`、`crates/asd-domain/src/traits.rs` | 领域层 crate 依赖 IPC 协议 crate 的 IpcCommand/IpcMessage 类型。严格 DDD 中领域层不应知道通信协议。 | asd-domain 仅使用 IpcCommand/IpcMessage 的数据结构（serde 序列化），不包含任何 IPC 传输逻辑。仅允许 `src/traits.rs` 引用 IpcCommand/IpcMessage 类型，禁止领域层引用 asd-ipc-protocol 的其他类型或直接构造 IPC 命令。trait 定义（IpcSender）的参数类型引用 IpcCommand 是合理的抽象；未来应将其迁移至应用层，领域层定义纯领域命令接口。 |
| 2 | **bridge.rs 中 blocking_lock** | `src-tauri/src/bridge.rs` | IpcBridge 和 WatchdogBridge 使用 `blocking_lock()` 实现 trait 的同步方法。 | 仅在已知不会死锁的短临界区使用；未来可考虑将 trait 改为 async。 |

## Subdirectories

### AHK v2 部分

| Directory        | Purpose                                |
| ---------------- | -------------------------------------- |
| `docs/`          | 技术文档（架构/开发指南/部署/API参考）              |
| `logs/`          | 日志文件（`app.log` / `debug.log`）         |
| `backups/`       | 配置备份文件                                |
| `config_backup/` | 配置备份目录（遗留）                            |
| `domain/`        | AHK 领域层模块                             |
| `infrastructure/`| AHK 基础设施层模块                           |
| `application/`   | AHK 应用层模块                             |
| `presentation/`  | AHK 表现层模块                             |
| `tests/`         | AHK 测试套件                              |
| `lib/`           | AHK 第三方库（ahk2_lib）                    |

### Rust/Tauri 部分

| Directory | Purpose |
|-----------|---------|
| `asd-tauri/crates/asd-domain/` | 纯逻辑 crate — 领域模型、验证、trait 定义 |
| `asd-tauri/crates/asd-ipc-protocol/` | 纯逻辑 crate — IPC 协议（命令、消息、错误） |
| `asd-tauri/crates/asd-application/` | 应用逻辑 crate — 调度器、状态、配置仓库 |
| `asd-tauri/src-tauri/` | Tauri 主 crate — 表现层 + 基础设施 |
| `asd-tauri/src-tauri/src/commands/` | Tauri 命令处理器（5 个模块） |
| `asd-tauri/src-tauri/src/infrastructure/` | 基础设施（IPC、Watchdog、日志） |
| `asd-tauri/src-tauri/src/tests/` | 主 crate 集成测试 |
| `asd-tauri/src-tauri/ahk_executor/` | AHK 子进程执行器脚本 |
| `asd-tauri/src-tauri/benches/` | Criterion 基准测试 |
| `asd-tauri/src-tauri/fuzz/` | cargo-fuzz 模糊测试目标 |
| `asd-tauri/src/` | Vite 前端源码（JS/CSS） |

## For AI Agents

### Working In This Directory

#### Git 提交规范

- **⚠️ 强制：所有 git commit 必须遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范**
- **格式**：`<type>(<scope>): <描述>`，详见 `docs/commit-convention.md`
- **type**（全小写）：feat / fix / docs / style / refactor / test / chore / perf / ci / build
- **scope**（全小写，可选）：asd-domain / asd-ipc-protocol / asd-application / asd-tauri / asd-test-harness / ahk / test / ci / docs / config
- **描述语言**：中文优先，技术术语保留英文；首字母不大写，结尾不加句号
- **示例**：
  - `feat(asd-ipc-protocol): 新增 HotkeyMerger 热键合并器`
  - `fix(asd-test-harness): 修复 unique_pipe_name 并发碰撞`
  - `docs(test): 新建 TESTING.md 测试管理文档`
- **BREAKING CHANGE**：在 type 后加 `!`（如 `feat(asd-ipc-protocol)!: 重构 IpcCommand 枚举`）或在 Footer 标注
- **禁止**：无 type 的提交（如 `update files`）、英文描述（如 `Add new feature`）、描述以句号结尾
- 提交时使用 `git commit`（不带 -m）会自动加载 `.gitmessage` 模板提示

#### AHK v2 规则

- **⚠️ 强制：所有 .ahk 文件顶部必须包含以下警告/错误接管指令（在 `#Requires` 之后、任何代码之前）：**
  ```autohotkey
  #Requires AutoHotkey v2.0
  #ErrorStdOut "UTF-8"          ; 加载时错误重定向到标准输出，不弹窗
  #Warn VarUnset, OutputDebug   ; 未赋值变量警告 → OutputDebug，不弹窗
  #Warn Unreachable, OutputDebug ; 不可达代码警告 → OutputDebug，不弹窗
  #Warn LocalSameAsGlobal, OutputDebug ; 局部与全局同名警告 → 不弹窗
  ```
- **⚠️ 强制：主入口文件（main.ahk / asd.ahk）必须设置 `OnError` 全局回调接管运行时错误：**
  ```autohotkey
  OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))
  ; 返回 true 阻止默认错误对话框弹出
  ```
- **⚠️ 强制：以上规则适用于项目中所有 .ahk 文件，包括 domain/、infrastructure/、application/、presentation/、tests/ 目录下的所有文件，无例外**
- 所有 GUI 控件位置参数必须用双引号包围
- Button 控件使用 `.Text` 属性设置文本
- 日志级别：ERROR/WARNING/DEBUG（不使用 INFO）
- 配置更改后调用 `ConfigService.SaveConfig()` 持久化
- 周期性键必须使用独立触发时间，不能用 `Mod(A_TickCount, interval)`
- 定时器引用必须存储在 `_timers` Map 中，确保能正确停止
- 热路径日志（Execute\* 方法）会自动限速，每秒最多记录一次
- 模块文件顶部必须包含 `#Requires AutoHotkey v2.0`
- 主脚本使用 `#Include` 引入模块

#### Rust/Tauri 规则

- **⚠️ 强制：纯逻辑 crate（asd-domain, asd-ipc-protocol, asd-application）禁止引入以下依赖：**
  - `tokio`（异步运行时）
  - `tauri`（GUI 框架）
  - `interprocess`（IPC 传输）
  - `windows`（Win32 API）
  - 任何涉及文件 I/O 的 crate（`std::fs` 除外，仅在 asd-application 的 ConfigRepository 中使用）
- **测试豁免**：`#[cfg(test)]` 单元测试模块与 `tests/` 集成测试目录允许直接使用 `std::fs` 构造/清理测试固件（临时目录、临时配置文件），以消解与「无文件 I/O」规则的张力；该豁免仅作用于测试代码，不改变生产代码的运行行为。
- **⚠️ 强制：新增 trait 方法必须提供默认实现**，避免破坏现有实现者
- **⚠️ 强制：src-tauri 中的 Tauri command 函数必须使用 `#[tauri::command]` 宏标注**
- **⚠️ 强制：IPC 通信必须通过 `IpcSender` trait**，禁止直接调用 `IpcManager`。例外（仅限表现层/基础设施接线边界，M31 同款）：`src-tauri/src/lib.rs` 的 IPC 生命周期函数——心跳 `spawn_heartbeat_ping`、监听/接受循环 `spawn_ipc_accept_loop`、关机序列 `perform_graceful_shutdown`/`spawn_ipc_listener`、回调接线 `setup_ipc_callbacks`——可直接操作 `IpcManager`/`IpcManagerArc` 完成连接建立、心跳、监听与关机，因此类逻辑本身即 IPC 基础设施的接线与生命周期管理；该例外不扩展到任何应用层命令发送（命令仍必须经 `IpcSender` trait）。
- 使用 `thiserror` 定义错误类型，禁止手动实现 `std::error::Error`
- 使用 `tracing` 而非 `log` 进行日志记录
- 测试必须通过 `cargo test` 运行
- 新增 IpcCommand variant 必须同步更新 `asd-ipc-protocol/src/command.rs` 和对应的 AHK 执行器处理逻辑

### Testing Requirements

#### AHK v2 测试

- **AHK v2 路径**: `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` (64位) 或 `D:\Program Files\AutoHotkey\v2\AutoHotkey.exe`
- 运行语法检查: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk`
- 启动脚本: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" asd.ahk`
- 运行测试套件: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
- 查看调试日志（实时）: `Get-Content logs\debug.log -Tail 20 -Wait`
- 查看应用日志: `Get-Content logs\app.log -Tail 10`
- 过滤错误日志: `Select-String -Path logs\app.log -Pattern '"level":"ERROR"'`
- **tests/ 目录结构**（v4.1 整理）：
  - 根目录保留 14 个核心文件 = 10 个 `test_*.ahk`（`test_error_system`/`test_integration_error_system`/`test_joy_hotkey_manager`/`test_joy_hotkey_manager_ahu`/`test_joystick`/`test_key_recorder`/`test_key_test_integration`/`test_key_validator`/`test_result_reporter`/`test_webview2_bridge`）+ 4 个框架/入口文件（`AutoHotUnit.ahk`、`run_all_tests.ahk`、`run_tests.ahk`、`run_tests.ps1`）
  - `tests/archive/`：归档了 41 个调试/原型/旧版本/废弃测试文件（HTML 原型 `test_html_*`、WebView2 原型 `test_wv2_*`/`test_webview2_proto`、编号测试 `test_*_c*`、full 旧版本 `test_*_full`、bug 复现脚本 `run_bug_repro`/`test_bug_reproduction`、基准 `benchmark_hotpath`、以及 2026-09-12 归档的 6 个上一代断言式测试 `test_domain`/`test_application`/`test_infrastructure`/`test_presentation`/`test_boundary`/`test_error_captor` 等），不参与 `run_all_tests.ahk` 运行
  - `tests/suites/`：内联测试套件（`core_suites`/`base_suites`/`fix_round_suites`/`layering_security_suites`），由 `run_all_tests.ahk` 加载
  - `tests/test_ahk_executor/`：AHK 执行器测试（套件数见 `asd-tauri/docs/test-map.md`）
  - `tests/fixtures/`：AHK v2 测试固件目录（v4.1 新增），存放可复用的测试数据文件（如 `sample_config.json` 标准配置样本覆盖 7 种模式、`import_test_data.json` 导入测试场景数据）
  - 删除了 25 个 `.txt`/`.log` 调试输出文件（stderr/stdout 重定向、`bug_repro_results`、`debug_output`、`test_results.log` 等）

#### AHK v2 测试固件管理

- 所有 AHK v2 测试固件存放于 `tests/fixtures/`（如 `tests/fixtures/sample_config.json`）
- 测试中通过 `FileRead(A_ScriptDir "\fixtures\<filename>", "UTF-8")` 加载固件，再用 `JSONParser.Parse()` 解析
- 禁止硬编码可复用的测试数据，应提取为独立 fixture 文件
- 固件命名：配置样本 `<场景>_config.json`、测试数据 `<场景>_data.json`
- 新增固件须在本节登记说明
- 与 Rust/Tauri 的 `asd-tauri/tests/fixtures/` 保持对等的管理规范

#### AHK v2 测试模式统一规范

**强制规范：新增测试必须使用 AutoHotUnitSuite 模式。**

AHK v2 测试历史上存在 4 种不统一的测试模式，统一规范如下：

| 模式 | 状态 | 使用文件 | 迁移计划 |
|------|------|---------|---------|
| AutoHotUnitSuite | ✅ 推荐模式 | `run_all_tests.ahk`、`run_tests.ahk`、`test_joy_hotkey_manager_ahu.ahk`、`test_ahk_executor/*.ahk`（5 文件） | 新测试必须使用此模式；套件与用例数见 `asd-tauri/docs/test-map.md` |
| TestReporter 场景式 | 📦 已归档（2026-09-12） | 原 `test_application.ahk`、`test_domain.ahk`、`test_infrastructure.ahk`、`test_presentation.ahk`、`test_boundary.ahk`、`test_error_captor.ahk`（共 6 文件）已移入 `tests/archive/`——它们不含 `Test_` 方法，从未被 `run_all_tests.ahk` 加载。仍保留于根目录的：`test_integration_error_system.ahk`、`test_key_recorder.ahk`、`test_key_test_integration.ahk`、`test_key_validator.ahk`、`test_result_reporter.ahk`、`test_webview2_bridge.ahk` | 保留者后续逐步迁移 |
| JoyTestRunner 自定义 | ⚠️ 保留（已稳定） | `test_joystick.ahk` | 后续迁移，当前保留 |
| 函数式全局变量 | ⚠️ 保留（已稳定） | `test_error_system.ahk` | 后续迁移，当前保留 |

**AutoHotUnitSuite 标准模板要求：**
- 测试类必须 `extends AutoHotUnitSuite`
- 测试方法以 `Test_` 前缀命名
- 使用 `this.assert.isTrue()` / `this.assert.isFalse()` / `this.assert.fail()` 断言
- 通过 `run_all_tests.ahk` 的 `testManager.RegisterSuite()` 注册运行
- 例外：测试 ErrorSystem 自身的测试文件可保留 `OnError(ErrorSystem_HandleError, -1)` 模式（见 `test_error_system.ahk` 注释说明）

**迁移优先级：**
1. 新测试：必须使用 AutoHotUnitSuite
2. 函数式全局变量模式（`test_error_system.ahk`）：优先级低，因 OnError 特殊性，迁移需保留 ErrorSystem 回调
3. TestReporter 场景式模式（12 文件）：逐步迁移，每个文件独立评估风险
4. JoyTestRunner 模式（`test_joystick.ahk`）：最后迁移，需完全重写

#### Rust/Tauri 测试

```bash
# 编译
cd asd-tauri && cargo build

# 语法检查
cd asd-tauri/src-tauri && cargo check

# 纯逻辑 crate 测试（不需要 feature flag）
cd asd-tauri && cargo test -p asd-domain
cd asd-tauri && cargo test -p asd-ipc-protocol
cd asd-tauri && cargo test -p asd-application

# 主 crate 测试
cd asd-tauri/src-tauri && cargo test --lib

# 全 workspace 测试
cd asd-tauri && cargo test --workspace

# Miri 验证（纯逻辑 crate，0 UB）
cd asd-tauri && cargo +nightly miri test -p asd-domain
cd asd-tauri && cargo +nightly miri test -p asd-ipc-protocol
cd asd-tauri && cargo +nightly miri test -p asd-application -- --skip config_repository --skip save_config --skip load_from

# 基准测试
cd asd-tauri/src-tauri && cargo bench

# 覆盖率（统一使用 cargo-llvm-cov，详见 .codecov.yml）
cd asd-tauri && cargo llvm-cov --workspace --html --output-dir coverage/
# 或生成 lcov.info 用于上传 Codecov：
cd asd-tauri && cargo llvm-cov --workspace --lcov --output-path lcov.info

# 模糊测试
cd asd-tauri/src-tauri/fuzz && cargo +nightly fuzz run fuzz_config_deserialize
```

#### AHK 执行器测试

- 测试目录：`tests/test_ahk_executor/`（位于项目根目录，非 `asd-tauri/tests/`）
- 测试框架：AutoHotUnit（`tests/AutoHotUnit.ahk`，提供 `AutoHotUnitSuite` 基类）
- 运行命令：`& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
- 测试文件：
  - `test_executor.ahk`：executor.ahk CommandDispatcher 命令解析与辅助方法
  - `test_ipc_client.ahk`：ipc_client.ahk MiniJson 解析/序列化、IpcClient 状态与去重
  - `test_hotkey_hook.ahk`：hotkey_hook.ahk 热键规范化、注册/注销、回调
  - `test_sender.ahk`：sender.ahk 按键发送、模式切换、紧急释放、QPC 精确定刻
  - `test_joystick.ahk`：joystick.ahk 摇杆输入读取、VJoy 映射、模式启动
- 各文件套件数、用例总数与统计口径：**见 `asd-tauri/docs/test-map.md`（唯一权威）**。
  本文档不再复制这些数字 —— 此前此处逐文件记录并汇总出的结果与权威值不符，
  正是「复制数字必然失修」的实例。
- 强制规范：所有 AHK 测试文件必须包含 `#ErrorStdOut "UTF-8"` + `#Warn VarUnset, OutputDebug` + `#Warn Unreachable, OutputDebug` + `OnError` 回调（详见「错误与警告接管机制」节）
- 详细指南：参见 `asd-tauri/TESTING.md` 第 1.6 节

#### E2E 测试

- **E2E 测试目录**：`asd-tauri/e2e/`（独立 Node.js 项目，使用 tauri-driver + WebDriverIO）
- **测试框架**：WebDriverIO 8.x + Mocha BDD + chai 断言
- **测试范围**：9 个 suite，53 个用例
  - `smoke.spec.js`（1）：应用启动与关闭冒烟测试
  - `config_cmd.spec.js`（12）：11 个 config_cmd 命令
  - `group_cmd.spec.js`（8）：8 个 group_cmd 命令
  - `hotkey_cmd.spec.js`（3）：2 个 hotkey_cmd 命令 + 热键触发
  - `recording_cmd.spec.js`（5）：4 个 recording_cmd 命令 + 状态机
  - `system_cmd.spec.js`（5）：5 个 system_cmd 命令
  - `modes.spec.js`（7）：7 种执行模式（E2E 覆盖；系统能力共 10 种，`joystick_*` 三种未纳入 E2E）
  - `ipc.spec.js`（7）：Rust↔AHK IPC 通信
  - `key_send.spec.js`（5）：AHK 执行器按键验证
- **前置条件**：
  1. 安装 tauri-driver：`cargo install tauri-driver --locked`（tauri-driver 不在 npm registry）
  2. 构建应用：`cd asd-tauri && cargo build --release`
  3. 安装 AHK v2：`D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`
- **运行命令**：
  ```bash
  cd asd-tauri/e2e
  npm install
  npm test
  ```
- **测试报告**：`asd-tauri/e2e/docs/e2e-test-report.md`（运行后生成）
- **已知问题清单**：`asd-tauri/e2e/docs/e2e-known-issues.md`
- **强制规范**：
  - 所有 E2E 测试文件使用 ESM 语法（`import/export`）
  - 测试用例编号格式：`E2E-<SUITE>-NNN`（如 `E2E-CFG-001`）
  - 失败用例必须调用 `appendKnownIssue` 记录到 `asd-tauri/e2e/docs/e2e-known-issues.md`
  - binary 缺失时所有测试 skip（不 fail）
  - 不直接修改用户真实 `config.json`，使用 `backupUserConfig`/`restoreUserConfig`

#### 测试结果分析

- JUnit XML 生成：`cargo test -- --format junit -Z unstable-options`（nightly）或 `cargo-junit-report`（stable 回退方案）
- 分析脚本：`./scripts/analyze-tests.ps1`（解析 JUnit XML，输出通过率、失败清单、耗时 Top10、按 crate 分组统计表格）
- 一键流程：`./scripts/run-tests.ps1 -Coverage -Analyze`（运行测试 + 生成覆盖率 + 分析结果）
- 输出目录：`asd-tauri/test-results/`（JUnit XML）与 `asd-tauri/coverage/`（HTML 覆盖率报告）
- CI artifact：JUnit XML 在 GitHub Actions 中保留 90 天

#### 测试数据管理

- 所有测试固件存放于 `asd-tauri/tests/fixtures/`（如 `tests/fixtures/configs/tests_config.json`）
- 使用 `include_str!` 引用相对路径，禁止硬编码绝对路径
- 新增测试固件须在 `asd-tauri/docs/test-map.md` 的「测试固件」章节中登记
- 固件命名：配置样本 `<场景>_config.json`、输入数据 `<场景>_input.<ext>`、期望输出 `<场景>_expected.<ext>`

### 错误与警告接管机制（⚠️ 强制，无例外）

#### 错误分类

| 错误类型 | 触发时机 | 接管方式 | 退出码 |
|---------|---------|---------|-------|
| 加载时语法错误 | 脚本加载/解析阶段 | `#ErrorStdOut "UTF-8"` → stderr | 2 |
| 加载时警告（未赋值变量等） | 脚本加载阶段 | `#Warn VarUnset, OutputDebug` → OutputDebug | 0 |
| 运行时错误 | 脚本执行阶段 | `OnError` 回调 → 日志 | 0（回调返回 true 时） |
| 运行时警告 | 脚本执行阶段 | `#Warn Unreachable, OutputDebug` → OutputDebug | 0 |

#### 所有 .ahk 文件必须包含的接管指令

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"          ; 加载时语法错误 → stderr，不弹窗
#Warn VarUnset, OutputDebug   ; 未赋值变量警告 → OutputDebug，不弹窗
#Warn Unreachable, OutputDebug ; 不可达代码警告 → OutputDebug，不弹窗
#Warn LocalSameAsGlobal, Off  ; 局部与全局同名警告 → 关闭
```

#### 主入口文件额外必须包含

```autohotkey
OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))
; 返回 true 阻止默认错误对话框弹出
```

> **例外：MemoryError 等不可恢复错误**
> `ErrorSystem.HandleError` 对 `MemoryError` 返回 `0`（而非 `true`），允许系统显示默认错误对话框。这是有意设计：MemoryError 表示内存耗尽，脚本无法继续可靠执行，让系统感知致命错误比静默吞掉更安全。参见 `infrastructure/error_system.ahk` 第 82-85 行。

#### 测试文件额外必须包含

```autohotkey
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message "`n", "*"), true))
; 测试文件中用 FileAppend 输出到 stdout，确保错误可被捕获
```

#### 测试文件前置检查流程（⚠️ 执行任何测试前必须完成）

**第一步：语法检查（检测加载时错误）**

```powershell
# 方法1：使用 /ErrorStdOut 命令行参数 + stderr 重定向
$proc = Start-Process -FilePath "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" `
    -ArgumentList "/ErrorStdOut","test_file.ahk" `
    -WorkingDirectory "D:\1demo\AutoHotkeydemo" `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardError "D:\1demo\AutoHotkeydemo\test_stderr.txt"
Write-Host "Exit code: $($proc.ExitCode)"
# 退出码 0 = 无语法错误，退出码 2 = 存在语法错误
Get-Content "test_stderr.txt"  # 查看具体错误信息
```

```powershell
# 方法2：使用管道重定向（适用于简单场景）
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut test_file.ahk 2>&1 | Select-Object -First 10
# 注意：/ErrorStdOut 将错误输出到 stderr，需要 2>&1 重定向到 stdout
```

**第二步：验证接管指令存在**

```powershell
# 检查文件是否包含必要的接管指令
$content = Get-Content "test_file.ahk" -Raw
if ($content -notmatch '#ErrorStdOut') { Write-Host "ERROR: 缺少 #ErrorStdOut 指令" }
if ($content -notmatch '#Warn VarUnset') { Write-Host "ERROR: 缺少 #Warn VarUnset 指令" }
if ($content -notmatch '#Warn Unreachable') { Write-Host "ERROR: 缺少 #Warn Unreachable 指令" }
if ($content -notmatch 'OnError') { Write-Host "ERROR: 缺少 OnError 回调" }
```

**第三步：运行时错误验证**

```powershell
# 启动测试并检查退出码和输出
$proc = Start-Process -FilePath "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" `
    -ArgumentList "test_file.ahk" `
    -WorkingDirectory "D:\1demo\AutoHotkeydemo" `
    -NoNewWindow -Wait -PassThru
Write-Host "Exit code: $($proc.ExitCode)"
# 退出码 0 = 正常退出，退出码 2 = 加载时错误
# 运行时错误由 OnError 回调处理，退出码仍为 0
```

#### 退出码含义

| 退出码 | 含义 | 说明 |
|-------|------|------|
| 0 | 正常退出 | 脚本执行完毕或 `ExitApp` |
| 2 | 加载时错误 | 语法错误导致脚本无法启动 |
| 1 | 其他错误 | 一般性错误 |

#### ⚠️ 关键语法陷阱：箭头函数不支持块体

**AHK v2 的箭头函数 `=>` 只支持表达式体，不支持块体 `{ }`！**

```autohotkey
; ❌ 错误：箭头函数使用块体 — 会导致 "Missing propertyname: in object literal" 语法错误
someObj.then((result) => {
    DoSomething(result)
    DoAnotherThing()
})

; ✅ 正确：箭头函数使用表达式体（单行表达式）
someObj.then((result) => DoSomething(result))

; ✅ 正确：多语句用逗号表达式
someObj.then((result) => (DoSomething(result), DoAnotherThing()))

; ✅ 正确：使用闭包函数代替箭头函数块体
someObj.then(Func("MyCallback"))
MyCallback(result) {
    DoSomething(result)
    DoAnotherThing()
}
```

**特别说明：`.then()` 回调中的块体是重灾区！**

WebView2 的 `ExecuteScript().then()` 和 Promise 的 `.then()` 经常需要多行回调，
必须使用逗号表达式或闭包函数，**绝对不能**使用 `=> { }` 块体语法。

#### ⚠️ 关键语法陷阱：字符串拼接中的花括号

**AHK v2 在字符串拼接中，紧跟变量后的 `"..."` 会被解析为对象字面量的属性名！**

```autohotkey
; ❌ 错误：OB 后面的字符串被当作对象属性名
OB := "{"
CB := "}"
testJs := "try" OB "var x=1" CB "catch(e)" OB CB  ; 语法错误！

; ❌ 错误：Chr(123) 在拼接中同样触发对象字面量解析
testJs := "try" Chr(123) "var x=1" Chr(125)  ; 语法错误！

; ✅ 正确：使用 Format 函数
testJs := Format("try{1}var x=1{2}catch(e){1}{2}", "{", "}")

; ✅ 正确：使用单引号字符串（AHK v2 支持单引号字符串）
testJs := 'try{var x=1}catch(e){}'

; ✅ 正确：分步构建
testJs := "try"
testJs .= "{var x=1}"
testJs .= "catch(e){}"
```

#### 测试文件标准模板

```autohotkey
; =================================================================
; 测试模块名称 - 简要描述
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\infrastructure\error_system.ahk"
#Include "..\infrastructure\json_logger.ahk"
; ... 其他必要的 #Include ...

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试用例
; =================================================================

Test_SomeFeature() {
    try {
        ; 测试逻辑
        result := SomeModule.SomeMethod()
        if result {
            FileAppend("PASS: Test_SomeFeature`n", "*")
        } else {
            FileAppend("FAIL: Test_SomeFeature - unexpected result`n", "*")
        }
    } catch as e {
        FileAppend("ERROR: Test_SomeFeature - " e.Message "`n", "*")
    }
}

; =================================================================
; 执行测试
; =================================================================

FileAppend("=== Test Start ===`n", "*")
Test_SomeFeature()
FileAppend("=== Test End ===`n", "*")
```

#### 完整测试执行脚本（PowerShell）

```powershell
# test_runner.ps1 - 完整的 AHK 测试执行器
param([string]$TestFile)

$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
$workDir = "D:\1demo\AutoHotkeydemo"
$stderrFile = Join-Path $workDir "test_stderr.txt"

# 第1步：验证文件存在
if (-not (Test-Path $TestFile)) {
    Write-Host "ERROR: Test file not found: $TestFile"
    exit 1
}

# 第2步：验证接管指令
$content = Get-Content $TestFile -Raw
$missing = @()
if ($content -notmatch '#ErrorStdOut') { $missing += "#ErrorStdOut" }
if ($content -notmatch '#Warn') { $missing += "#Warn" }
if ($content -notmatch 'OnError') { $missing += "OnError" }
if ($missing.Count -gt 0) {
    Write-Host "WARNING: Missing error handling directives: $($missing -join ', ')"
}

# 第3步：语法检查（加载时错误检测）
$proc = Start-Process -FilePath $ahkPath `
    -ArgumentList "/ErrorStdOut",$TestFile `
    -WorkingDirectory $workDir `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardError $stderrFile

if ($proc.ExitCode -eq 2) {
    Write-Host "SYNTAX ERROR detected (exit code 2):"
    Get-Content $stderrFile
    Remove-Item $stderrFile -ErrorAction SilentlyContinue
    exit 2
}
Remove-Item $stderrFile -ErrorAction SilentlyContinue

# 第4步：运行测试
$proc = Start-Process -FilePath $ahkPath `
    -ArgumentList $TestFile `
    -WorkingDirectory $workDir `
    -NoNewWindow -Wait -PassThru

Write-Host "Test exit code: $($proc.ExitCode)"
exit $proc.ExitCode
```

### Common Patterns

#### AHK v2 模式

- 文件结构使用分节注释：`; =================================================================`
- 类名使用 PascalCase，方法名使用 PascalCase，静态属性使用 camelCase
- 使用 `HasProp()` 和 `_GetProp()` 兼容 Map 和 Object 访问
- 周期性触发使用独立触发时间而非 `Mod()`
- 使用 `Map()` 和 `SetTimer()` 管理状态和定时器
- 错误处理使用 `try-catch` 并记录 JSON 日志
- 配置数据使用全局 Map 结构

#### Rust/Tauri 模式

- **Trait 抽象**: 在 domain crate 定义 trait，在 infrastructure 层实现
  ```rust
  // asd-domain/src/traits.rs — 定义
  pub trait IpcSender: Send + Sync {
      fn send_command(&self, cmd: IpcCommand) -> Result<u64, String>;
  }

  // src-tauri/src/bridge.rs — 实现
  impl IpcSender for IpcBridge {
      fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> { ... }
  }
  ```
- **错误类型**: 使用 `thiserror` 派生宏
  ```rust
  #[derive(Debug, thiserror::Error)]
  pub enum AppError {
      #[error("配置验证失败: {0}")]
      Validation(String),
      #[error("IPC 通信错误: {0}")]
      Ipc(String),
  }
  ```
- **状态管理**: 使用 `Arc<AppState>` 共享状态，trait objects 实现依赖反转
  ```rust
  pub struct AppState {
      config_state: RwLock<ConfigState>,
      ipc_sender: Arc<dyn IpcSender>,
      pub(crate) active_hotkeys: RwLock<HashMap<String, String>>,
      pub emergency_mode: AtomicBool,
      pub hold_mode_enabled: AtomicBool,
      pub recording_mode: RwLock<Option<String>>,
      pub validation_in_progress: AtomicBool,
      pub watchdog_state: RwLock<WatchdogState>,
      watchdog: Arc<dyn ProcessWatcher>,
      event_emitter: Arc<dyn EventEmitter>,
      config_path: RwLock<Option<PathBuf>>,
  }
  ```
- **Tauri Command**: 使用 `#[tauri::command]` 宏，返回 `Result<T, AppError>`
  ```rust
  #[tauri::command]
  async fn get_config(state: State<'_, Arc<AppState>>) -> Result<Config, AppError> {
      state.config_repo.load_config()
  }
  ```
- **IPC 通信**: Rust 主进程 → interprocess named pipe → AHK 子进程
  ```rust
  // 发送命令
  ipc_sender.send_command(IpcCommand::ToggleGroup {
      group_id: "1".to_string(),
      active: true,
      mode: None,
      key_press_duration: None,
      hold_keys: None,
      hold_mode: None,
      mode_data: None,
  })?;
  // 接收消息
  while let Some(msg) = rx.recv().await { ... }
  ```
- **日志**: 使用 `tracing` 框架
  ```rust
  tracing::info!("收到热键事件: {hotkey}");
  tracing::error!("优雅关机失败: {e}");
  tracing::debug!("收到心跳");
  ```
- **测试**: 纯逻辑 crate 使用 `#[cfg(test)] mod tests`，集成测试放在 `tests/` 目录
  ```rust
  #[cfg(test)]
  mod tests {
      use super::*;
      #[test]
      fn test_config_validation() { ... }
  }
  ```

## Dependencies

### AHK v2 Internal

- 模块之间通过 `#Include` 引入
- `asd.ahk` 引入所有其他 .ahk 模块
- `infrastructure/json_parser.ahk` 提供 JSON 解析功能
- `infrastructure/json_serializer.ahk` 提供 JSON 序列化功能
- `presentation/webview2_manager.ahk` 提供 WebView2 GUI 和 AHK-JS Bridge
- `presentation/app_ui.html` WebView2 加载的 HTML 界面

### AHK v2 External

- WebView2 运行时（Edge Chromium 内核，Windows 10+ 内置）
- `lib/ahk2_lib/WebView2/` — thqby/ahk2_lib WebView2 封装库

### Rust/Tauri Internal (Workspace)

| Crate | 依赖 |
|-------|------|
| `asd-ipc-protocol` | serde, serde_json, thiserror |
| `asd-domain` | asd-ipc-protocol, serde, serde_json, indexmap, thiserror |
| `asd-application` | asd-domain, asd-ipc-protocol, serde, serde_json, indexmap, thiserror, tracing |
| `asd-tauri` (src-tauri) | asd-domain, asd-ipc-protocol, asd-application, tauri, tokio, interprocess, windows, tracing, clap, chrono, indexmap |

### Rust/Tauri External

| 依赖 | 版本 | 用途 |
|------|------|------|
| `tauri` | 2.11.2 | GUI 框架（tray-icon feature） |
| `tokio` | 1 (full) | 异步运行时 |
| `interprocess` | 2.4.2 (tokio) | Named pipe IPC 通信 |
| `windows` | 0.62.2 | Win32 API（进程管理、JobObjects） |
| `serde` / `serde_json` | 1.0 | 序列化/反序列化 |
| `thiserror` | 2.0 | 错误类型派生 |
| `tracing` / `tracing-subscriber` | 0.1 / 0.3 | 结构化日志 |
| `indexmap` | 2 (serde) | 有序 Map（保持配置顺序） |
| `clap` | 4 (derive) | 命令行参数解析 |
| `chrono` | 0.4 (serde) | 时间戳 |
| `criterion` | 0.5 | 基准测试（dev） |
| `tauri-plugin-opener` | 2 | 文件/URL 打开 |
| `tauri-plugin-global-shortcut` | 2.3.1 | 全局热键注册 |
| `tauri-plugin-dialog` | 2.7.1 | 系统对话框 |
| `tauri-plugin-fs` | 2.5.1 | 文件系统访问 |

### AHK-JS Bridge 通信架构（⚠️ 重要设计决策）

**核心问题：** `ExecuteScriptAsync` 使用 ICoreWebView2 原始接口，**不支持 Promise 等待**。所有 async/await 调用返回的 Promise 对象被 JSON 序列化为 `{}`。

**解决方案：** 使用 `WebMessage` 双向通信模式：

| 方向 | 方法 | 说明 |
|------|------|------|
| JS→AHK | `window.chrome.webview.postMessage(msg)` | JS 发送 JSON 消息到 AHK |
| AHK→JS | `wv.PostWebMessageAsJson(response)` | AHK 发送 JSON 响应到 JS |
| AHK 接收 | `wv.add_WebMessageReceived(handler)` | AHK 注册消息接收处理器 |
| JS 接收 | `window.chrome.webview.addEventListener("message", handler)` | JS 注册消息接收处理器 |

**通信流程：**

1. JS 调用 `ahkCall("GetGroupList")` → 生成 `{action, requestId}` → `postMessage()`
2. AHK `_OnWebMessageReceived` 解析 action → 调用对应 Bridge 方法 → `_SendResponse()`
3. AHK `_SendResponse()` 构造 `{requestId, result}` → `PostWebMessageAsJson()`
4. JS message handler 匹配 requestId → resolve Promise → 调用方收到结果

**⚠️ 禁止事项：**
- **禁止**通过 `ExecuteScriptAsync` 调用返回 Promise 的 JS 代码（结果必为 `{}`）
- **禁止**在 `ExecuteScriptAsync` 中使用 `async/await` IIFE
- **禁止**使用 `AddHostObjectToScript` 的 sync 代理（可能导致死锁）

**✅ 允许事项：**
- `ExecuteScriptAsync` 调用**同步** JS 函数（如 `updateDashboard(data)`）
- `InjectAhkComponent` 用于初始化 `window.ahk` 代理对象
- `PostWebMessageAsJson` / `postMessage` 用于所有需要返回值的通信

### Rust↔AHK IPC 通信架构（⚠️ 重要设计决策）

**核心问题：** Rust 主进程需要与 AHK 子进程（asd_executor.exe）双向通信，传递热键事件和按键指令。

**解决方案：** 使用 `interprocess` named pipe 双向通信：

| 方向 | 方法 | 说明 |
|------|------|------|
| Rust→AHK | `IpcSender::send_command()` | Rust 发送 IpcCommand 到 AHK |
| AHK→Rust | `IpcMessage` via pipe | AHK 发送心跳/热键/录制事件到 Rust |
| Rust 接收 | `IpcManager` tokio task | 异步监听 AHK 消息 |
| AHK 接收 | `ipc_client.ahk` | AHK 端 IPC 客户端 |

**通信流程：**

1. Rust 启动 AHK 子进程（`ProcessWatchdog` 管理）
2. AHK 通过 named pipe 连接到 Rust
3. Rust 发送 `IpcCommand::StartGroup` → AHK 开始执行按键序列
4. AHK 发送 `IpcMessage { type: "hotkey", keys: [...] }` → Rust 转发到前端
5. Rust 发送 `IpcCommand::StopGroup` → AHK 停止执行
6. AHK 发送心跳 → Rust 监控进程存活

**⚠️ 禁止事项：**
- **禁止**在 AHK 执行器中直接操作 Tauri 窗口
- **禁止**在 Rust 主线程中执行阻塞式 IPC 等待
- **禁止**跳过 `ProcessWatchdog` 直接启动/停止 AHK 进程

**✅ 允许事项：**
- 通过 `IpcSender` trait 发送命令（可 mock 测试）
- 通过 `EventEmitter` trait 发送前端事件
- 通过 `ProcessWatcher` trait 查询进程状态

<!-- MANUAL: 手动添加的注意事项请放在这里，重新生成时将予以保留。 -->

## 构建/运行命令

### AHK v2 运行脚本

```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" asd.ahk
```

### AHK v2 语法检查

```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk
```

### Rust/Tauri 构建

```bash
# 编译
cd asd-tauri && cargo build

# 发布构建
cd asd-tauri && cargo build --release

# 开发模式运行（Tauri + Vite HMR）
cd asd-tauri && npm run tauri dev
```

### Rust/Tauri 语法检查

```bash
cd asd-tauri/src-tauri && cargo check
```

### 调试命令

```bash
# 查看调试日志（实时）
Get-Content logs\debug.log -Tail 20 -Watch

# 查看应用日志
Get-Content logs\app.log -Tail 10

# 过滤错误日志
Select-String -Path logs\app.log -Pattern '"level":"ERROR"'

# 清空日志文件（测试前）
Clear-Content logs\app.log
Clear-Content logs\debug.log
```

## 代码风格指南

### AHK v2 文件结构

```autohotkey
; =================================================================
; 模块名称 - 简要描述
; =================================================================
#Requires AutoHotkey v2.0

; 第一部分: 常量/类定义
; 第二部分: 方法实现
; 第三部分: 初始化代码
```

### AHK v2 导入规范

```autohotkey
#Requires AutoHotkey v2.0  ; 模块文件顶部必须包含
#Include "json.ahk"        ; 主脚本使用 #Include 引入模块
```

### Rust 文件结构

```rust
// =================================================================
// 模块名称 - 简要描述
// =================================================================

use serde::{Deserialize, Serialize};

// 第一部分: 类型定义 + derive 宏
// 第二部分: impl 块
// 第三部分: #[cfg(test)] mod tests
```

### Rust 导入规范

```rust
// crate 内部模块
use crate::infrastructure::ipc::IpcManager;

// workspace crate
use asd_domain::traits::IpcSender;
use asd_ipc_protocol::IpcCommand;

// 标准库 + 第三方
use std::sync::Arc;
use tokio::sync::Mutex;
```

### 命名约定

#### AHK v2

| 类型   | 约定                    | 示例                                             |
| ---- | --------------------- | ---------------------------------------------- |
| 类名   | PascalCase            | `DebugLogger`, `SkillGroup`, `ConfigValidator` |
| 方法名  | PascalCase            | `Init()`, `Log()`, `Toggle()`                  |
| 静态属性 | camelCase             | `logFile`, `enabled`, `maxSize`                |
| 局部变量 | camelCase             | `currentChar`, `grpIdx`, `pressKeys`           |
| 全局变量 | PascalCase + `global` | `global GroupSettings`                         |
| 常量   | 全大写 + 下划线             | `JSONErrorType.FILE_READ_ERROR`                |
| 私有方法 | 下划线前缀                 | `_ExecutePeriodic()`, `_SetupMode()`           |

#### Rust

| 类型 | 约定 | 示例 |
|------|------|------|
| Crate 名 | snake_case | `asd-domain`, `asd-ipc-protocol` |
| 结构体/枚举 | PascalCase | `IpcCommand`, `AppState`, `AppError` |
| 函数/方法 | snake_case | `send_command()`, `load_config()` |
| 常量 | SCREAMING_SNAKE_CASE | `MAX_RESTART_COUNT` |
| Trait | PascalCase | `IpcSender`, `EventEmitter`, `ProcessWatcher` |
| 模块 | snake_case | `config_repository`, `hotkey_merger` |
| 生命周期 | 短小写字母 | `'a`, `'ctx` |

### AHK v2 类结构

```autohotkey
class ClassName {
    static property := ""
    static controls := Map()

    static MethodName() {
        ; 实现
    }

    static _PrivateMethod() {
        ; 私有方法
    }
}
```

### Rust 结构体 + Trait 实现

```rust
pub struct IpcBridge {
    outbound: IpcOutboundSender,
    ipc_manager: Arc<Mutex<Option<IpcManager>>>,
}

impl IpcSender for IpcBridge {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        // 实现
    }
}
```

### 错误处理

#### AHK v2

```autohotkey
; 使用 try-catch 处理可能失败的操作
try {
    content := FileRead(path, "UTF-8")
} catch as e {
    JSONLogger.Log(JSONError(JSONErrorType.FILE_READ_ERROR, e.Message, 0, "", path))
    return false
}

; 验证输入
if (this.config.hotkey = "") {
    MsgBox("请输入热键", "错误", "Icon!")
    return false
}
```

#### Rust

```rust
// 使用 thiserror 定义错误类型
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("配置验证失败: {0}")]
    Validation(String),
    #[error("IPC 通信错误: {0}")]
    Ipc(String),
}

// 使用 ? 操作符传播错误
fn load_config(path: &Path) -> Result<Config, AppError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| AppError::Io(e.to_string()))?;
    let config: Config = serde_json::from_str(&content)
        .map_err(|e| AppError::Validation(e.to_string()))?;
    Ok(config)
}
```

### 日志系统

#### AHK v2

```autohotkey
; 普通调试日志
DebugLogger.Log("_ExecuteHybrid: START groups.Length=" this.groups.Length)

; 热路径日志会自动限速（每秒最多一次）
; 受限速的方法: _ExecuteHybrid, _ExecuteEnhancedHybrid, _ExecutePeriodic, _ExecuteEnhancedPeriodic

; JSON 结构化日志
JSONLogger.LogError("Module", JSONErrorType.ERROR_xxx, "消息")
```

#### Rust

```rust
// 结构化日志（tracing）
tracing::info!("收到热键事件: {hotkey}");
tracing::warn!("进程重启次数: {count}");
tracing::error!("优雅关机失败: {e}");
tracing::debug!("收到心跳");

// 带字段的日志
tracing::info!(hotkey = %hotkey, group_id = id, "热键触发");
```

### Map vs Object 访问规范（重要！）

```autohotkey
; Map 类型 - 使用 obj.Has(key) 和 obj[key]
if (obj is Map) {
    if obj.Has("groups") {
        val := obj["groups"]
    }
}

; Object 类型 - 使用 HasProp(obj, key) 和 obj.%key%
if (IsObject(obj) && HasProp(obj, "groups")) {
    val := obj.groups
}

; 通用安全获取 - 使用 _GetField() / _GetProp()
val := _GetProp(obj, "type", "periodic")  ; 兼容 Map 和 Object
```

### 周期性触发时间规范（重要！）

```autohotkey
; 错误: 使用 Mod() 导致所有键共享时间基准，倍数间隔会同步触发
if (Mod(A_TickCount, interval) < 50) { ... }

; 正确: 每个键独立触发时间
for i, key in this.pressKeys {
    if (!this._lastTriggerTimes.Has(i)) {
        this._lastTriggerTimes[i] := A_TickCount
    }
    interval := (i <= this.intervals.Length) ? this.intervals[i] : 50
    if (A_TickCount - this._lastTriggerTimes[i] >= interval) {
        this._SendKey(key)
        this._lastTriggerTimes[i] := A_TickCount
    }
}

; 组内周期性键 - 使用 "grpIdx.keyIdx" 格式
triggerKey := grpIdx "." i
lastTime := this._groupTriggerTimes.Has(triggerKey) ? this._groupTriggerTimes[triggerKey] : A_TickCount
```

### 定时器管理规范（重要！）

```autohotkey
; 定时器引用必须存储，以便正确停止
class SkillManager {
    static _timers := Map()  ; 存储定时器引用

    static _StartGroupExecution(id) {
        ; ... 创建执行器 ...
        this._timers[id] := SetTimer(boundExecutor, -10)
    }

    static _StopGroupExecution(id) {
        if this._timers.Has(id) {
            SetTimer(this._timers[id], 0)  ; 取消定时器
            this._timers.Delete(id)
        }
    }
}
```

### 高精度定刻规范（重要！）

AHK/Windows 下**没有任何亚 15.625 ms 的唤醒手段**（本机实测，AutoHotkey v2）：

| 机制 | 实测 |
|------|------|
| `A_TickCount` 步进 | 中位 **15.52 ms** —— 无法度量 20 ms 以内的时延 |
| `SetTimer` / `Sleep` | 锁死 **15.625 ms 网格**；请求 1/5/10/15 ms 均得 ~15.6 ms，**请求 16 ms 反而得 ~31 ms**（跨格跳 2 格） |
| `timeBeginPeriod(1)` | 对 AHK **完全无效** |
| 一次性 `SetTimer(-1)` 自轮询 | 空闲时中位 **15.67 ms** |
| QPC 忙等 | 目标 20 ms → 中位 20.0017 ms（误差 0.0017 ms）—— **唯一精确手段** |

规范：

1. **需要 < 50 ms 精度的时间基准，一律用 `HighResClock`（`ahk_executor/high_res_clock.ahk`），
   禁止用 `A_TickCount`。** 后者 15.5 ms 的步进会让任何亚 20 ms 的断言失真。
2. **等待到点用 `HighResClock.SleepUntil(target)`，禁止 `Sleep` 收尾。**
   `Sleep` 只能落在 15.625 ms 网格上，末段误差不可控。
3. **定时器提前唤醒量必须 ≥ 一个网格周期 + 抖动余量**（`Sender.WAKE_LEAD_MS = 28`）。
   提前量太小会让定时器偶发迟到，进而压缩按键保持时长（实测提前量 18 时保持时长最短被压到 8 ms）。
4. **推进周期基准必须用「本次触发的计划时刻」，不能用发送完成后的当前时刻** ——
   后者已被保持时长推后，会让每轮都误判为「已落后」而白跳一个周期。
5. **滞后时禁止把基准重置为当前时刻**（旧 `sender.ahk` 的缺陷）：既丢相位又吞触发。
   应保相位单调推进，并把跳过的周期计入 `droppedTriggers` 使其可观测。
6. **同一时刻到期的多个键必须批量处理**（按计划时刻分桶 → 批量 Down → 统一等待 → 批量 Up）。
   逐键串行会让第二个键的等待立刻超时，保持时长塌到 ~0 ms（实测 0.022 ms）。
7. **序列类模式的首步基准必须在「首次执行」时确立**（`nextStepTime := 0` 作哨兵），
   不能初始化为启动调用时刻 —— 定时器首次回调可能晚到 100 ms 以上，会把首步判成过期而跳过。

> ⚠️ **精确定刻的代价：会连续占用 AHK 主线程。**
> `SleepUntil` 的让出段用的是 `DllCall("kernel32\Sleep", 0)`，**不会放行其它 AHK 定时器**；
> 等待期间 IPC 命令与热键都会被推迟。实测 interval=100 / kpd=15 下，扣除定时器网格后
> **最长连续占用 31.39 ms、占空比 29.2 %**（旧实现完全不阻塞）。
> 引入新的精确定刻点前，必须评估它对「停止技能组」等交互命令响应时延的影响。
> 实测数据与方法见 `docs/perf/key-latency-benchmark-2026-09-13.md`。

> ⚠️ **时延类断言的统计口径**：`P95` 在样本量小时会退化成「最大值」（`n=7` 时索引 = 7）。
> 时延/保持时长断言要取 **≥ 40 个样本**再算 P95；**判断「是否漂移」应当用中位数**
> （漂移是系统性偏移，中位数即可检出，且不会被个别宿主抖动污染）。
> 另：**不要用 Map 收集中间结果**，同名键互相覆盖后只剩一个样本。

### GUI 控件规范

```autohotkey
; 控件创建 - 位置参数必须用引号
this.controls["btnOK"] := this.gui.Add("Button", "x20 y30 w100 h35", "确定")

; Button 控件使用 .Text 属性而非 .Value
this.controls["btnToggle"].Text := "🐛 调试日志: 开启"

; 事件绑定 - 无参数使用 (*) =>
this.controls["btnOK"].OnEvent("Click", (*) => this._ApplyChanges())

; 事件绑定 - 带参数使用闭包
this.controls["btnDel"].OnEvent("Click", ((id) => (*) => this._Delete(id))(itemId))
```

### Switch 语句

```autohotkey
switch mode {
    case "periodic":
        result := this._ExecutePeriodic()
    case "sequence":
        result := this._ExecuteSequence()
    default:
        result := 10  ; 注意: default 分支不能用 { }
}
```

### 数据结构约定

#### AHK v2

```autohotkey
; 分组配置 - groups 数组格式
groups := [
    {type: "periodic", pressKeys: ["Space"], intervals: [50]},
    {type: "sequence", pressKeys: ["1", "2"], delays: [100, 100], seqInterval: 100}
]

; 配置数据
config := {
    hotkey: "F1",
    mode: "enhanced_periodic",
    pressKeys: ["space", "1", "2"],
    intervals: [50, 100, 100],
    holdKeys: ["Shift"],
    holdMode: "continuous"
}
```

#### Rust

```rust
// IpcCommand 枚举（13 variants，serde tag = "action"）
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action")]
pub enum IpcCommand {
    #[serde(rename = "toggle_group")]
    ToggleGroup {
        #[serde(rename = "groupId")]
        group_id: String,
        active: bool,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        mode: Option<String>,
        #[serde(rename = "keyPressDuration", skip_serializing_if = "Option::is_none", default)]
        key_press_duration: Option<u64>,
        #[serde(rename = "holdKeys", skip_serializing_if = "Option::is_none", default)]
        hold_keys: Option<Vec<String>>,
        #[serde(rename = "holdMode", skip_serializing_if = "Option::is_none", default)]
        hold_mode: Option<String>,
        #[serde(rename = "modeData", skip_serializing_if = "Option::is_none", default)]
        mode_data: Option<serde_json::Value>,
    },
    #[serde(rename = "register_hotkey")]
    RegisterHotkey { hotkey: String, #[serde(rename = "groupId")] group_id: String },
    #[serde(rename = "unregister_hotkey")]
    UnregisterHotkey { hotkey: String },
    #[serde(rename = "start_recording")]
    StartRecording { #[serde(rename = "groupId")] group_id: String, mode: String },
    #[serde(rename = "stop_recording")]
    StopRecording,
    #[serde(rename = "pause_recording")]
    PauseRecording,
    #[serde(rename = "resume_recording")]
    ResumeRecording,
    #[serde(rename = "emergency_release")]
    EmergencyRelease,
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "shutdown")]
    Shutdown,
    #[serde(rename = "hold_mode_toggle")]
    HoldModeToggle { enabled: bool },
    #[serde(rename = "start_validation")]
    StartValidation { #[serde(rename = "groupId")] group_id: String },
    #[serde(rename = "stop_validation")]
    StopValidation,
}

// IpcMessage 消息结构（9 字段，完整定义见 asd-tauri/crates/asd-ipc-protocol/src/message.rs）
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct IpcMessage {
    pub id: Option<String>,
    pub r#type: String,
    pub seq: u64,
    pub ack_seq: Option<u64>,
    pub action: Option<String>,
    pub keys: Option<Vec<String>>,
    pub delay: Option<u64>,
    pub status: Option<String>,
    pub data: Option<serde_json::Value>,
}

// Config 领域模型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub hotkey: String,
    pub mode: String,
    pub groups: IndexMap<String, GroupConfig>,
    // ...
}
```

## 支持的执行模式

| 模式                  | 说明    | 必需字段                       |
| ------------------- | ----- | -------------------------- |
| `periodic`          | 周期性按键 | `keys`, `intervals`        |
| `sequence`          | 序列按键  | `keys`, `delays`           |
| `hybrid`            | 混合模式  | `groups` 数组                |
| `hold`              | 长按模式  | `holdKeys`, `holdDuration` |
| `enhanced_periodic` | 增强周期性 | `pressKeys`, `intervals`   |
| `enhanced_sequence` | 增强序列  | `pressKeys`, `pressDelays` |
| `enhanced_hybrid`   | 增强混合  | `groups` 数组                |
| `joystick_periodic` | 摇杆周期性 | `pressKeys`, `intervals`（可选 `joystickId`） |
| `joystick_sequence` | 摇杆序列  | `pressKeys`, `delays`（可选 `joystickId`） |
| `joystick_hold`     | 摇杆长按  | `holdDuration` 可选、`autoRepeat` 可选、`repeatInterval` 可选（可选 `joystickId`，支持无限持续） |

> **执行模式口径**：上表为系统能力（共 10 种）。E2E 覆盖其中 7 种（`modes.spec.js`），`joystick_periodic` / `joystick_sequence` / `joystick_hold` 三种未纳入 E2E。两口径分别标注，不混用。

## 常见问题

### 日志文件位置

#### AHK v2

- 主日志: `logs/app.log` (JSON Lines 格式)
- 调试日志: `logs/debug.log` (详细执行追踪)
- JSON 错误: `logs/json_errors.log`

#### Rust/Tauri

- Rust 日志: 由 `tracing-appender` 管理，输出到标准位置
- Tauri 日志: `%APPDATA%/com.asd.tauri/logs/`

### 常见错误

#### AHK v2

1. **Map 属性访问错误**: `config.groups` 对 Map 无效，应使用 `config["groups"]` 或 `_GetProp()`
2. **控件位置参数错误**: `"x20 y30"` 必须有引号，`x20 y30` 是语法错误
3. **Button.Value 错误**: Button 控件应使用 `.Text` 属性，而非 `.Value`
4. **变量作用域**: 函数内访问全局变量需要 `global` 声明；AHK 变量名不区分大小写
5. **数组越界**: 访问数组前检查 `i <= arr.Length`
6. **OnEvent 静态方法引用**: `gui.OnEvent("Size", ClassName._OnResize)` 不能直接传递静态方法引用，必须用闭包包装：`gui.OnEvent("Size", (a,b,c,d) => ClassName._OnResize(a,b,c,d))`
7. **WebView2 await2 阻塞**: `WebView2.CreateControllerAsync().await2()` 需要消息循环运行，不能在同步初始化流程中直接调用，必须用 `SetTimer` 延迟执行
8. **Map.Delete 不存在的键**: `Map.Delete(key)` 在键不存在时抛出异常，必须先 `Map.Has(key)` 检查
9. **ExecuteScriptAsync 不等待 Promise**: `wv.ExecuteScriptAsync('Promise.resolve(42)')` 返回 `{}`，不是 `42`。必须使用 WebMessage 模式
10. **WebView2 sync 代理死锁**: `hostObjects.sync.ahk.Method()` 在 AHK 消息循环中被调用时会死锁，必须使用 postMessage 模式
11. **⚠️ 箭头函数块体语法错误（致命）**: AHK v2 的箭头函数 `=>` 只支持表达式体，**不支持块体 `{ }`**！使用 `(args) => { ... }` 会导致 "Missing propertyname: in object literal" 语法错误。必须使用逗号表达式 `(expr1, expr2, expr3)` 或闭包函数替代。
12. **⚠️ 字符串拼接中的花括号解析错误**: 在字符串拼接中，紧跟变量后的字符串字面量会被 AHK v2 解析为对象字面量的属性名。例如 `"try" OB "{" "code" CB "}"` 会报错。解决方案：使用 `Format()` 函数、单引号字符串 `'...'`、或分步构建。

#### Rust/Tauri

1. **纯逻辑 crate 引入 Tauri 依赖**: asd-domain/asd-ipc-protocol/asd-application 禁止引入 `tauri`, `tokio`, `interprocess`, `windows` crate
2. **IpcCommand 新增 variant 未同步**: 新增 IpcCommand variant 必须同步更新 AHK 执行器的处理逻辑，否则 IPC 通信会失败
3. **blocking_lock 死锁**: `Mutex::blocking_lock()` 在 tokio 异步上下文中可能导致死锁，优先使用 `lock().await`
4. **Config 序列化兼容性**: Rust 的 Config 结构体必须与 AHK 的 config.json 格式兼容（字段名、嵌套结构），否则 `config_compat_tests` 会失败
5. **Named pipe 路径**: interprocess named pipe 名称必须与 AHK 执行器中的管道名称一致
6. **ProcessWatchdog 超时**: AHK 子进程心跳超时时间需要与 AHK 端心跳间隔匹配

## 图谱式开发流程（摘要）

> **完整规范**：[`docs/graph-driven-workflow.md`](docs/graph-driven-workflow.md) — 本文件是**架构权威**，该规范是**流程权威**。

图谱式开发 = 先把代码真实依赖抽成图（节点 = 文件/crate，边 = 真实的 `#Include` / `use` / `import`），再基于图上的**四类靶点**做决策与审查：

| 靶点 | 含义 | 审查动作 |
|------|------|---------|
| **环** | A↔B 互相依赖（Tarjan 强连通分量） | 必须打破或记录架构决策 |
| **逆向边** | 内层依赖外层（如 infrastructure → domain） | 必须登记到本文件妥协表 |
| **孤点** | 无入边也无出边 | 删除 / 归档 / 确认合理 |
| **契约断点** | 跨进程同名契约不一致（IPC variant、命令名、配置字段） | 双向核对 |

**核心命令**：

```bash
python .review-analysis/build_graph.py      # 建图 → .review-analysis/graph-raw.json
python .review-analysis/gen_graph_html.py   # 渲染 → docs/review/<date>/graph/
```

**分层 depth 语义**（数值越小越内层，依赖方向恒由大 → 小）：
`infrastructure 0` → `domain 1` → `application 2` → `presentation 3` → `entry 4` → `executor 5` → `tests 6` → `other 7`
其中 `entry` / `tests` / `executor` / `other` 豁免分层约束。
> ⚠️ 分层常量（`LAYER_META` / `LAYER_EXEMPT`）在 **`gen_graph_html.py`**，不在 `build_graph.py`。

**开发流程要点**：变更前建基线 → 查影响面 → 变更后过**四闸门**（① 图谱无新环 ② fmt + clippy 零告警 ③ 测试通过且已登记 `test-map.md` ④ 文档已同步）。

**详细文档**：
- [`docs/graph-driven-workflow.md`](docs/graph-driven-workflow.md) — 目录结构 / 依赖图 / 链路追踪 / 开发流程 / 审查提交 / 同步机制
- [`docs/module-adjacency.md`](docs/module-adjacency.md) — 逐模块入边出边邻接表
- [`docs/graph-sync-checklist.md`](docs/graph-sync-checklist.md) — 可勾选的同步清单

> **数字权威**：本文件不持有测试数字，一切测试统计以 [`asd-tauri/docs/test-map.md`](asd-tauri/docs/test-map.md) 为**唯一权威**。

### 文档权威边界（五方，各自领域内唯一）

| 文档 | 权威领域 |
|------|---------|
| `AGENTS.md` | 架构决策、分层规则、妥协白名单、关键文件清单 |
| `asd-tauri/docs/test-map.md` | **一切测试数字**（其它文档只写指针） |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 |
| `docs/graph-driven-workflow.md` | 图谱方法、开发/审查流程、同步机制 |
| `docs/research/` | **架构级调研结论的唯一落点**（第三方/引擎层的源码走查 + 实测报告，如 AHK v2 引擎架构分析）。探针脚本在 `tools/ahk-probes/` |

冲突时：数字 → test-map；架构 → AGENTS；命令 → developer-guide；流程 → graph-driven-workflow；
外部引擎/第三方调研 → `docs/research/`。
**矛盾必须当场修正，不允许两边都留着。**

## 重要提醒

- 所有 GUI 控件位置参数必须用双引号包围
- Button 控件使用 `.Text` 属性设置文本
- 日志级别：ERROR/WARNING/DEBUG（不使用 INFO）
- 配置更改后调用 `ExportConfigToJson()` 持久化
- 周期性键必须使用独立触发时间，不能用 `Mod(A_TickCount, interval)`
- 定时器引用必须存储在 `_timers` Map 中，确保能正确停止
- 热路径日志（Execute\* 方法）会自动限速，每秒最多记录一次
- **⚠️ 所有 .ahk 文件必须包含错误接管指令（详见 "错误与警告接管机制" 节），无例外**
- **⚠️ 加载时错误通过 `#ErrorStdOut "UTF-8"` 接管，运行时错误通过 `OnError` 回调接管**
- **⚠️ 箭头函数 `=>` 只支持表达式体，绝对不能使用 `=> { }` 块体语法**
- **⚠️ 执行测试前必须完成前置检查：语法检查（stderr 重定向 + 退出码验证）→ 接管指令验证 → 运行时验证**
- **⚠️ 语法检查必须使用 `Start-Process -RedirectStandardError` 或 `2>&1` 重定向 stderr，否则无法捕获 `#ErrorStdOut` 输出的错误**
- **⚠️ 纯逻辑 Rust crate 禁止引入 Tauri/tokio/interprocess/windows 依赖**
- **⚠️ 新增 IpcCommand variant 必须同步更新 AHK 执行器处理逻辑**
- 使用中文回复
