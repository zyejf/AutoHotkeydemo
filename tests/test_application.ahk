; =================================================================
; 测试层 - 应用层 GroupService / ConfigService 完整功能测试
; 版本: 3.0
; 说明: 覆盖分组增删改查与配置格式迁移的全部公开方法
;       验证依赖注入、边界值、异常处理、格式迁移的正确性
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "test_result_reporter.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 依赖注入初始化
; =================================================================
LoadTestDependencies() {
    ConfigStore.InitDefaults()
    JSONLogger.Init()
    DebugLogger.Init()
    SkillGroup.Logger := DebugLogger
    SkillGroup.Notifier := ""
    SkillGroup.ConfigStore := ConfigStore
    SkillGroup.IsKeyAllowed := ((key, groupId) => true)
    SkillGroup.RegisterHoldKey := ((key, groupId) => true)
    SkillGroup.UnregisterHoldKey := ((key, groupId) => "")
    SkillManager.Logger := JSONLogger
    SkillManager.ConfigStore := ConfigStore
    GroupService.ConfigStore := ConfigStore
    GroupService.SkillManager := SkillManager
    ConfigService.ConfigStore := ConfigStore
    ConfigService.SkillManager := SkillManager
}
LoadTestDependencies()

TestReporter.BeginTest("test_application.ahk")

; 注册 setup 钩子：重置依赖状态，确保独立场景间状态隔离
TestReporter.RegisterBeforeEach(() => LoadTestDependencies())

; =================================================================
; 场景A: GroupService.CreateGroup 正常创建分组
; =================================================================
TestReporter.Scenario("场景A: GroupService.CreateGroup 正常创建")
configA := Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50])
resultA := GroupService.CreateGroup("test_1", configA)
TestReporter.AssertEqual(resultA["success"], true, "CreateGroup 返回 success=true")
TestReporter.AssertEqual(ConfigStore.HasGroup("test_1"), true, "ConfigStore 中 test_1 已存在")

; =================================================================
; 场景B: GroupService.CreateGroup 重复ID应抛出异常
; =================================================================
TestReporter.Scenario("场景B: GroupService.CreateGroup 重复ID")
TestReporter.AssertThrows(
    () => GroupService.CreateGroup("test_1", configA),
    "已存在",
    "重复创建 test_1 应抛出'已存在'异常"
)

; =================================================================
; 场景C: GroupService.GetGroup 获取已创建分组
; =================================================================
TestReporter.Scenario("场景C: GroupService.GetGroup 获取分组")
groupC := GroupService.GetGroup("test_1")
TestReporter.AssertEqual(groupC.active, false, "新建分组的 active 属性为 false")

; =================================================================
; 场景D: GroupService.GetAllGroups 获取全部分组
; =================================================================
TestReporter.Scenario("场景D: GroupService.GetAllGroups 获取全部分组")
allGroups := GroupService.GetAllGroups()
TestReporter.AssertEqual(allGroups is Map ? true : false, true, "GetAllGroups 返回值是 Map")
TestReporter.AssertEqual(allGroups.Has("test_1"), true, "返回值包含 test_1")
TestReporter.Assert(allGroups.Count >= 1, "分组总数 Count >= 1")

; =================================================================
; 场景E: GroupService.UpdateGroup 更新分组模式
; =================================================================
TestReporter.Scenario("场景E: GroupService.UpdateGroup 更新分组")
configE := Map("hotkey", "F1", "mode", "sequence", "keys", ["1", "2"], "delays", [100, 100])
resultE := GroupService.UpdateGroup("test_1", configE)
TestReporter.AssertEqual(resultE["success"], true, "UpdateGroup 返回 success=true")

groupAfterE := GroupService.GetGroup("test_1")
TestReporter.AssertEqual(groupAfterE.mode, "sequence", "更新后 mode 已变为 sequence")
TestReporter.AssertEqual(ConfigStore.GetGroupConfig("test_1")["mode"], "sequence",
    "ConfigStore 中 mode 已同步为 sequence")

; =================================================================
; 场景F: GroupService.DeleteGroup 正常删除分组
; =================================================================
TestReporter.Scenario("场景F: GroupService.DeleteGroup 正常删除")
resultF := GroupService.DeleteGroup("test_1")
TestReporter.AssertEqual(resultF["success"], true, "DeleteGroup 返回 success=true")
TestReporter.AssertEqual(ConfigStore.HasGroup("test_1"), false, "ConfigStore 中 test_1 已被移除")

; =================================================================
; 场景G: GroupService.DeleteGroup 删除不存在的分组
; =================================================================
TestReporter.Scenario("场景G: GroupService.DeleteGroup 不存在分组")
TestReporter.AssertThrows(
    () => GroupService.DeleteGroup("nonexistent_group"),
    "不存在",
    "删除不存在分组应抛出'不存在'异常"
)

; =================================================================
; 场景H: ConfigService.MigrateConfig 旧字段迁移
; =================================================================
TestReporter.Scenario("场景H: ConfigService.MigrateConfig 旧格式迁移")
legacyConfig := Map(
    "GroupSettings", Map(
        "1", Map(
            "hotkey", "F1",
            "mode", "periodic",
            "keys", ["Space"],
            "intervals", [50],
            "repeatMode", "loop"
        )
    )
)
migrated := ConfigService.MigrateConfig(legacyConfig)
migratedGroup := migrated["GroupSettings"]["1"]

TestReporter.AssertEqual(migratedGroup.Has("repeatMode"), false,
    "迁移后 repeatMode 字段不再存在")
TestReporter.AssertEqual(migratedGroup.Has("pressKeys"), true,
    "迁移后 keys 已转为 pressKeys")
TestReporter.AssertEqual(migratedGroup["pressKeys"][1], "Space",
    "迁移后 pressKeys 内容正确")

; =================================================================
; 场景I: ConfigService.MigrateConfig 清理 type 字段
; =================================================================
TestReporter.BeforeEach("场景I: ConfigService.MigrateConfig 清理 type 字段")
configWithType := Map(
    "GroupSettings", Map(
        "2", Map(
            "hotkey", "F2",
            "mode", "periodic",
            "keys", ["a"],
            "intervals", [50],
            "type", "special_type"
        )
    )
)
migratedI := ConfigService.MigrateConfig(configWithType)
migratedGroupI := migratedI["GroupSettings"]["2"]

TestReporter.AssertEqual(migratedGroupI.Has("type"), false,
    "迁移后旧字段 type 已被清除")

; =================================================================
; 汇总与报告
; =================================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed > 0 ? 1 : 0)
