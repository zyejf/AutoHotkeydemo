; =================================================================
; seqgen.ahk —— 「发送时刻序列生成」原型库（自包含，不依赖生产代码）
;
; 目的：把 sender.ahk 里与定时器纠缠在一起的调度逻辑抽成**纯计算**，
;       以便 (a) 可单元测试 (b) 可确定性回放 (c) 可基准评测 (d) 可替换策略。
;
; 与生产实现的三个关键差异：
;   1) 时刻用 **整数微秒**（Int64）而非 ms 浮点。
;      生产用浮点 dueAt 当 Map 分桶键（sender.ahk:481-491），数学上同刻的
;      两个键若浮点末位不同会被拆成两个桶，后一个桶的保持时长塌成 ~0ms ——
;      正是批量化（sender.ahk:418-421）本来要解决的问题。整数化顺带拿到确定性。
;   2) 生成与追赶分离：
;      生成（纯）: base' = base + interval，与 now 无关 → 完全确定、可回放
;      追赶      : 只在 now 越过计划时刻时发生，受 MAX_CATCHUP 约束
;      生产把两者混在一个 tick 里，所以既不可确定也不可单测。
;   3) 策略接口化：PeriodicPolicy / SequencePolicy 实现同一组方法，可独立替换；
;      enhanced_* 是配置别名（SeqModeOf），不新增策略 —— 依据 sender.ahk:277-288。
;
; ⚠️ AHK v2.0.26 坑（改本文件前先读 _harness.ahk 头部）：
;   - **普通 Object 不支持 obj["prop"] 取值**（无 __Item）→ 一律用 obj.prop；
;     需要字符串下标就改用 Map。本项目为此栽过跟头，见 MEMORY.md。
;   - catch as e / Array 没有 Sort() / 脚本级变量不会被箭头闭包捕获 → global
;   - case 是保留字 / 整数溢出会自动提升为 Double（故加法必须显式饱和）
; =================================================================
#Requires AutoHotkey v2.0

global SEQGEN_MIN_INTERVAL_US := 10 * 1000           ; sender.ahk:48  MIN_INTERVAL_MS=10
global SEQGEN_EPSILON_US      := 500                 ; sender.ahk:60  TIMING_EPSILON_MS=0.5
global SEQGEN_MAX_INTERVAL_US := 24 * 3600 * 1000000 ; 24h：防 base+interval 溢出
global SEQGEN_NO_DUE          := 0x7FFFFFFFFFFFFFFF   ; 「无到期事件」哨兵
global SEQGEN_INT64_MAX       := 0x7FFFFFFFFFFFFFFF

; 单次追赶上限。生产无此限制（sender.ahk:501 一次可跳任意多步）——
; 对「到达即算」的算术无所谓，但**窗口预生成**会把跳过的步逐个物化：
; 系统休眠 8 小时后醒来会瞬间生成上百万个事件。超限策略 = 相位重置为 now。
global SEQGEN_MAX_CATCHUP := 256

; ---------------------------------------------------------------
; 模式解析：enhanced_* 只是配置别名（配置字段名不同，调度语义完全一致）
; ---------------------------------------------------------------
SeqModeOf(mode) {
    return (mode = "enhanced_periodic") ? "periodic"
         : (mode = "enhanced_sequence") ? "sequence"
         : mode
}

SeqIsEnhanced(mode) {
    return mode = "enhanced_periodic" || mode = "enhanced_sequence"
}

; ---------------------------------------------------------------
; 饱和加法：AHK 整数溢出会自动提升为 Double，必须显式判定
; ---------------------------------------------------------------
AddUsSat(a, b) {
    global SEQGEN_INT64_MAX
    if b > 0 && a > SEQGEN_INT64_MAX - b
        return SEQGEN_INT64_MAX
    return a + b
}

; ---------------------------------------------------------------
; Clock：可注入时间源。生产用 RealClock，测试/基准用 VirtualClock。
; ---------------------------------------------------------------
class RealClock {
    static NowUs() {
        static freq := 0
        if !freq
            DllCall("QueryPerformanceFrequency", "Int64*", &freq)
        DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
        ; c*1e6 在 c≈1e10 时为 1e16，仍在 Int64 内（上限 9.22e18）
        return (c * 1000000) // freq
    }
}

class VirtualClock {
    __New(startUs := 0) {
        this.t := startUs
    }
    NowUs() {
        return this.t
    }
    Advance(dUs) {
        this.t += dUs
        return this.t
    }
    Set(us) {
        this.t := us
        return this.t
    }
}

