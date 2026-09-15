; =================================================================
; bench_prod_escape —— 【生产回归基准】JSON 转义快路径（T1）
;
; 与 tools/ahk-bench 下其它基准的区别（重要，别混淆）：
;   其它 bench_* 是「选型期」的双实现对照基准 —— old/new 两份实现都复刻在脚本里，
;   用来量化「改造值不值得做」。T1 / T6 落地后，那些脚本的 new 侧是**副本**，
;   生产代码再改也不会跟着变 —— 对生产回归**零防护力**。
;
;   本脚本反过来：**直接 #Include 生产代码并测它**，是 CI 门禁（T11）的输入。
;   判据见 tools/ahk-bench/gate.py：跨轮 p50 中位数 ≤ 基线 × K。
;
; 被测：infrastructure/json_serializer.ahk 的 JSONSerializer._EscapeString
;   （三段式快路径，原逐字符实现保留为 _EscapeStringCharByChar）
;
; 输出：%AHK_BENCH_OUT%\prod_escape.csv + prod_escape.done
;   每行：`metric,<name>,p50=..,p95=..,max=..,min=..,mean=..,n=..,len=..,raw_ms=..,us_per_call=..`
;   ⚠️ len= 是 payload 实际长度，gate.py 会校验它 —— 防止 payload 构造写错后
;      测到空串（耗时极低、永远 PASS）却没人发现。这是基准侧的「阳性对照」。
;
; ⚠️ p50 是**归一化值**（无量纲），不是毫秒：
;   `p50 = 一批调用的毫秒 ÷ 同进程内紧邻测得的参考负载毫秒`
;   raw_ms 是未归一化的原始毫秒，仅供人工排障，门禁不判它。
;
;   为什么必须归一化（2026-09-15 实测，CI 托管 runner）：同一份代码、5 次运行，
;   相对固定基线的倍率是 0.52× / 0.79× / 0.92× / 1.07× / 1.87~2.09× ——
;   **同代码跨 run 散布达 3.7~3.9 倍**，且每次都是 5 个 metric 同步移动（整机速度因子，
;   不是某条代码路径退化）。绝对阈值在这上面两头不讨好：
;     · 慢机器上无变化就 FAIL（本 run 就是）；
;     · 快机器上真实的 2× 回退会读成 0.52×2=1.04× 而 PASS —— 漏报更危险。
;   用与被测代码无关、但同为 AHK 解释器负载的参考负载做分母，可把这层因子约掉。
;   同批数据用兜底路径做分母的粗算：散布从 3.7~3.9× 降到 1.10~1.17×。
;
; 计时口径：单次调用太快（快路径 < 0.01 ms），直接计时会被 QPC 自身开销淹没。
;   故以「一批 BATCH_CALLS 次调用」为一次采样，跑 BATCH_ROUNDS 轮取分位数。
;   判据用 p50（归一化后的无量纲值，见上），us_per_call 与 raw_ms 仅供人工复核量级。
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"
#Include "../../infrastructure/json_serializer.ahk"

; ⚠️ 顶层不要再写 `global`（v2 里 global 只在函数内有效）；自动执行段的赋值本身就是全局
BATCH_CALLS := 200
BATCH_ROUNDS := 25

; 参考负载规模。调到「单次采样几毫秒」：够大以压住 QPC 自身开销，又不至于拖慢基准。
; 实测 AHK 解释器一次 arr[i]+=i 约 0.39 µs → 8192×4 ≈ 13 ms/采样。
REF_OPS := 8192
REF_LOOPS := 4

; -----------------------------------------------------------------
; 负载构造。三档，分别对应三条不同的代码路径：
;   plain_*  → 快路径（不含任何需转义字符），T1 收益最大的一条
;   mixed_2k → 含引号/反斜杠/换行，走 StrReplace 批量替换
;   ctrl_*   → 含需 \uXXXX 的控制字符，走 _EscapeStringCharByChar 兜底
; -----------------------------------------------------------------
BuildPlain(targetLen) {
    ; 用固定片段重复拼接，长度可控且跨机器完全一致（不能用随机数/时间）
    unit := "The quick brown fox jumps over the lazy dog 0123456789 "
    s := ""
    while StrLen(s) < targetLen
        s .= unit
    return SubStr(s, 1, targetLen)
}

BuildMixed(targetLen) {
    ; 每 ~12 个字符插入一个需转义字符，模拟真实配置/日志
    Q := Chr(34), B := Chr(92)
    fill := "config_value_abc_def_"
    s := "", i := 0
    special := [Q, B, Chr(10), Chr(9)]
    while StrLen(s) < targetLen {
        s .= fill
        s .= special[Mod(i, special.Length) + 1]
        i++
    }
    return SubStr(s, 1, targetLen)
}

BuildCtrl(targetLen) {
    ; 含 0x01（无短写法）→ 强制走逐字符兜底路径
    fill := "log_line_with_ctrl_"
    s := "", i := 0
    while StrLen(s) < targetLen {
        s .= fill
        if Mod(i, 5) = 0
            s .= Chr(1)
        i++
    }
    return SubStr(s, 1, targetLen)
}

; 生产实现的包装。⚠️ 不直接把 `JSONSerializer._EscapeString` 当函数对象传：
; v2 里引用静态方法得到的是 BoundFunc，调用约定不直观，包一层最稳。
CallProdEscape(s) {
    return JSONSerializer._EscapeString(s)
}

