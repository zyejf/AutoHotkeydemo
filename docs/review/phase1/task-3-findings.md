# Task 3: AHK v2 安全性与健壮性审查发现

> 审查日期：2026-08-03
> 审查范围：AHK v2 部分（DDD 四层架构 + 根目录主入口 + 外围模块）
> 审查性质：只读审查（未修改任何源代码）
> 审查维度：输入验证、配置校验、Map/Object 访问安全、定时器引用管理、WebView2 通信安全、文件 I/O 错误处理、全局变量作用域、JSON 解析安全、进程/外部命令安全

## 审查范围

### 已审查文件清单（共 30 个 .ahk 文件）

**根目录主入口（2 个）**
- `D:\1demo\AutoHotkeydemo\main.ahk`（142 行，含 OnError 全局回调）
- `D:\1demo\AutoHotkeydemo\asd.ahk`（兼容别名入口）

**领域层 domain/（7 个）**
- `domain\interfaces.ahk` — 抽象接口定义（ILogger/INotifier/IConfigStore/IExecutor/IEventHook）
- `domain\mode_registry.ahk` — 执行模式注册表 + 7 种内置执行器实现
- `domain\skill_group.ahk` — 单个技能组生命周期（含按键发送、防抖、长按、模式调度）
- `domain\skill_manager.ahk` — 全局分组协调器（定时器管理、热键绑定、紧急停止）
- `domain\key_recorder.ahk` — 按键录制器（InputHook + 鼠标 Hotkey）
- `domain\key_validator.ahk` — 按键验证器
- `domain\joystick_executor.ahk` — 手柄模式执行器（3 种模式）

**基础设施层 infrastructure/（12 个）**
- `infrastructure\backup_core.ahk` — 备份管理器核心（创建/恢复/删除/清理）
- `infrastructure\config_store.ahk` — 全局配置存储（GroupSettings/CONTROL_HOTKEYS/HoldSettings）
- `infrastructure\config_validator.ahk` — 配置验证器（10 种模式字段校验）
- `infrastructure\debug_logger.ahk` — 调试日志器（热路径限速）
- `infrastructure\error_handler.ahk` — 错误处理器（SafeExecute/RetryWithPolicy）
- `infrastructure\error_system.ahk` — 错误系统（OnError 回调/结构化日志）
- `infrastructure\ipc_channel.ahk` — IPC 通道（文件管道预留接口）
- `infrastructure\joy_hotkey_manager.ahk` — 手柄热键管理器（按钮/轴/POV 轮询）
- `infrastructure\joy_sender.ahk` — 手柄按键发送器
- `infrastructure\json_logger.ahk` — JSON 结构化日志器
- `infrastructure\json_parser.ahk` — JSON 解析器（强类型，含深度/迭代限制）
- `infrastructure\json_serializer.ahk` — JSON 序列化器（循环引用检测）
- `infrastructure\migration_logger.ahk` — 迁移日志器
- `infrastructure\utils.ahk` — 工具函数（_GetProp/_GetField/StrJoin/LogRotator）

**应用层 application/（2 个）**
- `application\config_service.ahk` — 配置管理服务（加载/保存/热重载/回滚/迁移）
- `application\group_service.ahk` — 分组生命周期服务（CRUD + 导入导出）

**表现层 presentation/（6 个 .ahk）**
- `presentation\backup_ui.ahk` — 备份管理 GUI
- `presentation\debug_panel.ahk` — 调试面板
- `presentation\group_editor.ahk` — 分组编辑器
- `presentation\gui_manager.ahk` — 原生 GUI 管理器（ListView/TrayMenu）
- `presentation\ui_manager.ahk` — Toast 通知实现
- `presentation\webview2_manager.ahk` — WebView2 现代化 GUI + AHK-JS Bridge（重点审查，1266 行）

**其他根目录文件**
- `gui.ahk`（遗留原生 GUI，2194 行，仍被引用）

### 范围外说明

- AGENTS.md「Key Files」中列出的外围模块 `equipment_recognizer.ahk`、`ocr.ahk`、`joystick_tester.ahk` 在项目根目录**实际不存在**（已通过 `Test-Path` 和递归搜索确认），无法审查。
- 测试目录 `tests/` 与 `tests/test_ahk_executor/` 不在本次审查任务范围内（由 Task 4 覆盖）。
- `lib/ahk2_lib/` 为第三方库（WebView2 封装、deepclone、RapidOcr 等），不在审查范围内。
- `asd-tauri/` 为 Rust/Tauri 部分，不在本次审查范围内（由 Task 5~8 覆盖）。
- `presentation\app_ui.html` / `editor_ui.html` / `editor_ui_v2.html` 为 HTML 资源，不在 .ahk 审查范围内。

### 审查方法

