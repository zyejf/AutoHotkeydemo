# Task 1: AHK v2 架构合规性审查发现

## 审查范围

### 已审查文件清单

**领域层 (domain/)**
- `domain/interfaces.ahk` — 抽象接口定义（ILogger/INotifier/IConfigStore/IExecutor/IHealthChecker/IEventHook）
- `domain/mode_registry.ahk` — 执行模式注册表
- `domain/joystick_executor.ahk` — 手柄模式执行器（**违规重点**）
- `domain/joystick_input.ahk` — 手柄输入规范
- `domain/skill_group.ahk` — 技能组领域模型（含 `_Notify` 实现）
- `domain/skill_manager.ahk` — 技能管理器（含 `_Notify` 实现）
- `domain/key_recorder.ahk` — 键录制器（仅检查 #Include）
- `domain/key_validator.ahk` — 键验证器（仅检查 #Include）

**基础设施层 (infrastructure/)**
- `infrastructure/error_system.ahk` — 错误处理系统
- `infrastructure/utils.ahk` — 通用工具函数（`_GetProp`/`_GetField` 定义点）
- `infrastructure/joy_sender.ahk` — 手柄按键发送器
- `infrastructure/joy_hotkey_manager.ahk` — 手柄热键管理器（**反向依赖**）
- `infrastructure/backup_core.ahk` — 备份核心（仅检查 #Include）

**应用层 (application/)**
- `application/config_service.ahk` — 配置管理服务（含 `BackupCore` 调用与 `_Notify` 实现）
- `application/group_service.ahk` — 分组服务（仅检查 #Include 与 `BackupCore` 调用）

**表现层 (presentation/)**
- `presentation/webview2_manager.ahk` — WebView2 管理器（前 200 行 + `BackupCore` 调用点）
- `presentation/ui_manager.ahk` — UI 管理器（`Notify` 实现）
- `presentation/gui_manager.ahk` — GUI 管理器（仅检查 #Include 与 `BackupCore` 调用）
- `presentation/backup_ui.ahk` — 备份 UI（仅检查 `BackupCore` 调用）

**根目录**
- `main.ahk` — 主入口文件（依赖注入与初始化流程）

### 审查方法
- 使用 `Select-String` 全量扫描 `#Include` 指令、`_GetProp/_GetField`、`BackupCore.`、`ErrorSystem.Log/LogError`、`_Notify/Notify(`、文件 I/O API
- 对关键文件使用 `Read` 工具逐行审查
- 基于依赖关系图分析循环依赖与分层违规

---

## 发现清单

### Finding 1

- **位置**: `domain/joystick_executor.ahk:16`
- **维度**: 架构合规性 / DDD 层依赖违规
- **严重级别**: Critical
- **描述**: 领域层文件 `domain/joystick_executor.ahk` 通过 `#Include "../infrastructure/joy_sender.ahk"` 直接引用基础设施层的 `JoySender` 模块。该文件中 `JoystickExecutor._SendJoyKey`（第 149-178 行）与 `_ReleaseJoyKeys`（第 180-199 行）直接调用 `JoySender.SendBtn/SendPov/SendAxis` 等具体方法，形成领域层对基础设施实现细节的硬依赖。
- **根因**: `JoystickExecutor` 作为领域执行器，需要发送手柄按键，但未通过 `domain/interfaces.ahk` 中定义的抽象接口（如 `IExecutor`）反转依赖，而是直接 `#Include` 基础设施实现类。这违反了 AGENTS.md「AHK 已知架构妥协」第 1 项的约束边界。
- **违反约束**: AGENTS.md 妥协 #1 明确规定"仅允许 `domain/` 引用 `infrastructure/error_system.ahk` 的 `LogError` 方法。禁止领域层引用 `infrastructure/` 中的其他模块"。`joy_sender.ahk` 不在豁免清单内。
- **修复建议**:
  1. 在 `domain/interfaces.ahk` 中新增 `IJoySender` 抽象基类，定义 `SendBtn/SendPov/SendAxis/IsVJoyAvailable` 等方法契约
  2. `infrastructure/joy_sender.ahk` 中的 `JoySender` 类 `extends IJoySender`
  3. `domain/joystick_executor.ahk` 删除 `#Include "../infrastructure/joy_sender.ahk"`，改为通过注入的 `IJoySender` 实例调用（参考 `SkillGroup.Notifier` 的注入模式）
  4. 在 `main.ahk` 的 `InitDependencies()` 中完成注入：`JoystickExecutor.JoySender := JoySender`

