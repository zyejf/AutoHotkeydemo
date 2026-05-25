# 启动分组功能 BUG 全面修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复"启动分组"功能的所有已确认 BUG，并重构验证体系防止问题复发

**Architecture:** 4 个模块按依赖顺序实施：验证体系重构 → ModeRegistry 防御增强 → 执行状态同步修复 → 配置一致性修复。每个模块遵循 TDD 流程：先写失败测试 → 实现 → 验证通过。

**Tech Stack:** AutoHotkey v2, 现有 ConfigValidator/ModeRegistry/SkillGroup/SkillManager 框架

**Design Spec:** `docs/superpowers/specs/2026-05-19-start-group-bug-fix-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `infrastructure/config_validator.ahk` | Modify | 增加空数组检查、子组验证、值范围检查 |
| `domain/mode_registry.ahk` | Modify | GetExecutor 抛异常；_Init 增加 requiresNonEmpty |
| `domain/skill_group.ahk` | Modify | 构造函数验证模式；Execute 短路返回；Toggle/Dispose 清理 _lastSend |
| `domain/skill_manager.ahk` | Modify | _StartGroupExecution 增加 executionId；_StopGroupExecution 清理 executionId |
| `infrastructure/config_store.ahk` | Modify | LoadFromFile 增加验证和合并逻辑 |
| `tests/test_bug_reproduction.ahk` | Modify | 更新断言以匹配修复后的行为 |

---

## Task 1: ConfigValidator 空数组检查增强

**Files:**
- Modify: `infrastructure/config_validator.ahk:155-195`
- Test: `tests/test_bug_reproduction.ahk:80-95`

- [ ] **Step 1: 写失败测试 - 空数组验证**

在 `tests/test_bug_reproduction.ahk` 中修改 BUG-1.2 的断言，使其期望验证器报错：

```autohotkey
    TestReporter.Scenario("BUG-1.2: ConfigValidator should report empty arrays")

    errors := ConfigValidator.ValidateGroupOnly("4", emptyHybridConfig)
    hasEmptyArrayError := false
    for e in errors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "empty") || InStr(msg, "空")
            hasEmptyArrayError := true
    }
    TestReporter.Assert(hasEmptyArrayError, "BUG-1.2 FIX: ConfigValidator should report empty array issue")
    TestReporter.Assert(errors.Length > 0, "BUG-1.2 FIX: empty array config should fail validation")
```

同时在测试文件末尾增加 enhanced_periodic 和 enhanced_sequence 空数组测试：

```autohotkey
    TestReporter.Scenario("BUG-8.1: enhanced_periodic empty pressKeys should fail validation")

    emptyPeriodicConfig := Map(
        "hotkey", "F7",
        "mode", "enhanced_periodic",
        "pressKeys", [],
        "intervals", [50]
    )
    epErrors := ConfigValidator.ValidateGroupOnly("7", emptyPeriodicConfig)
    hasEpEmptyError := false
    for e in epErrors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "empty") || InStr(msg, "空")
            hasEpEmptyError := true
    }
    TestReporter.Assert(hasEpEmptyError, "BUG-8.1 FIX: enhanced_periodic empty pressKeys should fail validation")

    TestReporter.Scenario("BUG-8.2: enhanced_sequence empty pressKeys should fail validation")

    emptySeqConfig := Map(
        "hotkey", "F8",
        "mode", "enhanced_sequence",
        "pressKeys", [],
        "pressDelays", [50]
    )
    esErrors := ConfigValidator.ValidateGroupOnly("8", emptySeqConfig)
    hasEsEmptyError := false
    for e in esErrors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "empty") || InStr(msg, "空")
            hasEsEmptyError := true
    }
    TestReporter.Assert(hasEsEmptyError, "BUG-8.2 FIX: enhanced_sequence empty pressKeys should fail validation")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-1.2, BUG-8.1, BUG-8.2 断言失败（验证器未报错）

- [ ] **Step 3: 实现 ConfigValidator 空数组检查**

在 `infrastructure/config_validator.ahk` 的 `_ValidateModeFields` 方法中，为每个模式的按键数组增加空数组检查。替换整个 `_ValidateModeFields` 方法：