; 单调守卫：包裹任意 Clock，保证 NowUs() 永不倒退并统计回拨。
; QPC 本身单调，但 (a) 虚拟时钟 (b) 未来接入墙钟 (c) 跨进程回放都可能回拨。
; 策略 = **钳制而非报错**：时间倒退时沿用上次值，base 不倒退、不会重复触发，
; 代价是这一刻的触发被推迟。回拨次数与累计钳制量均被记录，可供监控告警。
class MonotonicGuard {
    __New(inner) {
        this.inner := inner
        this.last := 0
        this.backsteps := 0
        this.clampedUs := 0
    }
    NowUs() {
        t := this.inner.NowUs()
        if t < this.last {
            this.backsteps++
            this.clampedUs += (this.last - t)
            return this.last
        }
        this.last := t
        return t
    }
}

; ---------------------------------------------------------------
; 参数夹紧（对齐生产 _IntervalOf / _DelayOf，单位换成微秒）
; ---------------------------------------------------------------
ClampIntervalUs(us) {
    global SEQGEN_MIN_INTERVAL_US, SEQGEN_MAX_INTERVAL_US
    if us < SEQGEN_MIN_INTERVAL_US
        return SEQGEN_MIN_INTERVAL_US
    if us > SEQGEN_MAX_INTERVAL_US
        return SEQGEN_MAX_INTERVAL_US
    return us
}

IntervalUsOf(intervalsUs, i) {
    return i <= intervalsUs.Length ? ClampIntervalUs(intervalsUs[i]) : ClampIntervalUs(50000)
}

DelayUsOf(delaysUs, i) {
    return i <= delaysUs.Length ? ClampIntervalUs(delaysUs[i]) : ClampIntervalUs(100000)
}

; ---------------------------------------------------------------
; PeriodicPolicy：多键各自独立周期，取最早到期者
;   state.bases[i] = 第 i 键「上一次的计划时刻」，初始 = originUs
;   state.iv[i]    = 第 i 键**已夹紧**的间隔（Init 时算一次）
;   事件 = (dueUs = bases[i] + iv[i], keyIdx = i)
;
; 性能约定（实测，本项目的 AHK 解释器很慢，函数调用不是免费的）：
;   Init 时就把间隔夹紧存进 st.iv，热路径里**不再**调用
;   IntervalUsOf / ClampIntervalUs / AddUsSat —— 这三个调用让第一版
;   比旧实现慢 1.45×（实测 100K 事件：1350ms vs 923ms）。
;   饱和加法同样内联成 `(b > lim - v) ? lim : (b + v)` 一条三元表达式。
; ---------------------------------------------------------------
class PeriodicPolicy {
    static Name => "periodic"

    static Init(keyCount, intervalsUs, originUs) {
        bases := []
        iv := []
        i := 1
        while i <= keyCount {
            bases.Push(originUs)
            iv.Push(IntervalUsOf(intervalsUs, i))
            i++
        }
        return {bases: bases, iv: iv, intervalsUs: intervalsUs, dropped: 0
              , emitted: 0, truncated: 0, noSort: false}
        ; noSort：仅供基准消融（bench_seqgen 的 G 阶段）量化排序本身的成本。
        ; 生产路径恒为 false —— 关掉排序会破坏「按 dueUs 升序」的输出契约。
    }

    static NextDueUs(st) {
        global SEQGEN_NO_DUE
        bases := st.bases
        iv := st.iv
        n := bases.Length
        if n = 0
            return SEQGEN_NO_DUE
        lim := SEQGEN_NO_DUE
        best := lim
        i := 1
        while i <= n {
            b := bases[i], v := iv[i]
            d := (b > lim - v) ? lim : (b + v)
            if d < best
                best := d
            i++
        }
        return best
    }

    ; 收集 nowUs（含容差）前到期的全部事件并推进基准。
    ; 返回 {dueUs:[], keyIdx:[]}，按 dueUs 升序、同刻相邻（SoA 布局）。
    ; 语义与 CollectInto 完全一致，只是多分配两个数组 + 一个对象。
    static Collect(st, nowUs, epsilonUs := "", maxCatchup := "") {
        outDue := []
        outKey := []
        PeriodicPolicy.CollectInto(st, nowUs, epsilonUs, maxCatchup, outDue, outKey)
        return {dueUs: outDue, keyIdx: outKey}
    }

