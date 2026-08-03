# Task 2: AHK v2 代码质量与可维护性审查发现

> 审查日期：2026-08-03
> 审查范围：AHK v2 部分（DDD 四层架构 + 根目录主入口）
> 审查性质：只读审查（未修改任何源代码）

## 审查范围

### 已审查文件清单（共 33 个 .ahk 文件）

**根目录主入口（2 个）**
- `D:\1demo\AutoHotkeydemo\main.ahk`
- `D:\1demo\AutoHotkeydemo\asd.ahk`

**领域层 domain/（8 个）**
- `domain\interfaces.ahk`
- `domain\joystick_executor.ahk`
- `domain\joystick_input.ahk`
- `domain\key_recorder.ahk`
- `domain\key_validator.ahk`
- `domain\mode_registry.ahk`
- `domain\skill_group.ahk`
- `domain\skill_manager.ahk`

**基础设施层 infrastructure/（14 个）**
- `infrastructure\backup_core.ahk`
- `infrastructure\config_store.ahk`
- `infrastructure\config_validator.ahk`
- `infrastructure\debug_logger.ahk`
- `infrastructure\error_handler.ahk`
- `infrastructure\error_system.ahk`
- `infrastructure\ipc_channel.ahk`
- `infrastructure\joy_hotkey_manager.ahk`
- `infrastructure\joy_sender.ahk`
- `infrastructure\json_logger.ahk`
- `infrastructure\json_parser.ahk`
- `infrastructure\json_serializer.ahk`
- `infrastructure\migration_logger.ahk`
- `infrastructure\utils.ahk`

**应用层 application/（2 个）**
- `application\config_service.ahk`
- `application\group_service.ahk`

**表现层 presentation/（7 个 .ahk）**
- `presentation\backup_ui.ahk`
- `presentation\debug_panel.ahk`
- `presentation\group_editor.ahk`
- `presentation\gui_manager.ahk`
- `presentation\ui_manager.ahk`
- `presentation\webview2_manager.ahk`
- （`presentation\app_ui.html` / `editor_ui.html` / `editor_ui_v2.html` 为 HTML 资源，不在本次 .ahk 审查范围内）

### 范围外说明

- AGENTS.md「Key Files」中列出的外围模块 `equipment_recognizer.ahk`、`ocr.ahk`、`joystick_tester.ahk` 在项目根目录**实际不存在**，无法审查（详见 Finding 23）。
- 测试目录 `tests/` 不在本次审查任务范围内。
- `lib/ahk2_lib/` 为第三方库，不在审查范围内。

---

## 发现清单

### Finding 1
- **位置**: `infrastructure\migration_logger.ahk:1-2`
- **维度**: 强制规则遵守（错误与警告接管机制）
- **严重级别**: Critical
- **描述**: 该文件仅包含 `#Requires AutoHotkey v2.0` 和 `#ErrorStdOut "UTF-8"`，**缺少以下 3 条强制接管指令**：
  - `#Warn VarUnset, OutputDebug`
  - `#Warn Unreachable, OutputDebug`
  - `#Warn LocalSameAsGlobal, Off`
- **根因**: 文件未遵循 AGENTS.md「错误与警告接管机制」章节中「所有 .ahk 文件必须包含的接管指令」的强制要求。该文件是 33 个被审查文件中**唯一**缺少 #Warn 指令的文件，其他 32 个文件均完整包含全部 5 条指令。
- **修复建议**: 在 `#ErrorStdOut "UTF-8"` 之后补充 3 条 #Warn 指令，与其他 infrastructure 层文件（如 `utils.ahk:9-11`、`json_logger.ahk:11-13`）保持一致。

### Finding 2
- **位置**: `infrastructure\joy_hotkey_manager.ahk:299`
- **维度**: 强制规则遵守（日志级别）
- **严重级别**: Important
- **描述**: 使用了 `"INFO"` 日志级别：
  ```autohotkey
  ErrorSystem.LogError("手柄已重新连接", "INFO", A_ThisFunc, A_LineNumber)
  ```
  AGENTS.md「重要提醒」与「日志系统」章节明确要求「日志级别：ERROR/WARNING/DEBUG（不使用 INFO）」。
