# ASD 技能管理器 全面代码审查报告

> **审查日期**: 2026-08-03
> **审查范围**: AHK v2 + Rust/Tauri 全代码库
> **审查维度**: 架构合规性、代码质量、安全性、测试覆盖
> **审查方式**: 只读分析，未修改任何代码
> **审查依据**: `AGENTS.md` v4.0 规范文档

---

## 一、执行摘要

### 1.1 总体评估

ASD 技能管理器 v4.0 项目整体代码质量**中等偏上**，采用了 AHK v2 DDD 四层架构与 Rust/Tauri 4-crate workspace 混合架构，设计思路清晰。项目在错误处理体系、定时器引用管理、WebView2 postMessage 通信模式、Rust 纯逻辑 crate 隔离等方面表现优秀，特别是 Rust 纯逻辑 crate 实现了 0 unsafe 代码、0 禁用依赖、0 I/O 泄漏，符合 Miri 兼容性要求。

但审查也发现了若干需要关注的问题领域。**安全性方面**存在 2 个 Critical 级别漏洞（WebView2 调试端口遗留、路径遍历防护可被绕过），需立即修复。**架构合规性方面**存在 1 个 Critical 级别的 DDD 层依赖违规（领域层直接引用基础设施层模块），以及多处未登记的反向依赖。**测试覆盖方面**存在显著盲区：27 个 Tauri command 函数无直接单元测试、`joy_hotkey_manager.ahk` 完全无测试覆盖、约 30 个 AHK 测试文件缺少 `OnError` 回调。**文档一致性方面**，AGENTS.md 作为强制规则文档存在多处与实际代码不符的描述（IpcCommand 示例变体名全错、执行模式表少 3 项、workspace 成员数错误、Tauri commands 数量过期等），会误导后续维护者。

### 1.2 关键指标

| 指标 | 数值 |
|------|------|
| 审查 Task 总数 | 8 |
| 审查文件总数 | 100+（AHK 63 + Rust 40+ + 文档） |
| 发现总数（去重后） | 94 |
| Critical | 10 |
| Important | 43 |
| Minor | 41 |

### 1.3 关键风险（Critical 级别问题清单）

1. **C1**: `domain/joystick_executor.ahk:16` 违规引用 `infrastructure/joy_sender.ahk`，违反 AGENTS.md 妥协 #1 约束边界
2. **C2**: `infrastructure/migration_logger.ahk` 缺少 3 条 `#Warn` 强制接管指令，全项目唯一不合规文件
3. **C3**: `presentation/webview2_manager.ahk:63` 通过 `EnvSet` 强制开启 WebView2 远程调试端口 9222，允许本机任意进程注入恶意 JS
4. **C4**: `webview2_manager.ahk:1171-1172` 与 `backup_core.ahk:112-113` 路径遍历防护使用 `RegExReplace` 删除 `..`，可被 `....` 输入绕过
5. **C5**: `tests/AutoHotUnit.ahk` 测试框架本身完全缺少接管指令，使用非标准 `#Warn All, StdOut`
6. **C6**: `tests/` 根目录约 30 个测试文件缺少 `OnError` 回调，单独运行时运行时错误弹窗卡死
7. **C7**: `infrastructure/joy_hotkey_manager.ahk`（11575 bytes，手柄热键/轴轮询/热插拔检测）完全无测试覆盖
8. **C8**: `asd-tauri/src-tauri/Cargo.toml` 定义 `test-manifest` feature 但全代码库无任何使用，AGENTS.md 文档说法已过时
9. **C9**: `asd-tauri/e2e/specs/hotkey_cmd.spec.js:43` 硬编码 AHK 路径 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`，跨机器不可移植
10. **C10**: `src-tauri/src/commands/` 下 27 个 `#[tauri::command]` 函数无直接单元测试覆盖

---

## 二、统计汇总

### 2.1 按严重级别分布

| 级别 | 数量 | 占比 |
|------|------|------|
| Critical | 10 | 10.6% |
| Important | 43 | 45.7% |
| Minor | 41 | 43.6% |
| **总计** | **94** | **100%** |

### 2.2 按维度分布

| 维度 | Critical | Important | Minor | 小计 |
|------|----------|-----------|-------|------|
| 架构合规性 | 2 | 13 | 5 | 20 |
| 代码质量 | 0 | 8 | 20 | 28 |
| 安全性 | 2 | 12 | 5 | 19 |
| 测试覆盖 | 6 | 10 | 11 | 27 |
| **总计** | **10** | **43** | **41** | **94** |

### 2.3 按模块分布

| 模块 | Critical | Important | Minor | 小计 |
|------|----------|-----------|-------|------|
| AHK v2 - domain/ | 1 | 1 | 1 | 3 |
| AHK v2 - infrastructure/ | 1 | 9 | 6 | 16 |
| AHK v2 - application/ | 0 | 0 | 2 | 2 |
| AHK v2 - presentation/ | 2 | 7 | 7 | 16 |
| AHK v2 - tests/ | 3 | 4 | 4 | 11 |
| AHK v2 - 根目录/跨文件 | 0 | 2 | 2 | 4 |
| Rust - asd-domain | 0 | 1 | 1 | 2 |
| Rust - asd-ipc-protocol | 0 | 1 | 0 | 1 |
| Rust - asd-application | 0 | 2 | 7 | 9 |
| Rust - src-tauri | 3 | 9 | 8 | 20 |
| 文档（AGENTS.md） | 0 | 7 | 3 | 10 |
| **总计** | **10** | **43** | **41** | **94** |

> 注：部分发现跨多个模块，按主要文件位置归类。AGENTS.md 文档不一致问题统一归入"文档（AGENTS.md）"模块。

---

## 三、详细发现

### 3.1 Critical 级别发现

#### C1: 领域层违规引用基础设施层 joy_sender 模块

- **位置**: `domain/joystick_executor.ahk:16`
- **维度**: 架构合规性 / DDD 层依赖违规
- **模块**: AHK v2 - domain/
- **描述**: 领域层文件 `domain/joystick_executor.ahk` 通过 `#Include "../infrastructure/joy_sender.ahk"` 直接引用基础设施层的 `JoySender` 模块。该文件中 `JoystickExecutor._SendJoyKey`（第 149-178 行）与 `_ReleaseJoyKeys`（第 180-199 行）直接调用 `JoySender.SendBtn/SendPov/SendAxis` 等具体方法，形成领域层对基础设施实现细节的硬依赖。
- **根因**: `JoystickExecutor` 作为领域执行器，需要发送手柄按键，但未通过 `domain/interfaces.ahk` 中定义的抽象接口（如 `IExecutor`）反转依赖，而是直接 `#Include` 基础设施实现类。
- **违反约束**: AGENTS.md 妥协 #1 明确规定"仅允许 `domain/` 引用 `infrastructure/error_system.ahk` 的 `LogError` 方法。禁止领域层引用 `infrastructure/` 中的其他模块"。`joy_sender.ahk` 不在豁免清单内。
- **修复建议**: 在 `domain/interfaces.ahk` 中新增 `IJoySender` 抽象基类；`JoySender` 类 `extends IJoySender`；删除 `#Include`，改为通过注入的 `IJoySender` 实例调用；在 `main.ahk` 的 `InitDependencies()` 中完成注入。
- **来源**: Task 1

#### C2: migration_logger.ahk 缺少 #Warn 强制接管指令

- **位置**: `infrastructure/migration_logger.ahk:1-2`
- **维度**: 架构合规性 / 强制规则遵守
- **模块**: AHK v2 - infrastructure/
- **描述**: 该文件仅包含 `#Requires AutoHotkey v2.0` 和 `#ErrorStdOut "UTF-8"`，缺少以下 3 条强制接管指令：`#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`。该文件是 33 个被审查文件中唯一缺少 `#Warn` 指令的文件。
- **根因**: 文件未遵循 AGENTS.md「错误与警告接管机制」章节中「所有 .ahk 文件必须包含的接管指令」的强制要求。
- **修复建议**: 在 `#ErrorStdOut "UTF-8"` 之后补充 3 条 `#Warn` 指令，与其他 infrastructure 层文件保持一致。
- **来源**: Task 2

#### C3: WebView2 远程调试端口在生产环境开启

- **位置**: `presentation/webview2_manager.ahk:63`
- **维度**: 安全性 / WebView2 通信安全
- **模块**: AHK v2 - presentation/
- **描述**: 在 `_InitWebView2()` 中通过 `EnvSet` 强制设置 WebView2 远程调试端口：
  ```autohotkey
  EnvSet("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9222")
  ```
  该环境变量在 WebView2 控制器创建时被读取，会在本机 9222 端口开启 Chrome DevTools Protocol 调试服务。在生产环境中，任何本机进程（包括恶意脚本、浏览器内的恶意网页通过 DNS Rebinding）均可连接该端口，执行任意 JavaScript、读取页面数据、调用 AHK-JS Bridge 暴露的所有命令（含分组删除、配置覆盖、紧急停止等）。该代码无任何条件判断，每次初始化 WebView2 都会启用调试端口。
- **根因**: 开发阶段为调试 WebView2 内容遗留的代码未在发布前移除。
- **修复建议**: 移除该 `EnvSet` 调用，或仅在显式调试模式下开启（如检查 `A_IsCompiled` 或读取配置标志）；发布构建时强制关闭调试端口。
- **来源**: Task 3

#### C4: 路径遍历防护可被 .... 输入绕过

- **位置**: `presentation/webview2_manager.ahk:1171-1172`、`infrastructure/backup_core.ahk:112-113`
- **维度**: 安全性 / 输入验证 / 路径遍历
- **模块**: AHK v2 - presentation/ + infrastructure/
- **描述**: 两处路径遍历防护均使用 `RegExReplace(path, "\.\.", "")` 删除所有 `..` 子串，该正则替换可被 `....` 输入绕过。攻击者构造 `backups\....\....\config.json`，`....` 中匹配到 `..` 删除后剩 `..`，可逃逸出 `backups` 目录，读取任意文件。`_BridgeCompareConfigs` 接受来自 WebView2 JS 端的 `basePath` / `targetPath` 参数，攻击者可通过 JS 注入恶意路径。
- **根因**: 使用"删除危险字符串"而非"拒绝危险输入"的过滤策略，违反 OWASP 路径遍历防护原则。
- **修复建议**: 改用 `InStr` 拒绝式检查（参考 `_BridgeRestoreBackup:721-723` 的正确实现）：`if InStr(absBase, "..") || InStr(absTarget, "..") return 错误`；或使用 `SplitPath` 解析后比较绝对路径前缀。
- **来源**: Task 3

#### C5: AutoHotUnit.ahk 测试框架缺少接管指令

- **位置**: `tests/AutoHotUnit.ahk:1-4`
- **维度**: 测试覆盖 / 测试前置检查流程遵守
- **模块**: AHK v2 - tests/
- **描述**: AutoHotUnit.ahk（AutoHotUnit 测试框架本身）完全缺少 AGENTS.md 强制要求的接管指令。文件顶部仅有 `#SingleInstance Force`、`#Warn All, StdOut`、`FileEncoding("UTF-8")`，缺少 `#Requires AutoHotkey v2.0`、`#ErrorStdOut "UTF-8"`、`#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`、`OnError` 回调。更严重的是使用 `#Warn All, StdOut` 而非标准要求的细粒度 `#Warn` 配置（警告输出到 stdout 而非 OutputDebug，会污染测试输出）。
- **根因**: 测试框架文件被误认为不需要遵守接管指令规则；`#Warn All, StdOut` 与标准要求的细粒度 `#Warn` 配置冲突。
- **修复建议**: 在 AutoHotUnit.ahk 顶部添加完整的接管指令集。
- **来源**: Task 4

#### C6: 约 30 个 AHK 测试文件缺少 OnError 回调

- **位置**: `tests/test_domain.ahk`, `test_infrastructure.ahk`, `test_application.ahk`, `test_presentation.ahk`, `test_webview2_bridge.ahk`, `test_boundary.ahk`, `test_error_captor.ahk` 等 30 个文件
- **维度**: 测试覆盖 / 测试前置检查流程遵守
- **模块**: AHK v2 - tests/
- **描述**: tests/ 根目录下约 30 个测试文件缺少 `OnError` 回调。AGENTS.md「测试文件额外必须包含」章节明确要求测试文件包含 `OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))`。这些文件如果单独运行，运行时错误会弹出默认错误对话框，导致测试卡死、无法在 CI 中自动化运行。
- **根因**: tests/ 根目录的测试文件采用场景式（TestReporter）模式，预期作为独立脚本运行，但未遵循 OnError 强制规则。
- **修复建议**: 为所有 30 个缺少 OnError 的测试文件添加标准 OnError 回调。
- **来源**: Task 4

#### C7: joy_hotkey_manager.ahk 完全无测试覆盖

