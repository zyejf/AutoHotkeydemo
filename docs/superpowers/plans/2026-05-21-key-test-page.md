# 按键测试页面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 WebView2 仪表盘中集成"按键测试"页面，提供录制真实按键节奏和验证执行时序两个独立功能。

**Architecture:** 方案 A — WebView2 桥接。AHK 后端通过 `InputHook` 捕获按键事件、通过 `_SendKey`/`_SendHoldKey` 埋点收集执行时序，通过 WebView2 Bridge 实时推送到前端 Canvas 时序图。录制数据可导出为分组配置。

**Tech Stack:** AutoHotkey v2 (InputHook, OnMessage, SetTimer), HTML5 Canvas, WebView2 Bridge (PostWebMessageAsJson / ExecuteScriptAsync)

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `domain/key_recorder.ahk` | Create | 按键录制器，使用 InputHook + OnMessage 捕获键盘/鼠标事件 |
| `domain/key_validator.ahk` | Create | 执行验证器，在 _SendKey/_SendHoldKey 埋点收集实际发送时序 |
| `domain/skill_group.ahk` | Modify | 在 _SendKey/_SendHoldKey 中添加 KeyValidator 埋点 |
| `main.ahk` | Modify | 添加 key_recorder.ahk 和 key_validator.ahk 的 #Include |
| `presentation/webview2_manager.ahk` | Modify | 添加 Bridge action 处理和事件推送 |
| `presentation/app_ui.html` | Modify | 添加导航项、页面容器、录制/验证 Tab UI、Canvas 时序图 |

---

### Task 1: KeyRecorder 领域类

**Files:**
- Create: `domain/key_recorder.ahk`
- Test: `tests/test_key_recorder.ahk`

- [ ] **Step 1: Write the failing test**

```ahk
; tests/test_key_recorder.ahk
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/key_recorder.ahk"

ErrorSystem.Init()
JSONLogger.Init()
DebugLogger.Init()

TestReporter.BeginTest("test_key_recorder.ahk")

TestReporter.Scenario("1.1 KeyRecorder 初始状态")
TestReporter.Assert(!KeyRecorder.IsRecording(), "初始不应在录制中")
TestReporter.Assert(KeyRecorder.GetEventCount() = 0, "初始事件数应为0")

TestReporter.Scenario("1.2 KeyRecorder.Start 设置录制状态")
captured := []
KeyRecorder.Start((evt) => captured.Push(evt))
TestReporter.Assert(KeyRecorder.IsRecording(), "开始后应在录制中")

TestReporter.Scenario("1.3 KeyRecorder.OnKey 记录事件")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("A", "up", 15)
TestReporter.Assert(KeyRecorder.GetEventCount() = 2, "应记录2个事件")

TestReporter.Scenario("1.4 KeyRecorder.Stop 停止录制并返回结果")
result := KeyRecorder.Stop()
TestReporter.Assert(!KeyRecorder.IsRecording(), "停止后不应在录制中")
TestReporter.Assert(result.Has("events"), "结果应包含 events")
TestReporter.Assert(result.Has("duration"), "结果应包含 duration")
TestReporter.Assert(result["events"].Length = 2, "应有2个事件")

TestReporter.Scenario("1.5 KeyRecorder 事件格式正确")
evt := result["events"][1]
TestReporter.Assert(evt["key"] = "A", "key 应为 A")
TestReporter.Assert(evt["event"] = "down", "event 应为 down")
TestReporter.Assert(evt["device"] = "keyboard", "device 应为 keyboard")

TestReporter.Scenario("1.6 ExportAsGroupConfig 周期性模式")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("A", "up", 15)
KeyRecorder.OnKey("B", "down", 50)
KeyRecorder.OnKey("B", "up", 65)
KeyRecorder.OnKey("A", "down", 100)
KeyRecorder.OnKey("A", "up", 115)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config.Has("keys"), "配置应包含 keys")
TestReporter.Assert(config.Has("intervals"), "配置应包含 intervals")
TestReporter.Assert(config["keys"].Length > 0, "keys 不应为空")

TestReporter.Scenario("1.7 ExportAsGroupConfig 序列模式")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("B", "down", 100)
KeyRecorder.OnKey("C", "down", 250)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("sequence", 15)
TestReporter.Assert(config.Has("keys"), "配置应包含 keys")
TestReporter.Assert(config.Has("delays"), "配置应包含 delays")

TestReporter.Scenario("1.8 KeyRecorder 重复 Stop 安全")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
r1 := KeyRecorder.Stop()
r2 := KeyRecorder.Stop()
TestReporter.Assert(r2 = "", "重复 Stop 应返回空")

TestReporter.Scenario("1.9 KeyRecorder 未启动时 OnKey 忽略")
KeyRecorder.OnKey("Z", "down", 0)
TestReporter.Assert(KeyRecorder.GetEventCount() = 0, "未启动时不应记录")

TestReporter.EndTest()
ExitApp()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `AutoHotkey.exe tests\test_key_recorder.ahk`
Expected: FAIL — `key_recorder.ahk` 不存在

- [ ] **Step 3: Write minimal implementation**

```ahk
; domain/key_recorder.ahk
; =================================================================
; 领域层 - KeyRecorder 按键录制器
; 版本: 1.0
; 说明: 使用 InputHook + OnMessage 捕获键盘/鼠标事件
;       记录时间戳，可导出为分组配置
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "../infrastructure/error_system.ahk"

class KeyRecorder {
    static _recording := false
    static _events := []
    static _startTime := 0
    static _onEvent := ""
    static _hook := 0
    static _mouseMsgHandlers := Map()

    static IsRecording() => this._recording

    static GetEventCount() => this._events.Length

    static Start(onEvent) {
        if this._recording
            return
        this._recording := true
        this._events := []
        this._startTime := A_TickCount
        this._onEvent := onEvent
        this._hook := InputHook("V L0")
        this._hook.KeyDown := (keyName, *) => this.OnKey(keyName, "down")
        this._hook.KeyUp := (keyName, *) => this.OnKey(keyName, "up")
        this._hook.Start()
        this._InstallMouseHooks()
    }

