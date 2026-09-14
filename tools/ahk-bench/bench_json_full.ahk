; =================================================================
; bench_json_full —— T9 · 序列化流式输出：五种累加方式对照
;
; 协议来源：docs/refactor/plan-C-evaluation.md §5
;   现有基线   M1 = 1.29 ms（2 KB p50）、M2 = 5.44 ms（8 KB p50）
;   T1 后目标  M1 <= 0.10 ms、M2 <= 0.30 ms
;   T9 后目标  M1 <= 0.05 ms、M2 <= 0.15 ms
;   一票否决项：峰值内存不得高于旧实现
;
; 五个实现共用同一套缩进/分派/转义规则，**只换累加方式**：
;   concat  —— 原样复刻 json_serializer.ahk（递归返回 + result .= ...）
;   parts   —— 递归收集进数组，最后一次拼接
;   buf     —— 预分配 Buffer + StrPut 索引写入，容量倍增
;   stream  —— 单一 ByRef 累加器（规范流式写法，无中间字符串返回）
;   streamp —— stream + VarSetStrCapacity 预分配容量
;
; 转义函数单独参数化，因为 T1（转义快路径）与 T9（流式输出）是两个独立任务：
;   esc=old -> 与生产一致，可对照 1.29 / 5.44 ms 基线
;   esc=new -> T1 已落地后的水平，T9 的收益要在这个基础上看
;
; ⚠️ AHK v2 硬约束（实测）：函数定义必须写在所有顶层可执行语句之前，
;    且不接受单行花括号函数体（F(x) { return x } 报 "Unexpected {"）。
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

; -----------------------------------------------------------------
; 转义（与 bench_json_escape 完全一致，此处内联以免跨文件依赖）
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

; 缩进空格（复刻 _BuildSpaces 的缓存行为）
; ⚠️ 函数名不能叫 Spaces：AHK 标识符大小写不敏感，调用方的局部变量 spaces
;    会与函数 Spaces 同名，Spaces(cur) 被解析成「尚未赋值的局部变量」→
;    "This local variable has not been assigned a value"。
;    生产代码用 this._BuildSpaces（方法调用）所以天然躲开，这里同理改名。
BuildSpaces(count) {
    static cache := Map()
    if cache.Has(count)
        return cache[count]
    pad := ""
    loop count
        pad .= " "
    cache[count] := pad
    return pad
}

; 标量分派（三实现共用，保证只有累加方式不同）
ScalarOf(val, esc) {
    if Type(val) = "String"
        return '"' esc.Call(val) '"'
    else if Type(val) = "Boolean" || val = true || val = false
        return val ? "true" : "false"
    else if Type(val) = "Integer" || Type(val) = "Float"
        return String(val)
    return "null"
}

; -----------------------------------------------------------------
; 实现 ①：concat —— 原样复刻 json_serializer.ahk
; -----------------------------------------------------------------
SerConcat(val, indent, cur, esc) {
    if Type(val) = "Map" {
        if val.Count = 0
            return "{}"
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        result := "{`n"
        first := true
        for key, value in val {
            if !first
                result .= ",`n"
            first := false
            result .= nextPad '"' esc.Call(key) '": '
                . SerConcat(value, indent, cur + indent, esc)
        }
        result .= "`n" pad "}"
        return result
    }
    if Type(val) = "Array" {
        if val.Length = 0
            return "[]"
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        result := "[`n"
        first := true
        for item in val {
            if !first
                result .= ",`n"
            first := false
            result .= nextPad SerConcat(item, indent, cur + indent, esc)
        }
        result .= "`n" pad "]"
        return result
    }
    return ScalarOf(val, esc)
}

; -----------------------------------------------------------------
; 实现 ②：parts —— 递归收集进数组，最后一次拼接
; -----------------------------------------------------------------
SerParts(val, indent, cur, esc) {
    parts := []
    SerPartsFill(val, indent, cur, esc, parts)
    result := ""
    for p in parts
        result .= p
    return result
}

SerPartsFill(val, indent, cur, esc, parts) {
    if Type(val) = "Map" {
        if val.Count = 0 {
            parts.Push("{}")
            return
        }
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        parts.Push("{`n")
        first := true
        for key, value in val {
            if !first
                parts.Push(",`n")
            first := false
            parts.Push(nextPad '"' esc.Call(key) '": ')
            SerPartsFill(value, indent, cur + indent, esc, parts)
        }
        parts.Push("`n" pad "}")
        return
    }
    if Type(val) = "Array" {
        if val.Length = 0 {
            parts.Push("[]")
            return
        }
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        parts.Push("[`n")
        first := true
        for item in val {
            if !first
                parts.Push(",`n")
            first := false
            parts.Push(nextPad)
            SerPartsFill(item, indent, cur + indent, esc, parts)
        }
        parts.Push("`n" pad "]")
        return
    }
    parts.Push(ScalarOf(val, esc))
}

