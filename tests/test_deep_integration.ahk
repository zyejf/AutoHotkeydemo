; =================================================================
; 深度集成测试 v3.2 - 分段执行避免挂起
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

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

TestReporter.BeginTest("test_deep_integration")

; ============================================================
; 维度1: 执行模式全覆盖（不通过SkillManager，直接创建SkillGroup）
; ============================================================

TestReporter.Scenario("执行模式: PeriodicExecutor")
pConfig := Map("mode", "periodic", "hotkey", "", "keys", ["a", "b"], "intervals", [50, 100])
pGroup := SkillGroup("test_periodic_deep", pConfig)
pGroup.active := true
pResult := pGroup.Execute()
TestReporter.AssertEqual(pResult, 10, "PeriodicExecutor 返回10")

TestReporter.Scenario("执行模式: SequenceExecutor")
sConfig := Map("mode", "sequence", "hotkey", "", "keys", ["1", "2", "3"], "delays", [100, 200, 300])
sGroup := SkillGroup("test_sequence_deep", sConfig)
sGroup.active := true
sGroup._currentStep := 1
sGroup.Execute()
TestReporter.AssertEqual(sGroup._currentStep, 2, "Sequence: 第1步后currentStep=2")

TestReporter.Scenario("执行模式: EnhancedPeriodicExecutor")
epConfig := Map("mode", "enhanced_periodic", "hotkey", "", "pressKeys", ["x", "y"], "intervals", [60, 80])
epGroup := SkillGroup("test_ep_deep", epConfig)
epGroup.active := true
epResult := epGroup.Execute()
TestReporter.AssertEqual(epResult, 10, "EnhancedPeriodicExecutor 返回10")

TestReporter.Scenario("执行模式: EnhancedSequenceExecutor")
esConfig := Map("mode", "enhanced_sequence", "hotkey", "", "pressKeys", ["a", "b"], "pressDelays", [50, 50])
esGroup := SkillGroup("test_es_deep", esConfig)
esGroup.active := true
esGroup._currentStep := 1
esGroup.Execute()
TestReporter.AssertEqual(esGroup._currentStep, 2, "EnhancedSequence: 步进到2")

TestReporter.Scenario("执行模式: HybridExecutor")
hConfig := Map("mode", "hybrid", "hotkey", "", "groups", [Map("type", "periodic", "pressKeys", ["a"], "intervals", [50])])
hGroup := SkillGroup("test_hybrid_deep", hConfig)
hGroup.active := true
hResult := hGroup.Execute()
TestReporter.AssertEqual(hResult, 10, "HybridExecutor 返回10")

TestReporter.Scenario("执行模式: EnhancedHybridExecutor")
ehConfig := Map("mode", "enhanced_hybrid", "hotkey", "", "groups", [Map("type", "periodic", "pressKeys", ["a"], "intervals", [50])])
ehGroup := SkillGroup("test_eh_deep", ehConfig)
ehGroup.active := true
ehResult := ehGroup.Execute()
TestReporter.AssertEqual(ehResult, 10, "EnhancedHybridExecutor 返回10")

TestReporter.Scenario("执行模式: HoldExecutor")
holdConfig := Map("mode", "hold", "hotkey", "", "holdKeys", ["Shift"], "holdDuration", 1000)
holdGroup := SkillGroup("test_hold_deep", holdConfig)
holdGroup.active := true
holdResult := holdGroup.Execute()
TestReporter.Assert(holdResult is Integer || holdResult is Float, "HoldExecutor 返回数值")

TestReporter.Scenario("执行模式: 未激活组不执行")
inactiveConfig := Map("mode", "periodic", "hotkey", "", "keys", ["a"], "intervals", [50])
inactiveGroup := SkillGroup("test_inactive_deep", inactiveConfig)
inactiveGroup.active := false
inactiveResult := inactiveGroup.Execute()
TestReporter.AssertEqual(inactiveResult, 0, "未激活组返回0")

; ============================================================
; 维度2: 异常场景与边界条件
; ============================================================

TestReporter.Scenario("异常: JSONParser空字符串返回空Map")
emptyResult := JSONParser.Parse("")
TestReporter.Assert(emptyResult is Map, "空字符串返回Map")
TestReporter.AssertEqual(emptyResult.Count, 0, "空Map无键")

TestReporter.Scenario("异常: JSONParser畸形JSON抛出异常")
malformedCaught := false
try {
    JSONParser.Parse("{invalid json!!!")
} catch {
    malformedCaught := true
}
TestReporter.Assert(malformedCaught, "畸形JSON抛出异常被捕获")

TestReporter.Scenario("异常: JSONSerializer序列化数字")
nonObjResult := JSONSerializer.Stringify(42)
TestReporter.Assert(nonObjResult is String, "序列化数字不崩溃")

TestReporter.Scenario("异常: ConfigValidator空配置")
emptyValidate := ConfigValidator.Validate(Map())
TestReporter.Assert(emptyValidate is Map || emptyValidate is Object || emptyValidate is Array, "空配置验证不崩溃")

TestReporter.Scenario("异常: SkillManager删除不存在的分组")
delNoExist := SkillManager.DeleteGroup("nonexistent_del_99999")
TestReporter.Assert(delNoExist = false || delNoExist = 0, "删除不存在的分组返回false/0")

TestReporter.Scenario("异常: ModeRegistry未注册模式")
hasFake := ModeRegistry.HasMode("fake_mode_xyz")
TestReporter.AssertEqual(hasFake, false, "未注册模式返回false")

