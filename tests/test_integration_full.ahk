; =================================================================
; 测试层 - 全面集成测试
; 版本: 1.0
; 说明: 覆盖所有7种执行模式的端到端场景
;       验证跨模块交互、配置加载/保存、优化后正确性
; 运行: AutoHotkey.exe tests\test_integration_full.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"

TestReporter.BeginTest("test_integration_full.ahk")

OnError((Thrown, Mode) => (ErrorSystem.HandleError(Thrown, Mode), 1))

; =================================================================
; 初始化依赖（模拟 main.ahk 的依赖注入）
; =================================================================
TestReporter.Scenario("0: 依赖注入初始化")

JSONLogger.Init()
DebugLogger.Init()
ConfigStore.InitDefaults()
ErrorSystem.Init()
ModeRegistry._Init()

SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := {Notify: (msg, type) => ""}
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))

SkillManager.Logger := JSONLogger
SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillManager.ConfigStore := ConfigStore

GroupService.ConfigStore := ConfigStore
GroupService.SkillManager := SkillManager

ConfigService.ConfigStore := ConfigStore
ConfigService.SkillManager := SkillManager
ConfigService.Notifier := {Notify: (msg, type) => ""}

TestReporter.Assert(ModeRegistry.HasMode("periodic"), "ModeRegistry 已注册 periodic")
TestReporter.Assert(ModeRegistry.HasMode("sequence"), "ModeRegistry 已注册 sequence")
TestReporter.Assert(ModeRegistry.HasMode("hybrid"), "ModeRegistry 已注册 hybrid")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_periodic"), "ModeRegistry 已注册 enhanced_periodic")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_sequence"), "ModeRegistry 已注册 enhanced_sequence")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_hybrid"), "ModeRegistry 已注册 enhanced_hybrid")
TestReporter.Assert(ModeRegistry.HasMode("hold"), "ModeRegistry 已注册 hold")

; =================================================================
; 场景1: periodic 模式 - 创建/激活/执行/停用
; =================================================================
TestReporter.Scenario("1: periodic 模式全流程")

periodicConfig := Map(
    "hotkey", "F1",
    "mode", "periodic",
    "keys", ["Space", "a"],
    "intervals", [50, 100]
)

periodicGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("P1", periodicConfig), "创建 periodic 分组不崩溃")
periodicGroup := SkillGroup("P1", periodicConfig)
TestReporter.AssertEqual(periodicGroup.mode, "periodic", "mode = periodic")
TestReporter.AssertEqual(periodicGroup.keys.Length, 2, "keys.Length = 2")
TestReporter.AssertEqual(periodicGroup._isMouse.Length, 2, "_isMouse 已初始化")
TestReporter.AssertEqual(periodicGroup._isMouse[1], false, "Space 不是鼠标键")
TestReporter.AssertEqual(periodicGroup._lastTriggerTimes.Count, 2, "_lastTriggerTimes 已初始化")
TestReporter.AssertEqual(periodicGroup._groupTriggerTimes.Count, 0, "_groupTriggerTimes 为空(非混合模式)")
TestReporter.AssertEqual(periodicGroup._seqSteps.Count, 0, "_seqSteps 为空(非混合模式)")

TestReporter.AssertEqual(periodicGroup.Toggle(), true, "激活返回 true")
TestReporter.AssertEqual(periodicGroup.active, true, "active = true")

delay := periodicGroup.Execute()
TestReporter.Assert(delay > 0, "Execute 返回正延迟")
TestReporter.AssertEqual(periodicGroup._executionCount, 1, "执行计数 = 1")

periodicGroup._lastToggleTime := 0
TestReporter.AssertEqual(periodicGroup.Toggle(), false, "停用返回 false")
TestReporter.AssertEqual(periodicGroup.active, false, "active = false")
TestReporter.AssertEqual(periodicGroup._heldKeys.Count, 0, "_heldKeys 已清空")
TestReporter.AssertEqual(periodicGroup._lastTriggerTimes.Count, 2, "_lastTriggerTimes 保留(停用不清空)")

; =================================================================
; 场景2: sequence 模式
; =================================================================
TestReporter.Scenario("2: sequence 模式全流程")

seqConfig := Map(
    "hotkey", "F2",
    "mode", "sequence",
    "keys", ["1", "2", "3"],
    "delays", [100, 100, 100]
)

seqGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("S1", seqConfig), "创建 sequence 分组不崩溃")
seqGroup := SkillGroup("S1", seqConfig)
TestReporter.AssertEqual(seqGroup.mode, "sequence", "mode = sequence")
TestReporter.AssertEqual(seqGroup._currentStep, 1, "初始步骤 = 1")
TestReporter.AssertEqual(seqGroup._isMouse.Length, 3, "_isMouse 已初始化")

seqGroup.Toggle()
delay := seqGroup.Execute()
TestReporter.AssertEqual(seqGroup._currentStep, 2, "执行后步骤 = 2")
delay := seqGroup.Execute()
TestReporter.AssertEqual(seqGroup._currentStep, 3, "执行后步骤 = 3")
delay := seqGroup.Execute()
TestReporter.AssertEqual(seqGroup._currentStep, 1, "循环回步骤 = 1")

seqGroup._lastToggleTime := 0
seqGroup.Toggle()
TestReporter.AssertEqual(seqGroup.active, false, "sequence 停用成功")

; =================================================================
; 场景3: hybrid 模式
; =================================================================
TestReporter.Scenario("3: hybrid 模式全流程")

hybridConfig := Map(
    "hotkey", "F3",
    "mode", "hybrid",
    "groups", [
        Map("type", "periodic", "pressKeys", ["a", "b"], "intervals", [50, 50]),
        Map("type", "sequence", "pressKeys", ["1", "2"], "delays", [100, 100], "seqInterval", 100)
    ],
    "seqInterval", 100
)

hybridGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("H1", hybridConfig), "创建 hybrid 分组不崩溃")
hybridGroup := SkillGroup("H1", hybridConfig)
TestReporter.AssertEqual(hybridGroup.mode, "hybrid", "mode = hybrid")
TestReporter.Assert(hybridGroup._groupTriggerTimes.Count > 0, "_groupTriggerTimes 已填充")
TestReporter.AssertEqual(hybridGroup._seqSteps.Count, 1, "_seqSteps 已填充")
TestReporter.AssertEqual(hybridGroup._isHoldMouse.Length, 0, "hybrid 无 holdKeys 时 _isHoldMouse 为空数组")

hybridGroup.Toggle()
TestReporter.AssertEqual(hybridGroup.active, true, "hybrid 激活成功")

delay := hybridGroup.Execute()
TestReporter.Assert(delay > 0, "hybrid Execute 返回正延迟")

hybridGroup._lastToggleTime := 0
hybridGroup.Toggle()
TestReporter.AssertEqual(hybridGroup.active, false, "hybrid 停用成功")

; =================================================================
; 场景4: enhanced_periodic 模式（含鼠标键 + 长按）
; =================================================================
TestReporter.Scenario("4: enhanced_periodic 模式全流程")

epConfig := Map(
    "hotkey", "F4",
    "mode", "enhanced_periodic",
    "pressKeys", ["Space", "RButton", "a"],
    "intervals", [50, 100, 50],
    "holdKeys", ["Shift"],
    "holdMode", "continuous"
)

epGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("EP1", epConfig), "创建 enhanced_periodic 分组不崩溃")
epGroup := SkillGroup("EP1", epConfig)
TestReporter.AssertEqual(epGroup.mode, "enhanced_periodic", "mode = enhanced_periodic")
TestReporter.AssertEqual(epGroup._pressMouse.Length, 3, "_pressMouse 已初始化")
TestReporter.AssertEqual(epGroup._pressMouse[2], true, "RButton 是鼠标键")
TestReporter.AssertEqual(epGroup._pressMouse[1], false, "Space 不是鼠标键")
TestReporter.AssertEqual(epGroup._isHoldMouse.Length, 1, "_isHoldMouse 已初始化")
TestReporter.AssertEqual(epGroup._isHoldMouse[1], false, "Shift 不是鼠标键")
TestReporter.AssertEqual(epGroup._heldKeyMouse.Count, 0, "_heldKeyMouse 初始为空")

epGroup.Toggle()
TestReporter.AssertEqual(epGroup.active, true, "enhanced_periodic 激活成功")

delay := epGroup.Execute()
TestReporter.Assert(delay > 0, "enhanced_periodic Execute 返回正延迟")

