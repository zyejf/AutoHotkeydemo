; =================================================================
; bench_seqgen —— L1 纯生成基准：四种模式 × 100/1K/10K/100K 事件量
;
; 分五个阶段：
;   A 规模吞吐   N ∈ {100,1K,10K,100K}，测 ops/s、内存峰值、CPU 占用
;   B 每 tick 时延 固定 2000 事件，逐 tick 打点 → P50/P95/P99/P999 + max-min
;   C enhanced 别名 同参数跑 enhanced_* 与基础版，验证输出逐位相同
;   D 新旧等价性  同输入下 old/new 的计划时刻序列必须一致
;   E 分桶漂移    浮点 ms 累加 vs 整数 us，量化「同刻被拆桶」
;   F 键数扫描    8 / 24 / 64 键下的每 tick 耗时 p50（对齐方案 C 的 M8/M9）
;
; 方法学说明（与 stats 口径强相关，别改）：
;   · P999 需要 ≥1000 样本，故 B 阶段固定跑到 2000 个事件
;   · 每 tick 打点含 QPC 调用开销，单列 overhead 行供扣减参考
;   · 吞吐用 p50（中位数）而非均值，避免被 GC/调度离群点带偏
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"
#Include "lib\seqgen.ahk"
#Include "lib\seqgen_legacy.ahk"

global K8_INTERVALS_US := [50000, 75000, 100000, 125000, 150000, 175000, 200000, 225000]
global K8_DELAYS_US    := [100000, 120000, 140000, 160000, 180000, 200000, 220000, 240000]
global KEY_COUNT       := 8
global ORIGIN_US       := 1000000

; ---------- 用给定实现生成 n 个事件，返回 {got, ticks} ----------
GenRun(policy, state, n, rngAmp := 0, seed := 1) {
    vc := VirtualClock(ORIGIN_US)
    w := EventWindow(policy, state, vc)
    plan := ""
    if rngAmp > 0 {
        rng := Lcg(seed)
        plan := ((due, t) => due + rng.Jitter(rngAmp))
    }
    r := w.Fill(n, plan)
    return r
}

; ---------- 构造状态 ----------
MakeState(impl, mode, keyCount) {
    if mode = "periodic" {
        if impl = "old"
            return LegacyPeriodicPolicy.Init(keyCount, [50, 75, 100, 125, 150, 175, 200, 225], ORIGIN_US / 1000)
        return PeriodicPolicy.Init(keyCount, K8_INTERVALS_US, ORIGIN_US)
    }
    if impl = "old"
        return LegacySequencePolicy.Init(keyCount, [100, 120, 140, 160, 180, 200, 220, 240], ORIGIN_US / 1000)
    return SequencePolicy.Init(keyCount, K8_DELAYS_US, ORIGIN_US)
}

PolicyOf(impl, mode) {
    if mode = "periodic"
        return impl = "old" ? LegacyPeriodicPolicy : PeriodicPolicy
    return impl = "old" ? LegacySequencePolicy : SequencePolicy
}

; ---------- A 阶段：规模吞吐 ----------
RunScale(mode, n, impl, rounds) {
    p := PolicyOf(impl, mode)
    samples := []
    cpu0 := SnapCpuMs()
    t0 := HighResNow()
    r := 1
    while r <= rounds {
        st := MakeState(impl, mode, KEY_COUNT)
        t := HighResNow()
        GenRun(p, st, n)
        samples.Push((HighResNow() - t) * 1000)     ; ms
        r++
    }
    wall := (HighResNow() - t0) * 1000
    cpuMs := SnapCpuMs() - cpu0

    ; 内存：单独生成一次并在持有结果时采样
    stM := MakeState(impl, mode, KEY_COUNT)
    m0 := SnapMemKB()
    hold := GenRun(p, stM, n)
    m1 := SnapMemKB()
    ; 阻止被优化掉
    _n := hold.dueUs.Length

    s := SortNums(samples)
    p50 := Pct(s, 0.50)
    ops := p50 > 0 ? (n / (p50 / 1000)) : 0
    BenchWrite("scale,mode=" . mode . ",impl=" . impl . ",n=" . n
        . ",p50_ms=" . Round(p50, 4)
        . ",p95_ms=" . Round(Pct(s, 0.95), 4)
        . ",ops_per_s=" . Round(ops, 1)
        . ",us_per_event=" . Round(p50 * 1000 / n, 5)
        . ",mem_kb=" . (m1[2] - m0[2])
        . ",cpu_pct=" . Round(cpuMs / wall * 100, 2)
        . ",rounds=" . rounds)
    return p50
}

