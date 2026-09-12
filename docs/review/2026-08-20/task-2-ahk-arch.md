# AHK v2 部分架构设计与代码可维护性审查报告

- **审查日期**：2026-08-20
- **审查范围**：`domain/`（8 文件）、`infrastructure/`（15 文件）、`application/`（3 文件）、`presentation/`（6 文件），共 32 个 `.ahk` 文件
- **审查方式**：只读静态审查（#Include 依赖图 + 代码模式扫描），未修改任何 `.ahk` 文件
- **发现总数**：10 项（Critical 2 / Important 2 / Minor 6）

---

## 执行摘要

### 总体结论

AHK v2 部分的 DDD 四层架构整体骨架清晰、分层意图明确：领域层通过抽象接口（`ILogger`/`INotifier`/`IConfigStore`/`IExecutor`/`IJoySender` 等）实现依赖倒置，`SkillManager` 仅依赖抽象，表现层 GUI 规范执行到位。**强制接管指令、GUI 规范、定时器管理、周期性触发、箭头函数/字符串花括号陷阱**等 AGENTS.md 强制项抽查**全部合规**（详见下文「合规确认」）。

但本报告发现 **2 个 Critical 级问题同源于一次不完整的 I6 重构**：配置 I/O 逻辑被下沉到新增的 `infrastructure/config_io.ahk`（`ConfigIO` 类），但该文件**从未被生产入口 `main.ahk` 引入**，且 `backup_core.ahk` 仍残留对应用层 `ExportConfigToFile` 的反向调用——这两处会导致**配置读写核心路径运行时崩溃**以及**分层测试失败**，是当前最需要优先修复的问题。

### 合规确认（抽查均通过）

| 检查项 | 结果 |
|--------|------|
| 32 个文件顶部强制接管指令（`#Requires AutoHotkey v2.0` + `#ErrorStdOut "UTF-8"` + `#Warn VarUnset, OutputDebug` + `#Warn Unreachable, OutputDebug` + `#Warn LocalSameAsGlobal, Off`） | ✅ 全部存在 |
| 箭头函数 `=> { }` 块体陷阱（`domain/`、`infrastructure/`、`application/`、`presentation/` 全量扫描） | ✅ 0 处 |
| 字符串拼接花括号陷阱（`"... " OB "{"` 模式） | ✅ 0 处 |
| `Mod(A_TickCount, interval)` 周期性触发 | ✅ 0 处（使用独立触发时间/`executionId` 防串扰） |
| 定时器引用存入 `_timers` Map、停止时正确清理 | ✅ 合规（`SkillManager._StartGroupExecution/_StopGroupExecution/_CleanupOrphanTimers`） |
| GUI 控件位置参数双引号、Button 使用 `.Text`、OnEvent 静态方法闭包包装 | ✅ 合规（`Edit` 控件使用 `.Value` 属正确用法） |
| 空 `catch { }` 块 | ✅ 0 处 |
| 已登记架构妥协（domain→error_system、joy_hotkey_manager→joystick_input） | ✅ 均符合约束边界 |

---

## 发现清单

### T2-01 【Critical｜架构设计】`ConfigIO` 类定义文件未加入生产入口 `#Include` 链，配置读写核心路径运行时崩溃

- **位置**：`main.ahk`（第 21-58 行 include 段缺失）；`application/config_service.ahk:412-417`；`infrastructure/config_io.ahk:21`
- **描述**：I6 重构将配置读写下沉到 `infrastructure/config_io.ahk` 的 `ConfigIO` 类，`config_service.ahk` 底部新增全局包装函数 `ImportConfigFromFile`/`ExportConfigToFile`（412-417 行）委托给 `ConfigIO.LoadFromFile/ExportToFile`。但 `main.ahk`（21-33 行的 infrastructure include 段）与 `config_service.ahk`（14-23 行）**均未** `#Include "infrastructure/config_io.ahk"`。由于 AHK v2 的 `#Include` 不会通过全局命名空间自动解析类，`ConfigIO` 类在生产环境中**从未被定义**。
- **影响**：以下生产代码路径均会触发 `ConfigService.SaveConfig`/`LoadConfig`、`GroupService`、`GUI` 导出等核心功能，任何一次调用都会抛出 `Error: Unknown class: ConfigIO`，属于核心功能失效：
  - `application/config_service.ahk:36`（加载）、`:106`、`:376`（保存）
  - `application/group_service.ahk:227`、`:236`
  - `presentation/gui_manager.ahk:212`
  - `infrastructure/backup_core.ahk:70`
