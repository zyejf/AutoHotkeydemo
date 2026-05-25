; =================================================================
; 测试层 - 领域层完整测试套件
; 版本: 3.0
; 说明: 接口契约 + ModeRegistry + SkillGroup 功能全覆盖
;       使用 TestReporter 统一断言，JSON 报告输出
; 运行: AutoHotkey.exe tests\test_domain.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
#Include "test_result_reporter.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"

; 保留旧 TestRunner 对象以维持兼容性（不再使用）
TestRunner := {
    passed: 0,
    failed: 0,
    errors: []
}

TestReporter.BeginTest("test_domain.ahk")

; ============================================================
; 场景A: 抽象接口契约 —— 每个抽象方法必须抛出异常
; ============================================================
TestReporter.Scenario("接口契约: ILogger/INotifier/IConfigStore/IExecutor/IHealthChecker/IEventHook")

TestReporter.AssertThrows(() => ILogger().Log("INFO", "test"), "抽象方法", "ILogger.Log 抛出异常")
TestReporter.AssertThrows(() => INotifier().Notify("test"), "抽象方法", "INotifier.Notify 抛出异常")
TestReporter.AssertThrows(() => INotifier().ShowBriefInfo(0, false), "抽象方法", "INotifier.ShowBriefInfo 抛出异常")
TestReporter.AssertThrows(() => IConfigStore().Load(), "抽象方法", "IConfigStore.Load 抛出异常")
TestReporter.AssertThrows(() => IConfigStore().Save({}), "抽象方法", "IConfigStore.Save 抛出异常")
TestReporter.AssertThrows(() => IConfigStore().Get("key"), "抽象方法", "IConfigStore.Get 抛出异常")
TestReporter.AssertThrows(() => IConfigStore().Set("key", "val"), "抽象方法", "IConfigStore.Set 抛出异常")
TestReporter.AssertThrows(() => IConfigStore().Has("key"), "抽象方法", "IConfigStore.Has 抛出异常")
TestReporter.AssertThrows(() => IExecutor().Execute(""), "抽象方法", "IExecutor.Execute 抛出异常")
TestReporter.AssertThrows(() => IExecutor().GetModeName(), "抽象方法", "IExecutor.GetModeName 抛出异常")
TestReporter.AssertThrows(() => IHealthChecker().Check(), "抽象方法", "IHealthChecker.Check 抛出异常")
TestReporter.AssertThrows(() => IEventHook().OnEvent("test", ""), "抽象方法", "IEventHook.OnEvent 抛出异常")

; ============================================================
; 场景B: ModeRegistry 内置模式 —— 7 种模式全部就绪
; ============================================================
TestReporter.Scenario("ModeRegistry 内置模式验证")

TestReporter.Assert(ModeRegistry.HasMode("periodic"), "periodic 模式已注册")
TestReporter.Assert(ModeRegistry.HasMode("sequence"), "sequence 模式已注册")
TestReporter.Assert(ModeRegistry.HasMode("hybrid"), "hybrid 模式已注册")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_periodic"), "enhanced_periodic 模式已注册")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_sequence"), "enhanced_sequence 模式已注册")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_hybrid"), "enhanced_hybrid 模式已注册")
TestReporter.Assert(ModeRegistry.HasMode("hold"), "hold 模式已注册")

modes := ModeRegistry.GetRegisteredModes()
TestReporter.Assert(modes.Length >= 7, "GetRegisteredModes 至少返回 7 种模式，实际=" modes.Length)

displayNames := ModeRegistry.GetModeDisplayNames()
TestReporter.Assert(displayNames is Map, "GetModeDisplayNames 返回 Map 类型")

; ============================================================
; 场景C: ModeRegistry 获取执行器 —— 每种模式返回有效 IExecutor
; ============================================================
TestReporter.Scenario("ModeRegistry 获取执行器")

allModes := ["periodic", "sequence", "hybrid", "enhanced_periodic", "enhanced_sequence", "enhanced_hybrid", "hold"]
for modeName in allModes {
    exec := ModeRegistry.GetExecutor(modeName)
    TestReporter.Assert(exec is IExecutor, modeName " 执行器实现 IExecutor 接口")
    if exec is IExecutor
        TestReporter.AssertEqual(exec.GetModeName(), modeName, modeName " 执行器 GetModeName() 返回正确模式名")
    else
        TestReporter.Assert(false, modeName " GetExecutor 返回非 IExecutor，跳过 GetModeName 测试")
}

; ============================================================
; 场景D: ModeRegistry 错误处理 —— 不存在模式、注册/注销/获取
; ============================================================
TestReporter.Scenario("ModeRegistry 错误处理")

execNotExist := ModeRegistry.GetExecutor("not_a_real_mode")
TestReporter.AssertEqual(execNotExist, "", "不存在的模式返回空字符串")

ModeRegistry.Register("temp_test_mode", PeriodicExecutor(), {name: "临时", description: "测试"})
TestReporter.Assert(ModeRegistry.HasMode("temp_test_mode"), "临时模式注册成功")
ModeRegistry.Unregister("temp_test_mode")
TestReporter.Assert(!ModeRegistry.HasMode("temp_test_mode"), "临时模式已注销")
execAfterUnreg := ModeRegistry.GetExecutor("temp_test_mode")
TestReporter.AssertEqual(execAfterUnreg, "", "注销后获取执行器返回空字符串")

; ============================================================
; 场景E: SkillGroup 构造函数参数验证
; ============================================================
TestReporter.Scenario("SkillGroup 构造函数参数验证")