; -----------------------------------------------------------------
; 实现 ③：buf —— 预分配 Buffer + StrPut 索引写入
;
; ⚠️ StrPut 语义（实测确认）：
;   StrPut(s, ptr, n, "UTF-16") 返回「字节数」= n*2，且不写终止符；
;   所以 pos 要按 StrLen(s)*2 推进，回读用 StrGet(ptr, pos//2, "UTF-16")。
;   若省略 n（StrPut(s, ptr, "UTF-16")）则会多写一个 2 字节终止符。
; -----------------------------------------------------------------
BufPut(st, s) {
    need := StrLen(s) * 2
    if need = 0
        return
    if st.pos + need > st.cap {
        newCap := st.cap
        while newCap < st.pos + need
            newCap := newCap * 2
        nb := Buffer(newCap, 0)
        if st.pos > 0
            DllCall("RtlMoveMemory", "Ptr", nb.Ptr, "Ptr", st.buf.Ptr, "Ptr", st.pos)
        st.buf := nb
        st.cap := newCap
    }
    StrPut(s, st.buf.Ptr + st.pos, StrLen(s), "UTF-16")
    st.pos := st.pos + need
}

SerBuf(val, indent, cur, esc) {
    st := {buf: Buffer(4096, 0), pos: 0, cap: 4096}
    SerBufFill(val, indent, cur, esc, st)
    return StrGet(st.buf.Ptr, st.pos // 2, "UTF-16")
}

SerBufFill(val, indent, cur, esc, st) {
    if Type(val) = "Map" {
        if val.Count = 0 {
            BufPut(st, "{}")
            return
        }
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        BufPut(st, "{`n")
        first := true
        for key, value in val {
            if !first
                BufPut(st, ",`n")
            first := false
            BufPut(st, nextPad '"' esc.Call(key) '": ')
            SerBufFill(value, indent, cur + indent, esc, st)
        }
        BufPut(st, "`n" pad "}")
        return
    }
    if Type(val) = "Array" {
        if val.Length = 0 {
            BufPut(st, "[]")
            return
        }
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        BufPut(st, "[`n")
        first := true
        for item in val {
            if !first
                BufPut(st, ",`n")
            first := false
            BufPut(st, nextPad)
            SerBufFill(item, indent, cur + indent, esc, st)
        }
        BufPut(st, "`n" pad "]")
        return
    }
    BufPut(st, ScalarOf(val, esc))
}

; -----------------------------------------------------------------
; 实现 ④⑤：stream —— 单一 ByRef 累加器（规范流式写法）
;   与 concat 的本质差别：递归不返回字符串，全程只往一个变量追加，
;   因此不存在「父层把子层结果再拼一遍」的二次拷贝。
;   streamp = stream + VarSetStrCapacity 预分配（调用方给出估计容量）。
; -----------------------------------------------------------------
SerStream(val, indent, cur, esc, cap := 0) {
    out := ""
    if cap > 0
        VarSetStrCapacity(&out, cap)
    SerStreamFill(&out, val, indent, cur, esc)
    return out
}

SerStreamFill(&out, val, indent, cur, esc) {
    if Type(val) = "Map" {
        if val.Count = 0 {
            out .= "{}"
            return
        }
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        out .= "{`n"
        first := true
        for key, value in val {
            if !first
                out .= ",`n"
            first := false
            out .= nextPad '"' esc.Call(key) '": '
            SerStreamFill(&out, value, indent, cur + indent, esc)
        }
        out .= "`n" pad "}"
        return
    }
    if Type(val) = "Array" {
        if val.Length = 0 {
            out .= "[]"
            return
        }
        pad := BuildSpaces(cur)
        nextPad := BuildSpaces(cur + indent)
        out .= "[`n"
        first := true
        for item in val {
            if !first
                out .= ",`n"
            first := false
            out .= nextPad
            SerStreamFill(&out, item, indent, cur + indent, esc)
        }
        out .= "`n" pad "]"
        return
    }
    out .= ScalarOf(val, esc)
}

; -----------------------------------------------------------------
; 测试负载
; -----------------------------------------------------------------
BuildPayload(n) {
    obj := Map()
    obj["version"] := 3
    obj["group"] := "default_group"
    keys := []
    i := 1
    while i <= n {
        e := Map()
        e["id"] := i
        e["name"] := "skill_name_" i
        e["enabled"] := true
        e["ratio"] := 0.75
        e["tags"] := ["alpha", "beta", "gamma"]
        keys.Push(e)
        i++
    }
    obj["keys"] := keys
    meta := Map()
    meta["created"] := "2026-09-14"
    meta["count"] := n
    obj["meta"] := meta
    return obj
}

; 按目标字符数反推条目数（先测单条与双条的差值）
Calibrate(targetChars) {
    s1 := StrLen(SerConcat(BuildPayload(1), 2, 0, EscapeOld))
    s2 := StrLen(SerConcat(BuildPayload(2), 2, 0, EscapeOld))
    per := s2 - s1
    n := Round((targetChars - s1) / per) + 1
    return n < 1 ? 1 : n
}

; -----------------------------------------------------------------
; 等价性：逐字节比对（5 种累加方式的输出必须完全一致）
; -----------------------------------------------------------------
EdgeCases() {
    cases := []
    cases.Push(["empty_map", Map()])
    cases.Push(["empty_arr", []])
    cases.Push(["one_map", Map("a", 1)])
    cases.Push(["one_arr", [42]])
    longKey := ""
    while StrLen(longKey) < 300
        longKey .= "k"
    cases.Push(["long_key", Map(longKey, "v")])
    deep := Map("leaf", 1)
    i := 0
    while i < 60 {
        d := Map()
        d["n"] := deep
        deep := d
        i++
    }
    cases.Push(["deep60", deep])
    mixed := Map()
    mixed["quote"] := 'he said "hi"'
    mixed["backslash"] := "a\b"
    mixed["newline"] := "line1`nline2"
    mixed["tab"] := "a`tb"
    mixed["cjk"] := "中文键名"
    mixed["int"] := -12345
    mixed["float"] := 3.14159
    mixed["yes"] := true
    mixed["no"] := false
    mixed["nested"] := [1, "two", Map("three", 3), []]
    cases.Push(["mixed", mixed])
    return cases
}

RunEquivalence() {
    cases := EdgeCases()
    ok := 0
    bad := 0
    for c in cases {
        name := c[1]
        val := c[2]
        a := SerConcat(val, 2, 0, EscapeOld)
        b := SerConcat(val, 2, 0, EscapeNew)
        d := SerParts(val, 2, 0, EscapeNew)
        e := SerBuf(val, 2, 0, EscapeNew)
        f := SerStream(val, 2, 0, EscapeNew, 0)
        g := SerStream(val, 2, 0, EscapeNew, StrLen(a) * 2)
        same := (a = b) && (b = d) && (d = e) && (e = f) && (f = g)
        if same
            ok++
        else
            bad++
        BenchWrite("equiv,case=" . name . ",bytes=" . StrLen(a) . ",identical=" . (same ? 1 : 0))
    }
    BenchWrite("equiv,summary,ok=" . ok . ",bad=" . bad)
}

; -----------------------------------------------------------------
; 计时
; -----------------------------------------------------------------
SerOf(kind) {
    if kind = "concat"
        return SerConcat
    if kind = "parts"
        return SerParts
    if kind = "buf"
        return SerBuf
    if kind = "stream"
        return SerStream
    return SerStreamP
}

; SerStream 的第 5 个参数是容量估计，统一包装成 (val, indent, cur, esc)
SerStreamP(val, indent, cur, esc) {
    return SerStream(val, indent, cur, esc, SerStreamPCap())
}

SerStreamPCap() {
    global _capHint
    return _capHint
}

EscOf(escName) {
    return escName = "old" ? EscapeOld : EscapeNew
}

RunSer(kind, escName, payload, label, rounds, capHint := 0) {
    global _capHint
    _capHint := capHint
    ser := SerOf(kind)
    esc := EscOf(escName)
    ; 预热：AHK 首次遍历某结构会填充内部缓存，不预热会污染 p50
    w := 0
    while w < 20 {
        s := ser.Call(payload, 2, 0, esc)
        w++
    }
    memA := SnapMemKB()
    lat := []
    r := 0
    while r < rounds {
        t0 := HighResNow()
        s := ser.Call(payload, 2, 0, esc)
        t1 := HighResNow()
        lat.Push((t1 - t0) * 1000)      ; ms
        r++
    }
    memB := SnapMemKB()
    st := SortNums(lat)
    BenchWrite("ser,impl=" . kind . ",esc=" . escName . ",case=" . label
        . ",bytes=" . StrLen(s)
        . ",n=" . st.Length
        . ",p50_ms=" . Round(Pct(st, 0.50), 4)
        . ",p95_ms=" . Round(Pct(st, 0.95), 4)
        . ",min_ms=" . Round(st[1], 4)
        . ",max_ms=" . Round(st[st.Length], 4)
        . ",ws_delta_kb=" . (memB[1] - memA[1])
        . ",priv_delta_kb=" . (memB[2] - memA[2]))
    return Pct(st, 0.50)
}

Main() {
    BenchInit("json_full")

    BenchWrite("# --- 等价性（5 种累加方式 + 2 种转义，输出必须逐字节相同）---")
    RunEquivalence()

    for target in [2048, 8192] {
        n := Calibrate(target)
        payload := BuildPayload(n)
        chars := StrLen(SerConcat(payload, 2, 0, EscapeOld))
        label := (target = 2048 ? "2KB" : "8KB")
        BenchWrite("# --- 规模 " . label . " · 实际 " . chars . " 字符 · 条目数 " . n . " ---")
        rounds := target = 2048 ? 300 : 150
        ; esc=old 只有 concat 有意义（那是生产现状，用于对照 1.29 / 5.44 ms 基线）
        RunSer("concat", "old", payload, label, rounds)
        RunSer("concat", "new", payload, label, rounds)
        RunSer("parts", "new", payload, label, rounds)
        RunSer("buf", "new", payload, label, rounds)
        RunSer("stream", "new", payload, label, rounds)
        RunSer("streamp", "new", payload, label, rounds, chars * 2)
    }

    BenchDone()
}

Main()
ExitApp(0)