- **根因**: 开发时遗漏了日志级别约束。注：`json_logger.ahk`（行 100/161/207/260）内部确实支持 INFO 级别的映射与计数，但这是日志框架的通用能力，不应在业务代码中实际使用。
- **修复建议**: 将 `"INFO"` 改为 `"DEBUG"`（信息性提示）或 `"WARNING"`（视语义而定）。手柄重连场景建议用 `"DEBUG"`。

### Finding 3
- **位置**: `presentation\gui_manager.ahk:79`
- **维度**: GUI 控件规范（OnEvent 静态方法引用）
- **严重级别**: Important
- **描述**: 直接传递静态方法引用作为事件回调：
  ```autohotkey
  GUIManager.controls["GroupLV"].OnEvent("ContextMenu", GUIManager._ShowContextMenu)
  ```
  AGENTS.md「常见错误」#6 明确指出：「`gui.OnEvent("Size", ClassName._OnResize)` 不能直接传递静态方法引用，必须用闭包包装」。
- **根因**: AGENTS.md 将此列为已知陷阱，但该处未遵循闭包包装模式。注：AHK v2 在某些版本/事件中可能允许此模式，但按项目规范应统一使用闭包。
- **修复建议**: 改为闭包包装形式：
  ```autohotkey
  GUIManager.controls["GroupLV"].OnEvent("ContextMenu", (lv, item, isRightClick, *) => GUIManager._ShowContextMenu(lv, item, isRightClick))
  ```

### Finding 4
- **位置**: `infrastructure\backup_core.ahk:70`
- **维度**: 架构分层（DDD 层依赖违规）
- **严重级别**: Important
- **描述**: 基础设施层模块调用了应用层定义的全局函数：
  ```autohotkey
  exportResult := ExportConfigToFile(BackupCore.currentConfigPath, config)
  ```
  `ExportConfigToFile` 定义于 `application\config_service.ahk:421`（应用层）。AGENTS.md「Crate 依赖关系」与 DDD 原则要求基础设施层不应依赖应用层。AGENTS.md「已知架构妥协」#3 仅允许 `ConfigService` 通过 `BackupCore.CreateBackup()` 静态方法调用 BackupCore，**未授权反向依赖**。
- **根因**: `ExportConfigToFile` 是模块级全局函数，AHK v2 在运行时全局解析，掩盖了静态依赖关系。`backup_core.ahk` 的 `#Include` 列表（行 14-16）也未声明对 `config_service.ahk` 的依赖。
- **修复建议**: 将 `ExportConfigToFile` 的核心文件写入逻辑下沉到基础设施层（如 `infrastructure\config_io.ahk`），让 `config_service.ahk` 与 `backup_core.ahk` 都依赖基础设施层；或让 `BackupCore.RestoreBackup` 接受一个写入回调参数。

### Finding 5
- **位置**: `infrastructure\joy_hotkey_manager.ahk:14`
- **维度**: 架构分层（DDD 层依赖违规）
- **严重级别**: Important
- **描述**: 基础设施层模块 #Include 了领域层模块：
  ```autohotkey
  #Include "../domain/joystick_input.ahk"
  ```
  AGENTS.md「Crate 依赖关系」明确依赖方向为「domain ← infrastructure」（领域层定义接口，基础设施层实现），**不允许基础设施层依赖领域层具体模块**。AGENTS.md「已知架构妥协」中也未登记此妥协。
