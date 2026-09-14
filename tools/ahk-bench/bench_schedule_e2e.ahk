; =================================================================
; bench_schedule_e2e —— L3 端到端基准：真实时钟 + mock 发送钩子
;
; 与 L1（bench_seqgen.ahk）的区别：
;   L1 = 纯生成，虚拟时钟瞬间推进，回答「算法本身多快」
;   L3 = 真实 QPC + 忙等精确定刻 + mock 发送，回答「挂到真实调度里还行不行」
;
; ⚠️ 不发真键。发送钩子只记录时刻 —— SendLevel(10) 会把 SendInput 判成物理键
;    而自触发死循环（已实测，见 MEMORY.md）。
;
; 指标定义（第一版写错过一次，别改回去）：
;   e2e_us      实际唤醒时刻 − 计划时刻（≥0）。受 Sleep 网格支配，是「定刻精度」，
;               不是「算法快慢」；本文件用 LEAD_US=10ms 的忙等，非生产的 28ms。
;   collect_us  单次 CollectInto 的真实耗时。这是 L3 真正的新信号：
;               它在 tick 内执行，直接挤占 AHK 主线程。
;   occupy_us   **从进入忙等段到 Collect 结束**的连续时长。
;               这段时间里 AHK 主线程不处理任何其它定时器/热键/IPC。
;               若一直在粗睡（未进忙等）则只算 Collect。
;               ⚠️ 第一版从 SleepUntil 之前就开始计时，量到的是「整个等待」
;                  （≈ 一个间隔），毫无意义 —— 已修。
;
; 口径：
;   · 首 tick 含 100ms 预热，**不计入任何统计**（第一版把它算进去，
;     于是 occupy_max 出现 360ms 的假离群）
;   · 用 p50 判定，max 单列不当判定依据
;   · periodic 每 tick 约 2.37 事件 → 1000 事件只有约 420 tick，P999 样本不足
;     （需 ≥1000），故只报 p50/p95/p99/max
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"
#Include "lib\seqgen.ahk"
#Include "lib\seqgen_legacy.ahk"

; 间隔/延时的选择：既要真实（≥ MIN_INTERVAL 10ms）又要让一轮跑得完。
; periodic 8 键 40..320ms → 合计触发率 0.068/ms → 1000 事件约 14.7s
; sequence 8 步 15..50ms  → 平均 32.5ms       → 1000 事件约 32.5s
global E2E_INTERVALS_US := [40000, 80000, 120000, 160000, 200000, 240000, 280000, 320000]
global E2E_DELAYS_US    := [15000, 20000, 25000, 30000, 35000, 40000, 45000, 50000]
global E2E_KEY_COUNT    := 8
global E2E_WARMUP_US    := 100000
global E2E_LEAD_US      := 10000      ; 忙等提前量（生产是 28ms，见下注）

; ---------------- 真实时钟（µs，整数） ----------------
class QpcClock {
    NowUs() {
        static freq := 0
        if !freq
            DllCall("QueryPerformanceFrequency", "Int64*", &freq)
        DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
        return (c * 1000000) // freq
    }
}

; 忙等到 targetUs，返回 {nowUs, busy0}，busy0 是进入忙等段的时刻（秒），
; 未进忙等则返回 0（说明一直在粗睡，主线程是可被 OS 调度的）。
SleepUntilUs(targetUs, leadUs) {
    clk := QpcClock()
    busy0 := 0
    loop {
        nowUs := clk.NowUs()
        if nowUs >= targetUs
            return {nowUs: nowUs, busy0: busy0}
        dUs := targetUs - nowUs
        if dUs > leadUs
            Sleep(Floor((dUs - leadUs) / 1000))
        else {
            if busy0 = 0
                busy0 := HighResNow()
            Sleep(0)
        }
    }
}

