#Include _harness.ahk

Main() {
    ProbeInit("_dbg_hk")
    TryReg("F16-bare", "F16", ((*) => 0))
    TryReg("F17-closure", "F17", ((*) => 0))
    TryReg("F18-caret", "^F18", ((*) => 0))
    TryReg("F19-bang", "!F19", ((*) => 0))
    TryReg("F20-plus", "+F20", ((*) => 0))
    TryReg("F21-hash", "#F21", ((*) => 0))
    ; 规模：60 个，用闭包回调
    t0 := HighResNow()
    n := 0
    err := 0
    for p in ["^", "!", "+", "#", "^!", "^+", "!+", "#^", "#+", "#!", "^!+", "^!#+"] {
        k := 16
        while k <= 20 {
            try {
                Hotkey(p . "F" . k, ((*) => 0))
                n += 1
            } catch as e {
                err += 1
                if err <= 2
                    ProbeWrite("scale_err," . p . "F" . k . "," . StrReplace(e.Message, ",", ";"))
            }
            k += 1
        }
    }
    ProbeWrite("scale_ok," . n . ",errors," . err . ",ms," . Round((HighResNow() - t0) * 1000, 3))
    ProbeDone()
}

TryReg(tag, name, cb) {
    try {
        Hotkey(name, cb)
        ProbeWrite(tag . ",OK")
    } catch as e {
        ProbeWrite(tag . ",ERR," . StrReplace(e.Message, ",", ";"))
    }
}

Cb() {
}

Main()
ExitApp
