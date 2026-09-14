; =================================================================
; 按键发送器 - IPC 指令驱动的按键执行
; 版本: 1.0
; 说明: 收到 IPC 执行指令时发送按键
;       支持各种执行模式（periodic, sequence, enhanced_*）
;       使用 AHK Send/SendInput 命令
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "ipc_client.ahk"
#Include "high_res_clock.ahk"

class Sender {
    ; 活跃的执行组: groupId => 执行状态
    static _activeGroups := Map()

    ; 定时器引用: groupId => timerRef
    static _timers := Map()

    ; 释放定时器引用: groupId => (key => timerRef)，用于停止时取消滞后 up（T6-02）
    static _releaseTimers := Map()

    ; Hold 模式按住的键: groupId => [keys]
    static _heldKeys := Map()

    ; Hold 模式状态
    static _holdModeEnabled := true

    ; 逐键 key_send_event IPC 上报开关（仅在录制/验证模式由 CommandDispatcher 置 true）
    static _reportKeyEvents := false

    ; 逐键事件发送函数注入点（默认为空=使用 IpcClient._SendMsg；测试可注入 mock 避免真实 IPC）
    static _keyEventSender := ""

    ; 发送原语注入点（默认为空=使用 SendInput；测试可注入 mock 避免真实按键副作用）
    static _sendHook := ""

    ; =================================================================
    ; 精确定刻常量（背景与实测数据见 _ExecutePeriodic 注释）
    ; =================================================================

    ; ⚠️ 调度内部一切时刻/间隔一律用「整数微秒」（int µs），不用浮点毫秒。
    ; 理由：浮点毫秒累加的末位误差会让「数学上同时到期」的两个键被 Map 判成
    ; 不同的键、拆成两个桶，后一个桶的保持时长塌成 ~0ms。实测拆桶率 94% → 0%。
    ; 对外（配置、SetTimer、kpd）仍是毫秒，边界处用 Round(x * 1000) 转换。

    ; 最小周期间隔（µs），等价于既有行为的 10 ms
    static MIN_INTERVAL_US := 10000

    ; 定时器提前唤醒量（µs）。必须显著大于 15.625ms（Windows 定时器网格），
    ; 保证定时唤醒一定落在 [目标-提前量, 目标) 内，再由 SleepUntil 精修到点。
    ; 实测（interval=100/kpd=15，各 3 轮）选参依据：
    ;   18 → 定时器偶发迟到 ~7ms，保持时长被压缩到最低 8.0ms，周期最大 107ms
    ;   28 → 保持时长最低 14.8ms，周期最大 100.17ms
    ;   40 → 与 28 持平（14.9 / 100.23），但让出式等待窗口更长
    ; 28 ≈ 1.8 个网格，足以吸收一整格唤醒抖动 + 系统调度抖动，代价最小
    static WAKE_LEAD_US := 28000

    ; 判定"已到期"的容差（µs），等价于既有行为的 0.5 ms
    static TIMING_EPSILON_US := 500

    ; 精确定刻保持时长的上限（ms）。超过此值的 keyPressDuration 退回异步释放 ——
    ; 该配置下「计划时刻 → 抬起完成」必然 > 20ms，精确定刻已无意义
    static PRECISE_HOLD_MAX_MS := 20

