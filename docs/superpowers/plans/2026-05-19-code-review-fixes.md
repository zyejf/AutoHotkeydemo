# 代码审查修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代码审查发现的 8 个问题（1 严重 + 3 中等 + 4 轻微）

**Architecture:** 增强现有验证架构，使 requiresNonEmpty 元数据被 ValidateModeConfig 消费；修复 SkillManager 生命周期管理缺陷；优化 ConfigStore 修复粒度

**Tech Stack:** AutoHotkey v2, TDD

---

### Task 1: 增强 ValidateModeConfig 消费 requiresNonEmpty（严重）

**Files:**
- Modify: `domain/mode_registry.ahk:115-146`
- Test: `tests/test_domain_full.ahk`

- [ ] **Step 1: 写失败测试**

在 `tests/test_domain_full.ahk` 的 ModeRegistry 测试区域添加：

```autohotkey
TestReporter.Scenario("2.7 ModeRegistry ValidateModeConfig requiresNonEmpty")
emptyConfig := Map("pressKeys", [], "intervals", [50])
errorsNE := ModeRegistry.ValidateModeConfig("enhanced_periodic", emptyConfig)
TestReporter.Assert(errorsNE.Length > 0, "ValidateModeConfig should report empty pressKeys via requiresNonEmpty")

validConfig := Map("pressKeys", ["a"], "intervals", [50])
errorsOK := ModeRegistry.ValidateModeConfig("enhanced_periodic", validConfig)
TestReporter.AssertEqual(errorsOK.Length, 0, "ValidateModeConfig should pass for non-empty pressKeys")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_domain_full.ahk" 2>&1`
Expected: 新测试项 FAIL（requiresNonEmpty 未被消费，空数组不报错）

- [ ] **Step 3: 实现 ValidateModeConfig 增强**

修改 `domain/mode_registry.ahk` 的 `ValidateModeConfig` 方法，在 `for field in requires` 循环后添加 requiresNonEmpty 检查：

```autohotkey
    static ValidateModeConfig(modeName, config) {
        try {
            if !this._modeMeta.Has(modeName)
                return []

            meta := this._modeMeta[modeName]
            if !meta || !(meta is Map) || !meta.Has("requires")
                return []

            errors := []
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

- [ ] **Step 4: 运行测试确认通过**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_domain_full.ahk" 2>&1`
Expected: PASS

---

### Task 2: OnExit 清理 _executionIds（中等）

**Files:**
- Modify: `domain/skill_manager.ahk:463-482`

- [ ] **Step 1: 写失败测试**

在 `tests/test_bug_reproduction.ahk` 末尾添加：

