; =================================================================
; vJoy 操作 - IPC 指令驱动的手柄模拟
; 版本: 1.0
; 说明: 通过 DllCall 调用 vJoy SDK
;       支持 joystick_periodic, joystick_sequence, joystick_hold 模式
;       auto 模式自动检测 vJoy 可用性并降级
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 高精度时钟（QPC）：调度时刻一律用整数微秒，不用 A_TickCount（步进 15.52ms）
; 说明：AHK 的 #Include 按解析路径自动去重，executor.ahk 先 include sender.ahk
; （内部已 include 本文件）不会造成重复定义。
#Include "high_res_clock.ahk"

class Joystick {
    ; 发送原语注入点（默认为空=使用 vJoy / Direct；测试可注入 mock 避免真实按键副作用）
    static _joySendHook := ""

    ; Joystick 按键白名单 - 允许的按键名模式
    static ALLOWED_JOY_KEYS := Map(
        ; 按钮: Joy1 - Joy32 (标准手柄范围)
        "Joy1", true, "Joy2", true, "Joy3", true, "Joy4", true,
        "Joy5", true, "Joy6", true, "Joy7", true, "Joy8", true,
        "Joy9", true, "Joy10", true, "Joy11", true, "Joy12", true,
        "Joy13", true, "Joy14", true, "Joy15", true, "Joy16", true,
        "Joy17", true, "Joy18", true, "Joy19", true, "Joy20", true,
        "Joy21", true, "Joy22", true, "Joy23", true, "Joy24", true,
        "Joy25", true, "Joy26", true, "Joy27", true, "Joy28", true,
        "Joy29", true, "Joy30", true, "Joy31", true, "Joy32", true,
        ; POV 方向
        "JoyPOVUP", true, "JoyPOVDOWN", true, "JoyPOVLEFT", true, "JoyPOVRIGHT", true,
        ; 轴
        "JoyX", true, "JoyY", true, "JoyZ", true, "JoyR", true, "JoyU", true, "JoyV", true
    )

    ; vJoy 可用性: -1=未检测, 0=不可用, 1=可用
    static _vJoyAvailable := -1
    static _vJoyDeviceId := 1
    static _vJoyDll := ""
    static _vJoyRefCount := 0

    ; 活跃的执行组: groupId => 执行状态
    static _activeGroups := Map()

    ; 定时器引用: groupId => timerRef
    static _timers := Map()

    ; 释放定时器引用: groupId => (key => timerRef)，用于停止时取消滞后 up（T6-02）
    static _releaseTimers := Map()

    ; 按住的按键: groupId => [keys]
    static _heldJoyKeys := Map()

    ; =================================================================
    ; 精确定刻常量（与 sender.ahk 同源，规则见 AGENTS.md §高精度定刻规范）
    ; =================================================================

    ; ⚠️ 调度内部一切时刻/间隔一律用「整数微秒」（int µs），不用 A_TickCount。
    ; A_TickCount 步进中位 15.52ms，用它推进基准会把每一步的超时累积进下一步
    ; （实测 sequence delay=100ms 时步进退化成 110.73ms，3 秒累积漂移 +258.6ms）。
    static MIN_INTERVAL_US := 10000

    ; ⚠️ 这里**不设** sender.ahk 那种 TIMING_EPSILON_US 到期容差：本实现没有
    ; SleepUntilUs 把唤醒时刻精修到计划时刻上，「是否到期」的唯一判据就是
    ; 提前返回处的 `target - now > 0`。再加一个容差等于允许提前触发 —— 旧实现的
    ; `threshold := interval - 5%` 就是这么把配置 100ms 变成实测 95.5ms 的。

    ; 取间隔/延时的整数微秒（越界与缺项都回落到默认，下限 10ms）
    static _IntervalUsOf(joyIntervals, i) {
        interval := i <= joyIntervals.Length ? joyIntervals[i] : 50
        intervalUs := Round(interval * 1000)
        return intervalUs < Joystick.MIN_INTERVAL_US ? Joystick.MIN_INTERVAL_US : intervalUs
    }

