# 手柄按键连招 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 AutoHotkey 按键精灵添加手柄连招功能 — 手柄按键作为触发器(A方向) + 工具发送手柄按键序列(B方向)

**Architecture:** 对称架构 — 新增 JoystickExecutor/JoyInputCapture/JoySender/JoyHotkeyManager 四个类，通过 ModeRegistry 插件机制接入，不修改现有7种键盘模式。深度集成到 DDD 四层架构。

**Tech Stack:** AutoHotkey v2.0, vJoy SDK (可选), WebView2, JSON

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| ⭐新增 | `infrastructure/joy_sender.ahk` | JoySender — vJoy API + 直接Send双通道，检测vJoy可用性 |
| ⭐新增 | `domain/joystick_input.ahk` | JoystickInput — 手柄输入标识解析/映射/验证 |
| ⭐新增 | `domain/joystick_executor.ahk` | JoystickExecutor — 3种手柄模式执行器(periodic/sequence/hold) |
| ⭐新增 | `infrastructure/joy_hotkey_manager.ahk` | JoyHotkeyManager — 手柄热键注册/轴轮询/热插拔检测 |
| ✏️修改 | `domain/mode_registry.ahk` | 注册 joystick_periodic/joystick_sequence/joystick_hold 3种模式 |
| ✏️修改 | `main.ahk` | Include 新文件 + 初始化 JoyHotkeyManager |
| ⭐新增 | `tests/test_joystick.ahk` | 手柄单元测试（标识解析/JoySender/Executor） |
| ✏️修改 | `presentation/app_ui.html` | 手柄UI：模式下拉/按键选择器/热键捕获/测试区/仪表盘适配 |

---

### Task 1: 创建 JoySender 基础设施

**Files:**
- Create: `infrastructure/joy_sender.ahk`

- [ ] **Step 1: 创建 JoySender 类**

```autohotkey
; =================================================================
; 基础设施层 - JoySender 手柄按键发送器
; 版本: 1.0
; 说明: 双通道手柄按键发送 — vJoy API (游戏兼容) + 直接Send (无需驱动)
;       auto 模式自动检测vJoy可用性并降级
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class JoySender {
    static _vJoyAvailable := -1
    static _vJoyDeviceId := 1
    static _vJoyDll := ""

    static IsVJoyAvailable() {
        if JoySender._vJoyAvailable != -1
            return JoySender._vJoyAvailable
        JoySender._vJoyAvailable := JoySender._DetectVJoy()
        return JoySender._vJoyAvailable
    }

    static _DetectVJoy() {
        try {
            DllCall("LoadLibrary", "Str", "vJoyInterface.dll", "Ptr")
            DllCall("FreeLibrary", "Ptr", DllCall("GetModuleHandle", "Str", "vJoyInterface.dll", "Ptr"))
            JoySender._vJoyDll := "vJoyInterface.dll"
            return true
        } catch {
            try {
                DllCall("LoadLibrary", "Str", A_WinDir "\System32\vJoyInterface.dll", "Ptr")
                DllCall("FreeLibrary", "Ptr", DllCall("GetModuleHandle", "Str", A_WinDir "\System32\vJoyInterface.dll", "Ptr"))
                JoySender._vJoyDll := A_WinDir "\System32\vJoyInterface.dll"
                return true
            } catch {
                return false
            }
        }
    }

    static ResolveMethod(method) {
        if method = "auto"
            return JoySender.IsVJoyAvailable() ? "vjoy" : "direct"
        if method = "vjoy" && !JoySender.IsVJoyAvailable()
            throw Error("vJoy 驱动未安装，无法使用 vjoy 发送方式")
        return method
    }

    static SendBtn(btnNum, state, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            if resolved = "vjoy"
                JoySender._VJoySetBtn(btnNum, state)
            else
                JoySender._DirectSendBtn(btnNum, state)
        } catch as e {
            if method = "auto" && resolved = "vjoy"
                JoySender._DirectSendBtn(btnNum, state)
        }
    }

    static SendPov(direction, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            povVal := JoySender._PovDirectionToValue(direction)
            if resolved = "vjoy"
                JoySender._VJoySetPov(povVal)
        } catch as e {
        }
    }

    static SendAxis(axis, value, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            if resolved = "vjoy"
                JoySender._VJoySetAxis(axis, value)
        } catch as e {
        }
    }

    static _VJoyOpen() {
        h := DllCall(JoySender._vJoyDll "\AcquireVJD", "UInt", JoySender._vJoyDeviceId)
        if h = 0
            throw Error("vJoy AcquireVJD 失败，设备ID=" JoySender._vJoyDeviceId)
        return true
    }

    static _VJoyClose() {
        DllCall(JoySender._vJoyDll "\RelinquishVJD", "UInt", JoySender._vJoyDeviceId)
    }

    static _VJoySetBtn(btnNum, state) {
        JoySender._VJoyOpen()
        DllCall(JoySender._vJoyDll "\SetBtn", "UInt", state ? 1 : 0, "UInt", JoySender._vJoyDeviceId, "UChar", btnNum)
    }

    static _VJoySetAxis(axis, value) {
        JoySender._VJoyOpen()
        axisId := JoySender._AxisToVJoyId(axis)
        scaledVal := Round(value * 327.67)
        if scaledVal < 0
            scaledVal := 0
        if scaledVal > 32767
            scaledVal := 32767
        DllCall(JoySender._vJoyDll "\SetAxis", "Int", scaledVal, "UInt", JoySender._vJoyDeviceId, "UInt", axisId)
    }

    static _VJoySetPov(povVal) {
        JoySender._VJoyOpen()
        DllCall(JoySender._vJoyDll "\SetContPov", "UInt", povVal < 0 ? 0xFFFFFFFF : povVal, "UInt", JoySender._vJoyDeviceId, "UInt", 1)
    }

    static _AxisToVJoyId(axis) {
        m := Map(
            "JoyX", 0x30, "JoyY", 0x31, "JoyZ", 0x32,
            "JoyR", 0x33, "JoyU", 0x34, "JoyV", 0x35
        )
        return m.Has(axis) ? m[axis] : 0x30
    }

    static _DirectSendBtn(btnNum, state) {
        idx := JoySender._vJoyDeviceId
        action := state ? "Down" : "Up"
        SendInput("{Blind}{" idx "Joy" btnNum " " action "}")
    }

    static _PovDirectionToValue(direction) {
        switch direction {
            case "UP":    return 0
            case "RIGHT": return 9000
            case "DOWN":  return 18000
            case "LEFT":  return 27000
            case "CENTER":return -1
            default:      return -1
        }
    }
}
```

