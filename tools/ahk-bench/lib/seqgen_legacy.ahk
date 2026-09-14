; =================================================================
; seqgen_legacy.ahk —— 旧实现复刻（对照基线，勿用于生产）
;
; 逐行对齐 asd-tauri/src-tauri/ahk_executor/sender.ahk 的现有逻辑，仅去掉
; 「定时器唤醒 / SleepUntil 阻塞 / 真实发键」三件与序列生成无关的事。
; 保留的三处**原样复刻**特征是本次要量化的差异来源：
;   ① 时刻用 **ms 浮点**（HighResClock.Now() 返回 c/freq*1000，double）
;   ② 每 tick 对 keys 做 **4 次全遍历**，且同一轮里 _IntervalOf 被算 3 次
;      （sender.ahk:462 / :483 / :522）
;   ③ 分桶用 **浮点 dueAt 当 Map 键** → 数学同刻的键可能被拆成两桶
;
; ⚠️ 2026-09-14 修正：4 次遍历此前只复刻了中间 2 次（系统性低估 old、把收益压到
; 1.48×）。现已补齐 T1(EnsureBaseline) 与 T4(MinRemainingUs)，完整口径下收益为
; 2.02× / 1.71× / 1.62×（K=8/24/64），与 bench_tick_traversal 的 1.80~1.96× 互相印证。
;
; 接口与 seqgen.ahk 的新策略保持一致（Init / NextDueUs / Collect），
; 以便同一个 EventWindow 驱动两者做同口径对比。
; ⚠️ 普通 Object 不支持 obj["prop"]，一律用点号。
; =================================================================
; ⚠️ 本文件不自行 #Include seqgen.ahk：跨目录的相对 #Include 语义（相对 A_ScriptDir
; 还是相对包含者所在目录）不直观，统一由使用方在同目录下按 lib\ 前缀引入两者：
;     #Include "lib\seqgen.ahk"
;     #Include "lib\seqgen_legacy.ahk"
#Requires AutoHotkey v2.0

global LEGACY_MIN_INTERVAL_MS := 10       ; sender.ahk:48
global LEGACY_EPSILON_MS      := 0.5      ; sender.ahk:60

; 复刻 Sender._IntervalOf（越界默认 50ms，下限夹紧 10ms）
LegacyIntervalOf(intervals, i) {
    global LEGACY_MIN_INTERVAL_MS
    interval := i <= intervals.Length ? intervals[i] : 50
    return interval < LEGACY_MIN_INTERVAL_MS ? LEGACY_MIN_INTERVAL_MS : interval
}

; 复刻 Sender._DelayOf（越界默认 100ms，下限夹紧 10ms）
LegacyDelayOf(delays, i) {
    global LEGACY_MIN_INTERVAL_MS
    delay := i <= delays.Length ? delays[i] : 100
    return delay < LEGACY_MIN_INTERVAL_MS ? LEGACY_MIN_INTERVAL_MS : delay
}

; ---------------------------------------------------------------
; 旧 periodic：sender.ahk:442-532
; ---------------------------------------------------------------
class LegacyPeriodicPolicy {
    static Name => "periodic(legacy)"

    static Init(keyCount, intervalsMs, originMs) {
        ; 生产在首个 tick 的「第 1 次遍历」里把缺失的基准填成 now；
        ; 这里在 Init 时预置为 originMs，等价于首次 tick 恰好发生在 origin。
        tt := Map()
        i := 1
        while i <= keyCount {
            tt[i] := originMs
            i++
        }
        return {tt: tt, intervals: intervalsMs, n: keyCount, dropped: 0, emitted: 0}
    }

    ; 复刻「第 1 次遍历」sender.ahk:449-452：为首次出现的键建立基准时刻。
    ; 原型 Init 已把 tt 预置为 origin，所以这里不会有键真的缺失 —— 但生产每 tick
    ; 都要付这 n 次 Has 判断（Map 查找），量化时必须计入。
    static EnsureBaseline(st, nowUs) {
        nowMs := nowUs / 1000
        i := 1
        while i <= st.n {
            if !st.tt.Has(i)
                st.tt[i] := nowMs
            i++
        }
    }