- **位置**: `infrastructure/joy_hotkey_manager.ahk`（11575 bytes）
- **维度**: 测试覆盖 / 覆盖率盲区
- **模块**: AHK v2 - tests/（覆盖率盲区）
- **描述**: `infrastructure/joy_hotkey_manager.ahk` 是一个 11575 bytes 的基础设施模块，提供手柄按钮热键注册（Joy1~Joy32）、轴/POV 轮询（SetTimer）、热插拔检测（30s）、多手柄支持等关键功能。经全量扫描 tests/ 下所有 .ahk 文件，确认该模块未被任何测试文件 #Include 或引用。
- **根因**: 该模块添加时未同步创建测试，AGENTS.md「Subdirectories」章节也未在 infrastructure 模块清单中列出它的测试对应物。
- **修复建议**: 创建 `tests/test_joy_hotkey_manager.ahk`，覆盖热键注册/注销、轴/POV 轮询、热插拔检测、多手柄支持等关键路径；将该模块登记到 AGENTS.md。
- **来源**: Task 4

#### C8: test-manifest feature 已废弃但仍被文档引用

- **位置**: `asd-tauri/src-tauri/Cargo.toml:7`
- **维度**: 测试覆盖 / 配置一致性
- **模块**: Rust - src-tauri
- **描述**: `Cargo.toml` 第 7 行定义了 `test-manifest = []` feature，但全代码库中无任何 `#[cfg(feature = "test-manifest")]` 或 `#[cfg(not(feature = "test-manifest"))]` 使用。AGENTS.md 多处声称"主 crate 测试需要 `--features test-manifest`，否则部分测试会被跳过"，包括「Testing Requirements」章节和「常见错误」第 4 条。
- **根因**: feature 早期可能 gate 过 manifest 加载测试，后续重构中被废弃但未删除定义；AGENTS.md 文档未同步更新。
- **修复建议**: 从 `Cargo.toml` 删除 `test-manifest = []`；同步更新 AGENTS.md 移除所有"test-manifest"相关描述；简化测试运行命令。
- **来源**: Task 8

#### C9: E2E 测试硬编码 AHK v2 路径

- **位置**: `asd-tauri/e2e/specs/hotkey_cmd.spec.js:43`、`asd-tauri/e2e/helpers/key_receiver.js:16`
- **维度**: 测试覆盖 / 测试隔离性 / 跨机器可移植性
- **模块**: Rust - src-tauri（E2E）
- **描述**: 两处硬编码 AHK v2 路径 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`。其他开发者的机器上若 AHK 安装在 `C:\Program Files\AutoHotkey\` 或使用 32 位版本，E2E 测试将立即失败。
- **根因**: E2E 测试开发时直接写死了开发者本机路径，未做环境抽象。
- **修复建议**: 通过环境变量注入（`process.env.AHK_PATH`）；或在 `e2e/helpers/config.js` 中集中管理路径常量；或在 `wdio.conf.js` 中读取 `tauri.conf.json` 的 AHK 路径配置。
- **来源**: Task 8

#### C10: 27 个 Tauri command 函数无直接单元测试

- **位置**: `asd-tauri/src-tauri/src/commands/{config_cmd.rs, group_cmd.rs, recording_cmd.rs}`
- **维度**: 测试覆盖 / 覆盖率盲区
- **模块**: Rust - src-tauri
- **描述**: 三个 commands 模块共有 27 个 `#[tauri::command]` 函数，但单元测试均未覆盖 command 函数本身：
  - `config_cmd.rs`：11 个 commands，7 个测试全部测试 `ConfigValidator` 和 `AppError`
  - `group_cmd.rs`：8 个 commands，4 个测试仅测试数据结构序列化
  - `recording_cmd.rs`：8 个 commands，3 个测试仅测试 `RecordingResult` 序列化
- **根因**: `#[tauri::command]` 函数需要 `tauri::State<'_, Arc<AppState>>` 参数，Tauri 2.11.2 中无公共构造函数，难以在纯单元测试中构造。`system_cmd.rs` 通过 `_impl` 辅助函数模式绕过了此限制，但其他 commands 未采用此模式。
- **修复建议**: 仿照 `system_cmd.rs` 的 `_impl` 模式，将 command 函数体提取为 `fn xxx_impl(state: &Arc<AppState>, ...) -> Result<...>`，command 函数仅一行委托；对每个 command 至少添加正常路径 + 错误路径测试。
- **来源**: Task 8

### 3.2 Important 级别发现

#### I1: 表现层多处直接调用 BackupCore 基础设施类

- **位置**: `presentation/backup_ui.ahk:61,86,100,126,142,153`、`presentation/gui_manager.ahk:238`、`presentation/webview2_manager.ahk:712,725,726,745,746,754,1135,1144`
- **维度**: 架构合规性 / DDD 分层违规
- **模块**: AHK v2 - presentation/
- **描述**: 表现层多个文件直接调用基础设施层的 `BackupCore` 类方法（`ListBackups/RestoreBackup/DeleteBackup/CreateBackup/RecordConfigChange`），跳过应用层中转，绕过了应用层的事务协调与回滚保护逻辑。
- **根因**: 表现层为快速访问备份功能直接调用基础设施层，未通过应用层封装抽象，导致分层边界被绕过。
- **违反约束**: 此违规不在已知妥协 #3 范围内（妥协 #3 仅豁免 `application/config_service.ahk` 对 `BackupCore` 的引用）。
- **修复建议**: 在 `application/` 中封装备份相关 API，表现层改为调用应用层方法。
- **来源**: Task 1

#### I2: AGENTS.md 妥协 #2 _Notify 签名描述与实际不符

- **位置**: `AGENTS.md`「AHK 已知架构妥协」第 2 项 vs `domain/interfaces.ahk:51`、`presentation/webview2_manager.ahk`
- **维度**: 架构合规性 / 文档与代码一致性
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 妥协 #2 描述"`domain/interfaces.ahk` 定义 `_Notify` 签名为 `(event, data)`，`presentation/webview2_manager.ahk` 使用 `(event, data, meta*)` 可变参数"，与实际代码完全不符：`domain/interfaces.ahk:51` 实际定义的是 `INotifier.Notify(message, type := "info", duration := 0)`，不存在 `_Notify(event, data)` 方法；`presentation/webview2_manager.ahk` 中完全没有 `_Notify` 方法定义。
- **根因**: 接口重构后 INotifier 方法签名已变更，但 AGENTS.md 妥协条款未同步更新，文档长期漂移。
- **修复建议**: 更新 AGENTS.md 妥协 #2 描述，反映当前 `INotifier.Notify(message, type, duration)` 契约，或直接移除妥协 #2（因签名差异问题已不存在）。
- **来源**: Task 1

#### I3: joy_hotkey_manager.ahk 反向依赖 domain/joystick_input.ahk

- **位置**: `infrastructure/joy_hotkey_manager.ahk:14`
- **维度**: 架构合规性 / DDD 反向依赖
- **模块**: AHK v2 - infrastructure/
- **描述**: 基础设施层文件 `infrastructure/joy_hotkey_manager.ahk` 通过 `#Include "../domain/joystick_input.ahk"` 引用领域层的 `JoystickInput` 具体类，并在多处直接调用 `JoystickInput.IsButton/IsAxis/IsTrigger/IsPov/PovToDirection/IsJoystickConnected` 等具体静态方法。
- **根因**: infrastructure 层手柄热键模块需要复用 domain 层的手柄输入工具函数，但未通过接口抽象或迁移到 infrastructure 层，形成反向依赖且未在妥协清单登记。
- **违反约束**: AGENTS.md「AHK v2 架构（DDD 四层）」隐含的依赖倒置原则。此问题不在已知妥协清单内，属于未声明的架构妥协。
- **修复建议**: 将 `joystick_input.ahk` 中的纯工具函数迁移到 `infrastructure/` 下；或在 `domain/interfaces.ahk` 中新增抽象基类；或在 AGENTS.md「已知妥协」中显式登记此依赖。
- **来源**: Task 1 & Task 2 均报告

#### I4: joy_hotkey_manager.ahk 使用 INFO 日志级别

- **位置**: `infrastructure/joy_hotkey_manager.ahk:299`
- **维度**: 架构合规性 / 强制规则遵守（日志级别）
- **模块**: AHK v2 - infrastructure/
- **描述**: 使用了 `"INFO"` 日志级别：`ErrorSystem.LogError("手柄已重新连接", "INFO", A_ThisFunc, A_LineNumber)`。AGENTS.md 明确要求「日志级别：ERROR/WARNING/DEBUG（不使用 INFO）」。
- **根因**: 开发者未遵循 AGENTS.md 日志级别规范，使用了项目禁用的 INFO 级别而非 DEBUG。
- **修复建议**: 将 `"INFO"` 改为 `"DEBUG"`。
- **来源**: Task 2

#### I5: gui_manager.ahk OnEvent 静态方法引用未用闭包包装

- **位置**: `presentation/gui_manager.ahk:79`
- **维度**: 代码质量 / GUI 控件规范
- **模块**: AHK v2 - presentation/
- **描述**: 直接传递静态方法引用作为事件回调：`GUIManager.controls["GroupLV"].OnEvent("ContextMenu", GUIManager._ShowContextMenu)`。AGENTS.md「常见错误」#6 明确指出此类用法必须用闭包包装。
- **根因**: 开发者未遵循 AGENTS.md「常见错误」#6 关于 OnEvent 静态方法引用必须用闭包包装的规范。
- **修复建议**: 改为闭包包装形式：`(lv, item, isRightClick, *) => GUIManager._ShowContextMenu(lv, item, isRightClick)`。
- **来源**: Task 2

#### I6: backup_core.ahk 调用应用层 ExportConfigToFile 函数

- **位置**: `infrastructure/backup_core.ahk:70`
- **维度**: 架构合规性 / DDD 层依赖违规
- **模块**: AHK v2 - infrastructure/
- **描述**: 基础设施层模块调用了应用层定义的全局函数 `ExportConfigToFile`（定义于 `application/config_service.ahk:421`）。AGENTS.md 妥协 #3 仅允许 `ConfigService` 通过 `BackupCore.CreateBackup()` 静态方法调用 BackupCore，未授权反向依赖。
- **根因**: 基础设施层 BackupCore 需要写回配置文件，但未在自身实现文件写入逻辑，而是反向调用应用层函数，违反依赖方向。
- **修复建议**: 将 `ExportConfigToFile` 的核心文件写入逻辑下沉到基础设施层，或让 `BackupCore.RestoreBackup` 接受写入回调参数。
- **来源**: Task 2

#### I7: config_store.ahk DeleteGroupConfig 未检查 Map.Has

- **位置**: `infrastructure/config_store.ahk:119-121`
- **维度**: 代码质量 / 错误处理（Map.Delete 不存在键）
- **模块**: AHK v2 - infrastructure/
- **描述**: `DeleteGroupConfig` 公共方法直接调用 `Map.Delete` 而未先检查 `Has`。AGENTS.md「常见错误」#8 明确指出「`Map.Delete(key)` 在键不存在时抛出异常，必须先 `Map.Has(key)` 检查」。
- **根因**: 开发者未遵循 AGENTS.md「常见错误」#8 关于 Map.Delete 前必须 Has 检查的规范，缺少防御性编程。
- **修复建议**: 添加 `if this._groupSettings.Has(groupId)` 前置检查。
- **来源**: Task 2

#### I8: joy_hotkey_manager.ahk UnregisterHotkey 未检查 Map.Has

- **位置**: `infrastructure/joy_hotkey_manager.ahk:92`
- **维度**: 代码质量 / 错误处理（Map.Delete 不存在键）
- **模块**: AHK v2 - infrastructure/
- **描述**: `UnregisterHotkey` 的 `else` 分支（非按钮类型）直接 Delete 而未检查 Has。对比同文件行 70（按钮分支）有 `Has` 检查，此处遗漏。
- **根因**: 与按钮分支（行 70）的 Has 检查不一致，else 分支遗漏了相同的防御性检查。
- **修复建议**: 包裹 `if JoyHotkeyManager._registered.Has(joyKey)` 后再 Delete。
- **来源**: Task 2

#### I9: error_system.ahk OnError 对 MemoryError 返回 0

- **位置**: `infrastructure/error_system.ahk:82-85`
- **维度**: 代码质量 / 强制规则遵守（OnError 回调返回值）
- **模块**: AHK v2 - infrastructure/
- **描述**: `HandleError` 对 MemoryError 返回 0（允许默认错误对话框弹出），AGENTS.md 要求「OnError 回调返回 true 阻止默认错误对话框弹出」。这看起来是有意设计——MemoryError 不可恢复，让系统弹出对话框并终止是合理的。但严格按 AGENTS.md 字面要求，所有运行时错误都应返回 true 接管。
- **根因**: AGENTS.md 规则要求所有运行时错误返回 true 接管，但未对 MemoryError 等不可恢复错误提供例外说明，导致代码的合理设计与文档规则字面冲突。
- **修复建议**: 保留当前行为（MemoryError 应该让用户感知），但在 AGENTS.md 中补充例外说明：「MemoryError 等不可恢复错误允许返回 0」。这是文档对齐问题，而非代码缺陷。
- **来源**: Task 2

#### I10: joy_hotkey_manager.ahk 连接轮询定时器未存储引用