    ; 零分配快路径：直接写入调用方数组，返回本轮新增的事件数。
    ; EventWindow 每 tick 调它一次，避免 3 次分配/tick。
    static CollectInto(st, nowUs, epsilonUs, maxCatchup, outDue, outKey) {
        global SEQGEN_EPSILON_US, SEQGEN_MAX_CATCHUP
        if epsilonUs = ""
            epsilonUs := SEQGEN_EPSILON_US
        if maxCatchup = ""
            maxCatchup := SEQGEN_MAX_CATCHUP

        bases := st.bases
        iv := st.iv
        n := bases.Length
        lim := 0x7FFFFFFFFFFFFFFF
        lo := outDue.Length + 1          ; 只排序本轮新增的尾部（见下）
        i := 1
        ; 单遍扫描：interval 每键每轮只算一次（旧实现同一轮算 3 次：
        ; sender.ahk:462 / :483 / :522）
        while i <= n {
            v := iv[i]
            b := bases[i]
            dueAt := (b > lim - v) ? lim : (b + v)
            if nowUs < dueAt - epsilonUs {
                i++
                continue
            }
            outDue.Push(dueAt)
            outKey.Push(i)

            ; 保相位推进：基准用「本次计划时刻」，不用发送后的当前时刻 ——
            ; 后者已被 kpd 推后，会让每次都被误判为落后而白跳一个周期。
            last := dueAt
            next := (dueAt > lim - v) ? lim : (dueAt + v)
            if next <= nowUs {
                steps := (nowUs - next) // v + 1
                st.dropped := st.dropped + steps
                if steps > maxCatchup {
                    ; 超长追赶：不逐个物化，直接把相位重置为 now
                    last := nowUs
                    st.truncated := st.truncated + 1
                } else {
                    stepUs := steps * v
                    next := (next > lim - stepUs) ? lim : (next + stepUs)
                    last := next - v
                }
            }
            bases[i] := last
            st.emitted := st.emitted + 1
            i++
        }
        ; ⚠️ 只能排本轮新增的尾部。整表重排会让 EventWindow 累积成 O(n²)。
        if !st.noSort && outDue.Length > lo
            SeqSortPair(outDue, outKey, lo)
        return outDue.Length - lo + 1
    }
}

; ---------------------------------------------------------------
; SequencePolicy：按 delays 逐步推进，走到末步循环回第 1 步
;   state.step = 当前步（1-based），state.nextUs = 本步计划时刻
; 每次 Collect 只发当前步（与生产 _ExecuteSequence 一致）
; ---------------------------------------------------------------
class SequencePolicy {
    static Name => "sequence"

    ; 同 PeriodicPolicy.Init：延迟在 Init 时夹紧进 st.dv，热路径零函数调用
    static Init(keyCount, delaysUs, originUs) {
        dv := []
        i := 1
        while i <= keyCount {
            dv.Push(DelayUsOf(delaysUs, i))
            i++
        }
        return {step: 1, nextUs: originUs, dv: dv, delaysUs: delaysUs
              , keyCount: keyCount, dropped: 0, emitted: 0, truncated: 0}
    }

    static NextDueUs(st) {
        global SEQGEN_NO_DUE
        if st.keyCount = 0
            return SEQGEN_NO_DUE
        return st.nextUs
    }

    static Collect(st, nowUs, epsilonUs := "", maxCatchup := "") {
        outDue := []
        outKey := []
        SequencePolicy.CollectInto(st, nowUs, epsilonUs, maxCatchup, outDue, outKey)
        return {dueUs: outDue, keyIdx: outKey}
    }

    static CollectInto(st, nowUs, epsilonUs, maxCatchup, outDue, outKey) {
        global SEQGEN_EPSILON_US, SEQGEN_MAX_CATCHUP
        if epsilonUs = ""
            epsilonUs := SEQGEN_EPSILON_US
        if maxCatchup = ""
            maxCatchup := SEQGEN_MAX_CATCHUP

        if st.keyCount = 0
            return 0
        if nowUs < st.nextUs - epsilonUs
            return 0

        step := st.step
        if step > st.keyCount
            step := 1
        dueAt := st.nextUs
        outDue.Push(dueAt)
        outKey.Push(step)
        st.emitted := st.emitted + 1

        nextStep := Mod(step, st.keyCount) + 1
        nextDelay := st.dv[nextStep]

        advance := 1
        lim := 0x7FFFFFFFFFFFFFFF
        next := (dueAt > lim - nextDelay) ? lim : (dueAt + nextDelay)
        if next <= nowUs {
            skipped := (nowUs - next) // nextDelay + 1
            st.dropped := st.dropped + skipped
            if skipped > maxCatchup {
                ; 同上：超长追赶不逐个物化，相位重置为 now
                next := nowUs
                st.truncated := st.truncated + 1
            } else {
                skipUs := skipped * nextDelay
                next := (next > lim - skipUs) ? lim : (next + skipUs)
                advance := advance + skipped
            }
        }
        st.nextUs := next
        st.step := Mod(step - 1 + advance, st.keyCount) + 1
        return 1
    }
}

