# Task 3: AHK v2 安全性与性能审查

> 审查日期：2026-08-20
> 审查范围：AHK v2 部分（domain / infrastructure / application / presentation 关键模块）
> 审查性质：只读审查（未修改任何 .ahk 文件）
> 审查维度：输入验证与配置校验、Map/Object 安全访问、WebView2 通信安全、文件 I/O 错误处理、全局变量作用域、热路径日志限速、周期性触发时间、定时器生命周期、热路径循环开销

## 执行摘要

本次对 AHK v2 部分 15 个核心源文件进行了安全性与性能专项审查，共发现 **9 项**问题（**0 Critical、6 Important、3 Minor**）。

**总体判断**：代码整体成熟度较高——此前多轮审查修复痕迹明显（大量 `I##/M##/C##` 注释标记），关键安全规范大多已落实：

- ✅ **周期性触发时间规范**：全库搜索 `Mod(A_TickCount`，仅命中文档与注释，**0 处**实际调用；所有周期性按键均使用独立触发时间（`_lastTriggerTimes[i]` / `_groupTriggerTimes[key]` + `(i-1)*10` 偏移），符合规范。
- ✅ **Map/Object 安全访问**：所有 `Map.Delete()` 调用点均先做 `Has()` 检查（skill_manager.ahk:250/259/302/383/390/420/600/602、skill_group.ahk:568、mode_registry.ahk:47/49 等），未发现「Delete 不存在键抛异常」的崩溃点。
- ✅ **WebView2 通信安全**：遵守 postMessage 模式（`PostWebMessageAsJson` / `add_WebMessageReceived`），**无** `AddHostObjectToScript`；`ExecuteScriptAsync` 仅调用同步 JS 函数（`onAhkReady()`），未等待 Promise；远程调试端口仅在「未编译 + 环境变量显式开启」时设置（webview2_manager.ahk:65-67，C3 修复）；`await2()` 在 SetTimer 消息循环内执行，符合规范。
- ✅ **导入防护**：`_BridgeImportConfig` 有 5MB 体积上限 + 1000 分组数量上限 + 导入前强制备份（I17/I20）；备份恢复/删除有路径遍历拒绝式检查（C4）。

**主要风险集中在以下两个方向**：
1. **配置验证覆盖不完整**——热键格式校验仅覆盖 `_ValidateGroup` 路径，`ValidateGroupOnly`（Create/Update 组）与控制热键（`_ValidateHotkeys`）均未做格式校验，按键名合法性（keys/joyKeys 等）则完全未被验证器覆盖（T3-01/02/03/04）。
2. **热路径日志限速承诺未兑现**——AGENTS.md 声明「Execute* 热路径日志每秒最多记录一次」，但执行器 catch 块直接调用 `ErrorSystem.LogError`，而 `ErrorSystem._WriteLog` 无任何限速，摇杆模式在 JoySender 未注入时会产生高频写盘（T3-05/06）。

## 分级统计

| 严重级别 | 数量 | 编号 |
|---------|------|------|
| Critical | 0 | — |
| Important | 6 | T3-01、T3-02、T3-03、T3-04、T3-05、T3-06 |
| Minor | 3 | T3-07、T3-08、T3-09 |

---

## 发现清单

### T3-01 — ValidateGroupOnly 未校验热键格式，热键校验存在覆盖缺口

