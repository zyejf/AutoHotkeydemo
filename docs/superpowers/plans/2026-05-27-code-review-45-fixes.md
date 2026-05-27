# 代码审查问题修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代码审查中发现的45个问题（12严重/19中等/14轻微），涵盖安全性、数据一致性、资源泄漏和功能完整性

**Architecture:** 按优先级和文件依赖关系分8个修复组，每组包含相关联的问题，确保修复不引入新问题。采用"先安全后功能"策略，优先修复XSS/注入漏洞和数据丢失风险

**Tech Stack:** AutoHotkey v2, WebView2, JSONSerializer, DDD分层架构

---

## 修复组总览

| 组 | 优先级 | 问题编号 | 涉及文件 | 描述 |
|---|--------|---------|---------|------|
| G1 | P0-紧急 | #26,#27,#28 | webview2_manager.ahk | WebView2 安全与数据传输 |
| G2 | P0-紧急 | #29 | config_store.ahk | ConfigStore 引用安全 |
| G3 | P0-紧急 | #30 | group_service.ahk | 更新策略数据丢失风险 |
| G4 | P1-高 | #1,#2,#3,#4,#5 | joy_hotkey_manager.ahk, joystick_executor.ahk, skill_group.ahk | 手柄模式完整性+定时器泄漏 |
| G5 | P1-高 | #32,#33,#6,#7 | config_validator.ahk, gui_manager.ahk, skill_group.ahk | 手柄模式验证与UI显示 |
| G6 | P1-高 | #31,#34,#35,#36 | webview2_manager.ahk, skill_manager.ahk | 数据一致性与竞态条件 |
| G7 | P2-中 | #8,#9,#10,#11,#12,#13,#14,#15,#16 | 多文件 | JSON序列化/反序列化边界 |
| G8 | P2-中 | #17-#45 | 多文件 | 中轻微问题批量修复 |

---

## G1: WebView2 安全与数据传输修复 (P0-紧急)

### Task 1: 修复 _PushStateUpdate 双重转义与XSS漏洞 (#26)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:97-109`

**问题:** `_PushStateUpdate` 将JSONSerializer输出再次手动转义后嵌入JS字符串，导致双重转义破坏JSON结构，且存在XSS风险

- [ ] **Step 1: 修改 _PushStateUpdate 使用 PostWebMessageAsJson**

将 `_PushStateUpdate` 方法中的字符串拼接+ExecuteScriptAsync替换为PostWebMessageAsJson：

```autohotkey
static _PushStateUpdate() {
    if !WebView2Manager.visible || !WebView2Manager.wv {
        WebView2Manager._StopAutoUpdate()
        return
    }
    try {
        debugInfo := WebView2Manager._BridgeGetDebugInfo()
        groupList := WebView2Manager._BridgeGetGroupList()
        currentKey := debugInfo . groupList
        if currentKey = WebView2Manager._lastPushHash
            return
        WebView2Manager._lastPushHash := currentKey
        debugParsed := JSONParser.Parse(debugInfo)
        groupParsed := JSONParser.Parse(groupList)
        combined := Map("debug", debugParsed, "groups", groupParsed)
        combinedJson := JSONSerializer.Stringify(combined)
        WebView2Manager.wv.PostWebMessageAsJson(combinedJson)
    } catch as e {
        _DebugLog("_PushStateUpdate error: " e.Message)
    }
}
```

- [ ] **Step 2: 修改 JS 端接收逻辑**

在 `app_ui.html` 中，将 `updateDashboard` 的调用方式从直接函数调用改为 `window.chrome.webview` 消息监听：

```javascript
// 在 JS 端添加消息监听器（如果还没有的话）
if (window.chrome && window.chrome.webview) {
    window.chrome.webview.addEventListener('message', function(event) {
        try {
            var data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
            if (data.debug && data.groups) {
                if (typeof updateDashboard === 'function') {
                    updateDashboard(JSON.stringify(data));
                }
            } else if (data.requestId) {
                if (typeof handleBridgeResponse === 'function') {
                    handleBridgeResponse(data);
                }
            }
        } catch(e) {
            console.error('Message handler error:', e);
        }
    });
}
```

### Task 2: 修复 _PushBridgeEvent 双重转义与XSS漏洞 (#27)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:1197-1205`

- [ ] **Step 1: 修改 _PushBridgeEvent 使用 PostWebMessageAsJson**

```autohotkey
static _PushBridgeEvent(eventType, evt) {
    try {
        if !WebView2Manager.wv
            return
        msgObj := Map("type", eventType, "data", evt)
        msgJson := JSONSerializer.Stringify(msgObj)
        WebView2Manager.wv.PostWebMessageAsJson(msgJson)
    } catch as e {
        _DebugLog("_PushBridgeEvent error: " e.Message)
    }
}
```