- **根因**：单测（`tests/suites/layering_security_suites.ahk`）在内置 `#Include` 中单独把 `config_io.ahk` 拉入，掩盖了生产入口缺 include 的问题；重构时只提交了抽离代码，遗漏了在主入口登记新增模块。
- **修复建议**：在 `main.ahk` 基础设施层 include 段（建议紧邻 `config_store.ahk` 之后）加入 `#Include "infrastructure\config_io.ahk"`；同时建议在 `config_service.ahk` 顶部显式 `#Include "../infrastructure/config_io.ahk"`，避免再次依赖加载顺序。

### T2-02 【Critical｜架构设计】`backup_core.ahk:70` 反向依赖应用层 `ExportConfigToFile`，I6 重构不完整且导致分层测试失败

- **位置**：`infrastructure/backup_core.ahk:70`；`application/config_service.ahk:416`；`tests/suites/layering_security_suites.ahk:128-131`
- **描述**：`infrastructure/backup_core.ahk` 的 `RestoreBackup` 在第 70 行调用全局函数 `ExportConfigToFile(...)`，该函数定义于应用层 `config_service.ahk:416`。这是**基础设施层 → 应用层的反向依赖**，违反 DDD 分层。`config_io.ahk` 头部注释（第 5-7 行）明确声明本次重构的目标是"消除 BackupCore 对应用层 ExportConfigToFile 的反向依赖"，说明重构只完成了一半。
- **影响**：分层测试 `Test_BackupCore_NotCallExportConfigToFile`（`tests/suites/layering_security_suites.ahk:128-131`）断言 `InStr(内容, "ExportConfigToFile") == 0`，当前代码会被该断言命中而**测试失败**。同时它叠加了 T2-01 的 `ConfigIO` 未加载问题，使 `RestoreBackup` 双重失效。
- **根因**：I6 重构将 `ExportConfigToFile` 从 `config_service.ahk` 抽出后只做了"新增委托层 + 保留全局包装"两步，但遗漏了把 `backup_core.ahk` 的调用点切换为新基础设施类。
- **修复建议**：将 `backup_core.ahk:70` 改为 `ConfigIO.ExportToFile(BackupCore.currentConfigPath, config)`，并同步移除 `config_service.ahk:412-417` 中已无调用方的全局包装函数（或确认 `group_service`/`gui_manager` 改走后一并删除），使 `backup_core` 不再残留应用层符号。

### T2-03 【Important｜架构设计】基础设施层存在循环 `#Include` 链（utils ↔ json_parser ↔ json_logger）

- **位置**：`infrastructure/utils.ahk:13` → `infrastructure/json_parser.ahk:15` → `infrastructure/json_logger.ahk:16` → `infrastructure/utils.ahk`
- **描述**：三个基础设施模块形成三节点环：`utils.ahk` 引入 `json_parser.ahk`（供 `_GetField` 解析 JSON 字符串），`json_parser.ahk` 引入 `json_logger.ahk`，`json_logger.ahk` 又引入 `utils.ahk`。
- **影响**：AHK v2 的 `#Include` 语义为"同一路径只包含一次"，因此**运行时不会**产生重复定义崩溃，当前依赖 `main.ahk` 的固定加载顺序（先 serializer→logger→parser→utils）可正常运行。但这是架构耦合气味：工具函数层被日志层和解析层反向依赖，导致 `utils`/`json_parser`/`json_logger` 无法独立复用，任何加载顺序调整都可能触发"未定义符号"。
- **根因**：`utils._GetField` 为了兼容"JSON 字符串"输入而内联调用 `JSONParser.Parse`，把解析能力耦合进最底层工具函数。
- **修复建议**：打破环——将 `_GetField` 中的 JSON 解析改为由调用方传入解析结果，或把 `JSONParser.Parse` 的调用上提到 `json_logger`/`json_parser` 层；至少应在 `utils.ahk` 中移除对 `json_parser.ahk` 的直接依赖。

