; =================================================================
; bench_tick_traversal —— 每 tick 的遍历次数与重复计算
;
; 原型：asd-tauri/src-tauri/ahk_executor/sender.ahk:454/461/482/522
;   _ExecutePeriodic 一轮 tick 对 keys 做了 4 次全遍历，且
;   Sender._IntervalOf(intervals, i) 在同一轮里被重复调用（:462 / :483 / :522）
;
; 修复：合并为 1 次遍历，间隔只算一次并复用（语义完全等价：
;        target 用「推进前」的 triggerTimes 计算，与旧实现一致）
;
; 常量对齐真实值：MIN_INTERVAL_MS=10（sender.ahk:48）
;                 TIMING_EPSILON_MS=0.5（sender.ahk:60）
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

global MIN_INTERVAL_MS := 10
global TIMING_EPSILON_MS := 0.5

IntervalOf(intervals, i) {
    global MIN_INTERVAL_MS
    interval := i <= intervals.Length ? intervals[i] : 50
    return interval < MIN_INTERVAL_MS ? MIN_INTERVAL_MS : interval
}

; ---------- 优化前：4 次遍历 + 每键 3 次 IntervalOf ----------
TickOld(keys, intervals, triggerTimes, now) {
    global TIMING_EPSILON_MS
    i := 1
    while i <= keys.Length {
        if !triggerTimes.Has(i)
            triggerTimes[i] := now
        i++
    }
    target := 0
    i := 1
    while i <= keys.Length {
        t := triggerTimes[i] + IntervalOf(intervals, i)
        if target = 0 || t < target
            target := t
        i++
    }
    dueCount := 0
    i := 1
    while i <= keys.Length {
        interval := IntervalOf(intervals, i)
        dueAt := triggerTimes[i] + interval
        if now >= dueAt - TIMING_EPSILON_MS {
            dueCount++
            triggerTimes[i] := dueAt
        }
        i++
    }
    ; 第 4 次遍历：重新求下一轮 target（旧实现在推进基准后还要再扫一遍）
    nextTarget := 0
    i := 1
    while i <= keys.Length {
        t := triggerTimes[i] + IntervalOf(intervals, i)
        if nextTarget = 0 || t < nextTarget
            nextTarget := t
        i++
    }
    return [target, dueCount, nextTarget]
}

; ---------- 优化后：单次遍历，间隔只算一次 ----------
TickNew(keys, intervals, triggerTimes, now) {
    global TIMING_EPSILON_MS
    n := keys.Length
    target := 0
    dueCount := 0
    nextTarget := 0
    i := 1
    while i <= n {
        if !triggerTimes.Has(i)
            triggerTimes[i] := now
        interval := IntervalOf(intervals, i)
        dueAt := triggerTimes[i] + interval
        ; target 用「推进前」的值，与旧实现第 2 次遍历一致
        if target = 0 || dueAt < target
            target := dueAt
        cur := triggerTimes[i]
        if now >= dueAt - TIMING_EPSILON_MS {
            dueCount++
            cur := dueAt
            triggerTimes[i] := cur
        }
        ; nextTarget 用「推进后」的值再叠加一个间隔，与旧实现第 4 次遍历一致
        next := cur + interval
        if nextTarget = 0 || next < nextTarget
            nextTarget := next
        i++
    }
    return [target, dueCount, nextTarget]
}

RunCase(tag, keyCount, ticks, fn) {
    keys := []
    intervals := []
    i := 1
    while i <= keyCount {
        keys.Push("F" . i)
        intervals.Push(50 + i * 25)
        i++
    }
    triggerTimes := Map()
    now := 1000.0

    samples := []
    r := 1
    while r <= 5 {
        triggerTimes := Map()
        now := 1000.0
        t0 := HighResNow()
        k := 1
        while k <= ticks {
            fn.Call(keys, intervals, triggerTimes, now)
            now += 4
            k++
        }
        samples.Push((HighResNow() - t0) * 1000)
        r++
    }
    s := SortNums(samples)
    p50 := Pct(s, 0.5)
    BenchWrite("tick," . tag . ",keys=" . keyCount . ",ticks=" . ticks
        . ",p50_ms=" . Round(p50, 3)
        . ",us_per_tick=" . Round(p50 * 1000 / ticks, 4))
    return p50
}

Main() {
    BenchInit("tick_traversal")
    BenchWrite("# bench_tick_traversal —— 每 tick 4 次遍历 vs 单次遍历")
    BenchWrite("# p50_ms = 完成 ticks 次 tick 的总耗时中位数（5 轮）")

    BenchWrite("# --- 场景1：8 键（典型技能组）---")
    o1 := RunCase("old_keys8", 8, 20000, TickOld)
    n1 := RunCase("new_keys8", 8, 20000, TickNew)
    BenchWrite("cmp,keys8,p50_old_ms=" . Round(o1, 3) . ",p50_new_ms=" . Round(n1, 3)
        . ",speedup=" . Round(o1 / ((n1 > 0) ? n1 : 0.0001), 2))

    BenchWrite("# --- 场景2：24 键（大技能组，凸显规模效应）---")
    o2 := RunCase("old_keys24", 24, 20000, TickOld)
    n2 := RunCase("new_keys24", 24, 20000, TickNew)
    BenchWrite("cmp,keys24,p50_old_ms=" . Round(o2, 3) . ",p50_new_ms=" . Round(n2, 3)
        . ",speedup=" . Round(o2 / ((n2 > 0) ? n2 : 0.0001), 2))

    ; 等价性校验：同一输入两份实现必须给出相同结果
    keys := []
    intervals := []
    i := 1
    while i <= 8 {
        keys.Push("F" . i)
        intervals.Push(50 + i * 25)
        i++
    }
    tt1 := Map(), tt2 := Map()
    k := 1
    diffs := 0
    while k <= 500 {
        a := TickOld(keys, intervals, tt1, 1000.0 + k * 4)
        b := TickNew(keys, intervals, tt2, 1000.0 + k * 4)
        if a[1] != b[1] || a[2] != b[2] || a[3] != b[3]
            diffs++
        k++
    }
    BenchWrite("verify,equivalence,diffs=" . diffs . ",result=" . (diffs = 0 ? "IDENTICAL" : "DIFFERENT"))

    BenchDone()
}

Main()
ExitApp(0)