    static _DelayUsOf(joyDelays, i) {
        delay := i <= joyDelays.Length ? joyDelays[i] : 100
        delayUs := Round(delay * 1000)
        return delayUs < Joystick.MIN_INTERVAL_US ? Joystick.MIN_INTERVAL_US : delayUs
    }

    ; 把「距离下次到期的微秒数」换算成 SetTimer 的毫秒周期。
    ; ⚠️ 必须用 Ceil 而不是 Round —— 理由见 _ExecutePeriodic 第 2 步的注释：
    ;    Round 向下取整会让我们比计划时刻早醒最多 0.5ms，而本实现没有 SleepUntilUs
    ;    兜底，早醒就意味着再排一个 <1ms 的定时器、被抬成 15.625ms 网格，白吃一格。
    ;    实测：Round 的 3 秒累积漂移 +15.1~+17.2ms，Ceil 后降到 +1.9~+10.7ms。
    static _NextPollMs(remainingUs) {
        if remainingUs <= 0
            return 1
        return Ceil(remainingUs / 1000)
    }

    ; =================================================================
    ; 初始化
    ; =================================================================

    static Init() {
        Joystick._DetectVJoy()
        OutputDebug("Joystick: 已初始化 vJoy=" (Joystick._vJoyAvailable = 1 ? "可用" : "不可用"))
    }

    ; =================================================================
    ; 公开方法
    ; =================================================================

    static IsVJoyAvailable() {
        if Joystick._vJoyAvailable = -1
            Joystick._DetectVJoy()
        return Joystick._vJoyAvailable = 1
    }

    ; 启动手柄周期性模式
    static StartPeriodic(groupId, joyKeys, joyIntervals, sendMethod := "auto", keyDuration := 15) {
        ; T6-04 幂等保护：若组已活跃则先彻底停掉旧的（含 vJoy Relinquish + 定时器取消）
        if Joystick._activeGroups.Has(groupId)
            Joystick.StopGroup(groupId)

        resolved := Joystick._ResolveMethod(sendMethod)

        ; T6-07: 组级 vJoy 生命周期 — 组启动时 Acquire 一次
        if resolved = "vjoy" {
            try
                Joystick._VJoyOpen()
            catch as e {
                OutputDebug("Joystick: vJoy Acquire 失败，降级为 direct: " e.Message)
                resolved := "direct"
            }
        }

        Joystick._activeGroups[groupId] := Map(
            "mode", "joystick_periodic",
            "joyKeys", joyKeys,
            "joyIntervals", joyIntervals,
            "sendMethod", resolved,
            "keyDuration", keyDuration,
            "lastTriggerTimes", Map()
        )

        timerFn := () => Joystick._ExecutePeriodic(groupId)
        Joystick._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Joystick: 启动周期性 groupId=" groupId " keys=" joyKeys.Length " method=" resolved)
    }

    ; 启动手柄序列模式
    static StartSequence(groupId, joyKeys, joyDelays, sendMethod := "auto", keyDuration := 15) {
        ; T6-04 幂等保护：若组已活跃则先彻底停掉旧的（含 vJoy Relinquish + 定时器取消）
        if Joystick._activeGroups.Has(groupId)
            Joystick.StopGroup(groupId)

        resolved := Joystick._ResolveMethod(sendMethod)

        ; T6-07: 组级 vJoy 生命周期 — 组启动时 Acquire 一次
        if resolved = "vjoy" {
            try
                Joystick._VJoyOpen()
            catch as e {
                OutputDebug("Joystick: vJoy Acquire 失败，降级为 direct: " e.Message)
                resolved := "direct"
            }
        }

        Joystick._activeGroups[groupId] := Map(
            "mode", "joystick_sequence",
            "joyKeys", joyKeys,
            "joyDelays", joyDelays,
            "sendMethod", resolved,
            "keyDuration", keyDuration,
            "currentStep", 1,
            ; 0 = 未初始化，由 _ExecuteSequence 在**首次执行**时建立基准。
            ; 旧实现在 StartSequence 里就用 A_TickCount 建基准，基准与首次执行之间
            ; 还隔着一次 SetTimer(10)，首步会凭空多等一个网格。
            "nextStepTime", 0
        )

        timerFn := () => Joystick._ExecuteSequence(groupId)
        Joystick._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Joystick: 启动序列 groupId=" groupId " keys=" joyKeys.Length " method=" resolved)
    }