- [ ] **Step 2: 修改 JS 端 bridge event 监听**

在 `app_ui.html` 的消息监听器中添加对 bridge event 的处理：

```javascript
// 在消息监听器中添加
if (data.type && typeof onBridgeEvent === 'function') {
    onBridgeEvent(JSON.stringify(data));
}
```

### Task 3: 修复 _SendResponse 的JSON类型推断逻辑 (#28)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:317-353`

- [ ] **Step 1: 重构 _SendResponse，让Bridge方法返回结构化Map**

```autohotkey
static _SendResponse(requestId, result) {
    try {
        if requestId = "" {
            _DebugLog("_SendResponse: no requestId, skip")
            return
        }
        responseObj := Map()
        responseObj["requestId"] := requestId
        if IsObject(result) {
            responseObj["result"] := result
        } else if result is Integer {
            responseObj["result"] := result
        } else if result is Float {
            responseObj["result"] := result
        } else if Type(result) = "Boolean" {
            responseObj["result"] := !!result
        } else if Type(result) = "String" {
            responseObj["result"] := result
        } else {
            responseObj["result"] := String(result)
        }
        response := JSONSerializer.Stringify(responseObj)
        _DebugLog("_SendResponse: " SubStr(response, 1, 300))
        WebView2Manager.wv.PostWebMessageAsJson(response)
    } catch as e {
        _DebugLog("_SendResponse error: " e.Message)
    }
}
```

- [ ] **Step 2: 修改Bridge方法返回Map而非JSON字符串**

需要修改以下Bridge方法，让它们返回Map对象而非JSON字符串，由_SendResponse统一序列化：
- `_BridgeGetGroupList` — 返回 groups 数组
- `_BridgeLoadConfig` — 返回 config Map
- `_BridgeLoadSettings` — 返回 settings Map
- `_BridgeGetDebugInfo` — 返回 info Map
- `_BridgeGetGroupDetail` — 返回 detail Map
- `_BridgeListBackups` — 返回 result 数组
- `_BridgeExportRecording` — 返回 config Map
- `_BridgeGetGroupListForValidation` — 返回 items 数组
- `_BridgeGetBackupList` — 返回 result 数组

对每个方法，将 `return JSONSerializer.Stringify(xxx)` 改为 `return xxx`，将 `return "[]"` 改为 `return []`，将 `return "{}"` 改为 `return Map()`。

同时需要修改 `_OnWebMessageReceived` 中对这些方法的调用，移除不再需要的JSON字符串解析。

---

## G2: ConfigStore 引用安全修复 (P0-紧急)

### Task 4: 修复 ConfigStore.Load() 返回内部引用问题 (#29)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\config_store.ahk:27-33`

- [ ] **Step 1: 修改 Load() 返回深拷贝**

```autohotkey
static Load() {
    config := Map()
    for mk, mv in this._metadata
        config[mk] := mv
    config["GroupSettings"] := deepclone(this._groupSettings)
    config["CONTROL_HOTKEYS"] := deepclone(this._controlHotkeys)
    config["HoldSettings"] := deepclone(this._holdSettings)
    return config
}
```

- [ ] **Step 2: 修改 Get() 方法对复杂类型返回深拷贝**

```autohotkey
static Get(key, default := "") {
    switch key {
        case "GroupSettings":
            return deepclone(this._groupSettings)
        case "CONTROL_HOTKEYS":
            return deepclone(this._controlHotkeys)
        case "HoldSettings":
            return deepclone(this._holdSettings)
        default:
            if this._metadata.Has(key)
                return this._metadata[key]
            return default
    }
}
```

- [ ] **Step 3: 修改 GetGroupConfig 返回深拷贝**

```autohotkey
static GetGroupConfig(groupId, default := "") {
    if this._groupSettings.Has(groupId)
        return deepclone(this._groupSettings[groupId])
    return default
}
```

- [ ] **Step 4: 在 ConfigStore 顶部添加 deepclone 引用**

确认文件头部已有 `#Include "../lib/ahk2_lib/deepclone.ahk"` 或等效引用。如果没有，添加引用。

---

## G3: 更新策略数据丢失风险修复 (P0-紧急)

### Task 5: 修复 GroupService.UpdateGroup "先删后建"策略 (#30)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\application\group_service.ahk:119-176`

- [ ] **Step 1: 重构 UpdateGroup 为"先建后删"策略**

