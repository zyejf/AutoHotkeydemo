; =================================================================
; bench_json_escape —— JSON 字符串转义：O(n²) 逐字符 vs 快路径 + 批量替换
;
; 原型：infrastructure/json_serializer.ahk:100-128 `_EscapeString`
;       逐字符 SubStr + 逐字符 result .= c，字符串不可变 → O(n²) 拷贝
;
; 热路径：每条日志 / 每次配置保存 / 每条 IPC 消息 / 每次备份，都会走到
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

; -----------------------------------------------------------------
; 优化前：原样复刻 json_serializer.ahk:100-128
; -----------------------------------------------------------------
EscapeOld(str) {
    result := ""
    pos := 1
    len := StrLen(str)
    while pos <= len {
        c := SubStr(str, pos, 1)
        code := Ord(c)
        if code = 8
            result .= "\b"
        else if code = 9
            result .= "\t"
        else if code = 10
            result .= "\n"
        else if code = 12
            result .= "\f"
        else if code = 13
            result .= "\r"
        else if code = 34
            result .= "\`""
        else if code = 92
            result .= "\\"
        else if code < 32
            result .= "\u" Format("{:04X}", code)
        else
            result .= c
        pos++
    }
    return result
}

; -----------------------------------------------------------------
; 优化后：
;   ① 快路径：不含任何需转义字符 → 原样返回（配置/日志里绝大多数走这条）
;   ② 含「未覆盖的控制字符」（需 \uXXXX）→ 退回原算法，保证行为完全一致
;   ③ 其余：用原生 StrReplace 批量替换（一次遍历，避免 n 次字符串重建）
; -----------------------------------------------------------------
EscapeNew(str) {
    if !InStr(str, '"') && !InStr(str, "\") && !RegExMatch(str, "[\x00-\x1F]")
        return str
    if RegExMatch(str, "[\x00-\x08\x0B\x0E-\x1F]")
        return EscapeOld(str)
    s := StrReplace(str, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`t", "\t")
    s := StrReplace(s, "`b", "\b")
    s := StrReplace(s, "`f", "\f")
    return s
}

; -----------------------------------------------------------------
; 构造测试用例
; -----------------------------------------------------------------
BuildPlain(n) {
    s := ""
    while StrLen(s) < n
        s .= "abcdefghijklmnopqrstuvwxyz0123456789"
    return SubStr(s, 1, n)
}

BuildEscapeDense(n) {
    s := ""
    while StrLen(s) < n
        s .= 'a"b\c`nd`te'      ; 密集出现引号 / 反斜杠 / 换行 / 制表
    return SubStr(s, 1, n)
}

BuildConfigLike(n) {
    ; 贴近真实：少量转义，主体是普通文本
    s := ""
    while StrLen(s) < n
        s .= '{"groupId":"grp-001","name":"技能组 A","keys":["F1","F2","F3"]},'
    return SubStr(s, 1, n)
}

Main() {
    BenchInit("json_escape")
    BenchWrite("# bench_json_escape —— JSON 转义 O(n^2) vs 快路径")
    BenchWrite("# 单位：毫秒/次调用；us_per_kchar = 每千字符微秒")

    cases := [
        ["plain_8k",   BuildPlain(8192),      30],
        ["dense_4k",   BuildEscapeDense(4096), 15],
        ["config_2k",  BuildConfigLike(2048), 60]
    ]

    for cs in cases {
        name := cs[1], s := cs[2], iters := cs[3]

        ; 正确性：两份实现必须产出完全相同的字符串
        a := EscapeOld(s)
        b := EscapeNew(s)
        same := (a = b) ? "YES" : "NO"

        to := TimeIt(() => EscapeOld(s), iters)
        tn := TimeIt(() => EscapeNew(s), iters)

        BenchStat("old," . name, to)
        BenchStat("new," . name, tn)

        so := SortNums(to), sn := SortNums(tn)
        p50o := Pct(so, 0.5), p50n := Pct(sn, 0.5)
        kchars := StrLen(s) / 1000
        BenchWrite("cmp," . name . ",len=" . StrLen(s)
            . ",p50_old_ms=" . Round(p50o, 4)
            . ",p50_new_ms=" . Round(p50n, 4)
            . ",speedup=" . Round(p50o / ((p50n > 0) ? p50n : 0.0001), 2)
            . ",us_per_kchar_old=" . Round(p50o * 1000 / kchars, 2)
            . ",us_per_kchar_new=" . Round(p50n * 1000 / kchars, 2)
            . ",identical=" . same)
    }

    BenchDone()
}

Main()
ExitApp(0)