- **位置**：`infrastructure/config_validator.ahk:115-138`（`ValidateGroupOnly`）
- **维度**：安全性 / 输入验证
- **严重级别**：Important
- **描述**：`_ValidateGroup`（第 84-88 行）已通过 `_IsValidHotkeyFormat` 校验热键格式（注释标注 I18），但 `ValidateGroupOnly`（第 121-122 行）只检查 `hotkey` 字段「是否存在」，**不校验格式**。`ValidateGroupOnly` 是 `GroupService.CreateGroup/UpdateGroup`（group_service.ahk:81/121）实际走的分组级校验入口，这意味着通过 WebView2 保存分组时（`_BridgeSaveConfig` → `CreateGroup/UpdateGroup`）**不会校验热键格式**。
- **影响**：非法热键（如 `12345`、空串以外的畸形字符串）在配置写入阶段通过校验，直到运行时 `SkillManager.AddGroup` 调用 `Hotkey()` 才抛异常，且报错信息误导为「热键注册失败…可能被其他程序占用」，掩盖了真实原因。
- **根因**：`ValidateGroupOnly` 未复用 `_ValidateGroup` 中已有的 `_IsValidHotkeyFormat` 校验逻辑，形成两条不一致的校验路径。
- **修复方案**：在 `ValidateGroupOnly` 的 `hotkey` 分支中补充 `_IsValidHotkeyFormat` 校验（与 `_ValidateGroup` 保持一致）。

### T3-02 — 配置验证器未校验按键名合法性

- **位置**：`infrastructure/config_validator.ahk:140-284`（`_ValidateModeFields` 各 mode 分支）
- **维度**：安全性 / 输入验证
- **严重级别**：Important
- **描述**：验证器对各模式的 `keys`/`pressKeys`/`holdKeys`/`joyKeys` 数组只校验「非空」与 `intervals`/`delays` 的数值边界（10ms~86400000ms），**从不校验数组元素是否为合法按键名**。领域层虽在运行时通过 `SkillGroup._IsValidKeyName`（skill_group.ahk:889-902）兜底——非法按键在 `_SendKey`/`_ReleaseKey` 中静默 `return` 跳过，但这意味着非法按键配置静默失效，用户无任何告警。
- **影响**：导入或手写的配置中若包含 `"keys": ["xyz123"]` 之类非法按键名，验证通过、保存成功，但执行时对应按键永不触发，形成「配置看着正常但实际不工作」的隐蔽故障。
- **根因**：验证器缺少按键名合法性校验；`_IsValidKeyName` 是 `SkillGroup` 的静态私有方法，验证器无法复用（跨层/跨模块未共享）。
- **修复方案**：在 `_ValidateModeFields` 中校验每个按键数组元素（可复用 `_IsValidKeyName` 的合法名单逻辑，或将该逻辑下沉到共享工具模块供验证器与 `SkillGroup` 共同引用）。

### T3-03 — 控制热键 `_ValidateHotkeys` 未校验热键格式

- **位置**：`infrastructure/config_validator.ahk:286-299`（`_ValidateHotkeys`）
- **维度**：安全性 / 输入验证
- **严重级别**：Important
- **描述**：`_ValidateHotkeys` 只校验 5 个必需 action 是否存在、是否为空（空值仅记 WARNING），**不校验热键格式**。对照分组热键已通过 `_IsValidHotkeyFormat` 校验，控制热键（emergency/toggleAll/showStatus/toggleHoldMode/releaseAllHolds）存在同样的格式校验缺口。
- **影响**：用户可写入非法控制热键（如 `garbage`），`_BindControlHotkeys`（skill_manager.ahk:147-187）在运行时 `Hotkey(hk, ...)` 抛异常仅记 WARNING，控制热键静默失效——尤其是「紧急停止」这类关键安全功能一旦无效，后果严重。
- **根因**：`_ValidateHotkeys` 未复用 `_IsValidHotkeyFormat`。
- **修复方案**：在 `_ValidateHotkeys` 中对非空 action 值补充 `_IsValidHotkeyFormat` 校验，非法时记 ERROR。

### T3-04 — GlobalSettingsEditor._Save 输入未校验 + 忽略保存结果导致误报成功