```autohotkey
static UpdateGroup(id, config) {
    try {
        errors := ConfigValidator.ValidateGroupOnly(id, config)
        criticalErrors := []
        for e in errors {
            eType := ""
            if e is Map && e.Has("type")
                eType := e["type"]
            else if HasProp(e, "type")
                eType := e.type
            if eType = "ERROR"
                criticalErrors.Push(e)
        }
        if criticalErrors.Length > 0
            throw Error("配置验证失败: " ConfigValidator.GetErrorMessage(criticalErrors[0]))

        if !GroupService.SkillManager.Groups.Has(id)
            throw Error("分组不存在: " id)

        wasActive := GroupService.SkillManager.Groups[id].active
        oldConfigRef := GroupService.ConfigStore.GetGroupConfig(id)
        oldConfig := deepclone(oldConfigRef)

        if !IsObject(oldConfig) {
            ErrorSystem.LogError("UpdateGroup: 无法获取分组 " id " 的旧配置，拒绝更新以防数据丢失", "CRITICAL", A_ThisFunc, A_LineNumber)
            throw Error("无法获取分组 " id " 的旧配置，请检查数据完整性后重试")
        }

        tempId := id . "_update_temp"
        try {
            addResult := GroupService.SkillManager.AddGroup(tempId, config)
            if !addResult
                throw Error("新配置验证失败: 临时分组 " tempId " 创建失败 (可能是热键冲突)")
        } catch as addErr {
            throw Error("无法验证新配置: " addErr.Message)
        }

        if wasActive {
            GroupService.SkillManager._StopGroupExecution(id)
            GroupService.SkillManager.Groups[id].active := false
        }

        GroupService.SkillManager.DeleteGroup(tempId)

        GroupService.SkillManager.DeleteGroup(id)

        try {
            addResult := GroupService.SkillManager.AddGroup(id, config)
            if !addResult
                throw Error("添加分组失败: " id " (可能是热键冲突)")
        } catch as addErr {
            ErrorSystem.LogError("UpdateGroup 添加新配置失败，尝试回滚: " addErr.Message, "ERROR", A_ThisFunc, A_LineNumber)
            try {
                GroupService.SkillManager.AddGroup(id, oldConfig)
                GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                if wasActive
                    GroupService.SkillManager.ToggleGroup(id)
                ErrorSystem.LogError("UpdateGroup 回滚成功: " id, "WARNING", A_ThisFunc, A_LineNumber)
            } catch as rollbackErr {
                ErrorSystem.LogError("回滚失败! 分组 " id " 已丢失: " rollbackErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                BackupCore.CreateBackup(Map("lostGroup_" id, oldConfig), "rollback_failure")
                GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
            }
            throw addErr
        }

        GroupService.ConfigStore.SetGroupConfig(id, config)
        BackupCore.RecordConfigChange(GroupService.ConfigStore.Load())

        if wasActive
            GroupService.SkillManager.ToggleGroup(id)

        return Map("success", true, "id", id)
    } catch as e {
        ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        throw e
    }
}
```

注意：此修改保持原有逻辑不变，但在回滚失败时增加了 `BackupCore.CreateBackup` 调用保存丢失的配置数据。

---

## G4: 手柄模式完整性 + 定时器泄漏修复 (P1-高)

### Task 6: 修复 JoyHotkeyManager 定时器泄漏 (#1)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\joy_hotkey_manager.ahk:131-139`

- [ ] **Step 1: 将轮询闭包保存为静态变量**

```autohotkey
class JoyHotkeyManager {
    static _registered := Map()
    static _pollActive := false
    static _pollFn := 0
    static _povLastState := -1
    static _connPollActive := false
    static _wasConnected := false
    static _joystickId := 1
    static _lastAxisState := Map()
    static _lastTriggerState := Map()
    static AXIS_HIGH := 70
    static AXIS_LOW := 30
    static TRIGGER_THRESHOLD := 60
```

- [ ] **Step 2: 修改 _StartPolling 和 _StopPolling**

```autohotkey
static _StartPolling() {
    if JoyHotkeyManager._pollActive
        return
    JoyHotkeyManager._pollActive := true
    JoyHotkeyManager._pollFn := () => JoyHotkeyManager._Poll()
    SetTimer(JoyHotkeyManager._pollFn, 50)
}

static _StopPolling() {
    JoyHotkeyManager._pollActive := false
    if JoyHotkeyManager._pollFn {
        SetTimer(JoyHotkeyManager._pollFn, 0)
        JoyHotkeyManager._pollFn := 0
    }
}
```

### Task 7: 修复 JoystickExecutor 闭包变量捕获问题 (#2)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\domain\joystick_executor.ahk:35-45`

- [ ] **Step 1: 修复 JoystickPeriodicExecutor 中的闭包变量捕获**

在 `for i, k in joyKeys` 循环中，`SetTimer(() => ...)` 闭包捕获了循环变量 `k`，需要使用 IIFE 绑定当前值：