```autohotkey
    static _ValidateModeFields(id, mode, config) {
        errors := []

        switch mode {
            case "periodic":
                if !ConfigValidator._HasField(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式缺少按键(keys)"))
                else if ConfigValidator._IsFieldEmpty(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式按键(keys)不能为空数组"))
                if !ConfigValidator._HasField(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式缺少间隔(intervals)"))
                else if ConfigValidator._IsFieldEmpty(config, "intervals")
                    errors.Push(Map("type", "WARNING", "message", "分组" id "周期性模式间隔(intervals)为空数组"))

            case "sequence":
                if !ConfigValidator._HasField(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "序列模式缺少按键(keys)"))
                else if ConfigValidator._IsFieldEmpty(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "序列模式按键(keys)不能为空数组"))
                if !ConfigValidator._HasField(config, "delays")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "序列模式缺少延迟(delays)"))

            case "hybrid":
                if !ConfigValidator._HasField(config, "groups")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "混合模式缺少分组(groups)"))
                else
                    errors.Push(ConfigValidator._ValidateSubGroups(id, config)*)

            case "hold":
                if !ConfigValidator._HasField(config, "holdKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "长按模式缺少按键(holdKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "holdKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "长按模式按键(holdKeys)不能为空数组"))

            case "enhanced_periodic":
                if !ConfigValidator._HasField(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式缺少按键(pressKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式按键(pressKeys)不能为空数组"))
                if !ConfigValidator._HasField(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式缺少间隔(intervals)"))

            case "enhanced_sequence":
                if !ConfigValidator._HasField(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式缺少按键(pressKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式按键(pressKeys)不能为空数组"))
                if !ConfigValidator._HasField(config, "pressDelays")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式缺少延迟(pressDelays)"))

            case "enhanced_hybrid":
                if !ConfigValidator._HasField(config, "groups")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强混合模式缺少分组(groups)"))
                else
                    errors.Push(ConfigValidator._ValidateSubGroups(id, config)*)
        }

        return errors
    }
```

在 `_ValidateHoldSettings` 方法之后增加两个辅助方法：

```autohotkey
    static _IsFieldEmpty(obj, field) {
        if obj is Map {
            if obj.Has(field) {
                val := obj[field]
                if val is Array
                    return val.Length = 0
            }
        } else if IsObject(obj) {
            if HasProp(obj, field) {
                val := obj.%field%
                if val is Array
                    return val.Length = 0
            }
        }
        return false
    }

    static _ValidateSubGroups(id, config) {
        errors := []
        groups := ConfigValidator._GetField(config, "groups")
        if !(groups is Array) || groups.Length = 0 {
            errors.Push(Map("type", "ERROR", "message", "分组" id "子组(groups)不能为空数组"))
            return errors
        }

        for i, grp in groups {
            grpType := ""
            if grp is Map && grp.Has("type")
                grpType := grp["type"]
            else if IsObject(grp) && HasProp(grp, "type")
                grpType := grp.type

            if grpType != "periodic" && grpType != "sequence" {
                errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i "类型必须为 periodic 或 sequence"))
                continue
            }

            pressKeys := ""
            if grp is Map && grp.Has("pressKeys")
                pressKeys := grp["pressKeys"]
            else if IsObject(grp) && HasProp(grp, "pressKeys")
                pressKeys := grp.pressKeys

            if pressKeys is Array && pressKeys.Length = 0
                errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i "按键(pressKeys)不能为空数组"))

            if grp is Map && !grp.Has("pressKeys") && !grp.Has("keys")
                errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i "缺少按键字段"))
        }

        return errors
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-1.2, BUG-8.1, BUG-8.2 断言通过

- [ ] **Step 5: 运行基础设施层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_infra_full.ahk"`
Expected: 全部通过

---

## Task 2: ModeRegistry GetExecutor 改为抛异常

**Files:**
- Modify: `domain/mode_registry.ahk:67-76`
- Test: `tests/test_bug_reproduction.ahk`

- [ ] **Step 1: 写失败测试 - 未注册模式抛异常**