    ; 按键白名单
    static ALLOWED_KEYS := Map(
        "F1", true, "F2", true, "F3", true, "F4", true, "F5", true, "F6", true,
        "F7", true, "F8", true, "F9", true, "F10", true, "F11", true, "F12", true,
        "1", true, "2", true, "3", true, "4", true, "5", true,
        "6", true, "7", true, "8", true, "9", true, "0", true,
        "a", true, "b", true, "c", true, "d", true, "e", true, "f", true,
        "g", true, "h", true, "i", true, "j", true, "k", true, "l", true,
        "m", true, "n", true, "o", true, "p", true, "q", true, "r", true,
        "s", true, "t", true, "u", true, "v", true, "w", true, "x", true,
        "y", true, "z", true,
        "Space", true, "Enter", true, "Tab", true, "Esc", true, "Backspace", true,
        "Delete", true, "Insert", true, "Home", true, "End", true,
        "PgUp", true, "PgDn", true,
        "Up", true, "Down", true, "Left", true, "Right", true,
        "Shift", true, "Ctrl", true, "Alt", true, "LWin", true, "RWin", true,
        "LShift", true, "RShift", true, "LCtrl", true, "RCtrl", true,
        "LAlt", true, "RAlt", true,
        "Numpad0", true, "Numpad1", true, "Numpad2", true, "Numpad3", true,
        "Numpad4", true, "Numpad5", true, "Numpad6", true, "Numpad7", true,
        "Numpad8", true, "Numpad9", true,
        "NumpadEnter", true, "NumpadAdd", true, "NumpadSub", true,
        "NumpadMult", true, "NumpadDiv", true,
        "Joy1", true, "Joy2", true, "Joy3", true, "Joy4", true,
        "Joy5", true, "Joy6", true, "Joy7", true, "Joy8", true,
        "Joy9", true, "Joy10", true, "Joy11", true, "Joy12", true,
        "Joy13", true, "Joy14", true, "Joy15", true, "Joy16", true,
        "Joy17", true, "Joy18", true, "Joy19", true, "Joy20", true,
        "Joy21", true, "Joy22", true, "Joy23", true, "Joy24", true,
        "Joy25", true, "Joy26", true, "Joy27", true, "Joy28", true,
        "Joy29", true, "Joy30", true, "Joy31", true, "Joy32", true,
        "JoyX", true, "JoyY", true, "JoyZ", true, "JoyR", true,
        "JoyU", true, "JoyV", true,
        "JoyPOVUP", true, "JoyPOVDOWN", true,
        "JoyPOVLEFT", true, "JoyPOVRIGHT", true
    )

    ; =================================================================
    ; 公开方法
    ; =================================================================

    static Init() {
        OutputDebug("Sender: 已初始化")
    }

    ; 切换技能组激活状态
    static ToggleGroup(groupId, active) {
        if active
            return Sender._StartGroup(groupId)
        else
            return Sender._StopGroup(groupId)
    }

    ; 紧急释放所有按键
    static EmergencyRelease() {
        OutputDebug("Sender: 紧急释放所有按键")

        ; 停止所有执行组
        groupIds := []
        for id in Sender._activeGroups
            groupIds.Push(id)
        for id in groupIds
            Sender._StopGroup(id)

        ; 释放所有 hold 按键
        for groupId, keys in Sender._heldKeys {
            for k in keys
                Sender._SendKeyUp(k)
        }
        Sender._heldKeys := Map()

        ; T6-02: 清空所有残留释放定时器（_StopGroup 已处理活跃组，此处兜底）
        for groupId, groupTimers in Sender._releaseTimers
            for k, timerRef in groupTimers
                SetTimer(timerRef, 0)
        Sender._releaseTimers := Map()

        OutputDebug("Sender: 紧急释放完成")
    }

    ; Hold 模式切换
    static HoldModeToggle(enabled) {
        Sender._holdModeEnabled := enabled
        OutputDebug("Sender: Hold 模式 " (enabled ? "启用" : "禁用"))

        if !enabled {
            ; 释放所有 hold 按键
            for groupId, keys in Sender._heldKeys {
                for k in keys
                    Sender._SendKeyUp(k)
            }
            Sender._heldKeys := Map()
        }
    }

    ; 关机清理
    static Shutdown() {
        Sender.EmergencyRelease()
        OutputDebug("Sender: 已关机")
    }

    ; =================================================================
    ; 执行组管理
    ; =================================================================

    static _StartGroup(groupId) {
        if Sender._activeGroups.Has(groupId) {
            OutputDebug("Sender: 组已激活 groupId=" groupId)
            return true
        }

        Sender._activeGroups[groupId] := Map(
            "startTime", HighResClock.Now(),
            "lastTriggerTimes", Map(),
            "currentStep", 1,
            "nextStepTime", 0
        )

        OutputDebug("Sender: 已激活 groupId=" groupId)
        return true
    }

    static _StopGroup(groupId) {
        if !Sender._activeGroups.Has(groupId) {
            OutputDebug("Sender: 组未激活 groupId=" groupId)
            return true
        }

        ; 停止定时器
        if Sender._timers.Has(groupId) {
            SetTimer(Sender._timers[groupId], 0)
            Sender._timers.Delete(groupId)
        }

        ; T6-02: 取消该组的释放定时器，消除停止后滞后 up
        Sender._CancelReleaseTimers(groupId)

        ; 释放 hold 按键
        if Sender._heldKeys.Has(groupId) {
            for k in Sender._heldKeys[groupId]
                Sender._SendKeyUp(k)
            Sender._heldKeys.Delete(groupId)
        }

        ; 停止摇杆轮询
        Joystick.StopGroup(groupId)

        Sender._activeGroups.Delete(groupId)
        OutputDebug("Sender: 已停止 groupId=" groupId)
        return true
    }