    ; 启动手柄 Hold 模式
    static StartHold(groupId, joyKeys, sendMethod := "auto") {
        ; T6-04 幂等保护：若组已活跃则先彻底停掉旧的（含 vJoy Relinquish + 定时器取消）
        if Joystick._activeGroups.Has(groupId)
            Joystick.StopGroup(groupId)

        resolved := Joystick._ResolveMethod(sendMethod)

        ; T6-07: 组级 vJoy 生命周期 — 组启动时 Acquire 一次
        if resolved = "vjoy" {
            try
                Joystick._VJoyOpen()
            catch as e {
                OutputDebug("Joystick: vJoy Acquire 失败，降级为 direct: " e.Message)
                resolved := "direct"
            }
        }

        Joystick._activeGroups[groupId] := Map(
            "mode", "joystick_hold",
            "joyKeys", joyKeys,
            "sendMethod", resolved
        )

        ; 按住所有按键
        Joystick._heldJoyKeys[groupId] := joyKeys
        for k in joyKeys
            Joystick._SendJoyKey(k, "down", resolved)

        OutputDebug("Joystick: 启动 Hold groupId=" groupId " keys=" joyKeys.Length " method=" resolved)
    }

    ; 停止手柄执行组
    static StopGroup(groupId) {
        if !Joystick._activeGroups.Has(groupId)
            return

        state := Joystick._activeGroups[groupId]

        ; 停止定时器
        if Joystick._timers.Has(groupId) {
            SetTimer(Joystick._timers[groupId], 0)
            Joystick._timers.Delete(groupId)
        }

        ; T6-02: 取消该组的释放定时器，消除停止后滞后 up
        Joystick._CancelReleaseTimers(groupId)

        ; 释放 hold 按键
        if Joystick._heldJoyKeys.Has(groupId) {
            method := state.Has("sendMethod") ? state["sendMethod"] : "auto"
            for k in Joystick._heldJoyKeys[groupId]
                Joystick._SendJoyKey(k, "up", method)
            Joystick._heldJoyKeys.Delete(groupId)
        }

        ; T6-07: 组级 vJoy 生命周期 — 组停止时 Relinquish 一次
        if state.Has("sendMethod") && state["sendMethod"] = "vjoy"
            Joystick._VJoyClose()

        Joystick._activeGroups.Delete(groupId)
        OutputDebug("Joystick: 已停止 groupId=" groupId)
    }

    ; 紧急释放所有手柄按键
    static EmergencyRelease() {
        for groupId, state in Joystick._activeGroups {
            method := state.Has("sendMethod") ? state["sendMethod"] : "auto"
            if state.Has("joyKeys") {
                for k in state["joyKeys"]
                    Joystick._SendJoyKey(k, "up", method)
            }
            if Joystick._timers.Has(groupId) {
                SetTimer(Joystick._timers[groupId], 0)
            }
            ; T6-02: 取消该组的释放定时器
            Joystick._CancelReleaseTimers(groupId)
            ; T6-07: 组级 vJoy 生命周期 — 紧急释放时 Relinquish
            if method = "vjoy"
                Joystick._VJoyClose()
        }
        Joystick._activeGroups := Map()
        Joystick._timers := Map()
        Joystick._releaseTimers := Map()
        Joystick._heldJoyKeys := Map()
        OutputDebug("Joystick: 紧急释放完成")
    }

    ; =================================================================
    ; 执行引擎
    ; =================================================================