- **根因**: `JoystickInput` 被设计为领域层抽象（提供 `IsButton`/`IsAxis`/`IsPov` 等纯函数），但被放在 `domain/` 目录，导致基础设施层反向依赖。
- **修复建议**: 将 `joystick_input.ahk` 中的纯工具函数（`IsButton`/`IsAxis`/`IsTrigger`/`IsPov`/`PovToDirection`/`IsJoystickConnected`）迁移到 `infrastructure\utils.ahk` 或新建 `infrastructure\joystick_utils.ahk`；或在 AGENTS.md「已知架构妥协」中补充登记此依赖。

### Finding 6
- **位置**: `infrastructure\config_store.ahk:119-121`
- **维度**: 错误处理（Map.Delete 不存在键）
- **严重级别**: Important
- **描述**: `DeleteGroupConfig` 公共方法直接调用 `Map.Delete` 而未先检查 `Has`：
  ```autohotkey
  static DeleteGroupConfig(groupId) {
      this._groupSettings.Delete(groupId)
  }
  ```
  AGENTS.md「常见错误」#8 明确指出：「`Map.Delete(key)` 在键不存在时抛出异常，必须先 `Map.Has(key)` 检查」。该方法为公共 API，调用方可能传入不存在的 groupId。
- **根因**: 该方法被 `webview2_manager.ahk:1112`（`_BridgeBatchDeleteGroups`）等处调用，调用方虽有 try-catch 保护，但按规范应在此方法内防御。
- **修复建议**: 改为：
  ```autohotkey
  static DeleteGroupConfig(groupId) {
      if this._groupSettings.Has(groupId)
          this._groupSettings.Delete(groupId)
  }
  ```

### Finding 7
- **位置**: `infrastructure\joy_hotkey_manager.ahk:92`
- **维度**: 错误处理（Map.Delete 不存在键）
- **严重级别**: Important
- **描述**: `UnregisterHotkey` 的 `else` 分支（非按钮类型）直接 Delete 而未检查 Has：
  ```autohotkey
  } else {
      JoyHotkeyManager._registered.Delete(joyKey)  ; 无 Has 检查
  }
  ```
  对比同文件行 70（按钮分支）有 `if JoyHotkeyManager._registered.Has(key)` 检查，此处遗漏。
- **根因**: 轴/POV 类型热键的注销路径未做防御性检查。
- **修复建议**: 包裹 `if JoyHotkeyManager._registered.Has(joyKey)` 后再 Delete。

### Finding 8
- **位置**: `infrastructure\error_system.ahk:82-85`
- **维度**: 强制规则遵守（OnError 回调返回值）
- **严重级别**: Important
- **描述**: `HandleError` 对 MemoryError 返回 0（允许默认错误对话框弹出）：
  ```autohotkey
  if IsObject(Thrown) && Type(Thrown) = "MemoryError"
      return 0
  return 1
  ```
  AGENTS.md「错误与警告接管机制」要求「OnError 回调返回 true 阻止默认错误对话框弹出」。
- **根因**: 这看起来是**有意设计**——MemoryError 不可恢复，让系统弹出对话框并终止是合理的。但严格按 AGENTS.md 字面要求，所有运行时错误都应返回 true 接管。这是规则与实际设计的张力点。
- **修复建议**: 保留当前行为（MemoryError 应该让用户感知），但在 AGENTS.md「错误与警告接管机制」中补充例外说明：「MemoryError 等不可恢复错误允许返回 0 触发默认对话框」。这是文档对齐问题，而非代码缺陷。

### Finding 9
- **位置**: `infrastructure\joy_hotkey_manager.ahk:285-291`
- **维度**: 定时器管理规范
- **严重级别**: Important
- **描述**: 连接轮询定时器未存储引用，无法停止：
  ```autohotkey
  static _StartConnectionPoll() {
      ...
      SetTimer(() => JoyHotkeyManager._PollConnection(), 30000)  ; 未存储
  }
  ```
  AGENTS.md「定时器管理规范」要求「定时器引用必须存储在 `_timers` Map 中，确保能正确停止」。该定时器每 30 秒执行一次，应用生命周期内无法停止。
