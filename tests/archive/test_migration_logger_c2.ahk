; =================================================================
; test_migration_logger_c2 - C2 合规违规修复测试
; 验证 migration_logger.ahk 包含完整的 #Warn 强制接管指令
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; ⚠️ 原来这里是 `(…, true)` —— 「已处理」会让 AHK 终止自动执行段并以退出码 0 收场，
; 于是任何运行期错误都被伪装成「测试通过」。改为显式以 99 退出：错误必须看得见。
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), ExitApp(99)))

; =================================================================
; 测试固件 - 读取 migration_logger.ahk 源码
; =================================================================

GetMigrationLoggerSource() {
    ; A_ScriptDir 是 tests/archive，到仓库根要退两级（原先只退了一级，
    ; 解析成 tests/infrastructure/… —— 该目录不存在，FileRead 必抛错；
    ; 而 OnError 又把它吞掉，脚本中途终止、退出码 0，看起来像「全部通过」）。
    path := A_ScriptDir "\..\..\infrastructure\migration_logger.ahk"
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

; 退出码必须反映失败数：裸 `ExitApp(failed > 0 ? 1 : 0)` 退出码恒为 0，失败会被静默吞掉。
; 本脚本已被 G3g（scripts/run-standalone-ahk-tests.sh）逐个按退出码汇总。
ExitApp(failed > 0 ? 1 : 0)