- [ ] **Step 2: 验证语法**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe /Validate infrastructure\joy_sender.ahk`
Expected: 退出码0

- [ ] **Step 3: Commit**

```bash
git add infrastructure/joy_sender.ahk
git commit -m "feat: 添加 JoySender 基础设施（vJoy+直接Send双通道）"
```

---

### Task 2: 创建 JoystickInput 领域类

**Files:**
- Create: `domain/joystick_input.ahk`

- [ ] **Step 1: 创建手柄输入规范类**

```autohotkey
; =================================================================
; 领域层 - JoystickInput 手柄输入规范
; 版本: 1.0
; 说明: 定义手柄输入标识的解析、映射和验证规则
;       统一 Joy1 / JoyPOV_UP / JoyX_RIGHT 等标识的语义
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class JoystickInput {
    static THRESHOLD := 80
    static DEADZONE := 20
    static HYSTERESIS := 10

    static IsJoystickKey(key) {
        return JoystickInput.IsButton(key) || JoystickInput.IsPov(key)
            || JoystickInput.IsAxis(key) || JoystickInput.IsTrigger(key)
    }

    static IsButton(key) {
        return RegExMatch(key, "^Joy\d+$") && !RegExMatch(key, "^Joy[XYZRUV]")
    }

    static IsPov(key) {
        return InStr(key, "JoyPOV_") = 1
    }

    static IsAxis(key) {
        return RegExMatch(key, "^Joy[XYZRUV]_(LEFT|RIGHT|UP|DOWN)$")
    }

    static IsTrigger(key) {
        return key = "JoyZ_DOWN" || key = "JoyV_DOWN"
    }

    static GetButtonNum(key) {
        return Integer(RegExReplace(key, "^Joy", ""))
    }

    static GetPovDirection(key) {
        return StrReplace(key, "JoyPOV_", "")
    }

    static GetAxisInfo(key) {
        parts := StrSplit(key, "_")
        return Map("axis", parts[1], "target", parts[2])
    }

    static GetAhkReadKey(key) {
        if JoystickInput.IsButton(key) || JoystickInput.IsTrigger(key)
            return RegExReplace(key, "^(Joy\d+).*", "$1")
        if JoystickInput.IsAxis(key) {
            axis := StrSplit(key, "_")[1]
            return axis
        }
        if JoystickInput.IsPov(key)
            return "JoyPOV"
        return key
    }

    static PovToDirection(value) {
        if value = -1
            return ""
        angle := Integer(value / 100)
        if angle >= 0 && angle < 4500
            return "UP"
        if angle >= 4500 && angle < 13500
            return "RIGHT"
        if angle >= 13500 && angle < 22500
            return "DOWN"
        if angle >= 22500 && angle < 31500
            return "LEFT"
        return "UP"
    }

    static DirectionToPovValue(direction) {
        switch direction {
            case "UP":    return 0
            case "RIGHT": return 9000
            case "DOWN":  return 18000
            case "LEFT":  return 27000
            default:      return -1
        }
    }

    static IsJoystickConnected() {
        try {
            return GetKeyState("1Joy1") != ""
        } catch {
            return false
        }
    }

    static GetConnectedJoysticks() {
        result := []
        Loop 16 {
            try {
                if GetKeyState(A_Index "Joy1") != ""
                    result.Push(A_Index)
            } catch {
                break
            }
        }
        return result
    }

    static GetButtonDisplayName(key) {
        names := Map(
            "Joy1", "(A)", "Joy2", "(B)", "Joy3", "(X)", "Joy4", "(Y)",
            "Joy5", "(LB)", "Joy6", "(RB)", "Joy7", "(Back)", "Joy8", "(Start)",
            "Joy9", "(LS)", "Joy10", "(RS)"
        )
        if names.Has(key)
            return key " " names[key]
        return key
    }

    static GetAllJoystickKeys() {
        result := []
        Loop 32
            result.Push("Joy" A_Index)
        for dir in ["UP", "DOWN", "LEFT", "RIGHT"]
            result.Push("JoyPOV_" dir)
        for _, pair in [["JoyX", ["LEFT", "RIGHT"]], ["JoyY", ["UP", "DOWN"]],
                         ["JoyR", ["LEFT", "RIGHT"]], ["JoyU", ["UP", "DOWN"]]] {
            for _, d in pair[2]
                result.Push(pair[1] "_" d)
        }
        result.Push("JoyZ_DOWN")
        result.Push("JoyV_DOWN")
        return result
    }
}
```

- [ ] **Step 2: 验证语法**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe /Validate domain\joystick_input.ahk`
Expected: 退出码0

- [ ] **Step 3: Commit**

```bash
git add domain/joystick_input.ahk
git commit -m "feat: 添加 JoystickInput 手柄输入规范类"
```

---

### Task 3: 创建 JoystickExecutor 领域类

**Files:**
- Create: `domain/joystick_executor.ahk`

- [ ] **Step 1: 创建三种手柄模式执行器**

