; =================================================================
; bench_prod_tick —— 【生产回归基准】周期模式 tick 遍历（T6 / MERGE_TICK_SCAN）
;
; 与 bench_tick_traversal.ahk 的区别（重要，别混淆）：
;   bench_tick_traversal 是**选型期**的双实现对照基准 —— old/new 两份实现都复刻在脚本里。
;   T6 落地后脚本里的 new 侧是副本，生产代码再改也不会跟着变 —— 对生产回归**零防护力**。
;   本脚本直接 #Include 生产 sender.ahk 并测它的 _ExecutePeriodic。
;
; 被测：asd-tauri/src-tauri/ahk_executor/sender.ahk 的 Sender._ExecutePeriodic
;   （内部按 MERGE_TICK_SCAN 在 _ExecutePeriodicMerged / _ExecutePeriodicLegacy 间分派）
;
; 为什么要测 tick：T6 把每 tick 的 4 次遍历合并成 2 次。合并版是**唯一在跑**的实现，
;   一旦有人把它改回多次遍历、或引入 O(n²)，功能测试全绿、性能静默劣化。
;
; 两种形态（信号强度实测，见 docs/developer-guide.md §4.6.4）：
;   onedue —— n 个键里只有第 1 个到期（**生产最常见形态**）：遍历照跑 n 次，但只有
;             2 次发送，发送开销不稀释遍历耗时 → **信号最强（n=64 1.71~1.81×、
;             n=128 1.73~1.79×，且区间不重叠）**
;   alldue —— n 个键全部到期：覆盖「分桶」路径（n 个桶）。发送开销 2n 次会稀释，
;             信号只有 ~1.2× → **主力守「复杂度回归」，不指望它抓住回退**
;
; ⚠️ 不测 prescan（提前返回路径）：实测合并版与旧版在该路径上**区间重叠、测不出差异**
;    （n=8 1.02× / n=64 0.82× / n=128 0.93×），放进门禁只会得到一条永远 PASS 的虚线。
;
; ⚠️ 不测 n≤32：实测**每 tick 有一档约 13 µs 的固定开销跨进程抖动**（与 n 无关），
;    n=16 时它占总耗时 26% → 同一份代码连跑 5 轮出现 0.042 / 0.053 双峰（±32%）。
;    而 n=16 的回退信号只有 1.26~1.48×，**低于自身噪声 → 信噪比 <1，无法用于门禁**。
;    n=64 起该抖动降到 <10%，n=128 降到 ~5%。代价是失去了「真实规模（十几键）」覆盖，
;    属**已知盲区**。
;
; ⚠️ 不测 hybrid：hybrid 每 tick 都要重建 items 数组（n 个 7 元数组），分配开销会
;    淹没遍历差异，信号同样不可靠。等价性已由单测 Test_TickMerge_* 覆盖。
;
; 为什么形态能保持稳定（关键，否则基准会退化成测别的东西）：
;   onedue 用「固定基准」构造：intervals[1] = 1e6 ms（1e9 µs），
;   triggerTimes[1] = base - 1e9 → dueAt 恒等于 base（过去），且 dueAt + interval 恒 > now
;   → **不触发追帧分支**，结果与时俱退无关、可跨实现比对。每 tick 只需 O(1) 重武装。
;   其余键的 triggerTimes 设到 5 秒后 → 永不到期、永不被改写。
;
; 输出：%AHK_BENCH_OUT%\prod_tick.csv + prod_tick.done
;   每行：`metric,<name>,p50=..,p95=..,max=..,min=..,mean=..,n=..,keys=..,sends=..,us_per_tick=..`
;   ⚠️ keys=/sends= 是**形态自描述**：keys 是键数量，sends 是每 tick 实际发送次数。
;      gate.py 会拿它跟基线比对 —— 万一形态构造写错（比如全键都到期了），
;      耗时结构会变而没人发现。这是基准侧的「阳性对照」。
;   ⚠️ 单位：p50 等是**每 tick 毫秒**（gate.py 表头口径），us_per_tick 是同一数值的 µs 形式。
;
; 等价性自校验：`equiv,tick_onedue_n<k>,diffs=0` —— 在确定性形态下分别跑合并版与旧版，
;   比对 triggerTimes / droppedTriggers / 发送次数。这是「为了快而改错」的兜底网。
;   （周期性等价性的主覆盖在 tests/test_ahk_executor/test_sender.ahk 的 Test_TickMerge_*）
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"
#Include "../../asd-tauri/src-tauri/ahk_executor/sender.ahk"