- **根因**: 连接轮询被视为「始终运行」的后台任务，但缺少显式停止机制。若需在退出时清理或测试中重置，无法做到。
- **修复建议**: 将定时器引用存储到静态属性（如 `_connPollTimer`），并在 `Init` 重置或应用退出时调用 `SetTimer(_connPollTimer, 0)`。

### Finding 10
- **位置**: 多文件（21 处空 catch 块）
- **维度**: 错误处理（静默吞没异常）
- **严重级别**: Important
- **描述**: 全代码库存在 21 处空 catch 块，完全吞没异常。分布：
  - `key_recorder.ahk:278, 282, 287, 291`（4 处）
  - `joy_hotkey_manager.ahk:184, 202, 227, 271`（4 处，轮询方法）
  - `ipc_channel.ahk:122, 129, 184`（3 处）
  - `config_service.ahk:439, 444, 450, 455`（4 处，文件清理）
  - `joy_sender.ahk:36, 44`（2 处）
  - `skill_manager.ahk:154`、`utils.ahk:49`、`gui_manager.ahk:473`、`webview2_manager.ahk:873, 1264`（各 1 处）
- **根因**: 部分空 catch 是合理的「best-effort」清理（如 `config_service.ahk` 的临时文件清理），但轮询方法（`joy_hotkey_manager.ahk` 的 `_Poll`/`_PollPov`/`_PollAxes`/`_PollTriggers`）每 50ms 执行一次，完全静默会掩盖手柄输入子系统的故障。
- **修复建议**: 至少使用 `OutputDebug(...)` 输出诊断信息（不弹窗、不写日志文件，不影响生产）；对于轮询方法，建议增加限速日志（如每秒最多记录一次），与 AGENTS.md「热路径日志限速」模式一致。

### Finding 11
- **位置**: `infrastructure\migration_logger.ahk:41, 43`
- **维度**: 依赖管理（隐式依赖）
- **严重级别**: Minor
- **描述**: 使用 `StrJoin` 函数但未 `#Include "utils.ahk"`：
  ```autohotkey
  lines.Push(StrJoin("|", parts*))
  content := StrJoin("`n", lines*)
  ```
  `StrJoin` 定义于 `infrastructure\utils.ahk:13`。该文件靠 `main.ahk` 的加载顺序在运行时解析到全局 `StrJoin`。
- **根因**: AHK v2 全局函数解析机制掩盖了静态依赖。该文件本身也缺少 `#Warn` 指令（见 Finding 1），整体属于「未完整接入项目规范」的模块。
- **修复建议**: 补充 `#Include "utils.ahk"`，并在补全 #Warn 指令后验证。

### Finding 12
- **位置**: `domain\skill_group.ahk:783`
- **维度**: 代码可维护性（复杂单行表达式）
- **严重级别**: Minor
- **描述**: 单行 SetTimer 回调包含箭头函数 + 三元 + 逗号表达式 + Map.Has/Delete：
  ```autohotkey
  SetTimer(() => (capturedThis._pendingReleases.Has(capturedKey) && capturedThis._pendingReleases[capturedKey] = capturedId ? (capturedThis._pendingReleases.Delete(capturedKey), SendInput("{Blind}{" capturedReleaseKey " Up}")) : 0), -duration)
  ```
- **根因**: 为避免 AGENTS.md「箭头函数不支持块体」陷阱而压缩为单行，但可读性严重下降。
- **修复建议**: 改用闭包函数（Func 对象）替代箭头函数：
  ```autohotkey
  releaseFn := ReleaseKeyLater.Bind(this, key, releaseKey, releaseId)
  SetTimer(releaseFn, -duration)
  ; 并定义独立函数 ReleaseKeyLater(this, key, releaseKey, releaseId) { ... }
  ```

