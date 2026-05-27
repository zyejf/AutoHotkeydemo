# 轻微项修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**目标:** 修复100轮全栈审查发现的4个轻微问题(M1空状态引导, M2热重载测试, M3删除OCR文件, M4无障碍属性)

**架构:** 4个独立任务，可并行执行。M3是文件删除操作；M1/M4是前端HTML修改；M2是新增测试文件。

**技术栈:** AutoHotkey v2.0, JavaScript(WebView2), HTML/CSS

**测试方法:** TDD — 每个实现步骤前先写失败测试，验证失败后再写实现代码

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `ocr.ahk` | 删除 | OCR mock封装（未使用） |
| `equipment_recognizer.ahk` | 删除 | 依赖ocr.ahk（未使用） |
| `joystick_tester.ahk` | 删除 | 依赖equipment_recognizer.ahk（未使用） |
| `presentation/app_ui.html` | 修改 | 添加空状态引导、aria-label |
| `tests/test_hotreload.ahk` | 新建 | HotReload完整测试套件 |

---

### Task 1: M3 — 删除OCR相关文件

**文件:**
- 删除: `d:\1demo\AutoHotkeydemo\ocr.ahk`
- 删除: `d:\1demo\AutoHotkeydemo\equipment_recognizer.ahk`
- 删除: `d:\1demo\AutoHotkeydemo\joystick_tester.ahk`

- [ ] **Step 1: 确认文件存在**

```powershell
Test-Path "d:\1demo\AutoHotkeydemo\ocr.ahk"; Test-Path "d:\1demo\AutoHotkeydemo\equipment_recognizer.ahk"; Test-Path "d:\1demo\AutoHotkeydemo\joystick_tester.ahk"
```

**验证:** 三个文件均返回 `True`

- [ ] **Step 2: 删除三个文件**

```powershell
Remove-Item "d:\1demo\AutoHotkeydemo\ocr.ahk", "d:\1demo\AutoHotkeydemo\equipment_recognizer.ahk", "d:\1demo\AutoHotkeydemo\joystick_tester.ahk"
```

- [ ] **Step 3: 验证已删除**

```powershell
Test-Path "d:\1demo\AutoHotkeydemo\ocr.ahk"; Test-Path "d:\1demo\AutoHotkeydemo\equipment_recognizer.ahk"; Test-Path "d:\1demo\AutoHotkeydemo\joystick_tester.ahk"
```

**验证:** 三个文件均返回 `False`

- [ ] **Step 4: 运行测试套件确保无回归**

```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "d:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk"
```

**验证:** 退出码为0，所有测试通过

- [ ] **Step 5: 提交**

```bash
git add .
git commit -m "fix: 删除未使用的OCR模块及相关文件 (M3)"
```

---

### Task 2: M1 — 仪表盘空状态引导

**文件:**
- 修改: `d:\1demo\AutoHotkeydemo\presentation\app_ui.html:1847`

- [ ] **Step 1: 添加空状态HTML**

在 `renderDashboard()` 函数中，`for`循环结束后、`container.innerHTML = html` 之前，插入空状态判断。

**定位**: 搜索 `}` (for循环结束)、`var container = document.getElementById('groupCards');`、`container.innerHTML = html;`

**修改代码** — 在 `}` (第1846行for结束大括号) 之后、`var container = document.getElementById('groupCards');` (第1847行) 之前插入：

```javascript
  if (filtered.length === 0) {
    html = '<div class="empty-state" style="text-align:center;padding:40px;color:var(--text-muted);">📭 暂无分组<br><small>点击"+ 添加新分组"开始</small></div>';
  }
```

**完整修改后** (`app_ui.html` 第1846-1849行):

```javascript
  }
  if (filtered.length === 0) {
    html = '<div class="empty-state" style="text-align:center;padding:40px;color:var(--text-muted);">📭 暂无分组<br><small>点击"+ 添加新分组"开始</small></div>';
  }
  var container = document.getElementById('groupCards');
  container.innerHTML = html;
```