epGroup._lastToggleTime := 0
epGroup.Toggle()
TestReporter.AssertEqual(epGroup.active, false, "enhanced_periodic 停用成功")

; =================================================================
; 场景5: enhanced_sequence 模式（含长按触发）
; =================================================================
TestReporter.Scenario("5: enhanced_sequence 模式全流程")

esConfig := Map(
    "hotkey", "F5",
    "mode", "enhanced_sequence",
    "pressKeys", ["1", "2", "3"],
    "pressDelays", [100, 100, 100],
    "holdKeys", ["Ctrl"],
    "holdMode", "sequence",
    "holdTriggers", [1, 0, 1]
)

esGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("ES1", esConfig), "创建 enhanced_sequence 分组不崩溃")
esGroup := SkillGroup("ES1", esConfig)
TestReporter.AssertEqual(esGroup.mode, "enhanced_sequence", "mode = enhanced_sequence")
TestReporter.AssertEqual(esGroup.holdTriggers.Length, 3, "holdTriggers 已初始化")
TestReporter.AssertEqual(esGroup._isHoldMouse.Length, 1, "_isHoldMouse 已初始化")

esGroup.Toggle()
TestReporter.AssertEqual(esGroup.active, true, "enhanced_sequence 激活成功")

delay := esGroup.Execute()
TestReporter.Assert(delay > 0, "enhanced_sequence Execute 返回正延迟")

esGroup._lastToggleTime := 0
esGroup.Toggle()
TestReporter.AssertEqual(esGroup.active, false, "enhanced_sequence 停用成功")

; =================================================================
; 场景6: enhanced_hybrid 模式（含鼠标键 + 长按）
; =================================================================
TestReporter.Scenario("6: enhanced_hybrid 模式全流程")

ehConfig := Map(
    "hotkey", "F6",
    "mode", "enhanced_hybrid",
    "groups", [
        Map("type", "periodic", "pressKeys", ["LButton", "a"], "intervals", [50, 50]),
        Map("type", "sequence", "pressKeys", ["1", "2"], "delays", [100, 100], "seqInterval", 100)
    ],
    "holdKeys", ["Shift"],
    "holdMode", "continuous",
    "seqInterval", 100
)

ehGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("EH1", ehConfig), "创建 enhanced_hybrid 分组不崩溃")
ehGroup := SkillGroup("EH1", ehConfig)
TestReporter.AssertEqual(ehGroup.mode, "enhanced_hybrid", "mode = enhanced_hybrid")
TestReporter.AssertEqual(ehGroup._periodicMouse.Length, 2, "_periodicMouse 已初始化")
TestReporter.AssertEqual(ehGroup._periodicMouse[1], true, "LButton 是鼠标键")
TestReporter.AssertEqual(ehGroup._seqMouse.Length, 2, "_seqMouse 已初始化")
TestReporter.AssertEqual(ehGroup._isHoldMouse.Length, 1, "_isHoldMouse 已初始化")

ehGroup.Toggle()
TestReporter.AssertEqual(ehGroup.active, true, "enhanced_hybrid 激活成功")

delay := ehGroup.Execute()
TestReporter.Assert(delay > 0, "enhanced_hybrid Execute 返回正延迟")

ehGroup._lastToggleTime := 0
ehGroup.Toggle()
TestReporter.AssertEqual(ehGroup.active, false, "enhanced_hybrid 停用成功")

; =================================================================
; 场景7: hold 模式
; =================================================================
TestReporter.Scenario("7: hold 模式全流程")

holdConfig := Map(
    "hotkey", "F7",
    "mode", "hold",
    "holdKeys", ["RButton", "Shift"],
    "holdDuration", 700,
    "autoRepeat", false,
    "repeatInterval", 1000
)

holdGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("HD1", holdConfig), "创建 hold 分组不崩溃")
holdGroup := SkillGroup("HD1", holdConfig)
TestReporter.AssertEqual(holdGroup.mode, "hold", "mode = hold")
TestReporter.AssertEqual(holdGroup._isHoldMouse.Length, 2, "_isHoldMouse 已初始化")
TestReporter.AssertEqual(holdGroup._isHoldMouse[1], true, "RButton 是鼠标键")
TestReporter.AssertEqual(holdGroup._isHoldMouse[2], false, "Shift 不是鼠标键")

holdGroup.Toggle()
TestReporter.AssertEqual(holdGroup.active, true, "hold 激活成功")

