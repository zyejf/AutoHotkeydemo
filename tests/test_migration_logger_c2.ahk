; =================================================================
; test_migration_logger_c2 - C2 合规违规修复测试
; 验证 migration_logger.ahk 包含完整的 #Warn 强制接管指令
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试固件 - 读取 migration_logger.ahk 源码
; =================================================================

GetMigrationLoggerSource() {
    path := A_ScriptDir "\..\infrastructure\migration_logger.ahk"
    return FileRead(path, "UTF-8")
}

; =================================================================
; 测试用例
; =================================================================

Test_MigrationLogger_HasWarnVarUnset() {
    source := GetMigrationLoggerSource()
    if InStr(source, "#Warn VarUnset, OutputDebug") {
        FileAppend("PASS: Test_MigrationLogger_HasWarnVarUnset`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_MigrationLogger_HasWarnVarUnset - 缺少 #Warn VarUnset, OutputDebug`n", "*")
        return false
    }
}

Test_MigrationLogger_HasWarnUnreachable() {
    source := GetMigrationLoggerSource()
    if InStr(source, "#Warn Unreachable, OutputDebug") {
        FileAppend("PASS: Test_MigrationLogger_HasWarnUnreachable`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_MigrationLogger_HasWarnUnreachable - 缺少 #Warn Unreachable, OutputDebug`n", "*")
        return false
    }
}

Test_MigrationLogger_HasWarnLocalSameAsGlobal() {
    source := GetMigrationLoggerSource()
    if InStr(source, "#Warn LocalSameAsGlobal, Off") {
        FileAppend("PASS: Test_MigrationLogger_HasWarnLocalSameAsGlobal`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_MigrationLogger_HasWarnLocalSameAsGlobal - 缺少 #Warn LocalSameAsGlobal, Off`n", "*")
        return false
    }
}

Test_MigrationLogger_DirectivesCount() {
    source := GetMigrationLoggerSource()
    ; 统计 #Warn 指令出现次数
    count := 0
    pos := 1
    while pos := InStr(source, "#Warn", true, pos) {
        count++
        pos += 5
    }
    if count >= 3 {
        FileAppend("PASS: Test_MigrationLogger_DirectivesCount - #Warn 数量=" count "`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_MigrationLogger_DirectivesCount - #Warn 数量=" count "，期望 >= 3`n", "*")
        return false
    }
}

; =================================================================
; 执行测试
; =================================================================

FileAppend("=== Test Start: test_migration_logger_c2 ===`n", "*")
results := []
results.Push(Test_MigrationLogger_HasWarnVarUnset())
results.Push(Test_MigrationLogger_HasWarnUnreachable())
results.Push(Test_MigrationLogger_HasWarnLocalSameAsGlobal())
results.Push(Test_MigrationLogger_DirectivesCount())

passed := 0
failed := 0
for r in results {
    if r
        passed++
    else
        failed++
}
FileAppend("--- 汇总: PASS=" passed " FAIL=" failed " ---`n", "*")
if failed > 0
    FileAppend("RESULT: FAILURE`n", "*")
else
    FileAppend("RESULT: SUCCESS`n", "*")
FileAppend("=== Test End ===`n", "*")

ExitApp()
