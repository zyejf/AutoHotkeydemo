# 缺失功能全面实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实施13项缺失功能，覆盖数据层增强、桥接层增强、UI体验增强、高级功能

**Architecture:** 分4批次按依赖顺序实施，数据层优先于桥接层，桥接层优先于UI层

**Tech Stack:** AutoHotkey v2, HTML/CSS/JavaScript (WebView2)

---

## 批次1: 数据层增强（3项）

### Task 1: 增量更新机制 — 后端脏标记与快照对比

**Files:**
- Modify: `presentation/webview2_manager.ahk:1-30` (类属性区)
- Modify: `presentation/webview2_manager.ahk:117-128` (_PushStateUpdate方法)

- [ ] **Step 1: 添加脏标记和快照属性**

在`WebView2Manager`类顶部添加静态属性：

```autohotkey
static _stateSnapshot := ""
static _dirtyGroups := Map()
static _lastPushHash := ""
```

- [ ] **Step 2: 修改_PushStateUpdate添加快照对比**

替换`_PushStateUpdate`方法体：

```autohotkey
static _PushStateUpdate() {
    if !WebView2Manager.visible || !WebView2Manager.wv {
        WebView2Manager._StopAutoUpdate()
        return
    }
    try {
        debugInfo := WebView2Manager._BridgeGetDebugInfo()
        groupList := WebView2Manager._BridgeGetGroupList()
        currentHash := StrLen(debugInfo) + StrLen(groupList)
        if currentHash = WebView2Manager._lastPushHash
            return
        WebView2Manager._lastPushHash := currentHash
        combined := '{"debug":' debugInfo ',"groups":' groupList '}'
        WebView2Manager.wv.ExecuteScriptAsync("if(typeof updateDashboard==='function')updateDashboard(" combined ")")
    } catch as e {
        _DebugLog("_PushStateUpdate error: " e.Message)
    }
}
```

- [ ] **Step 3: 在状态变化时重置哈希**

在`OnEvent`方法的`onActivate`/`onDeactivate`/`onStateChange`/`onConfigChange`分支中，在触发防抖前重置哈希：

```autohotkey
WebView2Manager._lastPushHash := ""
```

- [ ] **Step 4: 验证**

启动应用，观察日志中`_PushStateUpdate`调用频率是否在无变化时降低。

---

### Task 2: 配置导入/导出UI — 前端界面

**Files:**
- Modify: `presentation/app_ui.html` (设置页面)
- Modify: `presentation/webview2_manager.ahk` (Bridge方法)

- [ ] **Step 1: 在设置页面添加导入/导出区域**

在`page-settings`的保存按钮区域前添加：

```html
<div class="section-label" style="margin-top:16px;">配置导入/导出</div>
<div class="card">
  <div style="display:flex;gap:8px;flex-wrap:wrap;">
    <button class="btn btn-primary btn-sm" data-action="exportConfig">📤 导出配置</button>
    <button class="btn btn-ghost btn-sm" data-action="importConfig">📥 导入配置</button>
    <input type="file" id="importFileInput" accept=".json" style="display:none;">
  </div>
  <div style="font-size:10px;color:var(--text-muted);margin-top:6px;">导入前将自动创建备份</div>
</div>
```

- [ ] **Step 2: 添加导入/导出JavaScript函数**

在`showToast`函数后添加：

```javascript
function exportConfig() {
  ahkCall("ExportConfig", "").then(function(result) {
    if (result && result.success) {
      showToast("配置已导出到: " + result.path, "success");
    } else {
      showToast("导出失败", "error");
    }
  });
}

function importConfig() {
  document.getElementById("importFileInput").click();
}

document.addEventListener("DOMContentLoaded", function() {
  var fileInput = document.getElementById("importFileInput");
  if (fileInput) {
    fileInput.addEventListener("change", function(e) {
      var file = e.target.files[0];
      if (!file) return;
      var reader = new FileReader();
      reader.onload = function(ev) {
        try {
          var data = ev.target.result;
          if (!confirmDialog("确认导入", "导入将覆盖当前所有配置，是否继续？", function() {
            ahkCall("ImportConfig", data).then(function(result) {
              if (result && result.success) {
                showToast("配置已导入，共加载 " + result.groupsLoaded + " 个分组", "success");
              } else {
                showToast("导入失败: " + (result.error || "未知错误"), "error");
              }
            });
          })) {}
        } catch(ex) {
          showToast("文件读取失败", "error");
        }
      };
      reader.readAsText(file);
      fileInput.value = "";
    });
  }
});
```