    ; 周期性模式：QPC 整数微秒基准 + 保相位推进 + 按计划时刻分桶
    ;
    ; 旧实现的四个缺陷（2026-09-14 实测，见 docs/perf 报告）：
    ;   ① 时间基准用 A_TickCount（步进 15.52ms）；
    ;   ② `threshold := interval - 5%` 允许提前最多 5% 触发 —— 配置 100ms 实测按
    ;      95.46ms 发，实测步进在 93.75 / 112.5 之间三循环抖动（min 92.68, max 111.91）；
    ;   ③ 滞后时 `triggerTimes[i] := now` 把基准重置为当前时刻 —— 既丢相位又吞触发；
    ;      现改为保相位单调推进，跳过的周期计入 droppedTriggers；
    ;   ④ 只要有键触发就 `minRemaining := 1`，等于每 15.6ms 空转轮询一次。
    ;
    ; ⚠️ 已知残留：本实现**不做** SleepUntilUs 忙等，触发时刻仍受 SetTimer 15.625ms
    ;    网格限制（抖动约 ±8ms）。消除它必须占用 AHK 主线程约 8~28ms/次，代价与
    ;    sender.ahk 相当，属独立决策（见 docs/refactor/scheduling-design.md）。
    static _ExecutePeriodic(groupId) {
        if !Joystick._activeGroups.Has(groupId)
            return

        state := Joystick._activeGroups[groupId]
        joyKeys := state["joyKeys"]
        n := joyKeys.Length
        if n = 0
            return
        joyIntervals := state["joyIntervals"]
        sendMethod := state["sendMethod"]
        keyDuration := state["keyDuration"]
        triggerTimes := state["lastTriggerTimes"]

        ; ---- 1. 首次出现的键建立基准，顺带求最近的计划时刻 ----
        now := HighResClock.NowUs()
        target := 0
        i := 1
        while i <= n {
            if !triggerTimes.Has(i)
                triggerTimes[i] := now
            t := triggerTimes[i] + Joystick._IntervalUsOf(joyIntervals, i)
            if target = 0 || t < target
                target := t
            i++
        }

        ; ---- 2. 还没到期 → 交还定时器（SetTimer 只收毫秒，µs 差值须 /1000）----
        ; ⚠️ 这里必须用 Ceil 而不是 Round：本实现没有 SleepUntilUs 兜底，定时器唤醒的
        ;    瞬间就是触发时刻。Round 向下取整会让我们比计划时刻早醒最多 0.5ms，此时
        ;    `target - now > 0` 成立 → 再次排一个 <1ms 的定时器 → 被 Max(1,…) 抬成
        ;    15.625ms 网格，凭空多吃一格。实测：Round 的 3 秒累积漂移 +15.1~+17.2ms，
        ;    Ceil 后降到 ±2ms 内。（sender.ahk 用 Round 没问题——它有 28ms 提前量，
        ;    醒来后还有 SleepUntilUs 精修，早醒 0.5ms 不影响。）
        if target - now > 0 {
            if Joystick._timers.Has(groupId)
                SetTimer(Joystick._timers[groupId], -Joystick._NextPollMs(target - now))
            return
        }

        ; ---- 3. 收集到期键，按「计划时刻」分桶，并保相位推进基准 ----
        dueBuckets := Map()          ; dueAt(µs) -> [joyKeys 的下标]
        minNext := 0x7FFFFFFFFFFF    ; 哨兵要够大：µs 口径下 0x7FFFFFFF 只有约 35 分钟
        i := 1
        while i <= n {
            iv := Joystick._IntervalUsOf(joyIntervals, i)
            dueAt := triggerTimes[i] + iv
            next := dueAt             ; 未到期：下一次到期时刻就是本次的计划时刻

            if now >= dueAt {
                if !dueBuckets.Has(dueAt)
                    dueBuckets[dueAt] := []
                dueBuckets[dueAt].Push(i)

                ; 保相位单调推进。⚠️ 禁止在滞后时把基准重置为当前时刻。
                last := dueAt
                if dueAt + iv <= now {
                    steps := Floor((now - (dueAt + iv)) / iv) + 1
                    last := dueAt + iv + steps * iv - iv
                    state["droppedTriggers"] := (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0) + steps
                }
                triggerTimes[i] := last
                next := last + iv
            }

            if next < minNext
                minNext := next
            i++
        }

        ; ---- 4. 逐桶批量按下（同一计划时刻的键必须在同一 tick 内发完）----
        for dueAt, bucket in dueBuckets {
            for idx in bucket {
                k := joyKeys[idx]
                Joystick._SendJoyKey(k, "down", sendMethod)
                Joystick._ScheduleRelease(groupId, k, sendMethod, keyDuration)
            }
        }

        ; ---- 5. 排下一次唤醒（须在发送之后取时刻）----
        remaining := minNext - HighResClock.NowUs()
        if Joystick._timers.Has(groupId)
            SetTimer(Joystick._timers[groupId], -Joystick._NextPollMs(remaining))
    }

