; 最小复现：逐个 try/catch 定位统计函数的报错
#Include _harness.ahk

Main() {
    ProbeInit("_dbg_tick")
    a := [15, 16, 16, 15, 16, 16, 15, 16, 15, 16]
    ProbeWrite("phase,start")

    TryW("clone", () => a.Clone().Length)
    TryW("sort", () => a.Clone().Sort())
    TryW("pct", () => _Pct(a, 0.5))
    TryW("max", () => _Max(a))
    TryW("min", () => _Min(a))
    TryW("mean", () => _Mean(a))
    TryW("stats", () => _Stats("s", a))

    ProbeWrite("phase,ALL_OK")
    ProbeDone()
}

TryW(tag, fn) {
    try {
        v := fn()
        ProbeWrite(tag . ",OK," . (IsObject(v) ? "obj" : v))
    } catch as e {
        ProbeWrite(tag . ",ERR," . e.Message . " @ " . e.What . ":" . e.Line)
    }
}

Main()
ExitApp