    ; 复刻「第 2 次遍历」求 target
    static NextDueUs(st) {
        global SEQGEN_NO_DUE
        if st.n = 0
            return SEQGEN_NO_DUE
        best := 0
        i := 1
        while i <= st.n {
            t := st.tt[i] + LegacyIntervalOf(st.intervals, i)
            if best = 0 || t < best
                best := t
            i++
        }
        return Round(best * 1000)
    }

    ; 复刻「第 3 次遍历」分桶 + 推进。入参/出参统一用微秒，内部换算回 ms 浮点。
    static Collect(st, nowUs, epsilonUs := "", maxCatchup := "") {
        global LEGACY_EPSILON_MS, SEQGEN_NO_DUE
        nowMs := nowUs / 1000
        outDue := []
        outKey := []
        i := 1
        while i <= st.n {
            interval := LegacyIntervalOf(st.intervals, i)
            dueAt := st.tt[i] + interval
            if nowMs < dueAt - LEGACY_EPSILON_MS {
                i++
                continue
            }
            outDue.Push(Round(dueAt * 1000))
            outKey.Push(i)

            ; sender.ahk:493-506 的原样推进（无 MAX_CATCHUP 限制）
            last := dueAt
            next := dueAt + interval
            if next <= nowMs {
                steps := Floor((nowMs - next) / interval) + 1
                next := next + steps * interval
                st.dropped := st.dropped + steps
                last := next - interval
            }
            st.tt[i] := last
            st.emitted := st.emitted + 1
            i++
        }
        return {dueUs: outDue, keyIdx: outKey}
    }

    ; 复刻「第 4 次遍历」sender.ahk:518-522：发送后按推进过的基准重算最小剩余时间。
    ; 这是 LegacyIntervalOf 在同一轮里的**第 3 个调用点**（:522），也是旧实现
    ; 每 tick 第 4 次全量遍历 keys。新实现把它融进第 3 次遍历（见 seqgen.ahk）。
    static MinRemainingUs(st, nowUs) {
        nowMs := nowUs / 1000
        minRemaining := 0x7FFFFFFF
        i := 1
        while i <= st.n {
            remaining := st.tt[i] + LegacyIntervalOf(st.intervals, i) - nowMs
            if remaining < minRemaining
                minRemaining := remaining
            i++
        }
        return Round(minRemaining * 1000)
    }

    ; 统一契约用的零分配包装。旧实现**故意**保留 Collect 的两数组 + 一对象分配，
    ; 那是它原本就有的开销，量化时要如实计入。
    static CollectInto(st, nowUs, epsilonUs, maxCatchup, outDue, outKey) {
        ev := LegacyPeriodicPolicy.Collect(st, nowUs, epsilonUs, maxCatchup)
        i := 1
        while i <= ev.dueUs.Length {
            outDue.Push(ev.dueUs[i])
            outKey.Push(ev.keyIdx[i])
            i++
        }
        return ev.dueUs.Length
    }
}

; ---------------------------------------------------------------
; 旧 sequence：sender.ahk:542-597
; ---------------------------------------------------------------
class LegacySequencePolicy {
    static Name => "sequence(legacy)"

    static Init(keyCount, delaysMs, originMs) {
        return {step: 1, nextMs: originMs, delays: delaysMs
              , n: keyCount, dropped: 0, emitted: 0}
    }

    static NextDueUs(st) {
        global SEQGEN_NO_DUE
        if st.n = 0
            return SEQGEN_NO_DUE
        return Round(st.nextMs * 1000)
    }

    ; sequence 生产代码不遍历 keys（见 seqgen.ahk 同名方法注释），两次「遍历」都不存在；
    ; 这里给出 O(1) 实现，只为让基准能统一驱动。
    static EnsureBaseline(st, nowUs) {
        return
    }

    static MinRemainingUs(st, nowUs) {
        return Round((st.nextMs - nowUs / 1000) * 1000)
    }

    static Collect(st, nowUs, epsilonUs := "", maxCatchup := "") {
        global LEGACY_EPSILON_MS
        nowMs := nowUs / 1000
        outDue := []
        outKey := []
        if st.n = 0
            return {dueUs: outDue, keyIdx: outKey}
        if nowMs < st.nextMs - LEGACY_EPSILON_MS
            return {dueUs: outDue, keyIdx: outKey}

        step := st.step
        if step > st.n
            step := 1
        dueAt := st.nextMs
        outDue.Push(Round(dueAt * 1000))
        outKey.Push(step)
        st.emitted := st.emitted + 1

        nextStep := Mod(step, st.n) + 1
        nextDelay := LegacyDelayOf(st.delays, nextStep)

        advance := 1
        next := dueAt + nextDelay
        if next <= nowMs {
            skipped := Floor((nowMs - next) / nextDelay) + 1
            next := next + skipped * nextDelay
            st.dropped := st.dropped + skipped
            advance := advance + skipped
        }
        st.nextMs := next
        st.step := Mod(step - 1 + advance, st.n) + 1
        return {dueUs: outDue, keyIdx: outKey}
    }

