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
    static beforeEachHooks := []
    static afterEachHooks := []

    ; =================================================================
    ; 生命周期
    ; =================================================================
    static BeginTest(testName) {
        TestReporter.results := []
        TestReporter.startTime := A_TickCount
        TestReporter.scenarioCount := 0
        TestReporter.beforeEachHooks := []
        TestReporter.afterEachHooks := []
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
    ; Setup/Teardown 钩子（确保测试间状态隔离）
    ; 用法: 在 BeginTest 后注册钩子，每个场景前自动调用 setup，后调用 teardown
    ; =================================================================
    static RegisterBeforeEach(hook) {
        TestReporter.beforeEachHooks.Push(hook)
    }

    static RegisterAfterEach(hook) {
        TestReporter.afterEachHooks.Push(hook)
    }

    static BeforeEach(name := "") {
        ; 调用所有 beforeEach 钩子（setup），确保测试隔离
        for h in TestReporter.beforeEachHooks {
            try h()
        }
        if name != ""
            TestReporter.Scenario(name)
    }

    static AfterEach() {
        ; 调用所有 afterEach 钩子（teardown），清理状态
        for h in TestReporter.afterEachHooks {
            try h()
        }
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
        reportPath := TestReporter.ExportReport()
        return {summary: summary, reportPath: reportPath}
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

        reportDir := A_ScriptDir "\reports"
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