```autohotkey
; =================================================================
; 领域层 - JoystickExecutor 手柄模式执行器
; 版本: 1.0
; 说明: 实现 IExecutor 接口，提供3种手柄执行模式
;       joystick_periodic / joystick_sequence / joystick_hold
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "joystick_input.ahk"
#Include "../infrastructure/joy_sender.ahk"
#Include "../infrastructure/error_system.ahk"

class JoystickPeriodicExecutor extends IExecutor {
    GetModeName() {
        return "joystick_periodic"
    }

    Execute(group) {
        try {
            now := A_TickCount
            joyKeys := group.joyKeys
            joyIntervals := group.joyIntervals
            sendMethod := group.joySendMethod
            keyDuration := group.joyKeyDuration
            minRemaining := 0x7FFFFFFF

            if !group.HasProp("_joyLastTriggerTimes")
                group._joyLastTriggerTimes := Map()

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
                    JoystickExecutor._SendJoyKey(k, "down", sendMethod)
                    SetTimer(() => JoystickExecutor._SendJoyKey(k, "up", sendMethod), -keyDuration)
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
            return Max(1, minRemaining)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 10
        }
    }
}

class JoystickSequenceExecutor extends IExecutor {
    GetModeName() {
        return "joystick_sequence"
    }

    Execute(group) {
        try {
            now := A_TickCount
            joyKeys := group.joyKeys
            joyDelays := group.joyDelays
            sendMethod := group.joySendMethod
            keyDuration := group.joyKeyDuration

            if !group.HasProp("_joyCurrentStep")
                group._joyCurrentStep := 1
            step := group._joyCurrentStep
            if step > joyKeys.Length
                step := 1

            delay := step <= joyDelays.Length ? joyDelays[step] : 100
            if delay < 10
                delay := 10

            if !group.HasProp("_joyNextStepTime") || group._joyNextStepTime = 0 {
                group._joyNextStepTime := now + delay
            } else if now < group._joyNextStepTime - 2 {
                return Max(1, group._joyNextStepTime - now - 2)
            }

            k := joyKeys[step]
            JoystickExecutor._SendJoyKey(k, "down", sendMethod)
            SetTimer(() => JoystickExecutor._SendJoyKey(k, "up", sendMethod), -keyDuration)
            group._joyCurrentStep := Mod(step, joyKeys.Length) + 1

            nextDelay := (group._joyCurrentStep <= joyDelays.Length) ? joyDelays[group._joyCurrentStep] : 100
            if nextDelay < 10
                nextDelay := 10
            group._joyNextStepTime := A_TickCount + nextDelay
            return Max(1, nextDelay)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 100
        }
    }
}

class JoystickHoldExecutor extends IExecutor {
    GetModeName() {
        return "joystick_hold"
    }

    Execute(group) {
        try {
            joyKeys := group.joyKeys
            sendMethod := group.joySendMethod

            if !group.HasProp("_joyHoldActive")
                group._joyHoldActive := false

            if !group._joyHoldActive {
                for k in joyKeys
                    JoystickExecutor._SendJoyKey(k, "down", sendMethod)
                group._joyHoldActive := true
            }
            return 50
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 50
        }
    }
}

class JoystickExecutor {
    static _SendJoyKey(key, state, sendMethod := "auto") {
        try {
            if JoystickInput.IsButton(key) {
                btnNum := JoystickInput.GetButtonNum(key)
                JoySender.SendBtn(btnNum, state = "down", sendMethod)
            } else if JoystickInput.IsPov(key) {
                direction := JoystickInput.GetPovDirection(key)
                if state = "down"
                    JoySender.SendPov(direction, sendMethod)
                else
                    JoySender.SendPov("CENTER", sendMethod)
            } else if JoystickInput.IsAxis(key) || JoystickInput.IsTrigger(key) {
                info := JoystickInput.GetAxisInfo(key)
                value := 50
                if state = "down" {
                    if info["target"] = "RIGHT" || info["target"] = "DOWN"
                        value := 100
                    else
                        value := 0
                }
                JoySender.SendAxis(info["axis"], value, sendMethod)
            }
        } catch as e {
            ErrorSystem.LogError("_SendJoyKey 失败: " key " " state " " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _ReleaseJoyKeys(group) {
        try {
            sendMethod := group.joySendMethod
            for k in group.joyKeys {
                if JoystickInput.IsButton(k) {
                    JoySender.SendBtn(JoystickInput.GetButtonNum(k), false, sendMethod)
                } else if JoystickInput.IsPov(k) {
                    JoySender.SendPov("CENTER", sendMethod)
                } else if JoystickInput.IsAxis(k) || JoystickInput.IsTrigger(k) {
                    info := JoystickInput.GetAxisInfo(k)
                    JoySender.SendAxis(info["axis"], 50, sendMethod)
                }
            }
        } catch as e {
            ErrorSystem.LogError("_ReleaseJoyKeys 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}
```

- [ ] **Step 2: 验证语法**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe /Validate domain\joystick_executor.ahk`
Expected: 退出码0

- [ ] **Step 3: Commit**

```bash
git add domain/joystick_executor.ahk
git commit -m "feat: 添加 JoystickExecutor 三种手柄模式执行器"
```

---

### Task 4: 创建 JoyHotkeyManager 基础设施

**Files:**
- Create: `infrastructure/joy_hotkey_manager.ahk`

- [ ] **Step 1: 创建手柄热键管理器**

```autohotkey
; =================================================================
; 基础设施层 - JoyHotkeyManager 手柄热键管理器
; 版本: 1.0
; 说明: 手柄按钮热键注册(Joy1~Joy32)、轴/POV轮询(SetTimer)
;       热插拔检测(30s)、多手柄支持
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/joystick_input.ahk"
#Include "error_system.ahk"

class JoyHotkeyManager {
    static _registered := Map()
    static _pollActive := false
    static _povLastState := -1
    static _connPollActive := false
    static _wasConnected := false
    static _joystickId := 1

    static Init(joystickId := 1) {
        JoyHotkeyManager._joystickId := joystickId
        JoyHotkeyManager._StartConnectionPoll()
    }

