; =================================================================
; 测试层 - 错误信息捕获器测试套件
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
#Include "test_result_reporter.ahk"
#Include "../infrastructure/error_captor.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/error_watchdog.ahk"

TestReporter.BeginTest("test_error_captor.ahk")

; =================================================================
; 场景A: IErrorCaptor 接口合规性
; =================================================================
TestReporter.Scenario("A: IErrorCaptor 接口合规性")

try {
    captor := IErrorCaptor()

    TestReporter.AssertThrows(() => captor.Capture(Map("message", "test")),
        "抽象方法", "Capture() 抛出抽象方法异常")

    TestReporter.AssertThrows(() => captor.CaptureFromDialog(),
        "抽象方法", "CaptureFromDialog() 抛出抽象方法异常")

    TestReporter.AssertThrows(() => captor.Export(),
        "抽象方法", "Export() 抛出抽象方法异常")

    errObj := Error("测试异常", "TestMethod", "C:\\test\\script.ahk")
    errObj.Line := 42
    errObj.Extra := "额外信息"
    fields := IErrorCaptor._NormalizeError(errObj)
    TestReporter.Assert(fields["message"] = "测试异常", "_NormalizeError 提取 Message")
    TestReporter.Assert(fields["what"] = "TestMethod", "_NormalizeError 提取 What")
    TestReporter.Assert(fields["file"] = "C:\\test\\script.ahk", "_NormalizeError 提取 File")
    TestReporter.AssertEqual(fields["line"], 42, "_NormalizeError 提取 Line = 42")
    TestReporter.Assert(fields["extra"] = "额外信息", "_NormalizeError 提取 Extra")

    emptyFields := IErrorCaptor._NormalizeError(Map())
    TestReporter.Assert(emptyFields["message"] = "", "_NormalizeError 空对象 Message 为空")
    TestReporter.AssertEqual(emptyFields["line"], 0, "_NormalizeError 空对象 Line = 0")
    TestReporter.Assert(emptyFields["file"] = "", "_NormalizeError 空对象 File 为空")

    TestReporter.AssertEqual(captor.GetCapturedCount(), 0, "新实例 GetCapturedCount = 0")
} catch as e {
    TestReporter.Assert(false, "场景A 意外异常: " e.Message)
}

; =================================================================
; 场景B: ErrorRecord 数据结构
; =================================================================
TestReporter.Scenario("B: ErrorRecord 数据结构")

try {
    fields := ErrorRecord.CreateErrorFields("测试", "WhatInfo", "C:\\a.ahk", 10, "extra", "stack trace")
    record := ErrorRecord.Create("OnError", fields)

    TestReporter.Assert(record is Map, "ErrorRecord.Create 返回 Map")
    TestReporter.Assert(record.Has("timestamp"), "record 包含 timestamp")
    TestReporter.Assert(record.Has("captor"), "record 包含 captor")
    TestReporter.Assert(record["captor"] = "OnError", "record captor = OnError")
    TestReporter.Assert(record.Has("fields"), "record 包含 fields")

    rf := record["fields"]
    TestReporter.Assert(rf["message"] = "测试", "fields.message = 测试")
    TestReporter.Assert(rf["what"] = "WhatInfo", "fields.what = WhatInfo")
    TestReporter.Assert(rf["file"] = "C:\\a.ahk", "fields.file = C:\\a.ahk")
    TestReporter.AssertEqual(rf["line"], 10, "fields.line = 10")
    TestReporter.Assert(rf["extra"] = "extra", "fields.extra = extra")
    TestReporter.Assert(rf["stack"] = "stack trace", "fields.stack = stack trace")

    str := ErrorRecord.ToString(record)
    TestReporter.Assert(InStr(str, "[OnError]") > 0, "ToString 包含 [OnError]")
    TestReporter.Assert(InStr(str, "测试") > 0, "ToString 包含 message")
    TestReporter.Assert(InStr(str, "C:\\a.ahk") > 0, "ToString 包含 file 路径")

    minRecord := ErrorRecord.Create("Dialog", ErrorRecord.CreateErrorFields())
    minStr := ErrorRecord.ToString(minRecord)
    TestReporter.Assert(InStr(minStr, "[Dialog]") > 0, "ToString 最小记录包含 captor")
} catch as e {
    TestReporter.Assert(false, "场景B 意外异常: " e.Message)
}

