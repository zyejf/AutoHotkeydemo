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
; 被 run_all_tests.ahk #Include 的**套件文件**不需要这些指令 —— 它们没有入口代码，
; 靠主 runner 的 OnError/#ErrorStdOut 兜底。典型如 test_joystick_input.ahk
; （文件头已注明「不可独立运行」）。
; 注：这里用显式名单而不是去解析主 runner 的 #Include —— 动态解析在 AHK v2 里
; 容易踩到「连续空参数」「字符串里的引号转义」这类加载期语法错误，且 GUI 子系统
; 拿不到 stderr，排错成本远高于直接维护名单。新增套件文件时同步加一行。
_CollectIncludedByMainRunner() {
    included := Map()
    included["test_joystick_input.ahk"] := true
    return included
}

_CollectFilesMissingKeyword(keyword) {
    missing := []
    ; A_ScriptDir 是 tests/archive，但本用例要扫的是 **tests 根目录** ——
    ; 原先直接用 A_ScriptDir，等于在扫 tests/archive 自己（里面正好也有一批 .ahk），
    ; 于是扫了个寂寞：往 tests/ 里放一个缺 #ErrorStdOut 的文件也不会被发现
    ; （2026-09-16 实测阳性对照未触发）。
    testDir := A_ScriptDir "\.."
    includedByRunner := _CollectIncludedByMainRunner()
    Loop Files testDir "\*.ahk", "F" {
        ; 排除 AutoHotUnit.ahk（由其他任务处理）和本测试文件
        if (A_LoopFileName = "AutoHotUnit.ahk" || A_LoopFileName = "test_all_tests_have_onerror_c6.ahk")
            continue
        if includedByRunner.Has(A_LoopFileName)
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
