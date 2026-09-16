; =================================================================
; 测试层 - 错误系统集成测试
; 版本: 1.0
; 说明: 验证全项目错误处理集成，测试所有模块错误捕获功能
; 运行: AutoHotkey.exe tests\test_integration_error_system.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; =================================================================
; 引入依赖
; =================================================================
#Include "test_result_reporter.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"
#Include "../presentation/ui_manager.ahk"
#Include "../presentation/backup_ui.ahk"
#Include "../presentation/group_editor.ahk"

; =================================================================
; 全局配置
; =================================================================
ErrorSystem.logFile := A_ScriptDir "\logs\test_integration_errors.log"
OnError(ErrorSystem_HandleError, -1)

; ModeRegistry 不初始化就是一张空表 —— SkillGroup 拿任何模式去构造都会报
; 「无效的执行模式」，连 "periodic" 这种确实注册过的模式也不例外。
; （test_key_validator.ahk 里有这行，这里漏了。）
ModeRegistry._Init()

; 测试日志必须从干净状态开始：旧格式（多行 pretty JSON）的残留会让「日志格式」断言
; 一直红，而那反映的是历史数据，不是本次实现的结论。
if FileExist(ErrorSystem.logFile)
    FileDelete(ErrorSystem.logFile)

; =================================================================
; 测试开始
; =================================================================
TestReporter.BeginTest("test_integration_error_system.ahk")

; ============================================================
; 场景A: 领域层错误捕获测试
; ============================================================
TestReporter.Scenario("领域层错误捕获")

; 测试 ModeRegistry 错误捕获
TestReporter.AssertThrows(
    () => ModeRegistry.GetExecutor("invalid_mode_xyz"),
    "未注册",
    "ModeRegistry.GetExecutor 捕获无效模式错误"
)

; 测试 ModeRegistry 注册错误捕获
; Register 的契约是「记日志并返回 false」，不是抛异常（见 mode_registry.ahk）。
; 原来用 AssertThrows 断言，等于在测一个不存在的 throw。
TestReporter.AssertNoThrow(
    () => ModeRegistry.Register("test_mode", "not_an_executor"),
    "ModeRegistry.Register 无效执行器不抛异常"
)
TestReporter.Assert(
    ModeRegistry.Register("test_mode", "not_an_executor") = false,
    "ModeRegistry.Register 无效执行器返回 false"
)

; 测试 SkillGroup 构造错误捕获（通过 ModeRegistry）
TestReporter.AssertNoThrow(
    () => SkillGroup("test_group", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}),
    "SkillGroup 构造不崩溃"
)

; 测试 SkillManager 错误捕获
; 原来断言 AddGroup("") 抛异常，但 AddGroup 的契约是「返回 false」，且空 ID 目前
; 根本没有校验（expectedMsgPart 还是空串，这条断言本就什么都没验）。
; 改成钉住真实契约：重复 ID 返回 false。（空 ID 未校验 → 记为已知缺口，见技术债台账）
TestReporter.AssertNoThrow(
    () => SkillManager.AddGroup("", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}),
    "SkillManager.AddGroup 空ID 不抛异常"
)
_dupCfg := {mode: "periodic", hotkey: "F2", keys: ["b"], intervals: [50]}
_dupFirst := SkillManager.AddGroup("dup-test", _dupCfg)
_dupSecond := SkillManager.AddGroup("dup-test", _dupCfg)
TestReporter.Assert(_dupFirst != false && _dupSecond = false, "SkillManager.AddGroup 重复ID 返回 false")

; ============================================================
; 场景B: 应用层错误捕获测试
; ============================================================
TestReporter.Scenario("应用层错误捕获")

; 初始化应用层依赖
try {
    GroupService.SkillManager := SkillManager
    GroupService.ConfigStore := ConfigStore
} catch {
    ; 忽略初始化错误
}