; ---------- B 阶段：每 tick 时延分布（≥1000 样本） ----------
RunTickLatency(mode, impl, wantEvents, ampUs := 0, keyCount := 0, noSort := false) {
    global SEQGEN_NO_DUE
    if keyCount = 0
        keyCount := KEY_COUNT
    p := PolicyOf(impl, mode)
    st := MakeState(impl, mode, keyCount)
    if noSort
        st.noSort := true      ; 仅 G 阶段消融用
    vc := VirtualClock(ORIGIN_US)
    guard := MonotonicGuard(vc)
    rng := Lcg(11)
    lat := []
    nd := []
    bs := []
    rm := []
    tt := []
    got := 0
    spins := 0
    sinkD := []
    sinkK := []
    while got < wantEvents {
        ; ⚠️ 口径必须与 A 阶段一致：
        ;   1) 计时对象用 CollectInto（A 阶段走的就是它）。第一版这里用 Collect，
        ;      而 old 的 CollectInto = Collect + 拷贝循环，于是 B 系统性低估了 old。
        ;   2) NextDueUs 单独计时 —— A 阶段的收益被怀疑主要来自这里，不拆开就只能是猜测。
        ;   3) 2026-09-14 补齐：生产每 tick 对 keys 有 **4 次**遍历（sender.ahk
        ;      :449 / :457 / :476 / :518），只测中间两次会系统性低估 old。
        ;      现在四个都测，并把每 tick 四项之和单独入样（不能用 p50 相加，
        ;      分位数不可加）。
        nowUs := guard.NowUs()

        b0 := HighResNow()
        p.EnsureBaseline(st, nowUs)
        b1 := HighResNow()
        db := (b1 - b0) * 1000000
        bs.Push(db)

        n0 := HighResNow()
        due := p.NextDueUs(st)
        n1 := HighResNow()
        dn := (n1 - n0) * 1000000
        nd.Push(dn)
        if due = SEQGEN_NO_DUE
            break
        target := ampUs > 0 ? due + rng.Jitter(ampUs) : due
        vc.Set(target)
        nowUs := guard.NowUs()
        sinkD.Length := 0
        sinkK.Length := 0
        t0 := HighResNow()
        p.CollectInto(st, nowUs, "", "", sinkD, sinkK)
        t1 := HighResNow()
        dc := (t1 - t0) * 1000000          ; µs
        lat.Push(dc)

        r0 := HighResNow()
        p.MinRemainingUs(st, nowUs)
        r1 := HighResNow()
        dr := (r1 - r0) * 1000000
        rm.Push(dr)

        tt.Push(db + dn + dc + dr)
        got += sinkD.Length
        spins++
        if spins > wantEvents * 8 + 4096
            break
    }
    s := SortNums(lat)
    sn := SortNums(nd)
    sb := SortNums(bs)
    sr := SortNums(rm)
    stt := SortNums(tt)
    BenchWrite("tick,mode=" . mode . ",impl=" . impl . ",amp_us=" . ampUs
        . ",keys=" . keyCount
        . ",sort=" . (noSort ? "off" : "on")
        . ",n=" . s.Length
        . ",collect_p50_us=" . Round(Pct(s, 0.50), 3)
        . ",collect_p95_us=" . Round(Pct(s, 0.95), 3)
        . ",collect_p99_us=" . Round(Pct(s, 0.99), 3)
        . ",collect_p999_us=" . Round(Pct(s, 0.999), 3)
        . ",collect_max_us=" . Round(s[s.Length], 3)
        . ",collect_min_us=" . Round(s[1], 3)
        . ",next_p50_us=" . Round(Pct(sn, 0.50), 3)
        . ",next_p95_us=" . Round(Pct(sn, 0.95), 3)
        . ",next_p99_us=" . Round(Pct(sn, 0.99), 3)
        . ",base_p50_us=" . Round(Pct(sb, 0.50), 3)
        . ",remain_p50_us=" . Round(Pct(sr, 0.50), 3)
        . ",tick4_p50_us=" . Round(Pct(stt, 0.50), 3)
        . ",tick4_p95_us=" . Round(Pct(stt, 0.95), 3)
        . ",jitter_us=" . Round(s[s.Length] - s[1], 3))
    return Pct(s, 0.50)
}

