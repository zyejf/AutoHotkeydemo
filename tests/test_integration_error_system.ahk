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
TestReporter.AssertThrows(
    () => ModeRegistry.Register("test_mode", "not_an_executor"),
    "IExecutor",
    "ModeRegistry.Register 捕获无效执行器错误"
)

; 测试 SkillGroup 构造错误捕获（通过 ModeRegistry）
TestReporter.AssertNoThrow(
    () => SkillGroup("test_group", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}),
    "SkillGroup 构造不崩溃"
)

; 测试 SkillManager 错误捕获
TestReporter.AssertThrows(
    () => SkillManager.AddGroup("", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}),
    "",
    "SkillManager.AddGroup 捕获空ID错误"
)

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

; 测试 ConfigService 错误捕获
TestReporter.AssertThrows(
    () => ConfigService.GetGroupConfig("non_existent_config_xyz"),
    "不存在",
    "ConfigService.GetGroupConfig 捕获配置不存在错误"
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

; 测试 BackupUI 错误捕获
TestReporter.AssertNoThrow(
    () => BackupUI.Init(),
    "BackupUI.Init 不崩溃"
)

; 测试 GroupEditor 错误捕获
TestReporter.AssertNoThrow(
    () => GroupEditor.Init(),
    "GroupEditor.Init 不崩溃"
)

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

; 获取错误计数
errorCount := ErrorSystem.GetErrorCount()
TestReporter.Assert(
    errorCount > 0,
    "错误计数 > 0，当前: " errorCount
)

; 手动记录错误并验证计数增加
initialCount := ErrorSystem.GetErrorCount()
ErrorSystem.LogError("集成测试手动错误", "ERROR", "test_integration_error_system.ahk", A_LineNumber)
Sleep(50)  ; 等待日志写入
newCount := ErrorSystem.GetErrorCount()

TestReporter.Assert(
    newCount > initialCount,
    "手动记录错误后计数增加: " initialCount " -> " newCount
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

TestReporter.AssertNoThrow(
    () => ErrorSystem.LogInfo("INFO 级别测试"),
    "INFO 级别错误记录成功"
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

ExitApp(summary.failed > 0 ? 1 : 0)