; =================================================================
; 场景C: ErrorCaptureLog 持久化
; =================================================================
TestReporter.Scenario("C: ErrorCaptureLog 持久化")

try {
    testLogFile := "_unittest_capture.jsonl"
    fullPath := ErrorCaptureLog.dir "\" testLogFile

    if FileExist(fullPath)
        FileDelete(fullPath)

    entry := Map()
    entry["timestamp"] := "20250101000000"
    entry["captor"] := "UnitTest"
    entry["message"] := "测试写入"

    ErrorCaptureLog.Append(entry, testLogFile)
    TestReporter.Assert(FileExist(fullPath), "Append 后文件存在")

    content := FileRead(fullPath, "UTF-8")
    TestReporter.Assert(InStr(content, "UnitTest") > 0, "文件内容包含 captor 名称")
    TestReporter.Assert(InStr(content, "测试写入") > 0, "文件内容包含 message")

    parsed := JSONParser.Parse(RTrim(content, "`n"))
    TestReporter.Assert(parsed is Map, "写入内容为有效 JSON (Map)")
    TestReporter.Assert(parsed["captor"] = "UnitTest", "JSON 解析后 captor = UnitTest")

    lines := ErrorCaptureLog.ReadAll(testLogFile)
    TestReporter.Assert(lines.Length >= 1, "ReadAll 返回至少 1 条记录")

    entry2 := Map()
    entry2["timestamp"] := "20250101000001"
    entry2["captor"] := "FilterTest"
    entry2["message"] := "过滤测试 XYZ"
    ErrorCaptureLog.Append(entry2, testLogFile)

    filtered := ErrorCaptureLog.ReadAll(testLogFile, "XYZ")
    TestReporter.AssertEqual(filtered.Length, 1, "filter='XYZ' 只返回 1 条匹配记录")
    TestReporter.Assert(InStr(filtered[1], "FilterTest") > 0, "filter 返回正确条目")

    noMatch := ErrorCaptureLog.ReadAll(testLogFile, "NONEXISTENT")
    TestReporter.AssertEqual(noMatch.Length, 0, "无匹配 filter 返回空数组")

    FileDelete(fullPath)
} catch as e {
    TestReporter.Assert(false, "场景C 意外异常: " e.Message)
    try {
        FileDelete(ErrorCaptureLog.dir "\_unittest_capture.jsonl")
    }
}

; =================================================================
; 场景D: OnErrorCaptor 核心功能
; =================================================================
TestReporter.Scenario("D: OnErrorCaptor 核心功能")

try {
    oc := OnErrorCaptor()

    TestReporter.Assert(oc._captorName = "OnError", "_captorName = OnError")
    TestReporter.AssertEqual(oc._errorCount, 0, "初始 _errorCount = 0")

    errObj := Error("D场景测试异常", "D_TestMethod", "C:\\test\\d_script.ahk")
    errObj.Line := 55
    errObj.Extra := "D场景额外"
    errObj.Stack := "D场景堆栈"

    result := oc.Capture(errObj)
    TestReporter.Assert(result is Map, "Capture 返回 Map")
    TestReporter.Assert(result.Has("fields"), "返回 record 包含 fields")
    TestReporter.Assert(result["fields"]["message"] = "D场景测试异常", "Capture 提取 message")
    TestReporter.AssertEqual(result["fields"]["line"], 55, "Capture 提取 line = 55")
    TestReporter.Assert(result["fields"]["extra"] = "D场景额外", "Capture 提取 extra")
    TestReporter.Assert(result["captor"] = "OnError", "Capture record captor = OnError")

    last := oc.GetLastError()
    TestReporter.Assert(last is Map, "GetLastError 返回 Map")
    TestReporter.Assert(last.Has("fields"), "GetLastError record 包含 fields")
    TestReporter.Assert(last["fields"]["message"] = "D场景测试异常", "GetLastError message 正确")

    errObj2 := Error("第二次错误")
    oc.Capture(errObj2)
    last2 := oc.GetLastError()
    TestReporter.Assert(last2["fields"]["message"] = "第二次错误", "GetLastError 返回最新错误")

    TestReporter.AssertEqual(oc.GetCapturedCount(), 2, "GetCapturedCount = 2")
    TestReporter.Assert(oc.CaptureFromDialog() is Map, "CaptureFromDialog 返回 Map")

    oc._mode := "production"
    TestReporter.Assert(oc._mode = "production", "设置 _mode 为 production 后正确保存")

    oc._mode := "development"
    TestReporter.Assert(oc._mode = "development", "设置 _mode 为 development 后正确保存")

    TestReporter.AssertNoThrow(() => oc.Export(), "Export 不抛异常")
} catch as e {
    TestReporter.Assert(false, "场景D 意外异常: " e.Message)
}