delay := holdGroup.Execute()
TestReporter.Assert(delay > 0, "hold Execute 返回正延迟")

holdGroup._lastToggleTime := 0
holdGroup.Toggle()
TestReporter.AssertEqual(holdGroup.active, false, "hold 停用成功")

; =================================================================
; 场景8: SkillManager 集成 - 多分组管理
; =================================================================
TestReporter.Scenario("8: SkillManager 多分组管理")

SkillManager.Groups := Map()
SkillManager._timers := Map()
SkillManager.HoldKeyRegistry := Map()
SkillManager.EmergencyMode := false

groupSettings := Map(
    "1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50]),
    "2", Map("hotkey", "F2", "mode", "sequence", "keys", ["1", "2"], "delays", [100, 100]),
    "3", Map("hotkey", "F3", "mode", "hold", "holdKeys", ["Shift"], "holdDuration", 0)
)

TestReporter.AssertNoThrow(() => SkillManager.Init(groupSettings), "SkillManager.Init 不崩溃")
TestReporter.AssertEqual(SkillManager.Groups.Count, 3, "3 个分组已注册")
TestReporter.Assert(SkillManager.Groups.Has("1"), "分组1 存在")
TestReporter.Assert(SkillManager.Groups.Has("2"), "分组2 存在")
TestReporter.Assert(SkillManager.Groups.Has("3"), "分组3 存在")

TestReporter.AssertEqual(SkillManager.GetActiveCount(), 0, "初始无活跃分组")

; =================================================================
; 场景9: 配置验证集成
; =================================================================
TestReporter.Scenario("9: ConfigValidator 集成")

validConfig := Map(
    "GroupSettings", Map(
        "1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50])
    )
)
errors := ConfigValidator.Validate(validConfig)
TestReporter.AssertEqual(errors.Length, 0, "有效配置验证通过(errors=0)")

invalidConfig := Map(
    "GroupSettings", Map(
        "1", Map("hotkey", "", "mode", "invalid_mode", "keys", [], "intervals", [])
    )
)
errors := ConfigValidator.Validate(invalidConfig)
TestReporter.Assert(errors.Length > 0, "无效配置有验证错误")

; =================================================================
; 场景10: ConfigStore 集成
; =================================================================
TestReporter.Scenario("10: ConfigStore 集成")

ConfigStore.InitDefaults()
TestReporter.Assert(ConfigStore.Has("GroupSettings"), "ConfigStore 有 GroupSettings")
TestReporter.Assert(ConfigStore.Has("HoldSettings"), "ConfigStore 有 HoldSettings")
TestReporter.Assert(ConfigStore.Has("CONTROL_HOTKEYS"), "ConfigStore 有 CONTROL_HOTKEYS")

holdSettings := ConfigStore.Get("HoldSettings")
TestReporter.Assert(IsObject(holdSettings), "HoldSettings 是对象")
TestReporter.AssertEqual(_GetProp(holdSettings, "debounceDelay", 0), 20, "debounceDelay = 20")

; =================================================================
; 场景11: JSON 解析/序列化往返
; =================================================================
TestReporter.Scenario("11: JSON 往返集成")

original := Map(
    "version", "2.0",
    "GroupSettings", Map(
        "1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space", "RButton"], "intervals", [50, 100])
    )
)

jsonStr := JSONSerializer.Stringify(original)
TestReporter.Assert(InStr(jsonStr, "RButton") > 0, "序列化包含 RButton")

reparsed := ""
TestReporter.AssertNoThrow(() => JSONParser.Parse(jsonStr), "重新解析不崩溃")
reparsed := JSONParser.Parse(jsonStr)
TestReporter.AssertEqual(reparsed["GroupSettings"]["1"]["keys"][2], "RButton", "RButton 往返一致")

; =================================================================
; 场景12: ModeRegistry 执行器获取
; =================================================================
TestReporter.Scenario("12: ModeRegistry 执行器集成")

for modeName in ["periodic", "sequence", "hybrid", "enhanced_periodic", "enhanced_sequence", "enhanced_hybrid", "hold"] {
    exec := ModeRegistry.GetExecutor(modeName)
    TestReporter.Assert(exec != "", modeName " 执行器存在")
    TestReporter.Assert(exec is IExecutor, modeName " 执行器实现 IExecutor")
}

