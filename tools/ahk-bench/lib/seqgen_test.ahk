; =================================================================
; seqgen_test.ahk —— seqgen.ahk 的单元测试（自包含断言框架）
;
; 覆盖：空序列 / 单元素 / 极大间隔与溢出 / 极小间隔夹紧 / 时钟回拨 /
;       确定性（同输入同输出）/ 同刻分桶合并 / 追赶计数 / MAX_CATCHUP 截断 /
;       enhanced 别名 / 窗口不变量
;
; ⚠️ 两个必须遵守的坑：
;   1) 结果必须写文件：AutoHotkey64.exe 是 GUI 子系统进程，stdout 进不了
;      bash 的管道/重定向（实测重定向后恒为 0 字节）。输出落在脚本同目录的
;      seqgen_test_result.log（已被 .gitignore 的 *.log 覆盖）。
;   2) 普通 Object 不支持 obj["prop"] → 一律 obj.prop。
; 用法：AutoHotkey64.exe lib\seqgen_test.ahk  然后读该 log
; =================================================================
#Requires AutoHotkey v2.0
#Include "seqgen.ahk"

global T_PASS := 0
global T_FAIL := 0
global T_LOG := []
global T_CUR := ""

TCase(name) {
    global T_CUR, T_LOG
    T_CUR := name
    T_LOG.Push("CASE " name)
}

TOk(cond, msg) {
    global T_PASS, T_FAIL, T_CUR, T_LOG
    if cond {
        T_PASS++
    } else {
        T_FAIL++
        T_LOG.Push("  FAIL [" T_CUR "] " msg)
    }
}

TEq(actual, expected, msg) {
    TOk(actual = expected, msg . "（期望 " expected "，实际 " actual "）")
}

; ---------------------------------------------------------------
; 1. 空序列
; ---------------------------------------------------------------
Test_EmptySequence() {
    global SEQGEN_NO_DUE
    TCase("空序列")
    st := PeriodicPolicy.Init(0, [], 1000000)
    TEq(PeriodicPolicy.NextDueUs(st), SEQGEN_NO_DUE, "空 periodic 无到期时刻")
    ev := PeriodicPolicy.Collect(st, 9999999)
    TEq(ev.dueUs.Length, 0, "空 periodic Collect 产出 0 个事件")

    st2 := SequencePolicy.Init(0, [], 1000000)
    TEq(SequencePolicy.NextDueUs(st2), SEQGEN_NO_DUE, "空 sequence 无到期时刻")

    w := EventWindow(PeriodicPolicy, PeriodicPolicy.Init(0, [], 1000000), VirtualClock(1000000))
    r := w.Fill(100)
    TEq(r.dueUs.Length, 0, "空序列窗口立即返回，不空转")
    TEq(r.ticks, 0, "空序列窗口 tick 数为 0")
}

; ---------------------------------------------------------------
; 2. 单元素
; ---------------------------------------------------------------
Test_SingleElement() {
    TCase("单元素")
    ; periodic 单键：origin + i*interval
    st := PeriodicPolicy.Init(1, [50000], 1000000)
    w := EventWindow(PeriodicPolicy, st, VirtualClock(1000000))
    r := w.Fill(5)
    TEq(r.dueUs.Length, 5, "单键产出 5 个事件")
    TEq(r.dueUs[1], 1050000, "第 1 个计划时刻")
    TEq(r.dueUs[2], 1100000, "第 2 个计划时刻")
    TEq(r.dueUs[5], 1250000, "第 5 个计划时刻")
    TEq(r.keyIdx[3], 1, "单键 keyIdx 恒为 1")

    ; sequence 单步：每步都是 delays[1]
    st2 := SequencePolicy.Init(1, [70000], 1000000)
    w2 := EventWindow(SequencePolicy, st2, VirtualClock(1000000))
    r2 := w2.Fill(4)
    TEq(r2.dueUs[1], 1000000, "单步序列首步立即触发")
    TEq(r2.dueUs[2], 1070000, "单步序列第 2 步")
    TEq(r2.dueUs[4], 1210000, "单步序列第 4 步")
}