### T2-04 【Important｜代码质量】`config_store.ahk` 使用 `JSONLogger` 但未显式 `#Include`，存在隐式依赖

- **位置**：`infrastructure/config_store.ahk:95`（使用 `JSONLogger.Log`），`:14`（仅 include `deepclone.ahk`）
- **描述**：`config_store.ahk` 的 `Set()` 方法在第 95 行调用 `JSONLogger.Log`，但该文件仅 `#Include "..\lib\ahk2_lib\deepclone.ahk"`，未引入 `json_logger.ahk`。
- **影响**：当前依赖 `main.ahk` 在第 22 行先加载 `json_logger.ahk` 才在第 27 行加载 `config_store.ahk` 而掩盖了问题。若该文件被测试或其他脚本独立加载（项目测试规范明确要求模块文件显式 `#Include` 其依赖），将抛出 `Unknown class: JSONLogger`。
- **根因**：与 T2-01 同类——模块声明依赖不全，依赖外部的加载顺序。
- **修复建议**：在 `config_store.ahk` 顶部补 `#Include "json_logger.ahk"`（并视需要补 `json_parser.ahk` 以获得 `JSONErrorType` 常量，如确有引用）。

### T2-05 【Minor｜架构设计】`joy_sender.ahk` 反向依赖 `domain/interfaces.ahk`，未在 AGENTS.md 登记

- **位置**：`infrastructure/joy_sender.ahk:17`
- **描述**：`joy_sender.ahk` 为基础设施层，`#Include "../domain/interfaces.ahk"` 以实现 `IJoySender` 抽象接口（依赖倒置）。
- **影响**：方向本身**正确**（基础设施实现领域接口，正是依赖倒置的体现），但 AGENTS.md「已知架构妥协 #1」仅登记了 `joy_hotkey_manager.ahk → joystick_input.ahk` 这一处基础设施→领域的反向依赖，`joy_sender → interfaces` 属于同类但**未登记**的妥协，易在后续分层扫描中被误判。
- **根因**：文档登记滞后于代码演进。
- **修复建议**：在 AGENTS.md 妥协 #1 的约束边界中补记 `infrastructure/joy_sender.ahk` 引用 `domain/interfaces.ahk` 的 `IJoySender` 接口（依赖倒置，允许）。

### T2-06 【Minor｜代码质量】`ConfigStore.Set()` 与 `Save()` 深拷贝策略不一致

- **位置**：`infrastructure/config_store.ahk:82-98`（`Set` 直接赋值 `this._groupSettings := value`）对比 `:36-65`（`Save` 使用 `deepclone`）
- **描述**：`Save()`（第 42 行）对 `GroupSettings` 做了 `deepclone` 并标注 I15 注释"避免外部修改影响内部状态"，`Load()/Get()` 也做深拷贝，但 `Set()` 第 85-87 行直接引用赋值，无防御性拷贝。
- **影响**：通过 `Set("GroupSettings", map)` 传入的对象与内部 `_groupSettings` 共享引用，外部后续修改会污染内部状态，与 I15 的防护意图矛盾，属于潜在的数据别名缺陷。
- **根因**：`Set`/`Save` 两条写入路径未统一防御性拷贝策略。
- **修复建议**：`Set()` 的 `GroupSettings/CONTROL_HOTKEYS/HoldSettings` 分支与 `Save()` 对齐，统一使用 `deepclone`（或明确注释说明 `Set` 语义为"转移所有权"）。

### T2-07 【Minor｜架构设计】AGENTS.md 基础设施/领域文件清单滞后