- [ ] **Step 3: 添加后端Bridge方法**

在`webview2_manager.ahk`的Bridge区域添加：

```autohotkey
static _BridgeExportConfig(*) {
    try {
        filePath := A_ScriptDir "\config_export_" A_Now ".json"
        result := GroupService.ExportGroups(filePath)
        return JSONSerializer.Stringify(Map("success", true, "path", filePath))
    } catch as e {
        return JSONSerializer.Stringify(Map("success", false, "error", e.Message))
    }
}

static _BridgeImportConfig(jsonStr) {
    try {
        config := JSONParser.Parse(jsonStr)
        tempPath := A_Temp "\ahk_import_" A_Now ".json"
        FileAppend(jsonStr, tempPath)
        result := GroupService.ImportGroups(tempPath)
        try FileDelete(tempPath)
        return JSONSerializer.Stringify(Map("success", true, "groupsLoaded", GroupService.ConfigStore.GetGroupCount()))
    } catch as e {
        return JSONSerializer.Stringify(Map("success", false, "error", e.Message))
    }
}
```

- [ ] **Step 4: 在Bridge路由中注册**

在`_HandleMessage`的switch中添加：

```autohotkey
case "ExportConfig":
    return WebView2Manager._BridgeExportConfig()
case "ImportConfig":
    return WebView2Manager._BridgeImportConfig(args[1])
```

- [ ] **Step 5: 验证**

在设置页面点击导出按钮，确认文件生成；点击导入按钮，确认文件选择和导入流程正常。

---

### Task 3: 配置版本迁移日志

**Files:**
- Add: `infrastructure/migration_logger.ahk`
- Modify: `application/config_service.ahk:228-287` (MigrateConfig方法)

- [ ] **Step 1: 创建MigrationLogger**

创建`infrastructure/migration_logger.ahk`：

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

class MigrationLogger {
    static _logFile := A_ScriptDir "\logs\migrations.log"
    static _entries := []

    static Log(fromVersion, toVersion, groupId, field, oldValue, newValue) {
        entry := Map(
            "timestamp", ErrorSystem._FormatISO8601(A_Now),
            "fromVersion", fromVersion,
            "toVersion", toVersion,
            "groupId", groupId,
            "field", field,
            "oldValue", oldValue,
            "newValue", newValue
        )
        MigrationLogger._entries.Push(entry)
    }

    static Flush() {
        if MigrationLogger._entries.Length = 0
            return
        try {
            logDir := A_ScriptDir "\logs"
            if !DirExist(logDir)
                DirCreate(logDir)
            lines := []
            for entry in MigrationLogger._entries {
                lines.Push(JSONSerializer.Stringify(entry))
            }
            content := StrJoin("`n", lines*)
            FileAppend(content "`n", MigrationLogger._logFile)
            MigrationLogger._entries := []
        } catch as e {
            OutputDebug("MigrationLogger.Flush failed: " e.Message)
        }
    }

    static GetHistory() {
        try {
            if !FileExist(MigrationLogger._logFile)
                return []
            content := FileRead(MigrationLogger._logFile)
            lines := StrSplit(content, "`n")
            result := []
            for line in lines {
                line := Trim(line)
                if line = ""
                    continue
                try {
                    result.Push(JSONParser.Parse(line))
                } catch {
                    continue
                }
            }
            return result
        } catch {
            return []
        }
    }
}
```

- [ ] **Step 2: 在MigrateConfig中记录迁移日志**

在`ConfigService._MigrateGroup`中，每次字段迁移时调用`MigrationLogger.Log`：

```autohotkey
if legacyKeys && !result.Has("pressKeys") {
    MigrationLogger.Log(oldVersion, "3.0", groupId, "keys->pressKeys", String(legacyKeys), String(legacyKeys))
    result["pressKeys"] := legacyKeys
}
```

在`MigrateConfig`末尾调用`MigrationLogger.Flush()`。

- [ ] **Step 3: 验证**

修改配置版本触发迁移，检查`logs/migrations.log`文件是否正确记录。

---

## 批次2: 桥接层增强（4项）

### Task 4: 分组搜索/过滤

**Files:**
- Modify: `presentation/app_ui.html` (仪表盘区域)

- [ ] **Step 1: 在仪表盘顶部添加搜索框**

在`page-dashboard`的stat-grid后添加：

```html
<div style="margin:12px 0;display:flex;gap:8px;align-items:center;">
  <input class="input" id="groupSearch" placeholder="搜索分组名称、热键、模式..." style="flex:1;max-width:320px;">
  <select class="input" id="groupFilter" style="width:120px;padding:4px 8px;">
    <option value="all">全部</option>
    <option value="active">运行中</option>
    <option value="stopped">已停止</option>
    <option value="periodic">周期性</option>
    <option value="sequence">序列</option>
    <option value="hold">长按</option>
    <option value="enhanced_periodic">增强周期</option>
    <option value="enhanced_sequence">增强序列</option>
  </select>