- [ ] **Step 2: 验证 - 用agent-browser截图确认空状态显示**

启动应用后，确保无分组存在，截图验证仪表盘显示"📭 暂无分组"。

```powershell
agent-browser --cdp 9222 snapshot -i
```

**验证:** snapshot中应包含 "暂无分组" 文案

- [ ] **Step 3: 提交**

```bash
git add presentation/app_ui.html
git commit -m "fix: 仪表盘无分组时显示空状态引导 (M1)"
```

---

### Task 3: M4 — 无障碍属性补充

**文件:**
- 修改: `d:\1demo\AutoHotkeydemo\presentation\app_ui.html` (第310-423行按钮区域)

- [ ] **Step 1: 为全局操作按钮添加aria-label (第311-312行)**

**查找：**
```html
<button class="chip" data-action="emergencyStop" aria-label="紧急停止所有分组">🛑 紧急停止</button>
<button class="chip" data-action="toggleAll">🔄 全局开关</button>
<button class="chip" data-action="hotReload">🔁 热重载</button>
```

**替换为：**
```html
<button class="chip" data-action="emergencyStop" aria-label="紧急停止所有分组">🛑 紧急停止</button>
<button class="chip" data-action="toggleAll" aria-label="切换所有分组的启用状态">🔄 全局开关</button>
<button class="chip" data-action="hotReload" aria-label="重新加载配置文件">🔁 热重载</button>
```

- [ ] **Step 2: 为仪表盘操作按钮添加aria-label (第342-354行)**

**查找：**
```html
<button class="btn btn-primary btn-sm" data-action="batchActivate" disabled>▶ 批量启动</button>
<button class="btn btn-ghost btn-sm" data-action="batchDeactivate" disabled>⏹ 批量停止</button>
<button class="btn btn-danger btn-sm" data-action="batchDelete" disabled>🗑 批量删除</button>
...
<button class="btn btn-ghost btn-sm" data-action="exitBatchMode" style="margin-left:auto;">✕ 退出多选</button>
...
<button class="btn btn-primary" data-action="addNewGroup">+ 添加新分组</button>
<button class="btn btn-ghost" data-action="toggleBatchMode">☑ 多选模式</button>
<button class="btn btn-ghost" data-action="exportAllGroups">📤 导出全部</button>
<button class="btn btn-ghost" data-action="importGroups">📥 导入</button>
```

**替换为：**
```html
<button class="btn btn-primary btn-sm" data-action="batchActivate" disabled aria-label="批量启动选中的分组">▶ 批量启动</button>
<button class="btn btn-ghost btn-sm" data-action="batchDeactivate" disabled aria-label="批量停止选中的分组">⏹ 批量停止</button>
<button class="btn btn-danger btn-sm" data-action="batchDelete" disabled aria-label="批量删除选中的分组">🗑 批量删除</button>
...
<button class="btn btn-ghost btn-sm" data-action="exitBatchMode" style="margin-left:auto;" aria-label="退出多选模式">✕ 退出多选</button>
...
<button class="btn btn-primary" data-action="addNewGroup" aria-label="创建新技能分组">+ 添加新分组</button>
<button class="btn btn-ghost" data-action="toggleBatchMode" aria-label="切换到多选模式">☑ 多选模式</button>
<button class="btn btn-ghost" data-action="exportAllGroups" aria-label="导出所有分组配置">📤 导出全部</button>
<button class="btn btn-ghost" data-action="importGroups" aria-label="从文件导入分组配置">📥 导入</button>
```

- [ ] **Step 3: 为编辑器模板按钮添加aria-label (第362-367行)**

**查找：**
```html
<button class="btn btn-ghost btn-sm" data-action="templatePeriodic">🔄 周期按键</button>
<button class="btn btn-ghost btn-sm" data-action="templateSequence">📋 序列按键</button>
<button class="btn btn-ghost btn-sm" data-action="templateHold">✊ 长按保持</button>
<button class="btn btn-ghost btn-sm" data-action="templateEnhancedPeriodic">⚡ 增强周期</button>
<button class="btn btn-ghost btn-sm" data-action="templateEnhancedSequence">🔗 增强序列</button>
```