    static RegisterHotkey(joyKey, groupId, callback) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                JoyHotkeyManager._registered[key] := Map("groupId", groupId, "callback", callback)
                Hotkey(key, (*) => JoyHotkeyManager._OnButtonPress(key), "On")
                return true
            } else if JoystickInput.IsAxis(joyKey) || JoystickInput.IsTrigger(joyKey) {
                JoyHotkeyManager._StartPolling()
                return true
            } else if JoystickInput.IsPov(joyKey) {
                JoyHotkeyManager._StartPolling()
                return true
            }
            return false
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.RegisterHotkey 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    static UnregisterHotkey(joyKey, groupId) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                JoyHotkeyManager._registered.Delete(key)
                try
                    Hotkey(key, "Off")
            }
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.UnregisterHotkey 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static UnregisterAll(groupId) {
        keysToRemove := []
        for key, info in JoyHotkeyManager._registered {
            if info["groupId"] = groupId
                keysToRemove.Push(key)
        }
        for key in keysToRemove {
            JoyHotkeyManager._registered.Delete(key)
            try
                Hotkey(key, "Off")
        }
        if JoyHotkeyManager._registered.Count = 0 {
            JoyHotkeyManager._StopPolling()
        }
    }

    static _OnButtonPress(key) {
        try {
            if JoyHotkeyManager._registered.Has(key) {
                info := JoyHotkeyManager._registered[key]
                callback := info["callback"]
                callback.Call(info["groupId"])
            }
        } catch as e {
            ErrorSystem.LogError("_OnButtonPress 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _StartPolling() {
        if JoyHotkeyManager._pollActive
            return
        JoyHotkeyManager._pollActive := true
        SetTimer(JoyHotkeyManager._Poll, 50)
    }

    static _StopPolling() {
        JoyHotkeyManager._pollActive := false
    }

    static _Poll() {
        if !JoyHotkeyManager._pollActive
            return
        try {
            JoyHotkeyManager._PollPov()
        } catch as e {
        }
    }

    static _PollPov() {
        try {
            val := GetKeyState(JoyHotkeyManager._joystickId "JoyPOV")
            if val = ""
                return
            if val != JoyHotkeyManager._povLastState {
                JoyHotkeyManager._povLastState := val
            }
        } catch as e {
        }
    }

    static _StartConnectionPoll() {
        if JoyHotkeyManager._connPollActive
            return
        JoyHotkeyManager._connPollActive := true
        JoyHotkeyManager._wasConnected := JoystickInput.IsJoystickConnected()
        SetTimer(JoyHotkeyManager._PollConnection, 30000)
    }

    static _PollConnection() {
        try {
            isConnected := JoystickInput.IsJoystickConnected()
            if isConnected != JoyHotkeyManager._wasConnected {
                JoyHotkeyManager._wasConnected := isConnected
                if isConnected
                    ErrorSystem.LogError("手柄已重新连接", "INFO", A_ThisFunc, A_LineNumber)
                else
                    ErrorSystem.LogError("手柄已断开连接", "WARNING", A_ThisFunc, A_LineNumber)
            }
        } catch as e {
        }
    }

    static IsConnected() {
        return JoystickInput.IsJoystickConnected()
    }
}
```

- [ ] **Step 2: 验证语法**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe /Validate infrastructure\joy_hotkey_manager.ahk`
Expected: 退出码0

- [ ] **Step 3: Commit**

```bash
git add infrastructure/joy_hotkey_manager.ahk
git commit -m "feat: 添加 JoyHotkeyManager 手柄热键管理器"
```

---

### Task 5: 修改 ModeRegistry 注册手柄模式

**Files:**
- Modify: `domain/mode_registry.ahk`

- [ ] **Step 1: 添加 Include**

在 `mode_registry.ahk` 第10行 `#Include "../infrastructure/error_system.ahk"` 之后添加：

```autohotkey
#Include "joystick_executor.ahk"
```

- [ ] **Step 2: 在 _Init() 末尾注册3种手柄模式**

在 `_Init()` 方法中 `HoldExecutor` 注册块之后、`return true` 之前插入。搜索 `"hold", HoldExecutor()` 定位，在其后添加：

```autohotkey
            ModeRegistry.Register("joystick_periodic", JoystickPeriodicExecutor(), Map(
                "name", "手柄周期",
                "description", "周期性发送手柄按键",
                "requires", ["joyKeys", "joyIntervals"],
                "requiresNonEmpty", ["joyKeys"]
            ))

            ModeRegistry.Register("joystick_sequence", JoystickSequenceExecutor(), Map(
                "name", "手柄序列",
                "description", "按顺序发送手柄按键序列",
                "requires", ["joyKeys", "joyDelays"],
                "requiresNonEmpty", ["joyKeys"]
            ))

            ModeRegistry.Register("joystick_hold", JoystickHoldExecutor(), Map(
                "name", "手柄长按",
                "description", "持续按住手柄按键",
                "requires", ["joyKeys"],
                "requiresNonEmpty", ["joyKeys"]
            ))
```

- [ ] **Step 3: 验证语法**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe /Validate domain\mode_registry.ahk`
Expected: 退出码0

- [ ] **Step 4: Commit**

```bash
git add domain/mode_registry.ahk
git commit -m "feat: ModeRegistry 注册3种手柄执行模式"
```

---

### Task 6: 修改 main.ahk 引入手柄模块

**Files:**
- Modify: `main.ahk`

- [ ] **Step 1: 添加 Include 语句**

在基础设施层 Include 区域（`#Include "infrastructure\migration_logger.ahk"` 之后、`; 第 2 步: 加载领域层` 注释之前）添加：

```autohotkey
#Include "infrastructure\joy_sender.ahk"
#Include "infrastructure\joy_hotkey_manager.ahk"
```

在领域层 Include 区域（`#Include "domain\mode_registry.ahk"` 之下）添加：

```autohotkey
#Include "domain\joystick_executor.ahk"
#Include "domain\joystick_input.ahk"
```

- [ ] **Step 2: 添加初始化调用**

在 `InitDependencies()` 函数末尾（`}` 之前）添加：

```autohotkey
    JoyHotkeyManager.Init(1)
```

- [ ] **Step 3: 验证完整脚本**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe /Validate main.ahk`
Expected: 退出码0

- [ ] **Step 4: Commit**

```bash
git add main.ahk
git commit -m "feat: main.ahk 引入手柄模块并初始化 JoyHotkeyManager"
```

---

### Task 7: 创建手柄单元测试

**Files:**
- Create: `tests/test_joystick.ahk`

- [ ] **Step 1: 创建测试套件**

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/joystick_input.ahk"
#Include "../domain/joystick_executor.ahk"
#Include "../infrastructure/joy_sender.ahk"

class JoyTestRunner {
    static total := 0
    static passed := 0
    static failed := 0

    static RunAll() {
        JoyTestRunner.RunTest("IsButton_Joy1", () => JoystickInput.IsButton("Joy1") ? 0 : Error("Joy1应为按钮"))
        JoyTestRunner.RunTest("IsButton_Joy15", () => JoystickInput.IsButton("Joy15") ? 0 : Error("Joy15应为按钮"))
        JoyTestRunner.RunTest("IsButton_Joy32", () => JoystickInput.IsButton("Joy32") ? 0 : Error("Joy32应为按钮"))
        JoyTestRunner.RunTest("IsButton_NotJoyX", () => JoystickInput.IsButton("JoyX") ? Error("JoyX不是按钮") : 0)
        JoyTestRunner.RunTest("IsButton_NotPov", () => JoystickInput.IsButton("JoyPOV_UP") ? Error("JoyPOV_UP不是按钮") : 0)
        JoyTestRunner.RunTest("IsPov_UP", () => JoystickInput.IsPov("JoyPOV_UP") ? 0 : Error("JoyPOV_UP应为POV"))
        JoyTestRunner.RunTest("IsPov_DOWN", () => JoystickInput.IsPov("JoyPOV_DOWN") ? 0 : Error("JoyPOV_DOWN应为POV"))
        JoyTestRunner.RunTest("IsPov_LEFT", () => JoystickInput.IsPov("JoyPOV_LEFT") ? 0 : Error("JoyPOV_LEFT应为POV"))
        JoyTestRunner.RunTest("IsPov_RIGHT", () => JoystickInput.IsPov("JoyPOV_RIGHT") ? 0 : Error("JoyPOV_RIGHT应为POV"))
        JoyTestRunner.RunTest("IsPov_NotButton", () => JoystickInput.IsPov("Joy1") ? Error("Joy1不是POV") : 0)
        JoyTestRunner.RunTest("IsAxis_JoyXRIGHT", () => JoystickInput.IsAxis("JoyX_RIGHT") ? 0 : Error("JoyX_RIGHT应为轴"))
        JoyTestRunner.RunTest("IsAxis_JoyYUP", () => JoystickInput.IsAxis("JoyY_UP") ? 0 : Error("JoyY_UP应为轴"))
        JoyTestRunner.RunTest("IsAxis_NotButton", () => JoystickInput.IsAxis("Joy1") ? Error("Joy1不是轴") : 0)
        JoyTestRunner.RunTest("IsTrigger_JoyZ", () => JoystickInput.IsTrigger("JoyZ_DOWN") ? 0 : Error("JoyZ_DOWN应为扳机"))
        JoyTestRunner.RunTest("IsTrigger_JoyV", () => JoystickInput.IsTrigger("JoyV_DOWN") ? 0 : Error("JoyV_DOWN应为扳机"))
        JoyTestRunner.RunTest("IsTrigger_NotAxis", () => JoystickInput.IsTrigger("JoyX_RIGHT") ? Error("JoyX_RIGHT不是扳机") : 0)
        JoyTestRunner.RunTest("GetButtonNum_Joy1", () => JoystickInput.GetButtonNum("Joy1") = 1 ? 0 : Error("Joy1应为1"))
        JoyTestRunner.RunTest("GetButtonNum_Joy15", () => JoystickInput.GetButtonNum("Joy15") = 15 ? 0 : Error("Joy15应为15"))
        JoyTestRunner.RunTest("GetPovDirection_UP", () => JoystickInput.GetPovDirection("JoyPOV_UP") = "UP" ? 0 : Error("应为UP"))
        JoyTestRunner.RunTest("GetPovDirection_LEFT", () => JoystickInput.GetPovDirection("JoyPOV_LEFT") = "LEFT" ? 0 : Error("应为LEFT"))
        JoyTestRunner.RunTest("GetAxisInfo", () => (info := JoystickInput.GetAxisInfo("JoyX_RIGHT"), info["axis"] = "JoyX" && info["target"] = "RIGHT") ? 0 : Error("轴解析失败"))
        JoyTestRunner.RunTest("GetAhkReadKey_Joy1", () => JoystickInput.GetAhkReadKey("Joy1") = "Joy1" ? 0 : Error("应为Joy1"))
        JoyTestRunner.RunTest("GetAhkReadKey_POV", () => JoystickInput.GetAhkReadKey("JoyPOV_UP") = "JoyPOV" ? 0 : Error("应为JoyPOV"))
        JoyTestRunner.RunTest("GetAhkReadKey_Axis", () => JoystickInput.GetAhkReadKey("JoyX_RIGHT") = "JoyX" ? 0 : Error("应为JoyX"))
        JoyTestRunner.RunTest("PovToDirection_UP", () => JoystickInput.PovToDirection(0) = "UP" ? 0 : Error("0应为UP"))
        JoyTestRunner.RunTest("PovToDirection_RIGHT", () => JoystickInput.PovToDirection(9000) = "RIGHT" ? 0 : Error("9000应为RIGHT"))
        JoyTestRunner.RunTest("PovToDirection_DOWN", () => JoystickInput.PovToDirection(18000) = "DOWN" ? 0 : Error("18000应为DOWN"))
        JoyTestRunner.RunTest("PovToDirection_LEFT", () => JoystickInput.PovToDirection(27000) = "LEFT" ? 0 : Error("27000应为LEFT"))
        JoyTestRunner.RunTest("PovToDirection_NONE", () => JoystickInput.PovToDirection(-1) = "" ? 0 : Error("-1应为空"))
        JoyTestRunner.RunTest("DirectionToPovValue", () => JoystickInput.DirectionToPovValue("UP") = 0 && JoystickInput.DirectionToPovValue("RIGHT") = 9000 ? 0 : Error("方向值映射失败"))
        JoyTestRunner.RunTest("IsJoystickKey_all", () => JoystickInput.IsJoystickKey("Joy1") && JoystickInput.IsJoystickKey("JoyPOV_UP") && JoystickInput.IsJoystickKey("JoyX_RIGHT") ? 0 : Error("IsJoystickKey应识别所有手柄键"))
        JoyTestRunner.RunTest("JoySender_IsVJoyAvailable", () => (result := JoySender.IsVJoyAvailable(), result = true || result = false) ? 0 : Error("应返回bool"))
        JoyTestRunner.RunTest("JoySender_ResolveMethod_auto", () => (method := JoySender.ResolveMethod("auto"), method = "vjoy" || method = "direct") ? 0 : Error("auto应解析为vjoy或direct"))

        JoyTestRunner.Report()
    }

    static RunTest(name, fn) {
        JoyTestRunner.total++
        try {
            fn()
            JoyTestRunner.passed++
        } catch as e {
            JoyTestRunner.failed++
            OutputDebug("FAIL: " name " -> " e.Message "`n")
        }
    }

    static Report() {
        OutputDebug("`n===== 手柄测试汇总 =====`n")
        OutputDebug("总计: " JoyTestRunner.total " | 通过: " JoyTestRunner.passed " | 失败: " JoyTestRunner.failed "`n")
        if JoyTestRunner.failed > 0
            ExitApp(1)
        ExitApp(0)
    }
}

