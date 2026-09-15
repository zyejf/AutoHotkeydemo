; =================================================================
; _ahk_common.ahk —— ahk-bench 与 ahk-probes 共用的底层原语
;
; 由来（TD-004，2026-09-16）：tools/ahk-bench/_harness.ahk 与
; tools/ahk-probes/_harness.ahk 各自抄了一份 QPC 时钟 / 快排 / 分位数，
; 而且**抄歪了** —— 两份 `Pct` 语义不同：
;     bench  版：假定入参已升序，只做索引
;     probes 版：内部自己排一遍序
; 同名不同义是最容易产出「看起来对、其实是错的」数字的一类债：改其中一份时
; 没人会想到另一份，而错的那份不会报任何错。本文件把它们合成一套语义。
;
; 分工：本文件只放**与输出无关的纯计算原语**。
;   输出目录解析 / CSV 编码 / 哨兵语义两侧刻意不同（见各自 _harness.ahk 的注释），
;   不合并 —— 统一它们会动到已有有效基线的基准，得不偿失。
;
; ⚠️ 重名禁区（AHK v2 同名函数重复定义是**加载期报错**，不是覆盖）：
;   本文件定义的名字，include 链上任何脚本都不得再定义一份。当前占用：
;       HighResNow / SleepUntil / SortNums / QSort / Pct / Mean / ArrMax / ArrMin
;   （不叫 Max / Min 是因为那是 AHK 内置函数，定义同名函数会把它遮蔽掉。）
;   往这里加函数前，先确认 22 个 bench_*/p*_*.ahk 脚本里没有同名定义。
;
; 语义约定（务必遵守，否则数字会静默变错）：
;   Pct(arr, p)   —— arr **必须已升序**；只做索引，不排序。
;   SortNums(arr) —— 返回升序副本，不改原数组。
;   要对未排序数组取分位数就写 `Pct(SortNums(arr), p)`，**不要**让 Pct 偷偷
;   自己排序：那会让已排序的调用点白白多排几次，还把「调用方排没排序」这个
;   本该显式的信息藏起来 —— 两份 harness 当初就是这么分岔的。
; =================================================================
#Requires AutoHotkey v2.0

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

; 忙等到目标时刻（HighResNow 基准，单位秒），返回实际醒来时刻。
; ⚠️ 连续占用 AHK 主线程：Sleep(0) 不放行其它 AHK 定时器。
SleepUntil(target) {
    while HighResNow() < target
        Sleep(0)
    return HighResNow()
}

; ---------------------------------------------------------------
; 统计：AHK 2.0.26 的 Array 没有 Sort() 方法，自写快排。
; ---------------------------------------------------------------
; 返回升序副本，原数组不动。
SortNums(arr) {
    s := arr.Clone()
    if s.Length > 1
        QSort(s, 1, s.Length)
    return s
}

; 原地快排（Hoare 分区）。lo >= hi 直接返回既是剪枝，也是递归终止条件。
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

; 分位数。**入参必须已升序**（先调 SortNums）。
; ⚠️ 索引 = Ceil(n*p)：样本不足 40 时 P95 实际退化成接近最大值，
;    所以测时延一律取足样本，并同时给出中位数与最大值。
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

ArrMax(arr) {
    m := -1.0e308
    for v in arr
        if v > m
            m := v
    return arr.Length ? m : 0
}

ArrMin(arr) {
    m := 1.0e308
    for v in arr
        if v < m
            m := v
    return arr.Length ? m : 0
}