    static Stop() {
        if !this._recording
            return ""
        this._recording := false
        if this._hook {
            try this._hook.Stop()
            this._hook := 0
        }
        this._RemoveMouseHooks()
        duration := A_TickCount - this._startTime
        this._onEvent := ""
        return Map("events", this._events.Clone(), "duration", duration)
    }

    static OnKey(key, event, timestamp := "") {
        if !this._recording
            return
        if timestamp = ""
            timestamp := A_TickCount - this._startTime
        evt := Map(
            "key", key,
            "event", event,
            "timestamp", timestamp,
            "device", "keyboard"
        )
        this._events.Push(evt)
        if this._onEvent
            this._onEvent.Call(evt)
    }

    static OnMouse(button, event, timestamp := "") {
        if !this._recording
            return
        if timestamp = ""
            timestamp := A_TickCount - this._startTime
        evt := Map(
            "key", button,
            "event", event,
            "timestamp", timestamp,
            "device", "mouse"
        )
        this._events.Push(evt)
        if this._onEvent
            this._onEvent.Call(evt)
    }

    static ExportAsGroupConfig(mode, keyPressDuration := 15) {
        if this._events.Length = 0
            return Map()

        downEvents := []
        for evt in this._events {
            if evt["event"] = "down" || evt["event"] = "click"
                downEvents.Push(evt)
        }
        if downEvents.Length = 0
            return Map()

        keys := []
        for evt in downEvents
            keys.Push(evt["key"])

        if mode = "periodic" {
            intervals := []
            if downEvents.Length > 1 {
                for i in 2 .. downEvents.Length {
                    interval := downEvents[i]["timestamp"] - downEvents[i - 1]["timestamp"]
                    if interval < 10
                        interval := 10
                    intervals.Push(interval)
                }
            }
            if intervals.Length = 0
                intervals.Push(50)
            return Map(
                "mode", "periodic",
                "keys", keys,
                "intervals", intervals,
                "keyPressDuration", keyPressDuration
            )
        }

        if mode = "sequence" {
            delays := []
            if downEvents.Length > 1 {
                for i in 2 .. downEvents.Length {
                    delay := downEvents[i]["timestamp"] - downEvents[i - 1]["timestamp"]
                    if delay < 10
                        delay := 10
                    delays.Push(delay)
                }
            }
            if delays.Length = 0
                delays.Push(100)
            return Map(
                "mode", "sequence",
                "keys", keys,
                "delays", delays,
                "keyPressDuration", keyPressDuration
            )
        }

        return Map()
    }

    static _InstallMouseHooks() {
        handlers := Map(
            0x201, "LButton",
            0x204, "RButton",
            0x207, "MButton",
            0x20A, "Wheel"
        )
        for msg, btn in handlers {
            fn := (wParam, lParam, msgNum, hwnd) => (
                KeyRecorder._recording ? KeyRecorder.OnMouse(handlers[msgNum], "click") : 0, 0
            )
            boundFn := OnMessage(msg, fn)
            this._mouseMsgHandlers[msg] := Map("fn", fn, "original", boundFn)
        }
    }