; ---------------- 主流程 ----------------
RunE2E(mode, impl, wantEvents) {
    clk := QpcClock()
    guard := MonotonicGuard(clk)

    if mode = "periodic" {
        st := (impl = "old")
            ? LegacyPeriodicPolicy.Init(E2E_KEY_COUNT, [40, 80, 120, 160, 200, 240, 280, 320], 0)
            : PeriodicPolicy.Init(E2E_KEY_COUNT, E2E_INTERVALS_US, 0)
        p := (impl = "old") ? LegacyPeriodicPolicy : PeriodicPolicy
    } else {
        st := (impl = "old")
            ? LegacySequencePolicy.Init(E2E_KEY_COUNT, [15, 20, 25, 30, 35, 40, 45, 50], 0)
            : SequencePolicy.Init(E2E_KEY_COUNT, E2E_DELAYS_US, 0)
        p := (impl = "old") ? LegacySequencePolicy : SequencePolicy
    }

    ; origin = 现在 + 预热；之后所有计划时刻都以它为基准
    originUs := clk.NowUs() + E2E_WARMUP_US
    if mode = "periodic" {
        i := 1
        while i <= E2E_KEY_COUNT {
            if impl = "old"
                st.tt[i] := originUs / 1000
            else
                st.bases[i] := originUs
            i++
        }
    } else {
        if impl = "old"
            st.nextMs := originUs / 1000
        else
            st.nextUs := originUs
    }

    e2e := []
    collectUs := []
    occupyUs := []
    sent := 0
    ticks := 0
    warm := true                    ; 首 tick 含预热，不计入统计
    wall0 := HighResNow()
    cpu0 := SnapCpuMs()

    while sent < wantEvents {
        duePlanned := p.NextDueUs(st)
        r := SleepUntilUs(duePlanned, E2E_LEAD_US)
        nowUs := guard.NowUs()

        outD := []
        outK := []
        c0 := HighResNow()
        p.CollectInto(st, nowUs, "", "", outD, outK)
        c1 := HighResNow()

        if !warm {
            collectUs.Push((c1 - c0) * 1000000)
            ; occupy = 忙等段起点（或唤醒点）→ Collect 结束
            occupyUs.Push((c1 - (r.busy0 = 0 ? c0 : r.busy0)) * 1000000)
        }

        i := 1
        while i <= outD.Length && sent < wantEvents {
            if !warm
                e2e.Push(nowUs - outD[i])       ; ≥0：实际唤醒 − 计划时刻
            sent++
            i++
        }
        warm := false
        ticks++
        if ticks > wantEvents * 4 + 4096
            break
    }
    wall := (HighResNow() - wall0) * 1000
    cpuMs := SnapCpuMs() - cpu0

    se := SortNums(e2e)
    sc := SortNums(collectUs)
    so := SortNums(occupyUs)
    BenchWrite("e2e,mode=" . mode . ",impl=" . impl
        . ",events=" . sent . ",ticks=" . ticks
        . ",e2e_p50_us=" . Round(Pct(se, 0.50), 1)
        . ",e2e_p95_us=" . Round(Pct(se, 0.95), 1)
        . ",e2e_p99_us=" . Round(Pct(se, 0.99), 1)
        . ",e2e_max_us=" . Round(se[se.Length], 1)
        . ",collect_p50_us=" . Round(Pct(sc, 0.50), 2)
        . ",collect_p95_us=" . Round(Pct(sc, 0.95), 2)
        . ",collect_p99_us=" . Round(Pct(sc, 0.99), 2)
        . ",occupy_p50_us=" . Round(Pct(so, 0.50), 1)
        . ",occupy_p99_us=" . Round(Pct(so, 0.99), 1)
        . ",occupy_max_us=" . Round(so[so.Length], 1)
        . ",dropped=" . st.dropped
        . ",wall_ms=" . Round(wall, 1)
        . ",cpu_pct=" . Round(cpuMs / wall * 100, 2))
}

Main() {
    BenchInit("schedule_e2e")
    BenchWrite("# bench_schedule_e2e —— L3 端到端：真实 QPC + mock 发送钩子，不发真键")
    BenchWrite("# e2e_*_us   = 实际唤醒时刻 − 计划时刻（受 Sleep 网格支配，非算法快慢）")
    BenchWrite("# collect_*_us = 单次 CollectInto 真实耗时（tick 内，挤占主线程）")
    BenchWrite("# occupy_*_us  = 忙等段起点 → Collect 结束，主线程连续不可用的时长")
    BenchWrite("# 首 tick 含 100ms 预热，不计入统计；LEAD_US=10000（生产是 28000）")

    for mode in ["periodic", "sequence"] {
        RunE2E(mode, "old", 1000)
        RunE2E(mode, "new", 1000)
    }
    BenchDone()
}

try Main()
catch as e {
    try FileAppend("FATAL," . StrReplace(e.Message, ",", ";") . ",line=" . e.Line . "`n"
        , BENCH_FILE, "UTF-8")
    BenchDone()
}
ExitApp(0)
