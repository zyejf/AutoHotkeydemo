# 修复 Critical 审查发现 Spec

## Why

全面代码审查发现 10 项 Critical 级别问题，涵盖安全漏洞（WebView2 调试端口、路径遍历绕过）、架构违规（DDD 层依赖）、合规规则缺失（接管指令、OnError 回调）、配置文档过时（test-manifest feature、硬编码路径）和测试覆盖盲区（27 个 Tauri command 无测试、joy_hotkey_manager 无测试）。这些问题影响系统安全性、架构完整性和可维护性，需按优先级顺序修复。

## What Changes

按**安全优先**顺序修复全部 10 项 Critical 问题：

- **C3**: 移除/条件化 `webview2_manager.ahk:63` 的 WebView2 远程调试端口 `EnvSet`
- **C4**: 将 `webview2_manager.ahk:1171` 和 `backup_core.ahk:112` 的路径遍历防护从 `RegExReplace` 删除式改为 `InStr` 拒绝式
- **C1**: 完整 DI 重构 — 新增 `IJoySender` 抽象接口，`JoySender extends IJoySender`，删除 `domain/joystick_executor.ahk` 的 `#Include`，通过注入实例调用，在 `main.ahk` 完成注入
- **C2**: 为 `infrastructure/migration_logger.ahk` 补充 3 条 `#Warn` 强制接管指令
- **C5**: 为 `tests/AutoHotUnit.ahk` 补充完整接管指令集（`#Requires`/`#ErrorStdOut`/`#Warn`/`OnError`）
- **C6**: 为约 30 个缺少 `OnError` 的测试文件批量添加标准 `OnError` 回调
- **C8**: 从 `Cargo.toml` 删除废弃的 `test-manifest` feature，同步更新 `AGENTS.md`
- **C9**: 将 E2E 测试中硬编码的 AHK 路径改为环境变量注入
- **C7**: 创建 `tests/test_joy_hotkey_manager.ahk` 覆盖手柄热键管理器关键路径
- **C10**: 仿照 `system_cmd.rs` 的 `_impl` 模式，为 27 个 Tauri command 提取核心逻辑并补充测试

## Impact

- Affected specs: `comprehensive-code-audit`（审查报告中的发现将被修复）
- Affected code:
  - AHK v2: `domain/joystick_executor.ahk`, `domain/interfaces.ahk`, `infrastructure/joy_sender.ahk`, `infrastructure/migration_logger.ahk`, `infrastructure/backup_core.ahk`, `presentation/webview2_manager.ahk`, `main.ahk`, `tests/AutoHotUnit.ahk`, `tests/` 下约 30 个测试文件, 新建 `tests/test_joy_hotkey_manager.ahk`
  - Rust/Tauri: `asd-tauri/src-tauri/Cargo.toml`, `asd-tauri/src-tauri/src/commands/config_cmd.rs`, `group_cmd.rs`, `recording_cmd.rs`, `asd-tauri/e2e/specs/hotkey_cmd.spec.js`, `asd-tauri/e2e/helpers/key_receiver.js`
  - 文档: `AGENTS.md`（移除 test-manifest 相关描述、更新妥协清单）
- 产出物: 修复后的源代码 + 验证测试

## ADDED Requirements

### Requirement: 安全漏洞修复（C3, C4）

系统 SHALL 立即修复 2 项安全漏洞。

#### Scenario: C3 — WebView2 调试端口移除
- **WHEN** 修复 `webview2_manager.ahk:63`
- **THEN** 移除无条件的 `EnvSet("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9222")`
- **AND** 仅在显式调试模式下开启（如检查 `A_IsCompiled` 返回 false 时，或读取配置标志）
- **AND** 发布构建（`A_IsCompiled` 为 true）时强制不开启调试端口

#### Scenario: C4 — 路径遍历防护改为拒绝式
- **WHEN** 修复 `webview2_manager.ahk:1171-1172` 和 `backup_core.ahk:112-113`
- **THEN** 将 `RegExReplace(path, "\.\.", "")` 替换为 `InStr` 拒绝式检查
- **AND** 输入路径包含 `..` 时直接返回错误，不执行后续操作
- **AND** 参考 `_BridgeRestoreBackup:721-723` 的正确实现模式

### Requirement: 架构违规修复（C1）

系统 SHALL 通过完整依赖注入重构修复 DDD 层依赖违规。

