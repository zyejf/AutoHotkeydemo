# Task 4: AHK v2 测试覆盖与质量审查发现

## 审查范围

本审查针对 ASD 技能管理器 v4.0 项目的 **AHK v2 部分** 执行只读测试覆盖与质量审查。

**审查目录**：
- `D:\1demo\AutoHotkeydemo\tests\`（根目录测试文件 + 子目录）
- `D:\1demo\AutoHotkeydemo\tests\test_ahk_executor\`（AHK 执行器测试）

**审查依据**：`AGENTS.md` 中的「AHK v2 测试」「AHK 执行器测试」「错误与警告接管机制」「测试文件标准模板」「Subdirectories」章节。

**审查维度**：
1. 测试套件完整性
2. AHK 执行器测试完整性
3. 测试隔离性
4. 测试前置检查流程遵守
5. 测试文件标准模板遵守
6. fixture 管理
7. 覆盖率盲区识别
8. 测试质量

---

## 测试文件清单（实际发现的）

### tests/ 根目录下的 .ahk 文件（共 46 个）

#### AGENTS.md 标准列表中的文件（14 个，全部存在 ✓）
| 文件 | 大小 | 用途 |
|------|------|------|
| `AutoHotUnit.ahk` | 6910 | AutoHotUnit 测试框架基类 |
| `run_all_tests.ahk` | 68397 | 主测试运行器（内联 80 个 Suite） |
| `run_tests.ahk` | 7217 | 备用测试运行器 |
| `run_tests.ps1` | 4152 | PowerShell 测试运行器 |
| `test_domain.ahk` | 10813 | 领域层测试（场景式） |
| `test_infrastructure.ahk` | 8934 | 基础设施层测试（场景式） |
| `test_application.ahk` | 7446 | 应用层测试（场景式） |
| `test_presentation.ahk` | 8518 | 表现层测试（场景式） |
| `test_webview2_bridge.ahk` | 14001 | WebView2 Bridge 测试（场景式） |
| `test_boundary.ahk` | 6658 | 边界条件测试（场景式） |
| `test_error_captor.ahk` | 15126 | 错误捕获测试（场景式） |
| `test_error_system.ahk` | 7718 | 错误系统测试（函数式） |
| `test_integration_error_system.ahk` | 8860 | 错误系统集成测试（场景式） |
| `test_result_reporter.ahk` | 8159 | TestReporter 测试框架（非测试） |

#### tests/ 根目录下的额外文件（32 个，未在 AGENTS.md 登记）
- **历史遗留/调试文件**：`benchmark_hotpath.ahk`, `run_bug_repro.ahk`, `run_tests_silent.ahk`, `test_bug_reproduction.ahk`, `test_debug_minimal.ahk`
- **HTML/WebView2 原型文件**（10 个）：`test_html_editor_proto.ahk`, `test_html_editor_v2.ahk`, `test_html_loader.ahk`, `test_html_loader2.ahk`, `test_html_minimal.ahk`, `test_html_simple.ahk`, `test_html_simple2.ahk`, `test_html_simple3.ahk`, `test_webview2_proto.ahk`, `test_wv2_html.ahk`, `test_wv2_minimal.ahk`, `test_wv2_v2.ahk`
- **"full" 版本文件**（5 个）：`test_app_full.ahk`, `test_domain_full.ahk`, `test_infra_full.ahk`, `test_integration_full.ahk`, `test_pres_full.ahk`
- **集成测试变体**（3 个）：`test_deep_integration.ahk`, `test_integration_missing_features.ahk`, `test_integration_v2.ahk`
- **功能测试文件**（6 个）：`test_app_ui.ahk`, `test_dark_theme_proto.ahk`, `test_editor_e2e.ahk`, `test_hotreload.ahk`, `test_joystick.ahk`, `test_key_recorder.ahk`, `test_key_test_integration.ahk`, `test_key_validator.ahk`

### tests/test_ahk_executor/ 目录（5 个文件，符合 AGENTS.md 声明 ✓）
| 文件 | 大小 | 套件数 | 测试方法数 | 断言数 |
|------|------|--------|-----------|--------|
| `test_executor.ahk` | 13217 | 9 | 42 | 71 |
| `test_ipc_client.ahk` | 14913 | 12 | 64 | 101 |
| `test_hotkey_hook.ahk` | 7363 | 7 | 28 | 34 |
| `test_sender.ahk` | 14061 | 11 | 38 | 73 |
| `test_joystick.ahk` | 18089 | 18 | 72 | 106 |
| **总计** | | **57** | **244** | **385** |

### 其他子目录
- `tests/logs/`：测试日志输出（app.log 853KB, errors.log 212KB）
- `tests/reports/`：测试报告 JSON（40+ 个历史报告文件）
- `tests/unit/`：单元测试输出目录（含 domain/infrastructure 子目录的 logs）
- `tests/backups/`：测试备份目录

---

## 发现清单

### Finding 1
- **位置**: `D:\1demo\AutoHotkeydemo\tests\AutoHotUnit.ahk:1-4`
- **维度**: 测试前置检查流程遵守
- **严重级别**: Critical
- **描述**: AutoHotUnit.ahk（AutoHotUnit 测试框架本身）完全缺少 AGENTS.md 强制要求的接管指令。文件顶部仅有：
  ```autohotkey
  #SingleInstance Force
  #Warn All, StdOut
  FileEncoding("UTF-8")
  ```
  缺少 `#Requires AutoHotkey v2.0`、`#ErrorStdOut "UTF-8"`、`#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`、`OnError` 回调。更严重的是使用 `#Warn All, StdOut` 而非标准要求的 `#Warn VarUnset, OutputDebug`（警告输出到 stdout 而非 OutputDebug，会污染测试输出）。
