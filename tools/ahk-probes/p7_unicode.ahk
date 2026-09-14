; ----------------------------------------------------------------------------
; P7：Unicode 往返正确性
;   AHK v2 是 UTF-16（BMP 外字符占 2 个 code unit）。本项目 IPC 走 UTF-8 管道 +
;   自研 JSON 解析，任何一环按「字符数」而不是「code unit 数」处理都会错位。
; 用例：BMP 中文 / 平假名 / emoji（代理对）/ 组合字符 / RTL / 64KB 边界 /
;       StrPut-StrGet 多码页往返 / 文件往返（UTF-8、UTF-16）。
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    ProbeInit("p7_unicode")
    ProbeNote("P7 Unicode 往返：AHK v2 内部 UTF-16")
    ProbeWrite("case,codeunits,file_utf8,file_utf16,strput_utf8,strput_utf16,strput_cp936,note")

    d := EnvGet("TEMP") . "\ahkprobe\u7"
    DirCreate(d)

    cases := []
    cases.Push(["bmp_中文", "中文测试"])
    cases.Push(["bmp_日文", "ひらがな"])
    cases.Push(["emoji_1", Chr(0x1F600)])                       ; 😀 代理对
    cases.Push(["emoji_3", Chr(0x1F600) . Chr(0x1F601) . Chr(0x1F602)])
    cases.Push(["combining", "e" . Chr(0x0301) . "a" . Chr(0x0308)])
    cases.Push(["rtl", "אבג"])
    cases.Push(["mixed", "A" . Chr(0x1F600) . "中" . Chr(0x0301)])
    cases.Push(["ctrl_chars", "tab`t nl`n quote`" backslash\\"])
    cases.Push(["bmp_max", Chr(0xFFFF) . Chr(0xFFFD)])
    cases.Push(["null_edge", "a" . Chr(0) . "b"])               ; 嵌入 NUL

    for c in cases {
        Run1(d, c[1], c[2], "")
    }

    ; 64KB 边界（超过一个 UTF-16 串的常见缓冲假设）
    big := ""
    Loop 33000
        big .= "中"                           ; 66000 code units
    Run1(d, "big_66k_units", big, "len=" . StrLen(big))

    big2 := ""
    Loop 33000
        big2 .= Chr(0x1F600)                  ; 66000 code units（33000 个码点）
    Run1(d, "big_emoji_33k", big2, "len=" . StrLen(big2))

    try DirDelete(d, true)
    ProbeDone()
}

Run1(dir, tag, s, note) {
    cu := StrLen(s)
    f8 := dir . "\" . tag . "_u8.txt"
    f16 := dir . "\" . tag . "_u16.txt"

    r8 := Try_(() => (FileAppend(s, f8, "UTF-8-RAW"), (FileRead(f8, "UTF-8-RAW") = s) ? "ok" : "MISMATCH"))
    r16 := Try_(() => (FileAppend(s, f16, "UTF-16-RAW"), (FileRead(f16, "UTF-16-RAW") = s) ? "ok" : "MISMATCH"))

    ; ⚠️ AHK v2.0.26 里 StrPut(s, 65001) 这种**数字码页**会报
    ;    "Parameter #2 of StrPut is invalid."，必须写 "UTF-8" / "CP936" 这样的字符串。
    p8 := Try_(() => Rt(s, "UTF-8"))
    p16 := Try_(() => Rt(s, "UTF-16"))
    p936 := Try_(() => Rt(s, "CP936"))

    ProbeWrite(tag . "," . cu . "," . r8 . "," . r16 . "," . p8 . "," . p16 . "," . p936 . "," . note)
}

; StrPut → StrGet 往返是否恒等
Rt(s, cp) {
    n := StrPut(s, cp)
    buf := Buffer(n, 0)
    StrPut(s, buf, cp)
    back := StrGet(buf, cp)
    return (back = s) ? "ok" : ("DIFF(" . StrLen(back) . " vs " . StrLen(s) . ")")
}

Try_(fn) {
    try {
        return fn()
    } catch as e {
        return "ERR:" . StrReplace(e.Message, ",", ";")
    }
}

Main()
ExitApp