; ---------------------------------------------------------------
; 3. 极大间隔与溢出
; ---------------------------------------------------------------
Test_HugeInterval() {
    global SEQGEN_MAX_INTERVAL_US, SEQGEN_INT64_MAX
    TCase("极大间隔/溢出")
    over := SEQGEN_MAX_INTERVAL_US + 1
    TEq(ClampIntervalUs(over), SEQGEN_MAX_INTERVAL_US, "超过 24h 的间隔被夹紧")

    ; 饱和加法不得回绕成负数
    big := SEQGEN_INT64_MAX - 100
    TEq(AddUsSat(big, 1000), SEQGEN_INT64_MAX, "加法饱和到 Int64 上限")
    TOk(AddUsSat(big, 1000) > 0, "饱和结果必须为正（否则会重复触发）")

    st := PeriodicPolicy.Init(1, [SEQGEN_MAX_INTERVAL_US], 0)
    w := EventWindow(PeriodicPolicy, st, VirtualClock(0))
    r := w.Fill(3)
    TEq(r.dueUs.Length, 3, "极大间隔仍能产出 3 个事件")
    TEq(r.dueUs[1], SEQGEN_MAX_INTERVAL_US, "首个计划时刻 = 夹紧后的间隔")
}

; ---------------------------------------------------------------
; 4. 极小间隔夹紧
; ---------------------------------------------------------------
Test_MinIntervalClamp() {
    global SEQGEN_MIN_INTERVAL_US
    TCase("极小间隔夹紧")
    TEq(ClampIntervalUs(1), SEQGEN_MIN_INTERVAL_US, "1us 被夹到 10ms")
    TEq(ClampIntervalUs(0), SEQGEN_MIN_INTERVAL_US, "0 被夹到 10ms")
    TEq(ClampIntervalUs(-500), SEQGEN_MIN_INTERVAL_US, "负数被夹到 10ms")
    st := PeriodicPolicy.Init(1, [1], 0)
    TEq(PeriodicPolicy.NextDueUs(st), SEQGEN_MIN_INTERVAL_US, "夹紧在策略中生效")
}

; ---------------------------------------------------------------
; 5. 时钟回拨
; ---------------------------------------------------------------
Test_ClockRollback() {
    TCase("时钟回拨")
    vc := VirtualClock(5000000)
    g := MonotonicGuard(vc)
    TEq(g.NowUs(), 5000000, "首次读数")
    vc.Set(4000000)                       ; 回拨 1 秒
    TEq(g.NowUs(), 5000000, "回拨被钳制为上次值")
    TEq(g.backsteps, 1, "回拨计数 +1")
    TEq(g.clampedUs, 1000000, "累计钳制量 = 1s")
    vc.Set(5000001)
    TEq(g.NowUs(), 5000001, "恢复前进后正常读数")

    ; 回拨不得导致重复触发：同一 nowUs 连续 Collect 两次，第二次应为空
    st := PeriodicPolicy.Init(1, [50000], 1000000)
    e1 := PeriodicPolicy.Collect(st, 1050000)
    e2 := PeriodicPolicy.Collect(st, 1050000)
    TEq(e1.dueUs.Length, 1, "首次 Collect 触发 1 次")
    TEq(e2.dueUs.Length, 0, "同一时刻重复 Collect 不重复触发（base 已推进）")
}