### Finding 13
- **位置**: `presentation\webview2_manager.ahk:519-540`
- **维度**: 代码重复
- **严重级别**: Minor
- **描述**: 连续 12 次 `_CopyProp` 调用，模式高度重复：
  ```autohotkey
  _CopyProp(sg, sgObj, "pressKeys")
  _CopyProp(sg, sgObj, "keys")
  _CopyProp(sg, sgObj, "holdKeys")
  ...（共 12 行）
  ```
- **根因**: 子组属性复制逻辑未参数化为列表遍历。对比同文件行 493-496 的 `_SerializeGroupProperties` 已用 `for prop in props` 遍历，但此处未复用。
- **修复建议**: 提取属性名数组，用循环替代：
  ```autohotkey
  for prop in ["pressKeys", "keys", "holdKeys", "intervals", "delays", "pressDelays", "seqInterval", "holdMode", "holdDuration", "holdPattern", "holdTriggers", "autoRepeat", "repeatInterval"]
      _CopyProp(sg, sgObj, prop)
  ```

### Finding 14
- **位置**: `presentation\webview2_manager.ahk:141-166`
- **维度**: 代码重复
- **严重级别**: Minor
- **描述**: `OnEvent` 方法中 `case "onActivate", "onDeactivate", "onStateChange", "onConfigChange"` 与 `case "onError"` 的处理逻辑**完全相同**（防抖定时器设置），但分别书写了两遍。
- **根因**: switch 语句未利用 fall-through 或提取公共逻辑。
- **修复建议**: 合并 case 或提取 `_ScheduleDebouncedPush()` 辅助方法。

### Finding 15
- **位置**: `application\config_service.ahk:138-150` 与 `application\config_service.ahk:196-208`
- **维度**: 代码重复
- **严重级别**: Minor
- **描述**: `HotReload` 与 `_Rollback` 中存在几乎相同的「等待定时器停止」循环：
  ```autohotkey
  waitStart := A_TickCount
  loop {
      try {
          if ConfigService.SkillManager.GetTimerCount() <= 0
              break
      } catch {
          break
      }
      if (A_TickCount - waitStart) >= 500
          break
      Sleep(10)
  }
  ```
- **根因**: 两个方法都需要在 Emergency 后等待定时器清理，但未提取公共辅助。
- **修复建议**: 提取 `_WaitForTimersDrain(timeoutMs := 500)` 静态方法。

### Finding 16
- **位置**: `infrastructure\config_store.ahk:154-221`
- **维度**: 代码复杂度（重复逻辑）
- **严重级别**: Minor
- **描述**: `_RepairEmptyArrays` 方法约 67 行，每个模式 case 内部逻辑高度相似（检查数组为空 → 用默认值填充），共 7 个 case 分支。
- **根因**: 未参数化「字段名 → 默认值来源」映射。
- **修复建议**: 重构为数据驱动：定义 `Map(mode, Map(field, defaultField))` 结构，统一遍历处理。

### Finding 17
- **位置**: `presentation\webview2_manager.ahk:127-130`
- **维度**: 代码可维护性（哈希方式脆弱）
- **严重级别**: Minor
- **描述**: 用 JSON 字符串拼接作为状态变更指纹：
  ```autohotkey
  currentKey := debugInfo . groupList
  if currentKey = WebView2Manager._lastPushHash
      return
  ```
- **根因**: 两个独立 JSON 字符串拼接可能产生歧义（如 `"{}" . "[]"` 与 `"{" . "}[]"` 不可区分，虽实际不会发生）。性能上每次调用都序列化两次 JSON 用于比较。
- **修复建议**: 改用轻量指纹（如 `SkillManager.GetActiveCount() . "|" . SkillManager.Groups.Count . "|" . SkillManager.EmergencyMode`），或对拼接结果做 MD5/Adler32 哈希。

### Finding 18
- **位置**: `infrastructure\config_store.ahk:293`
- **维度**: 命名规范（大小写不一致）
- **严重级别**: Minor
- **描述**: 默认控制热键使用小写：
  ```autohotkey
  "emergency", "f12"   ; 小写
  ```
  对比同项目 `json_parser.ahk:58`、`webview2_manager.ahk` 等处均用 `"F12"`（大写）。AHK v2 热键字符串大小写敏感度依上下文而定，存在不一致风险。