**替换为：**
```html
<button class="btn btn-ghost btn-sm" data-action="templatePeriodic" aria-label="使用周期按键模板">🔄 周期按键</button>
<button class="btn btn-ghost btn-sm" data-action="templateSequence" aria-label="使用序列按键模板">📋 序列按键</button>
<button class="btn btn-ghost btn-sm" data-action="templateHold" aria-label="使用长按保持模板">✊ 长按保持</button>
<button class="btn btn-ghost btn-sm" data-action="templateEnhancedPeriodic" aria-label="使用增强周期模板">⚡ 增强周期</button>
<button class="btn btn-ghost btn-sm" data-action="templateEnhancedSequence" aria-label="使用增强序列模板">🔗 增强序列</button>
```

- [ ] **Step 4: 为编辑器操作按钮添加aria-label (第420-423行)**

**查找：**
```html
<button class="btn btn-ghost" data-action="undoEditor" title="Ctrl+Z">↩ 撤销</button>
<button class="btn btn-ghost" data-action="redoEditor" title="Ctrl+Y">↪ 重做</button>
<button class="btn btn-ghost" data-action="cancelEditor">取消</button>
<button class="btn btn-primary" data-action="saveConfig">保存分组</button>
```

**替换为：**
```html
<button class="btn btn-ghost" data-action="undoEditor" title="Ctrl+Z" aria-label="撤销编辑操作">↩ 撤销</button>
<button class="btn btn-ghost" data-action="redoEditor" title="Ctrl+Y" aria-label="重做编辑操作">↪ 重做</button>
<button class="btn btn-ghost" data-action="cancelEditor" aria-label="取消编辑返回仪表盘">取消</button>
<button class="btn btn-primary" data-action="saveConfig" aria-label="保存当前分组配置">保存分组</button>
```

- [ ] **Step 5: 验证 - 用agent-browser检查aria-label完整性**

```powershell
agent-browser --cdp 9222 snapshot -i
```

**验证:** snapshot中所有按钮均包含 `aria-label` 属性

- [ ] **Step 6: 提交**

```bash
git add presentation/app_ui.html
git commit -m "fix: 补充所有UI按钮的aria-label无障碍属性 (M4)"
```

---

### Task 4: M2 — 热重载完整测试

**文件:**
- 新建: `d:\1demo\AutoHotkeydemo\tests\test_hotreload.ahk`

- [ ] **Step 1: 编写测试文件（5个场景）**