---

### Finding 2

- **位置**: `presentation/backup_ui.ahk:61,86,100,126,142,153`、`presentation/gui_manager.ahk:238`、`presentation/webview2_manager.ahk:712,725,726,745,746,754,1135,1144`
- **维度**: 架构合规性 / DDD 分层违规
- **严重级别**: Important
- **描述**: 表现层多个文件直接调用基础设施层的 `BackupCore` 类方法（`ListBackups/RestoreBackup/DeleteBackup/CreateBackup/RecordConfigChange`），跳过应用层中转。具体调用点：
  - `presentation/backup_ui.ahk:61` `BackupCore.ListBackups()`
  - `presentation/backup_ui.ahk:100` `BackupCore.RestoreBackup(backupPath)`
  - `presentation/backup_ui.ahk:142` `BackupCore.DeleteBackup(backupPath)`
  - `presentation/backup_ui.ahk:153` `BackupCore.CreateBackup(config)`
  - `presentation/gui_manager.ahk:238` `BackupCore.CreateBackup(config, backupLabel)`
  - `presentation/webview2_manager.ahk:712` `BackupCore.CreateBackup(config)`
  - `presentation/webview2_manager.ahk:726` `BackupCore.RestoreBackup(backupPath)`
  - `presentation/webview2_manager.ahk:746` `BackupCore.DeleteBackup(backupPath)`
  - `presentation/webview2_manager.ahk:754` `BackupCore.ListBackups()`
  - `presentation/webview2_manager.ahk:1135` `BackupCore.RecordConfigChange(...)`
- **根因**: 表现层未通过应用层（`ConfigService`/`GroupService`）访问备份能力，而是直接持有 `BackupCore` 全局类引用。这绕过了应用层的事务协调与回滚保护逻辑。
- **违反约束**: AGENTS.md「AHK v2 架构（DDD 四层）」表格隐含的分层规则——表现层应通过应用层访问基础设施层。此违规不在已知妥协 #3 范围内（妥协 #3 仅豁免 `application/config_service.ahk` 对 `BackupCore` 的引用）。
- **修复建议**:
  1. 在 `application/config_service.ahk` 或新建 `application/backup_service.ahk` 中封装备份相关 API：`ListBackups/RestoreBackup/DeleteBackup/CreateBackup/RecordConfigChange`
  2. 表现层改为调用 `ConfigService.ListBackups()` 等应用层方法
  3. 表现层文件移除对 `infrastructure/backup_core.ahk` 的 `#Include`（当前 `presentation/backup_ui.ahk:14`、`presentation/gui_manager.ahk:18` 均有此引用）

---

### Finding 3

- **位置**: `AGENTS.md`「AHK 已知架构妥协」第 2 项 vs `domain/interfaces.ahk:51`、`presentation/webview2_manager.ahk`
- **维度**: 文档与代码一致性
- **严重级别**: Important
- **描述**: AGENTS.md 妥协 #2 描述"`domain/interfaces.ahk` 定义 `_Notify` 签名为 `(event, data)`，`presentation/webview2_manager.ahk` 使用 `(event, data, meta*)` 可变参数"，与实际代码完全不符：
  - `domain/interfaces.ahk:51` 实际定义的是 `INotifier.Notify(message, type := "info", duration := 0)`，**不存在** `_Notify(event, data)` 方法
  - `presentation/webview2_manager.ahk` 中**完全没有** `_Notify` 方法定义
  - 真实存在的 `_Notify` 方法定义在：
    - `domain/skill_group.ahk:892` `static _Notify(message, type := "info")`
    - `domain/skill_manager.ahk:660` `static _Notify(message, type := "info")`
    - `application/config_service.ahk:376` `static _Notify(message, type := "info", duration := 0)`
  - 表现层实现是 `presentation/ui_manager.ahk:42` `static Notify(message, type := "info", duration := 0)`