; 测试 GroupService 错误捕获
TestReporter.AssertThrows(
    () => GroupService.GetGroup("non_existent_group_xyz"),
    "不存在",
    "GroupService.GetGroup 捕获分组不存在错误"
)

; 测试分组配置错误捕获
; 注意：GetGroupConfig 属于 GroupService（抛「分组配置不存在」），ConfigService 上从来没有这个方法。
; 之前写成 ConfigService.GetGroupConfig 会抛「未知方法」，AssertThrows 照样判 PASS —— 是个假通过。
TestReporter.AssertThrows(
    () => GroupService.GetGroupConfig("non_existent_config_xyz"),
    "分组配置不存在",
    "GroupService.GetGroupConfig 捕获配置不存在错误"
)

; ============================================================
; 场景C: 表现层错误捕获测试
; ============================================================
TestReporter.Scenario("表现层错误捕获")

; 测试 UIManager 错误捕获（不抛出异常，只记录日志）
TestReporter.AssertNoThrow(
    () => UIManager.Notify("测试消息", "info", 100),
    "UIManager.Notify 不崩溃"
)

TestReporter.AssertNoThrow(
    () => UIManager.ShowBriefInfo(0, false),
    "UIManager.ShowBriefInfo 不崩溃"
)

; 测试 BackupUI / GroupEditor 的公开入口契约
; 原来断言的是 BackupUI.Init() / GroupEditor.Init()，但这两个入口在重构中已改名为
; Show() / Open()，且都不再是「无副作用的初始化」—— 直接调用会真的弹出 GUI，
; 无头测试里既跑不动也不该跑。改为守住「公开入口仍然存在」这条契约：
; 正是这次腐烂（方法被改名/移除）要拦的东西。
TestReporter.Assert(HasMethod(BackupUI, "Show"), "BackupUI 公开入口 Show 仍存在")
TestReporter.Assert(HasMethod(GroupEditor, "Open"), "GroupEditor 公开入口 Open 仍存在")

; ============================================================
; 场景D: 错误日志验证
; ============================================================
TestReporter.Scenario("错误日志验证")

; 验证日志文件存在
logFile := ErrorSystem.logFile
TestReporter.Assert(
    FileExist(logFile) != "",
    "错误日志文件存在: " logFile
)

; 验证日志格式（JSON Lines）
if FileExist(logFile) {
    content := FileRead(logFile, "UTF-8")
    lines := StrSplit(content, "`n")

    validLines := 0
    invalidLines := 0

    for line in lines {
        line := Trim(line)
        if (line = "")
            continue

        ; 验证 JSON 格式
        if (SubStr(line, 1, 1) = "{" && SubStr(line, StrLen(line), 1) = "}") {
            ; 验证必需字段
            hasTimestamp := InStr(line, '"timestamp"')
            hasLevel := InStr(line, '"level"')
            hasType := InStr(line, '"type"')
            hasMessage := InStr(line, '"message"')

            if (hasTimestamp && hasLevel && hasType && hasMessage)
                validLines++
            else
                invalidLines++
        } else {
            invalidLines++
        }
    }

    TestReporter.Assert(
        validLines > 0,
        "日志格式正确，有效行数: " validLines
    )

    TestReporter.Assert(
        invalidLines = 0,
        "日志格式无无效行"
    )
} else {
    TestReporter.Skip("日志文件不存在，跳过格式验证")
}

; ============================================================
; 场景E: 错误计数验证
; ============================================================
TestReporter.Scenario("错误计数验证")

; GetErrorCount() 只统计 HandleError() 处理过的错误 —— _errorCount 仅在 HandleError 里 ++，
; LogError / LogWarning 只是写日志、不计入。所以基线必须先用一次 HandleError 立起来，
; 否则这里永远是 0（改这段前先看 error_system.ahk 的实现，别再按「日志条数」去理解计数）。
ErrorSystem.HandleError(Error("错误计数基线"), "Test")
errorCount := ErrorSystem.GetErrorCount()
TestReporter.Assert(
    errorCount > 0,
    "错误计数 > 0，当前: " errorCount
)