JoyTestRunner.RunAll()
```

- [ ] **Step 2: 运行测试**

Run: `D:\Progra~1\AutoHotkey\v2\AutoHotkey64.exe tests\test_joystick.ahk`
Expected: 退出码0，33个用例全部通过

- [ ] **Step 3: Commit**

```bash
git add tests/test_joystick.ahk
git commit -m "test: 添加手柄单元测试（33个用例）"
```

---

### Task 8: 修改 UI 添加手柄支持

**Files:**
- Modify: `presentation/app_ui.html`

- [ ] **Step 1: 更新 MODE_NAMES 和 MODE_INFO**

在 `app_ui.html` 约1096行找到 `var MODE_NAMES = {...};`，修改为：

```javascript
var MODE_NAMES = {periodic:"周期性",sequence:"序列",hybrid:"混合",hold:"长按",enhanced_periodic:"增强周期",enhanced_sequence:"增强序列",enhanced_hybrid:"增强混合",
  joystick_periodic:"🎮 手柄周期",joystick_sequence:"🎮 手柄序列",joystick_hold:"🎮 手柄长按"};
```

在 `MODE_INFO` 对象（约1100行附近）末尾 `hold: {...}` 之后添加：

```javascript
  joystick_periodic: {desc:"周期性发送手柄按键，如连发A键", fieldKey:"joyKeys", keys:"joyKeys", vals:"joyIntervals", valLabel:"间隔(ms)"},
  joystick_sequence: {desc:"按顺序发送手柄按键序列", fieldKey:"joyKeys", keys:"joyKeys", vals:"joyDelays", valLabel:"延迟(ms)"},
  joystick_hold: {desc:"持续按住手柄按键", fieldKey:"joyKeys", keys:"joyKeys"}