; ---------- 打点开销基线 ----------
RunOverhead(n) {
    lat := []
    i := 1
    while i <= n {
        t0 := HighResNow()
        t1 := HighResNow()
        lat.Push((t1 - t0) * 1000000)
        i++
    }
    s := SortNums(lat)
    BenchWrite("overhead,qpc_pair,n=" . s.Length
        . ",p50_us=" . Round(Pct(s, 0.50), 4)
        . ",p95_us=" . Round(Pct(s, 0.95), 4)
        . ",max_us=" . Round(s[s.Length], 4))
}

; ---------- C 阶段：enhanced 别名验证 ----------
RunAliasCheck(mode, n) {
    ; 基础版
    p := PolicyOf("new", mode)
    st1 := MakeState("new", mode, KEY_COUNT)
    r1 := GenRun(p, st1, n)
    ; enhanced：走 SeqModeOf 归一化后策略与参数完全相同
    m2 := SeqModeOf("enhanced_" . mode)
    st2 := MakeState("new", m2, KEY_COUNT)
    r2 := GenRun(PolicyOf("new", m2), st2, n)

    diffs := 0
    if r1.dueUs.Length != r2.dueUs.Length
        diffs := -1
    else {
        i := 1
        while i <= r1.dueUs.Length {
            if r1.dueUs[i] != r2.dueUs[i] || r1.keyIdx[i] != r2.keyIdx[i]
                diffs++
            i++
        }
    }
    BenchWrite("alias,mode=" . mode . "→enhanced_" . mode . ",n=" . n
        . ",diffs=" . diffs
        . ",result=" . (diffs = 0 ? "IDENTICAL" : "DIFFERENT"))
}

; ---------- D 阶段：新旧等价性 ----------
RunEquivalence(mode, n) {
    stO := MakeState("old", mode, KEY_COUNT)
    rO := GenRun(PolicyOf("old", mode), stO, n)
    stN := MakeState("new", mode, KEY_COUNT)
    rN := GenRun(PolicyOf("new", mode), stN, n)

    diffs := 0
    firstDiff := ""
    if rO.dueUs.Length != rN.dueUs.Length {
        diffs := -1
        firstDiff := "长度不同 " rO.dueUs.Length " vs " rN.dueUs.Length
    } else {
        i := 1
        while i <= rO.dueUs.Length {
            if rO.dueUs[i] != rN.dueUs[i] || rO.keyIdx[i] != rN.keyIdx[i] {
                diffs++
                if firstDiff = ""
                    firstDiff := "idx" i " old=" rO.dueUs[i] " new=" rN.dueUs[i]
            }
            i++
        }
    }
    BenchWrite("equivalence,mode=" . mode . ",n=" . n
        . ",diffs=" . diffs
        . ",first=" . (firstDiff = "" ? "-" : firstDiff)
        . ",result=" . (diffs = 0 ? "IDENTICAL" : "DIFFERENT"))
}