- **根因**: 测试框架文件被误认为不需要遵守接管指令规则；`#Warn All, StdOut` 与标准要求的细粒度 `#Warn` 配置冲突。
- **修复建议**: 在 AutoHotUnit.ahk 顶部添加完整的接管指令集。注意 test_ahk_executor/ 下 5 个文件通过在 `#Include "../AutoHotUnit.ahk"` 之后重新声明 `#Warn VarUnset, OutputDebug` 等来覆盖此问题，但这属于 workaround，框架本身应合规。

### Finding 2
- **位置**: `D:\1demo\AutoHotkeydemo\tests\test_domain.ahk`, `test_infrastructure.ahk`, `test_application.ahk`, `test_presentation.ahk`, `test_webview2_bridge.ahk`, `test_boundary.ahk`, `test_error_captor.ahk` 等 30 个文件
- **维度**: 测试前置检查流程遵守
- **严重级别**: Critical
- **描述**: tests/ 根目录下约 30 个测试文件缺少 `OnError` 回调。AGENTS.md「测试文件额外必须包含」章节明确要求测试文件包含：
  ```autohotkey
  OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))
  ```
  缺少 OnError 的文件清单（部分）：
  - `test_domain.ahk`, `test_infrastructure.ahk`, `test_application.ahk`, `test_presentation.ahk`
  - `test_webview2_bridge.ahk`, `test_boundary.ahk`, `test_error_captor.ahk`
  - `test_app_ui.ahk`, `test_dark_theme_proto.ahk`, `test_debug_minimal.ahk`
  - `test_deep_integration.ahk`, `test_editor_e2e.ahk`, `test_hotreload.ahk`
  - `test_html_*.ahk`（7 个）, `test_wv2_*.ahk`（3 个）
  - `test_joystick.ahk`（tests/ 根目录版本）, `test_key_recorder.ahk`, `test_key_validator.ahk`
  - `run_tests.ahk`, `run_tests_silent.ahk`
  这些文件如果单独运行（`AutoHotkey64.exe tests\test_domain.ahk`），运行时错误会弹出默认错误对话框，导致测试卡死、无法在 CI 中自动化运行。
- **根因**: tests/ 根目录的测试文件采用场景式（TestReporter）模式，预期作为独立脚本运行，但未遵循 OnError 强制规则。开发者可能依赖 run_all_tests.ahk 的 OnError，但 run_all_tests.ahk 并未 #Include 这些文件（见 Finding 4）。
- **修复建议**: 为所有 30 个缺少 OnError 的测试文件添加标准 OnError 回调。