    ; =================================================================
    ; 执行模式
    ; =================================================================

    ; 启动周期性按键执行
    static StartPeriodic(groupId, keys, intervals, keyPressDuration := 15) {
        ; T6-04 幂等保护：若已存在执行定时器则先取消，避免重复激活导致双倍发键
        if Sender._timers.Has(groupId) {
            SetTimer(Sender._timers[groupId], 0)
            Sender._timers.Delete(groupId)
        }
        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "periodic"
        state["keys"] := keys
        state["intervals"] := intervals
        state["keyPressDuration"] := keyPressDuration

        ; 启动执行定时器
        timerFn := () => Sender._ExecutePeriodic(groupId)
        Sender._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Sender: 启动周期性 groupId=" groupId " keys=" keys.Length)
    }

    ; 启动序列按键执行
    static StartSequence(groupId, keys, delays, keyPressDuration := 15, seqInterval := 0) {
        ; T6-04 幂等保护：若已存在执行定时器则先取消，避免重复激活导致双倍发键
        if Sender._timers.Has(groupId) {
            SetTimer(Sender._timers[groupId], 0)
            Sender._timers.Delete(groupId)
        }
        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "sequence"
        state["keys"] := keys
        state["delays"] := delays
        state["keyPressDuration"] := keyPressDuration
        state["seqInterval"] := seqInterval
        state["currentStep"] := 1
        ; 0 = 未初始化，由 _ExecuteSequence 在**首次执行**时建立基准。
        ; 不能在这里直接写当前时刻：定时器首次回调可能远晚于本次调用（实测可达 100ms+），
        ; 若基准已过期，首次按下会立刻超时（保持时长被压成 ~0ms），
        ; 并且会被误判为「已落后」而白跳一步。
        state["nextStepTime"] := 0

        timerFn := () => Sender._ExecuteSequence(groupId)
        Sender._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Sender: 启动序列 groupId=" groupId " keys=" keys.Length)
    }

    ; 启动增强周期性
    static StartEnhancedPeriodic(groupId, keys, intervals, keyPressDuration := 15) {
        Sender.StartPeriodic(groupId, keys, intervals, keyPressDuration)
        if Sender._activeGroups.Has(groupId)
            Sender._activeGroups[groupId]["mode"] := "enhanced_periodic"
    }

    ; 启动增强序列
    static StartEnhancedSequence(groupId, keys, delays, keyPressDuration := 15, seqInterval := 0) {
        Sender.StartSequence(groupId, keys, delays, keyPressDuration, seqInterval)
        if Sender._activeGroups.Has(groupId)
            Sender._activeGroups[groupId]["mode"] := "enhanced_sequence"
    }

    ; 启动 Hold 模式
    ; holdDuration=0 表示无限保持（直到主动停止）
    ; holdDuration>0 表示固定时长保持，超时后自动释放并停用分组
    static StartHold(groupId, holdKeys, holdMode := "continuous", holdDuration := 0) {
        if !Sender._holdModeEnabled {
            OutputDebug("Sender: Hold 模式已禁用，跳过 groupId=" groupId)
            return
        }

        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "hold"
        state["holdKeys"] := holdKeys
        state["holdMode"] := holdMode
        state["holdDuration"] := holdDuration

        ; 按住按键
        Sender._heldKeys[groupId] := holdKeys
        for k in holdKeys
            Sender._SendKeyDown(k)

        ; 如果 holdDuration > 0，设置一次性定时器在超时后自动释放
        ; holdDuration=0 表示无限保持，不设置定时器
        ; SetTimer 第二个参数为负数 = 一次性定时器（N 毫秒后触发一次）
        if holdDuration > 0 {
            timerFn := () => Sender._HoldTimeout(groupId)
            Sender._timers[groupId] := timerFn
            SetTimer(timerFn, -holdDuration)
            OutputDebug("Sender: 启动 Hold groupId=" groupId " keys=" holdKeys.Length " mode=" holdMode " duration=" holdDuration "ms")
        } else {
            OutputDebug("Sender: 启动 Hold groupId=" groupId " keys=" holdKeys.Length " mode=" holdMode " duration=infinite")
        }
    }