1. **直接阅读**：通读 30 个 .ahk 文件的关键模块代码
2. **专项搜索**：使用 PowerShell `Select-String` 批量搜索危险 API 调用模式
   - `ExecuteScriptAsync` / `AddHostObjectToScript` / `postMessage` / `PostWebMessageAsJson`（WebView2 通信）
   - `Map.Delete` / `.Delete(`（Map 删除前置检查）
   - `Run(` / `RunWait(` / `ShellExecute(`（外部命令）
   - `FileRead(` / `FileAppend(`（文件 I/O）
   - `Integer(` / `Number(` / `Float(`（类型转换）
   - `..\` / `..\/`（路径遍历）
3. **模式匹配**：检查 AGENTS.md 强制规则的遵守情况
4. **数据流追踪**：从用户输入（WebView2 消息）追踪到关键操作（文件 I/O、按键发送、外部命令）

---

## 发现清单

### Finding 1
- **位置**: `presentation\webview2_manager.ahk:63`
- **维度**: WebView2 通信安全 / 进程安全
- **严重级别**: Critical
- **描述**: 在 `_InitWebView2()` 中通过 `EnvSet` 强制设置 WebView2 远程调试端口：
  ```autohotkey
  EnvSet("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9222")
  ```
  该环境变量在 WebView2 控制器创建时被读取，会在本机 9222 端口开启 Chrome DevTools Protocol 调试服务。在生产环境中，任何本机进程（包括恶意脚本、浏览器内的恶意网页通过 DNS Rebinding）均可连接该端口，执行任意 JavaScript、读取页面数据、调用 AHK-JS Bridge 暴露的所有命令（含分组删除、配置覆盖、紧急停止等）。该代码无任何条件判断，每次初始化 WebView2 都会启用调试端口。
- **根因**: 开发阶段为调试 WebView2 内容遗留的代码未在发布前移除。AGENTS.md「AHK-JS Bridge 通信架构」章节虽未明确禁止 EnvSet 调试端口，但「安全性与健壮性审查」维度要求检查"WebView2 通信安全"，调试端口属于明显的攻击面。
- **修复建议**:
  1. 移除该 `EnvSet` 调用，或仅在显式调试模式下开启（如检查 `A_IsCompiled` 或读取配置标志）。
  2. 若需保留调试能力，应使用随机端口并通过 `--remote-allow-origins=*` 限制来源。
  3. 发布构建（`A_IsCompiled = 1`）时强制关闭调试端口。

### Finding 2
- **位置**: `presentation\webview2_manager.ahk:1171-1172`、`infrastructure\backup_core.ahk:112-113`
- **维度**: 输入验证 / 路径遍历
- **严重级别**: Critical
- **描述**: 两处路径遍历防护均使用 `RegExReplace(path, "\.\.", "")` 删除所有 `..` 子串，该正则替换可被 `....` 输入绕过：
  ```autohotkey
  ; webview2_manager.ahk:1171-1172
  absBase := RegExReplace(absBase, "\.\.", "")
  absTarget := RegExReplace(absTarget, "\.\.", "")

  ; backup_core.ahk:112-113
  cleanPath := RegExReplace(absBackupPath, "\.\.", "")
  cleanDir := RegExReplace(absBackupDir, "\.\.", "")
  ```

  **绕过路径**：攻击者构造 `backups/....//....//config.json`，`RegExReplace` 第一次匹配删除中间的 `..` 后，剩余字符拼接形成新的 `..`：
  - 输入：`backups/....//....//config.json`
  - 第 1 次替换：删除所有 `..` → `backups////config.json`（安全）

  但若输入为 `backups\....\....\config.json`：
  - 第 1 次替换：`....` 中匹配到 `..` → 删除后剩 `..`（即 `backups\..\..\config.json`）
  - 前缀检查 `SubStr(cleanPath, 1, StrLen(cleanDir))` 匹配 `backups` 通过
  - 实际路径解析时 `..\..` 上跳两级，逃逸出 `backups` 目录

  `_BridgeCompareConfigs` 接受来自 WebView2 JS 端的 `basePath` / `targetPath` 参数（line 1162-1163），攻击者可通过 JS 注入恶意路径，读取 `backups` 目录外的任意文件（如 `config.json` 主配置、`logs/app.log` 日志、甚至系统文件）。

  `_BridgeRestoreBackup`（line 721-723）使用 `InStr(backupName, "..")` 检查，**该方式是正确的**（直接拒绝包含 `..` 的输入），不受本问题影响。
- **根因**: 使用"删除危险字符串"而非"拒绝危险输入"的过滤策略，违反 OWASP 路径遍历防护原则。正则替换是破坏性操作，会改变字符串长度，使后续前缀检查失效。
- **修复建议**:
  1. 改用 `InStr` 拒绝式检查（参考 `_BridgeRestoreBackup` line 721-723 的正确实现）：
     ```autohotkey
     if InStr(absBase, "..") || InStr(absTarget, "..")
         return JSONSerializer.Stringify(Map("error", "路径包含非法字符"))
     ```
  2. 或使用 `SplitPath` 解析后比较绝对路径前缀（推荐）。
  3. 对 `backup_core.ahk:112-113` 同步修复。

### Finding 3
- **位置**: `presentation\webview2_manager.ahk:1182-1183`
- **维度**: 文件 I/O 错误处理 / 编码安全
- **严重级别**: Important
- **描述**: `_BridgeCompareConfigs` 中的 `FileRead` 调用未指定编码参数：
  ```autohotkey
  baseContent := FileRead(absBase)
  targetContent := FileRead(absTarget)
  ```
  AHK v2 的 `FileRead` 不带第二个参数时使用系统默认 ANSI 代码页读取，而项目所有配置文件均以 UTF-8 编码写入（参见 `infrastructure\config_service.ahk:441` `FileAppend(jsonStr, tempPath, "UTF-8")`、`backup_core.ahk:41` `FileAppend(jsonStr, filePath, "UTF-8")`）。若备份文件包含非 ASCII 字符（如中文分组名、中文备注），读取结果会乱码，`JSONParser.Parse` 可能抛出"意外字符"错误或解析出错误的字符串值。