</div>
```

- [ ] **Step 2: 添加搜索过滤逻辑**

在JavaScript中添加：

```javascript
var _searchTerm = "";
var _filterMode = "all";

function getFilteredGroups() {
  var result = [];
  for (var i = 0; i < sampleGroups.length; i++) {
    var g = sampleGroups[i];
    if (_filterMode === "active" && !g.active) continue;
    if (_filterMode === "stopped" && g.active) continue;
    if (_filterMode !== "all" && _filterMode !== "active" && _filterMode !== "stopped") {
      if (g.mode !== _filterMode) continue;
    }
    if (_searchTerm) {
      var term = _searchTerm.toLowerCase();
      var name = (g.name || g.id || "").toLowerCase();
      var hotkey = (g.hotkey || "").toLowerCase();
      var mode = (g.mode || "").toLowerCase();
      if (name.indexOf(term) < 0 && hotkey.indexOf(term) < 0 && mode.indexOf(term) < 0) continue;
    }
    result.push(g);
  }
  return result;
}
```

- [ ] **Step 3: 修改renderDashboard使用过滤后的数据**

将`renderDashboard`中的`sampleGroups`替换为`getFilteredGroups()`。

- [ ] **Step 4: 绑定搜索和过滤事件**

```javascript
document.addEventListener("DOMContentLoaded", function() {
  var searchInput = document.getElementById("groupSearch");
  var filterSelect = document.getElementById("groupFilter");
  if (searchInput) {
    searchInput.addEventListener("input", function() {
      _searchTerm = this.value;
      renderDashboard();
    });
  }
  if (filterSelect) {
    filterSelect.addEventListener("change", function() {
      _filterMode = this.value;
      renderDashboard();
    });
  }
});
```

- [ ] **Step 5: 验证**

在仪表盘输入搜索词，确认过滤生效；选择模式过滤，确认正确筛选。

---

### Task 5: 批量操作（批量启用/禁用/删除）

**Files:**
- Modify: `presentation/app_ui.html` (仪表盘区域)
- Modify: `presentation/webview2_manager.ahk` (Bridge方法)
- Modify: `domain/skill_manager.ahk` (批量方法)

- [ ] **Step 1: 添加多选模式UI**

在搜索框区域后添加批量操作工具栏：

```html
<div id="batchToolbar" style="display:none;margin:8px 0;display:flex;gap:8px;align-items:center;">
  <label style="font-size:12px;color:var(--text-secondary);display:flex;align-items:center;gap:4px;">
    <input type="checkbox" id="selectAllGroups"> 全选
  </label>
  <button class="btn btn-primary btn-sm" data-action="batchActivate" disabled>▶ 批量启动</button>
  <button class="btn btn-ghost btn-sm" data-action="batchDeactivate" disabled>⏹ 批量停止</button>
  <button class="btn btn-danger btn-sm" data-action="batchDelete" disabled>🗑 批量删除</button>
  <span id="batchCount" style="font-size:11px;color:var(--text-muted);"></span>
</div>
```

- [ ] **Step 2: 在卡片中添加复选框**

修改`renderDashboard`中的卡片HTML，在header中添加：

```javascript
html += '<label class="batch-check" style="display:none;"><input type="checkbox" data-group-id="'+escAttr(g.id)+'"></label>';
```

- [ ] **Step 3: 添加批量操作JavaScript**

```javascript
var _batchMode = false;
var _selectedGroups = new Set();