- **位置**: `infrastructure/joy_hotkey_manager.ahk:285-291`
- **维度**: 代码质量 / 定时器管理规范
- **模块**: AHK v2 - infrastructure/
- **描述**: 连接轮询定时器未存储引用，无法停止：`SetTimer(() => JoyHotkeyManager._PollConnection(), 30000)` 未存储。AGENTS.md「定时器管理规范」要求「定时器引用必须存储在 `_timers` Map 中，确保能正确停止」。该定时器每 30 秒执行一次，应用生命周期内无法停止。
- **根因**: 开发者未遵循 AGENTS.md「定时器管理规范」，遗漏将长生命周期定时器引用存入 _timers Map 以便停止。
- **修复建议**: 将定时器引用存储到静态属性（如 `_connPollTimer`），并在 `Init` 重置或应用退出时调用 `SetTimer(_connPollTimer, 0)`。
- **来源**: Task 2

#### I11: 全代码库 21 处空 catch 块静默吞没异常

- **位置**: 多文件（`key_recorder.ahk:278,282,287,291`、`joy_hotkey_manager.ahk:184,202,227,271`、`ipc_channel.ahk:122,129,184`、`config_service.ahk:439,444,450,455`、`joy_sender.ahk:36,44`、`skill_manager.ahk:154`、`utils.ahk:49`、`gui_manager.ahk:473`、`webview2_manager.ahk:873,1264`）
- **维度**: 代码质量 / 错误处理（静默吞没异常）
- **模块**: AHK v2 - 跨文件
- **描述**: 全代码库存在 21 处空 catch 块，完全吞没异常。部分空 catch 是合理的「best-effort」清理（如 `config_service.ahk` 的临时文件清理），但轮询方法（`joy_hotkey_manager.ahk` 的 `_Poll`/`_PollPov`/`_PollAxes`/`_PollTriggers`）每 50ms 执行一次，完全静默会掩盖手柄输入子系统的故障。
- **根因**: 开发者为简化 best-effort 清理逻辑使用空 catch，未考虑轮询方法等关键路径的故障可见性需求，缺少诊断输出。
- **修复建议**: 至少使用 `OutputDebug(...)` 输出诊断信息；对于轮询方法，建议增加限速日志（如每秒最多记录一次）。
- **来源**: Task 2

#### I12: skill_group.ahk 复杂单行表达式与定时器引用管理

- **位置**: `domain/skill_group.ahk:783`
- **维度**: 代码质量 / 代码可维护性 + 定时器引用管理
- **模块**: AHK v2 - domain/
- **描述**: `_SendKey` 方法中使用极其复杂的单行三元表达式作为 `SetTimer` 回调，包含闭包捕获 4 个变量、Map.Has 检查、Map 索引比较、三元运算、逗号表达式（Delete + SendInput）。该 `SetTimer` 未将返回的回调引用存入 `_timers` Map，无法被 `_StopGroupExecution` 主动取消。
- **根因**: 为追求单行表达式简洁性，将复杂逻辑压缩进 SetTimer 回调，同时未将定时器引用纳入 _timers Map 管理，牺牲了可维护性和可控性。
- **修复建议**: 重构为闭包函数 `ReleaseKeyLater`，使用 `ObjBindMethod` 绑定参数；或将定时器引用存入 `_timers` Map。
- **来源**: Task 2 & Task 3 均报告

#### I13: webview2_manager.ahk FileRead 未指定 UTF-8 编码

- **位置**: `presentation/webview2_manager.ahk:1182-1183`
- **维度**: 安全性 / 文件 I/O 错误处理 / 编码安全
- **模块**: AHK v2 - presentation/
- **描述**: `_BridgeCompareConfigs` 中的 `FileRead` 调用未指定编码参数。AHK v2 的 `FileRead` 不带第二个参数时使用系统默认 ANSI 代码页读取，而项目所有配置文件均以 UTF-8 编码写入。若备份文件包含非 ASCII 字符（如中文分组名），读取结果会乱码。
- **根因**: 开发者遗漏指定 FileRead 编码参数，依赖 AHK 默认 ANSI 代码页，与项目 UTF-8 配置文件编码不一致。
- **修复建议**: `baseContent := FileRead(absBase, "UTF-8")`。
- **来源**: Task 3

#### I14: gui.ahk Run 调用未对路径参数加引号转义

- **位置**: `gui.ahk:886, 905`
- **维度**: 安全性 / 进程/外部命令安全
- **模块**: AHK v2 - 根目录
- **描述**: `Run("notepad.exe config.json")` 和 `Run("notepad.exe " logFile)` 未对路径参数加引号转义。当 `logFile` 路径包含空格时，notepad 只打开部分路径；更严重的情况下可能触发命令注入。
- **根因**: 开发者未对路径参数进行 shell 安全转义，缺少命令注入防护意识。
- **修复建议**: `Run('notepad.exe "' logFile '"')`。
- **来源**: Task 3

#### I15: config_store.ahk Save 方法未深拷贝配置对象

- **位置**: `infrastructure/config_store.ahk:36-64`
- **维度**: 安全性 / 数据完整性 / 引用安全
- **模块**: AHK v2 - infrastructure/
- **描述**: `ConfigStore.Save` 方法直接保存传入 `config` 对象的引用，未进行深拷贝。对比 `Load` 方法使用 `deepclone` 返回副本，`Save` 方法未对称地使用 `deepclone` 保存。调用方后续修改 `config` 对象会直接影响 `ConfigStore` 内部状态，破坏数据封装性。
- **根因**: Save 方法与 Load 方法不对称——Load 使用 deepclone 返回副本，Save 直接保存引用，未考虑调用方后续修改的隔离需求。
- **修复建议**: `this._groupSettings := deepclone(config["GroupSettings"])`。
- **来源**: Task 3

#### I16: webview2_manager.ahk JSONParser.Parse 后未验证返回类型

- **位置**: `presentation/webview2_manager.ahk:1184-1185`
- **维度**: 安全性 / 输入验证 / 类型安全
- **模块**: AHK v2 - presentation/
- **描述**: `_BridgeCompareConfigs` 中 `JSONParser.Parse` 后未验证返回类型即调用 `.Has()`。若备份文件内容是 JSON 数组或基本类型，调用 `.Has()` 会抛出异常，错误信息不明确。
- **根因**: 缺少对 JSON 解析结果的类型守护，假设输入一定是 Map 类型，未防御 JSON 数组或基本类型输入。
- **修复建议**: 添加 `if !(baseConfig is Map)` 类型守护。
- **来源**: Task 3

#### I17: webview2_manager.ahk 导入配置仅检查字节长度不防内存耗尽

- **位置**: `presentation/webview2_manager.ahk:1057-1058`
- **维度**: 安全性 / 输入验证 / 资源耗尽防护
- **模块**: AHK v2 - presentation/
- **描述**: `_BridgeImportConfig` 仅检查导入数据的字节长度（5MB），未限制解压后的内存使用。5MB 的 JSON 字符串经过 `JSONParser.Parse` 后，在内存中构建的对象图可能是原始字符串的 10-50 倍（50-250MB），导致进程内存暴涨甚至 OOM。
- **根因**: 仅按字符串字节长度限制输入，未考虑 JSON 解析后对象图的内存放大效应，缺少资源耗尽防护。
- **修复建议**: 在 `JSONParser` 中增加对象计数器，或在 `_BridgeImportConfig` 解析后检查 `GroupSettings.Count`，超过阈值拒绝。
- **来源**: Task 3

#### I18: config_validator.ahk 热键验证仅检查长度

- **位置**: `infrastructure/config_validator.ahk:65-66`
- **维度**: 安全性 / 输入验证 / 配置校验
- **模块**: AHK v2 - infrastructure/
- **描述**: 热键验证仅检查长度（≤15 字符），未验证格式合法性。当前验证接受任意 ≤15 字符的字符串，这些字符串在 `SkillManager._BindHotkeys` 调用 `Hotkey()` 时会抛出异常，但分组仍会被创建（热键不生效），用户无法通过 UI 得知热键无效。
- **根因**: 验证器仅做了长度上限检查，未实现热键格式合法性验证，导致无效热键在运行时才暴露。
- **修复建议**: 在 `ConfigValidator._ValidateGroup` 中增加热键格式正则验证。
- **来源**: Task 3

#### I19: webview2_manager.ahk 批量删除配置无事务回滚

- **位置**: `presentation/webview2_manager.ahk:1102-1140`
- **维度**: 安全性 / 数据一致性 / 事务完整性
- **模块**: AHK v2 - presentation/
- **描述**: `_BridgeBatchDeleteGroups` 在批量删除时，先循环删除 `ConfigStore` 中的配置，若中间某次删除失败会 `break` 退出循环，但已删除的分组配置不会回滚。若 `SaveConfig` 失败，返回"已回滚"，但 `ConfigStore._groupSettings` 已被部分修改，导致内存与磁盘状态不一致。
- **根因**: 批量删除操作未实现事务性保证，缺少失败时的状态快照恢复机制，导致内存与磁盘状态不一致。
- **修复建议**: 在删除前快照 `_groupSettings`：`snapshot := deepclone(ConfigStore._groupSettings)`，删除失败或保存失败时恢复快照。
- **来源**: Task 3

#### I20: webview2_manager.ahk 导入配置异常后状态可能不一致

- **位置**: `presentation/webview2_manager.ahk:1054-1070`
- **维度**: 安全性 / 数据一致性 / 异常处理
- **模块**: AHK v2 - presentation/
- **描述**: `_BridgeImportConfig` 在 `ImportGroups` 抛出异常时，临时文件会被清理，但 `ConfigStore` 和 `SkillManager` 状态可能已被部分修改。`GroupService.ImportGroups` 调用 `_ReplaceAllConfig` 会先删除所有现有分组，再保存新配置，再初始化。若初始化抛出异常，回滚本身可能失败，此时用户配置已丢失。
- **根因**: 配置替换流程未在执行前强制创建备份，且回滚本身可能失败，缺少"配置已损坏"的显式告警机制。
- **修复建议**: 在 `_ReplaceAllConfig` 前强制创建备份；回滚失败时向用户显式提示"配置已损坏，请从 backups 目录手动恢复"。
- **来源**: Task 3

#### I21: run_all_tests.ahk 未 #Include tests/ 根目录标准测试模块

- **位置**: `tests/run_all_tests.ahk:1-40`
- **维度**: 测试覆盖 / 测试套件完整性
- **模块**: AHK v2 - tests/
- **描述**: AGENTS.md 指示运行 `tests\run_all_tests.ahk` 执行测试套件，但实际检查发现它只 #Include 了 `AutoHotUnit.ahk`、被测模块和 `test_ahk_executor/` 下 5 个文件，没有 #Include tests/ 根目录下的任何标准测试模块（test_domain/test_infrastructure/test_application 等）。run_all_tests.ahk 转而内联定义了 80 个测试套件，导致两套并行测试体系，维护成本高。
- **根因**: 测试套件演进过程中形成了两套并行测试体系（内联定义与独立文件），未进行统一整合，维护成本累积。
- **修复建议**: 二选一：(a) 将内联测试拆分为独立文件并用 #Include 整合；(b) 将场景式测试迁移为 AutoHotUnitSuite 模式并 #Include。
- **来源**: Task 4

#### I22: AGENTS.md AHK 执行器测试统计 467 与实际不符

- **位置**: `AGENTS.md`「AHK 执行器测试」章节
- **维度**: 测试覆盖 / 文档一致性
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 声称 AHK 执行器测试为「57 套件 / 467 测试」。57 套件完全匹配，但 467 测试与实际不符。test_ahk_executor 下 5 个文件共有 244 个 `Test_` 方法。AGENTS.md 的统计口径不明确，且数字与任何一种统计方式都对不齐。
- **根因**: AGENTS.md 测试统计口径不明确，且数字未随测试演进同步更新，文档漂移。
- **修复建议**: 在 AGENTS.md 中明确测试统计口径（建议统一为「Test_ 方法数」），并更新为准确数字。
- **来源**: Task 4

#### I23: tests/test_joystick.ahk 缺少接管指令

- **位置**: `tests/test_joystick.ahk:1-3`（tests/ 根目录版本）
- **维度**: 测试覆盖 / 测试前置检查流程遵守
- **模块**: AHK v2 - tests/
- **描述**: `tests/test_joystick.ahk`（使用 JoyTestRunner 自定义模式）缺少 `#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`、`OnError` 回调。注意此文件与 `tests/test_ahk_executor/test_joystick.ahk`（完整合规）是两个不同的文件。
- **根因**: 该测试文件使用自定义 JoyTestRunner 模式，未遵循 AGENTS.md 测试文件强制接管指令规范。
- **修复建议**: 补全 #Warn 指令和 OnError 回调，或迁移为 AutoHotUnitSuite 模式。
- **来源**: Task 4

#### I24: 多个测试文件通过静态属性赋值污染全局状态