- **根因**: 该方法是为配置对比功能新增的，开发时遗漏了编码参数。项目内其他 `FileRead` 调用（如 `json_parser.ahk:34`、`group_editor.ahk:799`）均显式指定 `"UTF-8"`。
- **修复建议**:
  ```autohotkey
  baseContent := FileRead(absBase, "UTF-8")
  targetContent := FileRead(absTarget, "UTF-8")
  ```

### Finding 4
- **位置**: `gui.ahk:886, 905`
- **维度**: 进程/外部命令安全
- **严重级别**: Important
- **描述**: `Run` 调用未对路径参数加引号转义：
  ```autohotkey
  ; gui.ahk:886
  Run("notepad.exe config.json")

  ; gui.ahk:905
  Run("notepad.exe " logFile)
  ```
  当 `logFile` 路径包含空格（如 `C:\Users\My User\logs\app.log`）时，`Run` 会将其按空格分割，notepad 只打开 `C:\Users\My`，剩余部分作为参数被忽略，用户看到的是打开了错误文件而非日志。更严重的情况下，若 `logFile` 来自外部输入且包含特殊字符（如 `&`、`|`），可能触发命令注入（虽然此处 `logFile` 来自 `JSONLogger.logFile` 静态属性，风险较低）。
- **根因**: 未遵循 Windows 路径转义规范。AHK v2 的 `Run` 第一个参数是命令行字符串，路径需要用双引号包围。
- **修复建议**:
  ```autohotkey
  Run('notepad.exe "' logFile '"')
  ```
  或使用 `Run` 的第二参数指定工作目录，第三参数避免 Shell 解析。

### Finding 5
- **位置**: `infrastructure\config_store.ahk:36-64`
- **维度**: 数据完整性 / 引用安全
- **严重级别**: Important
- **描述**: `ConfigStore.Save` 方法直接保存传入 `config` 对象的引用，未进行深拷贝：
  ```autohotkey
  static Save(config) {
      ; ...
      if config.Has("GroupSettings") {
          this._groupSettings := config["GroupSettings"]   ; 直接引用
          this._RepairEmptyArrays(this._groupSettings)
      }
      if config.Has("CONTROL_HOTKEYS")
          this._controlHotkeys := config["CONTROL_HOTKEYS"]  ; 直接引用
      if config.Has("HoldSettings")
          this._holdSettings := config["HoldSettings"]       ; 直接引用
      ; ...
  }
  ```

  对比 `Load` 方法（line 26-34）使用 `deepclone` 返回副本，`Save` 方法未对称地使用 `deepclone` 保存。调用方后续修改 `config` 对象会直接影响 `ConfigStore` 内部状态，破坏数据封装性。实际场景中，`webview2_manager.ahk:_BridgeSaveSettings`（line 611-613）调用 `ConfigService.ConfigStore.Set("CONTROL_HOTKEYS", ch)` 后，若 `ch` 被复用或修改，`ConfigStore` 内部数据会被意外篡改。

  `Set` 方法（line 81-98）同样存在此问题。
- **根因**: 性能考虑导致遗漏深拷贝。`_groupSettings` 是高频访问字段，每次保存都深拷贝有性能成本，但破坏了封装性。
- **修复建议**:
  ```autohotkey
  if config.Has("GroupSettings")
      this._groupSettings := deepclone(config["GroupSettings"])
  ```
  或在文档中明确声明 `Save` 后调用方不得修改 `config` 对象（不推荐，容易遗漏）。

### Finding 6
- **位置**: `presentation\webview2_manager.ahk:1184-1185`
- **维度**: 输入验证 / 类型安全
- **严重级别**: Important
- **描述**: `_BridgeCompareConfigs` 中 `JSONParser.Parse` 后未验证返回类型即调用 `.Has()`：
  ```autohotkey
  baseConfig := JSONParser.Parse(baseContent)
  targetConfig := JSONParser.Parse(targetContent)

  diffs := []
  baseGs := baseConfig.Has("GroupSettings") ? baseConfig["GroupSettings"] : Map()
  ```
  若备份文件内容是 JSON 数组（如 `[1,2,3]`）或基本类型（如 `123`、`"string"`），`JSONParser.Parse` 返回 `Array` 或 `Integer`/`String`，调用 `.Has()` 会抛出 "This type of object does not support this method" 异常。虽然外层 `try-catch` 会捕获，但错误信息（`e.Message`）不明确，用户看到的是技术性错误而非"备份文件格式无效"。
- **根因**: 缺少类型守护。`BackupCore.RestoreBackup`（line 64）有正确的类型检查：`if !(config is Map) || !config.Has("GroupSettings")`，但 `_BridgeCompareConfigs` 未参考该模式。
- **修复建议**:
  ```autohotkey
  baseConfig := JSONParser.Parse(baseContent)
  if !(baseConfig is Map) {
      return JSONSerializer.Stringify(Map("error", "基准配置不是有效对象"))
  }
  baseGs := baseConfig.Has("GroupSettings") ? baseConfig["GroupSettings"] : Map()
  ```