; 再处理一个，计数必须继续增加
initialCount := ErrorSystem.GetErrorCount()
ErrorSystem.HandleError(Error("集成测试第二个错误"), "Test")
Sleep(50)  ; 等待日志写入
newCount := ErrorSystem.GetErrorCount()

TestReporter.Assert(
    newCount > initialCount,
    "HandleError 后计数增加: " initialCount " -> " newCount
)

; 反向钉住：LogError 只落盘、不计数。这条要是红了，说明 GetErrorCount 的语义变了。
countBefore := ErrorSystem.GetErrorCount()
ErrorSystem.LogError("集成测试手动错误", "ERROR", "test_integration_error_system.ahk", A_LineNumber)
Sleep(50)
TestReporter.Assert(
    ErrorSystem.GetErrorCount() = countBefore,
    "LogError 只写日志，不增加错误计数"
)

; ============================================================
; 场景F: 无弹窗验证
; ============================================================
TestReporter.Scenario("无弹窗验证")

; 触发错误并验证无弹窗（OnError 返回 1）
TestReporter.AssertNoThrow(
    () => ErrorSystem.HandleError(Error("测试无弹窗错误"), "Test"),
    "ErrorSystem.HandleError 不崩溃且无弹窗"
)

; 验证错误已记录
TestReporter.Assert(
    ErrorSystem.GetErrorCount() > 0,
    "错误已记录到日志"
)

; ============================================================
; 场景G: 错误级别识别测试
; ============================================================
TestReporter.Scenario("错误级别识别")

; 测试不同错误级别
TestReporter.AssertNoThrow(
    () => ErrorSystem.LogError("CRITICAL 级别测试", "CRITICAL"),
    "CRITICAL 级别错误记录成功"
)

TestReporter.AssertNoThrow(
    () => ErrorSystem.LogError("ERROR 级别测试", "ERROR"),
    "ERROR 级别错误记录成功"
)

TestReporter.AssertNoThrow(
    () => ErrorSystem.LogWarning("WARNING 级别测试"),
    "WARNING 级别错误记录成功"
)

; ErrorSystem 没有 LogInfo（只有 LogError / LogWarning，级别常量也只有 CRITICAL/ERROR/WARNING）。
; 这里真正想验证的是「传入未定义的级别不会崩」，用 LogError(msg, level) 表达即可，
; 不必为了一个没人调用的 API 去加生产代码。
TestReporter.AssertNoThrow(
    () => ErrorSystem.LogError("INFO 级别测试", "INFO"),
    "未定义级别 INFO 记录不崩溃"
)

; ============================================================
; 场景H: 错误恢复测试
; ============================================================
TestReporter.Scenario("错误恢复")

; 测试错误后系统仍可正常工作
TestReporter.AssertNoThrow(
    () => ModeRegistry.HasMode("periodic"),
    "错误后 ModeRegistry 仍可工作"
)

TestReporter.AssertNoThrow(
    () => SkillManager.Groups,
    "错误后 SkillManager 仍可工作"
)

; ============================================================
; 汇总与退出
; ============================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()

; 输出测试结果
OutputDebug("`n========================================")
OutputDebug("集成测试完成")
OutputDebug("总计: " summary.passed + summary.failed + summary.skipped " 个测试")
OutputDebug("通过: " summary.passed " 个")
OutputDebug("失败: " summary.failed " 个")
OutputDebug("跳过: " summary.skipped " 个")
OutputDebug("日志文件: " ErrorSystem.logFile)
OutputDebug("错误计数: " ErrorSystem.GetErrorCount())
OutputDebug("========================================`n")

; 统一走 TestReporter.Finish()：导出固定名报告 + 按失败数给退出码，外部 runner 才好聚合
TestReporter.Finish()
