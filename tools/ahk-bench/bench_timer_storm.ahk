; =================================================================
; bench_timer_storm —— 定时器重排策略：唤醒次数 / CPU / 定时精度 三方权衡
;
; 原型：asd-tauri/src-tauri/ahk_executor/sender.ahk:470-474
;   if target - now > WAKE_LEAD_MS
;       SetTimer(..., -Max(1, Round(target - now - WAKE_LEAD_MS)))
;   WAKE_LEAD_MS = 28（sender.ahk:57）
;
; 背景硬事实：AHK 的 SetTimer 锁死 15.625ms 网格（SLEEP_INTERVAL 10 →
;   WM_TIMER → CheckScriptTimers 线性扫描）。所以「请求 1ms」实际也是 ~15.9ms。
;   本项目每个活动分组一个自重排定时器，周期 100ms，提前量 28ms。
;
; 三个变体：
;   old     —— Max(1,  remaining-LEAD)：进 lead 窗口前会多几次无意义唤醒
;   floor16 —— Max(16, remaining-LEAD)：减少唤醒，但可能请求值超过剩余提前量
;   new     —— remaining-LEAD < 16 时不再重排，直接忙等到点（消除多余唤醒）
;
; 关键：三种策略的**定时精度误差**必须一起看，不能只盯 CPU。
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

global LEAD := 28
global PERIOD := 100          ; ms，每组的执行周期
global GROUP_N := 8
global DUR := 4               ; 每个变体跑 4 秒

global gVariant := "old"
global gNextAt := []
global gFuncs := []
global gWork := 0
global gCb := 0
global gErrs := []
global gStopAt := 0
global gProbeLast := 0
global gProbeMax := 0
global gProbeCount := 0

ProbeTick() {
    global gProbeLast, gProbeMax, gProbeCount
    t := HighResNow()
    if gProbeLast > 0 {
        gap := (t - gProbeLast) * 1000
        if gap > gProbeMax
            gProbeMax := gap
    }
    gProbeLast := t
    gProbeCount++
}

DoWork(idx) {
    global gNextAt, gFuncs, gWork, gErrs, gStopAt, PERIOD, LEAD
    now := HighResNow()
    gErrs.Push(Abs((now - gNextAt[idx]) * 1000))
    gWork++
    gNextAt[idx] += PERIOD / 1000
    if now >= gStopAt
        return
    SetTimer(gFuncs[idx], -Max(1, Round((gNextAt[idx] - HighResNow()) * 1000 - LEAD)))
}

GroupTick(idx) {
    global gNextAt, gCb, gVariant, LEAD
    gCb++
    remaining := (gNextAt[idx] - HighResNow()) * 1000      ; ms
    if remaining > LEAD {
        d := Round(remaining - LEAD)
        if gVariant = "floor16"
            SetTimer(gFuncs[idx], -Max(16, d))
        else if gVariant = "new" && d >= 16
            SetTimer(gFuncs[idx], -d)
        else if gVariant = "old"
            SetTimer(gFuncs[idx], -Max(1, d))
        else {
            SleepUntil(gNextAt[idx])
            DoWork(idx)
        }
        return
    }
    SleepUntil(gNextAt[idx])
    DoWork(idx)
}

RunVariant(variant) {
    global gVariant, gNextAt, gFuncs, gWork, gCb, gErrs, gStopAt, GROUP_N, DUR
    global gProbeLast, gProbeMax, gProbeCount

    gVariant := variant
    gNextAt := []
    gFuncs := []
    gWork := 0
    gCb := 0
    gErrs := []
    gProbeLast := 0
    gProbeMax := 0
    gProbeCount := 0

    i := 1
    while i <= GROUP_N {
        gFuncs.Push(GroupTick.Bind(i))
        i++
    }

    t0 := HighResNow()
    gStopAt := t0 + DUR
    cpu0 := SnapCpuMs()

    i := 1
    while i <= GROUP_N {
        gNextAt.Push(t0 + 0.100)
        SetTimer(gFuncs[i], -10)
        i++
    }
    SetTimer(ProbeTick, 10)

    while HighResNow() < gStopAt
        Sleep(30)

    cpu1 := SnapCpuMs()
    wall := (HighResNow() - t0) * 1000

    i := 1
    while i <= GROUP_N {
        try SetTimer(gFuncs[i], 0)
        i++
    }
    SetTimer(ProbeTick, 0)

    if gErrs.Length > 0 {
        s := SortNums(gErrs)
        BenchWrite("timer," . variant
            . ",work=" . gWork
            . ",callbacks=" . gCb
            . ",wake_per_work=" . Round(gCb / ((gWork > 0) ? gWork : 1), 2)
            . ",cpu_ms=" . Round(cpu1 - cpu0, 1)
            . ",wall_ms=" . Round(wall, 1)
            . ",cpu_pct=" . Round((cpu1 - cpu0) / wall * 100, 1)
            . ",err_p50_ms=" . Round(Pct(s, 0.5), 3)
            . ",err_p95_ms=" . Round(Pct(s, 0.95), 3)
            . ",err_max_ms=" . Round(s[s.Length], 3)
            . ",probe_ticks=" . gProbeCount
            . ",probe_max_gap_ms=" . Round(gProbeMax, 1))
    } else {
        BenchWrite("timer," . variant . ",NO_DATA")
    }
}

Main() {
    BenchInit("timer_storm")
    BenchWrite("# bench_timer_storm —— 定时器重排策略对比")
    BenchWrite("# 每组周期 100ms，提前量 28ms，8 个并发分组，每变体 4 秒")
    BenchWrite("# err_* = 实际执行时刻相对计划时刻的绝对误差（ms）")
    BenchWrite("# probe_max_gap = 10ms 探针定时器观测到的主线程最大停顿（ms）")

    RunVariant("old")
    RunVariant("floor16")
    RunVariant("new")

    BenchDone()
}

Main()
ExitApp(0)