; ⚠️ 顶层不要再写 `global`；自动执行段的赋值本身就是全局（v2 里 global 只在函数内有效）
TICKS := 400          ; 每次采样内的 tick 数（一次采样 = TICKS 次 _ExecutePeriodic）
ROUNDS := 25          ; 采样轮数，取分位数
ALLDUE_TICKS := 120   ; alldue 单 tick 更贵（n=64 时 ~0.5ms），采样内减少 tick 数
ALLDUE_ROUNDS := 21

; -----------------------------------------------------------------
; 负载构造
; -----------------------------------------------------------------
BuildKeys(n) {
    pool := []
    i := 1
    while i <= 12 {
        pool.Push("F" . i)
        i++
    }
    i := 0
    while i <= 9 {
        pool.Push(Chr(48 + i))
        i++
    }
    i := 0
    while i <= 25 {
        pool.Push(Chr(97 + i))
        i++
    }
    keys := []
    i := 1
    while i <= n {
        keys.Push(pool[Mod(i - 1, pool.Length) + 1])
        i++
    }
    return keys
}

; onedue：第 1 个键的间隔取 1e6 ms（= 1e9 µs），使其 dueAt 恒为 base 且**不触发追帧**
BuildIntervalsOneDue(n) {
    ivs := [1000000]
    i := 2
    while i <= n {
        ivs.Push(10 + i * 0.001)
        i++
    }
    return ivs
}

BuildIntervals(n) {
    ivs := []
    i := 1
    while i <= n {
        ivs.Push(10 + i * 0.001)
        i++
    }
    return ivs
}

MakeState(gid, n, intervals) {
    if Sender._activeGroups.Has(gid)
        Sender._activeGroups.Delete(gid)
    Sender._StartGroup(gid)
    state := Sender._activeGroups[gid]
    state["mode"] := "periodic"
    state["keys"] := BuildKeys(n)
    state["intervals"] := intervals
    state["keyPressDuration"] := 0
    state["lastTriggerTimes"] := Map()
    return state
}

; ---- 形态一：只有第 1 个键到期 ----
; 返回 triggerTimes 的 Map 引用（调用方负责每 tick 把 [1] 重武装回 C）
SetupOneDue(gid, n, base) {
    state := MakeState(gid, n, BuildIntervalsOneDue(n))
    tt := Map()
    i := 1
    while i <= n {
        tt[i] := base + 5000000      ; 5 秒后 → 永不到期、永不被改写
        i++
    }
    state["lastTriggerTimes"] := tt
    return state
}

; ---- 形态二：全部到期 ----
SetupAllDue(gid, n, base) {
    state := MakeState(gid, n, BuildIntervals(n))
    tt := Map()
    i := 1
    while i <= n {
        tt[i] := base - 1000000      ; 1 秒前 → 必然到期（会走追帧分支）
        i++
    }
    state["lastTriggerTimes"] := tt
    return state
}

; 重武装：alldue 每 tick 把所有键按回过去（O(n)，约占单 tick 耗时 4%）
ReArmAll(tt, n, base) {
    i := 1
    while i <= n {
        tt[i] := base - 1000000
        i++
    }
}

; -----------------------------------------------------------------
; 采样
; -----------------------------------------------------------------
Stat(name, samples, keys, sends) {
    s := SortNums(samples)
    p50 := Pct(s, 0.50)
    BenchWrite("metric," . name
        . ",p50=" . Round(p50, 6)
        . ",p95=" . Round(Pct(s, 0.95), 6)
        . ",max=" . Round(s[s.Length], 6)
        . ",min=" . Round(s[1], 6)
        . ",mean=" . Round(Mean(s), 6)
        . ",n=" . s.Length
        . ",keys=" . keys
        . ",sends=" . sends
        . ",us_per_tick=" . Round(p50 * 1000, 3))
}

RunOneDue(n) {
    gid := "__bench_onedue_" . n
    base := HighResClock.NowUs()
    state := SetupOneDue(gid, n, base)
    tt := state["lastTriggerTimes"]
    C := base - 1000000000           ; dueAt 恒等于 base

    tt[1] := C
    Sender._ExecutePeriodic(gid)     ; 预热（首次会分配 _ivBuf 等）

    sends := CountSends(gid, tt, C, 1, 40)
    samples := []
    r := 1
    while r <= ROUNDS {
        tt[1] := C
        t0 := HighResNow()
        k := 1
        while k <= TICKS {
            tt[1] := C
            Sender._ExecutePeriodic(gid)
            k++
        }
        samples.Push((HighResNow() - t0) * 1000 / TICKS)   ; 毫秒/tick
        r++
    }
    Stat("tick_onedue_n" . n, samples, n, sends)
}

