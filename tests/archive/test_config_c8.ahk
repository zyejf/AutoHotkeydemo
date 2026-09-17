; =================================================================
; test_config_c8.ahk - C8 配置一致性测试
; 验证 test-manifest feature 已从 Cargo.toml 和 AGENTS.md 中移除
; 验证 joy_hotkey_manager 已在 AGENTS.md 中登记
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试用例
; =================================================================

; 测试1: Cargo.toml 不含 test-manifest feature
; 验证废弃的 test-manifest feature 已从 Cargo.toml 中删除
Test_CargoToml_NoTestManifestFeature() {
    try {
        ; 相对 A_ScriptDir 解析，不要硬编码绝对路径 —— 本仓库还有 worktree
        ; 在别的盘符/目录下，写死 D:\1demo\... 会在 CI 与 worktree 上直接失败。
        cargoPath := A_ScriptDir "\..\..\asd-tauri\src-tauri\Cargo.toml"
        content := FileRead(cargoPath, "UTF-8")
        if InStr(content, "test-manifest") {
            FileAppend("FAIL: Test_CargoToml_NoTestManifestFeature - Cargo.toml 仍包含 test-manifest`n", "*")
            return false
        }
        FileAppend("PASS: Test_CargoToml_NoTestManifestFeature`n", "*")
        return true
    } catch as e {
        FileAppend("ERROR: Test_CargoToml_NoTestManifestFeature - " e.Message "`n", "*")
        return false
    }
}

; 测试2: AGENTS.md 不含 test-manifest 引用
; 验证所有 test-manifest 相关文档描述已移除
Test_AGENTS_MD_NoTestManifestRef() {
    try {
        agentsPath := A_ScriptDir "\..\..\AGENTS.md"
        content := FileRead(agentsPath, "UTF-8")
        if InStr(content, "test-manifest") {
            FileAppend("FAIL: Test_AGENTS_MD_NoTestManifestRef - AGENTS.md 仍包含 test-manifest 引用`n", "*")
            return false
        }
        FileAppend("PASS: Test_AGENTS_MD_NoTestManifestRef`n", "*")
        return true
    } catch as e {
        FileAppend("ERROR: Test_AGENTS_MD_NoTestManifestRef - " e.Message "`n", "*")
        return false
    }
}

; 测试3: AGENTS.md 提及 joy_hotkey_manager
; 验证 joy_hotkey_manager.ahk 模块已在文档中登记
Test_AGENTS_MD_HasJoyHotkeyManager() {
    try {
        agentsPath := A_ScriptDir "\..\..\AGENTS.md"
        content := FileRead(agentsPath, "UTF-8")
        if !InStr(content, "joy_hotkey_manager") {
            FileAppend("FAIL: Test_AGENTS_MD_HasJoyHotkeyManager - AGENTS.md 未提及 joy_hotkey_manager`n", "*")
            return false
        }
        FileAppend("PASS: Test_AGENTS_MD_HasJoyHotkeyManager`n", "*")
        return true
    } catch as e {
        FileAppend("ERROR: Test_AGENTS_MD_HasJoyHotkeyManager - " e.Message "`n", "*")
        return false
    }
}

; =================================================================
; 执行测试
; =================================================================

FileAppend("=== C8 Config Consistency Test Start ===`n", "*")
r1 := Test_CargoToml_NoTestManifestFeature()
r2 := Test_AGENTS_MD_NoTestManifestRef()
r3 := Test_AGENTS_MD_HasJoyHotkeyManager()

c8Fail := (r1 ? 0 : 1) + (r2 ? 0 : 1) + (r3 ? 0 : 1)
c8Pass := 3 - c8Fail
FileAppend("=== C8 Config Consistency Test End: " c8Pass " passed, "
    c8Fail " failed ===`n", "*")

; 退出码必须反映失败数：本脚本原先连 ExitApp 都没有，走到文件底部退出码恒为 0，
; 三个用例全 FAIL 也照样「通过」。本脚本已被 G3g（run-standalone-ahk-tests.sh）逐个汇总。
ExitApp(c8Fail > 0 ? 1 : 0)