- **位置**：`d:\1demo\AutoHotkeydemo\AGENTS.md`（Key Files / Subdirectories 表格）
- **描述**：现有 AGENTS.md 未登记以下实际存在且被引用的模块：`infrastructure/config_io.ahk`、`infrastructure/joy_sender.ahk`、`infrastructure/migration_logger.ahk`；领域层 Key Files 表也未登记 `joystick_executor.ahk`、`joystick_input.ahk`、`key_recorder.ahk`、`key_validator.ahk`。
- **影响**：文档与代码脱节，新维护者难以定位模块边界，也降低了架构妥协登记表的可信度。
- **根因**：模块新增/重构后未同步更新文档。
- **修复建议**：按现状补齐 AGENTS.md 的 Key Files 表与 Subdirectories 表。

### T2-08 【Minor｜代码质量】`SkillManager._resetEmergencyTimer` 未在类静态属性区声明

- **位置**：`domain/skill_manager.ahk:453-458`、`:470-473`
- **描述**：`_timers`/`_executionIds`/`_cleanupTimer`/`_eventHooks`/`_controlHotkeyBindings` 均在类顶部（66-70 行）集中声明，但 `_resetEmergencyTimer` 未声明，仅在第 458 行运行时动态赋值，导致必须用 `SkillManager.HasProp("_resetEmergencyTimer")`（453 行）做守卫。
- **影响**：状态声明不一致，`HasProp` 守卫属于"为未声明静态属性打补丁"的代码气味，降低可读性与一致性。
- **根因**：后补功能未同步更新类的静态属性声明区。
- **修复建议**：在静态属性区补充 `static _resetEmergencyTimer := 0`，并移除 `HasProp` 守卫。

### T2-09 【Minor｜代码质量】`SkillManager._StartGroupExecution` 嵌套闭包 + `Bind` 递归，圈复杂度偏高

- **位置**：`domain/skill_manager.ahk:318-379`
- **描述**：`_StartGroupExecution` 方法内定义命名嵌套闭包 `executor(gId, execId)`，通过 `executor.Bind(gId, execId)` 重绑定自身实现"延迟重调度"，配合 `_timers`/`_executionIds` 双 Map 实现停机与防串扰。方法体约 60 行、嵌套 5 层 `try`/`if`。
- **影响**：逻辑正确（且定时器/executionId 管理规范），但嵌套函数 + 自绑定递归的可读性差，后续修改易引入定时器泄漏或串扰回归。
- **根因**：AHK 无原生 async 调度原语，用闭包 + SetTimer 模拟递归调度。
- **修复建议**：将 `executor` 提取为独立私有方法（如 `_ExecuteTick(gId, execId)`），用显式 `SetTimer` 回调取代自绑定递归，降低嵌套深度。

### T2-10 【Minor｜代码质量】表现层/领域层存在超大类，建议拆分

- **位置**：`presentation/group_editor.ahk`（81 个静态方法）、`presentation/webview2_manager.ahk`（60 个静态方法）、`domain/skill_group.ahk`（约 920 行）
- **描述**：`group_editor.ahk` 与 `webview2_manager.ahk` 分别承载 81/60 个静态方法，`skill_group.ahk` 单文件近千行，均呈现 God Object 倾向。
- **影响**：单类职责过重，方法间共享大量静态状态（`controls`/`modeControls`/`subGroups` 等），可维护性与可测试性下降，是圈复杂度与隐性 Bug 的高发区。
- **根因**：GUI 编辑器与 WebView 桥接逻辑随功能叠加持续扩张，未做模块化拆分。
- **修复建议**：按职责拆分（如将 `group_editor` 的按键选择器/热键编辑器/预览逻辑抽为子类或独立文件；将 `webview2_manager` 的 AHK-JS Bridge 消息路由与 UI 刷新分离）；`skill_group` 可按执行模式拆算到各模式执行器。

---

## 建议修复优先级

1. **立即修复（Critical）**：T2-01（补 `main.ahk` 的 `config_io.ahk` include）+ T2-02（`backup_core` 改调 `ConfigIO.ExportToFile`，一并清理 `config_service.ahk` 全局包装函数）——两项同源，可一次提交解决。
2. **短期（Important）**：T2-03（打破 utils/json 循环依赖）、T2-04（`config_store` 显式 include）。
3. **长期（Minor）**：T2-05 ~ T2-10 随迭代逐步收口。