- **根因**: 不同模块编写者风格差异。
- **修复建议**: 统一为 `"F12"`（与 `json_parser.ahk:58` 的 fallback 配置一致）。

### Finding 19
- **位置**: `presentation\webview2_manager.ahk:339`
- **维度**: 代码可维护性（脆弱的 JSON 检测）
- **严重级别**: Minor
- **描述**: 用首字符判断字符串是否为 JSON：
  ```autohotkey
  isJson := InStr(result, "{") = 1 || InStr(result, "[") = 1
  ```
  会误判以 `{` 或 `[` 开头的普通字符串（如 `"{错误: ...}"`）。
- **根因**: 缺少更可靠的 JSON 类型标记机制。
- **修复建议**: Bridge 协议层应区分「原始字符串」与「JSON 序列化结果」（如在 `_SendResponse` 调用方显式标记，或统一返回 Map 由 `_SendResponse` 序列化）。

### Finding 20
- **位置**: `domain\skill_group.ahk:710-719`
- **维度**: 代码可维护性（动态属性检查）
- **严重级别**: Minor
- **描述**: `Dispose` 方法用 5 处 `if this.HasProp(...)` 检查属性是否存在：
  ```autohotkey
  if this.HasProp("_pendingReleases")
      this._pendingReleases.Clear()
  if this.HasProp("_activeHolds") && this._activeHolds is Map
      this._activeHolds.Clear()
  ...（共 5 处）
  ```
- **根因**: 部分实例属性按模式在 `_SetupMode` 中条件初始化，导致 `Dispose` 不确定属性是否存在。同样模式见 `skill_group.ahk:365, 485-491`。
- **修复建议**: 在 `__New` 中预先初始化所有可能的 Map 属性为空 Map（即使该模式不用），消除 `HasProp` 检查。

### Finding 21
- **位置**: `presentation\gui_manager.ahk:64-67`
- **维度**: 代码风格（缩进不一致）
- **严重级别**: Minor
- **描述**: `Show` 方法的 catch 块缩进比周围代码多 2 个空格：
  ```autohotkey
          _DebugLog("GUIManager.Show: DONE")
        } catch as e {
            _DebugLog("GUIManager.Show ERROR: " e.Message)
            MsgBox("显示主界面失败: " e.Message, "错误", "Icon!")
        }
  ```
  对比同文件其他方法的 4 空格缩进，此处为 6 空格。
- **根因**: 编辑时缩进失误。
- **修复建议**: 统一为 4 空格缩进。

### Finding 22
- **位置**: 多文件（3 处手动插入排序）
- **维度**: 代码重复
- **严重级别**: Minor
- **描述**: 手动插入排序实现重复出现 3 次：
  - `presentation\webview2_manager.ahk:543-567`（按 `_order` 排序分组）
  - `infrastructure\backup_core.ahk:156-169`（按 `time` 排序备份）
  - `infrastructure\utils.ahk:94-104`（按 `time` 排序日志备份）
- **根因**: AHK v2 标准库无排序函数，各模块自行实现。三处实现几乎相同。
- **修复建议**: 在 `infrastructure\utils.ahk` 提取通用 `_SortByField(arr, key, descending := true)` 函数，供三处复用。

### Finding 23
- **位置**: `AGENTS.md`「Key Files」章节
- **维度**: 文档与代码不一致
- **严重级别**: Minor
- **描述**: AGENTS.md 列出的根目录外围模块在项目中不存在：
  - `equipment_recognizer.ahk` — 未找到
  - `ocr.ahk` — 未找到
  - `joystick_tester.ahk` — 未找到
  实际根目录存在的 .ahk 文件为：`asd.ahk`、`config.ahk`、`gui.ahk`、`json.ahk`、`main.ahk`、`SkillMgrDebugLogger.ahk`、`test_ob.ahk`、`test_simple.ahk`、`test_val_btn.ahk`、`ui_manager.ahk`（后 4 个为测试脚本）。