### Finding 3
- **位置**: `D:\1demo\AutoHotkeydemo\infrastructure\joy_hotkey_manager.ahk`（11575 bytes，完全未被覆盖）
- **维度**: 覆盖率盲区
- **严重级别**: Critical
- **描述**: `infrastructure/joy_hotkey_manager.ahk` 是一个 11575 bytes 的基础设施模块，提供手柄按钮热键注册（Joy1~Joy32）、轴/POV 轮询（SetTimer）、热插拔检测（30s）、多手柄支持等关键功能。经全量扫描 tests/ 下所有 .ahk 文件，确认该模块**未被任何测试文件 #Include 或引用**（既不匹配 `joy_hotkey_manager` 也不匹配 `JoyHotkeyManager`）。
- **根因**: 该模块可能是较新添加的（AGENTS.md「Subdirectories」章节也未在 infrastructure 模块清单中明确列出它的测试对应物），添加时未同步创建测试。
- **修复建议**: 创建 `tests/test_joy_hotkey_manager.ahk`，覆盖热键注册/注销、轴/POV 轮询、热插拔检测、多手柄支持等关键路径。将该模块登记到 AGENTS.md 的 infrastructure 模块清单。

### Finding 4
- **位置**: `D:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk:1-40`
- **维度**: 测试套件完整性
- **严重级别**: Important
- **描述**: AGENTS.md「AHK v2 测试」章节指示运行 `tests\run_all_tests.ahk` 执行测试套件。但实际检查 run_all_tests.ahk 的 #Include 列表，发现它**只 #Include 了**：
  - `AutoHotUnit.ahk`（框架）
  - `../domain/`, `../infrastructure/`, `../application/`, `../presentation/` 下的被测模块（共 21 个）
  - `test_ahk_executor/` 下 5 个测试文件
  
  它**没有 #Include** tests/ 根目录下的任何标准测试模块：
  - `test_domain.ahk`, `test_infrastructure.ahk`, `test_application.ahk`, `test_presentation.ahk`
  - `test_webview2_bridge.ahk`, `test_boundary.ahk`, `test_error_captor.ahk`
  - `test_error_system.ahk`, `test_integration_error_system.ahk`, `test_result_reporter.ahk`
  
  run_all_tests.ahk 转而**内联定义**了 80 个 `extends AutoHotUnitSuite` 的测试套件（224 个 Test_ 方法），与 tests/ 根目录的场景式测试（TestReporter.Scenario）覆盖相同的模块但测试用例不同。这导致：
  - tests/ 根目录的标准测试模块成为「孤儿」，必须单独运行
  - 测试存在两套并行体系（内联 AutoHotUnitSuite vs 独立 TestReporter），维护成本高
  - AGENTS.md 描述与实际运行行为不符
- **根因**: 测试架构演进过程中，run_all_tests.ahk 重构为内联 AutoHotUnitSuite 模式，但未同步清理或整合 tests/ 根目录的旧场景式测试文件。
- **修复建议**: 二选一：(a) 将 run_all_tests.ahk 的内联测试拆分为独立的 test_*.ahk 文件并用 #Include 整合；(b) 将 tests/ 根目录的场景式测试迁移为 AutoHotUnitSuite 模式并 #Include 到 run_all_tests.ahk。同时更新 AGENTS.md 的运行说明。

### Finding 5
- **位置**: `D:\1demo\AutoHotkeydemo\AGENTS.md`（「AHK 执行器测试」章节）
- **维度**: 测试套件完整性
- **严重级别**: Important
- **描述**: AGENTS.md 声称 AHK 执行器测试为「57 套件 / 467 测试」。实际核对：
  - **57 套件** ✓ 完全匹配（test_executor 9 + test_ipc_client 12 + test_hotkey_hook 7 + test_sender 11 + test_joystick 18 = 57）
  - **467 测试** ✗ 与实际不符。test_ahk_executor 下 5 个文件共有 244 个 `Test_` 方法（regex `^\s+Test_\w+\s*\(`）。即便加上 run_all_tests.ahk 内联的 224 个 Test_ 方法（244+224=468，接近 467），也未包含 tests/ 根目录场景式测试中的 336 个 `TestReporter.Assert` 调用。AGENTS.md 的统计口径不明确，且数字与任何一种统计方式都对不齐。