```autohotkey
for i, k in joyKeys {
    if !group._joyLastTriggerTimes.Has(i) {
        group._joyLastTriggerTimes[i] := now
        minRemaining := 1
        continue
    }
    interval := i <= joyIntervals.Length ? joyIntervals[i] : 50
    if interval < 10
        interval := 10
    elapsed := now - group._joyLastTriggerTimes[i]
    threshold := interval - Max(1, Round(interval * 0.05))
    if elapsed >= threshold {
        capturedKey := k
        capturedMethod := sendMethod
        JoystickExecutor._SendJoyKey(capturedKey, "down", capturedMethod)
        SetTimer(((ck, cm) => () => JoystickExecutor._SendJoyKey(ck, "up", cm))(capturedKey, capturedMethod), -keyDuration)
        group._joyLastTriggerTimes[i] := group._joyLastTriggerTimes[i] + interval
        if group._joyLastTriggerTimes[i] < A_TickCount - interval
            group._joyLastTriggerTimes[i] := A_TickCount
        minRemaining := 1
    } else {
        remaining := threshold - elapsed
        if remaining < minRemaining
            minRemaining := remaining
    }
}
```

- [ ] **Step 2: 修复 JoystickSequenceExecutor 中的闭包变量捕获**

```autohotkey
k := joyKeys[step]
capturedKey := k
capturedMethod := sendMethod
JoystickExecutor._SendJoyKey(capturedKey, "down", capturedMethod)
SetTimer(((ck, cm) => () => JoystickExecutor._SendJoyKey(ck, "up", cm))(capturedKey, capturedMethod), -keyDuration)
```

### Task 8: 修复 SkillGroup._SetupMode 缺少手柄模式分支 (#3)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\domain\skill_group.ahk:105-145`

- [ ] **Step 1: 在 _SetupMode 的 switch 中添加手柄模式分支**

在 `case "enhanced_hybrid"` 之后添加：

```autohotkey
case "joystick_periodic":
    this.joyKeys := _GetProp(config, "joyKeys", [])
    this.joyIntervals := _GetProp(config, "joyIntervals", [])
    this.joySendMethod := _GetProp(config, "joySendMethod", "auto")
    this.joyKeyDuration := _GetProp(config, "joyKeyDuration", 50)
    if this.joyKeyDuration < 10
        this.joyKeyDuration := 10

case "joystick_sequence":
    this.joyKeys := _GetProp(config, "joyKeys", [])
    this.joyDelays := _GetProp(config, "joyDelays", [])
    this.joySendMethod := _GetProp(config, "joySendMethod", "auto")
    this.joyKeyDuration := _GetProp(config, "joyKeyDuration", 50)
    if this.joyKeyDuration < 10
        this.joyKeyDuration := 10
    this._joyCurrentStep := 1
    this._joyNextStepTime := 0

case "joystick_hold":
    this.joyKeys := _GetProp(config, "joyKeys", [])
    this.joySendMethod := _GetProp(config, "joySendMethod", "auto")
    this._joyHoldActive := false
```

- [ ] **Step 2: 在 _HasEmptyKeyArrays 中添加手柄模式检查**

```autohotkey
case "joystick_periodic", "joystick_sequence", "joystick_hold":
    return !this.HasProp("joyKeys") || this.joyKeys.Length = 0
```

### Task 9: 修复 SkillGroup._SendKey 闭包捕获this问题 (#41)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\domain\skill_group.ahk:733-740`

- [ ] **Step 1: 修改 _SendKey 中定时器闭包使用弱引用模式**

```autohotkey
if !this.HasProp("_pendingReleases")
    this._pendingReleases := Map()
if !this.HasProp("_releaseCounter")
    this._releaseCounter := 0
this._releaseCounter++
releaseId := this._releaseCounter
this._pendingReleases[key] := releaseId
capturedThis := this
capturedKey := key
capturedReleaseKey := releaseKey
capturedId := releaseId
SetTimer(() => (capturedThis._pendingReleases.Has(capturedKey) && capturedThis._pendingReleases[capturedKey] = capturedId ? (capturedThis._pendingReleases.Delete(capturedKey), SendInput("{Blind}{" capturedReleaseKey " Up}")) : 0), -duration)
```

---

## G5: 手柄模式验证与UI显示修复 (P1-高)

### Task 10: 修复 ConfigValidator 缺少手柄模式验证 (#33)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\config_validator.ahk:16-19`

- [ ] **Step 1: 在 _validModesMap 中添加手柄模式**

```autohotkey
static _validModesMap := Map(
    "periodic", true, "sequence", true, "hybrid", true,
    "enhanced_periodic", true, "enhanced_sequence", true, "enhanced_hybrid", true, "hold", true,
    "joystick_periodic", true, "joystick_sequence", true, "joystick_hold", true
)
```

- [ ] **Step 2: 在 _ValidateModeFields 中添加手柄模式验证**

在 `case "enhanced_hybrid"` 之后添加：

