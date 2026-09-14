; ----------------------------------------------------------------------------
; P10：权限 / UAC / 完整性级别（**纯只读**，不做任何提权、不写 Program Files）
;   - GetTokenInformation(TokenIntegrityLevel) → SID → IL
;   - A_IsAdmin（CheckTokenMembership 的封装）
;   - 当前 IL 下热键是否可注册（非管理员是本项目默认场景）
;   - 只读探测：Program Files / Windows 目录是否存在（不尝试写入）
;   - 进程是否以 elevated 运行
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    ProbeInit("p10_uac")
    ProbeNote("P10 权限/UAC（只读）")
    ProbeWrite("key,value")

    ProbeWrite("A_IsAdmin," . A_IsAdmin)
    ProbeWrite("A_UserName," . A_UserName)
    ProbeWrite("A_ComputerName," . A_ComputerName)
    ProbeWrite("A_OSVersion," . A_OSVersion)
    ProbeWrite("integrity_level," . IntegrityLevel())
    ProbeWrite("elevated," . IsElevated())
    ProbeWrite("script_dir," . A_ScriptDir)
    ProbeWrite("temp," . EnvGet("TEMP"))

    ; 只读探测：不写入，只判断目录/文件是否存在
    ProbeWrite("progfiles_exists," . (DirExist("C:\Program Files") ? "yes" : "no"))
    ProbeWrite("windows_exists," . (DirExist("C:\Windows") ? "yes" : "no"))
    ProbeWrite("system32_exists," . (DirExist("C:\Windows\System32") ? "yes" : "no"))

    ; 非管理员 + 中 IL 时，写 Program Files 会被 UAC 虚拟化到 VirtualStore；
    ; 这里**不实测写入**，只记录判定依据，避免任何副作用。
    ProbeWrite("virtualstore_probe,SKIPPED(只读探针，不做写入实测)")

    ; 当前 IL 下能否注册热键（这是本项目最关键的能力前提）
    ok := 0
    try {
        Hotkey("^F24", ((*) => 0))
        ok := 1
    } catch as e {
        ProbeWrite("hotkey_reg_err," . StrReplace(e.Message, ",", ";"))
    }
    ProbeWrite("hotkey_registers_ok," . ok)

    ; 能否装键盘 hook（InputLevel>0 或 $ 前缀会强制 hook）——只读判定：注册成功即说明
    ok2 := 0
    try {
        Hotkey("$F23", ((*) => 0))
        ok2 := 1
    } catch as e {
        ProbeWrite("hook_hotkey_err," . StrReplace(e.Message, ",", ";"))
    }
    ProbeWrite("hook_mandatory_hotkey_ok," . ok2)

    ProbeDone()
}

; 返回完整性级别数值（0x1000=Low, 0x2000=Medium, 0x3000=High, 0x4000=System）
IntegrityLevel() {
    tok := 0
    DllCall("advapi32\OpenProcessToken", "Ptr", -1, "UInt", 0x0008, "Ptr*", &tok)  ; TOKEN_QUERY
    if !tok
        return "OpenProcessToken_FAILED"
    len := 0
    DllCall("advapi32\GetTokenInformation", "Ptr", tok, "Int", 25, "Ptr", 0, "UInt", 0, "UInt*", &len)  ; TokenIntegrityLevel=25
    if !len
        return "GetTokenInformation_FAILED"
    buf := Buffer(len, 0)
    if DllCall("advapi32\GetTokenInformation", "Ptr", tok, "Int", 25, "Ptr", buf, "UInt", len, "UInt*", &len) {
        sid := NumGet(buf, 0, "Ptr")
        ; 这两个 API 返回的是**指针**，必须再解引用，否则拿到的是地址当成了数值
        pcnt := DllCall("advapi32\GetSidSubAuthorityCount", "Ptr", sid, "Ptr")
        cnt := pcnt ? NumGet(pcnt, "UChar") : 0
        prid := DllCall("advapi32\GetSidSubAuthority", "Ptr", sid, "UInt", (cnt ? cnt - 1 : 0), "Ptr")
        rid := prid ? NumGet(prid, "UInt") : 0
        name := (rid >= 0x4000) ? "System"
            : (rid >= 0x3000) ? "High(elevated)"
            : (rid >= 0x2000) ? "Medium(默认)"
            : (rid >= 0x1000) ? "Low" : "Unknown"
        return rid . " (0x" . Format("{:x}", rid) . ") " . name
    }
    return "FAILED"
}

IsElevated() {
    ; TOKEN_ELEVATION (TokenElevation = 20)
    tok := 0
    DllCall("advapi32\OpenProcessToken", "Ptr", -1, "UInt", 0x0008, "Ptr*", &tok)
    if !tok
        return "NA"
    v := 0
    n := 0
    if DllCall("advapi32\GetTokenInformation", "Ptr", tok, "Int", 20, "UInt*", &v, "UInt", 4, "UInt*", &n)
        return v ? "yes" : "no"
    return "NA"
}

Main()
ExitApp