- **根因**: 外围模块可能已移除或迁移至 `asd-tauri/src-tauri/ahk_executor/`，但 AGENTS.md 未同步更新。
- **修复建议**: 更新 AGENTS.md「Key Files」表格，移除不存在的条目；或补充说明这些模块已迁移。

---

## 无问题声明

以下检查项**未发现问题**：

1. **箭头函数块体陷阱（`=> {`）**: 全代码库搜索 `=>\s*\{` 模式，**0 处匹配**。所有箭头函数均使用表达式体或逗号表达式，符合 AGENTS.md「箭头函数 `=>` 只支持表达式体」要求。

2. **字符串拼接花括号陷阱**: 未发现 `"try" OB "{"` 类触发对象字面量解析的危险拼接模式。WebView2 相关 JS 字符串均使用单引号字符串（如 `'if(typeof onAhkReady==='function')onAhkReady()'`）或 `Format()`，符合 AGENTS.md 建议。

3. **`Mod(A_TickCount, interval)` 周期性触发陷阱**: 全代码库搜索 `Mod\s*\(\s*A_TickCount`，**0 处匹配**。所有周期性按键均使用独立触发时间（`_lastTriggerTimes[i]`、`_groupTriggerTimes[key]`），符合 AGENTS.md「周期性触发时间规范」。
   - 注：`mode_registry.ahk:328, 428` 与 `skill_group.ahk:617, 621` 使用 `Mod(step, length)`，这是**序列索引循环**，非时间触发，属合法用法。

4. **GUI 控件位置参数无引号**: 搜索 `Add\s*\(\s*"Button"\s*,\s*x[0-9]`（裸 xNN 模式），**0 处匹配**。所有控件位置参数均用双引号包围（如 `"x15 y45 w570 h300"`）。

5. **Button 控件误用 `.Value`**: 搜索 Button 与 .Value 组合，**0 处匹配**。

6. **WebView2 禁止模式**:
   - `ExecuteScriptAsync` 调用 Promise/async/await：**0 处**（仅 `webview2_manager.ahk:186` 调用同步 JS 函数 `onAhkReady()`，合规）
   - `AddHostObjectToScript` 同步代理：**0 处**
   - 通信均通过 `PostWebMessageAsJson` / `add_WebMessageReceived` 双向消息模式，符合 AGENTS.md「AHK-JS Bridge 通信架构」。

7. **主入口 OnError 缺失**: `main.ahk:98` 注册了 `OnError(ErrorSystem_HandleError, -1)`。`asd.ahk` 通过 `#Include "main.ahk"` 继承该 OnError，运行时生效，非违规。

8. **热路径日志限速**: `mode_registry.ahk` 中所有 `Execute*` 方法（`PeriodicExecutor.Execute`、`SequenceExecutor.Execute`、`EnhancedPeriodicExecutor.Execute`、`EnhancedSequenceExecutor.Execute`、`HybridExecutor.Execute`、`EnhancedHybridExecutor.Execute`、`HoldExecutor.Execute`）**热路径内无日志调用**（仅在 catch 块记录错误），无需限速。`skill_group.ahk` 中 `_ExecuteMixedGroups` / `_ExecutePeriodicHoldPattern` 同样无热路径日志。符合 AGENTS.md「热路径日志会自动限速」的设计意图。

9. **定时器引用存储**: `skill_manager.ahk` 的 `_timers` Map 正确存储所有分组执行定时器引用，停止时调用 `SetTimer(timerFunc, 0)`，符合「定时器管理规范」。`_cleanupTimer`、`_resetEmergencyTimer`、`webview2_manager._updateTimer`、`_eventDebounceTimer`、`gui_manager._updateTimer`、`backup_core._recordTimer`、`joy_hotkey_manager._pollFn` 均正确存储与清理（除 Finding 9 的连接轮询外）。