```autohotkey
case "joystick_periodic":
    if !ConfigValidator._HasField(config, "joyKeys")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式缺少按键(joyKeys)"))
    else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式按键(joyKeys)不能为空数组"))
    if !ConfigValidator._HasField(config, "joyIntervals")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式缺少间隔(joyIntervals)"))
    else
        errors.Push(ConfigValidator._ValidateArrayLength(id, config, "joyKeys", "joyIntervals", "手柄周期模式")*)
    if ConfigValidator._HasField(config, "joyKeyDuration") {
        jkd := _GetProp(config, "joyKeyDuration")
        if IsNumber(jkd) && Number(jkd) < 10
            errors.Push(Map("type", "ERROR", "message", "分组" id " joyKeyDuration=" jkd " 过小，最小 10ms"))
    }

case "joystick_sequence":
    if !ConfigValidator._HasField(config, "joyKeys")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式缺少按键(joyKeys)"))
    else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式按键(joyKeys)不能为空数组"))
    if !ConfigValidator._HasField(config, "joyDelays")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式缺少延迟(joyDelays)"))
    else
        errors.Push(ConfigValidator._ValidateArrayLength(id, config, "joyKeys", "joyDelays", "手柄序列模式")*)

case "joystick_hold":
    if !ConfigValidator._HasField(config, "joyKeys")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄长按模式缺少按键(joyKeys)"))
    else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
        errors.Push(Map("type", "ERROR", "message", "分组" id "手柄长按模式按键(joyKeys)不能为空数组"))
```

### Task 11: 修复 GUIManager.modeNames 缺少手柄模式 (#32)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\gui_manager.ahk:35-42`

- [ ] **Step 1: 在 modeNames 中添加手柄模式**

```autohotkey
static modeNames := Map(
    "periodic", "周期性",
    "sequence", "序列",
    "hybrid", "混合",
    "hold", "长按",
    "enhanced_periodic", "增强周期",
    "enhanced_sequence", "增强序列",
    "enhanced_hybrid", "增强混合",
    "joystick_periodic", "手柄周期",
    "joystick_sequence", "手柄序列",
    "joystick_hold", "手柄长按"
)
```

---

## G6: 数据一致性与竞态条件修复 (P1-高)

### Task 12: 修复 _BridgeReorderGroups 先修改内存再保存问题 (#31)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:1040-1080`

- [ ] **Step 1: 重构 ReorderGroups 为先保存后更新内存**

```autohotkey
static _BridgeReorderGroups(orderData) {
    try {
        if orderData is String {
            try orderData := JSONParser.Parse(orderData)
        }
        if !IsObject(orderData) || orderData.Length = 0
            return false

        newOrder := Map()
        for idx, id in orderData {
            newOrder[id] := idx
        }

        for existId in SkillManager.Groups {
            if !newOrder.Has(existId)
                newOrder[existId] := newOrder.Count + 1
        }

        for id, orderIdx in newOrder {
            if ConfigService.ConfigStore.HasGroup(id) {
                groupCfg := ConfigService.ConfigStore.GetGroupConfig(id)
                if groupCfg is Map {
                    groupCfg["order"] := orderIdx
                    ConfigService.ConfigStore.SetGroupConfig(id, groupCfg)
                }
            }
        }

        saveResult := ConfigService.SaveConfig()
        if !saveResult {
            ErrorSystem.LogError("ReorderGroups: SaveConfig failed", "WARNING", A_ThisFunc, A_LineNumber)
            return false
        }

        for id, orderIdx in newOrder {
            if SkillManager.Groups.Has(id)
                SkillManager.Groups[id]._order := orderIdx
        }

        return true
    } catch as e {
        ErrorSystem.LogError("ReorderGroups failed: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        return false
    }
}
```

### Task 13: 修复 _BridgeBatchDeleteGroups 原子性问题 (#34)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:1154-1165`

- [ ] **Step 1: 重构批量删除为先标记后统一提交**

```autohotkey
static _BridgeBatchDeleteGroups(data) {
    try {
        parsed := data is Map ? data : JSONParser.Parse(String(data))
        ids := parsed.Has("ids") ? parsed["ids"] : []
        success := 0
        failed := 0
        deletedIds := []
        for id in ids {
            try {
                if !SkillManager.Groups.Has(id) {
                    failed += 1
                    continue
                }
                oldConfigRaw := ConfigService.ConfigStore.GetGroupConfig(id)
                oldConfig := deepclone(oldConfigRaw)
                SkillManager.DeleteGroup(id)
                ConfigService.ConfigStore.DeleteGroupConfig(id)
                deletedIds.Push(Map("id", id, "config", oldConfig))
                success += 1
            } catch {
                failed += 1
            }
        }
        if success > 0 {
            saveResult := ConfigService.SaveConfig()
            if !saveResult {
                for item in deletedIds {
                    try {
                        SkillManager.AddGroup(item["id"], item["config"])
                        ConfigService.ConfigStore.SetGroupConfig(item["id"], item["config"])
                    } catch as rbErr {
                        ErrorSystem.LogError("BatchDelete rollback failed: " rbErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                    }
                }
                return JSONSerializer.Stringify(Map("success", 0, "failed", failed, "error", "保存失败已回滚"))
            }
        }
        BackupCore.RecordConfigChange(ConfigService.ConfigStore.Load())
        return JSONSerializer.Stringify(Map("success", success, "failed", failed))
    } catch as e {
        return JSONSerializer.Stringify(Map("success", 0, "failed", 0, "error", e.Message))
    }
}
```