- **根因**: 测试数量统计口径未明确（是统计 Test_ 方法数、Scenario 数，还是 Assert 调用数？）；测试演进后数字未同步更新。
- **修复建议**: 在 AGENTS.md 中明确测试统计口径（建议统一为「Test_ 方法数」），并更新为准确数字。建议分别统计：test_ahk_executor（57 套件/244 方法）、run_all_tests.ahk（80 套件/224 方法）、tests/ 根目录场景式测试（72 场景/336 断言）。

### Finding 6
- **位置**: `D:\1demo\AutoHotkeydemo\tests\test_joystick.ahk:1-3`（tests/ 根目录版本，非 test_ahk_executor/ 版本）
- **维度**: 测试前置检查流程遵守
- **严重级别**: Important
- **描述**: `tests/test_joystick.ahk`（5604 bytes，使用 JoyTestRunner 自定义模式，34 个 RunTest 调用）缺少接管指令：
  - 缺少 `#Warn VarUnset, OutputDebug`
  - 缺少 `#Warn Unreachable, OutputDebug`
  - 缺少 `#Warn LocalSameAsGlobal, Off`
  - 缺少 `OnError` 回调
  
  文件顶部仅有：
  ```autohotkey
  #Requires AutoHotkey v2.0
  #ErrorStdOut "UTF-8"
  ```
  注意：此文件与 `tests/test_ahk_executor/test_joystick.ahk`（18089 bytes，完整合规）是两个不同的文件，前者覆盖 `domain/joystick_input.ahk` + `domain/joystick_executor.ahk`，后者覆盖 `asd-tauri/src-tauri/ahk_executor/joystick.ahk`。
- **根因**: 该文件使用独立的 JoyTestRunner 模式，未遵循标准测试模板。
- **修复建议**: 补全 #Warn 指令和 OnError 回调，或将其迁移为 AutoHotUnitSuite 模式。

### Finding 7
- **位置**: `D:\1demo\AutoHotkeydemo\tests\test_application.ahk:29-46`, `test_presentation.ahk`, `test_webview2_bridge.ahk`, `test_error_system.ahk:18-20`
- **维度**: 测试隔离性
- **严重级别**: Important
- **描述**: 多个测试文件通过静态属性赋值污染全局状态，测试间存在隐式依赖：
  - `test_application.ahk`：12 处静态赋值（`SkillGroup.Logger := DebugLogger`, `SkillManager.ConfigStore := ConfigStore`, `GroupService.ConfigStore := ConfigStore`, `ConfigService.SkillManager := SkillManager` 等），通过 `LoadTestDependencies()` 函数在文件加载时立即执行
  - `test_presentation.ahk`：14 处静态属性赋值
  - `test_webview2_bridge.ahk`：14 处静态属性赋值
  - `test_error_system.ahk`：使用全局变量 `g_testResults`, `g_testPassed`, `g_testFailed`（声明为 `global`）
  - `test_error_system.ahk:25`：修改 `ErrorSystem.logFile := A_ScriptDir "\logs\test_errors.log"`（修改全局日志路径）
  
  这些测试如果被 #Include 到同一进程（如 run_all_tests.ahk），前面的测试会污染后面测试的依赖状态，导致测试结果不可重复。目前 run_all_tests.ahk 未 #Include 这些文件（见 Finding 4），问题被掩盖，但一旦整合就会暴露。
- **根因**: AHK v2 缺乏原生 DI 容器，测试依赖通过全局静态属性注入；场景式测试无 setup/teardown 隔离机制（TestReporter 框架未提供 beforeEach/afterEach）。
- **修复建议**: (a) 为 TestReporter 框架添加 setup/teardown 钩子，每个 Scenario 前重置依赖；(b) 或将场景式测试迁移为 AutoHotUnitSuite 模式（提供 beforeAll/afterEach）；(c) 在每个测试文件末尾添加状态清理代码。

