# asd.ahk 技能管理器 v3.0 — 全栈问题修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复8轮全栈审查发现的22个问题（5严重 + 11中等 + 6轻微），按 P0→P1→P2 优先级分阶段实施

**Architecture:** 遵循现有 DDD 四层架构（domain / infrastructure / application / presentation），保持依赖注入模式。修复集中在 `presentation/webview2_manager.ahk`（JS桥接安全）、`domain/skill_manager.ahk`（竞态条件与定时器管理）、`application/group_service.ahk`（回滚安全）三个核心文件。

**Tech Stack:** AutoHotkey v2.0 + WebView2 + JSON + AutoHotUnit 测试框架

**测试运行方式:** `AutoHotkey.exe tests\run_all_tests.ahk`

---

## Phase 1: P0 — 立即修复 (5个严重问题)

---

### Task 1: 修复 `_PushBridgeEvent` 的 JS 注入漏洞

**问题:** 问题5-1 — JSON 序列化后手动转义顺序错误，缺少双引号转义，可能导致 JS 注入

**Files:**
- Modify: `presentation/webview2_manager.ahk:1278-1290`

- [ ] **Step 1: 编写测试用例（验证修复后的安全性）**

在 `tests\run_all_tests.ahk` 末尾添加:

```autohotkey
class PushBridgeEventSafetyTests extends AutoHotUnitSuite {
    Test_QuotesInKeyName_EscapedCorrectly() {
        testJson := '{"type":"keyRecordEvent","data":{"key":"a\"b","event":"down","timestamp":100}}'
        safeJson := StrReplace(testJson, "'", "\'")
        safeJson := StrReplace(safeJson, "\", "\\")
        safeJson := StrReplace(safeJson, "`n", "\n")
        safeJson := StrReplace(safeJson, "`r", "\r")
        this.assert.isTrue(!InStr(safeJson, "\""))
    }

    Test_BackslashBeforeQuote_NotDoubleEscaped() {
        testStr := 'test\"hello'
        safe := StrReplace(testStr, "'", "\'")
        safe := StrReplace(safe, "\", "\\")
        this.assert.isTrue(InStr(safe, "\\") = InStr(safe, "\'"))
    }

    Test_AngleBrackets_NotAnIssue() {
        testJson := '{"type":"keyRecordEvent","data":{"key":"<script>","event":"down"}}'
        safeJson := StrReplace(testJson, "'", "\'")
        safeJson := StrReplace(safeJson, "\", "\\")
        safeJson := StrReplace(safeJson, "`n", "\n")
        safeJson := StrReplace(safeJson, "`r", "\r")
        this.assert.isTrue(!InStr(safeJson, "<script>"))
    }
}
```

- [ ] **Step 2: 运行测试验证当前代码失败**

运行: `AutoHotkey.exe tests\run_all_tests.ahk`
预期: `Test_QuotesInKeyName_EscapedCorrectly` FAIL — 当前转义逻辑无法正确处理含双引号的JSON

- [ ] **Step 3: 实现修复**

修改 `d:\1demo\AutoHotkeydemo\presentation\webview2_manager.ahk` 的 `_PushBridgeEvent` 方法:

```autohotkey
static _PushBridgeEvent(eventType, evt) {
    try {
        if !WebView2Manager.wv
            return
        json := JSONSerializer.Stringify(Map("type", eventType, "data", evt))
        safeJson := StrReplace(json, "\", "\\")
        safeJson := StrReplace(safeJson, "`"", "\`"")
        safeJson := StrReplace(safeJson, "`n", "\n")
        safeJson := StrReplace(safeJson, "`r", "\r")
        safeJson := StrReplace(safeJson, "'", "\'")
        safeJson := StrReplace(safeJson, "</", "<\/")
        WebView2Manager.wv.ExecuteScriptAsync("if(typeof onBridgeEvent==='function')onBridgeEvent('" safeJson "');")
    } catch as e {
        _DebugLog("_PushBridgeEvent error: " e.Message)
    }
}
```

**关键修改:**
1. 转义顺序: `\` → `"` → 换行/回车 → `'` → `</`（反斜杠最先，单引号次之，因为 JavaScript 字符串用单引号包裹，最后转义 `</script>` 标签）
2. 新增 `"` 的转义: `StrReplace(safeJson, "`"", "\`"")`
3. 新增 `</` 的转义防止脚本标签闭合

- [ ] **Step 4: 运行测试验证修复通过**

运行: `AutoHotkey.exe tests\run_all_tests.ahk`
预期: `PushBridgeEventSafetyTests` 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add tests/run_all_tests.ahk presentation/webview2_manager.ahk
git commit -m "fix: 修复 _PushBridgeEvent JS注入漏洞 (P0-5.1)"
```

---

### Task 2: 修复 `_StartGroupExecution` 竞态条件

**问题:** 问题3-1 — `executionId` 可能被并发调用覆盖，导致双重执行

**Files:**
- Modify: `domain/skill_manager.ahk:289-340`

- [ ] **Step 1: 编写测试用例**

```autohotkey
class StartGroupExecutionRaceConditionTests extends AutoHotUnitSuite {
    Test_ExecutionIdIsolation_PreventsDoubleExecution() {
        if !IsSet(SkillManager._executionIds)
            SkillManager._executionIds := Map()
        if !IsSet(SkillManager._timers)
            SkillManager._timers := Map()

        execId1 := "1000_12345"
        execId2 := "1000_67890"
        SkillManager._executionIds["test_race"] := execId1
        SkillManager._executionIds["test_race"] := execId2

        capturedIds := []
        check1(gId, eId) {
            capturedIds.Push(Map("groupId", gId, "execId", eId))
        }
        check2(gId, eId) {
            capturedIds.Push(Map("groupId", gId, "execId", eId))
        }
        check1("test_race", execId1)
        check2("test_race", execId2)

        id1 := SkillManager._executionIds["test_race"] != execId1
        id2 := SkillManager._executionIds["test_race"] = execId2

        this.assert.isTrue(id1, "execId1 should no longer be valid after overwrite")
        this.assert.isTrue(id2, "execId2 should be the current valid execution id")
    }

    Test_ExecutionGuard_RejectsStaleId() {
        if !IsSet(SkillManager._executionIds)
            SkillManager._executionIds := Map()

        SkillManager._executionIds["test_g"] := "current_999"
        staleCheck := SkillManager._executionIds.Has("test_g") && SkillManager._executionIds["test_g"] = "old_111"
        this.assert.isFalse(staleCheck, "Stale executionId should be rejected")
    }
}
```

- [ ] **Step 2: 运行验证失败**

- [ ] **Step 3: 实现修复**

在 `_StartGroupExecution` 开头添加原子性守护:

```autohotkey
static _StartGroupExecution(id) {
    this._StopGroupExecution(id)

    if !this.Groups.Has(id)
        return

    groupId := id
    executionId := A_TickCount . "_" . Random(1, 2147483647)
    this._executionIds[id] := executionId

    executor(gId, execId) {
        try {
            if !SkillManager.Groups.Has(gId)
                return

            currentId := ""
            try {
                if SkillManager._executionIds.Has(gId)
                    currentId := SkillManager._executionIds[gId]
            }

            if currentId != execId {
                return
            }

            if !SkillManager._timers.Has(gId) {
                SkillManager._StopGroupExecution(gId)
                return
            }

            grp := SkillManager.Groups[gId]
            if SkillManager.EmergencyMode || !grp.active {
                SkillManager._StopGroupExecution(gId)
                SkillManager._DispatchEvent("onDeactivate", Map("groupId", gId))
                return
            }

            delay := grp.Execute()
            if delay > 0 {
                try {
                    if !SkillManager._executionIds.Has(gId) || SkillManager._executionIds[gId] != execId
                        return
                }
                nextFunc := executor.Bind(gId, execId)
                SkillManager._timers[gId] := nextFunc
                SetTimer(nextFunc, -delay)
            } else {
                if grp.active
                    grp.active := false
                SkillManager._StopGroupExecution(gId)
                SkillManager._DispatchEvent("onDeactivate", Map("groupId", gId))
            }
        } catch as e {
            ErrorSystem.LogError("定时器回调异常: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            SkillManager._StopGroupExecution(gId)
        }
    }

    initialFunc := executor.Bind(groupId, executionId)
    this._timers[id] := initialFunc
    SetTimer(initialFunc, -10)
}
```

**关键修改:**
1. `executionId` 比较使用本地变量 `currentId` 捕获，避免在两次 `.Has()` 和 `[key]` 访问之间 Map 被修改
2. 在 `SetTimer(nextFunc, -delay)` 前再次检查 executionId

- [ ] **Step 4: 运行测试验证**

- [ ] **Step 5: Commit**

```bash
git add domain/skill_manager.ahk tests/run_all_tests.ahk
git commit -m "fix: 修复 _StartGroupExecution 竞态条件 (P0-3.1)"
```

---

### Task 3: 修复定时器泄漏 — 添加周期性清理器

**问题:** 问题8-1 — 孤儿定时器仅在 `Emergency()` 和 `ToggleAll()` 中清理

**Files:**
- Modify: `domain/skill_manager.ahk:549-560`
- Modify: `main.ahk` (注册定时清理器)

- [ ] **Step 1: 编写测试用例**

```autohotkey
class OrphanTimerCleanupTests extends AutoHotUnitSuite {
    Test_CleanupRemovesStaleTimerEntries() {
        if !IsSet(SkillManager._timers)
            SkillManager._timers := Map()
        if !IsSet(SkillManager._executionIds)
            SkillManager._executionIds := Map()
        if !IsSet(SkillManager.Groups)
            SkillManager.Groups := Map()

        dummyFunc := (*) => true
        SkillManager._timers["orphan_1"] := dummyFunc
        SkillManager._executionIds["orphan_1"] := "stale_1"
        SkillManager._timers["orphan_2"] := dummyFunc

        SkillManager._CleanupOrphanTimers()

        this.assert.isFalse(SkillManager._timers.Has("orphan_1"), "orphan_1 should be cleaned")
        this.assert.isFalse(SkillManager._timers.Has("orphan_2"), "orphan_2 should be cleaned")
        this.assert.isFalse(SkillManager._executionIds.Has("orphan_1"), "stale executionId should also be cleaned")
    }

    Test_CleanupPreservesActiveGroupTimers() {
        if !IsSet(SkillManager._timers)
            SkillManager._timers := Map()
        if !IsSet(SkillManager.Groups)
            SkillManager.Groups := Map()

        activeGroup := SkillGroup("active_test", Map("hotkey", "^F99", "mode", "periodic"))
        activeGroup.active := true
        SkillManager.Groups["active_test"] := activeGroup

        dummyFunc := (*) => true
        SkillManager._timers["active_test"] := dummyFunc

        SkillManager._CleanupOrphanTimers()

        this.assert.isTrue(SkillManager._timers.Has("active_test"), "active group timer should be preserved")
    }
}
```

- [ ] **Step 2: 运行验证失败**（现有 `_CleanupOrphanTimers` 不会自动被调用）

- [ ] **Step 3: 实现修复**

修改 `domain/skill_manager.ahk`，在 `Init()` 方法中注册周期性清理:

```autohotkey
static _cleanupTimer := 0

static Init(groupSettings) {
    for id, _ in this.Groups {
        try {
            this._StopGroupExecution(id)
        }
    }
    this.Groups.Clear()

    for id, config in groupSettings {
        try {
            this.AddGroup(id, config)
        } catch as e {
            this._Log("WARNING", "初始化分组失败 " id ": " e.Message)
        }
    }

    if this._cleanupTimer
        SetTimer(this._cleanupTimer, 0)
    this._cleanupTimer := () => SkillManager._CleanupOrphanTimers()
    SetTimer(this._cleanupTimer, 30000)

    this._BindControlHotkeys()
    this._Log("INFO", "技能管理器初始化完成: " this.Groups.Count " 个分组")
    SkillManager._Notify("技能管理器已启动", "success")
}
```

同时在 `OnExit` 中停止清理定时器:

```autohotkey
static OnExit(*) {
    if SkillManager._cleanupTimer {
        try
            SetTimer(SkillManager._cleanupTimer, 0)
        SkillManager._cleanupTimer := 0
    }
    ; ... 其余代码不变
}
```

- [ ] **Step 4: 运行测试验证**

- [ ] **Step 5: Commit**

```bash
git add domain/skill_manager.ahk tests/run_all_tests.ahk
git commit -m "fix: 添加周期性孤儿定时器清理器 (P0-8.1)"
```

---

### Task 4: 修复 JS 端 `onBridgeEvent` 静默丢弃事件

**问题:** 问题5-2 — JSON parse 失败时无声返回，用户无感知

**Files:**
- Modify: `presentation/app_ui.html:2660-2663`

- [ ] **Step 1: 实现修复**

修改 `d:\1demo\AutoHotkeydemo\presentation\app_ui.html` L2660-L2663:

```javascript
function onBridgeEvent(evt) {
  if (typeof evt === "string") {
    try {
      evt = JSON.parse(evt);
    } catch(ex) {
      console.error("[Bridge] onBridgeEvent JSON parse failed:", ex.message, "raw:", evt.substring(0, 200));
      addDebugLog("error", "bridge_parse_error", "Bridge事件解析失败: " + ex.message);
      return;
    }
  }
  if (!evt || !evt.type) return;
  // ... 其余代码不变
}
```

- [ ] **Step 2: 验证** — 启动脚本，确认调试日志面板中有 "bridge_parse_error" 日志出现时正常显示

- [ ] **Step 3: Commit**

```bash
git add presentation/app_ui.html
git commit -m "fix: onBridgeEvent JSON解析失败时添加错误日志 (P0-5.2)"
```

---

### Task 5: 修复 TTL 到期后分组永久不可用

**问题:** 问题3-2 — 一旦 ttl 到期，`CheckTTL()` 返回 <=0 阻止激活，但无手动重置机制

**Files:**
- Modify: `domain/skill_group.ahk`（需添加 `ResetTTL()` 方法）
- Modify: `domain/skill_manager.ahk`（添加 `ResetGroupTTL()` 入口）

- [ ] **Step 1: 编写测试用例**

```autohotkey
class TTLResetTests extends AutoHotUnitSuite {
    Test_ResetTTL_AllowsReactivation() {
        group := SkillGroup("ttl_test", Map(
            "hotkey", "^F99",
            "mode", "periodic",
            "ttl", 1
        ))
        group._lastToggleTime := A_Now
        Sleep(2000)
        ttl := group.CheckTTL()
        this.assert.isTrue(ttl <= 0, "TTL should be expired")

        group.ResetTTL()
        this.assert.isFalse(group._ttlApplied, "TTL applied flag should be reset")
    }
}
```

- [ ] **Step 2: 运行验证失败** — `ResetTTL` 方法尚不存在

- [ ] **Step 3: 实现修复**

在 `domain/skill_group.ahk` 中添加:

```autohotkey
static ResetTTL() {
    this._ttlApplied := false
    this._lastToggleTime := 0
    _DebugLog("SkillGroup.ResetTTL: TTL reset for " this.id)
}
```

在 `domain/skill_manager.ahk` 中添加公开方法:

```autohotkey
static ResetGroupTTL(id) {
    if this.Groups.Has(id)
        this.Groups[id].ResetTTL()
}
```

在 `OnEvent` 处理中新增 `onResetTTL` 事件路由:
```autohotkey
case "onResetTTL":
    this.ResetGroupTTL(_GetProp(eventData, "groupId", ""))
```

- [ ] **Step 4: 运行测试验证**

- [ ] **Step 5: Commit**

```bash
git add domain/skill_group.ahk domain/skill_manager.ahk tests/run_all_tests.ahk
git commit -m "fix: 添加 ResetTTL 方法允许重置已到期TTL (P0-3.2)"
```

---

## Phase 2: P1 — 尽快修复 (6个中等问题)

---

### Task 6: 修复 `UpdateGroup` 两阶段提交的数据丢失风险

**问题:** 问题7-1 — 先删后建模式在崩溃时会导致配置永久丢失

**Files:**
- Modify: `application/group_service.ahk:116-155`

- [ ] **Step 1: 实现修复**

修改 `application/group_service.ahk` L116-L155，改为"先建后删"模式:

```autohotkey
static UpdateGroup(id, config) {
    try {
        errors := ConfigValidator.ValidateGroupOnly(id, config)
        criticalErrors := []
        for e in errors {
            eType := ""
            if e is Map && e.Has("type")
                eType := e["type"]
            else if HasProp(e, "type")
                eType := e.type
            if eType = "ERROR"
                criticalErrors.Push(e)
        }
        if criticalErrors.Length > 0
            throw Error("配置验证失败: " ConfigValidator.GetErrorMessage(criticalErrors[1]))

        if !GroupService.SkillManager.Groups.Has(id)
            throw Error("分组不存在: " id)

        wasActive := GroupService.SkillManager.Groups[id].active
        oldConfigRef := GroupService.ConfigStore.GetGroupConfig(id)
        oldConfig := deepclone(oldConfigRef)

        if !IsObject(oldConfig) {
            ErrorSystem.LogError("UpdateGroup: 无法获取分组 " id " 的旧配置", "WARNING", A_ThisFunc, A_LineNumber)
        }

        tempId := id . "_update_temp"
        try {
            addResult := GroupService.SkillManager.AddGroup(tempId, config)
            if !addResult
                throw Error("临时分组创建失败: " tempId " (可能是热键冲突)")
        } catch as addErr {
            throw Error("无法验证新配置: " addErr.Message)
        }

        if wasActive {
            GroupService.SkillManager._StopGroupExecution(id)
            GroupService.SkillManager.Groups[id].active := false
        }

        GroupService.SkillManager.DeleteGroup(tempId)
        GroupService.SkillManager.DeleteGroup(id)

        try {
            addResult := GroupService.SkillManager.AddGroup(id, config)
            if !addResult {
                if IsObject(oldConfig) {
                    try {
                        GroupService.SkillManager.AddGroup(id, oldConfig)
                        GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                        if wasActive
                            GroupService.SkillManager.ToggleGroup(id)
                    } catch as rollbackErr {
                        ErrorSystem.LogError("回滚失败! 分组 " id " 可能丢失: " rollbackErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                        GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                    }
                }
                throw Error("添加分组失败: " id)
            }
        } catch as addErr {
            if IsObject(oldConfig) {
                try {
                    GroupService.SkillManager.AddGroup(id, oldConfig)
                    GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                    if wasActive
                        GroupService.SkillManager.ToggleGroup(id)
                } catch as rollbackErr {
                    ErrorSystem.LogError("回滚失败! 分组 " id " 可能丢失: " rollbackErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                    GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                }
            }
            throw addErr
        }

        GroupService.ConfigStore.SetGroupConfig(id, config)
        BackupCore.RecordConfigChange(GroupService.ConfigStore.Load())

        if wasActive
            GroupService.SkillManager.ToggleGroup(id)

        return Map("success", true, "id", id)
    } catch as e {
        ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        throw e
    }
}
```

**关键修改:** 先用临时ID验证新配置的可创建性，确认无误后再删旧、建新，而不是先删旧再建新。

- [ ] **Step 2: 运行现有测试套件验证**

运行: `AutoHotkey.exe tests\run_all_tests.ahk`
预期: `GroupServiceRollbackSafetyTests` 仍然 PASS

- [ ] **Step 3: Commit**

```bash
git add application/group_service.ahk
git commit -m "fix: UpdateGroup改为先验后换模式避免数据丢失 (P1-7.1)"
```

---

### Task 7: 修复热键注册失败静默问题

**问题:** 问题6-1 — 热键注册失败只写日志不通知用户

**Files:**
- Modify: `domain/skill_manager.ahk:260-275`

- [ ] **Step 1: 实现修复**

```autohotkey
} catch as hkErr {
    SkillManager._Log("WARNING", "AddGroup: 热键注册失败 id=" id " hotkey=" hotkeyStr " err=" hkErr.Message)
    SkillManager._Notify("热键注册失败: " hotkeyStr " 可能被其他程序占用", "error")
    this.Groups.Delete(id)
    return false
}
```

- [ ] **Step 2: Commit**

```bash
git add domain/skill_manager.ahk
git commit -m "fix: 热键注册失败时通过Notifier通知用户 (P1-6.1)"
```

---

### Task 8: 修复控制热键可能被分组热键覆盖

**问题:** 问题6-2 — 分组热键注册时 `Hotkey(x, "On")` 覆盖之前绑定的控制热键

**Files:**
- Modify: `domain/skill_manager.ahk` — `AddGroup` 和 `_BindControlHotkeys` 方法

- [ ] **Step 1: 实现修复**

在 `AddGroup` 的热键注册处添加控制热键冲突检查:

```autohotkey
if hotkeyStr != "" {
    ctrlHotkeys := SkillManager.ConfigStore.Has("CONTROL_HOTKEYS") ? SkillManager.ConfigStore.Get("CONTROL_HOTKEYS") : Map()
    if ctrlHotkeys is Map {
        for action, ctrlHk in ctrlHotkeys {
            if ctrlHk = hotkeyStr {
                SkillManager._Notify("警告: 热键 " hotkeyStr " 是控制热键(" action ")，分组热键将覆盖控制热键", "warning")
                break
            }
        }
    }
    try {
        Hotkey(hotkeyStr, ((id) => (*) => this.ToggleGroup(id))(id))
        Hotkey(hotkeyStr, "On")
    } catch as hkErr {
        SkillManager._Log("WARNING", "AddGroup: 热键注册失败 id=" id " hotkey=" hotkeyStr " err=" hkErr.Message)
        SkillManager._Notify("热键注册失败: " hotkeyStr " 可能被其他程序占用", "error")
        this.Groups.Delete(id)
        return false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add domain/skill_manager.ahk
git commit -m "fix: 添加分组时检测控制热键冲突 (P1-6.2)"
```

---

### Task 9: 修复 `_BridgeGetGroupList` O(n²) 排序

**问题:** 问题8-4 — 插入排序在大量分组时效率低

**Files:**
- Modify: `presentation/webview2_manager.ahk` — `_BridgeGetGroupList` 排序部分

- [ ] **Step 1: 实现修复**

将插入排序改为使用 AHK 内置排序:

```autohotkey
if n > 1 {
    sorted := []
    for idx, g in groups {
        orderIdx := HasProp(SkillManager.Groups[g["id"]], "_order") ? SkillManager.Groups[g["id"]]._order : 0
        sorted.Push(Map("order", orderIdx, "group", g))
    }
    GroupService._QuickSort(sorted, 1, sorted.Length)
    groups := []
    for entry in sorted
        groups.Push(entry["group"])
}
```

或在 `utils.ahk` 中添加快速排序工具函数，然后在 `_BridgeGetGroupList` 中使用。

- [ ] **Step 2: 编写排序性能测试**

```autohotkey
class GroupListSortPerformanceTests extends AutoHotUnitSuite {
    Test_LargeListSort_Efficient() {
        groups := []
        Loop 100 {
            groups.Push(Map("id", A_Index, "order", Random(1, 10000)))
        }
        startTime := A_TickCount
        ; 调用新排序函数
        elapsed := A_TickCount - startTime
        this.assert.isTrue(elapsed < 500, "100 groups should sort under 500ms")
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add presentation/webview2_manager.ahk infrastructure/utils.ahk tests/run_all_tests.ahk
git commit -m "perf: 优化分组列表排序为快速排序 (P1-8.4)"
```

---

### Task 10: 修复 `_AutoRefresh` 后台轮询 + 全量重建

**问题:** 问题2-2 + 问题8-2 — 每2秒全量重建列表，GUI不可见时可能仍运行

**Files:**
- Modify: `presentation/gui_manager.ahk:122-133, 262-297`

- [ ] **Step 1: 实现修复**

修改 `_AutoRefresh` 增加职责检查，修改 `_RefreshGroupList` 为增量更新:

```autohotkey
static _RefreshGroupList() {
    LV := GUIManager.controls["GroupLV"]
    currentIds := Map()
    for id in SkillManager.Groups
        currentIds[id] := true

    idsToRemove := []
    for idStr in GUIManager._rowIndex {
        if !currentIds.Has(idStr)
            idsToRemove.Push(idStr)
    }

    for idStr in idsToRemove {
        if GUIManager._rowIndex.Has(idStr) {
            rowIdx := GUIManager._rowIndex[idStr]
            if rowIdx <= LV.GetCount()
                LV.Delete(rowIdx)
            GUIManager._rowIndex.Delete(idStr)
            for idx, row in GUIManager._rowIndex {
                if row > rowIdx
                    GUIManager._rowIndex[idx] := row - 1
            }
        }
    }

    for id, group in SkillManager.Groups {
        idStr := String(id)
        modeDisplay := GUIManager.modeNames.Has(group.mode) ? GUIManager.modeNames[group.mode] : group.mode
        status := group.active ? "运行中" : "停止"

        if GUIManager._rowIndex.Has(idStr) {
            rowIdx := GUIManager._rowIndex[idStr]
            if rowIdx <= LV.GetCount() && LV.GetText(rowIdx, 1) = idStr {
                needUpdate := LV.GetText(rowIdx, 2) != group.hotkey
                    || LV.GetText(rowIdx, 3) != modeDisplay
                    || LV.GetText(rowIdx, 4) != status
                if needUpdate
                    LV.Modify(rowIdx, , idStr, group.hotkey, modeDisplay, status)
            } else {
                LV.Add(, idStr, group.hotkey, modeDisplay, status)
                GUIManager._rowIndex[idStr] := LV.GetCount()
            }
        } else {
            LV.Add(, idStr, group.hotkey, modeDisplay, status)
            GUIManager._rowIndex[idStr] := LV.GetCount()
        }
    }
}
```

- [ ] **Step 2: 运行现有测试验证**

运行: `AutoHotkey.exe tests\run_all_tests.ahk`
预期: `AutoRefreshIncrementalTests` PASS

- [ ] **Step 3: Commit**

```bash
git add presentation/gui_manager.ahk
git commit -m "perf: 优化 GroupList 为增量更新减少UI重建 (P1-2.2+P1-8.2)"
```

---

### Task 11: 修复 `_GetField` 字符串 JSON 重复解析

**问题:** 问题8-3 — 每次调用尝试 JSON parse

**Files:**
- Modify: `presentation/webview2_manager.ahk:324-339`

- [ ] **Step 1: 实现修复**

添加简单的 JSON 格式缓存检查:

```autohotkey
static _GetField(obj, key, defaultVal := "") {
    try {
        if obj is Map {
            return obj.Has(key) ? obj[key] : defaultVal
        }
        if IsObject(obj) && HasProp(obj, key) {
            return obj.%key%
        }
        if IsString(obj) {
            trimmed := LTrim(RTrim(obj))
            firstChar := SubStr(trimmed, 1, 1)
            if (firstChar = "{" || firstChar = "[") {
                try {
                    parsed := JSONParser.Parse(obj)
                    if parsed is Map
                        return parsed.Has(key) ? parsed[key] : defaultVal
                    if IsObject(parsed) && HasProp(parsed, key)
                        return parsed.%key%
                } catch {
                }
            }
        }
        return defaultVal
    } catch {
        return defaultVal
    }
}
```

**关键修改:** 使用 `LTrim` + `SubStr` 替代 `InStr(obj, "{") = 1`，更可靠地检测是否 JSON 开头

- [ ] **Step 2: Commit**

```bash
git add presentation/webview2_manager.ahk
git commit -m "perf: 优化 _GetField 的JSON检测逻辑 (P1-8.3)"
```

---

## Phase 3: P2 — 计划修复 (11个中等/轻微问题)

---

### Task 12: 清理 v1.0 死代码

**问题:** 问题1-2 — `gui.ahk` 和 `ui_manager.ahk` (root) 的死代码

**Files:**
- Move: `gui.ahk` → `archive/gui_v1.ahk`
- Move: `ui_manager.ahk` → `archive/ui_manager_v1.ahk`

- [ ] **Step 1: 创建 archive 目录并移动文件**
- [ ] **Step 2: 运行测试验证无 regressions**
- [ ] **Step 3: Commit**

---

### Task 13: 提取 TrayManager 为独立文件

**问题:** 问题1-4

**Files:**
- Create: `presentation/tray_manager.ahk`（从 gui_manager.ahk 末尾提取 TrayManager 类）
- Modify: `presentation/gui_manager.ahk`（删除 TrayManager 类定义，添加 `#Include "tray_manager.ahk"`）

---

### Task 14: 添加 `GlobalSettingsEditor._Save()` 中 CheckBox 类型转换

**问题:** 问题6-4

修改 `presentation/gui_manager.ahk` 中 `_Save()` 方法:
```autohotkey
if GlobalSettingsEditor.controls.Has("hs_allowOverlap") {
    val := GlobalSettingsEditor.controls["hs_allowOverlap"].Value
    holdSettings["allowOverlap"] := (val = 1 || val = "1" || val = true)
}
```

---

### Task 15: 添加日志写入失败告警

**问题:** 问题7-2

修改 `infrastructure/error_system.ahk` 的 `_WriteLog`:
```autohotkey
try {
    success := FileAppend(jsonLine "`n", this.logFile, "UTF-8")
    if !success
        OutputDebug("ErrorSystem._WriteLog: FileAppend returned false")
} catch as e {
    OutputDebug("ErrorSystem._WriteLog: 写入失败 - " e.Message)
}
```

---

### Task 16: 添加导入 JSON 结构验证

**问题:** 问题2-4

修改 `presentation/group_editor.ahk` 的 `_ImportConfig`:
```autohotkey
static _ImportConfig() {
    filePath := FileSelect(1, "", "导入分组配置", "JSON (*.json)")
    if filePath = ""
        return
    try {
        content := FileRead(filePath, "UTF-8")
        config := JSONParser.Parse(content)
        if !(config is Map) || !config.Has("hotkey") || !config.Has("mode") {
            MsgBox("导入的JSON格式不正确: 缺少必要的 hotkey/mode 字段", "格式错误", "Icon!")
            return
        }
        GroupEditor._PopulateForm(config)
    } catch as e {
        MsgBox("导入失败: " e.Message, "错误", "Icon!")
    }
}
```

---

### Task 17: 修改 `_DispatchEvent` 关键事件传播异常

**问题:** 问题3-4

修改 `domain/skill_manager.ahk`:
```autohotkey
static _DispatchEvent(event, data := "") {
    for hook in this._eventHooks {
        try
            hook.OnEvent(event, data)
        catch as e {
            isCritical := (event = "onConfigChange" || event = "onDeactivate" || event = "onActivate")
            level := isCritical ? "ERROR" : "WARNING"
            ErrorSystem.LogError("EventHook.OnEvent error: " e.Message " event=" event, level, A_ThisFunc, A_LineNumber)
            if isCritical
                try hook.OnEvent(event, Map("retry", true, "original", data))
        }
    }
}
```

---

### Task 18: 移除错误日志中的用户路径

**问题:** 问题7-3

修改 `infrastructure/error_system.ahk` 的 `_BuildErrorRecord`，将绝对路径缩成相对路径:
```autohotkey
if HasProp(Thrown, "File") {
    filePath := Thrown.File
    if InStr(filePath, A_ScriptDir) = 1
        filePath := SubStr(filePath, StrLen(A_ScriptDir) + 2)
    record["file"] := filePath
}
```

---

### Task 19: 增加 `HotReload` 等待超时到1500ms

**问题:** 问题7-4

修改 `application/config_service.ahk` L129:
```autohotkey
if (A_TickCount - waitStart) >= 1500
    break
```

---

### Task 20: 添加 `_CopyGroup` ID 分配的原子性保护

**问题:** 问题6-3

---

### Task 21: `GroupEditor` 间隔输入错误提示

**问题:** 问题2-3

修改 `_CollectSimpleIntervals`:
```autohotkey
if c.Has(prefix "intervalEdit") {
    try
        intervals.Push(Integer(c[prefix "intervalEdit"].Text))
    catch {
        intervals.Push(50)
        SkillManager._Notify("按键 " (row.idx) " 的间隔值无效，已使用默认值 50ms", "warning")
    }
}
```

---

### Task 22: 桥接通信版本协商

**问题:** 问题5-3

在 `_OnWebMessageReceived` 和 JS `callAhk` 中添加版本号:
```autohotkey
; AHK 侧
static BRIDGE_VERSION := "3.0"
; 在收到任何消息时检查版本
if action = "handshake" {
    WebView2Manager._SendResponse(requestId, Map("version", WebView2Manager.BRIDGE_VERSION, "status", "ok"))
    return
}
```

---

## 验证检查清单

- [ ] 所有 P0 修复后运行: `AutoHotkey.exe tests\run_all_tests.ahk` — 全部 PASS
- [ ] 所有 P1 修复后运行: `AutoHotkey.exe tests\run_all_tests.ahk` — 全部 PASS
- [ ] 启动 `AutoHotkey.exe asd.ahk` 验证主界面正常显示
- [ ] 测试热键注册/分组创建/切换/删除完整流程
- [ ] 测试 WebView2 界面 JS 通信完整性
- [ ] 验证紧急停止后所有定时器正确释放

---

**计划完成。** 分3个阶段共22个任务，预计整体修复时间约2-3小时（含测试验证）。