    ; 序列模式：与 _ExecutePeriodic 同策略
    ;
    ; 旧实现 `state["nextStepTime"] := A_TickCount + nextDelay` 用「发送完成后的当前时刻」
    ; 推进基准，把每一步的实际超时累积进下一步。实测 delay=100ms 时步进退化成
    ; 110.73ms（每步 +9.23ms），3 秒累积漂移 +258.6ms。
    ; 现改为：基准用「本次的计划时刻 dueAt」推进，超时不累积。
    static _ExecuteSequence(groupId) {
        if !Joystick._activeGroups.Has(groupId)
            return

        state := Joystick._activeGroups[groupId]
        joyKeys := state["joyKeys"]
        n := joyKeys.Length
        if n = 0
            return
        joyDelays := state["joyDelays"]
        sendMethod := state["sendMethod"]
        keyDuration := state["keyDuration"]

        now := HighResClock.NowUs()

        step := state["currentStep"]
        if step > n
            step := 1

        ; 首次执行才建立基准（0 = 未初始化），首步立即触发
        if !state.Has("nextStepTime") || state["nextStepTime"] = 0
            state["nextStepTime"] := now

        dueAt := state["nextStepTime"]

        ; ---- 还没到期 → 交还定时器 ----
        if dueAt - now > 0 {
            if Joystick._timers.Has(groupId)
                SetTimer(Joystick._timers[groupId], -Joystick._NextPollMs(dueAt - now))
            return
        }

        ; ---- 发送当前步 ----
        k := joyKeys[step]
        Joystick._SendJoyKey(k, "down", sendMethod)
        Joystick._ScheduleRelease(groupId, k, sendMethod, keyDuration)

        ; ---- 保相位推进：基准用本次的计划时刻 dueAt，不用发送后的当前时刻 ----
        nextStep := Mod(step, n) + 1
        nextDelay := Joystick._DelayUsOf(joyDelays, nextStep)

        advance := 1
        next := dueAt + nextDelay
        if next <= now {
            skipped := Floor((now - next) / nextDelay) + 1
            next += skipped * nextDelay
            state["droppedTriggers"] := (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0) + skipped
            advance += skipped
        }
        state["nextStepTime"] := next
        state["currentStep"] := Mod(step - 1 + advance, n) + 1

        if Joystick._timers.Has(groupId) {
            remaining := next - HighResClock.NowUs()
            SetTimer(Joystick._timers[groupId], -Joystick._NextPollMs(remaining))
        }
    }

    ; =================================================================
    ; vJoy 操作
    ; =================================================================

    static _DetectVJoy() {
        try {
            hModule := DllCall("LoadLibrary", "Str", "vJoyInterface.dll", "Ptr")
            if hModule {
                Joystick._vJoyDll := "vJoyInterface.dll"
                Joystick._vJoyAvailable := 1
                return
            }
        } catch {
        }
        try {
            hModule := DllCall("LoadLibrary", "Str", A_WinDir "\System32\vJoyInterface.dll", "Ptr")
            if hModule {
                Joystick._vJoyDll := A_WinDir "\System32\vJoyInterface.dll"
                Joystick._vJoyAvailable := 1
                return
            }
        } catch {
        }
        Joystick._vJoyAvailable := 0
    }