### Finding 8
- **位置**: `D:\1demo\AutoHotkeydemo\tests\`（根目录 32 个额外文件）
- **维度**: 测试套件完整性
- **严重级别**: Important
- **描述**: tests/ 根目录存在 32 个未在 AGENTS.md「Subdirectories」或「AHK v2 测试」章节登记的 .ahk 文件。这些文件大多是开发调试过程中的临时产物：
  - HTML/WebView2 原型文件 10 个（`test_html_*.ahk`, `test_wv2_*.ahk`）
  - "full" 版本文件 5 个（`test_*_full.ahk`）
  - 集成测试变体 3 个（`test_integration_*.ahk`, `test_deep_integration.ahk`）
  - 功能测试 6 个（`test_app_ui.ahk`, `test_editor_e2e.ahk`, `test_hotreload.ahk` 等）
  - 调试/bug 复现文件 5 个（`benchmark_hotpath.ahk`, `run_bug_repro.ahk`, `test_bug_reproduction.ahk` 等）
  
  其中大多数（约 25 个）缺少 OnError 回调，部分缺少完整的 #Warn 指令。这些文件增加了维护负担，且与 AGENTS.md 的测试模块清单不符，使审查者难以判断哪些是正式测试。
- **根因**: 测试文件缺乏生命周期管理，调试用文件未及时清理或归档；AGENTS.md 未登记这些文件。
- **修复建议**: (a) 将临时调试文件归档到 `tests/archive/` 或 `tests/debug/` 子目录；(b) 评估每个文件的测试价值，删除废弃文件；(c) 保留的文件补全接管指令并登记到 AGENTS.md。

### Finding 9
- **位置**: `D:\1demo\AutoHotkeydemo\tests\`（整个目录）
- **维度**: fixture 管理
- **严重级别**: Minor
- **描述**: tests/ 下没有独立的 fixture 目录（只有 `backups/`, `logs/`, `reports/`, `test_ahk_executor/`, `unit/`）。测试数据大多硬编码在测试文件中，例如：
  - `test_domain.ahk:54`：`configA := Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50])`
  - `test_infrastructure.ahk:31`：`JSONParser.Parse('{"key":"value","num":42}')`
  - `test_boundary.ahk:30-36`：循环构建 50 元素 JSON 数组
  
  仅 `run_all_tests.ahk` 和 `test_pres_full.ahk` 提到 'test_config'/'mock' 字样，但未使用独立 fixture 文件。对比 Rust/Tauri 部分有规范的 `asd-tauri/tests/fixtures/` 目录（AGENTS.md「测试数据管理」章节），AHK v2 部分缺乏同等机制。
- **根因**: AHK v2 测试缺乏 fixture 管理规范；场景式测试习惯内联数据。
- **修复建议**: 创建 `tests/fixtures/` 目录，将重复使用的测试数据（如标准 config、JSON 样本）提取为独立文件；在 AGENTS.md 中补充 AHK v2 的 fixture 管理规范。

### Finding 10
- **位置**: `D:\1demo\AutoHotkeydemo\tests\test_error_system.ahk:26`
- **维度**: 测试前置检查流程遵守
- **严重级别**: Minor
- **描述**: `test_error_system.ahk` 使用非标准的 OnError 模式：
  ```autohotkey
  OnError(ErrorSystem_HandleError, -1)
  ```
  而非 AGENTS.md 标准模板要求的：
  ```autohotkey
  OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))
  ```
  该模式引用了一个具名函数 `ErrorSystem_HandleError` 并设置优先级 `-1`。虽然这在该测试场景下可能合理（测试的就是 ErrorSystem），但偏离标准模板，且依赖外部函数定义。
- **根因**: 该测试需要与 ErrorSystem 交互验证，标准模板的 FileAppend 模式不适用。
- **修复建议**: 此为合理偏差，建议在文件顶部添加注释说明偏离原因；或重构为标准模式 + 额外的 ErrorSystem 验证逻辑。

### Finding 11
- **位置**: `D:\1demo\AutoHotkeydemo\tests\`（整体）
- **维度**: 测试质量
- **严重级别**: Minor
- **描述**: AHK v2 测试存在 4 种不统一的测试模式：
  1. **AutoHotUnitSuite 模式**（test_ahk_executor/ 5 文件 + run_all_tests.ahk 内联 80 套件）：使用 `class XxxTests extends AutoHotUnitSuite` + `Test_xxx()` 方法 + `this.assert.equal()` 断言
  2. **TestReporter 场景式模式**（test_domain/infrastructure/application/presentation/webview2_bridge/boundary/error_captor/integration_error_system）：使用 `TestReporter.Scenario()` + `TestReporter.Assert()` 顶层顺序执行
  3. **JoyTestRunner 自定义模式**（tests/test_joystick.ahk）：使用 `JoyTestRunner.RunTest(name, func)` + lambda 抛错断言
  4. **函数式全局变量模式**（test_error_system.ahk）：使用 `TestXxx()` 函数 + 全局 `g_testResults` 数组 + `_PrintResult()` 输出
  
  模式不统一导致：维护者需要理解 4 套不同的断言/报告机制；测试输出格式不一致；难以编写通用的测试工具。
- **根因**: 测试架构渐进式演进，不同时期采用不同模式，未进行统一重构。
- **修复建议**: 统一为 AutoHotUnitSuite 模式（最成熟，提供 beforeAll/beforeEach/afterEach/afterAll 钩子）。将 TestReporter 场景式测试迁移为 Suite 类，将 JoyTestRunner 和函数式测试重构为 Suite。

### Finding 12
- **位置**: `D:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk`（整体）
- **维度**: 测试质量
- **严重级别**: Minor
- **描述**: run_all_tests.ahk 文件大小 68397 bytes（约 1800 行），内联定义了 80 个测试套件类。单个文件过大，违反单一职责原则，难以维护和代码审查。任何修改都需要在巨型文件中定位，且无法独立运行某个套件。
- **根因**: 将所有测试内联到单一运行器文件，未按模块拆分。
- **修复建议**: 将 80 个套件按模块拆分为独立文件（如 `tests/suites/domain_tests.ahk`, `tests/suites/infrastructure_tests.ahk` 等），run_all_tests.ahk 仅负责 #Include 和运行调度。

---

## 覆盖率盲区清单

### 完全未覆盖的模块
| 模块 | 大小 | 功能 | 状态 |
|------|------|------|------|
| `infrastructure/joy_hotkey_manager.ahk` | 11575 bytes | 手柄热键注册、轴/POV 轮询、热插拔检测、多手柄支持 | **完全无测试**（Critical） |

### 可能覆盖不足的模块（需进一步评估）
| 模块 | 现状 | 风险 |
|------|------|------|
| `infrastructure/migration_logger.ahk` | 被 #Include 但无专项测试套件 | 迁移日志逻辑未独立验证 |
| `infrastructure/utils.ahk` | run_all_tests.ahk 有 `GetPropUtilTests`/`MapIterationSafetyTests` | 覆盖较好 |
| `presentation/backup_ui.ahk` | 被 #Include 但无专项测试 | UI 交互难测试，但接口合规未验证 |
| `presentation/debug_panel.ahk` | 被 #Include 但无专项测试 | 同上 |
| `presentation/gui_manager.ahk` | run_all_tests.ahk 有 `GUIManagerModeNamesTests` | 部分覆盖 |
| 根目录 `main.ahk`/`asd.ahk`/`config.ahk`/`gui.ahk`/`json.ahk`/`ui_manager.ahk` | 未被测试 #Include | 入口文件和兼容层未测试 |

### 关键路径覆盖评估
- **错误处理分支**：test_error_captor.ahk（100 断言）+ test_error_system.ahk + test_integration_error_system.ahk 提供了较好的错误路径覆盖
- **边界条件**：test_boundary.ahk（26 断言）覆盖超长输入、深层嵌套、边界值
- **JSON 往返**：test_infrastructure.ahk 场景 D 覆盖序列化/反序列化往返
- **配置验证**：run_all_tests.ahk 的 `ConfigValidatorTests`/`ConfigValidatorMapFormatTests`/`ConfigValidatorAllMapFormatTests` 提供充分覆盖
- **模式注册**：test_domain.ahk 场景 B + run_all_tests.ahk `ModeRegistryTests` 覆盖 7 种模式
- **缺失**：joy_hotkey_manager 的热插拔检测、多手柄支持、轴/POV 轮询定时器逻辑完全未测

---

## 无问题声明

以下维度未发现问题：
- **AHK 执行器测试套件数量**：57 套件完全匹配 AGENTS.md 声明（Finding 5 仅涉及测试方法数统计口径）
- **test_ahk_executor/ 5 文件的接管指令**：全部合规（#Requires + #ErrorStdOut + 3 个 #Warn + 标准 OnError 回调）
- **test_ahk_executor/ 5 文件的测试质量**：0 空测试，每测试 1.2-1.7 断言，断言充分
- **AutoHotUnitSuite 基类的使用**：test_ahk_executor/ 5 文件正确继承并提供 beforeAll/beforeEach/afterEach/afterAll 钩子
- **AGENTS.md 标准列表中的 14 个文件**：全部存在于 tests/ 根目录

---

## 统计

### 发现总数：12

### 各级别数量
| 级别 | 数量 | 占比 |
|------|------|------|
| Critical | 3 | 25% |
| Important | 5 | 42% |
| Minor | 4 | 33% |
| **总计** | **12** | 100% |

### 按维度分布
| 维度 | 发现数 | Finding 编号 |
|------|--------|-------------|
| 测试前置检查流程遵守 | 4 | F1, F2, F6, F10 |
| 覆盖率盲区 | 1 | F3 |
| 测试套件完整性 | 3 | F4, F5, F8 |
| 测试隔离性 | 1 | F7 |
| fixture 管理 | 1 | F9 |
| 测试质量 | 2 | F11, F12 |

### 最关键的 3 个发现摘要
1. **F1（Critical）**：AutoHotUnit.ahk 测试框架本身完全缺少接管指令（#Requires/#ErrorStdOut/#Warn/OnError），使用 `#Warn All, StdOut` 与标准要求的细粒度 #Warn 配置冲突。作为被所有 test_ahk_executor 测试 #Include 的核心框架，其不合规影响整个测试体系。
2. **F2（Critical）**：tests/ 根目录约 30 个测试文件缺少 OnError 回调，单独运行时运行时错误会弹出对话框卡死，无法 CI 自动化。包括 test_domain/test_infrastructure/test_application/test_presentation 等核心测试。
3. **F3（Critical）**：`infrastructure/joy_hotkey_manager.ahk`（11575 bytes，手柄热键注册/轴轮询/热插拔检测/多手柄支持）完全无测试覆盖，是明确的覆盖率盲区。