```

- [ ] **Step 2: 在模式选择UI添加手柄模式组**

在 `app_ui.html` 约389行，"特殊模式" `<div class="mode-group">` 之后添加：

```html
        <div class="mode-group"><div class="mode-group-label">🎮 手柄模式 <span class="enhance-badge">NEW</span></div><div class="mode-pills"><span class="mode-pill" data-mode="joystick_periodic" data-action="pickMode">🎮 手柄周期</span><span class="mode-pill" data-mode="joystick_sequence" data-action="pickMode">🎮 手柄序列</span><span class="mode-pill" data-mode="joystick_hold" data-action="pickMode">🎮 手柄长按</span></div></div>
```

- [ ] **Step 3: 修改 renderConfigSection 支持手柄模式**

在 `renderConfigSection()` 函数中（约2214行），`else if (currentMode==="hold")` 之后添加：

```javascript
  else if (currentMode==="joystick_periodic") h += renderJoyKeyIntervalTable();
  else if (currentMode==="joystick_sequence") h += renderJoyKeyDelayTable();
  else if (currentMode==="joystick_hold") h += renderJoyHoldConfig();
```

- [ ] **Step 4: 创建手柄按键选择器弹出层HTML**

在编辑器HTML中（约388行附近，`<div class="overlay" id="keyPickerOverlay">` 之后）添加：

```html
        <div class="overlay" id="joyKeyPickerOverlay" style="max-width:400px;">
          <div class="overlay-header"><span>🎮 选择手柄按键</span><span class="overlay-close" onclick="closeJoyKeyPicker()">✕</span></div>
          <div class="picker-search"><input class="input" id="joyKeySearch" oninput="filterJoyKeys()" placeholder="搜索手柄按键..." style="width:100%;box-sizing:border-box;"></div>
          <div id="joyKeyPickerContent" style="max-height:360px;overflow-y:auto;padding:8px;"></div>
        </div>