TestReporter.Scenario("异常: ModeRegistry.GetExecutor未注册模式返回空")
fakeExec := ModeRegistry.GetExecutor("fake_mode_xyz")
TestReporter.AssertEqual(fakeExec, "", "未注册模式返回空字符串")

TestReporter.Scenario("异常: JSONSerializer序列化Map")
mapData := Map("key1", "value1", "key2", 42)
mapResult := JSONSerializer.Stringify(mapData)
TestReporter.Assert(mapResult is String, "序列化Map不崩溃")

; ============================================================
; 维度3: 时序与状态一致性（避免注册热键）
; ============================================================

TestReporter.Scenario("时序: 多分组独立状态")
mg1Config := Map("mode", "periodic", "hotkey", "", "keys", ["a"], "intervals", [50])
mg2Config := Map("mode", "sequence", "hotkey", "", "keys", ["1", "2"], "delays", [100, 100])
mg1 := SkillGroup("mg1_deep", mg1Config)
mg2 := SkillGroup("mg2_deep", mg2Config)
mg1.active := true
mg2.active := true
mg1.Execute()
mg2.Execute()
TestReporter.Assert(mg1.active = true && mg2.active = true, "多分组独立激活状态")

TestReporter.Scenario("时序: Emergency紧急停止")
emConfig := Map("mode", "periodic", "hotkey", "", "keys", ["a"], "intervals", [50])
SkillManager.AddGroup("em_test_deep", emConfig)
SkillManager.ToggleGroup("em_test_deep")
SkillManager.Emergency()
TestReporter.AssertEqual(SkillManager.EmergencyMode, true, "紧急模式已激活")
SkillManager.ResetEmergency()
TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "紧急模式已重置")
SkillManager.DeleteGroup("em_test_deep")

TestReporter.Scenario("时序: SkillGroup执行计数")
cntConfig := Map("mode", "periodic", "hotkey", "", "keys", ["a"], "intervals", [50])
cntGroup := SkillGroup("cnt_test_deep", cntConfig)
cntGroup.active := true
cntGroup.Execute()
cntGroup.Execute()
cntGroup.Execute()
TestReporter.AssertEqual(cntGroup._executionCount, 3, "执行3次后计数为3")

TestReporter.Scenario("时序: ModeRegistry全模式注册验证")
allModes := ModeRegistry.GetRegisteredModes()
TestReporter.Assert(allModes.Length >= 7, "至少7种模式已注册")

; ============================================================
; 维度4: 配置持久化与恢复
; ============================================================

TestReporter.Scenario("配置: JSONSerializer序列化配置")
cfgMap := Map("hotkey", "F1", "mode", "periodic", "keys", ["a", "b"], "intervals", [50, 100])
cfgJson := JSONSerializer.Stringify(cfgMap)
TestReporter.Assert(cfgJson is String && StrLen(cfgJson) > 10, "配置序列化成功")

TestReporter.Scenario("配置: JSONParser反序列化配置")
parsedCfg := JSONParser.Parse(cfgJson)
TestReporter.Assert(parsedCfg is Map, "配置反序列化为Map")
TestReporter.AssertEqual(parsedCfg["hotkey"], "F1", "反序列化hotkey正确")

TestReporter.Scenario("配置: ConfigValidator验证合法配置")
validCfg := Map("mode", "periodic", "hotkey", "F1", "keys", ["a"], "intervals", [50])
validResult := ConfigValidator.Validate(validCfg)
TestReporter.Assert(validResult is Map || validResult is Object || validResult is Array, "合法配置验证不崩溃")

TestReporter.Scenario("配置: BackupCore创建备份")
try {
    backupCfgData := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [50])
    backupResult := BackupCore.CreateBackup(backupCfgData, "deep_test")
    TestReporter.Assert(backupResult is Map && backupResult.Has("success"), "备份返回结果Map")
} catch as e {
    TestReporter.Assert(false, "备份异常: " e.Message)
}

; ============================================================
; 维度5: Bridge逻辑模拟
; ============================================================

TestReporter.Scenario("Bridge模拟: JSONParser解析Bridge输入")
bridgeInput := '{"id":"bridge_sim","mode":"periodic","hotkey":"F9","keys":["a"],"intervals":[50]}'
bridgeParsed := JSONParser.Parse(bridgeInput)
TestReporter.Assert(bridgeParsed is Map, "Bridge JSON解析为Map")
TestReporter.AssertEqual(bridgeParsed["mode"], "periodic", "Bridge mode正确")

TestReporter.Scenario("Bridge模拟: GroupService创建分组ID")
bridgeGroupId := GroupService._GenerateGroupId()
TestReporter.Assert(bridgeGroupId is String && StrLen(bridgeGroupId) > 0, "生成分组ID")

TestReporter.Scenario("Bridge模拟: ConfigStore.HasGroup不存在的组")
hasBridgeGroup := ConfigService.ConfigStore.HasGroup("nonexistent_bridge_99999")
TestReporter.AssertEqual(hasBridgeGroup, false, "不存在的分组返回false")

TestReporter.Scenario("Bridge模拟: 序列化分组配置")
bridgeGroupCfg := Map("mode", "periodic", "hotkey", "F9", "keys", ["a"], "intervals", [50])
bridgeGroupCfg["id"] := "bridge_sim"
bridgeJson := JSONSerializer.Stringify(bridgeGroupCfg)
TestReporter.Assert(bridgeJson is String && InStr(bridgeJson, "bridge_sim") > 0, "分组配置序列化包含ID")

summary := TestReporter.Summarize()
TestReporter.ExportReport()

ExitApp(summary.failed > 0 ? 1 : 0)