#### Scenario: C1 — IJoySender 抽象接口
- **WHEN** 修复 `domain/joystick_executor.ahk:16` 的违规引用
- **THEN** 在 `domain/interfaces.ahk` 新增 `IJoySender` 抽象基类，定义 `SendBtn`/`SendPov`/`SendAxis` 等方法签名
- **AND** `infrastructure/joy_sender.ahk` 的 `JoySender` 类 `extends IJoySender`
- **AND** 删除 `domain/joystick_executor.ahk` 中的 `#Include "../infrastructure/joy_sender.ahk"`
- **AND** `JoystickExecutor` 通过注入的 `IJoySender` 实例调用方法
- **AND** 在 `main.ahk` 的 `InitDependencies()` 中完成 `JoySender` 实例的创建和注入

### Requirement: 合规规则修复（C2, C5, C6）

系统 SHALL 修复所有缺失的强制接管指令。

#### Scenario: C2 — migration_logger 补充 #Warn
- **WHEN** 修复 `infrastructure/migration_logger.ahk:1-2`
- **THEN** 在 `#ErrorStdOut "UTF-8"` 之后补充 `#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`

#### Scenario: C5 — AutoHotUnit 补充接管指令
- **WHEN** 修复 `tests/AutoHotUnit.ahk:1-4`
- **THEN** 移除非标准的 `#Warn All, StdOut`
- **AND** 添加 `#Requires AutoHotkey v2.0`、`#ErrorStdOut "UTF-8"`、`#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`、`OnError` 回调

#### Scenario: C6 — 测试文件批量补充 OnError
- **WHEN** 修复约 30 个缺少 `OnError` 的测试文件
- **THEN** 为每个文件添加 `OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))`

### Requirement: 配置文档修复（C8, C9）

系统 SHALL 修复过时的配置和硬编码路径。

#### Scenario: C8 — 删除 test-manifest feature
- **WHEN** 修复 `Cargo.toml` 和 `AGENTS.md`
- **THEN** 从 `Cargo.toml` 删除 `test-manifest = []` feature 定义
- **AND** 从 `AGENTS.md` 移除所有 `test-manifest` 相关描述（Testing Requirements 章节、常见错误第 4 条）
- **AND** 简化测试运行命令（移除 `--features test-manifest`）

#### Scenario: C9 — E2E 路径环境变量化
- **WHEN** 修复 `e2e/specs/hotkey_cmd.spec.js:43` 和 `e2e/helpers/key_receiver.js:16`
- **THEN** 将硬编码的 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` 改为从环境变量读取
- **AND** 在 `e2e/helpers/` 中集中管理路径常量（如 `config.js`）
- **AND** 提供合理的默认值回退

### Requirement: 测试覆盖补充（C7, C10）

系统 SHALL 为关键模块补充测试覆盖。

#### Scenario: C7 — joy_hotkey_manager 测试
- **WHEN** 创建 `tests/test_joy_hotkey_manager.ahk`
- **THEN** 覆盖热键注册/注销、轴/POV 轮询、热插拔检测、多手柄支持等关键路径
- **AND** 遵循测试文件标准模板（含完整接管指令 + OnError）

#### Scenario: C10 — Tauri command 测试
- **WHEN** 修复 `commands/{config_cmd.rs, group_cmd.rs, recording_cmd.rs}`
- **THEN** 仿照 `system_cmd.rs` 的 `_impl` 模式，将 command 函数体提取为 `fn xxx_impl(state: &Arc<AppState>, ...) -> Result<...>`
- **AND** command 函数仅一行委托给 `_impl`
- **AND** 对每个 command 至少添加正常路径 + 错误路径测试

### Requirement: TDD 工作流

所有修复 SHALL 遵循 TDD 流程（RED-GREEN-REFACTOR）。

#### Scenario: TDD 执行
- **WHEN** 实施每个修复
- **THEN** 先编写验证修复的测试（RED）
- **AND** 观察测试失败
- **AND** 编写最小修复代码使测试通过（GREEN）
- **AND** 必要时重构（REFACTOR）

### Requirement: 只读约束解除

与审查阶段不同，本阶段 SHALL 修改源代码文件以修复 Critical 问题。

#### Scenario: 代码修改
- **WHEN** 执行修复
- **THEN** 修改、创建源代码文件以实施修复
- **AND** 不修改与当前 10 项 Critical 无关的代码
- **AND** 不回滚用户已有的工作区变更

## MODIFIED Requirements

无

## REMOVED Requirements

无