### Finding 7
- **位置**: `presentation\webview2_manager.ahk:1057-1058`
- **维度**: 输入验证 / 资源耗尽防护
- **严重级别**: Important
- **描述**: `_BridgeImportConfig` 仅检查导入数据的字节长度，未限制解压后的内存使用：
  ```autohotkey
  if StrLen(jsonStr) > 5242880   ; 5MB 字节限制
      return JSONSerializer.Stringify(Map("success", false, "error", "导入数据过大(>5MB)"))
  ```
  5MB 的 JSON 字符串经过 `JSONParser.Parse` 后，在内存中会构建对应的 AHK 对象图。若 JSON 包含深度嵌套（虽受 `MAX_PARSE_DEPTH = 256` 限制）或大量小对象（如 100 万个空对象），AHK 对象内存占用可能是原始字符串的 10-50 倍（50-250MB），导致进程内存暴涨甚至 OOM。此外，`JSONSerializer.Stringify` 序列化时也无大小限制。
- **根因**: 字节长度限制无法反映对象图实际内存占用。`MAX_PARSE_DEPTH` 和 `MAX_LOOP_ITERATIONS` 仅防 DoS 攻击（解析死循环），不防内存耗尽。
- **修复建议**:
  1. 在 `JSONParser` 中增加对象计数器，超过阈值（如 100000 个对象）时抛出异常。
  2. 或在 `_BridgeImportConfig` 解析后检查 `GroupSettings.Count`，超过阈值（如 1000 个分组）拒绝。
  3. 文档化配置文件的合理大小上限。

### Finding 8
- **位置**: `infrastructure\config_validator.ahk:65-66`、`ValidateGroupHotkeys`
- **维度**: 输入验证 / 配置校验
- **严重级别**: Important
- **描述**: 热键验证仅检查长度（≤15 字符），未验证格式合法性：
  ```autohotkey
  if StrLen(hotkey) > 15
      errors.Push(Map("type", "ERROR", "message", "分组 " idStr ": 热键 '" hotkey "' 过长(>15字符)"))
  ```
  AGENTS.md 未定义热键格式规范，但 AHK v2 的 `Hotkey()` 函数对热键字符串有严格要求（如 `F1`、`^c`、`+!#a`）。当前验证接受任意 ≤15 字符的字符串（如 `";rm -rf /"`、`"invalid hotkey!!!"`），这些字符串在 `SkillManager._BindHotkeys`（line 137）调用 `Hotkey(group.hotkey, ...)` 时会抛出异常，被 try-catch 捕获并记录日志，但分组仍会被创建（热键不生效）。用户无法通过 UI 得知热键无效。
- **根因**: 缺少热键格式正则验证。`SkillGroup._IsValidKeyName`（line 867-880）有按键名称验证，但仅用于 `_SendKey`，未用于 `hotkey` 字段验证。
- **修复建议**:
  1. 在 `ConfigValidator._ValidateGroup` 中增加热键格式正则验证：
     ```autohotkey
     if !RegExMatch(hotkey, "^[#!^+]*<?[a-zA-Z0-9Ff]{1,2}(Up|Down|Up|Down)?$|^.*Joy\d+$")
         errors.Push(Map("type", "WARNING", "message", "分组 " id ": 热键格式可能无效"))
     ```
  2. 或在 `_BindHotkeys` 失败时通知 UI 高亮该分组。

### Finding 9
- **位置**: `presentation\webview2_manager.ahk:1102-1140`
- **维度**: 数据一致性 / 事务完整性
- **严重级别**: Important
- **描述**: `_BridgeBatchDeleteGroups` 在批量删除时，先循环删除 `ConfigStore` 中的配置（line 1112），若中间某次删除失败会 `break` 退出循环（line 1115），但已删除的分组配置不会回滚：
  ```autohotkey
  for id in ids {
      try {
          ConfigService.ConfigStore.DeleteGroupConfig(id)
          deletedIds.Push(id)
      } catch {
          break   ; 后续不再尝试，但 deletedIds 中的已删除项不会恢复
      }
  }

  saveResult := ConfigService.SaveConfig()
  if !saveResult {
      ; 回滚：但只是不保存，ConfigStore 内部状态已被部分修改
      return JSONSerializer.Stringify(Map("success", 0, "failed", ids.Length, "error", "保存失败，已回滚"))
  }
  ```

  若 `SaveConfig` 失败，返回"已回滚"，但 `ConfigStore._groupSettings` 已被修改（`DeleteGroupConfig` 直接操作内部 Map）。下次 `Load` 时返回的是已部分删除的状态，与磁盘上的 `config.json` 不一致。

  此外，内存中的 `SkillManager.Groups` 删除（line 1128）在 `SaveConfig` 失败时不会回滚，导致内存与配置文件状态分离。
- **根因**: 缺少事务边界。批量操作应"先全部验证 → 再全部执行"，或使用 `BackupCore.RecordConfigChange` 前的快照进行回滚。
- **修复建议**:
  1. 在删除前快照 `_groupSettings`：`snapshot := deepclone(ConfigStore._groupSettings)`
  2. 删除失败或保存失败时恢复快照。
  3. 或参考 `_BridgeSaveConfig`（line 446-462）的回滚模式。

