; =================================================================
; bench_key_regex —— 每次发键的键名校验：3 次正则 vs 1 次查表
;
; 原型：domain/skill_group.ahk:889-902 `_IsValidKeyName`
;   RegExReplace 剥修饰键 → RegExMatch(单字符) → RegExMatch(F1-F24) → Map 查表
;   = 每键 3 次正则 + 1 次查表
;
; 修复：把「单字符」与「F1~F24」这两类在构建集合时就展开进去，
;       运行期只剩 1 次剥离 + 1 次查表。语义完全等价。
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

global VALID_BASE := ""
global VALID_SET := ""

; 模拟 SkillGroup._GetValidKeysMap() 的内容（约 60 项命名键）
BuildBaseMap() {
    m := Map()
    for k in ["space", "enter", "tab", "esc", "escape", "backspace", "bs", "delete", "del",
              "insert", "ins", "home", "end", "pgup", "pgdn", "up", "down", "left", "right",
              "lbutton", "rbutton", "mbutton", "wheelup", "wheeldown", "wheelleft", "wheelright",
              "ctrl", "control", "alt", "shift", "lwin", "rwin", "numlock", "capslock",
              "scrolllock", "printscreen", "pause", "appskey", "browser_back", "browser_forward",
              "browser_refresh", "browser_stop", "browser_search", "browser_favorites",
              "browser_home", "volume_mute", "volume_down", "volume_up", "media_next",
              "media_prev", "media_stop", "media_play_pause", "launch_mail", "launch_media",
              "launch_app1", "launch_app2", "numpad0", "numpad1", "numpad5", "numpaddot",
              "numpadenter", "numpaddiv", "numpadmult", "numpadadd", "numpadsub"]
        m[k] := true
    return m
}

global BASE_MAP := ""

; 生产里 _GetValidKeysMap() 是懒加载 + 缓存的，这里必须对齐，否则旧实现被冤枉
EnsureBase() {
    global BASE_MAP
    if BASE_MAP = ""
        BASE_MAP := BuildBaseMap()
    return BASE_MAP
}

; ---------- 优化前：原样复刻 skill_group.ahk:889-902 ----------
IsValidOld(key) {
    if !IsSet(key) || key = ""
        return false
    baseKey := RegExReplace(key, "^[\^+!#]+", "")
    if RegExMatch(baseKey, "^[a-zA-Z0-9]$")
        return true
    if RegExMatch(baseKey, "^[fF]([1-9]|1[0-9]|2[0-4])$")
        return true
    lowerKey := StrLower(baseKey)
    return EnsureBase().Has(lowerKey)
}

; ---------- 优化后：预展开集合，运行期只查一次 ----------
EnsureSet() {
    global VALID_SET
    if VALID_SET != ""
        return VALID_SET
    m := BuildBaseMap()
    for c in StrSplit("abcdefghijklmnopqrstuvwxyz0123456789")
        m[c] := true
    i := 1
    while i <= 24 {
        m["f" . i] := true
        i++
    }
    VALID_SET := m
    return m
}

IsValidNew(key) {
    if !IsSet(key) || key = ""
        return false
    baseKey := RegExReplace(key, "^[\^+!#]+", "")
    return EnsureSet().Has(StrLower(baseKey))
}

; 构造测试键序列：混合 合法单字符 / F 键 / 命名键 / 带修饰键 / 非法键
BuildKeys(n) {
    ks := []
    pool := ["a", "Z", "5", "F1", "F13", "F24", "space", "enter", "up", "numpad0",
             "^a", "+F5", "!space", "#F12", "^!+F3", "unknown_key", "F25", "ab", ""]
    i := 0
    while i < n {
        ks.Push(pool[Mod(i, pool.Length) + 1])
        i++
    }
    return ks
}

RunCase(tag, keys, fn, rounds) {
    samples := []
    r := 1
    while r <= rounds {
        t0 := HighResNow()
        hits := 0
        for k in keys {
            if fn.Call(k)
                hits++
        }
        samples.Push((HighResNow() - t0) * 1000)
        r++
    }
    s := SortNums(samples)
    p50 := Pct(s, 0.5)
    BenchWrite("keyregex," . tag . ",n=" . keys.Length
        . ",p50_ms=" . Round(p50, 3)
        . ",us_per_op=" . Round(p50 * 1000 / keys.Length, 5))
    return p50
}

Main() {
    BenchInit("key_regex")
    BenchWrite("# bench_key_regex —— 每键 3 次正则 vs 1 次查表")
    keys := BuildKeys(20000)

    o := RunCase("old", keys, IsValidOld, 5)
    n := RunCase("new", keys, IsValidNew, 5)
    BenchWrite("cmp,keyregex,p50_old_ms=" . Round(o, 3) . ",p50_new_ms=" . Round(n, 3)
        . ",speedup=" . Round(o / ((n > 0) ? n : 0.0001), 2))

    ; 等价性：逐键比对布尔结果
    diffs := 0
    for k in keys {
        if IsValidOld(k) != IsValidNew(k)
            diffs++
    }
    BenchWrite("verify,equivalence,n=" . keys.Length . ",diffs=" . diffs
        . ",result=" . (diffs = 0 ? "IDENTICAL" : "DIFFERENT"))

    BenchDone()
}

Main()
ExitApp(0)