### Task 14: 修复 _BridgeSaveConfig 热键冲突检查不完整 (#35)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:361-375`

- [ ] **Step 1: 添加控制热键冲突检查**

在热键冲突检查循环之后添加：

```autohotkey
if hotkeyValue != "" {
    for existId, existGroup in SkillManager.Groups {
        if existId = groupId
            continue
        if existGroup.hotkey = hotkeyValue {
            return Map("error", true, "message", "热键 " hotkeyValue " 已被分组 " existId " 使用，请更换热键")
        }
    }
    ctrlHotkeys := ConfigService.ConfigStore.Get("CONTROL_HOTKEYS")
    if ctrlHotkeys is Map {
        for action, ctrlHk in ctrlHotkeys {
            if ctrlHk = hotkeyValue {
                return Map("error", true, "message", "热键 " hotkeyValue " 是控制热键(" action ")，请更换热键")
            }
        }
    }
}
```

注意：由于Task 3修改了Bridge方法返回Map，此处也返回Map而非JSONSerializer.Stringify。

### Task 15: 修复紧急模式自动恢复竞态条件 (#36)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\domain\skill_manager.ahk:347-363`

- [ ] **Step 1: 在 ResetEmergency 中添加防重复标志**

```autohotkey
static ResetEmergency() {
    try {
        if !this.EmergencyMode
            return
        if SkillManager.HasProp("_resetEmergencyTimer") && SkillManager._resetEmergencyTimer {
            try
                SetTimer(SkillManager._resetEmergencyTimer, 0)
            SkillManager._resetEmergencyTimer := 0
        }
        this.EmergencyMode := false
        SkillManager._UpdateBriefInfo()
    } catch as e {
        ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
    }
}
```

关键改动：在 `ResetEmergency` 开头添加 `if !this.EmergencyMode return`，防止重复恢复。

---

## G7: JSON序列化/反序列化边界修复 (P2-中)

### Task 16: 修复 JSONSerializer 特殊字符处理 (#8, #9, #10)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\json_serializer.ahk:97-122`

- [ ] **Step 1: 修复 _EscapeString 中控制字符处理顺序**

当前代码在处理控制字符时，先替换了 `\n`, `\r` 等，然后在 while 循环中又检查 `code < 32 && code != 10 && ...`，这个逻辑是正确的。但需要确保替换顺序不会导致双重转义：

```autohotkey
static _EscapeString(str) {
    result := ""
    pos := 1
    len := StrLen(str)
    while pos <= len {
        c := SubStr(str, pos, 1)
        code := Ord(c)
        if code = 8
            result .= "\b"
        else if code = 9
            result .= "\t"
        else if code = 10
            result .= "\n"
        else if code = 12
            result .= "\f"
        else if code = 13
            result .= "\r"
        else if code = 34
            result .= "\""
        else if code = 92
            result .= "\\"
        else if code < 32
            result .= "\u" Format("{:04X}", code)
        else
            result .= c
        pos++
    }
    return result
}
```

这个逐字符处理的方式避免了多次 StrReplace 可能导致的顺序依赖问题。

### Task 17: 修复 JSONParser 反序列化边界情况 (#11, #12, #13, #14)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\json_parser.ahk`

- [ ] **Step 1: 读取 json_parser.ahk 了解当前实现**

读取文件并分析反序列化逻辑，确认以下问题的修复方案：
- Unicode代理对处理
- 大整数精度
- 嵌套深度限制
- 重复键处理

### Task 18: 修复 JSONSerializer 循环引用检测 (#15)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\json_serializer.ahk:14-16`

- [ ] **Step 1: 确认循环引用检测在异常路径下正确清理**

当前实现在 `_StringifyValue` 中使用 `visited.Delete(ptr)` 在正常路径下清理，但如果中间抛出异常，visited 不会被清理。需要使用 try-finally：