function toggleBatchMode() {
  _batchMode = !_batchMode;
  _selectedGroups.clear();
  var checks = document.querySelectorAll('.batch-check');
  checks.forEach(function(c) { c.style.display = _batchMode ? 'inline-flex' : 'none'; });
  document.getElementById('batchToolbar').style.display = _batchMode ? 'flex' : 'none';
  updateBatchUI();
}

function updateBatchUI() {
  var count = _selectedGroups.size;
  document.getElementById('batchCount').textContent = count > 0 ? '已选 ' + count + ' 个' : '';
  var btns = ['batchActivate', 'batchDeactivate', 'batchDelete'];
  btns.forEach(function(id) {
    var btn = document.querySelector('[data-action="'+id+'"]');
    if (btn) btn.disabled = count === 0;
  });
}
```

- [ ] **Step 4: 添加后端批量Bridge方法**

```autohotkey
static _BridgeBatchToggle(ids, activate) {
    results := Map("success", 0, "failed", 0)
    idList := ids is Array ? ids : [ids]
    for id in idList {
        try {
            if SkillManager.Groups.Has(id) {
                if activate && !SkillManager.Groups[id].active
                    SkillManager.ToggleGroup(id)
                else if !activate && SkillManager.Groups[id].active
                    SkillManager.ToggleGroup(id)
                results["success"] += 1
            }
        } catch {
            results["failed"] += 1
        }
    }
    return JSONSerializer.Stringify(results)
}

static _BridgeBatchDelete(ids) {
    results := Map("success", 0, "failed", 0)
    idList := ids is Array ? ids : [ids]
    for id in idList {
        try {
            SkillManager.DeleteGroup(id)
            ConfigService.ConfigStore.DeleteGroupConfig(id)
            results["success"] += 1
        } catch {
            results["failed"] += 1
        }
    }
    BackupCore.RecordConfigChange(ConfigService.ConfigStore.Load())
    return JSONSerializer.Stringify(results)
}
```

- [ ] **Step 5: 验证**

选择多个分组，批量启动/停止/删除，确认操作结果正确。

---

### Task 6: 性能监控面板

**Files:**
- Modify: `presentation/app_ui.html` (调试页面)
- Modify: `presentation/webview2_manager.ahk` (_BridgeGetDebugInfo)

- [ ] **Step 1: 扩展_BridgeGetDebugInfo**

在`_BridgeGetDebugInfo`中添加更多指标：

```autohotkey
info["memoryUsage"] := ProcessGetMemoryInfo()
info["keySendRate"] := SkillManager.GetKeySendCount()
info["uptimeSeconds"] := Round((A_TickCount - WebView2Manager._startTick) / 1000)
```

- [ ] **Step 2: 在调试页面添加性能面板**

在`page-debug`的stat-grid后添加：

```html
<div class="section-label" style="margin-top:16px;">性能监控</div>
<div class="card" style="padding:12px;">
  <canvas id="perfChart" style="width:100%;height:120px;"></canvas>
  <div style="display:flex;gap:16px;margin-top:8px;font-size:11px;color:var(--text-secondary);">
    <span>运行时间: <span id="perfUptime">0s</span></span>
    <span>内存: <span id="perfMemory">0MB</span></span>
    <span>按键频率: <span id="perfKeyRate">0/s</span></span>
  </div>
</div>
```

- [ ] **Step 3: 添加性能数据采集和Canvas绘图**

```javascript
var perfData = { timers: [], memory: [], keyRate: [] };
var PERF_MAX_POINTS = 60;