    ; holdDuration 超时回调：自动释放按键并停用分组
    static _HoldTimeout(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        ; 释放 hold 按键
        if Sender._heldKeys.Has(groupId) {
            for k in Sender._heldKeys[groupId]
                Sender._SendKeyUp(k)
            Sender._heldKeys.Delete(groupId)
        }

        ; 清理定时器引用
        if Sender._timers.Has(groupId)
            Sender._timers.Delete(groupId)

        ; 停用分组
        Sender._activeGroups.Delete(groupId)

        OutputDebug("Sender: Hold 超时自动释放 groupId=" groupId)
    }

    ; 启动混合模式
    static StartHybrid(groupId, groups, keyPressDuration := 15) {
        ; T6-04 幂等保护：若已存在执行定时器则先取消，避免重复激活导致双倍发键
        if Sender._timers.Has(groupId) {
            SetTimer(Sender._timers[groupId], 0)
            Sender._timers.Delete(groupId)
        }
        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "hybrid"
        state["groups"] := groups
        state["keyPressDuration"] := keyPressDuration
        state["groupTriggerTimes"] := Map()

        timerFn := () => Sender._ExecuteHybrid(groupId)
        Sender._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Sender: 启动混合 groupId=" groupId)
    }

    ; 启动增强混合模式
    static StartEnhancedHybrid(groupId, groups, keyPressDuration := 15) {
        Sender.StartHybrid(groupId, groups, keyPressDuration)
        if Sender._activeGroups.Has(groupId)
            Sender._activeGroups[groupId]["mode"] := "enhanced_hybrid"
    }

    ; =================================================================
    ; 执行引擎
    ; =================================================================

    ; =================================================================
    ; 周期模式的精确定刻执行
    ;
    ; 目标：每一次模拟按键「计划时刻 → 抬起完成」P95 ≤ 20ms，且不遗漏触发。
    ;
    ; 背景（2026-09-13 本机实测，勿凭直觉回退）：
    ;   · SetTimer 与 Sleep 被锁死在 15.625ms 网格：请求 1/5/10/15ms 全部得到
    ;     ~15.6ms；请求 16ms 反而得到 ~31.25ms（跨过网格阈值直接跳两格）。
    ;   · A_TickCount 步进中位 15.52ms，不能作为 20ms 预算内的时间基准。
    ;   · timeBeginPeriod(1) 对 AHK 无效。
    ;   · 唯一能突破网格的是 QPC 定位（实测末段忙等误差约 0.002ms）。
    ;
    ; 因此：① 计划时刻一律用 HighResClock(QPC) 表示；
    ;       ② 定时器只负责“提前唤醒”（提前量 > 一个网格），到点由 SleepUntil 精修；
    ;       ③ 保持时长 kpd 同样用 SleepUntil 控制，不再走 SetTimer(-kpd)。
    ; =================================================================

    ; 取第 i 个键的周期间隔（µs，含下限夹紧）
    ; 入参 intervals 是毫秒（可能带小数，录制回放路径就是浮点），在此一次性转成整数 µs。
    static _IntervalUsOf(intervals, i) {
        interval := i <= intervals.Length ? intervals[i] : 50
        intervalUs := Round(interval * 1000)
        return intervalUs < Sender.MIN_INTERVAL_US ? Sender.MIN_INTERVAL_US : intervalUs
    }

    ; 取序列第 i 步的延时（µs，含下限夹紧）。默认值与旧实现一致（100ms）
    static _DelayUsOf(delays, i) {
        delay := i <= delays.Length ? delays[i] : 100
        delayUs := Round(delay * 1000)
        return delayUs < Sender.MIN_INTERVAL_US ? Sender.MIN_INTERVAL_US : delayUs
    }

    ; 精确执行一次「按下 → 保持 kpd → 抬起」。
    ; plannedAtUs 是本次按下的计划时刻（**整数微秒**），kpd 仍是毫秒（对外配置口径）；
    ; 抬起按 plannedAtUs + kpd 定位，使「计划时刻 → 抬起完成」恰好等于 kpd（+ 微秒级误差）。
    static _PressPrecise(groupId, key, plannedAtUs, kpd) {
        Sender._PressPreciseBatch(groupId, [key], plannedAtUs, kpd)
    }