- **位置**: `tests/test_application.ahk:29-46`、`test_presentation.ahk`、`test_webview2_bridge.ahk`、`test_error_system.ahk:18-20`
- **维度**: 测试覆盖 / 测试隔离性
- **模块**: AHK v2 - tests/
- **描述**: 多个测试文件通过静态属性赋值污染全局状态（test_application 12 处、test_presentation 14 处、test_webview2_bridge 14 处），test_error_system 使用全局变量。这些测试如果被 #Include 到同一进程，前面的测试会污染后面测试的依赖状态。
- **根因**: TestReporter 框架缺少 setup/teardown 钩子，测试通过静态属性共享状态无法自动清理，违反测试隔离性原则。
- **修复建议**: 为 TestReporter 框架添加 setup/teardown 钩子；或迁移为 AutoHotUnitSuite 模式（提供 beforeAll/afterEach）。
- **来源**: Task 4

#### I25: tests/ 根目录 32 个额外文件未在 AGENTS.md 登记

- **位置**: `tests/`（根目录 32 个额外文件）
- **维度**: 测试覆盖 / 测试套件完整性
- **模块**: AHK v2 - tests/
- **描述**: tests/ 根目录存在 32 个未在 AGENTS.md 登记的 .ahk 文件，包括 HTML/WebView2 原型文件 10 个、"full" 版本文件 5 个、集成测试变体 3 个、功能测试 6 个、调试/bug 复现文件 5 个。其中大多数（约 25 个）缺少 OnError 回调，部分缺少完整的 #Warn 指令。
- **根因**: 调试和原型文件在开发过程中累积未清理，且未在 AGENTS.md 文档中登记或归档，缺少测试资产管理规范。
- **修复建议**: 将临时调试文件归档到 `tests/archive/` 或 `tests/debug/` 子目录；评估每个文件的测试价值，删除废弃文件；保留的文件补全接管指令并登记到 AGENTS.md。
- **来源**: Task 4

#### I26: asd-application 的 backup_service 和 recording_service 直接使用 std::fs

- **位置**: `asd-tauri/crates/asd-application/src/backup_service.rs:110,116,166,230,312` 和 `asd-tauri/crates/asd-application/src/recording_service.rs:314`
- **维度**: 架构合规性
- **模块**: Rust - asd-application
- **描述**: `std::fs` 在 asd-application 的生产代码中被 `backup_service.rs`（5 处）和 `recording_service.rs`（1 处）直接使用，超出 AGENTS.md 规定的 ConfigRepository 范围。AGENTS.md 明确规定"std::fs 仅在 asd-application 的 ConfigRepository 中使用"。
- **根因**: 文件 I/O 操作超出 ConfigRepository 范围分散到其他 service，未遵循 AGENTS.md 关于 application 层 I/O 集中化的约束。
- **修复建议**: 将文件 I/O 操作委托给 ConfigRepository 或新建的专用 I/O 模块封装；更新 AGENTS.md 文档明确 application 层 I/O 的允许范围。
- **来源**: Task 5

#### I27: IpcCommand ping/shutdown 在 executor.ahk 无对应 case

- **位置**: `asd-tauri/crates/asd-ipc-protocol/src/command.rs:48-51` vs `asd-tauri/src-tauri/ahk_executor/executor.ahk`
- **维度**: 架构合规性 / IpcCommand 同步性
- **模块**: Rust - asd-ipc-protocol
- **描述**: IpcCommand 枚举有 13 个 variant，其中 `ping` 和 `shutdown` 两个 variant 在 AHK 执行器 `executor.ahk` 的 `case` 分支中无对应处理。AGENTS.md 强制规则要求"新增 IpcCommand variant 必须同步更新 asd-ipc-protocol/src/command.rs 和对应的 AHK 执行器处理逻辑"。
- **根因**: ping/shutdown 可能通过其他层级处理，但 AGENTS.md 要求 IpcCommand variant 同步更新 AHK 执行器逻辑，此同步性未在文档或代码中明确记录。
- **修复建议**: 确认 ping/shutdown 是否通过 `IpcMessage::command()` 发送（如果是则需补充 case）；在 AGENTS.md 或代码注释中明确记录 ping/shutdown 的处理层级。
- **来源**: Task 5

#### I28: AGENTS.md IpcCommand 示例与实际代码完全不符

- **位置**: `AGENTS.md`「数据结构约定」→「Rust」→ IpcCommand 示例
- **维度**: 架构合规性 / 文档漂移
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 展示的 IpcCommand 示例为 `StartGroup { id: usize }`、`StopGroup { id: usize }`、`StopAll`、`UpdateConfig { config: Config }`，与实际代码完全不符。实际代码使用 `ToggleGroup { group_id: String, active: bool, ... }`、`RegisterHotkey`、`EmergencyRelease` 等 variant。文档列出的 4 个示例 variant 在实际代码中一个都不存在，且字段类型也不同。
- **根因**: IpcCommand 枚举经过重构，variant 名称和字段类型已变更，但 AGENTS.md 数据结构约定章节未同步更新。
- **修复建议**: 更新 AGENTS.md 使用实际代码中的 variant 名称和字段类型。
- **来源**: Task 5

#### I29: AGENTS.md 执行模式表格遗漏 3 个 joystick 模式

- **位置**: `AGENTS.md`「支持的执行模式」表格 vs `asd-tauri/crates/asd-domain/src/config.rs:4-8`
- **维度**: 架构合规性 / 文档漂移
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 列出 7 种模式，但实际代码支持 10 种——额外包含 `joystick_periodic`、`joystick_sequence`、`joystick_hold` 3 个模式。这些模式在 `VALID_MODES`、`ModeData` 枚举、`ConfigValidator` 中均有完整实现，但 AGENTS.md 完全未记录。
- **根因**: joystick 模式后增补到代码中，但 AGENTS.md 执行模式表格未同步更新，文档漂移。
- **修复建议**: 在 AGENTS.md 表格中补充 3 个 joystick 模式及其必需字段。
- **来源**: Task 5

#### I30: AGENTS.md 声称 4-crate workspace 实际有 5 个成员

- **位置**: `AGENTS.md`「Rust/Tauri 架构」vs `asd-tauri/Cargo.toml:3-9`
- **维度**: 架构合规性 / 文档漂移
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 多处声称 "4-crate workspace 架构" 和 "4 members"，但 `asd-tauri/Cargo.toml` 的 workspace 实际有 5 个成员（含 `asd-test-harness`），该 crate 完全未在 AGENTS.md 中记录。
- **根因**: asd-test-harness crate 后加入 workspace，但 AGENTS.md 架构描述未同步更新成员数。
- **修复建议**: 更新 AGENTS.md 中所有 "4-crate" / "4 members" 表述为 "5-crate" / "5 members"；补充 asd-test-harness 的定位说明。
- **来源**: Task 5

#### I31: src-tauri 嵌套锁获取与 block_in_place 桥接模式

- **位置**: `asd-tauri/src-tauri/src/lib.rs:390-406`、`asd-tauri/src-tauri/src/bridge.rs:26-120, 151-191`、`asd-tauri/src-tauri/src/lib.rs:335,391,402`
- **维度**: 架构合规性 / 并发安全（已知妥协 #2）
- **模块**: Rust - src-tauri
- **描述**: 存在两个相关问题：(1) `setup_ipc_and_watchdog` 中存在嵌套锁获取（持有 `ipc_manager` 锁的同时获取 `watchdog` 锁），形成锁顺序 `ipc_manager → watchdog`。当前不会死锁（初始化阶段单线程 + 无反向锁顺序），但缺乏文档约束。(2) `IpcBridge` 和 `WatchdogBridge` 使用 `block_in_place + block_on` 模式桥接同步 trait 方法到 async 实现（共 5 处），会阻塞 tokio 工作线程。
- **根因**: 同步 trait 方法桥接到 async 实现需要 block_in_place，且初始化阶段存在嵌套锁获取，缺少锁顺序文档约束。
- **修复建议**: 短期：添加锁顺序注释，保持现状符合妥协 #2 约束。长期：将 `IpcSender`/`ProcessWatcher` trait 改为 async，消除 `block_in_place` 需求。
- **来源**: Task 6 & Task 7 均报告

#### I32: AGENTS.md 声称 19 Tauri commands 实际有 34 个

- **位置**: `AGENTS.md`「Key Files」+ `asd-tauri/src-tauri/src/lib.rs`
- **维度**: 架构合规性 / 文档一致性
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 多处声称"19 Tauri commands + 应用初始化"，但实际 `src/commands/*.rs` 中有 34 个 `#[tauri::command]` 函数（config_cmd 11 + group_cmd 8 + hotkey_cmd 2 + recording_cmd 8 + system_cmd 5）。此外，妥协 #3 描述的 `src-tauri/src/domain/` 和 `application/` 子模块已不存在；Common Patterns 示例返回类型 `String` 实际为 `AppError`。
- **根因**: commands 持续新增但 AGENTS.md Key Files 数量未同步更新；妥协 #3 描述的子模块已不存在；Common Patterns 示例返回类型过期。
- **修复建议**: 更新 AGENTS.md：命令数量改为 34；更新或移除妥协 #3；更新 Common Patterns 示例。
- **来源**: Task 6 & Task 8 均报告

#### I33: named pipe 名称硬编码在两处

- **位置**: `asd-tauri/src-tauri/src/lib.rs:117` 与 `asd-tauri/src-tauri/src/lib.rs:591`
- **维度**: 安全性 / IPC 通信安全
- **模块**: Rust - src-tauri
- **描述**: named pipe 名称 `"asd_ipc"` 以字符串字面量形式硬编码在两处独立调用中——`spawn_ipc_accept_loop` 中的 `create_listener("asd_ipc")` 与 `run()` 中的 `IpcManager::new("asd_ipc")`。两处必须严格一致才能建立通信，但缺乏单一常量约束，任何一处修改而另一处遗漏将导致 IPC 通信静默失败。
- **根因**: IPC 管道名称未提取为常量，分散在两处字面量中，缺少单一数据源约束，存在修改不一致风险。
- **修复建议**: 定义 `const IPC_PIPE_NAME: &str = "asd_ipc";`，将两处替换为该常量引用。
- **来源**: Task 7

#### I34: AppError 序列化丢失类型信息

- **位置**: `asd-tauri/crates/asd-application/src/error.rs:19-26`
- **维度**: 代码质量 / 错误传播链完整性
- **模块**: Rust - asd-application
- **描述**: `AppError` 实现了 `Serialize` trait，但实现方式为 `serializer.serialize_str(&self.to_string())`，即把整个错误序列化为纯字符串。前端通过 `invoke` 收到的错误只是一个字符串消息，丢失了错误变体类型信息（Config / Ipc / GroupNotFound / Validation / Internal）。前端无法基于错误类型进行差异化处理，只能依赖字符串匹配。
- **根因**: Serialize 实现采用简单字符串化方式，未考虑前端差异化错误处理需求，丢失了错误变体类型信息。
- **修复建议**: 将 `Serialize` 实现改为结构化序列化，包含 `kind: &'static str` 和 `message: String` 字段。
- **来源**: Task 7

#### I35: GroupConfig holdTriggers 字段解析失败时静默替换为空向量

- **位置**: `asd-tauri/crates/asd-domain/src/config.rs:337-345`
- **维度**: 安全性 / 输入验证 / 配置序列化兼容性
- **模块**: Rust - asd-domain
- **描述**: `GroupConfig` 的自定义 `Deserialize` 实现中，`holdTriggers` 字段解析失败时通过 `unwrap_or_else` 静默替换为空向量 `Vec::new()`，仅写入 `tracing::warn!` 日志，不返回错误。用户配置文件中 `holdTriggers` 字段格式错误时，配置仍能加载成功，但数据被丢弃，用户不会收到任何提示。
- **根因**: 混淆了"字段缺失"（可选，合理）与"字段存在但格式错误"（应报错）两种情况。
- **修复建议**: 区分两种情况；字段存在但解析失败时返回 `serde::de::Error::custom(...)`；或至少在 `ValidationResult` 中添加警告项。
- **来源**: Task 7

#### I36: JobObject 失败时无僵尸进程补偿机制

- **位置**: `asd-tauri/src-tauri/src/infrastructure/watchdog.rs:170-199`
- **维度**: 安全性 / 进程管理安全 / AHK 子进程隔离
- **模块**: Rust - src-tauri
- **描述**: `attach_child` 方法中，JobObject 创建或进程分配失败时，仅记录 `tracing::warn!` 日志，子进程仍被启动并跟踪。一旦 JobObject 失败，主进程异常退出（panic、kill -9、系统崩溃）时，AHK 子进程将成为僵尸进程持续运行，可能继续发送按键影响用户系统。`graceful_shutdown` 仅能处理正常退出场景。
- **根因**: JobObject 分配失败后仅记录日志继续启动子进程，未考虑主进程异常退出时的子进程清理补偿，缺少 panic hook 和遗留进程检测。
- **修复建议**: 增加补偿机制——在主进程启动时检测并清理遗留的 asd_executor.exe 进程（通过进程名匹配 + PID 文件），并注册 `panic::set_hook` 或 `std::process::abort` 回调尝试终止子进程。
- **来源**: Task 7