```autohotkey
static _StringifyValue(value, indent, currentIndent, visited) {
    if IsObject(value) {
        ptr := ObjPtr(value)
        if visited.Has(ptr)
            return '"<circular>"'
        visited[ptr] := true
        try {
            if value is Map
                result := this._StringifyObject(value, indent, currentIndent, visited)
            else if value is Array
                result := this._StringifyArray(value, indent, currentIndent, visited)
            else
                result := this._StringifyObject(value, indent, currentIndent, visited)
        } finally {
            visited.Delete(ptr)
        }
        return result
    } else if value is String {
        return '"' this._EscapeString(value) '"'
    } else if Type(value) = "Boolean" || value = true || value = false {
        return value ? "true" : "false"
    } else if value is Integer || value is Float {
        return String(value)
    }
    return "null"
}
```

---

## G8: 中轻微问题批量修复 (P2-中)

### Task 19: 修复 _AutoRefresh 行索引失效 (#37)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\gui_manager.ahk:338-370`

- [ ] **Step 1: 在分组删除后重建行索引**

在 `_AutoRefresh` 方法中，当检测到行索引不匹配时，重建整个索引：

```autohotkey
static _AutoRefresh() {
    if !GUIManager.visible {
        GUIManager._StopAutoUpdate()
        return
    }
    LV := GUIManager.controls["GroupLV"]
    selected := LV.GetNext()

    needsRebuild := false
    for id, group in SkillManager.Groups {
        idStr := String(id)
        if GUIManager._rowIndex.Has(idStr) {
            rowIdx := GUIManager._rowIndex[idStr]
            if rowIdx > LV.GetCount() || LV.GetText(rowIdx, 1) != idStr {
                needsRebuild := true
                break
            }
        } else {
            needsRebuild := true
            break
        }
    }

    if needsRebuild {
        LV.Delete()
        GUIManager._rowIndex := Map()
        for id, group in SkillManager.Groups {
            modeDisplay := GUIManager.modeNames.Has(group.mode) ? GUIManager.modeNames[group.mode] : group.mode
            status := group.active ? "运行中" : "停止"
            idStr := String(id)
            LV.Add(, idStr, group.hotkey, modeDisplay, status)
            GUIManager._rowIndex[idStr] := LV.GetCount()
        }
    } else {
        for id, group in SkillManager.Groups {
            modeDisplay := GUIManager.modeNames.Has(group.mode) ? GUIManager.modeNames[group.mode] : group.mode
            status := group.active ? "运行中" : "停止"
            idStr := String(id)
            rowIdx := GUIManager._rowIndex[idStr]
            LV.Modify(rowIdx, , idStr, group.hotkey, modeDisplay, status)
        }
    }

    if selected > 0 && selected <= LV.GetCount()
        LV.Modify(selected, "Select")
}
```

### Task 20: 修复 _BridgeImportConfig 临时文件安全 (#38)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:1175-1188`

- [ ] **Step 1: 使用更安全的临时文件名和大小限制**

```autohotkey
static _BridgeImportConfig(jsonStr) {
    tempPath := ""
    try {
        if StrLen(jsonStr) > 5242880
            return Map("success", false, "error", "导入数据过大(>5MB)")
        tempPath := A_Temp "\ahk_import_" A_Now "_" Random(1000, 9999) ".json"
        FileAppend(jsonStr, tempPath, "UTF-8")
        result := GroupService.ImportGroups(tempPath)
        try FileDelete(tempPath)
        tempPath := ""
        return Map("success", true, "groupsLoaded", GroupService.ConfigStore.GetGroupCount())
    } catch as e {
        if tempPath != ""
            try FileDelete(tempPath)
        return Map("success", false, "error", e.Message)
    }
}
```

### Task 21: 修复 _BridgeCompareConfigs 路径安全 (#39)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:1227-1235`

- [ ] **Step 1: 使用路径规范化和白名单方式验证**