; =================================================================
; 场景E: DialogCaptor 文本解析
; =================================================================
TestReporter.Scenario("E: DialogCaptor 文本解析")

try {
    dc := DialogCaptor()

    errorDialogText := "Error: Call to nonexistent function`nSpecifically: FooBar()"
        . "`n`n---- C:\my_scripts\test.ahk`n`n030: CallWithDefault()"
        . "`n`n032: }`n`n--->`t033: FooBar()"
        . "`n`n034: Exit`n`nThe current thread will exit."

    parsed := dc._ParseDialogText(errorDialogText)

    TestReporter.Assert(parsed is Map, "_ParseDialogText 返回 Map")
    TestReporter.Assert(parsed["message"] = "Error: Call to nonexistent function",
        "解析提取 message 首行")
    TestReporter.Assert(parsed["what"] = "FooBar()", "解析提取 what (Specifically 行)")
    TestReporter.Assert(parsed["file"] = "test.ahk", "解析提取文件名")
    TestReporter.Assert(parsed["line"] > 0, "解析提取行号 > 0")
    TestReporter.Assert(InStr(parsed["stack"], "Call to nonexistent") > 0,
        "stack 包含原始文本")

    emptyParsed := dc._ParseDialogText("")
    TestReporter.Assert(emptyParsed is Map, "空文本 _ParseDialogText 返回 Map")
    TestReporter.Assert(emptyParsed["message"] = "", "空文本 message 为空")
    TestReporter.AssertEqual(emptyParsed["line"], 0, "空文本 line = 0")
    TestReporter.Assert(emptyParsed["file"] = "", "空文本 file 为空")

    simpleParsed := dc._ParseDialogText("单行错误信息")
    TestReporter.Assert(simpleParsed["message"] = "单行错误信息", "单行文本 message 正确")

    complexText := "Error in #Include file`nSpecifically: Module.ahk"
        . "`n`n---- D:\path\to\main.ahk`n`n120: Foo()"
        . "`n`n--->`t125: Bar()"
        . "`n`nThe program will exit."
    complexParsed := dc._ParseDialogText(complexText)
    TestReporter.Assert(complexParsed["file"] = "main.ahk", "复杂文本正确提取 file")
    TestReporter.Assert(complexParsed["line"] > 0, "复杂文本正确提取 line")
} catch as e {
    TestReporter.Assert(false, "场景E 意外异常: " e.Message)
}

; =================================================================
; 场景F: ErrorCaptureMode 模式管理
; =================================================================
TestReporter.Scenario("F: ErrorCaptureMode 模式管理")

