; =================================================================
; _harness.ahk —— AHK 重构基准公共框架（自包含，不依赖任何生产代码）
;
; 提供：
;   - QPC 高精度计时（秒，double）
;   - 内存采样（WorkingSet / PrivateUsage，KB）
;   - CPU 采样（kernel+user，ms）
;   - 分位数统计（p50/p95/max/min/mean）
;   - OnError 守卫：GUI 子系统下未捕获错误会弹模态框导致静默挂起
;
; 输出：%TEMP%\ahkbench\<id>.csv  +  <id>.done 哨兵（run.sh 轮询它）
;
; ⚠️ AHK v2.0.26 已验证的坑（改本文件前请先读 tools/ahk-probes/README.md）：
;   catch as e（不是 catch e） / Array 没有 Sort() / 回调必须是函数对象 /
;   脚本级变量不会被箭头函数闭包捕获（assume-local）→ 必须 global
; =================================================================
#Requires AutoHotkey v2.0

global BENCH_ID    := ""
global BENCH_DIR   := ""
global BENCH_FILE  := ""
global BENCH_DONE  := ""
global BENCH_GUARD := true

; ---------------------------------------------------------------
; 初始化。guard=false 时不注册 OnError 守卫（用例要自己接管错误处理时用）。
; 实测：OnError 注册后摘不掉（OnError(cb, -1) 无效），且多个回调会全部执行，
; 所以只能「一开始就不注册」。
; ---------------------------------------------------------------
BenchInit(id, guard := true, append := false) {
    global BENCH_ID, BENCH_DIR, BENCH_FILE, BENCH_DONE, BENCH_GUARD
    BENCH_ID := id
    ; ⚠️ run.sh 会显式传 AHK_BENCH_OUT（Windows 路径）。
    ; 不能各自去取 %TEMP%：Git Bash 的 $TEMP 与 Windows %TEMP% 可能不是同一个目录，
    ; 那样 run.sh 会永远轮询不到哨兵文件。
    BENCH_DIR := EnvGet("AHK_BENCH_OUT")
    if BENCH_DIR = "" {
        BENCH_DIR := EnvGet("TEMP")
        if BENCH_DIR = ""
            BENCH_DIR := EnvGet("LOCALAPPDATA") . "\Temp"
        if BENCH_DIR = ""
            BENCH_DIR := "C:\Windows\Temp"
        BENCH_DIR .= "\ahkbench"
    }
    try DirCreate(BENCH_DIR)
    BENCH_FILE := BENCH_DIR . "\" . id . ".csv"
    BENCH_DONE := BENCH_DIR . "\" . id . ".done"
    BENCH_GUARD := guard
    ; .done 哨兵必须每次都清（否则上一轮的哨兵会让 run.sh 立刻返回）；
    ; CSV 在 append 模式下保留，供多个用例各自独立进程追加。
    try FileDelete BENCH_DONE
    if !append
        try FileDelete BENCH_FILE
    if guard
        OnError(OnBenchError)
    return BENCH_FILE
}

OnBenchError(e, mode) {
    global BENCH_GUARD, BENCH_FILE
    if !BENCH_GUARD
        return -1
    msg := StrReplace(StrReplace(e.Message, ",", ";"), "`n", " ")
    ; e.File 必须带上：#Include 之后只看行号无法定位是哪个文件
    ; e.Stack 带上：调用点报错时只看行号常常指向「调用方」而非真正出错的表达式
    stack := StrReplace(StrReplace(e.Stack, ",", ";"), "`n", " | ")
    try FileAppend("FATAL," . msg . ",line=" . e.Line . ",file=" . e.File
        . ",stack=" . stack . "`n", BENCH_FILE, "UTF-8")
    BenchDone()
    ExitApp(99)
}

BenchWrite(line) {
    global BENCH_FILE
    ; ⚠️ 必须显式 UTF-8：FileAppend 默认走系统 ANSI（本机 GBK），
    ; 中文注释与中文异常消息会被写成 GBK 字节，report.py 按 UTF-8 读回来就是乱码。
    FileAppend(line . "`n", BENCH_FILE, "UTF-8")
}