    static _ResolveMethod(method) {
        if method = "auto"
            return Joystick.IsVJoyAvailable() ? "vjoy" : "direct"
        if method = "vjoy" && !Joystick.IsVJoyAvailable()
            return "direct"
        return method
    }

    static _VJoyOpen() {
        if Joystick._vJoyRefCount > 0 {
            Joystick._vJoyRefCount++
            return true
        }
        h := DllCall(Joystick._vJoyDll "\AcquireVJD", "UInt", Joystick._vJoyDeviceId)
        if h = 0
            throw Error("vJoy AcquireVJD 失败，设备ID=" Joystick._vJoyDeviceId)
        Joystick._vJoyRefCount := 1
        return true
    }

    static _VJoyClose() {
        if Joystick._vJoyRefCount <= 0
            return
        Joystick._vJoyRefCount--
        if Joystick._vJoyRefCount = 0
            DllCall(Joystick._vJoyDll "\RelinquishVJD", "UInt", Joystick._vJoyDeviceId)
    }

    static _ValidateJoyKey(key) {
        if Joystick.ALLOWED_JOY_KEYS.Has(key)
            return true
        OutputDebug("Joystick: 按键被拒绝（不在白名单中） key=" key)
        return false
    }

    static _SendJoyKey(key, state, sendMethod := "auto") {
        try {
            if !Joystick._ValidateJoyKey(key)
                return

            ; 与 Sender._sendHook 同约定：非空则完全接管发送，不产生真实副作用
            if Joystick._joySendHook != "" {
                Joystick._joySendHook.Call(key, state)
                return
            }

            if Joystick._IsButton(key) {
                btnNum := Joystick._GetButtonNum(key)
                if sendMethod = "vjoy"
                    Joystick._VJoySetBtn(btnNum, state = "down")
                else
                    Joystick._DirectSendBtn(btnNum, state)
            } else if Joystick._IsPov(key) {
                direction := Joystick._GetPovDirection(key)
                if sendMethod = "vjoy" {
                    if state = "down"
                        Joystick._VJoySetPov(Joystick._PovDirectionToValue(direction))
                    else
                        Joystick._VJoySetPov(0xFFFFFFFF)
                } else {
                    OutputDebug("Joystick: POV 按键在 direct 模式下不支持 key=" key " (需要 vJoy)")
                }
            } else if Joystick._IsAxis(key) {
                info := Joystick._GetAxisInfo(key)
                value := state = "down" ? 100 : 0
                if sendMethod = "vjoy"
                    Joystick._VJoySetAxis(info["axis"], value)
                else
                    OutputDebug("Joystick: Axis 按键在 direct 模式下不支持 key=" key " (需要 vJoy)")
            }
        } catch as e {
            OutputDebug("Joystick: _SendJoyKey 失败 key=" key " state=" state " err=" e.Message)
        }
    }

    static _VJoySetBtn(btnNum, state) {
        if btnNum < 1 || btnNum > 128 {
            OutputDebug("Joystick: vJoy 按键编号超出范围 btnNum=" btnNum)
            return
        }
        ; T6-07: 依赖组级已 Acquire，直接设置按键，不再每次 open/close
        DllCall(Joystick._vJoyDll "\SetBtn", "UInt", state ? 1 : 0, "UInt", Joystick._vJoyDeviceId, "UChar", btnNum)
    }

    static _VJoySetAxis(axis, value) {
        ; T6-07: 依赖组级已 Acquire，直接设置轴，不再每次 open/close
        axisId := Joystick._AxisToVJoyId(axis)
        scaledVal := Round(value * 327.67)
        if scaledVal < 0
            scaledVal := 0
        if scaledVal > 32767
            scaledVal := 32767
        DllCall(Joystick._vJoyDll "\SetAxis", "Int", scaledVal, "UInt", Joystick._vJoyDeviceId, "UInt", axisId)
    }

