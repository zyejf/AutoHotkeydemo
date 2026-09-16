; =================================================================
; 测试层 - 增强断言与报告框架
; 版本: 3.0
; 说明: 提供结构化断言、预期/实际对比记录和 JSON 报告输出
;       被所有 test_*.ahk 文件引用，不作为独立测试运行
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
#Include "../infrastructure/json_serializer.ahk"

OnError(TestReporter_OnError, -1)

TestReporter_OnError(e, mode) {
    errorMsg := ""
    if e is Error
        errorMsg := e.Message " (" e.File ":" e.Line ")"
    else
        errorMsg := String(e)
    TestReporter._Record(
        "运行时错误: " errorMsg,
        "异常: " errorMsg,
        "无异常",
        "FAIL"
    )
    OutputDebug("[TEST ERROR] " errorMsg)
    return true
}

class TestReporter {
    static results := []
    static startTime := 0
    static scenarioCount := 0
    static currentScenario := ""

    ; =================================================================
    ; 生命周期
    ; =================================================================
    static BeginTest(testName) {
        TestReporter.results := []
        TestReporter.startTime := A_TickCount
        TestReporter.scenarioCount := 0
        OutputDebug("`n========= " testName " =========`n")
    }

    ; =================================================================
    ; 场景标记
    ; =================================================================
    static Scenario(name) {
        TestReporter.currentScenario := name
        TestReporter.scenarioCount++
        OutputDebug("--- " name " ---")
    }

    ; =================================================================
    ; 断言方法
    ; =================================================================
    static Assert(condition, message) {
        TestReporter._Record(
            message,
            condition ? "true" : "false",
            "true",
            condition ? "PASS" : "FAIL"
        )
    }

    static AssertEqual(actual, expected, message) {
        match := (actual = expected)
        actualStr := TestReporter._ToStr(actual)
        expectedStr := TestReporter._ToStr(expected)
        TestReporter._Record(
            message,
            actualStr,
            expectedStr,
            match ? "PASS" : "FAIL"
        )
    }

    static AssertThrows(action, expectedMsgPart, message) {
        try {
            action()
            TestReporter._Record(
                message,
                "无异常",
                "异常包含: " expectedMsgPart,
                "FAIL"
            )
        } catch as e {
            actualError := e.Message
            match := InStr(actualError, expectedMsgPart) ? true : false
            TestReporter._Record(
                message,
                "异常: " actualError,
                "异常包含: " expectedMsgPart,
                match ? "PASS" : "FAIL"
            )
        }
    }

    static AssertNoThrow(action, message) {
        try {
            action()
            TestReporter._Record(
                message,
                "无异常",
                "无异常",
                "PASS"
            )
        } catch as e {
            TestReporter._Record(
                message,
                "异常: " e.Message,
                "无异常",
                "FAIL"
            )
        }
    }

    static Skip(message, reason := "") {
        TestReporter._Record(
            message,
            "跳过",
            reason != "" ? reason : "跳过",
            "SKIP"
        )
    }

    ; =================================================================
    ; 记录
    ; =================================================================
    static _Record(testName, actual, expected, status) {
        entry := Map(
            "test", testName,
            "scenario", TestReporter.currentScenario,
            "status", status,
            "expected", expected,
            "actual", actual,
            "timestamp", A_Now
        )
        TestReporter.results.Push(entry)

        prefix := ""
        switch status {
            case "PASS": prefix := "  PASS: "
            case "FAIL": prefix := "  FAIL: "
            case "SKIP": prefix := "  SKIP: "
        }
        OutputDebug(prefix testName)

        if status = "FAIL" {
            OutputDebug("    期望: " expected)
            OutputDebug("    实际: " actual)
        }
    }

    ; =================================================================
    ; 汇总
    ; =================================================================
    static EndTest() {
        summary := TestReporter.Summarize()
        ; 报告名按脚本名固定（不再用时间戳）：外部 runner 才知道该读哪个文件
        reportPath := TestReporter.ExportReport(StrReplace(A_ScriptName, ".ahk", ".json"))
        return {summary: summary, reportPath: reportPath}
    }

    ; =================================================================
    ; 独立脚本的收尾（C2：tests/ 下不走 run_all_tests 的那批）
    ;
    ; ⚠️ 必须用 Finish() 取代 EndTest() + 裸 ExitApp()：裸 ExitApp() 退出码恒为 0，
    ; 于是「有断言失败」和「全过」在外部看来一模一样 —— 实测
    ; test_key_test_integration 有 11 条断言失败，退出码仍然是 0。
    ; 这些脚本各自要独立进程（全局状态互相污染），只能靠退出码把结果带出来。
    ; =================================================================
    static Finish() {
        r := TestReporter.EndTest()
        ExitApp(r.summary.failed > 0 ? 1 : 0)
    }

    static Summarize() {
        passed := 0
        failed := 0
        skipped := 0

        for r in TestReporter.results {
            switch r["status"] {
                case "PASS": passed++
                case "FAIL": failed++
                case "SKIP": skipped++
            }
        }

        elapsed := A_TickCount - TestReporter.startTime

        OutputDebug("`n======== 测试结果 ========")
        OutputDebug("场景: " TestReporter.scenarioCount)
        OutputDebug("通过: " passed)
        OutputDebug("失败: " failed)
        if skipped > 0
            OutputDebug("跳过: " skipped)
        OutputDebug("耗时: " elapsed "ms")
        OutputDebug("========================`n")

        return {passed: passed, failed: failed, skipped: skipped, elapsed: elapsed}
    }

    ; =================================================================
    ; 报告导出
    ; =================================================================
    static ExportReport(fileName := "") {
        summary := TestReporter.Summarize()

        passed := 0
        failed := 0
        skipped := 0
        for r in TestReporter.results {
            switch r["status"] {
                case "PASS": passed++
                case "FAIL": failed++
                case "SKIP": skipped++
            }
        }

        ; standalone 子目录：与 run_all_tests 的产物分开，且整体被 .gitignore 忽略
        reportDir := A_ScriptDir "\reports\standalone"
        if !InStr(FileExist(reportDir), "D")
            DirCreate(reportDir)

        if fileName = "" {
            timeStamp := FormatTime(, "yyyyMMdd_HHmmss")
            fileName := "test_report_" timeStamp ".json"
        }

        filePath := reportDir "\" fileName

        reportObj := Map(
            "generatedAt", A_Now,
            "elapsedMs", A_TickCount - TestReporter.startTime,
            "summary", Map(
                "total", TestReporter.results.Length,
                "passed", passed,
                "failed", failed,
                "skipped", skipped,
                "scenarios", TestReporter.scenarioCount
            ),
            "details", TestReporter._ResultsToArray()
        )

        try {
            jsonStr := JSONSerializer.Stringify(reportObj)
            if FileExist(filePath)
                FileDelete(filePath)
            FileAppend(jsonStr, filePath, "UTF-8")
            OutputDebug("报告已导出: " filePath)
            return filePath
        } catch as e {
            OutputDebug("报告导出失败: " e.Message)
            return ""
        }
    }

    static _ResultsToArray() {
        arr := []
        for r in TestReporter.results {
            arr.Push(r)
        }
        return arr
    }

    ; =================================================================
    ; 工具
    ; =================================================================
    static _ToStr(value) {
        if !IsSet(value)
            return "<未设置>"
        if value = ""
            return "<空字符串>"
        if IsObject(value) {
            if value is Map
                return "<Map: " value.Count " keys>"
            if value is Array
                return "<Array: " value.Length " items>"
            return "<Object>"
        }
        return String(value)
    }
}