```autohotkey
TestReporter.Scenario("CR-2: OnExit should clear _executionIds")
SkillManager._executionIds := Map()
SkillManager._executionIds["test_cr2"] := "exec_123"
SkillManager.OnExit()
cleared := !SkillManager._executionIds.Has("test_cr2")
TestReporter.Assert(cleared, "CR-2: OnExit should clear _executionIds")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: 新测试项 FAIL

- [ ] **Step 3: 实现 OnExit 清理**

修改 `domain/skill_manager.ahk` 的 `OnExit` 方法，在 `group._ReleaseAllKeys()` 循环后添加：

```autohotkey
    static OnExit(*) {
        try {
            for id, group in SkillManager.Groups
                group._ReleaseAllKeys()

            if this.HasProp("_executionIds")
                this._executionIds.Clear()

            if SkillManager.OnExitCallback {
                try
                    SkillManager.OnExitCallback()
                catch {
                }
            }

            SkillManager._Notify("系统已关闭", "info")
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: PASS

---

### Task 3: 统一 _executionIds 初始化（中等）

**Files:**
- Modify: `domain/skill_manager.ahk:66` (添加静态声明)
- Modify: `domain/skill_manager.ahk:225` (移除懒初始化)

- [ ] **Step 1: 写失败测试**

在 `tests/test_bug_reproduction.ahk` 添加：

```autohotkey
TestReporter.Scenario("CR-3: _executionIds should be initialized as Map")
hasProp := SkillManager.HasProp("_executionIds")
TestReporter.Assert(hasProp, "CR-3: _executionIds should exist as static prop")
isMap := SkillManager._executionIds is Map
TestReporter.Assert(isMap, "CR-3: _executionIds should be a Map")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: 可能 PASS（因为 _StartGroupExecution 可能已被调用过），但逻辑上应确认静态声明

- [ ] **Step 3: 实现统一初始化**

修改1: 在 `domain/skill_manager.ahk` 第66行附近（`static _timers := Map()` 后面）添加：

```autohotkey
    static _executionIds := Map()
```

修改2: 将第225行的懒初始化：

```autohotkey
        this._executionIds := this.HasProp("_executionIds") ? this._executionIds : Map()
```

改为：

```autohotkey
        this._executionIds[id] := executionId
```

同时修改 `_StopGroupExecution` 中的第261行：

```autohotkey
        if this.HasProp("_executionIds") && this._executionIds.Has(id)
```

改为：

```autohotkey
        if this._executionIds.Has(id)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: PASS

---

### Task 4: ConfigStore _RepairEmptyArrays 逐子组修复（轻微）

**Files:**
- Modify: `infrastructure/config_store.ahk:230-244`

- [ ] **Step 1: 写失败测试**

在 `tests/test_bug_reproduction.ahk` 添加：

```autohotkey
TestReporter.Scenario("CR-4: _RepairEmptyArrays should repair per sub-group not whole groups")
partialConfig := Map(
    "5", Map(
        "hotkey", "F5",
        "mode", "enhanced_hybrid",
        "groups", [
            Map("type", "periodic", "pressKeys", [], "intervals", [100]),
            Map("type", "sequence", "pressKeys", ["custom1", "custom2"], "delays", [50, 50], "seqInterval", 100)
        ],
        "holdKeys", ["Shift"],
        "holdMode", "continuous"
    )
)
ConfigStore._RepairEmptyArrays(partialConfig)
seqKeys := partialConfig["5"]["groups"][2]["pressKeys"]
TestReporter.AssertEqual(seqKeys[1], "custom1", "CR-4: Non-empty sub-group pressKeys should be preserved")
TestReporter.AssertEqual(seqKeys[2], "custom2", "CR-4: Non-empty sub-group pressKeys should be preserved")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: FAIL（当前整组替换会覆盖 custom1/custom2）

- [ ] **Step 3: 实现逐子组修复**

修改 `infrastructure/config_store.ahk` 中 `_RepairEmptyArrays` 的 hybrid/enhanced_hybrid 分支：

将：
```autohotkey
                case "enhanced_hybrid", "hybrid":
                    if config.Has("groups") && config["groups"] is Array {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("groups") && defaults["groups"] is Array {
                            needsRepair := false
                            for i, grp in config["groups"] {
                                if grp is Map && grp.Has("pressKeys") && grp["pressKeys"] is Array && grp["pressKeys"].Length = 0
                                    needsRepair := true
                                if grp is Map && grp.Has("keys") && grp["keys"] is Array && grp["keys"].Length = 0
                                    needsRepair := true
                            }
                            if needsRepair
                                config["groups"] := defaults["groups"]
                        }
                    }
```

改为：
```autohotkey
                case "enhanced_hybrid", "hybrid":
                    if config.Has("groups") && config["groups"] is Array {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("groups") && defaults["groups"] is Array {
                            for i, grp in config["groups"] {
                                if !(grp is Map)
                                    continue
                                if grp.Has("pressKeys") && grp["pressKeys"] is Array && grp["pressKeys"].Length = 0 {
                                    if i <= defaults["groups"].Length && defaults["groups"][i] is Map && defaults["groups"][i].Has("pressKeys")
                                        grp["pressKeys"] := defaults["groups"][i]["pressKeys"]
                                }
                                if grp.Has("keys") && grp["keys"] is Array && grp["keys"].Length = 0 {
                                    if i <= defaults["groups"].Length && defaults["groups"][i] is Map && defaults["groups"][i].Has("keys")
                                        grp["keys"] := defaults["groups"][i]["keys"]
                                }
                            }
                        }
                    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: PASS

---

### Task 5: executionId 增大随机范围（轻微）

**Files:**
- Modify: `domain/skill_manager.ahk:224`

- [ ] **Step 1: 修改 executionId 生成**

将：
```autohotkey
        executionId := A_TickCount . "_" . Random(1, 99999)
```

改为：
```autohotkey
        executionId := A_TickCount . "_" . Random(1, 2147483647)
```

- [ ] **Step 2: 运行 BUG 复现测试确认无回归**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: 27 PASS

---

### Task 6: _HasEmptyKeyArrays default 分支记录警告（轻微）

**Files:**
- Modify: `domain/skill_group.ahk:291`

- [ ] **Step 1: 修改 default 分支**

将：
```autohotkey
            default:
                return false
```

改为：
```autohotkey
            default:
                SkillGroup._Log("WARN", "_HasEmptyKeyArrays: unhandled mode=" this.mode)
                return false
```

- [ ] **Step 2: 运行全量测试确认无回归**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_domain_full.ahk" 2>&1`
Expected: PASS

---

### Task 7: 更新 BUG-5.1 测试描述（轻微）

**Files:**
- Modify: `tests/test_bug_reproduction.ahk`

- [ ] **Step 1: 更新测试描述**

将 BUG-5.1 相关测试描述从旧缺陷描述改为修复后预期行为：

- "BUG-5.1: _timers deleted" → "BUG-5.1 FIX: _timers deleted after stop"
- "BUG-5.1: but grpSeq.active still true (closure will still execute)" → "BUG-5.1 FIX: grpSeq.active still true (expected: closure checks executionId)"
- "BUG-5.1: even after _timers deleted, Execute still returns delay>0" → "BUG-5.1 FIX: Execute still returns delay>0 (executionId prevents stale timer)"

- [ ] **Step 2: 运行测试确认通过**

Run: `cd D:\1demo\AutoHotkeydemo\tests; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk" 2>&1`
Expected: PASS

---

### Task 8: 全量回归测试 + 主程序验证

**Files:**
- All test files

- [ ] **Step 1: 运行所有测试套件**

Run:
```
cd D:\1demo\AutoHotkeydemo\tests
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_domain_full.ahk"
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_infra_full.ahk"
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_app_full.ahk"
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_pres_full.ahk"
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_integration_v2.ahk"
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "test_bug_reproduction.ahk"
```
Expected: 全部退出码 0

- [ ] **Step 2: 运行主程序验证**

Run: `cd D:\1demo\AutoHotkeydemo; & "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "main.ahk" 2>&1`
Expected: 程序正常启动，无错误日志

- [ ] **Step 3: 检查日志确认无错误**

Read: `D:\1demo\AutoHotkeydemo\logs\app.log` — 无 ERROR/CRITICAL
Read: `D:\1demo\AutoHotkeydemo\logs\debug.log` — 无异常