#### I37: recording_cmd 命令层缺少输入验证

- **位置**: `asd-tauri/src-tauri/src/commands/recording_cmd.rs:62-68, 92-100, 106-109, 112-117`
- **维度**: 安全性 / 输入验证
- **模块**: Rust - src-tauri
- **描述**: recording_cmd 命令层缺少输入验证。`start_recording` 和 `start_validation` 接收 `group_id: String` 未验证是否为空；`export_recording` 和 `import_recording` 接收 `path: String` 未验证。对比 `config_cmd.rs` 都有 `if xxx.trim().is_empty()` 验证，recording_cmd 的验证不一致。
- **根因**: recording_cmd 命令未与 config_cmd 保持一致的输入验证模式，缺少空字符串和路径验证。
- **修复建议**: 在各命令函数开头添加与 config_cmd 一致的输入验证。
- **来源**: Task 7

#### I38: bridge_tests.rs 未在 test-map.md 登记

- **位置**: `asd-tauri/src-tauri/src/tests/bridge_tests.rs` + `asd-tauri/docs/test-map.md`
- **维度**: 测试覆盖 / 测试数量统计与文档登记
- **模块**: Rust - src-tauri
- **描述**: `bridge_tests.rs` 包含 10 个测试函数（覆盖 IpcBridge、TauriEventBridge、WatchdogBridge），但 `docs/test-map.md` 的"src-tauri 集成测试"表格中完全未列出，导致 test-map.md 测试总数偏低 10 个。
- **根因**: bridge_tests.rs 测试文件创建后未同步登记到 test-map.md，导致测试统计偏低。
- **修复建议**: 在 test-map.md 的 src-tauri 表格中追加 bridge_tests.rs 行。
- **来源**: Task 8

#### I39: watchdog_integration_tests.rs 实际 17 个测试 vs 声明 14 个

- **位置**: `asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`
- **维度**: 测试覆盖 / 测试数量统计
- **模块**: Rust - src-tauri
- **描述**: 实际 17 个测试函数，但 test-map.md 声明 14 个，差 +3。
- **根因**: 测试函数新增后未同步更新 test-map.md 中的数量声明，文档漂移。
- **修复建议**: 更新 test-map.md 中 watchdog_integration_tests.rs 的测试数为 17。
- **来源**: Task 8

#### I40: manifest_helper.rs 是空壳测试

- **位置**: `asd-tauri/src-tauri/tests/manifest_helper.rs`
- **维度**: 测试覆盖 / 测试质量 / 测试有效性
- **模块**: Rust - src-tauri
- **描述**: `manifest_helper.rs` 整个文件内容仅 `#[test] fn test_manifest_helper_smoke() { assert!(true); }`。test-map.md 声称其覆盖"tauri.conf.json manifest 加载冒烟测试"，但实际未读取、解析或验证任何 manifest 文件，是空壳测试（tautology）。
- **根因**: test-manifest feature 废弃后，对应测试未实现真实逻辑或删除，留下 tautology 空壳测试。
- **修复建议**: 实现 manifest 验证逻辑；或删除此空壳测试和 Cargo.toml 中的 `[[test]]` 段。
- **来源**: Task 8

#### I41: AGENTS.md 声称 3 个 fuzz target 实际有 5 个

- **位置**: `AGENTS.md`「关键设计决策」#5 vs `asd-tauri/fuzz/fuzz_targets/`
- **维度**: 架构合规性 / 文档一致性
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md "关键设计决策" 表格 #5 称"3 个 fuzz target"，但实际 `fuzz/Cargo.toml` 注册了 5 个 fuzz target。test-map.md 已正确登记 5 个，但 AGENTS.md 未更新。
- **根因**: fuzz target 后续新增 2 个，test-map.md 已更新但 AGENTS.md 关键设计决策表未同步更新。
- **修复建议**: 更新 AGENTS.md "关键设计决策" #5 为"5 个 fuzz target"。
- **来源**: Task 8

#### I42: bridge.rs TauriEventBridge::emit 完全无单元测试覆盖

- **位置**: `asd-tauri/src-tauri/src/bridge.rs:200-213`（TauriEventBridge 测试）
- **维度**: 测试覆盖 / 覆盖率盲区
- **模块**: Rust - src-tauri
- **描述**: `bridge_tests.rs:200` 的 `test_tauri_event_bridge_emit` 标记为 `#[ignore]`，且函数体仅 `panic!("此测试需要 Tauri AppHandle，无法在纯单元测试环境中运行")`。即 TauriEventBridge 的 `emit()` 方法完全无单元测试覆盖。
- **根因**: emit 方法依赖 Tauri AppHandle 难以在纯单元测试环境构造，测试标记 #[ignore] 且未通过 trait 抽象或 E2E 补充覆盖。
- **修复建议**: 将 emit 逻辑提取为使用 trait 抽象的函数；或在 E2E 测试中通过监听 `window.__TAURI__.event.listen` 验证。
- **来源**: Task 8

#### I43: lib.rs 核心函数无直接测试覆盖

- **位置**: `asd-tauri/src-tauri/src/lib.rs`（27936 bytes）
- **维度**: 测试覆盖 / 覆盖率盲区
- **模块**: Rust - src-tauri
- **描述**: `lib.rs` 是 src-tauri 主 crate 最大的源文件，但 `#[test]`/`#[tokio::test]` 数量为 0。`perform_graceful_shutdown()`、`setup_tray_menu()`、Tauri command 注册逻辑、`run()` 函数均未被直接测试。
- **根因**: lib.rs 中核心函数与 Tauri 框架耦合紧密，未提取为可独立测试的纯逻辑模块，导致测试覆盖盲区。
- **修复建议**: 将 `perform_graceful_shutdown` 等纯逻辑函数提取到独立模块便于测试；对 Tauri command 注册列表添加编译时断言。
- **来源**: Task 8

### 3.3 Minor 级别发现

#### M1: utils.ahk _GetField 隐式依赖 JSONParser

- **位置**: `infrastructure/utils.ahk:44`
- **维度**: 架构合规性 / 代码组织 / 隐式依赖
- **模块**: AHK v2 - infrastructure/
- **描述**: `_GetField` 调用 `JSONParser.Parse(obj)`，但 `utils.ahk` 顶部并未 `#Include "json_parser.ahk"`，依赖 `main.ahk` 已先加载才能工作。
- **根因**: utils.ahk 调用 JSONParser 但未显式 #Include，依赖 main.ahk 加载顺序，缺少模块自包含性。
- **修复建议**: 在 `infrastructure/utils.ahk` 顶部添加 `#Include "json_parser.ahk"`。
- **来源**: Task 1

#### M2: json.ahk 重复定义 _GetField

- **位置**: `json.ahk:1436`
- **维度**: 架构合规性 / 代码组织 / 重复定义
- **模块**: AHK v2 - 根目录
- **描述**: 根目录 `json.ahk:1436` 存在 `static _GetField(obj, field)` 方法定义，与 `infrastructure/utils.ahk:31` 的全局函数命名重复。`json.ahk` 是遗留文件，迁移后未清理。
- **根因**: json.ahk 为遗留文件，_GetField 迁移到 infrastructure/utils.ahk 后未清理旧定义，造成命名重复。
- **修复建议**: 确认 `json.ahk` 是否仍在使用，若已废弃则移至 `tests/legacy/` 或删除；若仍在使用则重命名以避免混淆。
- **来源**: Task 1

#### M3: migration_logger.ahk 隐式依赖 StrJoin

- **位置**: `infrastructure/migration_logger.ahk:41, 43`
- **维度**: 代码质量 / 依赖管理（隐式依赖）
- **模块**: AHK v2 - infrastructure/
- **描述**: 使用 `StrJoin` 函数但未 `#Include "utils.ahk"`，靠 `main.ahk` 的加载顺序在运行时解析到全局 `StrJoin`。
- **根因**: 使用 StrJoin 函数未显式 #Include utils.ahk，依赖运行时全局解析，模块自包含性不足。
- **修复建议**: 补充 `#Include "utils.ahk"`。
- **来源**: Task 2

#### M4: webview2_manager.ahk _CopyProp 调用代码重复

- **位置**: `presentation/webview2_manager.ahk:519-540`
- **维度**: 代码质量 / 代码重复
- **模块**: AHK v2 - presentation/
- **描述**: 连续 12 次 `_CopyProp` 调用，模式高度重复，未参数化为列表遍历。
- **根因**: 属性复制逻辑未参数化为列表遍历，连续 12 次重复调用，缺少重构意识。
- **修复建议**: 提取属性名数组，用循环替代。
- **来源**: Task 2

#### M5: webview2_manager.ahk OnEvent case 逻辑重复

- **位置**: `presentation/webview2_manager.ahk:141-166`
- **维度**: 代码质量 / 代码重复
- **模块**: AHK v2 - presentation/
- **描述**: `OnEvent` 方法中多个 case 的处理逻辑完全相同（防抖定时器设置），但分别书写了两遍。
- **根因**: 防抖定时器设置逻辑在多个 case 中重复书写，未提取为辅助方法或合并 case。
- **修复建议**: 合并 case 或提取 `_ScheduleDebouncedPush()` 辅助方法。
- **来源**: Task 2

#### M6: config_service.ahk 等待定时器停止循环代码重复

- **位置**: `application/config_service.ahk:138-150` 与 `196-208`
- **维度**: 代码质量 / 代码重复
- **模块**: AHK v2 - application/
- **描述**: `HotReload` 与 `_Rollback` 中存在几乎相同的"等待定时器停止"循环。
- **根因**: HotReload 与 _Rollback 中等待定时器停止逻辑重复，未提取为通用 _WaitForTimersDrain 方法。
- **修复建议**: 提取 `_WaitForTimersDrain(timeoutMs := 500)` 静态方法。
- **来源**: Task 2

#### M7: config_store.ahk _RepairEmptyArrays 方法复杂度高

- **位置**: `infrastructure/config_store.ahk:154-221`
- **维度**: 代码质量 / 代码复杂度
- **模块**: AHK v2 - infrastructure/
- **描述**: `_RepairEmptyArrays` 方法约 67 行，7 个 case 分支内部逻辑高度相似（检查数组为空 → 用默认值填充），未参数化。
- **根因**: 7 个 case 分支采用相似的手动检查+填充模式，未参数化为数据驱动的统一处理。
- **修复建议**: 重构为数据驱动：定义 `Map(mode, Map(field, defaultField))` 结构，统一遍历处理。
- **来源**: Task 2

#### M8: webview2_manager.ahk 哈希方式脆弱

- **位置**: `presentation/webview2_manager.ahk:127-130`
- **维度**: 代码质量 / 代码可维护性 / 性能
- **模块**: AHK v2 - presentation/
- **描述**: 用 JSON 字符串拼接作为状态变更指纹：`currentKey := debugInfo . groupList`。字符串拼接的时间复杂度为 O(n)，且可能产生哈希碰撞，跳过必要的更新。
- **根因**: 使用 JSON 字符串拼接作为状态指纹，时间复杂度 O(n) 且可能哈希碰撞，未采用轻量指纹或哈希算法。
- **修复建议**: 改用轻量指纹（如 `SkillManager.GetActiveCount() . "|" . SkillManager.Groups.Count`），或对拼接结果做哈希。
- **来源**: Task 2 & Task 3 均报告

#### M9: config_store.ahk 默认热键大小写不一致

- **位置**: `infrastructure/config_store.ahk:293`
- **维度**: 代码质量 / 命名规范（大小写不一致）
- **模块**: AHK v2 - infrastructure/
- **描述**: 默认控制热键使用小写 `"f12"`，对比同项目其他位置均用 `"F12"`（大写）。
- **根因**: 默认热键 "f12" 与项目其他位置的 "F12" 大小写不一致，缺少命名规范统一约束。
- **修复建议**: 统一为 `"F12"`。
- **来源**: Task 2

#### M10: webview2_manager.ahk 脆弱的 JSON 检测