10. **命名规范总体**:
    - 类名 PascalCase：通过（`SkillManager`、`ConfigStore`、`WebView2Manager`、`ModeRegistry` 等）
    - 方法名 PascalCase：通过（`ToggleGroup`、`LoadConfig`、`_SendKey` 等）
    - 静态属性 camelCase：通过（`logFile`、`configPath`、`backupDir`、`maxBackups` 等）
    - 常量全大写+下划线：通过（`TOGGLE_DEBOUNCE_MS`、`MAX_PARSE_DEPTH`、`MAX_LOOP_ITERATIONS`、`AXIS_HIGH`、`CATEGORY_IO` 等）
    - 私有方法下划线前缀：通过（`_SendKey`、`_BindHotkeys`、`_CleanupOrphanTimers`、`_SetupMode` 等）

11. **#Warn LocalSameAsGlobal 取值一致**: 全部 32 个包含该指令的文件均使用 `Off`（非 `OutputDebug`），内部一致。

12. **错误处理总体**: 几乎所有公共方法都有 try-catch，并在 catch 中调用 `ErrorSystem.LogError(...)` 记录错误后重新抛出或返回安全默认值。`main.ahk` 的启动流程有双层 try-catch + 降级启动 + fallback 机制，错误处理质量高。

---

## 统计

| 严重级别 | 数量 |
|---------|------|
| Critical | 1 |
| Important | 9 |
| Minor | 13 |
| **总计** | **23** |

### 按维度分布

| 维度 | 数量 |
|------|------|
| 强制规则遵守（接管指令/日志级别/OnError） | 3（Finding 1, 2, 8）|
| 架构分层（DDD 层依赖违规） | 2（Finding 4, 5）|
| 错误处理（Map.Delete / 空 catch） | 3（Finding 6, 7, 10）|
| GUI 控件规范 | 1（Finding 3）|
| 定时器管理规范 | 1（Finding 9）|
| 依赖管理 | 1（Finding 11）|
| 代码可维护性（复杂表达式/脆弱检测/动态属性） | 4（Finding 12, 17, 19, 20）|
| 代码重复 | 4（Finding 13, 14, 15, 22）|
| 代码复杂度 | 1（Finding 16）|
| 命名规范 | 1（Finding 18）|
| 代码风格 | 1（Finding 21）|
| 文档一致性 | 1（Finding 23）|

### 最关键的 3 个发现

1. **Finding 1（Critical）**：`migration_logger.ahk` 缺少 3 条 #Warn 强制指令，是全项目唯一不合规的文件。这是加载时警告接管缺口，未赋值变量等警告可能弹窗或被忽视。

2. **Finding 4（Important）**：`backup_core.ahk`（基础设施层）调用 `ExportConfigToFile`（应用层函数），构成 DDD 反向依赖。AGENTS.md 已登记的妥协中未包含此项，属未授权的架构退化。

3. **Finding 5（Important）**：`joy_hotkey_manager.ahk`（基础设施层）`#Include "../domain/joystick_input.ahk"`（领域层），另一处未登记的 DDD 反向依赖。叠加 Finding 2（同文件使用 INFO 日志级别）与 Finding 9（定时器未存储）与 Finding 10（4 处空 catch），`joy_hotkey_manager.ahk` 是本次审查中问题最集中的模块。

---

## 审查方法说明

- **工具**: Read（逐文件阅读关键文件）、PowerShell Select-String（批量正则搜索）、Get-Content -Raw（多行模式匹配）
- **覆盖度**: 33/33 个 .ahk 文件均通过批量搜索检查接管指令；其中 18 个核心文件（main、asd、domain 全部 8 个、infrastructure 关键 6 个、application 1 个、presentation 关键 3 个）进行了逐行深度阅读，其余 15 个通过模式搜索覆盖。
- **未修改任何源代码文件**，仅创建本审查报告。