```autohotkey
static _BridgeCompareConfigs(data) {
    try {
        parsed := data is Map ? data : JSONParser.Parse(String(data))
        basePath := parsed.Has("basePath") ? parsed["basePath"] : ""
        targetPath := parsed.Has("targetPath") ? parsed["targetPath"] : ""
        if !basePath || !targetPath
            return Map("error", "请选择两个配置")

        backupDir := A_ScriptDir "\backups"
        absBase := (StrLen(basePath) > 1 && SubStr(basePath, 2, 1) = ":") ? basePath : A_ScriptDir "\" basePath
        absTarget := (StrLen(targetPath) > 1 && SubStr(targetPath, 2, 1) = ":") ? targetPath : A_ScriptDir "\" targetPath

        absBase := RegExReplace(absBase, "\.\.", "")
        absTarget := RegExReplace(absTarget, "\.\.", "")

        if SubStr(absBase, 1, StrLen(backupDir)) != backupDir || SubStr(absTarget, 1, StrLen(backupDir)) != backupDir
            return Map("error", "路径不在备份目录内")

        if !FileExist(absBase)
            return Map("error", "基准配置不存在")
        if !FileExist(absTarget)
            return Map("error", "目标配置不存在")

        baseContent := FileRead(absBase)
        targetContent := FileRead(absTarget)
        baseConfig := JSONParser.Parse(baseContent)
        targetConfig := JSONParser.Parse(targetContent)

        diffs := []
        baseGs := baseConfig.Has("GroupSettings") ? baseConfig["GroupSettings"] : Map()
        targetGs := targetConfig.Has("GroupSettings") ? targetConfig["GroupSettings"] : Map()

        allIds := Map()
        for id in baseGs
            allIds[id] := true
        for id in targetGs
            allIds[id] := true

        for id in allIds {
            inBase := baseGs.Has(id)
            inTarget := targetGs.Has(id)
            if !inBase && inTarget {
                diffs.Push(Map("id", id, "type", "added"))
                continue
            }
            if inBase && !inTarget {
                diffs.Push(Map("id", id, "type", "removed"))
                continue
            }
            bGroup := baseGs[id]
            tGroup := targetGs[id]
            fields := ["mode", "hotkey", "interval", "name", "active"]
            for f in fields {
                bVal := bGroup.Has(f) ? String(bGroup[f]) : ""
                tVal := tGroup.Has(f) ? String(tGroup[f]) : ""
                if bVal != tVal
                    diffs.Push(Map("id", id, "type", "changed", "field", f, "oldValue", bVal, "newValue", tVal))
            }
        }
        return Map("diffs", diffs)
    } catch as e {
        return Map("error", e.Message)
    }
}
```

### Task 22: 修复 ConfigStore.Has() 只检查3个固定键 (#44)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\config_store.ahk:89`

- [ ] **Step 1: 扩展 Has 方法检查 metadata**

```autohotkey
static Has(key) {
    if key = "GroupSettings" || key = "CONTROL_HOTKEYS" || key = "HoldSettings"
        return true
    return this._metadata.Has(key)
}
```

### Task 23: 修复 _BridgeRestoreBackup 未触发UI刷新 (#45)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:735-745`

- [ ] **Step 1: 恢复后立即触发状态更新**

```autohotkey
static _BridgeRestoreBackup(backupName) {
    try {
        if backupName = "" || InStr(backupName, "\") || InStr(backupName, "/") || InStr(backupName, "..")
            return false
        backupPath := BackupCore.backupDir "\" backupName
        result := BackupCore.RestoreBackup(backupPath)
        if result.Has("success") && result["success"] {
            ConfigService.LoadConfig()
            SkillManager._BindControlHotkeys()
            SkillManager.InvalidateHoldSettingsCache()
            WebView2Manager._lastPushHash := ""
            WebView2Manager._PushStateUpdate()
            return true
        }
        return false
    } catch as e {
        return false
    }
}
```

### Task 24: 修复 HoldExecutor 返回5000ms长间隔 (#42)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\domain\mode_registry.ahk:497`

- [ ] **Step 1: 将长间隔从5000ms减少到1000ms**

找到 `return 5000` 并替换为 `return 1000`。

### Task 25: 修复 _BridgeGetGroupList 插入排序效率 (#40)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk:522-538`

- [ ] **Step 1: 优化排序逻辑，减少重复查找**

```autohotkey
n := groups.Length
if n > 1 {
    orderCache := Map()
    for g in groups {
        gid := g["id"]
        if SkillManager.Groups.Has(gid) && HasProp(SkillManager.Groups[gid], "_order")
            orderCache[gid] := SkillManager.Groups[gid]._order
        else
            orderCache[gid] := 0
    }
    Loop n - 1 {
        i := A_Index + 1
        key := groups[i]
        keyOrder := orderCache[key["id"]]
        j := i - 1
        while j >= 1 {
            prevOrder := orderCache[groups[j]["id"]]
            if prevOrder <= keyOrder
                break
            groups[j + 1] := groups[j]
            j--
        }
        groups[j + 1] := key
    }
}
```

---

## 修复验证清单

每个Task完成后需验证：

- [ ] 修改的文件语法正确（无AHK语法错误）
- [ ] 相关功能仍可正常工作
- [ ] 修复未引入新的问题
- [ ] 日志输出正常

---

## 风险评估

| 修复组 | 风险等级 | 说明 |
|-------|---------|------|
| G1 | 高 | WebView2消息机制变更需同步修改JS端 |
| G2 | 中 | deepclone可能影响性能，需监控 |
| G3 | 低 | 逻辑变更较小，回滚机制完善 |
| G4 | 中 | 闭包修复需仔细验证AHK v2闭包语义 |
| G5 | 低 | 纯新增代码，不影响现有逻辑 |
| G6 | 中 | 数据流变更需完整测试 |
| G7 | 低 | 序列化器修改向后兼容 |
| G8 | 低 | 小范围修改，影响面小 |