    static _VJoySetPov(povVal) {
        ; T6-07: 依赖组级已 Acquire，直接设置 POV，不再每次 open/close
        DllCall(Joystick._vJoyDll "\SetContPov", "UInt", povVal < 0 ? 0xFFFFFFFF : povVal, "UInt", Joystick._vJoyDeviceId, "UInt", 1)
    }

    static _DirectSendBtn(btnNum, state) {
        if btnNum < 1 || btnNum > 128 {
            OutputDebug("Joystick: 按键编号超出范围 btnNum=" btnNum)
            return
        }
        idx := Joystick._vJoyDeviceId
        action := state = "down" ? "Down" : "Up"
        SendInput("{Blind}{" idx "Joy" btnNum " " action "}")
    }

    ; =================================================================
    ; 释放定时器纳管（T6-02）
    ; 将逐键 up 一次性定时器登记进 _releaseTimers，分组停止时统一取消
    ; =================================================================

    static _ScheduleRelease(groupId, key, method, kpd) {
        if !Joystick._releaseTimers.Has(groupId)
            Joystick._releaseTimers[groupId] := Map()
        groupTimers := Joystick._releaseTimers[groupId]
        if groupTimers.Has(key)
            SetTimer(groupTimers[key], 0)
        timerFn := ((g, kk, mm) => () => Joystick._OnReleaseKey(g, kk, mm))(groupId, key, method)
        groupTimers[key] := timerFn
        SetTimer(timerFn, -kpd)
    }

    static _OnReleaseKey(groupId, key, method) {
        Joystick._SendJoyKey(key, "up", method)
        if Joystick._releaseTimers.Has(groupId) {
            groupTimers := Joystick._releaseTimers[groupId]
            if groupTimers.Has(key)
                groupTimers.Delete(key)
        }
    }

    static _CancelReleaseTimers(groupId) {
        if !Joystick._releaseTimers.Has(groupId)
            return
        for key, timerRef in Joystick._releaseTimers[groupId]
            SetTimer(timerRef, 0)
        Joystick._releaseTimers.Delete(groupId)
    }

    ; =================================================================
    ; 按键类型识别
    ; =================================================================

    static _IsButton(key) {
        return RegExMatch(key, "^Joy\d+$")
    }

    static _GetButtonNum(key) {
        return Integer(RegExReplace(key, "^Joy", ""))
    }

    static _IsPov(key) {
        return InStr(key, "JoyPOV") = 1
    }

    static _GetPovDirection(key) {
        if InStr(key, "UP")
            return "UP"
        if InStr(key, "DOWN")
            return "DOWN"
        if InStr(key, "LEFT")
            return "LEFT"
        if InStr(key, "RIGHT")
            return "RIGHT"
        return "CENTER"
    }

    static _IsAxis(key) {
        ; T6-07: 静态缓存轴名集合，避免每次 down/up 重建数组
        static axisSet := ""
        if axisSet = "" {
            axisSet := Map(
                "JoyX", true, "JoyY", true, "JoyZ", true,
                "JoyR", true, "JoyU", true, "JoyV", true
            )
        }
        return axisSet.Has(key)
    }

    static _GetAxisInfo(key) {
        ; T6-07: 静态缓存轴信息表，避免每次 down/up 重建 6 个子 Map
        static axisMap := ""
        if axisMap = "" {
            axisMap := Map(
                "JoyX", Map("axis", "JoyX", "id", 0x30),
                "JoyY", Map("axis", "JoyY", "id", 0x31),
                "JoyZ", Map("axis", "JoyZ", "id", 0x32),
                "JoyR", Map("axis", "JoyR", "id", 0x33),
                "JoyU", Map("axis", "JoyU", "id", 0x34),
                "JoyV", Map("axis", "JoyV", "id", 0x35)
            )
        }
        return axisMap.Has(key) ? axisMap[key] : Map("axis", "JoyX", "id", 0x30)
    }

    static _AxisToVJoyId(axis) {
        info := Joystick._GetAxisInfo(axis)
        return info["id"]
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