    ; 同一计划时刻的多个键必须批量处理：全部 Down → 统一等到 plannedAt + kpd → 全部 Up。
    ; 若逐键做「Down → 等 → Up」，第二个键的等待会立刻超时（已过 plannedAt + kpd），
    ; 保持时长被压成 ~0ms，且各键被串行推迟。旧实现是各键独立释放定时器（天然并行），
    ; 批量化既保持了该语义，又让每个键的保持时长都精确等于 kpd。
    static _PressPreciseBatch(groupId, keys, plannedAtUs, kpd) {
        for k in keys
            Sender._SendKeyDown(k)
        if kpd > 0
            HighResClock.SleepUntilUs(plannedAtUs + Round(kpd * 1000))
        for k in keys
            Sender._SendKeyUp(k)
    }

    ; 以批量或异步方式释放一批同刻按键（kpd 超出精确定刻范围时走此路径）
    static _PressAsyncBatch(groupId, keys, kpd) {
        for k in keys {
            Sender._SendKeyDown(k)
            if kpd > 0
                Sender._ScheduleRelease(groupId, k, kpd)
            else
                Sender._SendKeyUp(k)
        }
    }

    static _ExecutePeriodic(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        state := Sender._activeGroups[groupId]
        keys := state["keys"]
        intervals := state["intervals"]
        kpd := state["keyPressDuration"]
        triggerTimes := state["lastTriggerTimes"]

        ; ---- 1. 首次出现的键建立基准时刻 ----
        now := HighResClock.NowUs()
        for i, k in keys {
            if !triggerTimes.Has(i)
                triggerTimes[i] := now
        }

        ; ---- 2. 求最近的到期时刻（计划时刻）----
        target := 0
        for i, k in keys {
            t := triggerTimes[i] + Sender._IntervalUsOf(intervals, i)
            if target = 0 || t < target
                target := t
        }

        ; ---- 3. 精确定位到计划时刻 ----
        ; 还早 → 交给定时器提前唤醒（提前量覆盖最坏量化误差），本轮不阻塞主线程；
        ; 已近 → 让出式等待 + 末段忙等到点。
        ; ⚠️ SetTimer 只接受毫秒，µs 差值必须 /1000 后再传。
        if target - now > Sender.WAKE_LEAD_US {
            if Sender._timers.Has(groupId)
                SetTimer(Sender._timers[groupId], -Max(1, Round((target - now - Sender.WAKE_LEAD_US) / 1000)))
            return
        }
        if target > now
            now := HighResClock.SleepUntilUs(target)

        ; ---- 4. 收集已到期的键，按「计划时刻」分桶，并保相位推进基准 ----
        ; 分桶是必需的：计划时刻相同的键必须批量按下/释放，否则后一个键的保持时长
        ; 会被压成 ~0ms（详见 _PressPreciseBatch 注释）。
        dueBuckets := Map()          ; dueAt(µs) -> [keys]
        for i, k in keys {
            interval := Sender._IntervalUsOf(intervals, i)
            dueAt := triggerTimes[i] + interval

            if now < dueAt - Sender.TIMING_EPSILON_US
                continue

            if !dueBuckets.Has(dueAt)
                dueBuckets[dueAt] := []
            dueBuckets[dueAt].Push(k)

            ; 计划时刻单调推进并保持相位。
            ; 原实现 `if triggerTimes[i] < now - interval then triggerTimes[i] := now`
            ; 会在滞后时把基准直接重置为当前时刻 —— 既丢相位，又吞掉本应发生的触发。
            ; 注意：推进基准必须用「本次触发的计划时刻 dueAt」，而不是发送完成后的当前时刻 ——
            ; 后者已被 kpd 保持时长推后，会让每次都被误判为"已落后"而白跳一个周期。
            last := dueAt
            next := dueAt + interval
            if next <= now {
                steps := Floor((now - next) / interval) + 1
                next += steps * interval
                state["droppedTriggers"] := (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0) + steps
                last := next - interval
            }
            triggerTimes[i] := last
        }

        ; ---- 4b. 逐个计划时刻批量按下/释放 ----
        ; 超长保持（kpd > PRECISE_HOLD_MAX_MS）下「计划时刻→抬起完成」必然 > 20ms，
        ; 精确定刻已无意义，退回异步释放。
        for dueAt, batch in dueBuckets {
            if kpd > 0 && kpd <= Sender.PRECISE_HOLD_MAX_MS
                Sender._PressPreciseBatch(groupId, batch, dueAt, kpd)
            else
                Sender._PressAsyncBatch(groupId, batch, kpd)
        }

        ; ---- 4c. 按推进后的基准重算最小剩余时间（须在发送之后取时刻）----
        ; 哨兵要足够大：µs 口径下 0x7FFFFFFF 只有约 35 分钟，这里抬到约 2.4 年。
        minRemaining := 0x7FFFFFFFFFFF
        nowAfter := HighResClock.NowUs()
        for i, k in keys {
            remaining := triggerTimes[i] + Sender._IntervalUsOf(intervals, i) - nowAfter
            if remaining < minRemaining
                minRemaining := remaining
        }

        ; ---- 5. 排下一次唤醒（同样扣掉提前量，保证唤醒落在目标之前）----
        nextPoll := Max(1, Round((minRemaining - Sender.WAKE_LEAD_US) / 1000))
        if Sender._timers.Has(groupId)
            SetTimer(Sender._timers[groupId], -nextPoll)
    }