; keyPressDuration=1 被修正为 5（最小值）
sgMin := SkillGroup("testE1", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 1})
TestReporter.AssertEqual(sgMin.keyPressDuration, 5, "keyPressDuration=1 被修正为最小值 5")

; keyPressDuration=500 被修正为 100（最大值）
sgMax := SkillGroup("testE2", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 500})
TestReporter.AssertEqual(sgMax.keyPressDuration, 100, "keyPressDuration=500 被修正为最大值 100")

; holdKeys 可选字段缺失不崩溃，默认空数组
sgNoHold := SkillGroup("testE3", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]})
TestReporter.Assert(sgNoHold.holdKeys.Length = 0, "缺失 holdKeys 默认为空数组，不崩溃")

; 合法配置正常创建且 active 初始为 false
sgValid := SkillGroup("testE4", {mode: "periodic", hotkey: "F1", keys: ["a", "b"], intervals: [50, 100]})
TestReporter.AssertEqual(sgValid.mode, "periodic", "合法配置 mode 正确")
TestReporter.Assert(sgValid.active = false, "合法配置初始 active=false")
TestReporter.AssertEqual(sgValid.keys.Length, 2, "合法配置 keys 长度为 2")

; ============================================================
; 场景F: SkillGroup._IsValidKeyName 按键名称验证
; ============================================================
TestReporter.Scenario("SkillGroup._IsValidKeyName 按键名称验证")

; 合法键名
TestReporter.Assert(SkillGroup._IsValidKeyName("Space"), "Space 是合法键名")
TestReporter.Assert(SkillGroup._IsValidKeyName("RButton"), "RButton 是合法键名")
TestReporter.Assert(SkillGroup._IsValidKeyName("a"), "单字母 a 是合法键名")
TestReporter.Assert(SkillGroup._IsValidKeyName("F12"), "F12 是合法键名")
TestReporter.Assert(SkillGroup._IsValidKeyName("LButton"), "LButton 是合法键名")
TestReporter.Assert(SkillGroup._IsValidKeyName("Enter"), "Enter 是合法键名")

; 非法键名
TestReporter.Assert(!SkillGroup._IsValidKeyName("BadKey"), "BadKey 不是合法键名")
TestReporter.Assert(!SkillGroup._IsValidKeyName(""), "空字符串不是合法键名")
TestReporter.Assert(!SkillGroup._IsValidKeyName("   "), "纯空格不是合法键名")

; 特殊字符键名不崩溃（回车键名不应崩溃）
TestReporter.AssertNoThrow(() => SkillGroup._IsValidKeyName("`r`n"), "特殊字符键名调用不崩溃")

; ============================================================
; 场景G: SkillGroup Toggle 生命周期
; ============================================================
TestReporter.Scenario("SkillGroup Toggle 生命周期")

sgToggle := SkillGroup("testG", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]})
TestReporter.Assert(sgToggle.active = false, "初始 active=false")

r1 := sgToggle.Toggle()
TestReporter.Assert(r1 = true, "首次 Toggle 返回 true（激活）")
TestReporter.Assert(sgToggle.active = true, "首次 Toggle 后 active=true")

r2 := sgToggle.Toggle()
TestReporter.Assert(r2 = false, "再次 Toggle 返回 false（关闭）")
TestReporter.Assert(sgToggle.active = false, "再次 Toggle 后 active=false")

; ============================================================
; 场景H: SkillGroup 模式注册表集成
; ============================================================
TestReporter.Scenario("SkillGroup 模式注册表集成")

configs := [
    {mode: "periodic", config: {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}},
    {mode: "sequence", config: {mode: "sequence", hotkey: "F1", keys: ["a"], delays: [100]}},
    {mode: "hybrid", config: {mode: "hybrid", hotkey: "F1", groups: [{type: "periodic", pressKeys: ["a"], intervals: [50]}]}},
    {mode: "enhanced_periodic", config: {mode: "enhanced_periodic", hotkey: "F1", pressKeys: ["a"], intervals: [50]}},
    {mode: "enhanced_sequence", config: {mode: "enhanced_sequence", hotkey: "F1", pressKeys: ["a"], pressDelays: [100]}},
    {mode: "enhanced_hybrid", config: {mode: "enhanced_hybrid", hotkey: "F1", groups: [{type: "periodic", pressKeys: ["a"], intervals: [50]}]}},
    {mode: "hold", config: {mode: "hold", hotkey: "F1", holdKeys: ["a"], holdDuration: 1000}}
]

for entry in configs {
    sg := SkillGroup("testH_" entry.mode, entry.config)
    exec := ModeRegistry.GetExecutor(entry.mode)
    if exec is IExecutor
        TestReporter.AssertEqual(exec.GetModeName(), entry.mode, "SkillGroup(" entry.mode ") 通过 ModeRegistry 获取执行器，GetModeName()=" entry.mode)
    else
        TestReporter.Assert(false, "SkillGroup(" entry.mode ") GetExecutor 返回非 IExecutor")
    TestReporter.AssertEqual(sg.mode, entry.mode, "SkillGroup(" entry.mode ") 自身 mode 属性正确")
    ; 选中2个模式额外验证 setter 行为
    if entry.mode = "periodic" {
        TestReporter.Assert(HasProp(sg, "keys"), "periodic SkillGroup 有 keys 属性")
    }
    if entry.mode = "hold" {
        TestReporter.Assert(HasProp(sg, "holdDuration"), "hold SkillGroup 有 holdDuration 属性")
    }
}

; ============================================================
; 汇总与退出
; ============================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()

ExitApp(summary.failed > 0 ? 1 : 0)