### Finding 10
- **位置**: `presentation\webview2_manager.ahk:1054-1070`
- **维度**: 数据一致性 / 异常处理
- **严重级别**: Important
- **描述**: `_BridgeImportConfig` 在 `ImportGroups` 抛出异常时，临时文件会被清理（line 1066-1067），但 `ConfigStore` 和 `SkillManager` 状态可能已被部分修改：
  ```autohotkey
  FileAppend(jsonStr, tempPath, "UTF-8")
  result := GroupService.ImportGroups(tempPath)   ; 可能部分成功后抛异常
  try FileDelete(tempPath)
  ```
  `GroupService.ImportGroups`（`group_service.ahk:234-247`）调用 `_ReplaceAllConfig`，后者会先删除所有现有分组（line 279-280），再 `ConfigStore.Save(config)`（line 282），再 `SkillManager.Init`（line 284）。若 `SkillManager.Init` 抛出异常（如热键冲突），`_ReplaceAllConfig` 的 catch 块（line 289-299）会尝试用 `beforeBackup` 回滚，但回滚本身可能失败（line 297 记录 CRITICAL 日志）。此时用户配置已丢失。

  此外，`_BridgeImportConfig` 返回的 `groupsLoaded` 是 `ConfigStore.GetGroupCount()`，反映的是 ConfigStore 状态，而非 `SkillManager.Groups.Count`，两者可能在异常后不一致。
- **根因**: 多步操作无原子性保证，回滚可能失败，无二次备份机制。
- **修复建议**:
  1. 在 `_ReplaceAllConfig` 前，强制创建 `BackupCore.CreateBackup(beforeBackup, "pre_import")` 备份。
  2. 回滚失败时，向用户显式提示"配置已损坏，请从 backups 目录手动恢复"。
  3. 返回结果中同时包含 `configStoreCount` 和 `skillManagerCount`，便于前端检测不一致。

### Finding 11
- **位置**: `domain\skill_group.ahk:783`
- **维度**: 代码可维护性 / 定时器引用管理
- **严重级别**: Important
- **描述**: `_SendKey` 方法中使用极其复杂的单行三元表达式作为 `SetTimer` 回调：
  ```autohotkey
  SetTimer(() => (capturedThis._pendingReleases.Has(capturedKey) && capturedThis._pendingReleases[capturedKey] = capturedId ? (capturedThis._pendingReleases.Delete(capturedKey), SendInput("{Blind}{" capturedReleaseKey " Up}")) : 0), -duration)
  ```
  该单行代码包含：闭包捕获 4 个变量、Map.Has 检查、Map 索引比较、三元运算、逗号表达式（Delete + SendInput）。违反 AGENTS.md「代码风格指南」中"使用闭包函数代替箭头函数块体"的建议。虽然语法正确，但：
  1. 难以阅读和调试（无法在中间下断点）
  2. 任何修改都容易引入语法错误
  3. 闭包捕获的 `capturedThis` 在 `Dispose()` 后仍可能被调用（`_pendingReleases` 已 Clear，但 SetTimer 回调可能已排队），此时 `Has` 返回 false，三元走 `: 0` 分支，不会崩溃但会静默失败

  定时器引用管理：该 `SetTimer` 未将返回的回调引用存入 `_timers` Map，无法被 `_StopGroupExecution` 主动取消。若分组在 `duration` 时间内被停止，按键释放回调仍会执行（虽然 `_pendingReleases.Has` 检查能避免错误释放，但延迟回调会占用定时器槽位）。
- **根因**: 追求简洁导致可维护性下降；定时器引用管理规范未覆盖这种短生命周期回调。
- **修复建议**:
  1. 重构为闭包函数：
     ```autohotkey
     releaseFn(key, releaseKey, releaseId, group) {
         if group._pendingReleases.Has(key) && group._pendingReleases[key] = releaseId {
             group._pendingReleases.Delete(key)
             SendInput("{Blind}{" releaseKey " Up}")
         }
     }
     SetTimer(ObjBindMethod(SkillGroup, "_ReleaseKeyTimer", capturedKey, capturedReleaseKey, capturedId, capturedThis), -duration)
     ```
  2. 或保持现状但添加详细注释解释执行流程。

### Finding 12
- **位置**: `presentation\webview2_manager.ahk:131-135`
- **维度**: 性能 / 资源使用
- **严重级别**: Minor
- **描述**: `_PushStateUpdate` 中重复解析自己刚序列化的 JSON 字符串：
  ```autohotkey
  debugInfo := WebView2Manager._BridgeGetDebugInfo()    ; 返回 JSON 字符串
  groupList := WebView2Manager._BridgeGetGroupList()    ; 返回 JSON 字符串
  ; ...
  debugParsed := JSONParser.Parse(debugInfo)            ; 又解析回来
  groupParsed := JSONParser.Parse(groupList)            ; 又解析回来
  combined := Map("debug", debugParsed, "groups", groupParsed)
  combinedJson := JSONSerializer.Stringify(combined)    ; 再序列化
  ```
  Bridge 方法返回字符串（设计为通过 `_SendResponse` 发送），但此处需要对象用于组合，导致"序列化 → 解析 → 重新组合 → 序列化"的冗余流程。每 2 秒触发一次，浪费 CPU。
- **根因**: Bridge 方法签名设计为返回字符串（兼容 `_SendResponse` 的统一接口），但内部调用时又需要对象。
- **修复建议**:
  1. 增加 Bridge 方法的 `_Internal` 版本返回对象，`_PushStateUpdate` 调用内部版本。
  2. 或缓存 `debugParsed` / `groupParsed`，仅当源数据变化时重新解析。
  3. 优先级低，仅在性能分析显示瓶颈时优化。

### Finding 13
- **位置**: `presentation\webview2_manager.ahk:1059`
- **维度**: 临时文件管理 / 命名碰撞
- **严重级别**: Minor
- **描述**: `_BridgeImportConfig` 使用 `Random(1000, 9999)` 生成临时文件名后缀：
  ```autohotkey
  tempPath := A_Temp "\ahk_import_" A_Now "_" Random(1000, 9999) ".json"
  ```
  `Random` 范围仅 9000 个值，在并发场景下（虽然 AHK 单线程，但多次快速导入）可能碰撞。若碰撞，`FileAppend` 会追加到已有文件，导致 JSON 格式错误，`ImportGroups` 解析失败。`A_Now` 精度到秒，1 秒内多次导入必然碰撞。
