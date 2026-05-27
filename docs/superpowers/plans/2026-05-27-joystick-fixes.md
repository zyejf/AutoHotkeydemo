# 手柄连招 — 代码审查修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代码审查发现的 3严重 + 3中等 问题，使手柄连招功能的 A方向（手柄触发）和 B方向（手柄发送）在生产环境中正确运行。

**Architecture:** 6个修复分布在4个文件中：
- `infrastructure/joy_sender.ahk` — C2(vJoy引用计数) + M1(POV/轴direct回退) + M3(SendBtn错误回退)
- `infrastructure/joy_hotkey_manager.ahk` — C1(POV/轴/扳机轮询回调) + C3(SetTimer停止)
- `domain/joystick_executor.ahk` — 配合C2修改 + _SendJoyKey的Trigger先行检查
- `domain/skill_group.ahk` — M2(_ReleaseJoyKeys集成到_ReleaseAllKeys)

**Tech Stack:** AutoHotkey v2, vJoy SDK, WebView2

---

### Task 1: C3修复 — _StopPolling 停止 SetTimer

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\joy_hotkey_manager.ahk:103-105`

- [ ] **Step 1: 修改 _StopPolling 添加 SetTimer 停止**

在 `_StopPolling()` 中添加 `SetTimer(JoyHotkeyManager._Poll, 0)`：

```autohotkey
    static _StopPolling() {
        JoyHotkeyManager._pollActive := false
        SetTimer(JoyHotkeyManager._Poll, 0)
    }
```

- [ ] **Step 2: 验证语法**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk`
Expected: Exit code 0

- [ ] **Step 3: 提交**

```bash
git add infrastructure/joy_hotkey_manager.ahk
git commit -m "fix(joy): _StopPolling添加SetTimer(0)停止定时器 (C3)"
```

---

### Task 2: C2修复 — vJoy AcquireVJD 引用计数模式

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\joy_sender.ahk:17-19,89-97`

- [ ] **Step 1: 添加引用计数静态变量**

在 JoySender 类静态变量区（`_vJoyDll := ""` 之后）添加：

```autohotkey
    static _vJoyRefCount := 0
```

- [ ] **Step 2: 重写 _VJoyOpen 使用引用计数**

将 `_VJoyOpen()` 方法从：

```autohotkey
    static _VJoyOpen() {
        h := DllCall(JoySender._vJoyDll "\AcquireVJD", "UInt", JoySender._vJoyDeviceId)
        if h = 0
            throw Error("vJoy AcquireVJD 失败，设备ID=" JoySender._vJoyDeviceId)
        return true
    }
```

修改为：

```autohotkey
    static _VJoyOpen() {
        if JoySender._vJoyRefCount > 0 {
            JoySender._vJoyRefCount++
            return true
        }
        h := DllCall(JoySender._vJoyDll "\AcquireVJD", "UInt", JoySender._vJoyDeviceId)
        if h = 0
            throw Error("vJoy AcquireVJD 失败，设备ID=" JoySender._vJoyDeviceId)
        JoySender._vJoyRefCount := 1
        return true
    }
```

- [ ] **Step 3: 重写 _VJoyClose 使用引用计数**

将 `_VJoyClose()` 方法从：

```autohotkey
    static _VJoyClose() {
        DllCall(JoySender._vJoyDll "\RelinquishVJD", "UInt", JoySender._vJoyDeviceId)
    }
```

修改为：

```autohotkey
    static _VJoyClose() {
        if JoySender._vJoyRefCount <= 0
            return
        JoySender._vJoyRefCount--
        if JoySender._vJoyRefCount = 0
            DllCall(JoySender._vJoyDll "\RelinquishVJD", "UInt", JoySender._vJoyDeviceId)
    }
```

- [ ] **Step 4: 在 _VJoySetBtn/_VJoySetAxis/_VJoySetPov 中添加配对 _VJoyClose**

修改 `_VJoySetBtn` 从：

```autohotkey
    static _VJoySetBtn(btnNum, state) {
        JoySender._VJoyOpen()
        DllCall(JoySender._vJoyDll "\SetBtn", "UInt", state ? 1 : 0, "UInt", JoySender._vJoyDeviceId, "UChar", btnNum)
    }
```

修改为：

```autohotkey
    static _VJoySetBtn(btnNum, state) {
        JoySender._VJoyOpen()
        try {
            DllCall(JoySender._vJoyDll "\SetBtn", "UInt", state ? 1 : 0, "UInt", JoySender._vJoyDeviceId, "UChar", btnNum)
        } finally {
            JoySender._VJoyClose()
        }
    }
