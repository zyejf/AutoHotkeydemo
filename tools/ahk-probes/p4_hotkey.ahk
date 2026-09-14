; ----------------------------------------------------------------------------
; P4：热键时延 / SendLevel×InputLevel 判定矩阵 / 注册规模开销
;
; ① 判定矩阵：源码 hotkey.h:75 InputLevelFromInfo() —— AHK 自己 Send 的按键携带
;    KEY_IGNORE_LEVEL(SendLevel)；非 AHK 发出的事件（如 Rust 的 SendInput 不写
;    dwExtraInfo）被判成 SendLevelMax+1 = 101。判定规则
;    `InputLevelFromInfo(事件) > 热键的 InputLevel` 才触发（hotkey.cpp:621）。
;    实测三档 InputLevel：0(F13) / 1(F15) / 11(F14)。
; ② 端到端时延：Send 之前打点 → 回调入口打点。
; ③ 注册规模：逐个注册 120 个热键，看累计耗时是否超线性（hotkey.cpp:202
;    ManifestAllHotkeysHotstringsHooks 自述 high-overhead，含 O(n²) 内层扫描）。
;
; 只用 F13~F24（本机几乎不会被真实使用），且全部带修饰键前缀，避免劫持真实快捷键。
; ----------------------------------------------------------------------------
#Include _harness.ahk

#InputLevel 0
F13::OnHK(13)
#InputLevel 1
F15::OnHK(15)
#InputLevel 11
F14::OnHK(14)
#InputLevel 0

Main() {
    ProbeInit("p4_hotkey")
    ProbeNote("P4 热键：判定矩阵 / 时延 / 注册规模")

    ; ---- ① SendLevel × InputLevel 判定矩阵 ---------------------------------
    ProbeWrite("phase1_matrix")
    ProbeWrite("send_level,IL0(F13),IL1(F15),IL11(F14),lat_ms_IL0")
    for L in [0, 1, 2, 5, 10, 11, 12, 15, 20, 50, 100] {
        SendLevel(L)
        r13 := FireOnce("F13")
        SendLevel(L)
        r15 := FireOnce("F15")
        SendLevel(L)
        r14 := FireOnce("F14")
        ProbeWrite(L . "," . (r13[1] ? "YES" : "no") . "," . (r15[1] ? "YES" : "no") . ","
            . (r14[1] ? "YES" : "no") . "," . (r13[1] ? Round(r13[2], 2) : "-"))
    }
    SendLevel(0)

    ; ---- ② 端到端时延 --------------------------------------------------------
    ProbeWrite("phase2_latency")
    lat := []
    i := 1
    while i <= 30 {
        SendLevel(1)
        r := FireOnce("F13")
        if r[1] {
            lat.Push(r[2])
            ProbeWrite("lat," . i . "," . Round(r[2], 3))
        } else {
            ProbeWrite("lat," . i . ",MISS")
        }
        i += 1
    }
    SendLevel(0)
    _Stats("hk_latency_ms", lat)

    ; ---- ④ 裸 SendInput（模拟 Rust 侧下沉，dwExtraInfo = 0）----------------
    ; 这是本项目「Rust 侧 SendInput 会被 AHK 当物理键 → 自触发死循环」的直接验证：
    ; 不写 dwExtraInfo 时 InputLevelFromInfo() 返回 SendLevelMax+1 = 101，
    ; 判定 `101 > InputLevel` 对任意 InputLevel 都成立。
    ProbeWrite("phase4_raw_sendinput(extraInfo=0)")
    ProbeWrite("vk,IL0(F13),IL1(F15),IL11(F14)")
    for vk in [124, 126, 125] {
        gHit := 0
        SendRawKey(vk, true)
        SendRawKey(vk, false)
        t0 := HighResNow()
        guard := 0
        while (gHit == 0) && (HighResNow() - t0 < 0.2) && (guard < 200000) {
            Sleep(0)
            guard += 1
        }
        which := gWhich
        ProbeWrite("vk" . vk . "," . (which = 13 ? "YES" : "no") . ","
            . (which = 15 ? "YES" : "no") . "," . (which = 14 ? "YES" : "no"))
    }

    ; ---- ③ 注册规模开销 -----------------------------------------------------
    ProbeWrite("phase3_registration")
    ProbeWrite("n_registered,cumulative_ms,marginal_us_per_hotkey,errors")
    names := []
    for p in ["^", "!", "+", "#", "^!", "^+", "!+", "#^", "#+", "#!", "^!+", "^!#+"] {
        k := 16
        while k <= 24 {
            names.Push(p . "F" . k)
            k += 1
        }
    }
    t0 := HighResNow()
    prevN := 0
    prevT := t0
    errs := 0
    i := 1
    for nm in names {
        ; ⚠️ 回调必须是**函数对象**：写裸名字报 "Invalid callback function."，
        ;    写 Func("名字") 在本版本报 "Invalid base."，用闭包 ((*) => 0) 才行。
        try
            Hotkey(nm, ((*) => 0))
        catch as e
        {
            errs += 1
            if errs <= 3
                ProbeWrite("regerr," . nm . "," . StrReplace(e.Message, ",", ";"))
        }
        if (i == 1 || i == 10 || i == 30 || i == 60 || i == 108) {
            now := HighResNow()
            cum := (now - t0) * 1000
            marg := (now - prevT) * 1000 * 1000 / (i - prevN)
            ProbeWrite(i . "," . Round(cum, 3) . "," . Round(marg, 1) . "," . errs)
            prevN := i
            prevT := now
        }
        i += 1
    }
    ProbeDone()
}

; 发一次键，返回 [是否触发, 时延ms]
FireOnce(key) {
    global gHit, gHitAt
    gHit := 0
    gHitAt := 0
    t0 := HighResNow()
    Send("{" . key . "}")
    ; Sleep(0) 会驱动消息泵（见 P3），比 Sleep(n) 更快拿到 hook 回投的消息
    guard := 0
    while (gHit == 0) && (HighResNow() - t0 < 0.2) && (guard < 200000) {
        Sleep(0)
        guard += 1
    }
    if gHit
        return [true, (gHitAt - t0) * 1000]
    return [false, 0]
}

; 直接走 Win32 SendInput，dwExtraInfo = 0 —— 等价于 Rust 侧调用 SendInput
SendRawKey(vk, down := true) {
    buf := Buffer(40, 0)                       ; sizeof(INPUT) on x64 = 40
    NumPut("UInt", 1, buf, 0)                  ; INPUT_KEYBOARD
    NumPut("UShort", vk, buf, 8)               ; wVk
    NumPut("UShort", 0, buf, 10)               ; wScan
    NumPut("UInt", down ? 0 : 2, buf, 12)      ; dwFlags；2 = KEYEVENTF_KEYUP
    NumPut("UInt", 0, buf, 16)                 ; time
    NumPut("UPtr", 0, buf, 24)                 ; dwExtraInfo ← Rust 也是 0
    DllCall("user32\SendInput", "UInt", 1, "Ptr", buf, "Int", 40)
}

OnHK(which) {
    global gHit, gHitAt, gWhich
    gWhich := which
    gHit := 1
    gHitAt := HighResNow()
}

OnHKScale() {
}

Main()
ExitApp