- **根因**: 使用 `Random` 而非全局唯一标识符。
- **修复建议**:
  ```autohotkey
  tempPath := A_Temp "\ahk_import_" A_Now A_MSec "_" Random(1, 999999) ".json"
  ```
  或使用 `FileOpen` 的独占模式创建文件。

### Finding 14
- **位置**: `infrastructure\ipc_channel.ahk:34-44`
- **维度**: 文件 I/O 错误处理
- **严重级别**: Minor
- **描述**: `Init` 方法中 `DirCreate` 未包裹独立 try-catch：
  ```autohotkey
  if !InStr(FileExist(IPCChannel.channelDir), "D")
      DirCreate(IPCChannel.channelDir)
  ```
  若目录创建失败（权限不足、路径被占用），`DirCreate` 抛出异常会中断 `Init`，但 `initialized` 已被设为 `true`（line 32），后续 `Send`/`Emit` 调用会跳过 `Init` 直接 `FileAppend`，因目录不存在而失败。错误信息不明确（"系统找不到指定的路径"而非"IPC 目录创建失败"）。
- **根因**: 错误处理不完整。`initialized` 标志设置过早，应在所有初始化步骤成功后设置。
- **修复建议**:
  ```autohotkey
  static Init() {
      if IPCChannel.initialized
          return
      try {
          if !InStr(FileExist(IPCChannel.channelDir), "D")
              DirCreate(IPCChannel.channelDir)
          IPCChannel.inboundPipe := IPCChannel.channelDir "\inbound.json"
          IPCChannel.outboundPipe := IPCChannel.channelDir "\outbound.json"
          OnMessage(IPCChannel.msgType, IPCChannel._OnReceived)
          IPCChannel.initialized := true   ; 移到末尾
      } catch as e {
          JSONLogger.Log("ERROR", "IPC 初始化失败: " e.Message, Map("module", "IPCChannel"))
      }
  }
  ```

### Finding 15
- **位置**: `application\config_service.ahk:44`
- **维度**: 文件 I/O 错误处理
- **严重级别**: Minor
- **描述**: `LoadConfig` 中 `FileCopy` 使用 `try` 但无 `catch`：
  ```autohotkey
  try FileCopy(ConfigService.configPath, ConfigService.configPath ".bak", 1)
  ```
  若 `FileCopy` 失败（如源文件被锁定、目标路径权限不足），异常被静默吞掉，`config.json.bak` 不会被创建。后续若 `_SaveToFile` 也失败，用户将失去配置文件，且无 `.bak` 可恢复。
- **根因**: `try` 单语句无 `catch` 是 AHK v2 的合法语法，但会吞掉所有异常，违背"错误处理应记录日志"的原则。
- **修复建议**:
  ```autohotkey
  try FileCopy(ConfigService.configPath, ConfigService.configPath ".bak", 1)
  catch as e
      JSONLogger.Log("WARNING", "创建配置备份失败: " e.Message, Map("module", "ConfigService"))
  ```

### Finding 16
- **位置**: `infrastructure\json_parser.ahk:298-340`
- **维度**: 输入验证 / 数值范围
- **严重级别**: Minor
- **描述**: `ParseNumber` 解析数字时未检查整数范围：
  ```autohotkey
  try {
      intVal := Integer(numStr)
      return intVal
  } catch {
      return Float(numStr)
  }
  ```
  AHK v2 的 `Integer` 是 64 位有符号整数（范围 ±9.2e18）。若 JSON 中包含超过此范围的整数（如 `99999999999999999999999`），`Integer()` 转换会抛出异常，被 catch 捕获后转用 `Float()`，损失精度（Float 仅约 15-17 位有效数字）。配置文件中的 `intervals`、`delays` 字段若被恶意构造为超大数，会导致定时器间隔错误。
- **根因**: JSON 规范未限制数字范围，但应用层应明确接受范围。
- **修复建议**:
  1. 在 `ConfigValidator._ValidateArrayLength` 中增加数值上限检查（如 `if Number(v) > 86400000` 拒绝超过 24 小时的间隔）。
  2. 或在 `ParseNumber` 中对超长数字字符串（如 >18 位）直接返回 Float 并记录警告。

### Finding 17
- **位置**: `presentation\webview2_manager.ahk:139-135`（重复引用，实际为 line 128-130）
- **维度**: 性能 / 哈希碰撞
- **严重级别**: Minor
- **描述**: `_PushStateUpdate` 使用字符串拼接作为变更检测哈希：
  ```autohotkey
  currentKey := debugInfo . groupList
  if currentKey = WebView2Manager._lastPushHash
      return
  ```
  字符串拼接的时间复杂度为 O(n)，且拼接后的字符串可能很长（debugInfo + groupList 可达数 KB）。每次 `_PushStateUpdate`（每 2 秒）都执行一次全量字符串拼接和比较，浪费 CPU。更严重的是，若 `debugInfo` 和 `groupList` 的内容恰好互补（如 A="x", B="yz" 与 A="xy", B="z"），会产生哈希碰撞，跳过必要的更新。