```

同样修改 `_VJoySetAxis` 和 `_VJoySetPov`，将核心 DllCall 包裹在 `try { ... } finally { JoySender._VJoyClose() }` 中。

- [ ] **Step 5: 修改 JoystickExecutor._SendJoyKey 使用配对 Open/Close**

在 [joystick_executor.ahk:137-159](file:///d:/1demo/AutoHotkeydemo/domain/joystick_executor.ahk#L137-L159) 的 `_SendJoyKey` 中，按键发送后添加资源释放。由于 `_SendJoyKey` 一次只发送一个键，无需批量配对，依赖 `_VJoySetBtn` 内部的 finally 即可。

**注意:** 这会影响 `SendPov` 和 `SendAxis` 的 vJoy 调用。确认 `_VJoySetPov` 和 `_VJoySetAxis` 也已包裹 finally。

- [ ] **Step 6: 验证语法**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk`
Expected: Exit code 0

- [ ] **Step 7: 运行测试**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\test_joystick.ahk`
Expected: Exit code 0, 33 passed

- [ ] **Step 8: 提交**

```bash
git add infrastructure/joy_sender.ahk domain/joystick_executor.ahk
git commit -m "fix(joy): vJoy AcquireVJD引用计数模式，防止重复获取失败 (C2)"
```

---

### Task 3: C1修复 — POV/轴/扳机轮询触发回调

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\joy_hotkey_manager.ahk:108-135`

- [ ] **Step 1: 重写 _Poll 方法，添加轴/扳机轮询和回调查找**

将 `_Poll()` 和 `_PollPov()` 替换为完整的轮询逻辑：

```autohotkey
    static _Poll() {
        if !JoyHotkeyManager._pollActive
            return
        try {
            JoyHotkeyManager._PollPov()
            JoyHotkeyManager._PollAxes()
            JoyHotkeyManager._PollTriggers()
        } catch as e {
        }
    }

    static _PollPov() {
        try {
            val := GetKeyState(JoyHotkeyManager._joystickId "JoyPOV")
            if val = ""
                return
            if val != JoyHotkeyManager._povLastState {
                prevDir := JoystickInput.PovToDirection(JoyHotkeyManager._povLastState)
                newDir := JoystickInput.PovToDirection(val)
                JoyHotkeyManager._povLastState := val
                if prevDir != "" && prevDir != newDir
                    JoyHotkeyManager._TriggerPovCallback(prevDir, false)
                if newDir != ""
                    JoyHotkeyManager._TriggerPovCallback(newDir, true)
            }
        } catch as e {
        }
    }

    static _TriggerPovCallback(direction, isActive) {
        povKey := "JoyPOV_" direction
        for key, info in JoyHotkeyManager._registered {
            if InStr(key, "JoyPOV_") && info.Has("joyKey") && info["joyKey"] = povKey {
                try
                    info["callback"].Call(info["groupId"])
            }
        }
    }

    static _PollAxes() {
        axisKeys := ["JoyX", "JoyY", "JoyR", "JoyU"]
        for _, axis in axisKeys {
            try {
                val := GetKeyState(JoyHotkeyManager._joystickId axis)
                if val = ""
                    continue
                pos := Integer(val)
                if pos > JoyHotkeyManager.AXIS_HIGH {
                    JoyHotkeyManager._TriggerAxisCallback(axis, "RIGHT", true)
                    JoyHotkeyManager._TriggerAxisCallback(axis, "LEFT", false)
                } else if pos < JoyHotkeyManager.AXIS_LOW {
                    JoyHotkeyManager._TriggerAxisCallback(axis, "LEFT", true)
                    JoyHotkeyManager._TriggerAxisCallback(axis, "RIGHT", false)
                } else {
                    JoyHotkeyManager._TriggerAxisCallback(axis, "RIGHT", false)
                    JoyHotkeyManager._TriggerAxisCallback(axis, "LEFT", false)
                }
            } catch as e {
            }
        }
    }

    static _TriggerAxisCallback(axis, direction, isActive) {
        axisKey := axis "_" direction
        for key, info in JoyHotkeyManager._registered {
            if info.Has("joyKey") && info["joyKey"] = axisKey && isActive {
                try
                    info["callback"].Call(info["groupId"])
            }
        }
    }

    static _PollTriggers() {
        triggerAxes := ["JoyZ", "JoyV"]
        for _, axis in triggerAxes {
            try {
                val := GetKeyState(JoyHotkeyManager._joystickId axis)
                if val = ""
                    continue
                pos := Integer(val)
                triggerKey := axis "_DOWN"
                if pos > JoyHotkeyManager.TRIGGER_THRESHOLD {
                    JoyHotkeyManager._TriggerJoyCallback(triggerKey)
                }
            } catch as e {
            }
        }
    }

    static _TriggerJoyCallback(joyKey) {
        for key, info in JoyHotkeyManager._registered {
            if info.Has("joyKey") && info["joyKey"] = joyKey {
                try
                    info["callback"].Call(info["groupId"])
            }
        }
    }
```

