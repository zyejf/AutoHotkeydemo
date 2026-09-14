; ----------------------------------------------------------------------------
; P3：精确定刻（QPC 忙等）对 AHK 主线程的占用代价
;
; 观测手段：一个 **10ms** 探针定时器记录自己的实际触发间隔（gap）。
;   基线 gap ≈ 15.6ms（受 15.625ms 网格限制）；gap 被拉长多少 == 主线程连续占用多久。
;   ⚠️ 不能用 1ms（引擎会把 period 1 改成 0 = 每 tick 都跑），那样堵塞后会「爆发式补跑」，
;      gap 中位数反而变成 0，指标失效。
;
; 阶段 1（停摆判定）：纯自旋 40ms / 100ms，数期间探针触发了几次。
; 阶段 2（策略对比）：周期 100ms，先 Sleep(100-lead) 再 QPC 自旋到目标时刻，
;   量化 lead 与「占用 / 精度」的 trade-off。现网 sender.ahk 用 WAKE_LEAD_MS=28。
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    ProbeInit("p3_occupancy")
    ProbeNote("P3 主线程占用：探针定时器 10ms；周期 100ms，30 周期/策略")
    ProbeWrite("phase1_自旋期间消息泵是否停摆")
    ProbeWrite("case,spin_ms,ticks_during_spin,expected_if_pumping")
    StarveTest("spin40", 40)
    StarveTest("spin100", 100)
    ProbeWrite("phase2_lead_tradeoff")
    ProbeWrite("strategy,spin_p50,spin_max,miss_pct,gap_p50,gap_p95,gap_max,occup_max,duty_pct,cycles")
    RunStrategy("lead0(纯Sleep)", 0)
    RunStrategy("lead8", 8)
    RunStrategy("lead16", 16)
    RunStrategy("lead20", 20)
    RunStrategy("lead28", 28)
    RunStrategy("lead40", 40)
    ProbeDone()
}

; 纯自旋 X ms，数期间探针触发次数
StarveTest(tag, spinMs) {
    global gTicks
    gTicks := []
    f := OnTick
    SetTimer(f, 10)
    t0 := HighResNow()
    SleepUntil(t0 + spinMs / 1000.0)
    SetTimer(f, 0)
    ProbeWrite(tag . "," . spinMs . "," . gTicks.Length . ","
        . Round(spinMs / 15.625, 1))
}

RunStrategy(tag, lead) {
    global gTicks
    cycles := 30
    periodMs := 100

    gTicks := []
    f := OnTick
    SetTimer(f, 10)

    spins := []
    misses := 0
    base := HighResNow()
    i := 1
    while i <= cycles {
        target := base + (i * periodMs) / 1000.0
        Sleep(periodMs - lead)
        retAt := HighResNow()
        spinMs := (target - retAt) * 1000
        if spinMs < 0 {
            if lead > 0
                misses += 1
            spinMs := 0
        } else {
            SleepUntil(target)
        }
        spins.Push(spinMs)
        i += 1
    }
    SetTimer(f, 0)

    gaps := []
    k := 2
    while k <= gTicks.Length {
        gaps.Push((gTicks[k] - gTicks[k - 1]) * 1000)
        k += 1
    }
    totalMs := (HighResNow() - base) * 1000
    spinSum := 0
    for s in spins
        spinSum += s
    duty := totalMs > 0 ? (spinSum / totalMs * 100) : 0
    ; 扣除 15.625ms 网格后的「净占用」
    occMax := _Max(gaps) - 15.625
    if occMax < 0
        occMax := 0

    ProbeWrite(tag . "," . Round(_Pct(spins, 0.5), 2) . "," . Round(_Max(spins), 2) . ","
        . Round(misses / cycles * 100, 1) . ","
        . Round(_Pct(gaps, 0.5), 2) . "," . Round(_Pct(gaps, 0.95), 2) . ","
        . Round(_Max(gaps), 2) . "," . Round(occMax, 2) . ","
        . Round(duty, 1) . "," . cycles)
}

OnTick() {
    global gTicks
    gTicks.Push(HighResNow())
}

Main()
ExitApp