    ; 序列模式的精确定刻执行（策略与 _ExecutePeriodic 一致）
    ;
    ; 原实现有两个缺陷：
    ;   ① 时间基准用 A_TickCount（步进 15.52ms），释放走 SetTimer(-kpd)（15.625ms 网格）；
    ;   ② `nextStepTime := A_TickCount + nextDelay` 用「发送完成后的当前时刻」推进基准，
    ;      把每一步的实际超时累积进下一步。实测 delay=100ms 时步进退化成 111.9ms，
    ;      「计划时刻 → 抬起完成」随时长线性增长（3 秒内 P95 达 248~263ms）。
    ; 现改为：QPC 基准 + 提前唤醒 + SleepUntil 精修 + 保相位推进。
    static _ExecuteSequence(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        state := Sender._activeGroups[groupId]
        keys := state["keys"]
        delays := state["delays"]
        kpd := state["keyPressDuration"]

        now := HighResClock.NowUs()

        step := state["currentStep"]
        if step > keys.Length
            step := 1

        ; 首次进入：以当前时刻作为本步的计划时刻（与旧实现一致，首步立即触发）
        if !state.Has("nextStepTime") || state["nextStepTime"] = 0
            state["nextStepTime"] := now

        dueAt := state["nextStepTime"]

        ; ---- 精确定位到计划时刻 ----
        if dueAt - now > Sender.WAKE_LEAD_US {
            if Sender._timers.Has(groupId)
                SetTimer(Sender._timers[groupId], -Max(1, Round((dueAt - now - Sender.WAKE_LEAD_US) / 1000)))
            return
        }
        if dueAt > now
            now := HighResClock.SleepUntilUs(dueAt)

        ; ---- 发送当前步 ----
        k := keys[step]
        if kpd > 0 && kpd <= Sender.PRECISE_HOLD_MAX_MS
            Sender._PressPreciseBatch(groupId, [k], dueAt, kpd)
        else
            Sender._PressAsyncBatch(groupId, [k], kpd)

        ; ---- 保相位推进：基准用本次的计划时刻 dueAt，不用发送后的当前时刻 ----
        nextStep := Mod(step, keys.Length) + 1
        nextDelay := Sender._DelayUsOf(delays, nextStep)

        advance := 1
        next := dueAt + nextDelay
        if next <= now {
            skipped := Floor((now - next) / nextDelay) + 1
            next += skipped * nextDelay
            state["droppedTriggers"] := (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0) + skipped
            advance += skipped
        }
        state["nextStepTime"] := next
        state["currentStep"] := Mod(step - 1 + advance, keys.Length) + 1

        remaining := next - HighResClock.NowUs()
        if Sender._timers.Has(groupId)
            SetTimer(Sender._timers[groupId], -Max(1, Round((remaining - Sender.WAKE_LEAD_US) / 1000)))
    }