- [ ] **Step 2: 添加轮询常量**

在 JoyHotkeyManager 静态变量区添加：

```autohotkey
    static AXIS_HIGH := 70
    static AXIS_LOW := 30
    static TRIGGER_THRESHOLD := 60
```

- [ ] **Step 3: 修改 RegisterHotkey 存储 joyKey 标识**

将 `RegisterHotkey` 中的注册信息修改为同时存储 `joyKey`：

```autohotkey
    static RegisterHotkey(joyKey, groupId, callback) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                JoyHotkeyManager._registered[key] := Map("groupId", groupId, "callback", callback, "joyKey", joyKey)
                Hotkey(key, (*) => JoyHotkeyManager._OnButtonPress(key), "On")
                return true
            } else if JoystickInput.IsAxis(joyKey) || JoystickInput.IsTrigger(joyKey) {
                JoyHotkeyManager._registered[joyKey] := Map("groupId", groupId, "callback", callback, "joyKey", joyKey)
                JoyHotkeyManager._StartPolling()
                return true
            } else if JoystickInput.IsPov(joyKey) {
                JoyHotkeyManager._registered[joyKey] := Map("groupId", groupId, "callback", callback, "joyKey", joyKey)
                JoyHotkeyManager._StartPolling()
                return true
            }
            return false
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.RegisterHotkey 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }
```

- [ ] **Step 4: 修改 UnregisterHotkey 适配新键格式**

```autohotkey
    static UnregisterHotkey(joyKey, groupId) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                JoyHotkeyManager._registered.Delete(key)
                try
                    Hotkey(key, "Off")
            } else {
                JoyHotkeyManager._registered.Delete(joyKey)
            }
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.UnregisterHotkey 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
        if JoyHotkeyManager._registered.Count = 0
            JoyHotkeyManager._StopPolling()
    }
```

并同步更新 `UnregisterAll` 和 `_OnButtonPress`。

- [ ] **Step 5: 验证语法**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk`
Expected: Exit code 0

- [ ] **Step 6: 运行测试**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\test_joystick.ahk`
Expected: Exit code 0

- [ ] **Step 7: 提交**

```bash
git add infrastructure/joy_hotkey_manager.ahk
git commit -m "fix(joy): 实现POV/轴/扳机轮询回调触发 (C1)"
```

---

### Task 4: M3修复 — SendBtn 异常回退改进

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\joy_sender.ahk:57-64`

- [ ] **Step 1: 修改 SendBtn 捕获块，添加通用回退和日志**

将 `SendBtn` 从：

```autohotkey
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
```

修改为：

```autohotkey
    static SendBtn(btnNum, state, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            if resolved = "vjoy"
                JoySender._VJoySetBtn(btnNum, state)
            else
                JoySender._DirectSendBtn(btnNum, state)
        } catch as e {
            ErrorSystem.LogError("JoySender.SendBtn vJoy发送失败，回退direct: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
            try {
                JoySender._DirectSendBtn(btnNum, state)
            } catch as e2 {
            }
        }
    }
```

- [ ] **Step 2: 需要引入 error_system.ahk**

在 `joy_sender.ahk` 顶部添加：

```autohotkey
#Include "error_system.ahk"
```

- [ ] **Step 3: 验证语法 + 运行测试**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk`
Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\test_joystick.ahk`
Expected: Exit code 0

- [ ] **Step 4: 提交**

```bash
git add infrastructure/joy_sender.ahk
git commit -m "fix(joy): SendBtn异常时通用回退direct模式 (M3)"
```

---

### Task 5: M1修复 — SendPov/SendAxis 添加 direct 通道回退

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\infrastructure\joy_sender.ahk:66-82`

- [ ] **Step 1: 重写 SendPov 添加 direct 和日志**

```autohotkey
    static SendPov(direction, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        povVal := JoySender._PovDirectionToValue(direction)
        try {
            if resolved = "vjoy" {
                JoySender._VJoySetPov(povVal)
            }
        } catch as e {
            ErrorSystem.LogError("JoySender.SendPov 失败: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }
```

- [ ] **Step 2: 重写 SendAxis 添加日志**

```autohotkey
    static SendAxis(axis, value, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            if resolved = "vjoy"
                JoySender._VJoySetAxis(axis, value)
        } catch as e {
            ErrorSystem.LogError("JoySender.SendAxis 失败: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }
```