- **位置**: `presentation/webview2_manager.ahk:339`
- **维度**: 代码质量 / 代码可维护性
- **模块**: AHK v2 - presentation/
- **描述**: 用首字符判断字符串是否为 JSON：`isJson := InStr(result, "{") = 1 || InStr(result, "[") = 1`，会误判以 `{` 或 `[` 开头的普通字符串。
- **根因**: 用首字符判断是否为 JSON，会误判以 { 或 [ 开头的普通字符串，Bridge 协议层未区分原始字符串与 JSON 序列化结果。
- **修复建议**: Bridge 协议层应区分"原始字符串"与"JSON 序列化结果"。
- **来源**: Task 2

#### M11: skill_group.ahk Dispose 方法动态属性检查

- **位置**: `domain/skill_group.ahk:710-719`
- **维度**: 代码质量 / 代码可维护性
- **模块**: AHK v2 - domain/
- **描述**: `Dispose` 方法用 5 处 `if this.HasProp(...)` 检查属性是否存在，因为部分实例属性按模式在 `_SetupMode` 中条件初始化。
- **根因**: 实例属性按模式条件初始化，Dispose 时需动态检查存在性，未在 __New 中预初始化所有可能的 Map 属性。
- **修复建议**: 在 `__New` 中预先初始化所有可能的 Map 属性为空 Map，消除 `HasProp` 检查。
- **来源**: Task 2

#### M12: gui_manager.ahk catch 块缩进不一致

- **位置**: `presentation/gui_manager.ahk:64-67`
- **维度**: 代码质量 / 代码风格
- **模块**: AHK v2 - presentation/
- **描述**: `Show` 方法的 catch 块缩进比周围代码多 2 个空格（6 空格 vs 4 空格）。
- **根因**: catch 块缩进比周围代码多 2 空格，未遵循统一的 4 空格缩进规范。
- **修复建议**: 统一为 4 空格缩进。
- **来源**: Task 2

#### M13: 多文件 3 处手动插入排序重复

- **位置**: `presentation/webview2_manager.ahk:543-567`、`infrastructure/backup_core.ahk:156-169`、`infrastructure/utils.ahk:94-104`
- **维度**: 代码质量 / 代码重复
- **模块**: AHK v2 - 跨文件
- **描述**: 手动插入排序实现重复出现 3 次，几乎相同。
- **根因**: 手动插入排序实现重复出现 3 次，未提取为通用 _SortByField 工具函数。
- **修复建议**: 在 `infrastructure/utils.ahk` 提取通用 `_SortByField(arr, key, descending := true)` 函数。
- **来源**: Task 2

#### M14: AGENTS.md Key Files 列出的外围模块不存在

- **位置**: `AGENTS.md`「Key Files」章节
- **维度**: 架构合规性 / 文档与代码不一致
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 列出的根目录外围模块 `equipment_recognizer.ahk`、`ocr.ahk`、`joystick_tester.ahk` 在项目中实际不存在，可能已移除或迁移至 `asd-tauri/src-tauri/ahk_executor/`，但 AGENTS.md 未同步更新。
- **根因**: equipment_recognizer.ahk 等外围模块已移除或迁移，但 AGENTS.md Key Files 表格未同步更新。
- **修复建议**: 更新 AGENTS.md「Key Files」表格，移除不存在的条目。
- **来源**: Task 2 & Task 3 均报告

#### M15: webview2_manager.ahk 重复解析自己刚序列化的 JSON

- **位置**: `presentation/webview2_manager.ahk:131-135`
- **维度**: 代码质量 / 性能
- **模块**: AHK v2 - presentation/
- **描述**: `_PushStateUpdate` 中 Bridge 方法返回 JSON 字符串后，又解析回来再重新组合再序列化，导致"序列化 → 解析 → 重新组合 → 序列化"的冗余流程。每 2 秒触发一次。
- **根因**: _PushStateUpdate 中 Bridge 方法返回 JSON 字符串后又解析重新组合，缺少返回对象的 _Internal 版本，造成冗余序列化流程。
- **修复建议**: 增加 Bridge 方法的 `_Internal` 版本返回对象。
- **来源**: Task 3

#### M16: webview2_manager.ahk 临时文件命名碰撞风险

- **位置**: `presentation/webview2_manager.ahk:1059`
- **维度**: 安全性 / 临时文件管理
- **模块**: AHK v2 - presentation/
- **描述**: 使用 `Random(1000, 9999)` 生成临时文件名后缀，范围仅 9000 个值，`A_Now` 精度到秒，1 秒内多次导入可能碰撞。
- **根因**: 临时文件名使用 Random(1000, 9999) + A_Now 精度到秒，范围小且 1 秒内多次导入可能碰撞，未使用毫秒或更大随机空间。
- **修复建议**: 使用 `A_Now A_MSec "_" Random(1, 999999)` 或 `FileOpen` 的独占模式。
- **来源**: Task 3

#### M17: ipc_channel.ahk DirCreate 错误处理不完整

- **位置**: `infrastructure/ipc_channel.ahk:34-44`
- **维度**: 安全性 / 文件 I/O 错误处理
- **模块**: AHK v2 - infrastructure/
- **描述**: `Init` 方法中 `DirCreate` 未包裹独立 try-catch。若目录创建失败，`initialized` 已被设为 true（line 32），后续 `Send`/`Emit` 会因目录不存在而失败，错误信息不明确。
- **根因**: initialized 标志在 DirCreate 之前设置，且 DirCreate 未包裹 try-catch，目录创建失败时错误信息不明确。
- **修复建议**: 将 `initialized := true` 移到所有初始化步骤成功后；添加 try-catch 记录明确错误。
- **来源**: Task 3

#### M18: config_service.ahk FileCopy 无 catch 静默吞掉异常

- **位置**: `application/config_service.ahk:44`
- **维度**: 安全性 / 文件 I/O 错误处理
- **模块**: AHK v2 - application/
- **描述**: `LoadConfig` 中 `try FileCopy(...)` 无 `catch`，若 `FileCopy` 失败异常被静默吞掉，`config.json.bak` 不会被创建。
- **根因**: try FileCopy 无 catch 块，异常被静默吞掉，备份文件创建失败不会被发现。
- **修复建议**: 添加 `catch as e` 记录 WARNING 日志。
- **来源**: Task 3

#### M19: json_parser.ahk ParseNumber 未检查整数范围

- **位置**: `infrastructure/json_parser.ahk:298-340`
- **维度**: 安全性 / 输入验证 / 数值范围
- **模块**: AHK v2 - infrastructure/
- **描述**: `ParseNumber` 解析数字时未检查整数范围。超过 64 位整数范围的数字会转用 `Float()`，损失精度。配置文件中的 `intervals`、`delays` 字段若被恶意构造为超大数，会导致定时器间隔错误。
- **根因**: ParseNumber 解析数字时未检查整数范围，超大数会转 Float 损失精度，缺少数值上限验证。
- **修复建议**: 在 `ConfigValidator` 中增加数值上限检查。
- **来源**: Task 3

#### M20: tests/ 无独立 fixture 目录

- **位置**: `tests/`（整个目录）
- **维度**: 测试覆盖 / fixture 管理
- **模块**: AHK v2 - tests/
- **描述**: tests/ 下没有独立的 fixture 目录，测试数据大多硬编码在测试文件中。对比 Rust/Tauri 部分有规范的 `asd-tauri/tests/fixtures/` 目录。
- **根因**: AHK v2 测试数据硬编码在测试文件中，未建立独立的 fixture 目录管理机制，与 Rust/Tauri 部分规范不一致。
- **修复建议**: 创建 `tests/fixtures/` 目录，提取重复使用的测试数据；在 AGENTS.md 中补充 AHK v2 的 fixture 管理规范。
- **来源**: Task 4

#### M21: test_error_system.ahk 使用非标准 OnError 模式

- **位置**: `tests/test_error_system.ahk:26`
- **维度**: 测试覆盖 / 测试前置检查流程遵守
- **模块**: AHK v2 - tests/
- **描述**: 使用 `OnError(ErrorSystem_HandleError, -1)` 而非标准模板要求的 FileAppend 模式。虽然在该测试场景下合理（测试的就是 ErrorSystem），但偏离标准模板。
- **根因**: 该测试场景合理使用 OnError(ErrorSystem_HandleError, -1) 测试 ErrorSystem 本身，但未在文件顶部添加注释说明偏离原因。
- **修复建议**: 在文件顶部添加注释说明偏离原因。此为合理偏差。
- **来源**: Task 4

#### M22: AHK v2 测试存在 4 种不统一的测试模式

- **位置**: `tests/`（整体）
- **维度**: 测试覆盖 / 测试质量
- **模块**: AHK v2 - tests/
- **描述**: AHK v2 测试存在 4 种不统一的测试模式：AutoHotUnitSuite 模式、TestReporter 场景式模式、JoyTestRunner 自定义模式、函数式全局变量模式。导致维护者需要理解 4 套不同的断言/报告机制。
- **根因**: 测试体系演进过程中形成 AutoHotUnitSuite、TestReporter、JoyTestRunner、函数式全局变量 4 种模式，未统一为最成熟的 AutoHotUnitSuite。
- **修复建议**: 统一为 AutoHotUnitSuite 模式（最成熟，提供 beforeAll/beforeEach/afterEach/afterAll 钩子）。
- **来源**: Task 4

#### M23: run_all_tests.ahk 文件过大

- **位置**: `tests/run_all_tests.ahk`（68397 bytes，约 1800 行）
- **维度**: 测试覆盖 / 测试质量
- **模块**: AHK v2 - tests/
- **描述**: 单个文件内联定义了 80 个测试套件类，违反单一职责原则，难以维护和代码审查。
- **根因**: 单个文件内联定义 80 个测试套件类，违反单一职责原则，未按模块拆分为独立文件。
- **修复建议**: 将 80 个套件按模块拆分为独立文件，run_all_tests.ahk 仅负责 #Include 和运行调度。
- **来源**: Task 4

#### M24: AGENTS.md 声称 ConfigValidator 213 tests 实际仅 48 个

- **位置**: `AGENTS.md`「Key Files」→ `asd-domain/src/validator.rs | ConfigValidator（213 tests）`
- **维度**: 架构合规性 / 文档准确性
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md Key Files 表格声称 `ConfigValidator（213 tests）`，但实际 `validator.rs` 中仅有 48 个 `#[test]` 函数。AGENTS.md "测试覆盖" 章节又称 "asd-domain 125" 个测试（两者已互相矛盾：213 > 125）。
- **根因**: AGENTS.md Key Files 中 validator.rs 测试数 213 与实际 48 不符，且与同文档"asd-domain 125"互相矛盾，文档漂移严重。
- **修复建议**: 更正 AGENTS.md Key Files 中 validator.rs 的测试数量。
- **来源**: Task 5

#### M25: validator.rs is_none() 冗余检查

- **位置**: `asd-tauri/crates/asd-domain/src/validator.rs:184-185`
- **维度**: 代码质量
- **模块**: Rust - asd-domain
- **描述**: `validate_cross_fields` 方法中存在冗余的 None 检查：`group.hold_keys.is_none() || group.hold_keys.as_ref().is_none_or(|k| k.is_empty())`。`Option::is_none_or` 在 Option 为 None 时已返回 true，前置的 `is_none()` 是冗余的。
- **根因**: validate_cross_fields 中 is_none() || is_none_or(...) 表达式前置 is_none() 冗余，未利用 is_none_or 在 None 时已返回 true 的特性。
- **修复建议**: 简化为 `group.hold_keys.as_ref().is_none_or(|k| k.is_empty())`。
- **来源**: Task 5

#### M26: scheduler.rs SkillManager.ipc_sender 字段为死代码

- **位置**: `asd-tauri/crates/asd-application/src/scheduler.rs:14-15`
- **维度**: 代码质量
- **模块**: Rust - asd-application
- **描述**: `SkillManager` 结构体的 `ipc_sender` 字段被标记为 `#[allow(dead_code)]`，实际上该字段确实从未通过 `self.ipc_sender` 使用。该结构体已标记 `#[deprecated(since = "3.1.0")]`。
- **根因**: SkillManager 已标记 #[deprecated(since = "3.1.0")]，ipc_sender 字段从未通过 self.ipc_sender 使用，但未在清理时移除。
- **修复建议**: 可在下次清理时移除 `ipc_sender` 字段及其 `#[allow(dead_code)]` 标注。
- **来源**: Task 5

#### M27: recording_service.rs 硬编码模式列表

- **位置**: `asd-tauri/crates/asd-application/src/recording_service.rs:249-250`
- **维度**: 代码质量 / 可维护性
- **模块**: Rust - asd-application
- **描述**: `validate_recording_data` 函数中硬编码了模式列表，与 `VALID_MODES` 存在重复维护风险。
- **根因**: validate_recording_data 中硬编码模式列表，与 VALID_MODES 存在重复维护风险，未在 asd-domain 集中维护模式分类。
- **修复建议**: 在 asd-domain 中定义模式分类辅助函数，集中维护模式特征映射。
- **来源**: Task 5

#### M28: AppError 缺少 From&lt;std::io::Error&gt; 实现

- **位置**: `asd-tauri/crates/asd-application/src/error.rs:5-17`
- **维度**: 代码质量 / 错误处理
- **模块**: Rust - asd-application
- **描述**: `AppError` 实现了 `From<IpcError>` 但未实现 `From<std::io::Error>`。文件 I/O 错误通过 `format!("...{e}")` 转为 String，原始 `io::Error` 的类型信息（ErrorKind）丢失。对比 `IpcError` 实现了 `From<std::io::Error>` 并区分 `PipeBroken` 和 `IoError`。
- **根因**: AppError 实现 From<IpcError> 但未实现 From<std::io::Error>，文件 I/O 错误通过 format! 转为 String 丢失 ErrorKind 信息，与 IpcError 处理不一致。
- **修复建议**: 为 AppError 增加 `Io(#[source] std::io::Error)` 变体或使用 `#[from]` 派生。
- **来源**: Task 5

#### M29: state.rs set_emergency_mode/set_hold_mode_enabled pub 可见性问题

- **位置**: `asd-tauri/crates/asd-application/src/state.rs:145-148, 159-162`
- **维度**: 代码质量 / 可见性设计
- **模块**: Rust - asd-application
- **描述**: 这两个方法为 `pub` 可见性，但文档注释明确标注"仅用于测试代码。生产代码应使用 system_cmd"。这两个方法绕过了命令层的 `compare_exchange` 保护，直接 `store` 写入。
- **根因**: 两个方法为 pub 可见性但文档注释标注"仅用于测试代码"，绕过了命令层的 compare_exchange 保护，可见性设计宽松。
- **修复建议**: 考虑改为 `#[cfg(test)]` 或 `pub(crate)` 并在测试模块中通过 trait 暴露。
- **来源**: Task 5

#### M30: state.rs watchdog 字段标注 #[allow(dead_code)] 但实际被使用

- **位置**: `asd-tauri/crates/asd-application/src/state.rs:89-90`
- **维度**: 代码质量
- **模块**: Rust - asd-application
- **描述**: `AppState` 的 `watchdog` 字段被标记为 `#[allow(dead_code)]`，但该字段实际在 `reset_watchdog()` 方法中通过 `self.watchdog.reset()` 使用。标注与实际使用不符。
- **根因**: watchdog 字段被标记 #[allow(dead_code)] 但实际在 reset_watchdog() 中使用，标注与实际使用不符，可能是历史遗留。
- **修复建议**: 移除 `#[allow(dead_code)]` 标注，或添加注释说明为何需要该标注。
- **来源**: Task 5

#### M31: lib.rs setup_ipc_callbacks 直接调用 IpcManager

- **位置**: `asd-tauri/src-tauri/src/lib.rs:214-358`
- **维度**: 架构合规性 / IPC 通信规则
- **模块**: Rust - src-tauri
- **描述**: AGENTS.md 规则要求"IPC 通信必须通过 `IpcSender` trait，禁止直接调用 `IpcManager`"。但 `setup_ipc_callbacks` 函数接收 `ipc_manager: &IpcManager`（具体类型），直接调用其方法。这些是初始化阶段的回调注册，不属于"IPC 通信"范畴，而是基础设施配置。
- **根因**: setup_ipc_callbacks 接收 IpcManager 具体类型并直接调用方法，属于初始化阶段的基础设施配置而非 IPC 通信，依赖反转在此场景过度抽象。
- **修复建议**: 可接受现状：初始化代码需要操作具体类型，依赖反转在此场景过度抽象。
- **来源**: Task 6

#### M32: config_repository.rs load_from_file 错误传播不完整

- **位置**: `asd-tauri/crates/asd-application/src/config_repository.rs:67-95`
- **维度**: 代码质量 / 错误传播链完整性
- **模块**: Rust - asd-application
- **描述**: `load_from_file` 方法在配置文件解析失败或读取失败时，返回 `Config::default()` 而非错误。用户可能在使用默认配置的情况下不知情。`load_from_file_checked` 方法能正确传播错误，但 `load_from_file` 作为公开方法仍可能被误用。
- **根因**: load_from_file 在解析或读取失败时返回 Config::default() 而非错误，用户可能不知情使用默认配置，缺少 deprecated 引导。
- **修复建议**: 为 `load_from_file` 添加 `#[deprecated]` 注解，引导使用 `load_from_file_checked`。
- **来源**: Task 7

#### M33: lib.rs Arc::get_mut expect 脆弱假设

- **位置**: `asd-tauri/src-tauri/src/lib.rs:375`
- **维度**: 代码质量 / 健壮性
- **模块**: Rust - src-tauri
- **描述**: `init_app_state` 中使用 `Arc::get_mut(&mut app_state).expect(...)` 获取可变引用。当前在 `setup` 阶段调用，`Arc::get_mut` 必定返回 `Some`。但这是脆弱的隐式假设——如果未来代码重构在 `init_app_state` 之前将 `app_state` 的克隆传递给其他组件，将 panic。
- **根因**: init_app_state 使用 Arc::get_mut(&mut app_state).expect(...) 获取可变引用，依赖 setup 阶段 Arc 单所有权的隐式假设，未来重构可能导致 panic。
- **修复建议**: 将 `config_path` 作为 `AppState::new` 的参数传入，消除对 `Arc::get_mut` 的依赖。
- **来源**: Task 7

#### M34: group_cmd.rs toggle_group/delete_group 输入验证不一致

- **位置**: `asd-tauri/src-tauri/src/commands/group_cmd.rs:84-89, 104-110`
- **维度**: 安全性 / 输入验证
- **模块**: Rust - src-tauri
- **描述**: `toggle_group` 和 `delete_group` 接收 `group_id: String` 未在 command 层验证是否为空，而同文件的 `get_group_detail` 有显式空字符串验证。
- **根因**: toggle_group 和 delete_group 未在 command 层验证 group_id 是否为空，与同文件 get_group_detail 的验证模式不一致。
- **修复建议**: 在 `toggle_group` 和 `delete_group` command 函数开头添加空字符串验证，与 `get_group_detail` 保持一致。
- **来源**: Task 7

#### M35: e2e-test-report.md 时效性过时

- **位置**: `asd-tauri/e2e/docs/e2e-test-report.md`
- **维度**: 测试覆盖 / 测试报告时效性
- **模块**: Rust - src-tauri（E2E）
- **描述**: 报告记录的运行结果为 2026-06-28，通过率 20/53 = 37.7%。但 `e2e-known-issues.md`（更新于 2026-06-29）明确记载"9/9 E2E 测试全部通过"，即实际 53/53 全部通过，但报告未更新。
- **根因**: e2e-test-report.md 记录的 2026-06-28 结果（37.7% 通过率）未更新，而 e2e-known-issues.md（2026-06-29）已记载全部通过，报告时效性滞后。
- **修复建议**: 重新运行 `npm test` 生成最新报告，或手动更新。
- **来源**: Task 8

#### M36: AGENTS.md E2E 测试文档路径不准确

- **位置**: `AGENTS.md`「E2E 测试」章节
- **维度**: 测试覆盖 / 文档一致性 / 路径准确性
- **模块**: 文档（AGENTS.md）
- **描述**: AGENTS.md 引用的 E2E 测试文档路径不准确。声称 `docs/e2e-test-report.md`、`docs/e2e-test-checklist.md`、`docs/e2e-known-issues.md`，但实际 `e2e-test-checklist.md` 不存在，其他两个文档在 `asd-tauri/e2e/docs/` 下。
- **根因**: AGENTS.md 引用的 E2E 文档路径前缀错误（docs/ vs asd-tauri/e2e/docs/），且引用了不存在的 e2e-test-checklist.md，文档未随目录结构调整。
- **修复建议**: 更新 AGENTS.md 中路径为 `asd-tauri/e2e/docs/` 前缀；删除对不存在的 `e2e-test-checklist.md` 的引用。
- **来源**: Task 8

#### M37: smoke.spec.js 无 E2E 编号

- **位置**: `asd-tauri/e2e/specs/smoke.spec.js`
- **维度**: 测试覆盖 / E2E 编号规范
- **模块**: Rust - src-tauri（E2E）
- **描述**: AGENTS.md 强制规范"测试用例编号格式：`E2E-<SUITE>-NNN`"。8/9 spec 文件遵守此规范，但 `smoke.spec.js` 的唯一用例无 `E2E-SMOKE-001` 编号。
- **根因**: smoke.spec.js 唯一用例未遵循 AGENTS.md 强制规范"E2E-<SUITE>-NNN"编号格式，遗漏添加 E2E-SMOKE-001。
- **修复建议**: 在 it 描述前加 `E2E-SMOKE-001:`。
- **来源**: Task 8

#### M38: watchdog_integration_tests.rs 12 个测试标记 #[ignore] 未在文档说明

- **位置**: `asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`
- **维度**: 测试覆盖 / 测试可发现性
- **模块**: Rust - src-tauri
- **描述**: 17 个测试中 12 个标记 `#[ignore = "涉及真实进程管理且需要时序协调，需手动运行"]`，仅 5 个默认运行。test-map.md 未说明此 ignore 状态。
- **根因**: 17 个测试中 12 个标记 #[ignore] 需手动运行，但 test-map.md 未说明此 ignore 状态，影响测试可发现性。
- **修复建议**: 在 test-map.md 追加备注"（12 个 `#[ignore]`，需 `--ignored` 手动运行）"。
- **来源**: Task 8

#### M39: E2E 测试 binary 缺失时 8 个 spec 未正确 skip

- **位置**: `asd-tauri/e2e/wdio.conf.js:80-200` + 9 个 spec 文件
- **维度**: 测试覆盖 / E2E 测试隔离性
- **模块**: Rust - src-tauri（E2E）
- **描述**: AGENTS.md 强制规范"binary 缺失时所有测试 skip（不 fail）"。但实际只有 `smoke.spec.js` 有显式 skip 逻辑，其他 8 个 spec 在 binary 缺失时会因 WebDriver 会话建立失败而 fail。
- **根因**: 仅 smoke.spec.js 实现了 binary 缺失 skip 逻辑，其他 8 个 spec 未在 wdio.conf.js before 钩子中统一封装 skip 检查。
- **修复建议**: 在 `wdio.conf.js` 的 `before` 钩子中检查 binary 存在性，不存在则 `this.skip()`。
- **来源**: Task 8

#### M40: ipc_tests.rs 测试隔离性潜在风险

- **位置**: `asd-tauri/src-tauri/src/tests/ipc_tests.rs`
- **维度**: 测试覆盖 / 测试隔离性
- **模块**: Rust - src-tauri
- **描述**: 26 个测试中 18 个标记 `#[serial]`，串行执行避免 named pipe 并发冲突。但 8 个非 serial 测试与 serial 测试之间可能存在隐式依赖；`unique_pipe_name("ping")` 等使用固定字符串后缀，若并发运行多个 test binary 实例仍可能碰撞。
- **根因**: 26 个测试中 8 个非 serial 测试与 serial 测试可能存在隐式依赖，且 unique_pipe_name 使用固定字符串后缀在并发多实例时可能碰撞。
- **修复建议**: 将所有 ipc_tests 标记为 `#[serial]`；或在 `unique_pipe_name` 中加入 `process::id()` 前缀。
- **来源**: Task 8

#### M41: state.rs 实际 36 个测试 vs test-map.md 声明 35

- **位置**: `asd-tauri/crates/asd-application/src/state.rs`
- **维度**: 测试覆盖 / 测试数量统计
- **模块**: Rust - asd-application
- **描述**: state.rs 实际 36 个 `#[test]`/`#[tokio::test]`，test-map.md 声明 35，差 +1。
- **根因**: state.rs 测试新增后未同步更新 test-map.md 中的数量声明（35 vs 实际 36），文档漂移。
- **修复建议**: 更新 test-map.md 中 state.rs 的测试数为 36，asd-application 小计为 176，总计为 519。
- **来源**: Task 8

---

## 四、审查亮点（无问题声明汇总）

以下方面经审查未发现问题，代码质量良好：

### 4.1 AHK v2 部分

1. **箭头函数块体陷阱**：全代码库搜索 `=>\s*\{` 模式，0 处匹配。所有箭头函数均使用表达式体或逗号表达式，符合 AGENTS.md 要求。
2. **字符串拼接花括号陷阱**：未发现危险拼接模式。WebView2 相关 JS 字符串均使用单引号字符串或 `Format()`。
3. **`Mod(A_TickCount, interval)` 周期性触发陷阱**：0 处匹配。所有周期性按键均使用独立触发时间。
4. **GUI 控件位置参数无引号**：0 处匹配。所有控件位置参数均用双引号包围。
5. **Button 控件误用 `.Value`**：0 处匹配。
6. **WebView2 通信架构**：严格遵守 postMessage 双向通信模式；无 `AddHostObjectToScript` sync 代理；`ExecuteScriptAsync` 仅用于同步 JS 函数。
7. **Map.Delete 前置检查**：所有 38 处 `.Delete()` 调用均遵循"先 Has 检查"规范。
8. **定时器引用管理**：`skill_manager.ahk` 的 `_timers` Map 正确存储所有分组执行定时器引用，停止时正确取消，`OnExit` 遍历取消所有定时器，`_CleanupOrphanTimers` 定期清理孤儿定时器。
9. **领域层无 I/O 泄漏**：`domain/` 目录下所有文件无任何 I/O 操作。
10. **ErrorSystem.LogError 在 domain 层的使用**：仅调用 `LogError` 方法，符合妥协 #1 约束。
11. **模块间无循环依赖**：基于 `#Include` 关系构建的有向图为 DAG。
12. **JSON 解析安全**：`json_parser.ahk` 设置了 `MAX_PARSE_DEPTH = 256` 和 `MAX_LOOP_ITERATIONS = 100000` 双重保护。
13. **错误处理体系**：`ErrorSystem` + `OnError` 回调 + `try-catch` 普遍覆盖 + `JSONLogger` 结构化日志，质量高。

### 4.2 Rust/Tauri 部分

14. **纯逻辑 crate 无禁用依赖**：asd-domain、asd-ipc-protocol、asd-application 的 Cargo.toml 均无 tokio/tauri/interprocess/windows 依赖。
15. **纯逻辑 crate 无 unsafe 代码**：三个 crate 的 src/ 下所有 .rs 文件均无 unsafe 代码，满足 Miri 验证前提。
16. **无 I/O 泄漏到 asd-domain 和 asd-ipc-protocol**：两个 crate 的 src/ 下无 std::fs 使用。
17. **无循环依赖**：依赖链单向（application → domain → ipc-protocol）。
18. **trait 默认实现**：IpcSender 的 `send_and_wait`/`send_message` 有默认实现；ProcessWatcher 的 `reset` 有默认实现。符合"新增 trait 方法必须提供默认实现"规则。
19. **thiserror 使用**：`IpcError` 和 `AppError` 均使用 `#[derive(Debug, thiserror::Error)]`。
20. **34 个 Tauri command 全部正确标注** `#[tauri::command]` 并在 `invoke_handler!` 中注册，无遗漏。
21. **tracing 日志使用**：全部使用 `tracing::info!/warn!/error!/debug!`，无 `log::` 使用。
22. **生产代码 unwrap/expect 使用极为克制**：几乎全部出现在 `#[cfg(test)]` 模块中。
23. **IPC 通信安全**：named pipe 路径一致；认证机制完整（首条消息必须是 auth 类型且 token 匹配）；消息大小限制 64KB；指数退避防认证失败洪泛；pending response 定期清理。
24. **ProcessWatchdog 进程管理**：JobObject 使用 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`；`CREATE_NO_WINDOW` 避免弹出控制台；三阶段优雅关机（IPC shutdown → WM_CLOSE → 强制 kill）。
25. **心跳超时匹配**：Rust 端 ~6s 判定 Hung，AHK 端 5s 断开，时间窗口合理。
26. **并发安全**：锁顺序一致（ipc_manager → watchdog）；`block_in_place` 持锁期间无 `.await`；`shutting_down` 标志抑制不必要的回调；关机保护 `compare_exchange` 防重复关机。
27. **unsafe 代码合规性**：`src-tauri` 中的 unsafe 全部集中在 `watchdog.rs`，所有 `unsafe impl Send/Sync` 都有详细的 SAFETY 注释。`RawBoxGuard` 采用 RAII 模式防止内存泄漏。
28. **配置序列化兼容性**：`Config` 结构体的 serde 属性与 AHK 端 config.json 格式完全匹配。
29. **IPC 边界处理**：`MAX_MESSAGE_SIZE = 64KB` 限制；超大消息有 1MB 残余数据丢弃机制防止 OOM；`MAX_DISCARD_SIZE` 限制消耗量。
30. **E2E 测试数量与结构**：9 suite / 53 用例，与 AGENTS.md 完全一致；全部使用 ESM 语法；25 处调用 `appendKnownIssue`。
31. **基准测试**：7 个 criterion bench，与声明一致，目标明确。
32. **模糊测试**：5 个 fuzz target 覆盖 Config、IpcCommand、IpcMessage、HotkeyMerger 关键反序列化路径。

---

## 五、改进建议优先级排序

### 5.1 立即修复（Critical）

1. **C3 - 移除 WebView2 远程调试端口**：删除 `webview2_manager.ahk:63` 的 `EnvSet` 调用，或改为仅在非编译模式下开启。这是最严重的安全漏洞。
2. **C4 - 修复路径遍历防护**：将 `webview2_manager.ahk:1171-1172` 和 `backup_core.ahk:112-113` 的 `RegExReplace` 改为 `InStr` 拒绝式检查。
3. **C1 - 修复 DDD 层依赖违规**：在 `domain/interfaces.ahk` 中新增 `IJoySender` 抽象基类，通过依赖注入解耦 `joystick_executor.ahk` 与 `joy_sender.ahk`。
4. **C2 - 补全 migration_logger.ahk 接管指令**：添加 3 条 `#Warn` 指令。
5. **C5 - 补全 AutoHotUnit.ahk 接管指令**：添加完整的接管指令集。
6. **C6 - 为 30 个测试文件添加 OnError 回调**：确保单独运行时不弹窗卡死。
7. **C7 - 为 joy_hotkey_manager.ahk 创建测试**：覆盖热键注册/注销、轴/POV 轮询、热插拔检测等关键路径。
8. **C8 - 删除废弃的 test-manifest feature**：从 Cargo.toml 删除，更新 AGENTS.md。
9. **C9 - 修复 E2E 硬编码 AHK 路径**：通过环境变量或集中配置注入。
10. **C10 - 为 27 个 Tauri command 补充单元测试**：采用 `_impl` 辅助函数模式提取核心逻辑后补测。

### 5.2 短期修复（Important，按影响排序）

1. **I19 + I20 - 修复数据一致性/事务完整性**：为批量删除和导入配置添加事务回滚机制。
2. **I15 - ConfigStore.Save 深拷贝**：防止调用方修改影响内部状态。
3. **I13 - FileRead 指定 UTF-8 编码**：避免非 ASCII 字符乱码。
4. **I14 - Run 路径加引号转义**：避免路径包含空格时打开错误文件。
5. **I36 - JobObject 失败补偿机制**：增加启动时遗留进程清理 + panic hook。
6. **I34 - AppError 结构化序列化**：使前端能基于错误类型差异化处理。
7. **I33 - pipe 名称提取为常量**：防止两处不一致导致 IPC 静默失败。
8. **I37 + I34 - 补全 recording_cmd 输入验证**：与 config_cmd 保持一致。
9. **I3 - 登记或修复 joy_hotkey_manager.ahk 反向依赖**：在 AGENTS.md 登记或迁移函数。
10. **I6 - 修复 backup_core.ahk 反向依赖应用层**：下沉文件写入逻辑到基础设施层。
11. **I1 - 表现层通过应用层访问 BackupCore**：封装备份 API。
12. **I26 - 将 std::fs 使用集中到 ConfigRepository**：统一 I/O 入口。
13. **I28-I30, I32, I41 - 修复 AGENTS.md 文档漂移**：更新 IpcCommand 示例、执行模式表、workspace 成员数、Tauri commands 数量、fuzz target 数量。
14. **I4 - 修复 INFO 日志级别**：改为 DEBUG。
15. **I7 + I8 - 补全 Map.Delete 前置 Has 检查**。
16. **I10 - 存储连接轮询定时器引用**。
17. **I11 - 为空 catch 块添加 OutputDebug 诊断**。
18. **I21-I25 - 整合 AHK v2 测试体系**：统一测试模式，清理废弃文件。
19. **I38-I40 - 修复 test-map.md 测试数量统计**。
20. **I42-I43 - 补充 TauriEventBridge 和 lib.rs 测试覆盖**。

### 5.3 长期改进（Minor）

1. 统一代码风格（缩进、命名、大小写）。
2. 提取重复代码为通用工具函数（排序、属性复制、等待逻辑）。
3. 简化复杂表达式（skill_group.ahk:783 单行三元表达式）。
4. 改进错误处理（FileCopy 添加 catch、load_from_file 添加 deprecated）。
5. 清理遗留文件（json.ahk、tests/ 32 个额外文件）。
6. 创建 AHK v2 fixture 管理机制。
7. 拆分 run_all_tests.ahk 巨型文件。
8. 将 IpcSender/ProcessWatcher trait 改为 async（消除 block_in_place）。
9. 修复 E2E 测试隔离性（binary skip 统一封装）。
10. 为 smoke.spec.js 添加 E2E 编号。
11. 更新 e2e-test-report.md 报告。
12. 移除 state.rs 的 `#[allow(dead_code)]` 不当标注。

---

## 六、附录

### 附录 A: 各 Task 审查范围

| Task | 范围 | 发现数（去重前） | 去重后贡献 |
|------|------|--------|-----------|
| Task 1 | AHK v2 架构合规性 | 6 | 6（其中 1 个与 Task 2 合并） |
| Task 2 | AHK v2 代码质量 | 23 | 22（1 个与 Task 1 合并，1 个升级到 Important 与 Task 3 合并，1 个与 Task 3 合并，1 个与 Task 3 合并） |
| Task 3 | AHK v2 安全性 | 17 | 15（1 个与 Task 2 合并升级，1 个与 Task 2 合并） |
| Task 4 | AHK v2 测试覆盖 | 12 | 12 |
| Task 5 | Rust 纯逻辑 crate | 12 | 12 |
| Task 6 | Rust src-tauri | 8 | 4（3 个与 Task 7/8 合并，4 个为无问题声明） |
| Task 7 | Rust 安全性 | 9 | 8（1 个与 Task 6 合并） |
| Task 8 | Rust 测试覆盖 | 17 | 16（1 个与 Task 6 合并） |
| **总计** | | **104** | **94（去重后）** |

### 附录 B: 文档与代码不一致清单

以下为 AGENTS.md 与实际代码不一致的所有发现：

| # | 位置 | 不一致内容 | 来源 |
|---|------|-----------|------|
| 1 | AGENTS.md 妥协 #2 | `_Notify(event, data)` 签名描述与实际 `Notify(message, type, duration)` 不符 | Task 1 (I2) |
| 2 | AGENTS.md Key Files | 外围模块 `equipment_recognizer.ahk`/`ocr.ahk`/`joystick_tester.ahk` 不存在 | Task 2 (M14) |
| 3 | AGENTS.md 数据结构约定 | IpcCommand 示例变体名（StartGroup/StopGroup/StopAll/UpdateConfig）全错，实际为 ToggleGroup/RegisterHotkey 等 | Task 5 (I28) |
| 4 | AGENTS.md 执行模式表格 | 遗漏 3 个 joystick 模式（joystick_periodic/joystick_sequence/joystick_hold） | Task 5 (I29) |
| 5 | AGENTS.md Rust/Tauri 架构 | 声称 "4-crate workspace" 实际有 5 个成员（asd-test-harness 未记录） | Task 5 (I30) |
| 6 | AGENTS.md Key Files | 声称 `ConfigValidator（213 tests）` 实际仅 48 个 `#[test]` | Task 5 (M24) |
| 7 | AGENTS.md Key Files | 声称 "19 Tauri commands" 实际有 34 个 | Task 6 & Task 8 (I32) |
| 8 | AGENTS.md 妥协 #3 | 描述的 `src-tauri/src/domain/` 和 `application/` 子模块已不存在 | Task 6 (I32) |
| 9 | AGENTS.md Common Patterns | Tauri Command 示例返回 `Result<T, String>` 实际为 `Result<T, AppError>` | Task 6 (I32) |
| 10 | AGENTS.md 关键设计决策 #5 | 声称 "3 个 fuzz target" 实际有 5 个 | Task 8 (I41) |
| 11 | AGENTS.md AHK 执行器测试 | 声称 "467 测试" 与实际 244 个 Test_ 方法不符 | Task 4 (I22) |
| 12 | AGENTS.md E2E 测试章节 | 文档路径不准确（`docs/e2e-test-checklist.md` 不存在；其他两个路径前缀错误） | Task 8 (M36) |
| 13 | AGENTS.md Testing Requirements | "主 crate 测试需要 `--features test-manifest`" 说法已过时 | Task 8 (C8) |

### 附录 C: 去重合并记录

| 合并编号 | 来源 Task | 合并原因 |
|---------|----------|---------|
| I3 | Task 1 F4 + Task 2 F5 | 同一问题：joy_hotkey_manager.ahk 反向依赖 domain/joystick_input.ahk |
| I12 | Task 2 F12 + Task 3 F11 | 同一位置：skill_group.ahk:783 复杂表达式（按更严格标准升级为 Important） |
| I8 | Task 2 F17 + Task 3 F17 | 同一问题：webview2_manager.ahk 哈希方式脆弱 |
| M14 | Task 2 F23 + Task 3 范围外说明 | 同一问题：AGENTS.md 外围模块不存在 |
| I31 | Task 6 F1 + Task 6 F2 + Task 7 F6 | 同一问题域：嵌套锁 + block_in_place 桥接模式 |
| I32 | Task 6 F4 + Task 8 F8 | 同一问题：AGENTS.md "19 Tauri commands" 实际 34 |

### 附录 D: 排除项说明

以下 Task 6 的发现经评估为"无问题声明"，未计入发现问题统计，列入审查亮点：

| Task 6 编号 | 位置 | 评估结论 |
|------------|------|---------|
| F5 | lib.rs:249-330 竞态窗口 | 已有文档记录，有自动修正机制，设计权衡合理 |
| F6 | watchdog.rs:67-73 unsafe 安全性 | SAFETY 注释完整，符合 Rust unsafe 代码规范 |
| F7 | watchdog.rs:20-23 心跳超时匹配 | Rust ~6s 判定 Hung，AHK 5s 断开，时间窗口合理 |
| F8 | ipc.rs:432-483 IPC 健壮性 | 防御性编程到位，边界条件处理完善 |

---

> **报告生成时间**: 2026-08-03
> **审查执行**: 8 个并行 Task 子代理
> **报告整合**: 审查报告汇总整合员
> **审查性质**: 只读分析，未修改任何源代码文件