; 一批调用。⚠️ AHK v2 箭头函数只支持表达式体，所以批次循环必须写成具名函数
Batch(fn, s, n) {
    i := 0
    while i < n {
        fn.Call(s)
        i++
    }
}

; -----------------------------------------------------------------
; 机器速度参考负载
;
; 要求：与被测代码路径**无关**（否则被测代码一改，参考值跟着变，归一化会把真实
; 回归也抵消掉），但**同为 AHK 解释器负载**（才能反映机器/解释器速度）。
; 故用预分配 Array 上的算术循环：不分配 → 不触发 GC，抖动小。
;
; ⚠️ 这里刻意不复用 bench_prod_tick.ahk 里那份同名的 RefBatch/MeasureRef：
;   放进共享的 _harness.ahk 会与 prod_tick 的本地定义重名（AHK v2 报重复定义），
;   而改 prod_tick 去用共享版会动到一个已有有效基线的基准 —— 不值得。
;   待 prod_tick 下次重取基线时一并统一。
; -----------------------------------------------------------------
RefBatch(arr, n) {
    i := 1
    s := 0
    while i <= n {
        arr[i] := arr[i] + i
        s += arr[i]
        i++
    }
    return s
}

MeasureRef() {
    global REF_OPS, REF_LOOPS, BATCH_ROUNDS
    arr := []
    i := 1
    while i <= REF_OPS {
        arr.Push(i)
        i++
    }
    samples := []
    r := 1
    while r <= BATCH_ROUNDS {
        t0 := HighResNow()
        k := 1
        while k <= REF_LOOPS {
            RefBatch(arr, REF_OPS)
            k++
        }
        samples.Push((HighResNow() - t0) * 1000)
        r++
    }
    return samples
}

RunCase(name, s, calls := 0) {
    global BATCH_CALLS, BATCH_ROUNDS, REF_OPS, REF_LOOPS
    if calls = 0
        calls := BATCH_CALLS
    samples := []
    i := 1
    while i <= BATCH_ROUNDS {
        t0 := HighResNow()
        Batch(CallProdEscape, s, calls)
        samples.Push((HighResNow() - t0) * 1000)
        i++
    }
    ; 参考负载紧邻测量：同进程、同一段机器状态，才能约掉整机速度因子
    refSamples := MeasureRef()
    sorted := SortNums(samples)
    rs := SortNums(refSamples)
    raw := Pct(sorted, 0.50)
    ref := Pct(rs, 0.50)
    BenchWrite("info,ref_" . name . ",p50=" . Round(ref, 6)
        . ",ops=" . REF_OPS . ",loops=" . REF_LOOPS . ",n=" . rs.Length)
    ; ⚠️ p50 及各个分位数都是归一化值（除以 ref）；raw_ms 保留原始毫秒供排障
    BenchWrite("metric," . name
        . ",p50=" . Round(raw / ref, 6)
        . ",p95=" . Round(Pct(sorted, 0.95) / ref, 6)
        . ",max=" . Round(sorted[sorted.Length] / ref, 6)
        . ",min=" . Round(sorted[1] / ref, 6)
        . ",mean=" . Round(Mean(sorted) / ref, 6)
        . ",n=" . sorted.Length
        . ",len=" . StrLen(s)
        . ",calls=" . calls
        . ",raw_ms=" . Round(raw, 4)
        . ",us_per_call=" . Round(raw * 1000 / calls, 4))
}

Main() {
    BenchInit("prod_escape")
    BenchWrite("# bench=prod_escape ahk=" . A_AhkVersion
        . " calls_per_sample=" . BATCH_CALLS . " samples=" . BATCH_ROUNDS)

    RunCase("escape_plain_2k", BuildPlain(2048))
    RunCase("escape_plain_8k", BuildPlain(8192))
    ; 64KB 档：快路径省下的是「整串扫描」，负载越长、快路径失效的差距越明显
    ; （实测 2K 只 +16%、8K +22%，64K 可放大到能稳定判别的量级）。批次数降到 40 控时。
    RunCase("escape_plain_64k", BuildPlain(65536), 40)
    RunCase("escape_mixed_2k", BuildMixed(2048))
    ; ctrl 档走逐字符兜底路径，单次约 1.5 ms（比快路径慢 50 倍），故 payload 只取 512
    ; 以控制单轮耗时；它要守的是「兜底路径不要变得更慢」。
    RunCase("escape_ctrl_512", BuildCtrl(512))

    ; 等价性自校验：快路径必须与原逐字符实现逐字节一致。
    ; ⚠️ 这是基准里的正确性网 —— 只测耗时的话，「为了快而改错」不会被发现。
    ; 真正的等价性覆盖在 AHK 单测 JSONSerializerEscapeTests（含 7 项变异对照），
    ; 这里只做一次廉价的一致性兜底，防止生产实现被改动后基准仍在测「别的东西」。
    bad := 0
    i := 0
    while i <= 127 {
        for s in [Chr(i), "x" Chr(i) "y"] {
            if JSONSerializer._EscapeStringCharByChar(s) != JSONSerializer._EscapeString(s)
                bad++
        }
        i++
    }
    BenchWrite("equiv,ascii_scan,diffs=" . bad)

    BenchDone()
}

Main()
ExitApp(0)