; ---------------------------------------------------------------
; 惰性滑动窗口：按需产出接下来 want 个事件，不预生成整个（可能无界的）序列
;
; 契约
;   输入  policy / state / vc(VirtualClock) / want / tickPlan
;   输出  {dueUs:[], keyIdx:[], ticks:n, guard:MonotonicGuard}
;   副作用 仅推进 state 与 vc，不碰外部资源（纯计算，可安全单测）
;   tickPlan: (dueUs, tickIndex) -> 本次唤醒的 nowUs；省略 = 精确到达（零抖动）
; ---------------------------------------------------------------
class EventWindow {
    __New(policy, state, vc, guard := "", maxTicks := 0x7FFFFFFF) {
        this.p := policy
        this.st := state
        this.vc := vc
        this.guard := (guard = "") ? MonotonicGuard(vc) : guard
        this.maxTicks := maxTicks
        this.ticks := 0
    }

    Fill(want, tickPlan := "") {
        global SEQGEN_NO_DUE
        outDue := []
        outKey := []
        spins := 0
        while outDue.Length < want {
            if this.ticks >= this.maxTicks
                break
            due := this.p.NextDueUs(this.st)
            if due = SEQGEN_NO_DUE
                break                       ; 空序列：立即返回，不空转
            targetUs := tickPlan = "" ? due : tickPlan.Call(due, this.ticks)
            this.vc.Set(targetUs)
            nowUs := this.guard.NowUs()     ; 单调钳制后的值
            ; CollectInto 直接写入 outDue/outKey：省掉「2 个数组 + 1 个对象」的
            ; 每 tick 分配（实测这是第一版比旧实现慢的第二大来源）
            this.p.CollectInto(this.st, nowUs, "", "", outDue, outKey)
            this.ticks++
            ; 兜底防死循环：策略若始终不推进，不应把进程挂死
            spins++
            if spins > want * 8 + 4096
                break
        }
        ; 一轮可能多产出（批量同刻），截回 want 保证契约「恰好 want 个」
        if outDue.Length > want {
            outDue.Length := want
            outKey.Length := want
        }
        return {dueUs: outDue, keyIdx: outKey, ticks: this.ticks, guard: this.guard}
    }
}

; ---------------------------------------------------------------
; 确定性抖动源（32 位安全 LCG）。
; ⚠️ 不能用 64 位大常数：AHK 整数溢出会自动提升为 Double，位运算结果不可靠。
; 常数取 2^31 模，s*1103515245+12345 最大约 2.37e18 < Int64 上限 9.22e18。
; ---------------------------------------------------------------
class Lcg {
    __New(seed := 1) {
        this.s := Mod(seed, 2147483648)
        if this.s = 0
            this.s := 1
    }
    Next(maxExclusive) {
        this.s := Mod(this.s * 1103515245 + 12345, 2147483648)
        ; 取高位：LCG 低位周期短
        return Mod(Floor(this.s / 65536), maxExclusive)
    }
    ; 对称抖动 [-amp, +amp]
    Jitter(amp) {
        return this.Next(2 * amp + 1) - amp
    }
}

; ---------------------------------------------------------------
; 排序：AHK 2.0.26 的 Array 没有 Sort()。
; Collect 每轮产出的事件数 ≤ K（很小），用插入排序即可。
; ---------------------------------------------------------------
; lo：只从下标 lo 开始排（用于 CollectInto 只排本轮新增的尾部）
SeqSortPair(d, k, lo := 1) {
    i := lo + 1
    while i <= d.Length {
        vd := d[i], vk := k[i]
        j := i - 1
        while j >= lo && d[j] > vd {
            d[j + 1] := d[j]
            k[j + 1] := k[j]
            j--
        }
        d[j + 1] := vd
        k[j + 1] := vk
        i++
    }
}

; ---------------------------------------------------------------
; 分桶：把 (dueUs,keyIdx) 中 dueUs 相同的相邻事件合成桶。
; 整数微秒保证「数学同刻 ⟹ 同一桶」；浮点做不到（见文件头）。
; 返回 [{dueUs, keys}, ...]
; ---------------------------------------------------------------
GroupBuckets(ev) {
    buckets := []
    d := ev.dueUs, k := ev.keyIdx
    if d.Length = 0
        return buckets
    cur := d[1]
    keys := [k[1]]
    i := 2
    while i <= d.Length {
        if d[i] = cur {
            keys.Push(k[i])
        } else {
            buckets.Push({dueUs: cur, keys: keys})
            cur := d[i]
            keys := [k[i]]
        }
        i++
    }
    buckets.Push({dueUs: cur, keys: keys})
    return buckets
}