- **根因**: AGENTS.md 中的妥协描述基于已重构的旧版本接口契约，文档未随代码演进而更新。当前所有 `_Notify` 实现均使用 `(message, type)` 双参数形式，调用方一致，不存在签名差异问题。
- **违反约束**: AGENTS.md「AHK 已知架构妥协」第 2 项的描述已失效，但仍作为有效文档存在，会误导后续维护者。
- **修复建议**:
  1. 更新 AGENTS.md 妥协 #2 描述，反映当前 `INotifier.Notify(message, type, duration)` 契约
  2. 或者直接移除妥协 #2（因签名差异问题已不存在），并在「AHK 内部工具函数迁移」或新增章节记录当前 `_Notify` 的实际分布
  3. 文档同步后，此 Finding 自动消解

---

### Finding 4

- **位置**: `infrastructure/joy_hotkey_manager.ahk:14`
- **维度**: 架构合规性 / DDD 反向依赖
- **严重级别**: Important
- **描述**: 基础设施层文件 `infrastructure/joy_hotkey_manager.ahk` 通过 `#Include "../domain/joystick_input.ahk"` 引用领域层的 `JoystickInput` 具体类，并在第 38/50/54/68/194/195 等多处直接调用 `JoystickInput.IsButton/IsAxis/IsTrigger/IsPov/PovToDirection/IsJoystickConnected` 等具体静态方法。
- **根因**: `JoyHotkeyManager` 需要识别手柄按键类型，但未通过 `domain/interfaces.ahk` 中定义的抽象接口解耦，而是直接依赖领域层的具体实现类。虽然 DDD 允许基础设施层依赖领域层（实现领域接口），但直接使用具体类而非接口，削弱了可测试性与可替换性。
- **违反约束**: AGENTS.md「AHK v2 架构（DDD 四层）」隐含的依赖倒置原则。此问题不在已知妥协清单内，属于未声明的架构妥协。
- **修复建议**:
  1. 在 `domain/interfaces.ahk` 中新增 `IJoystickInputRecognizer` 抽象基类，定义 `IsButton/IsAxis/IsTrigger/IsPov/GetButtonNum/GetPovDirection/GetAxisInfo/PovToDirection/IsJoystickConnected` 等方法契约
  2. `domain/joystick_input.ahk` 中的 `JoystickInput` 类 `extends IJoystickInputRecognizer`
  3. `infrastructure/joy_hotkey_manager.ahk` 改为通过注入的抽象接口调用（或在 AHK 务实场景下，至少在 AGENTS.md「已知妥协」中显式登记此依赖）
  4. 如选择不重构，则必须在 AGENTS.md 中新增妥协 #5 显式记录此依赖及其约束边界

---

### Finding 5

- **位置**: `infrastructure/utils.ahk:44`
- **维度**: 代码组织 / 隐式依赖
- **严重级别**: Minor
- **描述**: `infrastructure/utils.ahk` 中的全局函数 `_GetField` 在第 44 行调用 `JSONParser.Parse(obj)`，但 `utils.ahk` 顶部并未 `#Include "json_parser.ahk"`。该调用依赖 `main.ahk:23` 已先加载 `json_parser.ahk` 才能正常工作。
- **根因**: `_GetField` 在 v3.1+ 迁移时引入了 JSON 字符串解析能力，但未声明对 `JSONParser` 的显式依赖。在 AHK 的 `#Include` 全局合并模型下不会运行时报错，但单独加载 `utils.ahk` 会导致 `JSONParser` 未定义。
- **违反约束**: AGENTS.md「AHK v2 文件结构」隐含的模块自包含原则。
- **修复建议**:
  1. 在 `infrastructure/utils.ahk` 顶部添加 `#Include "json_parser.ahk"`（注意 `json_parser.ahk:15` 已 `#Include "json_logger.ahk"`，需检查是否会引入重复包含——AHK v2 的 `#Include` 默认幂等，可安全添加）
  2. 或者在 `_GetField` 内部使用 `try/catch` 包裹 `JSONParser.Parse` 调用，并在 `JSONParser` 未定义时返回 `defaultVal`（当前已有外层 `try/catch`，但语义不够清晰）

---

### Finding 6

