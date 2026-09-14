; ----------------------------------------------------------------------------
; P5：内存与句柄
;   GetProcessMemoryInfo(psapi) 取 PrivateUsage / WorkingSetSize
;   GetProcessHandleCount(kernel32) 取句柄数
; 场景：
;   1) 10 万次 Map 增删
;   2) 10 万次 Array push/pop
;   3) 1 万次热键注册（F16-F24 + 修饰键，闭包回调）
;   4) 5 万个**循环引用**对象（验证源码 script_object.h:16 纯引用计数、无环检测 → 必泄漏）
;   5) 100 万次 StrPut/StrGet
;   6) 20 万次字符串拼接（Var 容量阶梯扩容：≤64B 走 SimpleHeap 只增不还）
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    ProbeInit("p5_memory")
    ProbeNote("P5 内存/句柄：每个场景前先 GC 一次（AHK 无 GC，这里只是稳定基线）")
    ProbeWrite("scenario,priv_before_kb,priv_after_kb,priv_delta_kb,ws_delta_kb,handle_before,handle_after,handle_delta,ms")

    Scenario("map_100k", () => SMap())
    Scenario("array_100k", () => SArr())
    Scenario("hotkey_1k", () => SHotkey())
    Scenario("nocycle_50k", () => SNoCycle())
    Scenario("cycle_ref_50k", () => SCycle())
    Scenario("strput_200k", () => SStrPut())
    Scenario("concat_200k", () => SConcat())
    ProbeDone()
}

Scenario(tag, fn) {
    b := Snap()
    t0 := HighResNow()
    fn()
    ms := (HighResNow() - t0) * 1000
    a := Snap()
    ProbeWrite(tag . "," . b[1] . "," . a[1] . "," . (a[1] - b[1]) . ","
        . (a[2] - b[2]) . "," . b[3] . "," . a[3] . "," . (a[3] - b[3]) . "," . Round(ms, 2))
}

; -1 = GetCurrentProcess() 伪句柄（不需要 OpenProcess）
; PROCESS_MEMORY_COUNTERS_EX 在 x64 的偏移：
;   0 cb / 4 PageFaultCount / 8 PeakWorkingSet / 16 WorkingSetSize / ... / 72 PrivateUsage
Snap() {
    pmc := Buffer(80, 0)
    DllCall("psapi\GetProcessMemoryInfo", "Ptr", -1, "Ptr", pmc, "UInt", 80)
    ws := NumGet(pmc, 16, "Int64") / 1024
    priv := NumGet(pmc, 72, "Int64") / 1024
    h := 0
    DllCall("kernel32\GetProcessHandleCount", "Ptr", -1, "UInt*", &h)
    return [Round(priv), Round(ws), h]
}

SMap() {
    m := Map()
    Loop 100000 {
        m[A_Index] := A_Index
        m.Delete(A_Index)
    }
}

SArr() {
    a := []
    Loop 100000 {
        a.Push(A_Index)
        a.Pop()
    }
}

SHotkey() {
    keys := []
    for p in ["^", "!", "+", "#", "^!", "^+", "!+", "#^", "#+", "#!", "^!+", "^!#+"] {
        k := 16
        while k <= 24 {
            keys.Push(p . "F" . k)
            k += 1
        }
    }
    Loop 10 {          ; 10 × 108 = 1080 次注册（反复注册同名键会不断累加 variant）
        for nm in keys {
            try
                Hotkey(nm, ((*) => 0))
            catch as e
                break
        }
    }
}

; 对照组：同样创建 5 万个 Map，但**不**形成循环引用
SNoCycle() {
    keep := []
    Loop 50000 {
        a := Map()
        b := Map()
        a["other"] := b
        keep.Push(1)
    }
}

; 循环引用：脚本层对象纯引用计数（script_object.h:16），无环检测 → 必然泄漏
SCycle() {
    keep := []
    Loop 50000 {
        a := Map()
        b := Map()
        a["self"] := a          ; 自引用
        a["other"] := b
        b["back"] := a          ; 互相引用
        keep.Push(1)            ; 保持循环，避免被提前回收（对照下方 SNoCycle）
    }
}

SStrPut() {
    s := "AutoHotkey 中文测试 😀 combining é"
    buf := Buffer(256, 0)
    Loop 200000 {
        n := StrPut(s, buf, "UTF-8")
        t := StrGet(buf, "UTF-8")
    }
}

; Var 容量 ≤64 字节时走 SimpleHeap（只增不还）；超 64 字节才转 malloc 并永久锁定
SConcat() {
    s := ""
    Loop 200000 {
        s .= "x"
        if StrLen(s) > 1000
            s := ""
    }
}

Main()
ExitApp
