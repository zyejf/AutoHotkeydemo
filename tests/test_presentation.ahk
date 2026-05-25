; =================================================================
; 测试层 - 表现层断言式验证脚本
; 版本: 3.1
; 说明: 验证 presentation 层 WebView2Manager 和 UIManager 的接口合规、
;       可加载性和基本功能
;       使用结构化断言框架，ExitApp(0) 成功 / ExitApp(1) 失败
; 运行: AutoHotkey.exe tests\test_presentation.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)
#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"
#Include "../presentation/ui_manager.ahk"
#Include "../presentation/webview2_manager.ahk"

TestReporter.BeginTest("test_presentation.ahk")

; ============================================================
; 场景 A: UIManager 接口合规
; ============================================================
TestReporter.Scenario("UIManager 接口合规")
TestReporter.Assert(ObjGetBase(UIManager) = INotifier, "UIManager 继承自 INotifier")

; ============================================================
; 场景 B: UIManager.Init 不崩溃
; ============================================================
TestReporter.Scenario("UIManager.Init 不崩溃")
TestReporter.AssertNoThrow(() => UIManager.Init(), "UIManager.Init() 不抛出异常")

; ============================================================
; 场景 C: UIManager.Notify 各类型
; ============================================================
TestReporter.Scenario("UIManager.Notify 各类型")
types := ["success", "error", "warning", "info"]
for t in types {
    TestReporter.AssertNoThrow(() => UIManager.Notify("测试消息 " t, t), "Notify 类型=" t " 不崩溃")
}

; ============================================================
; 场景 D: UIManager.ShowBriefInfo 各状态
; ============================================================
TestReporter.Scenario("ShowBriefInfo 各状态")
TestReporter.AssertNoThrow(() => UIManager.ShowBriefInfo(0, false), "ShowBriefInfo 待机状态(0,false) 不崩溃")
TestReporter.AssertNoThrow(() => UIManager.ShowBriefInfo(3, false), "ShowBriefInfo 运行状态(3,false) 不崩溃")
TestReporter.AssertNoThrow(() => UIManager.ShowBriefInfo(0, true), "ShowBriefInfo 紧急状态(0,true) 不崩溃")

; ============================================================
; 场景 E: WebView2Manager 类存在和结构
; ============================================================
TestReporter.Scenario("WebView2Manager 类存在和结构")
TestReporter.Assert(IsSet(WebView2Manager), "WebView2Manager 类存在")
TestReporter.Assert(HasProp(WebView2Manager, "Show"), "WebView2Manager.Show 方法存在")
TestReporter.Assert(HasProp(WebView2Manager, "_InitWebView2"), "WebView2Manager._InitWebView2 方法存在")
TestReporter.Assert(HasProp(WebView2Manager, "_OnResize"), "WebView2Manager._OnResize 方法存在")
TestReporter.Assert(HasProp(WebView2Manager, "_OnClose"), "WebView2Manager._OnClose 方法存在")
TestReporter.Assert(HasProp(WebView2Manager, "_StartAutoUpdate"), "WebView2Manager._StartAutoUpdate 方法存在")
TestReporter.Assert(HasProp(WebView2Manager, "_StopAutoUpdate"), "WebView2Manager._StopAutoUpdate 方法存在")

; ============================================================
; 场景 F: WebView2Manager Bridge 方法存在
; ============================================================
TestReporter.Scenario("WebView2Manager Bridge 方法存在")
bridgeMethods := [
    "_BridgeSaveConfig",
    "_BridgeLoadConfig",
    "_BridgeLoadGroupConfig",
    "_BridgeGetGroupList",
    "_BridgeSaveSettings",
    "_BridgeLoadSettings",
    "_BridgeEmergencyStop",
    "_BridgeToggleAll",
    "_BridgeHotReload",
    "_BridgeToggleGroup",
    "_BridgeDeleteGroup",
    "_BridgeCreateBackup",
    "_BridgeRestoreBackup",
    "_BridgeDeleteBackup",
    "_BridgeListBackups",
    "_BridgeGetDebugInfo"
]
for method in bridgeMethods {
    TestReporter.Assert(HasProp(WebView2Manager, method), "WebView2Manager." method " 方法存在")
}

; ============================================================
; 场景 G: TrayManager 类存在和结构
; ============================================================
TestReporter.Scenario("TrayManager 类存在和结构")
TestReporter.Assert(IsSet(TrayManager), "TrayManager 类存在")
TestReporter.Assert(HasProp(TrayManager, "Init"), "TrayManager.Init 方法存在")

; ============================================================
; 场景 H: WebView2Manager 静态属性初始值
; ============================================================
TestReporter.Scenario("WebView2Manager 静态属性初始值")
TestReporter.AssertEqual(WebView2Manager.wvc, "", "wvc 初始为空字符串")
TestReporter.AssertEqual(WebView2Manager.wv, "", "wv 初始为空字符串")
TestReporter.AssertEqual(WebView2Manager.mainGui, "", "mainGui 初始为空字符串")
TestReporter.AssertEqual(WebView2Manager.visible, false, "visible 初始为 false")

; ============================================================
; 场景 I: Bridge 方法连接领域服务（无GUI环境）
; ============================================================
TestReporter.Scenario("Bridge 方法连接领域服务")

JSONLogger.Init()
DebugLogger.Init()
ConfigStore.InitDefaults()
ConfigService.ConfigStore := ConfigStore
ConfigService.SkillManager := SkillManager
ConfigService.Notifier := UIManager
GroupService.ConfigStore := ConfigStore
GroupService.SkillManager := SkillManager
SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := UIManager
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
SkillManager.Logger := JSONLogger
SkillManager.Notifier := UIManager
SkillManager.ConfigStore := ConfigStore
ErrorSystem.Init()
ModeRegistry._Init()
ConfigService.LoadConfig()

TestReporter.AssertNoThrow(() => WebView2Manager._BridgeGetGroupList(), "_BridgeGetGroupList 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeLoadConfig(), "_BridgeLoadConfig 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeLoadSettings(), "_BridgeLoadSettings 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeGetDebugInfo(), "_BridgeGetDebugInfo 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeListBackups(), "_BridgeListBackups 不崩溃")

; ============================================================
; 场景 J: Bridge 返回值格式验证
; ============================================================
TestReporter.Scenario("Bridge 返回值格式验证")
groupList := WebView2Manager._BridgeGetGroupList()
TestReporter.Assert(groupList is String, "_BridgeGetGroupList 返回字符串")
TestReporter.Assert(SubStr(groupList, 1, 1) = "[" || SubStr(groupList, 1, 1) = "{", "_BridgeGetGroupList 返回 JSON")

debugInfo := WebView2Manager._BridgeGetDebugInfo()
TestReporter.Assert(debugInfo is String, "_BridgeGetDebugInfo 返回字符串")
TestReporter.Assert(SubStr(debugInfo, 1, 1) = "{", "_BridgeGetDebugInfo 返回 JSON 对象")

backupList := WebView2Manager._BridgeListBackups()
TestReporter.Assert(backupList is String, "_BridgeListBackups 返回字符串")
TestReporter.Assert(SubStr(backupList, 1, 1) = "[" || SubStr(backupList, 1, 1) = "{", "_BridgeListBackups 返回 JSON")

; ============================================================
; 结果汇总
; ============================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
if summary.failed > 0
    ExitApp(1)
ExitApp(0)