; ---------------------------------------------------------------
; 6. 确定性：同输入必同输出
; ---------------------------------------------------------------
Test_Determinism() {
    TCase("确定性")
    Run1(seed) {
        rng := Lcg(seed)
        st := PeriodicPolicy.Init(4, [50000, 75000, 100000, 125000], 1000000)
        w := EventWindow(PeriodicPolicy, st, VirtualClock(1000000))
        plan := ((due, t) => due + rng.Jitter(800))
        r := w.Fill(200, plan)
        s := ""
        i := 1
        while i <= r.dueUs.Length {
            s .= r.dueUs[i] ":" r.keyIdx[i] ","
            i++
        }
        ; 完整签名 = 计划时刻序列 + tick 数 + 丢步数
        return s . "|ticks=" . r.ticks . "|dropped=" . st.dropped
    }
    TEq(Run1(42), Run1(42), "同一 seed 两次运行输出逐位相同")

    ; ⚠️ 计划时刻本身**不依赖**唤醒抖动：抖动只改变「tick 何时发生」，
    ; 从而改变每 tick 收集到几个事件、是否触发追赶，但不改变计划时刻的值。
    ; 这正是「生成是纯函数」的体现，也是能拿来做回归基线的理由。
    PlanOnly(seed) {
        rng := Lcg(seed)
        st := PeriodicPolicy.Init(4, [50000, 75000, 100000, 125000], 1000000)
        w := EventWindow(PeriodicPolicy, st, VirtualClock(1000000))
        r := w.Fill(200, ((due, t) => due + rng.Jitter(800)))
        s := ""
        i := 1
        while i <= r.dueUs.Length {
            s .= r.dueUs[i] ":" r.keyIdx[i] ","
            i++
        }
        return s
    }
    TEq(PlanOnly(42), PlanOnly(43), "计划时刻序列不随唤醒抖动改变（生成是纯函数）")

    ; 抖动源本身必须随 seed 变化，否则上面的等价性测试毫无意义
    a := Lcg(42), b := Lcg(43)
    sa := "", sb := ""
    loop 5 {
        sa .= a.Next(1000) . ","
        sb .= b.Next(1000) . ","
    }
    TOk(sa != sb, "LCG 不同 seed 产生不同抖动序列")
}

; ---------------------------------------------------------------
; 7. 同刻分桶合并（整数微秒的核心收益）
; ---------------------------------------------------------------
Test_SameInstantBucketing() {
    TCase("同刻分桶")
    ; 4 个键同间隔同基准 → 数学上完全同刻
    st := PeriodicPolicy.Init(4, [50000, 50000, 50000, 50000], 1000000)
    ev := PeriodicPolicy.Collect(st, 1050000)
    TEq(ev.dueUs.Length, 4, "4 个键同时到期")
    bs := GroupBuckets(ev)
    TEq(bs.Length, 1, "数学同刻的键必须合并成 1 个桶")
    TEq(bs[1].keys.Length, 4, "该桶含全部 4 个键")

    ; 对照：间隔不同 → 不同刻
    st2 := PeriodicPolicy.Init(2, [50000, 75000], 1000000)
    ev2 := PeriodicPolicy.Collect(st2, 1125000)
    bs2 := GroupBuckets(ev2)
    TOk(bs2.Length >= 1, "不同间隔的键各自成桶")
}

; ---------------------------------------------------------------
; 8. 追赶计数
; ---------------------------------------------------------------
Test_CatchUp() {
    TCase("追赶")
    ; 单键 interval=50ms，origin=1s，now=1.3s
    st := PeriodicPolicy.Init(1, [50000], 1000000)
    ev := PeriodicPolicy.Collect(st, 1300000)
    TEq(ev.dueUs.Length, 1, "追赶时本轮只发 1 次（不是补发 6 次）")
    TEq(ev.dueUs[1], 1050000, "发出的仍是首个计划时刻")
    TEq(st.dropped, 5, "跳过的 5 步计入 dropped")
    TEq(st.truncated, 0, "未超 MAX_CATCHUP 时不截断")
    ; 保相位：1.05 触发 + 跳过 5 步（1.10/1.15/1.20/1.25/1.30）→ 下一步 = 1.35s
    ; 该公式与生产 sender.ahk:500-505 完全一致（steps = Floor((now-next)/interval)+1）
    TEq(PeriodicPolicy.NextDueUs(st), 1350000, "追赶后保相位（下一步 = 1.35s）")

    ; 超长追赶：跳过 1 万个周期
    st2 := PeriodicPolicy.Init(1, [50000], 1000000)
    far := 1000000 + 50000 * 10000
    PeriodicPolicy.Collect(st2, far)
    TEq(st2.truncated, 1, "超过 MAX_CATCHUP 触发截断")
    ; steps = Floor((now - next)/interval) + 1 = (501000000-1100000)//50000 + 1 = 9999
    ; 截断只是「不逐个物化」，dropped 仍如实记账，否则监控上看不出发生了长暂停
    TEq(st2.dropped, 9999, "dropped 如实累计跳过的步数（不因截断而少计）")
    TOk(PeriodicPolicy.NextDueUs(st2) >= far, "截断后相位重置为 now，不再落后")
}