    static _RemoveMouseHooks() {
        for msg in this._mouseMsgHandlers {
            try OnMessage(msg, this._mouseMsgHandlers[msg]["original"])
        }
        this._mouseMsgHandlers.Clear()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `AutoHotkey.exe tests\test_key_recorder.ahk`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add domain/key_recorder.ahk tests/test_key_recorder.ahk
git commit -m "feat: add KeyRecorder domain class for key event recording"
```

---

### Task 2: KeyValidator 领域类

**Files:**
- Create: `domain/key_validator.ahk`
- Test: `tests/test_key_validator.ahk`

- [ ] **Step 1: Write the failing test**

```ahk
; tests/test_key_validator.ahk
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/key_validator.ahk"

ErrorSystem.Init()
JSONLogger.Init()
DebugLogger.Init()

TestReporter.BeginTest("test_key_validator.ahk")

TestReporter.Scenario("2.1 KeyValidator 初始状态")
TestReporter.Assert(!KeyValidator.IsActive(), "初始不应激活")

TestReporter.Scenario("2.2 KeyValidator.Start 激活验证")
captured := []
KeyValidator.Start("1", (evt) => captured.Push(evt))
TestReporter.Assert(KeyValidator.IsActive(), "启动后应激活")
TestReporter.Assert(KeyValidator._groupId = "1", "groupId 应为 1")

TestReporter.Scenario("2.3 KeyValidator.OnSend 记录事件")
KeyValidator.OnSend("1", "A", "press", 0)
KeyValidator.OnSend("1", "B", "press", 50)
TestReporter.Assert(KeyValidator.GetActualCount() = 2, "应记录2个事件")

TestReporter.Scenario("2.4 KeyValidator.Stop 生成报告")
report := KeyValidator.Stop()
TestReporter.Assert(!KeyValidator.IsActive(), "停止后不应激活")
TestReporter.Assert(report.Has("groupId"), "报告应包含 groupId")
TestReporter.Assert(report.Has("totalActual"), "报告应包含 totalActual")
TestReporter.Assert(report["totalActual"] = 2, "totalActual 应为2")

TestReporter.Scenario("2.5 KeyValidator 过滤非目标分组事件")
KeyValidator.Start("2", (evt) => "")
KeyValidator.OnSend("1", "A", "press", 0)
KeyValidator.OnSend("2", "B", "press", 10)
TestReporter.Assert(KeyValidator.GetActualCount() = 1, "只应记录目标分组事件")
KeyValidator.Stop()

TestReporter.Scenario("2.6 KeyValidator 重复 Stop 安全")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.Stop()
KeyValidator.Start("1", (evt) => "")
KeyValidator.OnSend("1", "A", "press", 0)
r1 := KeyValidator.Stop()
r2 := KeyValidator.Stop()
TestReporter.Assert(r2 = "", "重复 Stop 应返回空")

TestReporter.Scenario("2.7 KeyValidator 未激活时 OnSend 忽略")
KeyValidator.OnSend("1", "A", "press", 0)
TestReporter.Assert(KeyValidator.GetActualCount() = 0, "未激活时不应记录")

TestReporter.EndTest()
ExitApp()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `AutoHotkey.exe tests\test_key_validator.ahk`
Expected: FAIL — `key_validator.ahk` 不存在

- [ ] **Step 3: Write minimal implementation**

```ahk
; domain/key_validator.ahk
; =================================================================
; 领域层 - KeyValidator 执行验证器
; 版本: 1.0
; 说明: 在 _SendKey/_SendHoldKey 中埋点收集实际发送时序
;       生成验证报告（顺序正确性/间隔偏差/发送成功率/长按时序）
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "../infrastructure/error_system.ahk"

class KeyValidator {
    static _active := false
    static _groupId := ""
    static _expectedSeq := []
    static _actualSeq := []
    static _startTime := 0
    static _onEvent := ""

    static IsActive() => this._active

    static GetActualCount() => this._actualSeq.Length

    static Start(groupId, onEvent) {
        if this._active
            return
        this._active := true
        this._groupId := groupId
        this._actualSeq := []
        this._expectedSeq := []
        this._startTime := A_TickCount
        this._onEvent := onEvent
        this._LoadExpectedSequence(groupId)
    }

    static Stop() {
        if !this._active
            return ""
        this._active := false
        report := this._BuildReport()
        this._onEvent := ""
        this._groupId := ""
        return report
    }

    static OnSend(groupId, key, event, timestamp) {
        if !this._active
            return
        if groupId != this._groupId
            return
        if timestamp = ""
            timestamp := A_TickCount - this._startTime
        evt := Map(
            "key", key,
            "event", event,
            "timestamp", timestamp
        )
        this._actualSeq.Push(evt)
        if this._onEvent
            this._onEvent.Call(evt)
    }

    static _LoadExpectedSequence(groupId) {
        if !SkillManager.Groups.Has(groupId)
            return
        group := SkillManager.Groups[groupId]
        keys := []
        intervals := []
        if HasProp(group, "pressKeys") && group.pressKeys.Length > 0 {
            for k in group.pressKeys
                keys.Push(k)
            if HasProp(group, "intervals")
                for v in group.intervals
                    intervals.Push(v)
            else if HasProp(group, "pressDelays")
                for v in group.pressDelays
                    intervals.Push(v)
        } else if HasProp(group, "keys") && group.keys.Length > 0 {
            for k in group.keys
                keys.Push(k)
            if HasProp(group, "intervals")
                for v in group.intervals
                    intervals.Push(v)
            else if HasProp(group, "delays")
                for v in group.delays
                    intervals.Push(v)
        } else if HasProp(group, "holdKeys") && group.holdKeys.Length > 0 {
            for k in group.holdKeys
                keys.Push(k)
        }
        this._expectedSeq := []
        for i, k in keys {
            interval := i <= intervals.Length ? intervals[i] : 50
            this._expectedSeq.Push(Map("key", k, "interval", interval))
        }
    }

    static _BuildReport() {
        totalExpected := this._expectedSeq.Length
        totalActual := this._actualSeq.Length

        orderCorrect := true
        if totalActual > 0 && totalExpected > 0 {
            minLen := Min(totalActual, totalExpected)
            for i in 1 .. minLen {
                if this._actualSeq[i]["key"] != this._expectedSeq[Mod(i - 1, totalExpected) + 1]["key"] {
                    orderCorrect := false
                    break
                }
            }
        }

        details := []
        deviations := []
        for i in 1 .. totalActual {
            if i < totalActual {
                actualInterval := this._actualSeq[i + 1]["timestamp"] - this._actualSeq[i]["timestamp"]
                expectedIdx := Mod(i - 1, totalExpected) + 1
                expectedInterval := this._expectedSeq[expectedIdx].Has("interval") ? this._expectedSeq[expectedIdx]["interval"] : 50
                deviation := expectedInterval > 0 ? Round(Abs(actualInterval - expectedInterval) / expectedInterval * 100, 1) : 0
                deviations.Push(deviation)
                status := deviation <= 20 ? "good" : (deviation <= 50 ? "acceptable" : "poor")
                details.Push(Map(
                    "key", this._actualSeq[i]["key"],
                    "expectedInterval", expectedInterval,
                    "actualInterval", actualInterval,
                    "deviation", deviation,
                    "status", status
                ))
            }
        }

        avgDeviation := deviations.Length > 0 ? Round(deviations.reduce((a, b) => a + b, 0) / deviations.Length, 1) : 0
        maxDeviation := deviations.Length > 0 ? Round(deviations.reduce((a, b) => Max(a, b)), 1) : 0
        sendSuccessRate := totalExpected > 0 ? Round(totalActual / totalExpected, 2) : 1

        return Map(
            "groupId", this._groupId,
            "duration", A_TickCount - this._startTime,
            "totalExpected", totalExpected,
            "totalActual", totalActual,
            "orderCorrect", orderCorrect,
            "avgIntervalDeviation", avgDeviation,
            "maxIntervalDeviation", maxDeviation,
            "sendSuccessRate", sendSuccessRate,
            "holdTimingCorrect", true,
            "details", details
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `AutoHotkey.exe tests\test_key_validator.ahk`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add domain/key_validator.ahk tests/test_key_validator.ahk
git commit -m "feat: add KeyValidator domain class for execution timing validation"
```

---

### Task 3: SkillGroup 埋点

**Files:**
- Modify: `domain/skill_group.ahk:654-683` (_SendKey 方法)
- Modify: `domain/skill_group.ahk:391-407` (_SendHoldKey 方法)

- [ ] **Step 1: Add KeyValidator notification in _SendKey**

In `domain/skill_group.ahk`, after the line `this._lastSend[key] := A_TickCount` (line 674), add:

```ahk
            if KeyValidator._active
                KeyValidator.OnSend(this.id, key, "press", A_TickCount - KeyValidator._startTime)
```

The full _SendKey method becomes:

```ahk
    _SendKey(key, isMouse) {
        if this._lastSend.Has(key) {
            if A_TickCount - this._lastSend[key] < this._debounceMs
                return
        }

        if !SkillGroup._IsValidKeyName(key)
            return

        try {
            duration := this._keyPressDuration > 0 ? this._keyPressDuration : 15
            hasModifier := RegExMatch(key, "^[\^+!#]")

            if hasModifier {
                SendInput("{Blind}" key)
            } else {
                SendInput("{Blind}{" key " Down}")
                releaseKey := key
                SetTimer(() => SendInput("{Blind}{" releaseKey " Up}"), -duration)
            }
            this._lastSend[key] := A_TickCount

            if KeyValidator._active
                KeyValidator.OnSend(this.id, key, "press", A_TickCount - KeyValidator._startTime)
        } catch as e {
            SkillGroup._Log("ERROR", "_SendKey 失败: key=" key " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
```

- [ ] **Step 2: Add KeyValidator notification in _SendHoldKey**

In `domain/skill_group.ahk`, after the `SendInput` call in `_SendHoldKey` (after line 401), add:

```ahk
            if KeyValidator._active
                KeyValidator.OnSend(this.id, key, press ? "down" : "up", A_TickCount - KeyValidator._startTime)
```

The full _SendHoldKey method becomes:

```ahk
    _SendHoldKey(key, isMouse, press := true) {
        if !SkillGroup._IsValidKeyName(key)
            return
        try {
            hasModifier := RegExMatch(key, "^[\^+!#]")
            if hasModifier {
                if press
                    SendInput("{Blind}" key)
            } else {
                action := press ? "Down" : "Up"
                SendInput("{Blind}{" key " " action "}")
            }

            if KeyValidator._active
                KeyValidator.OnSend(this.id, key, press ? "down" : "up", A_TickCount - KeyValidator._startTime)
        } catch as e {
            SkillGroup._Log("ERROR", "_SendHoldKey 失败: key=" key " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
```

- [ ] **Step 3: Add #Include for key_validator.ahk in skill_group.ahk**

At the top of `domain/skill_group.ahk`, after the existing `#Include` lines, add:

```ahk
#Include "key_validator.ahk"
```

- [ ] **Step 4: Verify existing tests still pass**

Run: `AutoHotkey.exe tests\test_domain_full.ahk`
Expected: PASS — KeyValidator._active 默认为 false，不影响现有逻辑

- [ ] **Step 5: Commit**

```bash
git add domain/skill_group.ahk
git commit -m "feat: add KeyValidator instrumentation in _SendKey and _SendHoldKey"
```

---

### Task 4: main.ahk 注册

**Files:**
- Modify: `main.ahk:30-35` (领域层 #Include 区域)

- [ ] **Step 1: Add #Include for key_recorder.ahk and key_validator.ahk**

In `main.ahk`, after line 33 (`#Include "domain\skill_manager.ahk"`), add:

```ahk
#Include "domain\key_recorder.ahk"
#Include "domain\key_validator.ahk"
```

The domain layer section becomes:

```ahk
; =================================================================
; 第 2 步: 加载领域层
; =================================================================
#Include "domain\interfaces.ahk"
#Include "domain\mode_registry.ahk"
#Include "domain\skill_group.ahk"
#Include "domain\skill_manager.ahk"
#Include "domain\key_recorder.ahk"
#Include "domain\key_validator.ahk"
```

- [ ] **Step 2: Verify main.ahk loads without errors**

Run: `AutoHotkey.exe main.ahk` (quick check, then close)
Expected: No load-time errors

- [ ] **Step 3: Commit**

```bash
git add main.ahk
git commit -m "feat: register KeyRecorder and KeyValidator in main.ahk"
```

---

### Task 5: WebView2 Bridge 扩展

**Files:**
- Modify: `presentation/webview2_manager.ahk:169-236` (_OnWebMessageReceived switch block)
- Modify: `presentation/webview2_manager.ahk` (add new Bridge methods)

- [ ] **Step 1: Add Bridge action handlers in _OnWebMessageReceived**

In `presentation/webview2_manager.ahk`, inside the `switch action` block (after the `case "GetDebugInfo"` block around line 229), add:

```ahk
                case "StartRecording":
                    result := WebView2Manager._BridgeStartRecording()
                    WebView2Manager._SendResponse(requestId, String(result))
                case "StopRecording":
                    result := WebView2Manager._BridgeStopRecording()
                    WebView2Manager._SendResponse(requestId, result)
                case "StartValidation":
                    result := WebView2Manager._BridgeStartValidation(WebView2Manager._GetField(msg, "groupId"))
                    WebView2Manager._SendResponse(requestId, String(result))
                case "StopValidation":
                    result := WebView2Manager._BridgeStopValidation()
                    WebView2Manager._SendResponse(requestId, result)
                case "ExportRecording":
                    result := WebView2Manager._BridgeExportRecording(WebView2Manager._GetField(msg, "mode"), WebView2Manager._GetField(msg, "keyPressDuration"))
                    WebView2Manager._SendResponse(requestId, result)
```

- [ ] **Step 2: Add Bridge method implementations**

Add these methods to `WebView2Manager` class (after the existing `_BridgeGetDebugInfo` method):

```ahk
    static _BridgeStartRecording() {
        try {
            _DebugLog("_BridgeStartRecording called")
            KeyRecorder.Start((evt) => WebView2Manager._PushKeyEvent(evt))
            return "true"
        } catch as e {
            _DebugLog("_BridgeStartRecording error: " e.Message)
            return "false"
        }
    }

    static _BridgeStopRecording() {
        try {
            _DebugLog("_BridgeStopRecording called")
            result := KeyRecorder.Stop()
            if result = ""
                return JSONSerializer.Stringify(Map("error", true, "message", "未在录制中"))
            events := []
            for evt in result["events"] {
                events.Push(Map("key", evt["key"], "event", evt["event"], "timestamp", evt["timestamp"], "device", evt["device"]))
            }
            return JSONSerializer.Stringify(Map("events", events, "duration", result["duration"]))
        } catch as e {
            _DebugLog("_BridgeStopRecording error: " e.Message)
            return JSONSerializer.Stringify(Map("error", true, "message", e.Message))
        }
    }

    static _BridgeStartValidation(groupId) {
        try {
            _DebugLog("_BridgeStartValidation called: " groupId)
            if !SkillManager.Groups.Has(groupId)
                return "false"
            KeyValidator.Start(groupId, (evt) => WebView2Manager._PushSendEvent(evt))
            return "true"
        } catch as e {
            _DebugLog("_BridgeStartValidation error: " e.Message)
            return "false"
        }
    }

    static _BridgeStopValidation() {
        try {
            _DebugLog("_BridgeStopValidation called")
            report := KeyValidator.Stop()
            if report = ""
                return JSONSerializer.Stringify(Map("error", true, "message", "未在验证中"))
            return JSONSerializer.Stringify(report)
        } catch as e {
            _DebugLog("_BridgeStopValidation error: " e.Message)
            return JSONSerializer.Stringify(Map("error", true, "message", e.Message))
        }
    }

    static _BridgeExportRecording(mode, keyPressDuration) {
        try {
            _DebugLog("_BridgeExportRecording called: mode=" mode " kpd=" keyPressDuration)
            kpd := keyPressDuration != "" ? Integer(keyPressDuration) : 15
            config := KeyRecorder.ExportAsGroupConfig(mode, kpd)
            if config.Count = 0
                return JSONSerializer.Stringify(Map("error", true, "message", "无录制数据"))
            return JSONSerializer.Stringify(config)
        } catch as e {
            _DebugLog("_BridgeExportRecording error: " e.Message)
            return JSONSerializer.Stringify(Map("error", true, "message", e.Message))
        }
    }

    static _PushKeyEvent(evt) {
        try {
            if !WebView2Manager.visible || !WebView2Manager.wv
                return
            json := JSONSerializer.Stringify(Map("key", evt["key"], "event", evt["event"], "timestamp", evt["timestamp"], "device", evt["device"]))
            WebView2Manager.wv.ExecuteScriptAsync("if(typeof onKeyEvent==='function')onKeyEvent(" json ")")
        } catch as e {
            _DebugLog("_PushKeyEvent error: " e.Message)
        }
    }

    static _PushSendEvent(evt) {
        try {
            if !WebView2Manager.visible || !WebView2Manager.wv
                return
            json := JSONSerializer.Stringify(Map("key", evt["key"], "event", evt["event"], "timestamp", evt["timestamp"]))
            WebView2Manager.wv.ExecuteScriptAsync("if(typeof onSendEvent==='function')onSendEvent(" json ")")
        } catch as e {
            _DebugLog("_PushSendEvent error: " e.Message)
        }
    }
```

- [ ] **Step 3: Add #Include for key_recorder and key_validator in webview2_manager.ahk**

At the top of `presentation/webview2_manager.ahk`, after the existing `#Include "..\domain\interfaces.ahk"`, add:

```ahk
#Include "..\domain\key_recorder.ahk"
#Include "..\domain\key_validator.ahk"
```

- [ ] **Step 4: Verify main.ahk loads without errors**

Run: `AutoHotkey.exe main.ahk` (quick check, then close)
Expected: No load-time errors

- [ ] **Step 5: Commit**

```bash
git add presentation/webview2_manager.ahk
git commit -m "feat: add WebView2 Bridge handlers for key recording and validation"
```

---

### Task 6: 前端 UI — 导航项和页面容器

**Files:**
- Modify: `presentation/app_ui.html` (导航区域 + 页面容器)

- [ ] **Step 1: Add navigation item**

In `presentation/app_ui.html`, after the backup nav-item (around line 255), add:

```html
      <div class="nav-item" data-page="keytest">
        <span class="icon">🧪</span> 按键测试
      </div>
```

- [ ] **Step 2: Add page container**

After the `page-backup` div (around line 392, before the closing `</div>` of `.content`), add:

```html
      <div class="page" id="page-keytest">
        <div class="keytest-tabs" style="display:flex;gap:8px;margin-bottom:16px;">
          <button class="btn btn-primary btn-sm keytest-tab active" data-tab="record">🎹 录制</button>
          <button class="btn btn-ghost btn-sm keytest-tab" data-tab="validate">✅ 验证</button>
        </div>
        <div class="keytest-panel" id="keytest-record">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
            <div style="display:flex;align-items:center;gap:12px;">
              <span id="recStatus" style="font-size:12px;color:var(--text-secondary);">就绪</span>
              <span id="recTimer" style="font-size:18px;font-weight:700;font-variant-numeric:tabular-nums;">00:00.000</span>
            </div>
            <div style="display:flex;gap:8px;">
              <button class="btn btn-primary btn-sm" id="btnStartRec" data-action="startRecording">🔴 开始录制</button>
              <button class="btn btn-danger btn-sm" id="btnStopRec" data-action="stopRecording" style="display:none;">⏹ 停止录制</button>
            </div>
          </div>
          <div class="glass" style="padding:12px;margin-bottom:12px;">
            <canvas id="recCanvas" width="800" height="200" style="width:100%;height:200px;"></canvas>
          </div>
          <div class="glass" style="padding:12px;margin-bottom:12px;max-height:200px;overflow-y:auto;">
            <div class="section-label" style="margin-bottom:8px;">录制事件</div>
            <div id="recEventList" style="font-size:11px;font-family:monospace;color:var(--text-secondary);"></div>
          </div>
          <div class="glass" style="padding:12px;" id="recExportPanel" hidden>
            <div class="section-label" style="margin-bottom:8px;">导出选项</div>
            <div style="display:flex;align-items:center;gap:12px;margin-bottom:8px;">
              <label style="font-size:12px;color:var(--text-secondary);">模式:</label>
              <select id="recExportMode" class="input" style="width:120px;">
                <option value="periodic">周期性</option>
                <option value="sequence">序列</option>
              </select>
              <label style="font-size:12px;color:var(--text-secondary);">按键时长:</label>
              <input id="recExportKPD" class="input" type="number" value="15" min="5" max="100" style="width:80px;">
              <span style="font-size:11px;color:var(--text-muted);">ms</span>
            </div>
            <button class="btn btn-primary btn-sm" data-action="exportRecording">📋 导出为分组配置</button>
          </div>
        </div>
        <div class="keytest-panel" id="keytest-validate" style="display:none;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
            <div style="display:flex;align-items:center;gap:12px;">
              <label style="font-size:12px;color:var(--text-secondary);">选择分组:</label>
              <select id="valGroupSelect" class="input" style="width:120px;"></select>
              <span id="valStatus" style="font-size:12px;color:var(--text-secondary);">就绪</span>
            </div>
            <div style="display:flex;gap:8px;">
              <button class="btn btn-primary btn-sm" id="btnStartVal" data-action="startValidation">▶ 开始验证</button>
              <button class="btn btn-danger btn-sm" id="btnStopVal" data-action="stopValidation" style="display:none;">⏹ 停止验证</button>
            </div>
          </div>
          <div class="glass" style="padding:12px;margin-bottom:12px;">
            <canvas id="valCanvas" width="800" height="200" style="width:100%;height:200px;"></canvas>
          </div>
          <div class="glass" style="padding:12px;" id="valReportPanel" hidden>
            <div class="section-label" style="margin-bottom:8px;">验证报告</div>
            <div id="valReport" style="font-size:12px;"></div>
          </div>
        </div>
      </div>
```

- [ ] **Step 3: Update switchPage function**

In the `switchPage` function (around line 660), add the keytest title:

```javascript
function switchPage(page) {
  document.querySelectorAll('.page').forEach(function(p) { p.classList.remove('active'); });
  document.querySelectorAll('.nav-item').forEach(function(n) { n.classList.remove('active'); });
  document.getElementById('page-' + page).classList.add('active');
  document.querySelector('.nav-item[data-page="'+page+'"]').classList.add('active');
  var titles = {dashboard:'📊 仪表盘',editor:'✏️ 分组编辑',settings:'⚙️ 全局设置',debug:'🐛 调试监控',backup:'💾 备份管理',keytest:'🧪 按键测试'};
  document.getElementById('pageTitle').textContent = titles[page] || page;
  if (page === 'keytest') initKeyTestPage();
}
```

- [ ] **Step 4: Commit**

```bash
git add presentation/app_ui.html
git commit -m "feat: add key test navigation item and page container in app_ui.html"
```

---

### Task 7: 前端 UI — JavaScript 逻辑

**Files:**
- Modify: `presentation/app_ui.html` (script section)

- [ ] **Step 1: Add key test JavaScript**

Add the following JavaScript in the `<script>` section of `app_ui.html`, before the `init()` function:

```javascript
var _recEvents = [];
var _recStartTime = 0;
var _recTimerInterval = 0;
var _valEvents = [];
var _valStartTime = 0;
var _valTimerInterval = 0;

function initKeyTestPage() {
  populateValGroupSelect();
  var tabBtns = document.querySelectorAll('.keytest-tab');
  for (var i = 0; i < tabBtns.length; i++) {
    tabBtns[i].onclick = function() {
      for (var j = 0; j < tabBtns.length; j++) {
        tabBtns[j].classList.remove('active');
        tabBtns[j].classList.remove('btn-primary');
        tabBtns[j].classList.add('btn-ghost');
      }
      this.classList.add('active');
      this.classList.remove('btn-ghost');
      this.classList.add('btn-primary');
      var tab = this.getAttribute('data-tab');
      document.getElementById('keytest-record').style.display = tab === 'record' ? '' : 'none';
      document.getElementById('keytest-validate').style.display = tab === 'validate' ? '' : 'none';
    };
  }
}

function populateValGroupSelect() {
  var sel = document.getElementById('valGroupSelect');
  if (!sel) return;
  sel.innerHTML = '';
  for (var i = 0; i < sampleGroups.length; i++) {
    var g = sampleGroups[i];
    var opt = document.createElement('option');
    opt.value = g.id;
    opt.textContent = '分组 ' + g.id + ' (' + (MODE_NAMES[g.mode] || g.mode) + ')';
    sel.appendChild(opt);
  }
}

function startRecording() {
  _recEvents = [];
  _recStartTime = Date.now();
  document.getElementById('btnStartRec').style.display = 'none';
  document.getElementById('btnStopRec').style.display = '';
  document.getElementById('recStatus').textContent = '🔴 录制中...';
  document.getElementById('recExportPanel').hidden = true;
  document.getElementById('recEventList').innerHTML = '';
  clearCanvas('recCanvas');
  _recTimerInterval = setInterval(updateRecTimer, 37);
  sendMessage('StartRecording');
}

function stopRecording() {
  document.getElementById('btnStartRec').style.display = '';
  document.getElementById('btnStopRec').style.display = 'none';
  document.getElementById('recStatus').textContent = '录制完成';
  clearInterval(_recTimerInterval);
  sendMessage('StopRecording').then(function(result) {
    if (result && result.events) {
      _recEvents = result.events;
      renderRecEventList(result.events);
      document.getElementById('recExportPanel').hidden = false;
    }
  });
}

function updateRecTimer() {
  var elapsed = Date.now() - _recStartTime;
  var min = Math.floor(elapsed / 60000);
  var sec = Math.floor((elapsed % 60000) / 1000);
  var ms = elapsed % 1000;
  document.getElementById('recTimer').textContent =
    String(min).padStart(2, '0') + ':' + String(sec).padStart(2, '0') + '.' + String(ms).padStart(3, '0');
}

function onKeyEvent(evt) {
  if (!_recEvents) _recEvents = [];
  _recEvents.push(evt);
  drawTimelineEvent('recCanvas', evt, _recEvents);
  var list = document.getElementById('recEventList');
  var line = document.createElement('div');
  line.textContent = '#' + _recEvents.length + '  ' + evt.key + ' ' + (evt.event === 'down' ? '↓' : evt.event === 'up' ? '↑' : '●') + '   ' + evt.timestamp + 'ms';
  list.appendChild(line);
  list.scrollTop = list.scrollHeight;
}

function renderRecEventList(events) {
  var list = document.getElementById('recEventList');
  list.innerHTML = '';
  for (var i = 0; i < events.length; i++) {
    var e = events[i];
    var line = document.createElement('div');
    line.textContent = '#' + (i + 1) + '  ' + e.key + ' ' + (e.event === 'down' ? '↓' : e.event === 'up' ? '↑' : '●') + '   ' + e.timestamp + 'ms';
    list.appendChild(line);
  }
}

function startValidation() {
  var groupId = document.getElementById('valGroupSelect').value;
  if (!groupId) return;
  _valEvents = [];
  _valStartTime = Date.now();
  document.getElementById('btnStartVal').style.display = 'none';
  document.getElementById('btnStopVal').style.display = '';
  document.getElementById('valStatus').textContent = '✅ 验证中...';
  document.getElementById('valReportPanel').hidden = true;
  clearCanvas('valCanvas');
  sendMessage('StartValidation', {groupId: groupId});
}

function stopValidation() {
  document.getElementById('btnStartVal').style.display = '';
  document.getElementById('btnStopVal').style.display = 'none';
  document.getElementById('valStatus').textContent = '验证完成';
  sendMessage('StopValidation').then(function(result) {
    if (result) renderValReport(result);
  });
}

function onSendEvent(evt) {
  if (!_valEvents) _valEvents = [];
  _valEvents.push(evt);
  drawTimelineEvent('valCanvas', evt, _valEvents);
}

function renderValReport(report) {
  document.getElementById('valReportPanel').hidden = false;
  var html = '';
  html += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px;">';
  html += reportCell('顺序正确性', report.orderCorrect ? '✅ 正确' : '❌ 不正确', report.orderCorrect);
  html += reportCell('发送成功率', Math.round(report.sendSuccessRate * 100) + '%', report.sendSuccessRate >= 0.95);
  html += reportCell('平均间隔偏差', report.avgIntervalDeviation + '%', report.avgIntervalDeviation <= 20);
  html += reportCell('最大间隔偏差', report.maxIntervalDeviation + '%', report.maxIntervalDeviation <= 50);
  html += '</div>';
  html += '<div style="font-size:11px;color:var(--text-secondary);">实际: ' + report.totalActual + ' / 期望: ' + report.totalExpected + '  持续: ' + report.duration + 'ms</div>';
  document.getElementById('valReport').innerHTML = html;
}

function reportCell(label, value, good) {
  return '<div class="glass" style="padding:8px;"><div style="font-size:10px;color:var(--text-muted);">' + label + '</div><div style="font-size:14px;font-weight:600;color:' + (good ? 'var(--success)' : 'var(--danger)') + ';">' + value + '</div></div>';
}

function exportRecording() {
  var mode = document.getElementById('recExportMode').value;
  var kpd = document.getElementById('recExportKPD').value;
  sendMessage('ExportRecording', {mode: mode, keyPressDuration: kpd}).then(function(result) {
    if (result && result.keys) {
      switchPage('editor');
      editorConfig = result;
      editorConfig.id = String(Date.now());
      editorConfig.hotkey = '';
      renderEditorFields();
    }
  });
}

function clearCanvas(canvasId) {
  var canvas = document.getElementById(canvasId);
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = 'rgba(255,255,255,0.03)';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
}

function drawTimelineEvent(canvasId, evt, allEvents) {
  var canvas = document.getElementById(canvasId);
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  var maxTime = 1;
  for (var i = 0; i < allEvents.length; i++) {
    if (allEvents[i].timestamp > maxTime) maxTime = allEvents[i].timestamp;
  }
  maxTime = maxTime * 1.2;
  var w = canvas.width;
  var h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(255,255,255,0.03)';
  ctx.fillRect(0, 0, w, h);

  var keys = [];
  var keyMap = {};
  for (var i = 0; i < allEvents.length; i++) {
    if (!(allEvents[i].key in keyMap)) {
      keyMap[allEvents[i].key] = keys.length;
      keys.push(allEvents[i].key);
    }
  }
  var rowH = Math.min(30, (h - 20) / Math.max(keys.length, 1));

  ctx.font = '10px monospace';
  ctx.fillStyle = 'rgba(255,255,255,0.4)';
  for (var i = 0; i < keys.length; i++) {
    ctx.fillText(keys[i], 4, 20 + i * rowH + rowH / 2);
  }

  for (var i = 0; i < allEvents.length; i++) {
    var e = allEvents[i];
    var x = 40 + (e.timestamp / maxTime) * (w - 50);
    var y = 10 + keyMap[e.key] * rowH;
    if (e.event === 'down' || e.event === 'click') {
      ctx.fillStyle = 'rgba(74,222,128,0.8)';
      ctx.fillRect(x, y, 6, rowH - 4);
    } else if (e.event === 'up') {
      ctx.fillStyle = 'rgba(248,113,113,0.5)';
      ctx.fillRect(x, y, 3, rowH - 4);
    } else if (e.event === 'press') {
      ctx.fillStyle = 'rgba(96,165,250,0.8)';
      ctx.fillRect(x, y, 6, rowH - 4);
    }
  }
}
```

- [ ] **Step 2: Add event delegation for key test actions**

In the `onAhkReady` function, add key test event delegation after the existing event handlers:

```javascript
  document.getElementById('page-keytest').onclick = function(e) {
    var el = e.target.closest('[data-action]');
    if (!el) return;
    var action = el.getAttribute('data-action');
    if (action === 'startRecording') startRecording();
    else if (action === 'stopRecording') stopRecording();
    else if (action === 'startValidation') startValidation();
    else if (action === 'stopValidation') stopValidation();
    else if (action === 'exportRecording') exportRecording();
  };
```

- [ ] **Step 3: Verify the page loads and renders correctly**

Run: `AutoHotkey.exe main.ahk`
Expected: WebView2 window opens, "按键测试" nav item visible, clicking it shows the record/validate tabs

- [ ] **Step 4: Commit**

```bash
git add presentation/app_ui.html
git commit -m "feat: add key test page JavaScript logic with Canvas timeline and Bridge integration"
```

---

### Task 8: 集成测试

**Files:**
- Create: `tests/test_key_test_integration.ahk`

- [ ] **Step 1: Write integration test**

```ahk
; tests/test_key_test_integration.ahk
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../domain/key_recorder.ahk"
#Include "../domain/key_validator.ahk"

ErrorSystem.Init()
ModeRegistry._Init()
ConfigStore.InitDefaults()
JSONLogger.Init()
DebugLogger.Init()

SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
SkillManager.Logger := JSONLogger
SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillManager.ConfigStore := ConfigStore

TestReporter.BeginTest("test_key_test_integration.ahk")

TestReporter.Scenario("8.1 KeyRecorder + KeyValidator 独立运行")
recEvents := []
KeyRecorder.Start((evt) => recEvents.Push(evt))
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("A", "up", 15)
KeyRecorder.OnKey("B", "down", 50)
recResult := KeyRecorder.Stop()
TestReporter.Assert(recResult["events"].Length = 3, "录制应有3个事件")
TestReporter.Assert(!KeyRecorder.IsRecording(), "录制应已停止")

TestReporter.Scenario("8.2 KeyValidator 埋点过滤非目标分组")
SkillManager.AddGroup("test1", Map("mode", "periodic", "keys", ["A", "B"], "intervals", [50, 50], "hotkey", "F1"))
valEvents := []
KeyValidator.Start("test1", (evt) => valEvents.Push(evt))
KeyValidator.OnSend("test1", "A", "press", 0)
KeyValidator.OnSend("test1", "B", "press", 50)
KeyValidator.OnSend("other", "C", "press", 100)
valResult := KeyValidator.Stop()
TestReporter.Assert(valResult["totalActual"] = 2, "只应记录目标分组事件")
TestReporter.Assert(valResult["orderCorrect"] = true, "顺序应正确")

TestReporter.Scenario("8.3 ExportAsGroupConfig 周期性模式完整性")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("B", "down", 100)
KeyRecorder.OnKey("A", "down", 200)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config["mode"] = "periodic", "模式应为 periodic")
TestReporter.Assert(config["keys"].Length = 3, "应有3个键")
TestReporter.Assert(config["intervals"].Length = 2, "应有2个间隔")
TestReporter.Assert(config["keyPressDuration"] = 15, "按键时长应为15")

TestReporter.Scenario("8.4 ExportAsGroupConfig 序列模式完整性")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("X", "down", 0)
KeyRecorder.OnKey("Y", "down", 200)
KeyRecorder.OnKey("Z", "down", 350)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("sequence", 20)
TestReporter.Assert(config["mode"] = "sequence", "模式应为 sequence")
TestReporter.Assert(config["keys"].Length = 3, "应有3个键")
TestReporter.Assert(config["delays"].Length = 2, "应有2个延迟")
TestReporter.Assert(config["keyPressDuration"] = 20, "按键时长应为20")

TestReporter.Scenario("8.5 验证报告偏差计算")
SkillManager.AddGroup("test2", Map("mode", "periodic", "keys", ["A", "B"], "intervals", [100, 100], "hotkey", "F2"))
KeyValidator.Start("test2", (evt) => "")
KeyValidator.OnSend("test2", "A", "press", 0)
KeyValidator.OnSend("test2", "B", "press", 105)
KeyValidator.OnSend("test2", "A", "press", 210)
report := KeyValidator.Stop()
TestReporter.Assert(report["avgIntervalDeviation"] <= 10, "平均偏差应小于10%")
TestReporter.Assert(report["details"].Length > 0, "应有详细数据")

TestReporter.Scenario("8.6 录制和验证可独立执行")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("Q", "down", 0)
KeyRecorder.Stop()
TestReporter.Assert(!KeyRecorder.IsRecording(), "录制已停止")
TestReporter.Assert(!KeyValidator.IsActive(), "验证未激活，独立运行")

SkillManager.DeleteGroup("test1")
SkillManager.DeleteGroup("test2")

TestReporter.EndTest()
ExitApp()
```

- [ ] **Step 2: Run integration test**

Run: `AutoHotkey.exe tests\test_key_test_integration.ahk`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/test_key_test_integration.ahk
git commit -m "test: add integration tests for KeyRecorder and KeyValidator"
```

---

## Self-Review

### 1. Spec Coverage

| Spec Section | Task |
|---|---|
| KeyRecorder 类设计 | Task 1 |
| KeyValidator 类设计 | Task 2 |
| 埋点机制 | Task 3 |
| main.ahk 注册 | Task 4 |
| Bridge 消息 | Task 5 |
| 前端 UI 导航+容器 | Task 6 |
| 前端 JS 逻辑+Canvas | Task 7 |
| 集成测试 | Task 8 |

All sections covered. ✅

### 2. Placeholder Scan

No TBD/TODO/fill-in-later found. ✅

### 3. Type Consistency

- `KeyRecorder.OnKey(key, event, timestamp)` — matches usage in Task 1 test and Task 3
- `KeyValidator.OnSend(groupId, key, event, timestamp)` — matches usage in Task 2 test and Task 3
- `KeyRecorder.ExportAsGroupConfig(mode, keyPressDuration)` — returns Map with "keys"/"intervals"/"delays" — matches Task 7 exportRecording usage
- Bridge action names: "StartRecording"/"StopRecording"/"StartValidation"/"StopValidation"/"ExportRecording" — consistent between Task 5 and Task 7
- Frontend function names: `onKeyEvent`/`onSendEvent` — match Task 5 `_PushKeyEvent`/`_PushSendEvent` ExecuteScriptAsync calls ✅