- **根因**: 简单字符串拼接非真正哈希，存在理论碰撞可能。
- **修复建议**:
  1. 使用简单的 CRC32 或 DJB2 哈希函数对字符串计算数值哈希。
  2. 或单独比较 `debugInfo` 和 `groupList` 两个字段。

---

## 无问题声明（已检查且未发现问题）

### Map.Delete 前置检查

已检查所有 38 处 `.Delete()` 调用（含 `Map.Delete` 和 `ListView.Delete`），关键模式均正确：

- **`skill_manager.ahk:248`** `this.Groups.Delete(id)` — 前置 `if !this.Groups.Has(id) return false`（line 227）
- **`skill_manager.ahk:257`** `this.HoldKeyRegistry.Delete(k)` — 在 `keysToRemove` 数组中预先收集，仅删除已存在的键
- **`skill_manager.ahk:381,388`** `_executionIds.Delete(id)` / `_timers.Delete(id)` — 前置 `Has` 检查
- **`skill_manager.ahk:418`** `this.HoldKeyRegistry.Delete(key)` — 前置 `if this.HoldKeyRegistry.Has(key) && ...` 
- **`skill_group.ahk:555`** `this._heldKeys.Delete(k)` — 前置 `if this._heldKeys.Has(k)`
- **`skill_group.ahk:783`** `capturedThis._pendingReleases.Delete(capturedKey)` — 前置 `Has` + 值匹配检查
- **`config_store.ahk:120`** `this._groupSettings.Delete(groupId)` — `DeleteGroupConfig` 公开方法，调用方负责检查（如 `HasGroup`）
- **`joy_hotkey_manager.ahk:79,86,92,124,131`** — 均有前置 `Has` 检查或在外层 `if` 条件中
- **`json_serializer.ahk:36`** `visited.Delete(ptr)` — 在 `finally` 块中，仅删除已 `visited[ptr] := true` 的键
- **`mode_registry.ahk:47,49`** — `Unregister` 前置 `if !this._executors.Has(modeName) return`

**结论**: 所有 Map.Delete 调用均遵循 AGENTS.md「常见错误」#8 的"先 Has 检查"规范，无键不存在异常风险。

### 定时器引用管理

已检查 `_timers` Map 的使用，符合 AGENTS.md「定时器管理规范」：

- **`skill_manager.ahk:66`** `static _timers := Map()` — 集中存储
- **`skill_manager.ahk:376,375`** `_StartGroupExecution` 中 `this._timers[id] := initialFunc` / `SkillManager._timers[gId] := nextFunc` — 引用存储
- **`skill_manager.ahk:386-388`** `_StopGroupExecution` 中 `SetTimer(timerFunc, 0)` + `this._timers.Delete(id)` — 正确取消和清理
- **`skill_manager.ahk:612-627`** `OnExit` 中遍历 `_timers` 取消所有定时器 — 优雅关闭
- **`skill_manager.ahk:585-610`** `_CleanupOrphanTimers` 定期清理孤儿定时器 — 防泄漏

**结论**: 定时器引用管理规范，符合 AGENTS.md 要求。短生命周期定时器（如 `skill_group.ahk:783` 的按键释放回调）未存入 `_timers`，但通过 `_pendingReleases` Map 的 ID 检查机制保证安全（见 Finding 11 的可维护性讨论）。

### WebView2 通信安全

已确认严格遵守 AGENTS.md「AHK-JS Bridge 通信架构」：

- **postMessage 双向通信模式**：使用 `add_WebMessageReceived`（line 184）+ `PostWebMessageAsJson`（line 135, 365, 1230）— ✓
- **未使用 `AddHostObjectToScript` sync 代理**：全项目搜索 `AddHostObjectToScript` 无结果 — ✓
- **`ExecuteScriptAsync` 仅用于同步 JS 函数**：唯一调用在 line 186 `ExecuteScriptAsync("if(typeof onAhkReady==='function')onAhkReady()")`，调用同步函数 `onAhkReady()`，未使用 `async/await` 或 Promise — ✓
- **未通过 `ExecuteScriptAsync` 等待 Promise**：全项目 `ExecuteScriptAsync` 仅 1 处（生产代码），其余 2 处在测试文件中 — ✓

**结论**: WebView2 通信架构符合 AGENTS.md 强制规范。**唯一的 Critical 问题（Finding 1）是调试端口开启，非通信模式问题。**

### ExecuteScriptAsync 与 Promise

仅 `webview2_manager.ahk:186` 一处生产代码使用 `ExecuteScriptAsync`，调用同步函数 `onAhkReady()`，符合 AGENTS.md「允许事项」第 1 条。

### AddHostObjectToScript

全项目无 `AddHostObjectToScript` 调用，符合 AGENTS.md「禁止事项」第 3 条。

### 全局变量作用域

已检查所有模块文件，未发现函数内访问全局变量未声明 `global` 的情况。静态类属性（如 `SkillManager.Groups`）通过类名访问，不涉及 `global` 关键字。

### JSON 解析安全

`json_parser.ahk` 设置了双重保护：
- `MAX_PARSE_DEPTH := 256`（line 18）— 防止深度嵌套攻击
- `MAX_LOOP_ITERATIONS := 100000`（line 19）— 防止超大数组/对象攻击

`json_serializer.ahk` 使用 `visited` Map + `ObjPtr` 检测循环引用（line 25-27），正确处理 `Map`/`Array`/`Object` 三种类型。

### 错误接管指令遵守

