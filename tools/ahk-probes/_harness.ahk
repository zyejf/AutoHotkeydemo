; ============================================================================
; _harness.ahk —— AHK 探针公共框架
;
; 背景：AutoHotkey64.exe 是 GUI 子系统程序，cmd / PowerShell 启动它不会等待，
;       且 stdout 不可靠。因此所有探针统一：
;         1) 结果 FileAppend 到 %TEMP%\ahkprobe\<id>.csv
;         2) 结束前写 <id>.done 哨兵
;         3) Bash 侧轮询 .done 判断结束（不依赖 stdout、不依赖退出码）
;
; 约定（踩坑记录，勿违反）：
;   - AHK v2 脚本级变量**不会被箭头函数闭包捕获**（函数 assume-local）
;     → 探针主体一律包在 Main() 里，需要跨函数访问的变量显式 global。
;   - 变量名禁用 log / in / out 等内置名（log 与内置 Log() 冲突）。
;   - `while i<=n { ... }` 不能写单行块体，必须多行。
;   - 末尾必须 ExitApp；若探针依赖定时器，需先 #Persistent 或保持热键存在。
; ============================================================================

global PROBE_ID   := ""
global PROBE_DIR  := ""
global PROBE_FILE := ""
global PROBE_T0   := 0
global PROBE_GUARD_ON := true

; ---------------------------------------------------------------------------
; 初始化：准备输出目录、清理上一次的 csv / done
; ---------------------------------------------------------------------------
; guard=false 时**不注册** OnError 守卫（探针要自己接管错误处理时用）。
; 实测：先注册再摘不掉（OnError(cb, -1) 无效），且多回调会让守卫抢先执行。
ProbeInit(id, guard := true) {
    global PROBE_ID, PROBE_DIR, PROBE_FILE, PROBE_T0, PROBE_GUARD_ON
    PROBE_ID   := id
    PROBE_DIR  := EnvGet("TEMP") . "\ahkprobe"
    PROBE_FILE := PROBE_DIR . "\" . id . ".csv"
    try DirCreate(PROBE_DIR)
    if FileExist(PROBE_FILE)
        FileDelete(PROBE_FILE)
    if FileExist(PROBE_DIR . "\" . id . ".done")
        FileDelete(PROBE_DIR . "\" . id . ".done")
    PROBE_T0 := HighResNow()
    PROBE_GUARD_ON := guard
    ; 关键守卫：AutoHotkey64.exe 是 GUI 子系统，未捕获错误会弹**模态错误框**并永久挂起，
    ; 探针就会「静默卡死」。注册 OnError 把错误写进 CSV 后主动 ExitApp。
    if guard
        OnError(OnProbeError)
}

; 探针要自己接管错误处理时先调 ProbeUnguard()：AHK v2 的 OnError 支持**多个**回调，
; 摘不掉前一个（实测 OnError(cb, -1) 无效），只能让守卫自己让位。
ProbeUnguard() {
    global PROBE_GUARD_ON
    PROBE_GUARD_ON := false
}

; 注意：本版本 AHK v2 的 catch 语法是 `catch as e`，写成 `catch e` 会被解析成
; 「捕获类 e」→ 加载期报 "Invalid class"。
OnProbeError(e, mode) {
    global PROBE_GUARD_ON
    if !PROBE_GUARD_ON
        return -1          ; 让位给探针自己的 OnError
    msg := ""
    try
        msg := e.Message . " @ " . e.What . ":" . e.Line
    catch as e2
        msg := "(无法读取异常信息)"
    ProbeWrite("ERROR," . StrReplace(StrReplace(msg, "`n", " "), ",", ";") . ",mode=" . mode)
    ProbeDone()
    ExitApp(99)
    return 1
}

; ---------------------------------------------------------------------------
; 写一行 CSV（字段自行用逗号拼接）
; ---------------------------------------------------------------------------
ProbeWrite(line) {
    global PROBE_FILE
    FileAppend(line . "`n", PROBE_FILE, "UTF-8-RAW")
}

; 注释行（以 # 开头，后处理时跳过）
ProbeNote(txt) {
    ProbeWrite("# " . txt)
}

; 结束：写 done 哨兵（内容含耗时毫秒）
ProbeDone() {
    global PROBE_DIR, PROBE_ID, PROBE_T0
    FileAppend(Round((HighResNow() - PROBE_T0) * 1000, 3)
        , PROBE_DIR . "\" . PROBE_ID . ".done", "UTF-8-RAW")
}

; ---------------------------------------------------------------------------
; 高精度时钟（QPC，秒）。比 A_TickCount 精确三个数量级。
; ---------------------------------------------------------------------------
HighResNow() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c / freq
}

; 忙等到目标时刻（HighResNow 基准，单位秒）
SleepUntil(target) {
    while HighResNow() < target
        Sleep(0)
}

; ---------------------------------------------------------------------------
; 统计工具
; ---------------------------------------------------------------------------
; 分位数。注意：索引 = Ceil(n*p)。n 太小时 p=0.95 会退化成最大值（P100），
; 经验：算 P95 至少要 40 个样本，否则断言的其实是 max。
; ⚠️ AHK 2.0.26 的 Array **没有 Sort() 方法**（该方法在更高版本才引入），
; 实测报错 "This value of type Array has no method named Sort"。故自写快排。
_SortNums(arr) {
    s := arr.Clone()
    if s.Length > 1
        _QSort(s, 1, s.Length)
    return s
}

_QSort(a, lo, hi) {
    i := lo
    j := hi
    p := a[(lo + hi) >> 1]
    while i <= j {
        while a[i] < p
            i += 1
        while a[j] > p
            j -= 1
        if i <= j {
            t := a[i]
            a[i] := a[j]
            a[j] := t
            i += 1
            j -= 1
        }
    }
    if lo < j
        _QSort(a, lo, j)
    if i < hi
        _QSort(a, i, hi)
}

_Pct(arr, p) {
    if arr.Length = 0
        return 0
    s := _SortNums(arr)
    n := s.Length
    i := Integer(Ceil(n * p))
    i := (i < 1) ? 1 : ((i > n) ? n : i)
    return s[i]
}

_Median(arr) {
    return _Pct(arr, 0.5)
}

_Max(arr) {
    m := -1.0e308
    for v in arr
        if v > m
            m := v
    return arr.Length ? m : 0
}

_Min(arr) {
    m := 1.0e308
    for v in arr
        if v < m
            m := v
    return arr.Length ? m : 0
}

_Mean(arr) {
    if arr.Length = 0
        return 0
    s := 0
    for v in arr
        s += v
    return s / arr.Length
}

; 一次性输出 p50/p95/max/min/mean/n
_Stats(prefix, arr) {
    ProbeWrite(prefix . ",p50=" . Round(_Pct(arr, 0.5), 3)
        . ",p95=" . Round(_Pct(arr, 0.95), 3)
        . ",max=" . Round(_Max(arr), 3)
        . ",min=" . Round(_Min(arr), 3)
        . ",mean=" . Round(_Mean(arr), 3)
        . ",n=" . arr.Length)
}
