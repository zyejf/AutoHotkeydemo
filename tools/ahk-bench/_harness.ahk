; =================================================================
; _harness.ahk —— AHK 重构基准公共框架（自包含，不依赖任何生产代码）
;
; 提供：
;   - 输出目录解析 + CSV 写出 + .done 哨兵（run.sh 轮询它）
;   - 内存采样（WorkingSet / PrivateUsage，KB）
;   - CPU 采样（kernel+user，ms）
;   - OnError 守卫：GUI 子系统下未捕获错误会弹模态框导致静默挂起
;
; 纯计算原语（QPC 时钟 / 快排 / 分位数）在 tools\_ahk_common.ahk，与 ahk-probes
; 共用一份（TD-004）。本文件只留**与 bench 输出约定绑定**的部分：输出目录取自
; AHK_BENCH_OUT、CSV 写 UTF-8（带 BOM）、BenchInit 支持 append —— 这三点 probes
; 侧都不同，强行统一会动到已有有效基线的基准。
;
; 输出：%TEMP%\ahkbench\<id>.csv  +  <id>.done 哨兵（run.sh 轮询它）
;
; ⚠️ AHK v2.0.26 已验证的坑（改本文件前请先读 tools/ahk-probes/README.md）：
;   catch as e（不是 catch e） / Array 没有 Sort() / 回调必须是函数对象 /
;   脚本级变量不会被箭头函数闭包捕获（assume-local）→ 必须 global
; =================================================================
#Requires AutoHotkey v2.0

; 时钟 / 快排 / 分位数：与 ahk-probes 共用（TD-004）。相对路径对 bench 与 probes
; 两侧都成立 —— AHK 解析 ..\ 时，无论按 A_ScriptDir 还是按 include 所在文件取，
; 落点都是 tools\（主脚本与 _harness.ahk 同目录）。
#Include "..\_ahk_common.ahk"

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

; 输出一行：<tag>,p50=..,p95=..,max=..,min=..,mean=..,n=..
; SortNums / Pct / Mean / ArrMax / ArrMin 来自 ..\_ahk_common.ahk
BenchStat(tag, arr) {
    s := SortNums(arr)
    BenchWrite(tag . ",p50=" . Round(Pct(s, 0.50), 4)
        . ",p95=" . Round(Pct(s, 0.95), 4)
        . ",max=" . Round(ArrMax(s), 4)
        . ",min=" . Round(ArrMin(s), 4)
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