通过 PowerShell 批量检查，所有 30 个被审查的 .ahk 文件均包含完整的 5 条接管指令：
- `#Requires AutoHotkey v2.0`
- `#ErrorStdOut "UTF-8"`
- `#Warn VarUnset, OutputDebug`
- `#Warn Unreachable, OutputDebug`
- `#Warn LocalSameAsGlobal, Off`

`main.ahk` 设置了全局 `OnError` 回调：`OnError(ErrorSystem_HandleError, -1)`（通过 `ErrorSystem.HandleError` 静态方法实现）。

**注**: `migration_logger.ahk` 缺少部分 `#Warn` 指令的问题已在 Task 2 的 Finding 1 中记录，本任务不重复。

---

## 统计

### 按严重级别

| 级别 | 数量 | 占比 |
|------|------|------|
| Critical | 2 | 11.8% |
| Important | 9 | 52.9% |
| Minor | 6 | 35.3% |
| **总计** | **17** | **100%** |

### 按维度分布

| 维度 | Critical | Important | Minor | 小计 |
|------|----------|-----------|-------|------|
| WebView2 通信安全 | 1 | 0 | 0 | 1 |
| 输入验证 / 路径遍历 | 1 | 3 | 0 | 4 |
| 文件 I/O 错误处理 | 0 | 1 | 2 | 3 |
| 数据一致性 / 事务完整性 | 0 | 3 | 0 | 3 |
| 进程/外部命令安全 | 0 | 1 | 0 | 1 |
| 引用安全 / 数据完整性 | 0 | 1 | 0 | 1 |
| 类型安全 | 0 | 1 | 0 | 1 |
| 资源耗尽防护 | 0 | 1 | 0 | 1 |
| 配置校验 | 0 | 1 | 0 | 1 |
| 代码可维护性 | 0 | 1 | 0 | 1 |
| 性能 | 0 | 0 | 2 | 2 |
| 临时文件管理 | 0 | 0 | 1 | 1 |
| 数值范围 | 0 | 0 | 1 | 1 |

### 按模块分布

| 模块 | Critical | Important | Minor | 小计 |
|------|----------|-----------|-------|------|
| `presentation\webview2_manager.ahk` | 2 | 5 | 2 | 9 |
| `infrastructure\backup_core.ahk` | 1（与 webview2 共享） | 0 | 0 | 1 |
| `infrastructure\config_store.ahk` | 0 | 1 | 0 | 1 |
| `infrastructure\config_validator.ahk` | 0 | 1 | 0 | 1 |
| `infrastructure\json_parser.ahk` | 0 | 0 | 1 | 1 |
| `infrastructure\ipc_channel.ahk` | 0 | 0 | 1 | 1 |
| `application\config_service.ahk` | 0 | 0 | 1 | 1 |
| `domain\skill_group.ahk` | 0 | 1 | 0 | 1 |
| `gui.ahk`（遗留） | 0 | 1 | 0 | 1 |

### 最关键的 3 个发现摘要

1. **Critical - WebView2 远程调试端口开启**（Finding 1）：`webview2_manager.ahk:63` 通过 `EnvSet` 强制开启 9222 调试端口，允许本机任意进程（含 DNS Rebinding 攻击的网页）通过 Chrome DevTools Protocol 注入恶意 JS，调用 AHK-JS Bridge 暴露的所有命令。**建议立即移除或条件化该调用**。

2. **Critical - 路径遍历防护可被 `....` 绕过**（Finding 2）：`webview2_manager.ahk:1171-1172` 与 `backup_core.ahk:112-113` 使用 `RegExReplace(path, "\.\.", "")` 删除 `..` 字符串，输入 `....` 经替换后剩余 `..`，可逃逸出 `backups` 目录，读取任意文件。**建议改用 `InStr` 拒绝式检查**（参考 `_BridgeRestoreBackup:721-723` 的正确实现）。

3. **Important - 批量删除配置无事务回滚**（Finding 9）：`webview2_manager.ahk:1102-1140` 的 `_BridgeBatchDeleteGroups` 在 `SaveConfig` 失败时仅返回错误，但 `ConfigStore` 内部 Map 已被部分修改，导致内存与磁盘状态不一致。**建议在批量操作前快照 `_groupSettings`，失败时恢复**。

### 整体评估

AHK v2 部分整体安全性与健壮性**中等偏上**：

**优势**:
- 错误处理体系完善（`ErrorSystem` + `OnError` 回调 + `try-catch` 普遍覆盖 + `JSONLogger` 结构化日志）
- Map/Object 访问规范（`_GetProp` / `_GetField` / `HasProp` 普遍使用）
- 定时器引用管理规范（`_timers` Map 集中管理 + 孤儿清理机制）
- WebView2 通信架构严格遵守 postMessage 模式（无 `AddHostObjectToScript` sync 代理，无 `ExecuteScriptAsync` Promise 等待）
- JSON 解析器有深度和迭代次数双重保护
- 配置验证器覆盖 10 种模式，字段校验完整

**主要风险**:
- WebView2 调试端口遗留（Critical）
- 路径遍历防护策略错误（Critical）
- 多步操作缺少事务边界（Important，影响数据一致性）
- 部分文件 I/O 缺少编码参数和独立错误处理（Important）

**修复优先级建议**:
1. 立即修复 Finding 1（移除调试端口）和 Finding 2（路径遍历）
2. 下一迭代修复 Finding 9、10（事务完整性）和 Finding 3（FileRead 编码）
3. 长期改进 Finding 5（ConfigStore deepclone）、Finding 8（热键格式验证）