    static CollectInto(st, nowUs, epsilonUs, maxCatchup, outDue, outKey) {
        ev := LegacySequencePolicy.Collect(st, nowUs, epsilonUs, maxCatchup)
        i := 1
        while i <= ev.dueUs.Length {
            outDue.Push(ev.dueUs[i])
            outKey.Push(ev.keyIdx[i])
            i++
        }
        return ev.dueUs.Length
    }
}

; ---------------------------------------------------------------
; 复刻生产的浮点分桶：Map 的键就是浮点 dueAt（ms）。
; ⚠️ 这是本文件存在的意义 —— 用来**量化**「数学同刻的键被拆成两个桶」。
; ---------------------------------------------------------------
LegacyBucketsMs(ev) {
    m := Map()
    i := 1
    while i <= ev.dueUs.Length {
        ; 换回 ms 浮点：微秒整数 /1000 后仍可能与另一路径算出的值差 1 ULP
        k := ev.dueUs[i] / 1000
        if !m.Has(k)
            m[k] := []
        m[k].Push(ev.keyIdx[i])
        i++
    }
    return m
}

; =================================================================
; 分桶漂移对照（两个键间隔 1:3，数学上每 3 个 tick 应当同刻一次）
;
; ⚠️ 第一版写错了：tick 网格取 99.9ms（= 慢键周期），于是快键每次都**落后 2 步**，
;    被追赶逻辑（steps>0 → 只物化最老的那一步并跳过中间步）吃掉，
;    两个键的到期时刻永远落不到同一个 tick —— old/new 都报 split=300、merged=0，
;    什么都没证明。教训：**演示场景必须先确认「同刻」真的会落在同一次 Collect 里**。
;
; 修正：tick 网格 = 33.333ms（= 快键周期，足够密 → 永不触发追赶），
;       于是 k=3,6,9… 时两键同时到期，可以直接数桶：
;         旧 float ms：(33.333+33.333)+33.333 ≠ 99.999（末位不同）→ 拆成两桶
;         新 整数 µs： 33333+33333+33333 = 99999 精确相等   → 合成一桶
; opp = 「两键同时到期」的机会数（= ticks/3），merged+split 应当等于 opp。
; =================================================================
LegacyBucketDriftDemo(ticks) {
    intervals := [33.333, 99.999]
    tt := [0.0, 0.0]
    grid := 33.333
    merged := 0
    split := 0
    opp := 0
    k := 1
    while k <= ticks {
        nowMs := grid * k
        buckets := Map()
        due := 0
        i := 1
        while i <= 2 {
            dueAt := tt[i] + intervals[i]
            if dueAt <= nowMs + 0.5 {          ; 复刻 TIMING_EPSILON_MS=0.5
                if !buckets.Has(dueAt)
                    buckets[dueAt] := []
                buckets[dueAt].Push(i)
                tt[i] := dueAt                 ; 单步推进（网格够密，不触发追赶）
                due++
            }
            i++
        }
        if due = 2 {
            opp++
            if buckets.Count = 1
                merged++
            else
                split++
        }
        k++
    }
    return {merged: merged, split: split, opp: opp}
}

; 新实现（整数微秒）在同一场景下的对照
NewBucketDriftDemo(ticks) {
    st := PeriodicPolicy.Init(2, [33333, 99999], 0)
    grid := 33333
    merged := 0
    split := 0
    opp := 0
    k := 1
    while k <= ticks {
        nowUs := grid * k
        outD := []
        outK := []
        PeriodicPolicy.CollectInto(st, nowUs, "", "", outD, outK)
        if outD.Length = 2 {
            opp++
            if outD[1] = outD[2]
                merged++
            else
                split++
        }
        k++
    }
    return {merged: merged, split: split, opp: opp}
}