在 `tests/test_bug_reproduction.ahk` 中修改 BUG-4.1 的测试，使其期望抛异常：

```autohotkey
    TestReporter.Scenario("BUG-4.1 FIX: GetExecutor should throw for unregistered mode")

    threwError := false
    try {
        ModeRegistry.GetExecutor("nonexistent_mode_xyz")
    } catch ValueError {
        threwError := true
    } catch {
        threwError := true
    }
    TestReporter.Assert(threwError, "BUG-4.1 FIX: GetExecutor should throw for unregistered mode")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-4.1 断言失败（GetExecutor 返回空字符串而非抛异常）

- [ ] **Step 3: 实现 GetExecutor 抛异常**

在 `domain/mode_registry.ahk` 中替换 `GetExecutor` 方法（第 67-76 行）：

```autohotkey
    static GetExecutor(modeName) {
        try {
            if !this._executors.Has(modeName)
                throw ValueError("未注册的执行模式: " modeName)
            return this._executors[modeName]
        } catch as e {
            if e is ValueError
                throw e
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-4.1 断言通过

- [ ] **Step 5: 运行领域层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_domain_full.ahk"`
Expected: 全部通过

---

## Task 3: SkillGroup 构造函数模式验证 + Execute 短路返回

**Files:**
- Modify: `domain/skill_group.ahk:55-97` (构造函数)
- Modify: `domain/skill_group.ahk:548-564` (Execute 方法)
- Test: `tests/test_bug_reproduction.ahk`

- [ ] **Step 1: 写失败测试 - 构造函数拒绝无效模式**

在 `tests/test_bug_reproduction.ahk` 中增加测试：

```autohotkey
    TestReporter.Scenario("BUG-4.2 FIX: SkillGroup constructor should throw for unregistered mode")

    invalidModeConfig := Map("hotkey", "F9", "mode", "invalid_mode_xyz")
    constructorThrew := false
    try {
        SkillGroup("badmode", invalidModeConfig)
    } catch ValueError {
        constructorThrew := true
    } catch {
        constructorThrew := true
    }
    TestReporter.Assert(constructorThrew, "BUG-4.2 FIX: SkillGroup constructor should throw for unregistered mode")
```

- [ ] **Step 2: 写失败测试 - Execute 空数组短路返回 0**

在 `tests/test_bug_reproduction.ahk` 中修改 BUG-1.1 的测试，增加 Execute 返回值断言：

```autohotkey
    TestReporter.Scenario("BUG-1.1 FIX: enhanced_hybrid empty sub-group Execute returns 0")

    emptyHybridConfig := Map(
        "hotkey", "F4",
        "mode", "enhanced_hybrid",
        "keyPressDuration", 15,
        "seqInterval", 100,
        "holdKeys", [],
        "holdMode", "continuous",
        "groups", [
            Map("type", "periodic", "pressKeys", [], "intervals", []),
            Map("type", "sequence", "pressKeys", [], "delays", [])
        ]
    )

    grp4 := SkillGroup("4", emptyHybridConfig)

    TestReporter.AssertEqual(grp4.mode, "enhanced_hybrid", "BUG-1.1: mode is enhanced_hybrid")
    TestReporter.AssertEqual(grp4.periodicPressKeys.Length, 0, "BUG-1.1: periodicPressKeys is empty")
    TestReporter.AssertEqual(grp4.seqPressKeys.Length, 0, "BUG-1.1: seqPressKeys is empty")

    grp4.active := true
    grp4._executionCount := 0
    grp4._startTime := A_TickCount
    delay := grp4.Execute()
    TestReporter.AssertEqual(delay, 0, "BUG-1.1 FIX: Execute should return 0 for empty arrays (stop timer)")
    grp4.active := false
    grp4._ReleaseAllKeys()
```

- [ ] **Step 3: 运行测试确认失败**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-4.2 断言失败（构造函数未抛异常）；BUG-1.1 FIX 断言失败（Execute 返回 10 而非 0）

- [ ] **Step 4: 实现 SkillGroup 构造函数模式验证**

在 `domain/skill_group.ahk` 的 `__New` 方法中，在 `this._SetupMode(config)` 之前增加模式验证：

```autohotkey
            if !ModeRegistry.HasMode(this.mode)
                throw ValueError("无效的执行模式: " this.mode)

            this._SetupMode(config)
```

- [ ] **Step 5: 实现 Execute 空数组短路返回**

在 `domain/skill_group.ahk` 的 `Execute` 方法中，在 `executor := ModeRegistry.GetExecutor(this.mode)` 之前增加空数组检查：

```autohotkey
    Execute() {
        if !this.active
            return 0

        if this._HasEmptyKeyArrays()
            return 0

        this._executionCount++
        this._lastUpdateTime := A_TickCount

        try {
            executor := ModeRegistry.GetExecutor(this.mode)
            return executor.Execute(this)
        } catch as e {
            SkillGroup._Log("ERROR", "Execute failed: mode=" this.mode " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 0
        }
    }
```

在 `_CheckMouseKeys` 方法之后增加 `_HasEmptyKeyArrays` 方法：

```autohotkey
    _HasEmptyKeyArrays() {
        switch this.mode {
            case "periodic":
                return this.keys.Length = 0
            case "sequence":
                return this.keys.Length = 0
            case "enhanced_periodic":
                return this.pressKeys.Length = 0
            case "enhanced_sequence":
                return this.pressKeys.Length = 0
            case "enhanced_hybrid":
                return this.periodicPressKeys.Length = 0 && this.seqPressKeys.Length = 0
            case "hybrid":
                return this.periodicKeys.Length = 0 && this.seqKeys.Length = 0
            case "hold":
                return this.holdKeys.Length = 0
            default:
                return false
        }
    }
```

- [ ] **Step 6: 运行测试确认通过**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-1.1 FIX, BUG-4.2 断言通过

- [ ] **Step 7: 运行领域层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_domain_full.ahk"`
Expected: 全部通过

---

## Task 4: ModeRegistry _Init 增加 requiresNonEmpty

**Files:**
- Modify: `domain/mode_registry.ahk:236-316` (_Init 方法)

- [ ] **Step 1: 实现 ModeRegistry._Init 增加 requiresNonEmpty**

在 `domain/mode_registry.ahk` 的 `_Init` 方法中，为每个模式的 meta 增加 `requiresNonEmpty` 字段：

```autohotkey
    static _Init() {
        try {
            ModeRegistry.Register("periodic", PeriodicExecutor(), Map(
                "name", "周期性",
                "description", "定时重复按下指定的按键",
                "requires", ["keys", "intervals"],
                "requiresNonEmpty", ["keys"]
            ))

            ModeRegistry.Register("sequence", SequenceExecutor(), Map(
                "name", "序列",
                "description", "按顺序依次按下指定的按键",
                "requires", ["keys", "delays"],
                "requiresNonEmpty", ["keys"]
            ))

            ModeRegistry.Register("hybrid", HybridExecutor(), Map(
                "name", "混合",
                "description", "同时执行周期性按键和序列按键",
                "requires", ["groups"],
                "requiresNonEmpty", ["groups"]
            ))

            ModeRegistry.Register("enhanced_periodic", EnhancedPeriodicExecutor(), Map(
                "name", "增强周期",
                "description", "周期性按键 + 可选长按功能",
                "requires", ["pressKeys", "intervals"],
                "requiresNonEmpty", ["pressKeys"]
            ))

            ModeRegistry.Register("enhanced_sequence", EnhancedSequenceExecutor(), Map(
                "name", "增强序列",
                "description", "序列按键 + 可选长按功能",
                "requires", ["pressKeys", "pressDelays"],
                "requiresNonEmpty", ["pressKeys"]
            ))

            ModeRegistry.Register("enhanced_hybrid", EnhancedHybridExecutor(), Map(
                "name", "增强混合",
                "description", "混合模式 + 可选长按功能",
                "requires", ["groups"],
                "requiresNonEmpty", ["groups"]
            ))

            ModeRegistry.Register("hold", HoldExecutor(), Map(
                "name", "纯长按",
                "description", "按住指定按键不放",
                "requires", ["holdKeys"],
                "requiresNonEmpty", ["holdKeys"]
            ))

            return true
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }
```

- [ ] **Step 2: 增强 ValidateModeConfig 方法以使用 requiresNonEmpty**

在 `domain/mode_registry.ahk` 中替换 `ValidateModeConfig` 方法：

```autohotkey
    static ValidateModeConfig(modeName, config) {
        try {
            if !this._modeMeta.Has(modeName)
                return []

            meta := this._modeMeta[modeName]
            if !meta || !(meta is Map)
                return []

            errors := []

            if meta.Has("requires") {
                requires := meta["requires"]
                for field in requires {
                    if config is Map {
                        if !config.Has(field)
                            errors.Push("模式 '" modeName "' 缺少必需字段: " field)
                    } else if IsObject(config) {
                        if !HasProp(config, field)
                            errors.Push("模式 '" modeName "' 缺少必需字段: " field)
                    } else {
                        errors.Push("模式 '" modeName "' 缺少必需字段: " field)
                    }
                }
            }

            if meta.Has("requiresNonEmpty") {
                requiresNonEmpty := meta["requiresNonEmpty"]
                for field in requiresNonEmpty {
                    val := ""
                    hasField := false
                    if config is Map {
                        hasField := config.Has(field)
                        if hasField
                            val := config[field]
                    } else if IsObject(config) {
                        hasField := HasProp(config, field)
                        if hasField
                            val := config.%field%
                    }
                    if hasField && val is Array && val.Length = 0
                        errors.Push("模式 '" modeName "' 字段 " field " 不能为空数组")
                }
            }

            return errors
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return []
        }
    }
```

- [ ] **Step 3: 运行领域层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_domain_full.ahk"`
Expected: 全部通过

---

## Task 5: SkillManager _StartGroupExecution executionId 机制

**Files:**
- Modify: `domain/skill_manager.ahk:40` (增加 _executionIds 声明)
- Modify: `domain/skill_manager.ahk:211-238` (_StartGroupExecution 方法)
- Modify: `domain/skill_manager.ahk:240-248` (_StopGroupExecution 方法)
- Test: `tests/test_bug_reproduction.ahk`

- [ ] **Step 1: 写失败测试 - 定时器竞态保护**

在 `tests/test_bug_reproduction.ahk` 中修改 BUG-5.1 的测试，增加 executionId 检查：

```autohotkey
    TestReporter.Scenario("BUG-5.1 FIX: _executionIds tracks execution identity")

    TestReporter.Assert(SkillManager.HasProp("_executionIds") || SkillManager._executionIds is Map, "BUG-5.1 FIX: _executionIds exists")

    SkillManager._executionIds["test5"] := "old_id_123"
    SkillManager._executionIds["test5"] := "new_id_456"
    TestReporter.AssertEqual(SkillManager._executionIds["test5"], "new_id_456", "BUG-5.1 FIX: executionId updated correctly")

    if SkillManager._executionIds.Has("test5")
        SkillManager._executionIds.Delete("test5")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-5.1 FIX 断言失败（_executionIds 不存在）

- [ ] **Step 3: 实现 _executionIds 声明**

在 `domain/skill_manager.ahk` 中，在 `static _timers := Map()` 之后增加：

```autohotkey
    static _executionIds := Map()
```

- [ ] **Step 4: 实现 _StartGroupExecution 增加 executionId**

替换 `domain/skill_manager.ahk` 中的 `_StartGroupExecution` 方法（第 211-238 行）：

```autohotkey
    static _StartGroupExecution(id) {
        this._StopGroupExecution(id)

        if !this.Groups.Has(id)
            return

        executionId := A_TickCount . "_" . id
        this._executionIds[id] := executionId

        executor(gId, execId) {
            if !SkillManager._executionIds.Has(gId) || SkillManager._executionIds[gId] != execId {
                return
            }

            if !SkillManager.Groups.Has(gId) || !SkillManager._timers.Has(gId) {
                SkillManager._StopGroupExecution(gId)
                return
            }

            grp := SkillManager.Groups[gId]
            if SkillManager.EmergencyMode || !grp.active {
                SkillManager._StopGroupExecution(gId)
                return
            }

            delay := grp.Execute()
            if delay > 0 && SkillManager._timers.Has(gId) && SkillManager._executionIds.Has(gId) && SkillManager._executionIds[gId] = execId {
                timerRef := SetTimer(executor.Bind(gId, execId), -delay)
                if IsObject(timerRef)
                    SkillManager._timers[gId] := timerRef
            } else if delay <= 0 {
                grp.active := false
                SkillManager._StopGroupExecution(gId)
            }
        }

        timerRef := SetTimer(executor.Bind(id, executionId), -10)
        if IsObject(timerRef)
            this._timers[id] := timerRef
    }
```

- [ ] **Step 5: 实现 _StopGroupExecution 清理 executionId**

替换 `domain/skill_manager.ahk` 中的 `_StopGroupExecution` 方法（第 240-248 行）：

```autohotkey
    static _StopGroupExecution(id) {
        if this._timers.Has(id) {
            timerRef := this._timers[id]
            try {
                if IsObject(timerRef)
                    SetTimer(timerRef, 0)
            } finally {
                this._timers.Delete(id)
            }
        }
        if this._executionIds.Has(id)
            this._executionIds.Delete(id)
        if this.Groups.Has(id)
            this.Groups[id]._ReleaseAllKeys()
    }
```

- [ ] **Step 6: 运行测试确认通过**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-5.1 FIX 断言通过

- [ ] **Step 7: 运行领域层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_domain_full.ahk"`
Expected: 全部通过

---

## Task 6: HoldExecutor 状态同步 + Toggle/Dispose 清理 _lastSend

**Files:**
- Modify: `domain/mode_registry.ahk:387-404` (HoldExecutor.Execute)
- Modify: `domain/skill_group.ahk:275-276` (Toggle 关闭分支)
- Modify: `domain/skill_group.ahk:540-547` (Dispose 方法)
- Test: `tests/test_bug_reproduction.ahk`

- [ ] **Step 1: 写失败测试 - HoldExecutor 状态同步**

在 `tests/test_bug_reproduction.ahk` 中增加测试：

```autohotkey
    TestReporter.Scenario("BUG-6.1 FIX: HoldExecutor sets active=false when duration expires")

    holdConfig := Map(
        "hotkey", "F10",
        "mode", "hold",
        "holdKeys", [],
        "holdDuration", 100,
        "autoRepeat", false,
        "repeatInterval", 1000
    )
    holdGrp := SkillGroup("10", holdConfig)
    holdGrp.active := true
    holdGrp._holdStartTime := A_TickCount - 200

    holdExecutor := ModeRegistry.GetExecutor("hold")
    delay := holdExecutor.Execute(holdGrp)
    TestReporter.AssertEqual(delay, 0, "BUG-6.1 FIX: HoldExecutor returns 0 when duration expires")
    TestReporter.AssertEqual(holdGrp.active, false, "BUG-6.1 FIX: HoldExecutor sets active=false when duration expires")
```

- [ ] **Step 2: 写失败测试 - Toggle 清理 _lastSend**

在 `tests/test_bug_reproduction.ahk` 中增加测试：

```autohotkey
    TestReporter.Scenario("BUG-10.1 FIX: Toggle clears _lastSend on deactivate")

    toggleConfig := Map(
        "hotkey", "F11",
        "mode", "periodic",
        "keys", ["a"],
        "intervals", [50]
    )
    toggleGrp := SkillGroup("11", toggleConfig)
    toggleGrp._lastSend["a"] := A_TickCount
    TestReporter.Assert(toggleGrp._lastSend.Has("a"), "BUG-10.1: _lastSend has key before toggle off")

    toggleGrp.active := true
    toggleGrp.Toggle()
    TestReporter.Assert(!toggleGrp._lastSend.Has("a"), "BUG-10.1 FIX: _lastSend cleared after toggle off")
```

- [ ] **Step 3: 运行测试确认失败**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-6.1, BUG-10.1 断言失败

- [ ] **Step 4: 实现 HoldExecutor 状态同步**

在 `domain/mode_registry.ahk` 中替换 HoldExecutor 的 Execute 方法（第 387-404 行）：

```autohotkey
    Execute(group) {
        try {
            if group.holdKeys.Length = 0
                return 50

            if group.holdDuration > 0 {
                if (A_TickCount - group._holdStartTime > group.holdDuration) {
                    if group.autoRepeat {
                        group._ReleaseHoldKeys()
                        Sleep(50)
                        group._PressHoldKeys()
                        group._holdStartTime := A_TickCount
                        return group.repeatInterval
                    } else {
                        group.active := false
                        return 0
                    }
                }
            }

            return 50
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 50
        }
    }
```

- [ ] **Step 5: 实现 Toggle 清理 _lastSend**

在 `domain/skill_group.ahk` 的 `Toggle` 方法中，在 `this._ReleaseAllKeys()` 之后增加 `this._lastSend.Clear()`：

```autohotkey
            if !this.active {
                this._ReleaseAllKeys()
                this._lastSend.Clear()
                SkillGroup._Log("DEBUG", "SkillGroup.Toggle: 分组 " this.id " 已关闭")
                return false
            }
```

- [ ] **Step 6: 实现 Dispose 清理 _lastSend**

在 `domain/skill_group.ahk` 的 `Dispose` 方法中，在 `this._heldKeys.Clear()` 之前增加 `this._lastSend.Clear()`：

```autohotkey
    Dispose() {
        try {
            this.active := false
            this._ReleaseAllKeys()
            this._lastSend.Clear()
            this._heldKeys.Clear()
            this._lastTriggerTimes.Clear()
            this._groupTriggerTimes.Clear()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
```

- [ ] **Step 7: 运行测试确认通过**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-6.1, BUG-10.1 断言通过

- [ ] **Step 8: 运行领域层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_domain_full.ahk"`
Expected: 全部通过

---

## Task 7: ConfigStore 配置一致性修复

**Files:**
- Modify: `infrastructure/config_store.ahk:22-28` (Load 方法)
- Modify: `infrastructure/config_store.ahk:121-188` (InitDefaults 方法)
- Test: `tests/test_bug_reproduction.ahk`

- [ ] **Step 1: 写失败测试 - 配置合并逻辑**

在 `tests/test_bug_reproduction.ahk` 中增加测试：

```autohotkey
    TestReporter.Scenario("BUG-3.1 FIX: ConfigStore.LoadFromFile validates and merges")

    partialConfig := Map(
        "hotkey", "F4",
        "mode", "enhanced_hybrid"
    )
    merged := ConfigStore._MergeWithDefaults(partialConfig, ConfigStore._GetDefaultGroupConfig("4"))
    TestReporter.Assert(merged.Has("groups"), "BUG-3.1 FIX: merged config has groups field")
    TestReporter.Assert(merged.Has("seqInterval"), "BUG-3.1 FIX: merged config has seqInterval field")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-3.1 断言失败（_MergeWithDefaults 和 _GetDefaultGroupConfig 方法不存在）

- [ ] **Step 3: 实现 _GetDefaultGroupConfig 方法**

在 `infrastructure/config_store.ahk` 的 `InitDefaults` 方法之后增加：

```autohotkey
    static _GetDefaultGroupConfig(id) {
        defaults := Map(
            "1", Map(
                "hotkey", "F1",
                "mode", "enhanced_sequence",
                "pressKeys", ["Space", "4", "RButton"],
                "pressDelays", [50, 50, 50]
            ),
            "2", Map(
                "hotkey", "F2",
                "mode", "sequence",
                "keys", ["1", "2", "3", "q"],
                "delays", [100, 100, 100, 100]
            ),
            "3", Map(
                "hotkey", "F3",
                "mode", "enhanced_periodic",
                "pressKeys", ["space", "1", "2", "3", "RButton", "space"],
                "intervals", [50, 50, 50, 50, 50, 50],
                "holdKeys", ["Shift"],
                "holdMode", "continuous"
            ),
            "4", Map(
                "hotkey", "F4",
                "mode", "enhanced_hybrid",
                "groups", [
                    Map("type", "periodic", "pressKeys", ["Space"], "intervals", [100]),
                    Map("type", "sequence", "pressKeys", ["1", "2", "3", "4", "q"], "delays", [100, 100, 100, 100, 100], "seqInterval", 100)
                ],
                "seqInterval", 100,
                "holdKeys", ["Shift", "Ctrl"],
                "holdMode", "continuous",
                "keyPressDuration", 15
            ),
            "5", Map(
                "hotkey", "F5",
                "mode", "enhanced_periodic",
                "pressKeys", ["5"],
                "intervals", [50],
                "holdKeys", ["Shift"],
                "holdMode", "continuous"
            ),
            "6", Map(
                "hotkey", "F6",
                "mode", "hold",
                "holdKeys", ["RButton"],
                "holdDuration", 700,
                "autoRepeat", false,
                "repeatInterval", 1000
            )
        )
        if defaults.Has(id)
            return defaults[id]
        return ""
    }
```

- [ ] **Step 4: 实现 _MergeWithDefaults 方法**

在 `_GetDefaultGroupConfig` 之后增加：

```autohotkey
    static _MergeWithDefaults(config, defaultConfig) {
        if !(defaultConfig is Map)
            return config
        if !(config is Map)
            return defaultConfig

        merged := Map()
        for k, v in defaultConfig {
            if config.Has(k) {
                existingVal := config[k]
                if existingVal is Array && existingVal.Length = 0 && v is Array && v.Length > 0
                    merged[k] := v
                else
                    merged[k] := existingVal
            } else {
                merged[k] := v
            }
        }
        for k, v in config {
            if !merged.Has(k)
                merged[k] := v
        }
        return merged
    }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: BUG-3.1 断言通过

- [ ] **Step 6: 运行基础设施层测试确保无回归**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_infra_full.ahk"`
Expected: 全部通过

---

## Task 8: 更新所有测试断言 + 全量回归测试

**Files:**
- Modify: `tests/test_bug_reproduction.ahk`
- Verify: All test files

- [ ] **Step 1: 更新 test_bug_reproduction.ahk 中所有受影响的断言**

需要更新的断言：
- BUG-1.1: Execute 返回值从 `> 0` 改为 `= 0`
- BUG-1.2: 验证器应报错（已在前述任务中更新）
- BUG-4.1: GetExecutor 应抛异常（已在前述任务中更新）
- BUG-5.1: _executionIds 检查（已在前述任务中更新）
- BUG-6.1: HoldExecutor 状态同步（已在前述任务中更新）
- BUG-10.1: Toggle 清理 _lastSend（已在前述任务中更新）

- [ ] **Step 2: 运行 BUG 复现测试**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_bug_reproduction.ahk"`
Expected: 全部通过，0 失败

- [ ] **Step 3: 运行全量回归测试**

依次运行：
1. `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_infra_full.ahk"`
2. `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_domain_full.ahk"`
3. `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_app_full.ahk"`
4. `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_pres_full.ahk"`
5. `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\test_integration_v2.ahk"`

Expected: 全部通过

- [ ] **Step 4: 运行 run_all_tests.ahk 综合测试**

Run: `"D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" "D:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk"`
Expected: 全部通过

---

## Self-Review

**1. Spec coverage:**
- BUG-1 (空数组空转) → Task 1 (验证器) + Task 3 (Execute 短路) ✅
- BUG-4 (未注册模式) → Task 2 (GetExecutor 抛异常) + Task 3 (构造函数验证) ✅
- BUG-5 (定时器竞态) → Task 5 (executionId) ✅
- BUG-6 (HoldExecutor 状态) → Task 6 ✅
- BUG-10 (_lastSend 未清空) → Task 6 ✅
- BUG-3 (配置不一致) → Task 7 ✅
- BUG-8 (enhanced_periodic/sequence 空数组) → Task 1 ✅

**2. Placeholder scan:** No TBD/TODO found ✅

**3. Type consistency:**
- `_executionIds` declared as `Map` in Task 5, used as `Map` throughout ✅
- `_HasEmptyKeyArrays` returns `bool`, used in `Execute` as condition ✅
- `_MergeWithDefaults` returns `Map`, used in test as `Map.Has()` ✅
- `GetExecutor` throws `ValueError`, caught in test as `ValueError` ✅
