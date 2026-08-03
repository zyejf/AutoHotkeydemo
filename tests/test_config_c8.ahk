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
        cargoPath := "D:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\Cargo.toml"
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
        agentsPath := "D:\1demo\AutoHotkeydemo\AGENTS.md"
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
        agentsPath := "D:\1demo\AutoHotkeydemo\AGENTS.md"
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
Test_CargoToml_NoTestManifestFeature()
Test_AGENTS_MD_NoTestManifestRef()
Test_AGENTS_MD_HasJoyHotkeyManager()
FileAppend("=== C8 Config Consistency Test End ===`n", "*")