    ; 混合模式的精确定刻执行。
    ; 子组可能是 periodic 或 sequence，两者统一按 QPC 策略调度。
    ;
    ; 原实现的三个问题与 _ExecutePeriodic / _ExecuteSequence 同源：
    ;   ① A_TickCount 基准（步进 15.52ms）+ SetTimer(-kpd) 释放（15.625ms 网格）；
    ;   ② periodic 子组允许提前 5% 触发，且触发后把基准写成 now（丢相位）；
    ;   ③ sequence 子组从发送完成后的当前时刻推进基准，误差逐步累积。
    static _ExecuteHybrid(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        state := Sender._activeGroups[groupId]
        groups := state["groups"]
        kpd := state["keyPressDuration"]
        triggerTimes := state["groupTriggerTimes"]

        now := HighResClock.NowUs()

        ; ---- 1. 初始化基准，并构造子项列表 ----
        ; 子项 = [kind, grpIdx, idx, dueAt(µs), params, key, keyCount]
        ;   periodic: idx = 键序号，params = intervals
        ;   sequence: idx = 当前步，params = delays，keyCount = 键总数
        items := []
        for grpIdx, grp in groups {
            grpType := grp.Has("type") ? grp["type"] : "periodic"
            grpKeys := grp.Has("pressKeys") ? grp["pressKeys"] : (grp.Has("keys") ? grp["keys"] : [])

            if grpKeys.Length = 0
                continue

            if grpType = "sequence" {
                stepKey := grpIdx ".step"
                if !triggerTimes.Has(stepKey)
                    triggerTimes[stepKey] := 1
                nextTimeKey := grpIdx ".nextTime"
                if !triggerTimes.Has(nextTimeKey)
                    triggerTimes[nextTimeKey] := now
                grpDelays := grp.Has("delays") ? grp["delays"] : [100]
                step := triggerTimes[stepKey]
                if step > grpKeys.Length
                    step := 1
                items.Push(["sequence", grpIdx, step, triggerTimes[nextTimeKey], grpDelays, grpKeys[step], grpKeys.Length])
            } else {
                grpIntervals := grp.Has("intervals") ? grp["intervals"] : [50]
                for i, k in grpKeys {
                    triggerKey := grpIdx "." i
                    if !triggerTimes.Has(triggerKey)
                        triggerTimes[triggerKey] := now
                    interval := Sender._IntervalUsOf(grpIntervals, i)
                    items.Push(["periodic", grpIdx, i, triggerTimes[triggerKey] + interval, grpIntervals, k, grpKeys.Length])
                }
            }
        }

        if items.Length = 0 {
            if Sender._timers.Has(groupId)
                SetTimer(Sender._timers[groupId], 0)
            return
        }

        ; ---- 2. 求最近的计划时刻 ----
        target := 0
        for it in items {
            if target = 0 || it[4] < target
                target := it[4]
        }

        ; ---- 3. 精确定位到计划时刻 ----
        if target - now > Sender.WAKE_LEAD_US {
            if Sender._timers.Has(groupId)
                SetTimer(Sender._timers[groupId], -Max(1, Round((target - now - Sender.WAKE_LEAD_US) / 1000)))
            return
        }
        if target > now
            now := HighResClock.SleepUntilUs(target)

        ; ---- 4. 收集已到期子项（按计划时刻分桶），并保相位推进基准 ----
        dueBuckets := Map()      ; dueAt(µs) -> [子项]
        nextDues := []           ; 每个子项下一次的计划时刻
        for it in items {
            dueAt := it[4]
            if now < dueAt - Sender.TIMING_EPSILON_US {
                nextDues.Push(dueAt)
                continue
            }

            if !dueBuckets.Has(dueAt)
                dueBuckets[dueAt] := []
            dueBuckets[dueAt].Push(it)

            if it[1] = "periodic" {
                interval := Sender._IntervalUsOf(it[5], it[3])
                last := dueAt
                next := dueAt + interval
                if next <= now {
                    steps := Floor((now - next) / interval) + 1
                    next += steps * interval
                    state["droppedTriggers"] := (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0) + steps
                    last := next - interval
                }
                triggerTimes[it[2] "." it[3]] := last
            } else {
                nextStep := Mod(it[3], it[7]) + 1
                nextDelay := Sender._DelayUsOf(it[5], nextStep)
                advance := 1
                next := dueAt + nextDelay
                if next <= now {
                    skipped := Floor((now - next) / nextDelay) + 1
                    next += skipped * nextDelay
                    state["droppedTriggers"] := (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0) + skipped
                    advance += skipped
                }
                triggerTimes[it[2] ".nextTime"] := next
                triggerTimes[it[2] ".step"] := Mod(it[3] - 1 + advance, it[7]) + 1
            }
            nextDues.Push(next)
        }

        ; ---- 5. 逐个计划时刻批量按下/释放（同刻必须批量，见 _PressPreciseBatch）----
        for dueAt, batch in dueBuckets {
            batchKeys := []
            for it in batch
                batchKeys.Push(it[6])
            if kpd > 0 && kpd <= Sender.PRECISE_HOLD_MAX_MS
                Sender._PressPreciseBatch(groupId, batchKeys, dueAt, kpd)
            else
                Sender._PressAsyncBatch(groupId, batchKeys, kpd)
        }

        ; ---- 6. 按推进后的基准排下一次唤醒（须在发送之后取时刻）----
        minRemaining := 0x7FFFFFFFFFFF
        nowAfter := HighResClock.NowUs()
        for d in nextDues {
            if d - nowAfter < minRemaining
                minRemaining := d - nowAfter
        }
        if Sender._timers.Has(groupId)
            SetTimer(Sender._timers[groupId], -Max(1, Round((minRemaining - Sender.WAKE_LEAD_US) / 1000)))
    }