try {
    ErrorCaptureMode.onErrorInstance := ""
    ErrorCaptureMode.dialogInstance := ""
    ErrorCaptureMode.mode := ""
    ErrorCaptureMode.activeCaptor := ""

    result := ErrorCaptureMode.Init("production")
    TestReporter.AssertEqual(result, "OnError", "Init('production') 返回 OnError")
    TestReporter.Assert(ErrorCaptureMode.activeCaptor = "OnError",
        "production 模式 activeCaptor = OnError")
    TestReporter.Assert(ErrorCaptureMode.mode = "production",
        "production 模式 mode = production")
    TestReporter.Assert(ErrorCaptureMode.IsProduction() = true,
        "IsProduction() = true")
    TestReporter.Assert(ErrorCaptureMode.onErrorInstance != "",
        "production 模式 onErrorInstance 已创建")
    TestReporter.Assert(ErrorCaptureMode.dialogInstance = "",
        "production 模式 dialogInstance 未创建")

    lastBeforeCapture := ErrorCaptureMode.GetLastError()
    TestReporter.Assert(lastBeforeCapture is Map, "GetLastError 在无错误时返回 Map")

    ; Toggle 到 development
    ErrorCaptureMode.Toggle()
    TestReporter.Assert(ErrorCaptureMode.mode = "development",
        "Toggle 后 mode = development")
    TestReporter.Assert(ErrorCaptureMode.activeCaptor = "Dialog",
        "Toggle 后 activeCaptor = Dialog")
    TestReporter.Assert(ErrorCaptureMode.IsProduction() = false,
        "Toggle 后 IsProduction() = false")
    TestReporter.Assert(ErrorCaptureMode.dialogInstance != "",
        "Toggle 后 dialogInstance 已创建")

    ; Toggle 回 production
    ErrorCaptureMode.Toggle()
    TestReporter.Assert(ErrorCaptureMode.mode = "production",
        "再次 Toggle 后 mode = production")
    TestReporter.Assert(ErrorCaptureMode.activeCaptor = "OnError",
        "再次 Toggle 后 activeCaptor = OnError")
    TestReporter.Assert(ErrorCaptureMode.IsProduction() = true,
        "再次 Toggle 后 IsProduction() = true")

    errObj := Error("F场景测试")
    ErrorCaptureMode.Capture(errObj)
    lastAfterCapture := ErrorCaptureMode.GetLastError()
    TestReporter.Assert(lastAfterCapture is Map, "Capture 后 GetLastError 返回 Map")
    TestReporter.Assert(lastAfterCapture.Count > 0
        || (lastAfterCapture.Has("fields") && lastAfterCapture["fields"].Has("message")),
        "Capture 后 GetLastError 包含捕获数据")

    TestReporter.AssertNoThrow(() => ErrorCaptureMode.Export(), "Export 不抛异常")

    ErrorCaptureMode.Capture("")
    TestReporter.Assert(lastAfterCapture is Map, "Capture 空字符串不崩溃")

    ErrorCaptureMode.onErrorInstance := ""
    ErrorCaptureMode.dialogInstance := ""
    ErrorCaptureMode.mode := ""
    ErrorCaptureMode.activeCaptor := ""
} catch as e {
    TestReporter.Assert(false, "场景F 意外异常: " e.Message)
    ErrorCaptureMode.onErrorInstance := ""
    ErrorCaptureMode.dialogInstance := ""
    ErrorCaptureMode.mode := ""
    ErrorCaptureMode.activeCaptor := ""
}

; =================================================================
; 场景G: ErrorWatchdog 模块可加载
; =================================================================
TestReporter.Scenario("G: ErrorWatchdog 模块可加载")

try {
    TestReporter.Assert(IsObject(ErrorWatchdog), "ErrorWatchdog 类存在")
    TestReporter.Assert(ErrorWatchdog.pollInterval > 0, "ErrorWatchdog 有 pollInterval 属性")
    TestReporter.Assert(ErrorWatchdog.heartbeatFile != "", "ErrorWatchdog 有 heartbeatFile 属性")
    TestReporter.Assert(ErrorWatchdog.HasProp("mainProcName"), "ErrorWatchdog 有 mainProcName 属性")
    TestReporter.Assert(ErrorWatchdog.HasProp("Start"), "ErrorWatchdog 有 Start 方法")
    TestReporter.Assert(ErrorWatchdog.HasProp("Stop"), "ErrorWatchdog 有 Stop 方法")
    TestReporter.Assert(ErrorWatchdog.HasProp("_ParseFilePath"), "ErrorWatchdog 有 _ParseFilePath 方法")

    filePath := ErrorWatchdog._ParseFilePath("Error in C:\\path\\to\\module.ahk at line 42")
    TestReporter.Assert(filePath = "module.ahk", "_ParseFilePath 提取文件名正确")

    lineNum := ErrorWatchdog._ParseLineNumber("042: SomeFunction()")
    TestReporter.AssertEqual(lineNum, 42, "_ParseLineNumber 提取行号 = 42")
} catch as e {
    TestReporter.Assert(false, "场景G 意外异常: " e.Message)
}

summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed > 0 ? 1 : 0)