BenchDone() {
    global BENCH_DONE
    try FileAppend("done`n", BENCH_DONE)
}

; ---------------------------------------------------------------
; QPC 高精度时钟（秒）。A_TickCount 步进 15.52ms，测不了毫秒级差异。
; ---------------------------------------------------------------
HighResNow() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c / freq
}

SleepUntil(target) {
    while HighResNow() < target
        Sleep(0)
    return HighResNow()
}

; ---------------------------------------------------------------
; 内存采样：伪句柄 -1 = 当前进程。
; PROCESS_MEMORY_COUNTERS_EX 偏移：16 = WorkingSetSize，72 = PrivateUsage。
; ---------------------------------------------------------------
SnapMemKB() {
    pmc := Buffer(80, 0)
    NumPut("UInt", 80, pmc, 0)
    if !DllCall("psapi\GetProcessMemoryInfo", "Ptr", -1, "Ptr", pmc, "UInt", 80)
        return [-1, -1]
    return [NumGet(pmc, 16, "Int64") // 1024, NumGet(pmc, 72, "Int64") // 1024]
}

; ---------------------------------------------------------------
; CPU 采样：FILETIME 单位为 100ns，/10000 得毫秒。
; GetProcessTimes(h, creation, exit, kernel, user) → kernel@16 user@24
; ---------------------------------------------------------------
SnapCpuMs() {
    ft := Buffer(32, 0)
    if !DllCall("kernel32\GetProcessTimes", "Ptr", -1
        , "Ptr", ft, "Ptr", ft.Ptr + 8, "Ptr", ft.Ptr + 16, "Ptr", ft.Ptr + 24)
        return -1
    return (NumGet(ft, 16, "Int64") + NumGet(ft, 24, "Int64")) / 10000
}

; ---------------------------------------------------------------
; 统计：AHK 2.0.26 的 Array 没有 Sort() 方法，自写快排。
; ⚠️ _Pct 索引 = Ceil(n*p)：样本不足 40 时 P95 实际退化成接近最大值，
;    所以基准一律取足样本，并同时给出中位数与最大值。
; ---------------------------------------------------------------
SortNums(arr) {
    s := arr.Clone()
    if s.Length > 1
        QSort(s, 1, s.Length)
    return s
}

QSort(a, lo, hi) {
    if lo >= hi
        return
    i := lo, j := hi, p := a[(lo + hi) // 2]
    while i <= j {
        while a[i] < p
            i++
        while a[j] > p
            j--
        if i <= j {
            tmp := a[i], a[i] := a[j], a[j] := tmp
            i++, j--
        }
    }
    if lo < j
        QSort(a, lo, j)
    if i < hi
        QSort(a, i, hi)
}

Pct(arr, p) {
    n := arr.Length
    if n = 0
        return 0
    i := Ceil(n * p)
    i := Max(1, Min(i, n))
    return arr[i]
}

Mean(arr) {
    n := arr.Length
    if n = 0
        return 0
    s := 0
    for v in arr
        s += v
    return s / n
}

; 输出一行：<tag>,p50=..,p95=..,max=..,min=..,mean=..,n=..
BenchStat(tag, arr) {
    s := SortNums(arr)
    BenchWrite(tag . ",p50=" . Round(Pct(s, 0.50), 4)
        . ",p95=" . Round(Pct(s, 0.95), 4)
        . ",max=" . Round(s[s.Length], 4)
        . ",min=" . Round(s[1], 4)
        . ",mean=" . Round(Mean(s), 4)
        . ",n=" . s.Length)
}

; 计时一次调用，返回毫秒
TimeIt(fn, iterations) {
    samples := []
    i := 1
    while i <= iterations {
        t0 := HighResNow()
        fn.Call()
        samples.Push((HighResNow() - t0) * 1000)
        i++
    }
    return samples
}