; =================================================================
; 场景13: SkillGroup 鼠标键检测精确性
; =================================================================
TestReporter.Scenario("13: 鼠标键检测精确性")

mouseTestConfig := Map(
    "hotkey", "F99",
    "mode", "periodic",
    "keys", ["LButton", "RButton", "MButton", "a", "F1", "^LButton", "+RButton"],
    "intervals", [50, 50, 50, 50, 50, 50, 50]
)

mouseGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("MT", mouseTestConfig), "创建鼠标测试分组不崩溃")
mouseGroup := SkillGroup("MT", mouseTestConfig)
TestReporter.AssertEqual(mouseGroup._isMouse[1], true, "LButton 是鼠标键")
TestReporter.AssertEqual(mouseGroup._isMouse[2], true, "RButton 是鼠标键")
TestReporter.AssertEqual(mouseGroup._isMouse[3], true, "MButton 是鼠标键")
TestReporter.AssertEqual(mouseGroup._isMouse[4], false, "a 不是鼠标键")
TestReporter.AssertEqual(mouseGroup._isMouse[5], false, "F1 不是鼠标键")
TestReporter.AssertEqual(mouseGroup._isMouse[6], true, "^LButton 修饰后仍检测为鼠标键")
TestReporter.AssertEqual(mouseGroup._isMouse[7], true, "+RButton 修饰后仍检测为鼠标键")

; =================================================================
; 场景14: _heldKeyMouse 缓存正确性
; =================================================================
TestReporter.Scenario("14: _heldKeyMouse 缓存正确性")

holdMouseConfig := Map(
    "hotkey", "F98",
    "mode", "enhanced_periodic",
    "pressKeys", ["a"],
    "intervals", [50],
    "holdKeys", ["RButton", "Shift"],
    "holdMode", "continuous"
)

hmGroup := ""
TestReporter.AssertNoThrow(() => SkillGroup("HM", holdMouseConfig), "创建 holdMouse 测试分组不崩溃")
hmGroup := SkillGroup("HM", holdMouseConfig)
TestReporter.AssertEqual(hmGroup._isHoldMouse[1], true, "RButton holdMouse = true")
TestReporter.AssertEqual(hmGroup._isHoldMouse[2], false, "Shift holdMouse = false")

; =================================================================
; 场景15: 快速激活/停用循环
; =================================================================
TestReporter.Scenario("15: 快速激活/停用循环")

rapidConfig := Map(
    "hotkey", "F97",
    "mode", "enhanced_periodic",
    "pressKeys", ["a", "b"],
    "intervals", [50, 50],
    "holdKeys", ["Shift"],
    "holdMode", "continuous"
)

rapidGroup := SkillGroup("RP", rapidConfig)
SkillManager.HoldKeyRegistry := Map()

rapidGroup._lastToggleTime := 0
toggleResult := rapidGroup.Toggle()
TestReporter.AssertEqual(rapidGroup.active, true, "快速循环: active = true")

loop 10 {
    rapidGroup.Execute()
}

rapidGroup._lastToggleTime := 0
rapidGroup.Toggle()
TestReporter.AssertEqual(rapidGroup.active, false, "快速循环: active = false")
TestReporter.AssertEqual(rapidGroup._heldKeys.Count, 0, "停用后 _heldKeys 清空")
TestReporter.AssertEqual(rapidGroup._heldKeyMouse.Count, 0, "停用后 _heldKeyMouse 清空")

; =================================================================
; 场景16: GroupService 集成
; =================================================================
TestReporter.Scenario("16: GroupService 集成")

gsConfig := Map("hotkey", "F24", "mode", "periodic", "keys", ["a"], "intervals", [50])
gsCreated := false
gsErrorMsg := ""
try {
    result := GroupService.CreateGroup("GS1", gsConfig)
    gsCreated := result["success"]
} catch as e {
    gsErrorMsg := e.Message
}
if gsCreated {
    TestReporter._Record("GroupService.CreateGroup", "成功", "成功", "PASS")
    TestReporter.Assert(SkillManager.Groups.Has("GS1"), "GroupService 添加后分组存在")

    try {
        GroupService.DeleteGroup("GS1")
        TestReporter._Record("GroupService.DeleteGroup", "成功", "成功", "PASS")
    } catch as e2 {
        TestReporter._Record("GroupService.DeleteGroup", "异常: " e2.Message, "无异常", "FAIL")
    }
    TestReporter.Assert(!SkillManager.Groups.Has("GS1"), "GroupService 删除后分组不存在")
} else {
    TestReporter._Record("GroupService.CreateGroup (热键注册受限: " gsErrorMsg ")", "跳过", "成功", "SKIP")
    TestReporter._Record("GroupService.DeleteGroup", "跳过", "成功", "SKIP")
    TestReporter._Record("GroupService 删除后分组不存在", "跳过", "成功", "SKIP")
}