- **位置**: `json.ahk:1436`
- **维度**: 代码组织 / 重复定义
- **严重级别**: Minor
- **描述**: 根目录 `json.ahk:1436` 存在 `static _GetField(obj, field)` 方法定义，与 `infrastructure/utils.ahk:31` 的全局函数 `_GetField(obj, key, defaultVal := "")` 命名重复。虽然作用域不同（类方法 vs 全局函数），但容易造成混淆。`json.ahk` 内部第 1084-1455 行大量调用 `this._GetField(...)`。
- **根因**: `json.ahk` 是项目根目录的遗留文件（`main.ahk` 的 `#Include` 列表中未包含 `json.ahk`），其内部的 `_GetField` 是迁移前的旧实现，迁移至 `infrastructure/utils.ahk` 后未清理。
- **违反约束**: AGENTS.md「AHK 内部工具函数迁移」表格规定 `_GetField` 应统一在 `infrastructure/utils.ahk` 中定义。
- **修复建议**:
  1. 确认 `json.ahk` 是否仍在使用（从 `main.ahk` 的 `#Include` 列表看已未引用，可能是遗留测试文件）
  2. 若已废弃，将 `json.ahk` 移至 `tests/legacy/` 或删除
  3. 若仍在使用，将 `json.ahk` 中的 `static _GetField` 重命名为 `static _JsonGetField` 以避免与全局函数混淆，并改为委托调用全局 `_GetField`

---

## 无问题声明

以下检查项未发现问题：

1. **已检查 `domain/` 目录下所有文件的文件 I/O 操作**（`FileRead/FileAppend/FileDelete/FileOpen/DirCreate/DirRemove/FileCopy/FileMove`），未发现任何 I/O 操作。领域层无 I/O 泄漏，符合 DDD 纯逻辑层要求。

2. **已检查 `domain/` 是否引用 `application/` 或 `presentation/`**：所有 domain 层文件的 `#Include` 仅指向 domain 内部模块或 `infrastructure/error_system.ahk`（及违规的 `joy_sender.ahk`，见 Finding 1）。未发现领域层向上引用应用层或表现层。

3. **已检查 `ErrorSystem.LogError` 在 domain 层的使用**：`domain/` 下所有文件（`joystick_executor.ahk`、`mode_registry.ahk`、`skill_group.ahk`、`skill_manager.ahk`、`key_recorder.ahk`、`key_validator.ahk`）均仅调用 `ErrorSystem.LogError(message, level, file, line)` 方法，未访问 `ErrorSystem` 的其他成员。符合妥协 #1 的约束边界。

4. **已检查 `BackupCore` 在 `application/` 层的调用方式**：`application/config_service.ahk:121` 调用 `BackupCore.CreateBackup(beforeBackup, "pre_reload")`，`application/group_service.ahk:104,180,190,212,288` 调用 `BackupCore.CreateBackup/RecordConfigChange`，均为静态方法调用，未直接访问 `BackupCore` 内部状态。符合妥协 #3 的约束边界。

5. **已检查工具函数迁移**：`_GetProp` 与 `_GetField` 已在 `infrastructure/utils.ahk:23,31` 中定义。`presentation/webview2_manager.ahk` 中无遗留的 `_GetField` 本地定义，仅作为调用方使用全局函数。迁移已完成。

6. **已检查模块间循环依赖**：基于 `#Include` 关系构建的有向图（domain → infrastructure/error_system, domain → infrastructure/joy_sender[违规], infrastructure/joy_hotkey_manager → domain/joystick_input, application → domain+infrastructure, presentation → domain+application+infrastructure）为有向无环图（DAG），未发现循环依赖。

7. **已检查 `domain/key_recorder.ahk` 与 `domain/key_validator.ahk` 的依赖**：两者仅 `#Include "interfaces.ahk"` 与 `../infrastructure/error_system.ahk`，符合妥协 #1 约束。

---

## 统计

- **Critical**: 1 个
- **Important**: 3 个
- **Minor**: 2 个
- **总计**: 6 个

### 最关键的 3 个发现摘要

1. **[Critical] Finding 1**：`domain/joystick_executor.ahk:16` 违规引用 `infrastructure/joy_sender.ahk`，违反妥协 #1 的约束边界（仅允许引用 `error_system.ahk` 的 `LogError`）。需引入 `IJoySender` 抽象接口并通过依赖注入解耦。

2. **[Important] Finding 2**：表现层（`backup_ui.ahk`/`gui_manager.ahk`/`webview2_manager.ahk`）多处直接调用 `BackupCore` 基础设施类，跳过应用层中转，违反 DDD 分层。应在应用层封装备份 API 后由表现层调用。

3. **[Important] Finding 3**：AGENTS.md 妥协 #2 关于 `_Notify(event, data)` 签名差异的描述与实际代码完全不符（实际为 `Notify(message, type, duration)`），文档已过时，需更新或移除该妥协条目以免误导维护者。