RunAllDue(n) {
    gid := "__bench_alldue_" . n
    base := HighResClock.NowUs()
    state := SetupAllDue(gid, n, base)
    tt := state["lastTriggerTimes"]

    ReArmAll(tt, n, base)
    Sender._ExecutePeriodic(gid)     ; 预热

    sends := CountSendsAll(gid, tt, n, base, 20)
    samples := []
    r := 1
    while r <= ALLDUE_ROUNDS {
        ReArmAll(tt, n, base)
        t0 := HighResNow()
        k := 1
        while k <= ALLDUE_TICKS {
            ReArmAll(tt, n, base)
            Sender._ExecutePeriodic(gid)
            k++
        }
        samples.Push((HighResNow() - t0) * 1000 / ALLDUE_TICKS)
        r++
    }
    Stat("tick_alldue_n" . n, samples, n, sends)
}

; ---- 发送次数统计（形态自校验，不计入耗时采样）----
CountSends(gid, tt, C, n, ticks) {
    global SEND_COUNT := 0
    Sender._sendHook := (key, st) => (SEND_COUNT := SEND_COUNT + 1)
    SEND_COUNT := 0
    k := 1
    while k <= ticks {
        tt[1] := C
        Sender._ExecutePeriodic(gid)
        k++
    }
    Sender._sendHook := (key, st) => 0
    return Round(SEND_COUNT / ticks, 3)
}

CountSendsAll(gid, tt, n, base, ticks) {
    global SEND_COUNT := 0
    Sender._sendHook := (key, st) => (SEND_COUNT := SEND_COUNT + 1)
    SEND_COUNT := 0
    k := 1
    while k <= ticks {
        ReArmAll(tt, n, base)
        Sender._ExecutePeriodic(gid)
        k++
    }
    Sender._sendHook := (key, st) => 0
    return Round(SEND_COUNT / ticks, 3)
}

; -----------------------------------------------------------------
; 等价性自校验：确定性形态下，合并版与旧版必须产生完全一致的状态
;
; 为什么能确定性比对：onedue 的 dueAt 恒等于 base（与真实时钟无关），
; 且 dueAt + interval 恒 > now → 不触发追帧分支 → triggerTimes 结果与何时执行无关。
; -----------------------------------------------------------------
RunOnceForEquiv(gid, n, base, flag) {
    origin := Sender.MERGE_TICK_SCAN
    Sender.MERGE_TICK_SCAN := flag
    try {
        state := SetupOneDue(gid, n, base)
        tt := state["lastTriggerTimes"]
        C := base - 1000000000
        tt[1] := C
        global SEND_COUNT := 0
        Sender._sendHook := (key, st) => (SEND_COUNT := SEND_COUNT + 1)
        SEND_COUNT := 0
        Sender._ExecutePeriodic(gid)
        Sender._sendHook := (key, st) => 0
        return Map("tt", tt, "sends", SEND_COUNT
                 , "dropped", state.Has("droppedTriggers") ? state["droppedTriggers"] : 0)
    } finally {
        Sender.MERGE_TICK_SCAN := origin
    }
}

CheckEquiv(n) {
    base := HighResClock.NowUs()
    m := RunOnceForEquiv("__bench_eq_m_" . n, n, base, true)
    l := RunOnceForEquiv("__bench_eq_l_" . n, n, base, false)
    diffs := 0
    if m["sends"] != l["sends"]
        diffs++
    if m["dropped"] != l["dropped"]
        diffs++
    i := 1
    while i <= n {
        mv := m["tt"].Has(i) ? m["tt"][i] : ""
        lv := l["tt"].Has(i) ? l["tt"][i] : ""
        if mv != lv
            diffs++
        i++
    }
    BenchWrite("equiv,tick_onedue_n" . n . ",diffs=" . diffs
        . ",merged_sends=" . m["sends"] . ",legacy_sends=" . l["sends"])
}

; -----------------------------------------------------------------
Main() {
    BenchInit("prod_tick")
    BenchWrite("# bench=prod_tick ahk=" . A_AhkVersion
        . " ticks_per_sample=" . TICKS . " samples=" . ROUNDS)

    ; ⚠️ 必须装 hook：否则会真的往系统发按键（CI 上后果不可控）
    Sender._sendHook := (key, st) => 0

    RunOneDue(64)
    RunOneDue(128)
    RunAllDue(64)

    CheckEquiv(64)
    CheckEquiv(128)

    BenchDone()
}

Main()
ExitApp(0)