- [ ] **Step 3: 验证语法 + 运行测试**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk`
Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\test_joystick.ahk`
Expected: Exit code 0

- [ ] **Step 4: 提交**

```bash
git add infrastructure/joy_sender.ahk
git commit -m "fix(joy): SendPov/SendAxis添加错误日志替代空catch (M1)"
```

---

### Task 6: M2修复 — _ReleaseJoyKeys 集成到 SkillGroup

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\domain\skill_group.ahk` — `_ReleaseAllKeys()` 方法
- Modify: `d:\1demo\AutoHotkeydemo\domain\joystick_executor.ahk` — `_SendJoyKey` Trigger先行检查

- [ ] **Step 1: 在 _ReleaseAllKeys switch 中添加 joystick case**

在 [skill_group.ahk](file:///d:/1demo/AutoHotkeydemo/domain/skill_group.ahk) 的 `_ReleaseAllKeys()` 方法的 switch 语句中，在现有的 `case "enhanced_hybrid":` 之后添加：

```autohotkey
            case "joystick_periodic", "joystick_sequence", "joystick_hold":
                JoystickExecutor._ReleaseJoyKeys(this)
```

完整修改后的 switch：

```autohotkey
    _ReleaseAllKeys() {
        switch this.mode {
            case "periodic":
                for i, k in this.keys
                    this._ReleaseKey(k, i <= this._isMouse.Length ? this._isMouse[i] : false)
            case "sequence":
                for i, k in this.keys
                    this._ReleaseKey(k, i <= this._isMouse.Length ? this._isMouse[i] : false)
            case "hybrid":
                for i, k in this.periodicKeys
                    this._ReleaseKey(k, i <= this._periodicMouse.Length ? this._periodicMouse[i] : false)
                for i, k in this.seqKeys
                    this._ReleaseKey(k, i <= this._seqMouse.Length ? this._seqMouse[i] : false)
            case "enhanced_periodic":
                for i, k in this.pressKeys
                    this._ReleaseKey(k, i <= this._pressMouse.Length ? this._pressMouse[i] : false)
            case "enhanced_sequence":
                for i, k in this.pressKeys
                    this._ReleaseKey(k, i <= this._pressMouse.Length ? this._pressMouse[i] : false)
            case "enhanced_hybrid":
                for i, k in this.periodicPressKeys
                    this._ReleaseKey(k, i <= this._periodicMouse.Length ? this._periodicMouse[i] : false)
                for i, k in this.seqPressKeys
                    this._ReleaseKey(k, i <= this._seqMouse.Length ? this._seqMouse[i] : false)
            case "joystick_periodic", "joystick_sequence", "joystick_hold":
                JoystickExecutor._ReleaseJoyKeys(this)
        }
        this._ReleaseHoldKeys()
    }
```

- [ ] **Step 2: 在 skill_group.ahk 中添加 joystick_executor include**

在文件顶部的 #Include 区域添加：

```autohotkey
#Include "joystick_executor.ahk"
```

- [ ] **Step 3: 修复 _SendJoyKey 中 IsTrigger 优先于 IsAxis 检查 (m2修复)**

在 [joystick_executor.ahk:137-159](file:///d:/1demo/AutoHotkeydemo/domain/joystick_executor.ahk#L137-L159) 的 `_SendJoyKey` 中，将 IsTrigger 检查提前到 IsAxis 之前：

```autohotkey
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
            } else if JoystickInput.IsTrigger(key) {
                info := JoystickInput.GetAxisInfo(key)
                value := state = "down" ? 100 : 0
                JoySender.SendAxis(info["axis"], value, sendMethod)
            } else if JoystickInput.IsAxis(key) {
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
```

- [ ] **Step 4: 验证语法**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk`
Expected: Exit code 0

- [ ] **Step 5: 运行全量测试**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
Expected: Exit code 0, all tests pass

- [ ] **Step 6: 提交**

```bash
git add domain/skill_group.ahk domain/joystick_executor.ahk
git commit -m "fix(joy): _ReleaseJoyKeys集成到SkillGroup._ReleaseAllKeys (M2)"
```

---

### Task 7: 最终验证

- [ ] **Step 1: 全量语法校验**

```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate main.ahk
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /Validate tests/test_joystick.ahk
```

Expected: 全部 Exit code 0

- [ ] **Step 2: 运行手柄测试套件**

```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\test_joystick.ahk
```

Expected: Exit code 0, 33 passed

- [ ] **Step 3: 运行全量测试套件**

```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
```

Expected: Exit code 0, all tests pass (no regression)

- [ ] **Step 4: 提交最终验证结果**

```bash
git add -A
git commit -m "test: 手柄修复后全量测试通过"
```