function updatePerfChart(debug) {
  if (!debug) return;
  perfData.timers.push(debug.timers || 0);
  if (perfData.timers.length > PERF_MAX_POINTS) perfData.timers.shift();
  var canvas = document.getElementById("perfChart");
  if (!canvas) return;
  var ctx = canvas.getContext("2d");
  var w = canvas.width = canvas.offsetWidth;
  var h = canvas.height = canvas.offsetHeight;
  ctx.clearRect(0, 0, w, h);
  ctx.strokeStyle = "#7c5cfc";
  ctx.lineWidth = 2;
  ctx.beginPath();
  var maxVal = Math.max.apply(null, perfData.timers) || 1;
  for (var i = 0; i < perfData.timers.length; i++) {
    var x = (i / (PERF_MAX_POINTS - 1)) * w;
    var y = h - (perfData.timers[i] / maxVal) * (h - 10) - 5;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.stroke();
  if (debug.uptimeSeconds !== undefined) document.getElementById("perfUptime").textContent = formatUptime(debug.uptimeSeconds);
}
```

- [ ] **Step 4: 在updateDashboard中调用性能更新**

在`updateDashboard`函数的debug处理末尾添加：

```javascript
updatePerfChart(d);
```

- [ ] **Step 5: 验证**

切换到调试页面，确认性能折线图实时更新。

---

### Task 7: 配置差异比较工具

**Files:**
- Add: `infrastructure/config_differ.ahk`
- Modify: `presentation/app_ui.html` (备份页面)
- Modify: `presentation/webview2_manager.ahk` (Bridge方法)

- [ ] **Step 1: 创建ConfigDiffer**

创建`infrastructure/config_differ.ahk`：

```autohotkey
#Requires AutoHotkey v2.0

class ConfigDiffer {
    static Diff(configA, configB) {
        result := Map("added", [], "removed", [], "modified", [])
        groupsA := configA is Map && configA.Has("GroupSettings") ? configA["GroupSettings"] : Map()
        groupsB := configB is Map && configB.Has("GroupSettings") ? configB["GroupSettings"] : Map()
        if !(groupsA is Map)
            groupsA := Map()
        if !(groupsB is Map)
            groupsB := Map()

        for id in groupsB {
            if !groupsA.Has(id) {
                result["added"].Push(id)
            } else {
                fieldDiffs := ConfigDiffer._DiffGroup(groupsA[id], groupsB[id])
                if fieldDiffs.Length > 0
                    result["modified"].Push(Map("id", id, "fields", fieldDiffs))
            }
        }
        for id in groupsA {
            if !groupsB.Has(id)
                result["removed"].Push(id)
        }
        return result
    }

    static _DiffGroup(groupA, groupB) {
        diffs := []
        a := groupA is Map ? groupA : Map()
        b := groupB is Map ? groupB : Map()
        allKeys := Map()
        for k in a
            allKeys[k] := true
        for k in b
            allKeys[k] := true
        for k in allKeys {
            valA := a.Has(k) ? a[k] : ""
            valB := b.Has(k) ? b[k] : ""
            if valA != valB
                diffs.Push(Map("field", k, "from", valA, "to", valB))
        }
        return diffs
    }
}
```

- [ ] **Step 2: 在备份页面添加对比按钮**

修改备份列表项的渲染，添加"对比"按钮。

- [ ] **Step 3: 添加BridgeDiffConfigs方法**

```autohotkey
static _BridgeDiffConfigs(pathA, pathB) {
    try {
        contentA := FileRead(pathA)
        contentB := FileRead(pathB)
        configA := JSONParser.Parse(contentA)
        configB := JSONParser.Parse(contentB)
        diff := ConfigDiffer.Diff(configA, configB)
        return JSONSerializer.Stringify(diff)
    } catch as e {
        return JSONSerializer.Stringify(Map("error", e.Message))
    }
}
```

- [ ] **Step 4: 验证**

在备份页面选择两个备份进行对比，确认差异正确显示。

---

## 批次3: UI体验增强（4项）

### Task 8: 主题切换（暗色/亮色）

**Files:**
- Modify: `presentation/app_ui.html` (CSS变量和设置页面)

- [ ] **Step 1: 定义亮色主题CSS变量**

在`:root`后添加：

```css
:root.light {
  --bg-primary: #f5f5f7;
  --bg-secondary: #eaeaef;
  --bg-tertiary: #d5d5de;
  --text-primary: #1a1a2e;
  --text-secondary: rgba(26,26,46,0.6);
  --text-muted: rgba(26,26,46,0.35);
  --glass-bg: rgba(0,0,0,0.04);
  --glass-border: rgba(0,0,0,0.08);
  --glass-hover: rgba(0,0,0,0.06);
}
```

- [ ] **Step 2: 在设置页面添加主题切换开关**

在长按设置区域后添加：

```html
<div class="section-label" style="margin-top:16px;">外观</div>
<div class="card">
  <div class="form-row"><span class="form-label">主题</span><div class="form-field">
    <select class="input" id="themeSelect" style="width:120px;padding:4px 8px;">
      <option value="dark">暗色</option>
      <option value="light">亮色</option>
    </select>
  </div></div>
</div>
```

- [ ] **Step 3: 添加主题切换JavaScript**

```javascript
function applyTheme(theme) {
  if (theme === "light") {
    document.documentElement.classList.add("light");
  } else {
    document.documentElement.classList.remove("light");
  }
  try { localStorage.setItem("theme", theme); } catch(e) {}
}

document.addEventListener("DOMContentLoaded", function() {
  var saved = "dark";
  try { saved = localStorage.getItem("theme") || "dark"; } catch(e) {}
  var sel = document.getElementById("themeSelect");
  if (sel) {
    sel.value = saved;
    applyTheme(saved);
    sel.addEventListener("change", function() { applyTheme(this.value); });
  } else {
    applyTheme(saved);
  }
});
```

- [ ] **Step 4: 验证**

切换主题，确认所有元素颜色正确变化，刷新后主题保持。

---

### Task 9: 设置页面热键格式验证

**Files:**
- Modify: `presentation/app_ui.html` (设置页面)

- [ ] **Step 1: 添加热键验证函数**

```javascript
function validateHotkey(value) {
  if (!value || value.trim() === "") return { valid: true };
  var pattern = /^([#!^+]*<[^>]+>|[#!^+]*[a-zA-Z0-9]+|F\d+)$/;
  if (pattern.test(value.trim())) return { valid: true };
  return { valid: false, message: "无效热键格式，示例: F12, ^!a, #c" };
}
```

- [ ] **Step 2: 为热键输入框添加实时验证**

```javascript
document.addEventListener("DOMContentLoaded", function() {
  var hkInputs = ["hkEmergency", "hkToggleAll", "hkShowStatus", "hkToggleHold", "hkReleaseHolds"];
  hkInputs.forEach(function(id) {
    var input = document.getElementById(id);
    if (!input) return;
    input.addEventListener("input", function() {
      var result = validateHotkey(this.value);
      if (!result.valid) {
        this.style.borderColor = "var(--danger)";
        this.title = result.message;
      } else {
        this.style.borderColor = "";
        this.title = "";
      }
    });
  });
});
```

- [ ] **Step 3: 在保存设置时验证所有热键**

在`saveSettings`函数开头添加：

```javascript
var hkInputs = ["hkEmergency", "hkToggleAll", "hkShowStatus", "hkToggleHold", "hkReleaseHolds"];
for (var i = 0; i < hkInputs.length; i++) {
  var input = document.getElementById(hkInputs[i]);
  if (input) {
    var result = validateHotkey(input.value);
    if (!result.valid) {
      showToast(hkInputs[i] + ": " + result.message, "error");
      input.focus();
      return;
    }
  }
}
```

- [ ] **Step 4: 验证**

在设置页面输入无效热键，确认红色边框和错误提示。

---

### Task 10: 键盘快捷键自定义UI

**Files:**
- Modify: `presentation/app_ui.html` (设置页面)

- [ ] **Step 1: 将热键输入框改为可捕获模式**

修改设置页面的热键输入框，添加捕获按钮：

```html
<div class="form-row"><span class="form-label">紧急停止</span><div class="form-field" style="display:flex;gap:4px;">
  <input class="input" id="hkEmergency" value="F12" style="width:120px;" readonly>
  <button class="btn btn-ghost btn-sm" data-action="captureHotkey" data-target="hkEmergency">🎹</button>
</div></div>
```

对其他4个热键输入框做同样修改。

- [ ] **Step 2: 添加热键捕获逻辑**

```javascript
var _capturingTarget = null;

function startCaptureHotkey(targetId) {
  _capturingTarget = targetId;
  var input = document.getElementById(targetId);
  if (input) {
    input.value = "按下热键...";
    input.style.borderColor = "var(--accent)";
    input.focus();
  }
}

document.addEventListener("keydown", function(e) {
  if (!_capturingTarget) return;
  e.preventDefault();
  e.stopPropagation();
  var parts = [];
  if (e.ctrlKey) parts.push("^");
  if (e.altKey) parts.push("!");
  if (e.shiftKey) parts.push("+");
  if (e.metaKey) parts.push("#");
  var key = e.key;
  if (key.length === 1) key = key.toLowerCase();
  else if (key.startsWith("F") && key.length <= 3) key = key;
  else if (key === "Escape") { _capturingTarget = null; return; }
  else key = "";
  if (key) {
    parts.push(key);
    var hotkey = parts.join("");
    var input = document.getElementById(_capturingTarget);
    if (input) {
      input.value = hotkey;
      input.style.borderColor = "";
    }
    _capturingTarget = null;
  }
});
```

- [ ] **Step 3: 验证**

点击捕获按钮，按下组合键，确认输入框正确显示热键。

---

### Task 11: 分组模板/预设

**Files:**
- Modify: `presentation/app_ui.html` (编辑器区域)

- [ ] **Step 1: 定义内置模板**

```javascript
var GROUP_TEMPLATES = [
  { name: "周期性单键", config: { mode: "periodic", pressKeys: ["a"], intervals: [100], keyPressDuration: 15 } },
  { name: "序列连招", config: { mode: "sequence", pressKeys: ["a","s","d"], pressDelays: [100,100], keyPressDuration: 15 } },
  { name: "混合模式", config: { mode: "enhanced_periodic", pressKeys: ["a"], intervals: [50], keyPressDuration: 15, groups: [{ type: "hold", holdKeys: ["Shift"] }] } },
  { name: "纯长按", config: { mode: "hold", holdKeys: ["Shift"], holdDuration: 0, autoRepeat: false, repeatInterval: 1000, keyPressDuration: 15 } }
];
```

- [ ] **Step 2: 在编辑器中添加模板选择**

在分组编辑器的顶部添加模板选择区域：

```html
<div style="margin-bottom:12px;display:flex;gap:6px;flex-wrap:wrap;">
  <span style="font-size:11px;color:var(--text-muted);line-height:28px;">模板:</span>
</div>
```

在JavaScript中动态生成模板按钮。

- [ ] **Step 3: 添加模板应用逻辑**

```javascript
function applyTemplate(template) {
  if (!template || !template.config) return;
  var config = JSON.parse(JSON.stringify(template.config));
  fillEditorFromConfig(config);
  showToast("已应用模板: " + template.name, "success");
}
```

- [ ] **Step 4: 支持保存自定义模板**

```javascript
function saveAsTemplate(name, config) {
  var templates = [];
  try { templates = JSON.parse(localStorage.getItem("customTemplates") || "[]"); } catch(e) {}
  templates.push({ name: name, config: config, custom: true });
  try { localStorage.setItem("customTemplates", JSON.stringify(templates)); } catch(e) {}
  showToast("模板已保存: " + name, "success");
}
```

- [ ] **Step 5: 验证**

新建分组时选择模板，确认配置正确填充；保存自定义模板，确认可复用。

---

## 批次4: 高级功能（2项）

### Task 12: 响应式设计

**Files:**
- Modify: `presentation/app_ui.html` (CSS)

- [ ] **Step 1: 添加响应式CSS媒体查询**

在`</style>`前添加：

```css
@media (max-width: 900px) {
  :root { --nav-width: 56px; }
  .nav-label, .nav-logo-ver, .nav-status span { display: none; }
  .nav-item { justify-content: center; padding: 10px 0; }
  .nav-logo { font-size: 16px; }
  .group-card { min-width: 100%; }
}
@media (max-width: 640px) {
  .main-content { padding: 8px; }
  .stat-grid { grid-template-columns: repeat(2, 1fr) !important; }
  .form-row { flex-direction: column; gap: 4px; }
  .form-label { min-width: unset; }
}
```

- [ ] **Step 2: 添加汉堡菜单切换**

在小屏幕下侧边栏可折叠：

```javascript
function toggleNav() {
  var nav = document.querySelector('.sidebar');
  if (nav) nav.classList.toggle('collapsed');
}
```

- [ ] **Step 3: 验证**

调整窗口大小，确认布局在不同尺寸下正确适配。

---

### Task 13: 多语言支持

**Files:**
- Modify: `presentation/app_ui.html` (i18n框架)

- [ ] **Step 1: 定义i18n字典**

```javascript
var I18N = {
  "zh-CN": {
    "dashboard": "📊 仪表盘",
    "editor": "✏️ 分组编辑",
    "settings": "⚙️ 全局设置",
    "debug": "🐛 调试监控",
    "backup": "💾 备份管理",
    "keytest": "🧪 按键测试",
    "running": "运行中",
    "stopped": "已停止",
    "start": "▶ 启动",
    "stop": "⏹ 停止",
    "edit": "✏️ 编辑",
    "clone": "📋 克隆",
    "delete": "🗑 删除",
    "save": "保存",
    "cancel": "取消",
    "search": "搜索分组名称、热键、模式...",
    "all": "全部",
    "active": "运行中",
    "emergencyStop": "紧急停止",
    "globalToggle": "全局开关",
    "holdSettings": "长按设置",
    "importExport": "配置导入/导出",
    "theme": "主题",
    "dark": "暗色",
    "light": "亮色"
  },
  "en-US": {
    "dashboard": "📊 Dashboard",
    "editor": "✏️ Editor",
    "settings": "⚙️ Settings",
    "debug": "🐛 Debug",
    "backup": "💾 Backup",
    "keytest": "🧪 Key Test",
    "running": "Running",
    "stopped": "Stopped",
    "start": "▶ Start",
    "stop": "⏹ Stop",
    "edit": "✏️ Edit",
    "clone": "📋 Clone",
    "delete": "🗑 Delete",
    "save": "Save",
    "cancel": "Cancel",
    "search": "Search groups, hotkeys, modes...",
    "all": "All",
    "active": "Active",
    "emergencyStop": "Emergency Stop",
    "globalToggle": "Global Toggle",
    "holdSettings": "Hold Settings",
    "importExport": "Import/Export",
    "theme": "Theme",
    "dark": "Dark",
    "light": "Light"
  }
};
var _currentLang = "zh-CN";

function t(key) {
  var dict = I18N[_currentLang] || I18N["zh-CN"];
  return dict[key] || key;
}

function setLanguage(lang) {
  _currentLang = lang;
  try { localStorage.setItem("lang", lang); } catch(e) {}
  applyLanguage();
}

function applyLanguage() {
  document.querySelectorAll("[data-i18n]").forEach(function(el) {
    var key = el.getAttribute("data-i18n");
    el.textContent = t(key);
  });
  document.querySelectorAll("[data-i18n-placeholder]").forEach(function(el) {
    var key = el.getAttribute("data-i18n-placeholder");
    el.placeholder = t(key);
  });
}
```

- [ ] **Step 2: 为界面元素添加data-i18n属性**

在HTML中为需要翻译的元素添加`data-i18n="key"`属性。

- [ ] **Step 3: 在设置页面添加语言选择**

```html
<div class="form-row"><span class="form-label">语言</span><div class="form-field">
  <select class="input" id="langSelect" style="width:120px;padding:4px 8px;">
    <option value="zh-CN">中文</option>
    <option value="en-US">English</option>
  </select>
</div></div>
```

- [ ] **Step 4: 初始化语言**

```javascript
document.addEventListener("DOMContentLoaded", function() {
  var savedLang = "zh-CN";
  try { savedLang = localStorage.getItem("lang") || "zh-CN"; } catch(e) {}
  var sel = document.getElementById("langSelect");
  if (sel) {
    sel.value = savedLang;
    sel.addEventListener("change", function() { setLanguage(this.value); });
  }
  setLanguage(savedLang);
});
```

- [ ] **Step 5: 验证**

切换语言，确认界面文案正确切换；刷新后语言保持。

---

## 跨批次集成验证

### Task 14: 全量集成测试

- [ ] **Step 1: 启动应用，验证所有13项功能正常工作**

逐项检查：
1. 增量更新：无操作时推送频率降低
2. 导入/导出：文件正确生成和读取
3. 迁移日志：迁移时日志正确记录
4. 搜索过滤：输入搜索词和选择过滤模式正确筛选
5. 批量操作：多选后批量启动/停止/删除正确
6. 性能监控：折线图实时更新
7. 差异比较：两个配置差异正确显示
8. 主题切换：暗色/亮色正确切换
9. 热键验证：无效热键显示错误
10. 快捷键自定义：捕获热键正确
11. 分组模板：模板应用和保存正确
12. 响应式：窗口缩小时布局适配
13. 多语言：中英文切换正确

- [ ] **Step 2: 检查控制台无错误**

打开WebView2开发者工具，确认无JavaScript错误。

- [ ] **Step 3: 提交所有变更**