### 覆盖率盲区概要
- **完全未覆盖**：1 个模块（`infrastructure/joy_hotkey_manager.ahk`，Critical）
- **可能覆盖不足**：5 个模块（migration_logger, backup_ui, debug_panel, gui_manager 部分覆盖, 根目录入口文件未测）
- **覆盖良好**：domain/ 8 模块、infrastructure/ 13/14 模块、application/ 2 模块、presentation/ 4/6 模块
- **关键路径覆盖**：错误处理、边界条件、JSON 往返、配置验证、模式注册均有覆盖；缺失手柄热键管理器的定时器/热插拔/多手柄逻辑

### 接管指令合规统计
| 指令 | test_ahk_executor/ (5 文件) | tests/ 根目录 (46 文件) |
|------|---------------------------|------------------------|
| `#Requires AutoHotkey v2.0` | 5/5 ✓ | 45/46（缺 AutoHotUnit.ahk） |
| `#ErrorStdOut "UTF-8"` | 5/5 ✓ | 45/46（缺 AutoHotUnit.ahk） |
| `#Warn VarUnset, OutputDebug` | 5/5 ✓ | 44/46（缺 AutoHotUnit.ahk, test_joystick.ahk） |
| `#Warn Unreachable, OutputDebug` | 5/5 ✓ | 44/46（缺 AutoHotUnit.ahk, test_joystick.ahk） |
| `#Warn LocalSameAsGlobal, Off` | 5/5 ✓ | 44/46（缺 AutoHotUnit.ahk, test_joystick.ahk） |
| `OnError` 回调 | 5/5 ✓ | 16/46（30 个文件缺失） |
| 标准 `FileAppend("RUNTIME_ERROR:...")` 模式 | 5/5 ✓ | 0/46（test_error_system.ahk 用非标准模式） |