    ; =================================================================
    ; 底层按键操作
    ; =================================================================

    static _ValidateKey(key) {
        if Sender.ALLOWED_KEYS.Has(key)
            return true
        OutputDebug("Sender: 按键被拒绝（不在白名单中） key=" key)
        return false
    }

    static _SendKeyDown(key) {
        if !Sender._ValidateKey(key)
            return
        if Sender._sendHook != "" {
            Sender._sendHook.Call(key, "down")
        } else {
            try
                SendInput("{Blind}{" key " Down}")
            catch as e
                OutputDebug("Sender: 按键按下失败 key=" key " err=" e.Message)
        }
        Sender._ReportKeyEvent(key, "down")
    }

    static _SendKeyUp(key) {
        if !Sender._ValidateKey(key)
            return
        if Sender._sendHook != "" {
            Sender._sendHook.Call(key, "up")
        } else {
            try
                SendInput("{Blind}{" key " Up}")
            catch as e
                OutputDebug("Sender: 按键释放失败 key=" key " err=" e.Message)
        }
        Sender._ReportKeyEvent(key, "up")
    }

    ; =================================================================
    ; 释放定时器纳管（T6-02）
    ; 将逐键 up 一次性定时器登记进 _releaseTimers，分组停止时统一取消，
    ; 消除「停止后滞后发一次 up」的问题
    ; =================================================================

    static _ScheduleRelease(groupId, key, kpd) {
        if !Sender._releaseTimers.Has(groupId)
            Sender._releaseTimers[groupId] := Map()
        groupTimers := Sender._releaseTimers[groupId]
        ; 覆盖前先取消旧释放定时器，避免同键悬挂
        if groupTimers.Has(key)
            SetTimer(groupTimers[key], 0)
        timerFn := ((g, kk) => () => Sender._OnReleaseKey(g, kk))(groupId, key)
        groupTimers[key] := timerFn
        SetTimer(timerFn, -kpd)
    }

    static _OnReleaseKey(groupId, key) {
        Sender._SendKeyUp(key)
        if Sender._releaseTimers.Has(groupId) {
            groupTimers := Sender._releaseTimers[groupId]
            if groupTimers.Has(key)
                groupTimers.Delete(key)
        }
    }

    static _CancelReleaseTimers(groupId) {
        if !Sender._releaseTimers.Has(groupId)
            return
        for key, timerRef in Sender._releaseTimers[groupId]
            SetTimer(timerRef, 0)
        Sender._releaseTimers.Delete(groupId)
    }

    ; 仅在录制/验证模式（_reportKeyEvents=true）时上报逐键 key_send_event；
    ; SendInput 始终执行，本方法只负责 IPC 上报的可测试切片
    static _ReportKeyEvent(key, state) {
        if !Sender._reportKeyEvents
            return false
        try {
            msg := Map(
                "type", "key_send_event",
                "seq", IpcClient._NextSeq(),
                "data", Map("key", key, "state", state, "device", "keyboard")
            )
            sendFn := Sender._keyEventSender
            if sendFn = ""
                return IpcClient._SendMsg(msg)
            return sendFn(msg)
        } catch as e {
            OutputDebug("Sender: 按键上报失败 key=" key " err=" e.Message)
            return false
        }
    }
}