; ---------------------------------------------------------------
; 9. enhanced 别名
; ---------------------------------------------------------------
Test_EnhancedAlias() {
    TCase("enhanced 别名")
    TEq(SeqModeOf("enhanced_periodic"), "periodic", "enhanced_periodic → periodic")
    TEq(SeqModeOf("enhanced_sequence"), "sequence", "enhanced_sequence → sequence")
    TEq(SeqModeOf("periodic"), "periodic", "periodic 原样返回")
    TOk(SeqIsEnhanced("enhanced_sequence"), "识别 enhanced")
    TOk(!SeqIsEnhanced("sequence"), "非 enhanced 返回 false")
}

; ---------------------------------------------------------------
; 10. 窗口不变量
; ---------------------------------------------------------------
Test_WindowInvariants() {
    TCase("窗口不变量")
    rng := Lcg(7)
    st := PeriodicPolicy.Init(8, [50000, 75000, 100000, 125000
                                , 150000, 175000, 200000, 225000], 1000000)
    w := EventWindow(PeriodicPolicy, st, VirtualClock(1000000))
    r := w.Fill(1000, ((due, t) => due + rng.Jitter(2000)))
    TEq(r.dueUs.Length, 1000, "窗口产出恰好 want 个事件")

    ; ⚠️ 全局序列**不**单调：各键周期不同，同一 tick 会同时产出多个刻，
    ; 下一 tick 里短周期键的计划时刻可能小于上一 tick 长周期键的时刻。
    ; 真正成立的不变量是「每个键自己的计划时刻严格递增」。
    lastOf := Map()
    ok := true
    i := 1
    while i <= r.dueUs.Length {
        ki := r.keyIdx[i]
        if lastOf.Has(ki) && r.dueUs[i] <= lastOf[ki]
            ok := false
        lastOf[ki] := r.dueUs[i]
        i++
    }
    TOk(ok, "每个键自己的计划时刻严格递增")

    ; sequence 的步序号必须落在 [1, keyCount]
    st2 := SequencePolicy.Init(3, [100000, 200000, 300000], 0)
    w2 := EventWindow(SequencePolicy, st2, VirtualClock(0))
    r2 := w2.Fill(100)
    ok2 := true
    j := 1
    while j <= r2.keyIdx.Length {
        if r2.keyIdx[j] < 1 || r2.keyIdx[j] > 3
            ok2 := false
        j++
    }
    TOk(ok2, "sequence 步序号始终在合法范围")
    TEq(r2.dueUs[1], 0, "sequence 首步立即触发（与生产一致）")
}

; ---------------------------------------------------------------
Main() {
    out := A_ScriptDir . "\seqgen_test_result.log"
    try FileDelete out

    Test_EmptySequence()
    Test_SingleElement()
    Test_HugeInterval()
    Test_MinIntervalClamp()
    Test_ClockRollback()
    Test_Determinism()
    Test_SameInstantBucketing()
    Test_CatchUp()
    Test_EnhancedAlias()
    Test_WindowInvariants()

    global T_PASS, T_FAIL, T_LOG
    lines := ["seqgen 单元测试", "通过: " T_PASS "  /  失败: " T_FAIL, ""]
    for l in T_LOG
        lines.Push(l)
    txt := ""
    for l in lines
        txt .= l . "`n"
    FileAppend(txt, out, "UTF-8")
}

; GUI 子系统下未捕获的错误会弹模态框 → 进程静默挂起（本项目曾空等 28 分钟）。
; 因此必须「OnError 守卫 + try/catch」双保险，把错误写进结果文件而不是弹框。
OnTestError(e, mode) {
    try FileAppend("FATAL " e.Message " @line " e.Line "`n"
        , A_ScriptDir . "\seqgen_test_result.log", "UTF-8")
    ExitApp(99)
}
OnError(OnTestError)

try
    Main()
catch as e {
    FileAppend("FATAL " e.Message " @line " e.Line "`n"
        , A_ScriptDir . "\seqgen_test_result.log", "UTF-8")
    T_FAIL++
}

; 退出码必须反映失败数：裸 `ExitApp(0)` 会让任何按退出码判断的 runner 静默放行。
; 本脚本已被 scripts/run-standalone-ahk-tests.sh（四闸门 G3g）逐个按退出码汇总。
ExitApp(T_FAIL > 0 ? 1 : 0)