```autohotkey
; =================================================================
; 测试层 - ConfigService.HotReload 热重载完整测试
; 版本: 1.0
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
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"

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

TestReporter.BeginTest("test_hotreload.ahk")

originalPath := ConfigService.configPath
testPath := "test_hotreload_config.json"
testBackupPath := testPath . ".backup"

; =================================================================
; 场景A: 正常热重载流程
; =================================================================
TestReporter.Scenario("场景A: 正常热重载")

realPath := A_WorkingDir . "\config.json"
if FileExist(realPath)
    FileCopy(realPath, testPath, 1)

ConfigService.configPath := testPath

configA := ConfigService.ConfigStore.Load()
groupCountBeforeA := 0
if configA.Has("GroupSettings")
    groupCountBeforeA := configA.GroupSettings.Count

resultA := ConfigService.HotReload()
TestReporter.AssertTrue(resultA, "HotReload 正常返回 true")

configAfterA := ConfigService.ConfigStore.Load()
groupCountAfterA := 0
if configAfterA.Has("GroupSettings")
    groupCountAfterA := configAfterA.GroupSettings.Count
TestReporter.AssertEqual(groupCountAfterA, groupCountBeforeA,
    "热重载后分组数量一致")

; =================================================================
; 场景B: 配置损坏回滚
; =================================================================
TestReporter.Scenario("场景B: 配置损坏回滚")

invalidJson := "{ invalid json content !@#$"
FileDelete(testPath)
FileAppend(invalidJson, testPath, "UTF-8")

groupIdsBefore := Map()
configB := ConfigService.ConfigStore.Load()
if configB.Has("GroupSettings")
    for id, _ in configB.GroupSettings
        groupIdsBefore[id] := true

resultB := ConfigService.HotReload()
TestReporter.AssertEqual(resultB, false, "损坏配置热重载返回 false")

configBAfter := ConfigService.ConfigStore.Load()
groupIdsAfter := Map()
if configBAfter.Has("GroupSettings")
    for id, _ in configBAfter.GroupSettings
        groupIdsAfter[id] := true
TestReporter.AssertEqual(groupIdsAfter.Count, groupIdsBefore.Count,
    "回滚后分组数量保持不变")

; =================================================================
; 场景C: 空分组配置热重载
; =================================================================
TestReporter.Scenario("场景C: 空分组配置热重载")

emptyConfig := Map("version", "3.0", "lastModified", A_Now, "GroupSettings", Map())
FileDelete(testPath)
emptyJson := JSONSerializer.Serialize(emptyConfig)
FileAppend(emptyJson, testPath, "UTF-8")

resultC := ConfigService.HotReload()
TestReporter.AssertTrue(resultC, "空分组热重载返回 true")

configCAfter := ConfigService.ConfigStore.Load()
groupCountC := 0
if configCAfter.Has("GroupSettings")
    groupCountC := configCAfter.GroupSettings.Count
TestReporter.AssertEqual(groupCountC, 0, "热重载后分组数为0")

; =================================================================
; 场景D: 配置文件不存在
; =================================================================
TestReporter.Scenario("场景D: 配置文件不存在")

nonexistentPath := "test_nonexistent_config.json"
ConfigService.configPath := nonexistentPath
if FileExist(nonexistentPath)
    FileDelete(nonexistentPath)

resultD := ConfigService.HotReload()
TestReporter.AssertEqual(resultD, false, "文件不存在时返回 false")

; =================================================================
; 场景E: 热重载后分组状态恢复
; =================================================================
TestReporter.Scenario("场景E: 热重载后分组状态恢复")

if FileExist(realPath)
    FileCopy(realPath, testPath, 1)

ConfigService.configPath := testPath

configE := ConfigService.ConfigStore.Load()
eGroupIds := Map()
if configE.Has("GroupSettings")
    for id, settings in configE.GroupSettings {
        eGroupIds[id] := settings.Has("active") ? settings.active : false
    }

resultE := ConfigService.HotReload()
TestReporter.AssertTrue(resultE, "热重载成功返回 true")

configEAfter := ConfigService.ConfigStore.Load()
if configEAfter.Has("GroupSettings")
    for id, settings in configEAfter.GroupSettings {
        expectedActive := eGroupIds.Has(id) ? eGroupIds[id] : false
        actualActive := settings.Has("active") ? settings.active : false
        TestReporter.AssertEqual(actualActive, expectedActive,
            "分组 '" id "' active状态与配置一致")
    }

; =================================================================
; 清理
; =================================================================
ConfigService.configPath := originalPath

try FileDelete(testPath)
try FileDelete(testBackupPath)
try FileDelete(nonexistentPath)

; =================================================================
; 汇总与报告
; =================================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed > 0 ? 1 : 0)
```

- [ ] **Step 2: 运行测试验证**

```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "d:\1demo\AutoHotkeydemo\tests\test_hotreload.ahk"
```

**验证:** 退出码为0，5个场景全部PASS

- [ ] **Step 3: 提交**

```bash
git add tests/test_hotreload.ahk
git commit -m "test: 添加HotReload热重载完整测试 (M2)"
```

---

## 执行汇总

| 任务 | 内容 | 验证方式 |
|------|------|---------|
| Task 1 (M3) | 删除3个OCR文件 | 文件不存在 + 测试无回归 |
| Task 2 (M1) | 空状态引导 | agent-browser截图确认 |
| Task 3 (M4) | aria-label补充 | agent-browser snapshot检查 |
| Task 4 (M2) | 热重载测试 | 5场景全部PASS，退出码0 |