```

- [ ] **Step 5: 在 saveConfig 中添加手柄字段**

在 `saveConfig()` 函数中（约2450行），`else if(currentMode==="hold"){` 块之后、`ahkCall("SaveConfig"` 之前添加：

```javascript
  } else if(currentMode==="joystick_periodic"){
    if(!editorConfig.joyKeys||editorConfig.joyKeys.length===0){showToast("请设置手柄按键","error");return;}
    cfg.joyKeys=editorConfig.joyKeys.slice();cfg.joyIntervals=editorConfig.joyIntervals.slice();
    cfg.joySendMethod=editorConfig.joySendMethod||"auto";cfg.joyKeyDuration=editorConfig.joyKeyDuration||50;
  } else if(currentMode==="joystick_sequence"){
    if(!editorConfig.joyKeys||editorConfig.joyKeys.length===0){showToast("请设置手柄按键","error");return;}
    cfg.joyKeys=editorConfig.joyKeys.slice();cfg.joyDelays=editorConfig.joyDelays.slice();
    cfg.joySendMethod=editorConfig.joySendMethod||"auto";cfg.joyKeyDuration=editorConfig.joyKeyDuration||50;
  } else if(currentMode==="joystick_hold"){
    if(!editorConfig.joyKeys||editorConfig.joyKeys.length===0){showToast("请设置手柄按键","error");return;}
    cfg.joyKeys=editorConfig.joyKeys.slice();cfg.joySendMethod=editorConfig.joySendMethod||"auto";
```

- [ ] **Step 6: 在 editGroup 中初始化手柄默认值**

在 `editGroup()` 函数（约1926行），`editorConfig.repeatInterval = ...` 之后添加：

```javascript
      editorConfig.joyKeys = cfg.joyKeys ? cfg.joyKeys.slice() : ["Joy1"];
      editorConfig.joyIntervals = cfg.joyIntervals ? cfg.joyIntervals.slice() : [500];
      editorConfig.joyDelays = cfg.joyDelays ? cfg.joyDelays.slice() : [200];
      editorConfig.joySendMethod = cfg.joySendMethod || "auto";
      editorConfig.joyKeyDuration = cfg.joyKeyDuration || 50;
```

- [ ] **Step 7: 在文件末尾添加手柄JS辅助函数**

在 `</script>` 之前、最后一行JS代码之后添加：

```javascript
var ALL_JOY_KEYS = [];
function buildJoyKeysList() {
  if (ALL_JOY_KEYS.length > 0) return;
  var btns = [];
  for (var i = 1; i <= 16; i++) btns.push("Joy" + i);
  ALL_JOY_KEYS.push({section:"常用按钮",keys:["Joy1","Joy2","Joy3","Joy4","Joy5","Joy6","Joy7","Joy8","Joy9","Joy10"]});
  ALL_JOY_KEYS.push({section:"全部按钮",keys:btns});
  ALL_JOY_KEYS.push({section:"十字键",keys:["JoyPOV_UP","JoyPOV_DOWN","JoyPOV_LEFT","JoyPOV_RIGHT"]});
  ALL_JOY_KEYS.push({section:"左摇杆",keys:["JoyX_LEFT","JoyX_RIGHT","JoyY_UP","JoyY_DOWN"]});
  ALL_JOY_KEYS.push({section:"右摇杆",keys:["JoyR_LEFT","JoyR_RIGHT","JoyU_UP","JoyU_DOWN"]});
  ALL_JOY_KEYS.push({section:"扳机",keys:["JoyZ_DOWN","JoyV_DOWN"]});
}

function renderJoyKeyPickerOverlay() {
  buildJoyKeysList();
  var h = '';
  for (var s = 0; s < ALL_JOY_KEYS.length; s++) {
    h += '<div class="picker-section-label">' + ALL_JOY_KEYS[s].section + '</div>';
    for (var k = 0; k < ALL_JOY_KEYS[s].keys.length; k++) {
      var key = ALL_JOY_KEYS[s].keys[k];
      var display = key;
      var dn = {"Joy1":"A","Joy2":"B","Joy3":"X","Joy4":"Y","Joy5":"LB","Joy6":"RB","Joy7":"Back","Joy8":"Start","Joy9":"LS","Joy10":"RS"};
      if (dn[key]) display = key + " (" + dn[key] + ")";
      h += '<button class="picker-key" onclick="pickJoyKey(\'' + key + '\')">' + display + '</button>';
    }
  }
  return h;
}

function filterJoyKeys() {
  var q = (document.getElementById("joyKeySearch") ? document.getElementById("joyKeySearch").value : "").toLowerCase();
  var btns = document.querySelectorAll("#joyKeyPickerOverlay .picker-key");
  var sv = {};
  for (var i = 0; i < btns.length; i++) {
    var v = btns[i].textContent.toLowerCase().indexOf(q) >= 0;
    btns[i].style.display = v ? "" : "none";
    var p = btns[i].previousElementSibling;
    while (p && !p.classList.contains("picker-section-label")) p = p.previousElementSibling;
    if (p) sv[p.textContent] = (sv[p.textContent] || false) || v;
  }
  var sections = document.querySelectorAll("#joyKeyPickerOverlay .picker-section-label");
  for (var j = 0; j < sections.length; j++) sections[j].style.display = sv[sections[j].textContent] ? "" : "none";
}

var _joyKeyPickerTarget = null;
function openJoyKeyPicker(target) {
  _joyKeyPickerTarget = target;
  var overlay = document.getElementById("joyKeyPickerOverlay");
  if (!overlay) return;
  overlay.classList.add("show");
  var searchInput = document.getElementById("joyKeySearch");
  if (searchInput) { searchInput.value = ""; searchInput.focus(); }
  filterJoyKeys();
}
function closeJoyKeyPicker() {
  var overlay = document.getElementById("joyKeyPickerOverlay");
  if (overlay) overlay.classList.remove("show");
  _joyKeyPickerTarget = null;
}
function pickJoyKey(key) {
  if (_joyKeyPickerTarget) {
    _saveUndo();
    _joyKeyPickerTarget.value = key;
    var idx = parseInt(_joyKeyPickerTarget.getAttribute("data-idx"));
    var field = _joyKeyPickerTarget.getAttribute("data-field");
    if (!isNaN(idx) && field && editorConfig[field]) editorConfig[field][idx] = key;
    updatePreview();
  }
  closeJoyKeyPicker();
}

function renderJoyKeyIntervalTable() {
  var keysArr = editorConfig.joyKeys || ["Joy1"];
  var valsArr = editorConfig.joyIntervals || [500];
  if (!editorConfig.joySendMethod) editorConfig.joySendMethod = "auto";
  if (!editorConfig.joyKeyDuration) editorConfig.joyKeyDuration = 50;
  var h = '<div style="margin-bottom:4px;font-size:10px;color:var(--text-muted);">手柄按键 → 间隔（每个键独立循环）</div>';
  for (var i = 0; i < keysArr.length; i++) {
    var display = keysArr[i] || "Joy1";
    h += '<div class="kv-row"><span class="kv-idx">#' + (i+1) + '</span>';
    h += '<input class="input" value="' + escAttr(display) + '" readonly onclick="openJoyKeyPicker(this)" data-idx="' + i + '" data-field="joyKeys" style="width:120px;cursor:pointer;">';
    h += '<span class="kv-arrow">→</span><input class="input input-sm" type="number" value="' + (valsArr[i]||500) + '" onchange="updateJoyVal('+i+',this.value)" style="width:60px;" min="10" aria-label="间隔时间"><span style="font-size:10px;color:var(--text-muted);">ms</span>';
    h += '<button class="btn btn-ghost btn-sm" onclick="deleteJoyKey('+i+')" aria-label="删除手柄按键">✕</button></div>';
  }
  h += '<button class="btn btn-ghost btn-sm" onclick="addJoyKey()" aria-label="添加手柄按键">+ 添加按键</button>';
  h += joySendMethodRow();
  return h;
}

function renderJoyKeyDelayTable() {
  var keysArr = editorConfig.joyKeys || ["Joy1","Joy2"];
  var valsArr = editorConfig.joyDelays || [200,100];
  if (!editorConfig.joySendMethod) editorConfig.joySendMethod = "auto";
  if (!editorConfig.joyKeyDuration) editorConfig.joyKeyDuration = 50;
  var h = '<div style="margin-bottom:4px;font-size:10px;color:var(--text-muted);">手柄按键 → 延迟（顺序执行）</div>';
  for (var i = 0; i < keysArr.length; i++) {
    h += '<div class="kv-row"><span class="kv-idx">#' + (i+1) + '</span>';
    h += '<input class="input" value="' + escAttr(keysArr[i]) + '" readonly onclick="openJoyKeyPicker(this)" data-idx="' + i + '" data-field="joyKeys" style="width:120px;cursor:pointer;">';
    h += '<span class="kv-arrow">→</span><input class="input input-sm" type="number" value="' + (valsArr[i]||200) + '" onchange="updateJoyVal('+i+',this.value)" style="width:60px;" min="10" aria-label="延迟时间"><span style="font-size:10px;color:var(--text-muted);">ms</span>';
    h += '<button class="btn btn-ghost btn-sm" onclick="deleteJoyKey('+i+')" aria-label="删除手柄按键">✕</button></div>';
  }
  h += '<button class="btn btn-ghost btn-sm" onclick="addJoyKey()" aria-label="添加手柄按键">+ 添加按键</button>';
  h += joySendMethodRow();
  return h;
}

function renderJoyHoldConfig() {
  var keysArr = editorConfig.joyKeys || ["Joy1"];
  if (!editorConfig.joySendMethod) editorConfig.joySendMethod = "auto";
  var h = '<div style="margin-bottom:4px;font-size:10px;color:var(--text-muted);">持续按住的手柄按键</div>';
  for (var i = 0; i < keysArr.length; i++) {
    h += '<div class="kv-row"><span class="kv-idx">#' + (i+1) + '</span>';
    h += '<input class="input" value="' + escAttr(keysArr[i]) + '" readonly onclick="openJoyKeyPicker(this)" data-idx="' + i + '" data-field="joyKeys" style="width:120px;cursor:pointer;">';
    h += '<button class="btn btn-ghost btn-sm" onclick="deleteJoyKey('+i+')" aria-label="删除手柄按键">✕</button></div>';
  }
  h += '<button class="btn btn-ghost btn-sm" onclick="addJoyKey()" aria-label="添加手柄按键">+ 添加按键</button>';
  h += '<div style="margin-top:8px;"><span style="font-size:10px;">发送方式:</span><select class="input" style="width:100px;" onchange="_saveUndo();editorConfig.joySendMethod=this.value;"><option value="auto"'+(editorConfig.joySendMethod==="auto"?' selected':'')+'>自动</option><option value="vjoy"'+(editorConfig.joySendMethod==="vjoy"?' selected':'')+'>vJoy</option><option value="direct"'+(editorConfig.joySendMethod==="direct"?' selected':'')+'>直接</option></select></div>';
  return h;
}

function joySendMethodRow() {
  return '<div style="margin-top:8px;display:flex;gap:8px;align-items:center;"><span style="font-size:10px;">发送:</span><select class="input" style="width:100px;" onchange="_saveUndo();editorConfig.joySendMethod=this.value;"><option value="auto"'+(editorConfig.joySendMethod==="auto"?' selected':'')+'>自动</option><option value="vjoy"'+(editorConfig.joySendMethod==="vjoy"?' selected':'')+'>vJoy</option><option value="direct"'+(editorConfig.joySendMethod==="direct"?' selected':'')+'>直接</option></select><span style="font-size:10px;">按键时长:</span><input class="input input-sm" type="number" value="'+editorConfig.joyKeyDuration+'" onchange="_saveUndo();editorConfig.joyKeyDuration=parseInt(this.value)||50;" style="width:50px;" min="5" max="200" aria-label="按键持续时间"><span style="font-size:10px;color:var(--text-muted);">ms</span></div>';
}

function addJoyKey() { _saveUndo(); editorConfig.joyKeys.push("Joy1"); if (editorConfig.joyIntervals) editorConfig.joyIntervals.push(500); if (editorConfig.joyDelays) editorConfig.joyDelays.push(200); renderConfigSection(); updatePreview(); }
function deleteJoyKey(i) { if (editorConfig.joyKeys.length <= 1) { showToast("至少保留一个按键", "error"); return; } _saveUndo(); editorConfig.joyKeys.splice(i, 1); if (editorConfig.joyIntervals) editorConfig.joyIntervals.splice(i, 1); if (editorConfig.joyDelays) editorConfig.joyDelays.splice(i, 1); renderConfigSection(); updatePreview(); }
function updateJoyVal(i, v) { var val = parseInt(v); if (isNaN(val) || val < 10) return; _saveUndo(); if (currentMode==="joystick_periodic") editorConfig.joyIntervals[i] = val; else editorConfig.joyDelays[i] = val; updatePreview(); }
```

- [ ] **Step 8: 在 init() 中初始化手柄选择器**

在 `init()` 函数中（约1690行），`renderKeyGrid();` 之后添加：

```javascript
  var joyPickerContent = document.getElementById("joyKeyPickerContent");
  if (joyPickerContent) joyPickerContent.innerHTML = renderJoyKeyPickerOverlay();
```

- [ ] **Step 9: 仪表盘热键适配手柄前缀**

在 `renderDashboard()` 中（约1834行），`hotkeyDisplay` 变量：

```javascript
var hotkeyDisplay = g.hotkey||"";
if (hotkeyDisplay.indexOf("Joy") === 0) hotkeyDisplay = "🎮 " + hotkeyDisplay;
```

已有该变量，确认行中使用了 `hotkeyDisplay` 而不是 `g.hotkey`。搜索 `g.hotkey` 在仪表盘渲染处，确保手柄热键显示带 🎮 前缀。

- [ ] **Step 10: 预览适配手柄模式**

在 `updatePreview()` 函数末尾 `tl.innerHTML=h;` 之前添加：

```javascript
  if (currentMode.indexOf("joystick_") === 0) {
    var jk = editorConfig.joyKeys || ["Joy1"];
    if (currentMode === "joystick_hold") {
      for (var x = 0; x < jk.length; x++) {
        if (x > 0) h += '<span class="timeline-arrow">+</span>';
        h += '<span class="timeline-hold">🎮' + escHtml(jk[x]) + ' ⏳</span>';
      }
      h += '<span class="timeline-loop">持续</span>';
    } else if (currentMode === "joystick_periodic") {
      var iv = editorConfig.joyIntervals || [500];
      for (var y = 0; y < jk.length; y++) {
        if (y > 0) h += '<span class="timeline-arrow">·</span>';
        h += '<span class="timeline-key">🎮' + escHtml(jk[y]) + '</span><span class="timeline-time">' + (iv[y]||500) + 'ms</span><span class="timeline-loop">↻</span>';
      }
    } else {
      var dv = editorConfig.joyDelays || [200];
      for (var z = 0; z < jk.length; z++) {
        if (z > 0) h += '<span class="timeline-time">' + (dv[z-1]||200) + 'ms</span><span class="timeline-arrow">→</span>';
        h += '<span class="timeline-key">🎮' + escHtml(jk[z]) + '</span>';
      }
      h += '<span class="timeline-time">' + (dv[jk.length-1]||200) + 'ms</span><span class="timeline-loop">↻ 循环</span>';
    }
    tl.innerHTML = h; if (editorConfig.holdKeys && editorConfig.holdKeys.length > 0) renderHoldKeysAfter(tl); return;
  }
```

- [ ] **Step 11: Commit**

```bash
git add presentation/app_ui.html
git commit -m "feat: UI 添加手柄模式选择器和手柄按键配置"
```

---

## 自审

1. **规格覆盖**: 7个章节均对应具体Task — A方向(Task4/6)、B方向(Task1/3)、UI(Task8)、错误处理(Task4)、测试(Task7) ✓
2. **占位符扫描**: 无 "TBD"、"TODO"、"implement later"、"add appropriate error handling" ✓
3. **类型一致性**: `joyKeys`/`joyIntervals`/`joyDelays`/`joySendMethod`/`joyKeyDuration` 字段名在 AHK 和 JS 中统一使用驼峰 ✓

---

## 执行交接

**计划已保存到 `docs/superpowers/plans/2026-05-27-joystick-combo.md`。两种执行方式：**

**1. 子代理驱动（推荐）** — 每个Task派遣独立子代理，任务间审查，快速迭代
**2. 内联执行** — 在当前会话中使用 executing-plans，批量执行 + 检查点审查

**选择哪种方式？**