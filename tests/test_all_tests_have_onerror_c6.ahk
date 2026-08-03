; =================================================================
; C6 合规验证测试 - 验证所有测试文件包含 OnError 回调及接管指令
; 扫描 tests/ 根目录下所有 .ahk 文件（排除 AutoHotUnit.ahk 和本文件）
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 辅助函数 - 扫描 tests 根目录，返回缺少指定关键字的文件列表
; =================================================================

; 扫描 tests 根目录下所有 .ahk 文件，返回不包含 keyword 的文件名数组
_CollectFilesMissingKeyword(keyword) {
    missing := []
    testDir := A_ScriptDir
    Loop Files testDir "\*.ahk", "F" {
        ; 排除 AutoHotUnit.ahk（由其他任务处理）和本测试文件
        if (A_LoopFileName = "AutoHotUnit.ahk" || A_LoopFileName = "test_all_tests_have_onerror_c6.ahk")
            continue
        content := FileRead(A_LoopFileFullPath)
        if (!InStr(content, keyword)) {
            missing.Push(A_LoopFileName)
        }
    }
    return missing
}

; =================================================================
; 测试用例
; =================================================================

; 测试1: 所有测试文件必须包含 OnError 回调
Test_AllTestFilesHaveOnError() {
    missing := _CollectFilesMissingKeyword("OnError")
    if (missing.Length > 0) {
        FileAppend("FAIL: Test_AllTestFilesHaveOnError - " missing.Length " 个文件缺少 OnError:`n", "*")
        for f in missing {
            FileAppend("  - " f "`n", "*")
        }
        return false
    }
    FileAppend("PASS: Test_AllTestFilesHaveOnError`n", "*")
    return true
}

; 测试2: 所有测试文件必须包含 #ErrorStdOut 指令
Test_AllTestFilesHaveErrorStdOut() {
    missing := _CollectFilesMissingKeyword("#ErrorStdOut")
    if (missing.Length > 0) {
        FileAppend("FAIL: Test_AllTestFilesHaveErrorStdOut - " missing.Length " 个文件缺少 #ErrorStdOut:`n", "*")
        for f in missing {
            FileAppend("  - " f "`n", "*")
        }
        return false
    }
    FileAppend("PASS: Test_AllTestFilesHaveErrorStdOut`n", "*")
    return true
}

; 测试3: 所有测试文件必须包含 #Warn VarUnset 指令
Test_AllTestFilesHaveWarnVarUnset() {
    missing := _CollectFilesMissingKeyword("#Warn VarUnset")
    if (missing.Length > 0) {
        FileAppend("FAIL: Test_AllTestFilesHaveWarnVarUnset - " missing.Length " 个文件缺少 #Warn VarUnset:`n", "*")
        for f in missing {
            FileAppend("  - " f "`n", "*")
        }
        return false
    }
    FileAppend("PASS: Test_AllTestFilesHaveWarnVarUnset`n", "*")
    return true
}

; =================================================================
; 执行测试
; =================================================================

FileAppend("=== C6 Compliance Test Start ===`n", "*")
passCount := 0
failCount := 0

if (Test_AllTestFilesHaveOnError())
    passCount++
else
    failCount++

if (Test_AllTestFilesHaveErrorStdOut())
    passCount++
else
    failCount++

if (Test_AllTestFilesHaveWarnVarUnset())
    passCount++
else
    failCount++

FileAppend("`n=== Summary: " passCount " passed, " failCount " failed ===`n", "*")
FileAppend("=== C6 Compliance Test End ===`n", "*")

ExitApp(failCount > 0 ? 1 : 0)