; =================================================================
; 场景17: 紧急停止集成
; =================================================================
TestReporter.Scenario("17: 紧急停止集成")

SkillManager.Groups := Map()
SkillManager._timers := Map()
SkillManager.HoldKeyRegistry := Map()
SkillManager.EmergencyMode := false

emSettings := Map(
    "1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50]),
    "2", Map("hotkey", "F2", "mode", "hold", "holdKeys", ["Shift"], "holdDuration", 0)
)
SkillManager.Init(emSettings)

TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "初始非紧急模式")

SkillManager.Emergency()
TestReporter.AssertEqual(SkillManager.EmergencyMode, true, "紧急模式已激活")
TestReporter.AssertEqual(SkillManager.GetActiveCount(), 0, "紧急停止后无活跃分组")

; =================================================================
; 场景18: 配置文件加载集成
; =================================================================
TestReporter.Scenario("18: 配置文件加载集成")

configPath := A_ScriptDir "\..\config.json"
if FileExist(configPath) {
    loaded := ""
    TestReporter.AssertNoThrow(() => JSONParser.LoadFile(configPath), "加载 config.json 不崩溃")
    loaded := JSONParser.LoadFile(configPath)
    TestReporter.Assert(IsObject(loaded), "配置是对象")
    TestReporter.Assert(loaded.Has("GroupSettings"), "配置有 GroupSettings")
    TestReporter.Assert(loaded.Has("HoldSettings"), "配置有 HoldSettings")
    TestReporter.Assert(loaded.Has("version"), "配置有 version")

    gs := loaded["GroupSettings"]
    groupCount := 0
    for id in gs
        groupCount++
    TestReporter.Assert(groupCount > 0, "GroupSettings 有分组")
} else {
    TestReporter.Skip("config.json 不存在", "文件缺失")
}

; =================================================================
; 场景19: _IsValidKeyName 优化后正确性
; =================================================================
TestReporter.Scenario("19: _IsValidKeyName 优化后正确性")

TestReporter.AssertEqual(SkillGroup._IsValidKeyName("a"), true, "a 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("Space"), true, "Space 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("F1"), true, "F1 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("F12"), true, "F12 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("LButton"), true, "LButton 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("RButton"), true, "RButton 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("MButton"), true, "MButton 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("^a"), true, "^a 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("+Space"), true, "+Space 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName(""), false, "空字符串无效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("F24"), true, "F24 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("F13"), true, "F13 有效")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("InvalidButton"), false, "InvalidButton 无效")

; =================================================================
; 场景20: HoldSettings 缓存集成
; =================================================================
TestReporter.Scenario("20: HoldSettings 缓存集成")

SkillManager._holdSettingsDirty := true
hs1 := SkillManager._GetHoldSettings()
TestReporter.Assert(IsObject(hs1), "首次获取 HoldSettings 成功")
TestReporter.AssertEqual(SkillManager._holdSettingsDirty, false, "缓存已标记为干净")

hs2 := SkillManager._GetHoldSettings()
TestReporter.Assert(hs1 = hs2, "第二次获取使用缓存(同一对象)")

SkillManager.InvalidateHoldSettingsCache()
TestReporter.AssertEqual(SkillManager._holdSettingsDirty, true, "缓存已标记为脏")

; =================================================================
; 汇总与退出
; =================================================================
summary := TestReporter.Summarize()
reportPath := TestReporter.ExportReport("integration_full_report.json")
if reportPath = "" {
    summaryJson := '{"total":' summary.total ',"passed":' summary.passed ',"failed":' summary.failed ',"skipped":' summary.skipped '}'
    FileAppend(summaryJson, A_ScriptDir "\reports\integration_full_report.json", "UTF-8")
}
ExitApp(summary.failed > 0 ? 1 : 0)