; ---------- E 阶段：分桶漂移 ----------
RunBucketDrift(ticks) {
    lo := LegacyBucketDriftDemo(ticks)
    ln := NewBucketDriftDemo(ticks)
    BenchWrite("bucket,impl=old_float_ms,ticks=" . ticks
        . ",opp=" . lo.opp . ",merged=" . lo.merged . ",split=" . lo.split)
    BenchWrite("bucket,impl=new_int_us,ticks=" . ticks
        . ",opp=" . ln.opp . ",merged=" . ln.merged . ",split=" . ln.split)
}

Main() {
    BenchInit("seqgen")
    BenchWrite("# bench_seqgen —— L1 纯生成基准（mock 时钟，无真实发键）")
    BenchWrite("# scale.p50_ms = 生成 n 个事件的耗时中位数；ops_per_s = n / p50")
    BenchWrite("# tick.collect_*_us = 单次 CollectInto；tick.next_*_us = 单次 NextDueUs")
    BenchWrite("# 两者均含 QPC 打点开销（见 overhead 行）；口径与 A 阶段一致")

    BenchWrite("# --- A 规模吞吐 ---")
    for mode in ["periodic", "sequence"] {
        for n in [100, 1000, 10000, 100000] {
            rounds := n <= 100 ? 200 : (n <= 1000 ? 100 : (n <= 10000 ? 30 : 8))
            RunScale(mode, n, "old", rounds)
            RunScale(mode, n, "new", rounds)
        }
    }

    ; ⚠️ 口径：P999 需要 ≥1000 个样本。实测 periodic 每 tick 平均产出 2.37 个
    ; 事件（8 键周期成倍数，同刻批量），所以「事件数」≠「tick 数」。
    ; 取 10000 事件 → periodic 约 4200 tick、sequence 10000 tick，均 ≥1000。
    BenchWrite("# --- B 每 tick 时延分布（10000 事件 → tick 样本 ≥1000）---")
    RunOverhead(2000)
    for mode in ["periodic", "sequence"] {
        RunTickLatency(mode, "old", 10000)
        RunTickLatency(mode, "new", 10000)
        ; ±5ms 唤醒抖动（模拟真实定时器网格误差）下的同口径对照
        RunTickLatency(mode, "old", 10000, 5000)
        RunTickLatency(mode, "new", 10000, 5000)
    }

    BenchWrite("# --- C enhanced 别名验证 ---")
    RunAliasCheck("periodic", 2000)
    RunAliasCheck("sequence", 2000)

    BenchWrite("# --- D 新旧等价性 ---")
    RunEquivalence("periodic", 2000)
    RunEquivalence("sequence", 2000)

    ; F 阶段：键数扫描 —— 对齐方案 C 的 M8（8 键）/ M9（24 键）目标口径。
    ; ⚠️ 只报 p50：K 越大每 tick 事件越多 → tick 样本越少，P999 必然不足。
    BenchWrite("# --- F 键数扫描（每 tick 耗时 p50，对齐 M8/M9）---")
    for kc in [8, 24, 64] {
        RunTickLatency("periodic", "old", 20000, 0, kc)
        RunTickLatency("periodic", "new", 20000, 0, kc)
        RunTickLatency("sequence", "old", 20000, 0, kc)
        RunTickLatency("sequence", "new", 20000, 0, kc)
    }

    ; G 阶段：排序消融 —— F 阶段发现「加速比随键数下降」，需要确认排序是不是真瓶颈。
    ; 只报 p50（同 F 阶段口径）；sort=on 与 sort=off 的差即排序本身的成本。
    BenchWrite("# --- G 排序消融（periodic，量化 SeqSortPair 的真实占比）---")
    for kc in [8, 24, 64] {
        RunTickLatency("periodic", "new", 20000, 0, kc, false)
        RunTickLatency("periodic", "new", 20000, 0, kc, true)
    }

    BenchWrite("# --- E 分桶漂移（浮点 ms 累加 vs 整数 us）---")
    RunBucketDrift(300)

    BenchDone()
}

Main()
ExitApp(0)
