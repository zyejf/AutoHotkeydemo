; ----------------------------------------------------------------------------
; P2：定时器网格根因 + timeBeginPeriod(1) 对照实验
;
; 四段：
;   A  A_TickCount 的步进（决定「能测多细」）
;   B  SetTimer(fn, 1) 的实际间隔分布（基线）
;   C  Sleep(D) 实际时长 vs 请求 D（D = 1/5/10/15/16/20/21/25）
;   D  进程内 timeBeginPeriod(1) 之后重跑 B、C，再 timeEndPeriod(1) 复原
;
; 注意：timeBeginPeriod 是**全系统**副作用，本探针严格控制在一分钟内且必须配对
;       timeEndPeriod；若中途异常退出，系统会在进程结束时由 OS 回收该请求。
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    global gTicks
    ProbeInit("p2_timer")
    ProbeNote("P2 定时器网格 + timeBeginPeriod 对照")

    ProbeWrite("phase,start")
    ; ---- A. A_TickCount 步进 ------------------------------------------------
    last := A_TickCount
    steps := []
    while steps.Length < 100 {
        v := A_TickCount
        if v != last {
            steps.Push(v - last)
            last := v
        }
    }
    ProbeWrite("phase,A_done")
    ProbeWrite("metric,unit,p50,p95,max,min,n")
    ProbeWrite("A_TickCount_step,ms," . Round(_Pct(steps, 0.5), 3) . ","
        . Round(_Pct(steps, 0.95), 3) . "," . Round(_Max(steps), 3) . ","
        . Round(_Min(steps), 3) . "," . steps.Length)

    ; ---- B/C 基线 -----------------------------------------------------------
    RunTimerProbe("baseline", 3000)
    ProbeWrite("phase,B_done")
    RunSleepProbe("baseline", 40)
    ProbeWrite("phase,C_done")

    ; ---- D. timeBeginPeriod(1) 对照 ----------------------------------------
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    RunTimerProbe("tbp1", 3000)
    ProbeWrite("phase,D_timer_done")
    RunSleepProbe("tbp1", 40)
    ProbeWrite("phase,D_sleep_done")
    DllCall("winmm\timeEndPeriod", "UInt", 1)

    ; ---- E. 复原确认 --------------------------------------------------------
    RunTimerProbe("after_tbp1", 1500)
    ProbeWrite("phase,E_done")

    ProbeDone()
}

; SetTimer(fn,1) 的间隔分布。AHK 源码里 mPeriod==1 会被改成 0（= 每 tick 都跑）
RunTimerProbe(tag, ms := 8000) {
    global gTicks
    gTicks := []
    f := OnTick
    SetTimer(f, 1)
    Sleep(ms)
    SetTimer(f, 0)
    gaps := []
    i := 2
    while i <= gTicks.Length {
        gaps.Push((gTicks[i] - gTicks[i - 1]) * 1000)
        i += 1
    }
    if gaps.Length > 0 {
        ProbeWrite("SetTimer_1ms_gap,ms[" . tag . "]," . Round(_Pct(gaps, 0.5), 3) . ","
            . Round(_Pct(gaps, 0.95), 3) . "," . Round(_Max(gaps), 3) . ","
            . Round(_Min(gaps), 3) . "," . gaps.Length)
        ; 直方图：0-2 / 2-8 / 8-14 / 14-17 / 17-25 / 25-50 / >50
        b := [0, 0, 0, 0, 0, 0, 0]
        for g in gaps {
            if (g < 2)
                b[1] += 1
            else if (g < 8)
                b[2] += 1
            else if (g < 14)
                b[3] += 1
            else if (g < 17)
                b[4] += 1
            else if (g < 25)
                b[5] += 1
            else if (g < 50)
                b[6] += 1
            else
                b[7] += 1
        }
        ProbeWrite("hist_" . tag . ",<2|2-8|8-14|14-17|17-25|25-50|>50,"
            . b[1] . "|" . b[2] . "|" . b[3] . "|" . b[4] . "|" . b[5] . "|" . b[6] . "|" . b[7])
    } else {
        ProbeWrite("SetTimer_1ms_gap,ms[" . tag . "],NOSAMPLE,0,0,0,0")
    }
}

; Sleep(D) 实际时长 vs 请求值
RunSleepProbe(tag, n := 40) {
    for D in [1, 5, 10, 15, 16, 20, 21, 25] {
        got := []
        Loop n {
            t0 := HighResNow()
            Sleep(D)
            got.Push((HighResNow() - t0) * 1000)
        }
        ProbeWrite("Sleep_req_" . D . ",ms[" . tag . "]," . Round(_Pct(got, 0.5), 3) . ","
            . Round(_Pct(got, 0.95), 3) . "," . Round(_Max(got), 3) . ","
            . Round(_Min(got), 3) . "," . got.Length)
    }
}

OnTick() {
    global gTicks
    gTicks.Push(HighResNow())
}

Main()
ExitApp