- **位置**：`presentation/gui_manager.ahk:408-438`（`GlobalSettingsEditor._Save`）
- **维度**：安全性 / 健壮性
- **严重级别**：Important
- **描述**：两点问题：
  1. 第 422-424 行直接对 Edit 文本执行 `Integer(...)`，用户输入非数字时抛 `ValueError`，被第 435 行外层 catch 吞掉，**无任何用户提示**，界面停留在原状。
  2. 第 432 行 `ConfigService.SaveConfig()` 的返回值被**忽略**，第 433 行无条件 `MsgBox("全局设置已保存", "成功", ...)`。若 `SaveConfig` 因验证严重错误返回 `false`（保存被阻止），用户仍被告知「已保存」，实际配置未持久化，重启后丢失。
- **根因**：`GlobalSettingsEditor._Save` 缺少逐字段输入校验与保存结果检查；对比 `WebView2Manager._BridgeSaveSettings`（webview2_manager.ahk:553-608）有完整的校验、失败回滚与返回值处理，两条设置保存路径不一致。
- **修复方案**：对 `debounceDelay`/`checkInterval`/`pressSpeed` 逐字段 try-catch 转换并提示用户；检查 `SaveConfig()` 返回值，失败时提示「保存失败」而非「已保存」。

### T3-05 — 热路径错误日志无限速（违反 AGENTS.md 强制规范）

- **位置**：`domain/mode_registry.ahk` 各 Execute catch（第 294/343/394/444/463/481/541 等）、`domain/skill_group.ahk:756-758`、`infrastructure/error_system.ahk:185-213`（`_WriteLog`）
- **维度**：性能
- **严重级别**：Important
- **描述**：AGENTS.md「热路径日志（Execute* 方法）会自动限速，每秒最多记录一次」，但审查发现：各执行器 `Execute` 的 catch 块直接调用 `ErrorSystem.LogError(...)`（`ERROR` 级），而 `ErrorSystem.LogError` → `_WriteLog`（第 185-213 行）**无任何限速逻辑**，每次调用 `FileAppend` 写磁盘。当某分组执行器持续抛异常时（典型场景：JoySender 未注入 → `_SendJoyKey` 在 try 外抛异常，见 T3-06），将以约 100 次/秒（tick=10ms）的频率写盘，且每次序列化 JSON + `FileAppend`，构成磁盘 I/O 风暴。
- **根因**：热路径限速并未实现；唯一限速逻辑存在于 `JoyHotkeyManager` 的轮询路径（`_lastPollErrLog`，每秒一次，见 joy_hotkey_manager.ahk:199-203），但执行器错误日志路径无对应限速。
- **修复方案**：在 `ErrorSystem.LogError` 层（或执行器 catch 封装处）增加「同一错误源每秒最多记一次」的时间戳限速，与 `JoyHotkeyManager` 的 I11 模式保持一致。

### T3-06 — 摇杆 release 一次性定时器未纳管 + 未注入时热路径每 tick 抛异常

- **位置**：`domain/joystick_executor.ahk:55/107`（`JoystickPeriodicExecutor`、`JoystickSequenceExecutor`）、`:157-160`（`_SendJoyKey` 注入检查）
- **维度**：健壮性 / 性能
- **严重级别**：Important
- **描述**：
  1. 第 55、107 行为每次按键 release 创建的 `SetTimer(..., -keyDuration)` 一次性定时器**引用未存储**（匿名箭头函数 + 立即调用返回闭包），无法在紧急停止/分组停止时取消。虽为短延迟（默认 50ms）一次性定时器自清理、非泄漏，但停止时会产生多余的「up」发送（与 `_ReleaseJoyKeys` 已发送的 up 重复，冗余但无害）。
  2. `_SendJoyKey` 第 159-160 行在 `try` 之外抛「JoySender 未注入」异常，异常向上传播到 `Execute` 的 catch → 每次 tick 记一次 ERROR 日志（与 T3-05 叠加放大高频写盘）。`JoystickHoldExecutor.Execute` 同样受影响（第 136-137 行）。
- **根因**：release 定时器未纳入任何 Map 管理；注入检查放在热路径内而非模式启动前。
- **修复方案**：release 定时器引用存入 `group` 的 Map（如复用 `_releaseTimers` 模式）以便停止时取消；在 joystick 模式激活前（`Toggle`/`_SetupMode`）完成 `JoystickExecutor._joySender` 注入检查，避免每 tick 重复抛异常。

### T3-07 — IPCChannel._OnReceived 监听器回调缺 catch

- **位置**：`infrastructure/ipc_channel.ahk:181-184`（`_OnReceived`）
- **维度**：健壮性
- **严重级别**：Minor
- **描述**：`for callback in IPCChannel.listeners[eventName] { try callback(msgObj) }` 中的 `try` 无 `catch`/`finally` 块，回调抛出的异常会**向上传播到 `OnMessage` 分发流程**，可能中断本轮消息分发，其余待分发消息与监听器被跳过。对比 `KeyRecorder`/`KeyValidator` 对 `_onEvent.Call` 均有 try-catch 包裹。
- **根因**：监听器调用处误用「无 catch 的 try」，未真正捕获异常。
- **修复方案**：为回调调用补 `catch` 并记 WARNING 日志（与 KeyRecorder 的 onEvent 处理保持一致）。

### T3-08 — _BridgeImportConfig 重复 JSON 解析 + 保存路径多次 deepclone

- **位置**：`presentation/webview2_manager.ahk:1040-1081`（`_BridgeImportConfig`）、`:408/438-439`（`_BridgeSaveConfig`）
- **维度**：性能优化
- **严重级别**：Minor
- **描述**：
  1. `_BridgeImportConfig` 对同一份 `jsonStr` 解析两次：先 `JSONParser.Parse` 做 preCheck（第 1047 行），再写临时文件经 `GroupService.ImportGroups` → `ConfigIO.LoadFromFile` → `JSONParser.LoadFile` 二次解析。
  2. `_BridgeSaveConfig` 路径存在多次 deepclone（`ConfigStore.GetGroupConfig` 内部 deepclone + 第 439 行再次 `deepclone(oldConfigRaw)`，`GroupService.UpdateGroup` 内又有 `deepclone(oldConfigRef)`）。
- **影响**：均位于用户操作触发的一次性链路（非热路径），开销可接受，仅列为优化项。
- **根因**：为满足 I15/I16/I20 等防御性 deepclone 保护叠加了重复拷贝，未做解析结果复用。
- **修复方案**：`_BridgeImportConfig` 将 preCheck 的解析结果直接复用（或调整 `ImportGroups` 接受已解析对象）；`_BridgeSaveConfig` 减少冗余 deepclone 层级。

### T3-09 — KeyRecorder 鼠标钩子标志位滞后导致部分清理失败

- **位置**：`domain/key_recorder.ahk:273-302`（`_InstallMouseHooks`）、`:312-323`（`_RemoveMouseHooks`）
- **维度**：健壮性
- **严重级别**：Minor
- **描述**：`_InstallMouseHooks` 在**方法末尾**（第 301 行）才置 `this._mouseHotkeys := true`；而 `_RemoveMouseHooks` 开头（第 313-314 行）`if !this._mouseHotkeys return` 提前返回。若 `_InstallMouseHooks` 中途异常（虽然当前每个 `Hotkey` 注册均有 try-catch，理论不抛），此时 `_mouseHotkeys` 仍为 `false`，`Start` 的 catch 块调用 `_RemoveMouseHooks` 会直接提前返回，已成功注册的按钮/滚轮热键**不会被注销**，导致录制停止后鼠标钩子残留。
- **根因**：`_mouseHotkeys` 作为「清理开关」在注册完成后才置位，无法反映「部分注册」状态。
- **修复方案**：`_RemoveMouseHooks` 无条件遍历注销一轮（注销不存在/未注册的热键在 try 内只会在 `Hotkey(..., "Off")` 失败时被忽略）；或每成功注册一个热键即立即维护状态。