# 按键测试页面功能完善 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完善按键测试页面的5项功能缺失：验证自动触发、分组选择器、导出导入、可视化增强、验证报告增强

**Architecture:** 在现有 WebView2 Bridge 架构上扩展，后端增加 Bridge 方法（GetGroupListForValidation、ImportRecording、StartValidationWithAutoTrigger），前端重构验证面板UI和Canvas可视化

**Tech Stack:** AutoHotkey v2, WebView2, HTML/JS/CSS, Canvas API

---

### Task 1: 后端 - 新增 Bridge 方法 GetGroupListForValidation

**Files:**
- Modify: `presentation/webview2_manager.ahk` (Bridge switch 区域 ~L245, 新增方法 ~L750)

- [ ] **Step 1: 在 Bridge switch 中添加新 case**

在 `presentation/webview2_manager.ahk` 的 Bridge switch 区域（`case "ExportRecording":` 之后）添加：

```ahk
case "GetGroupListForValidation":
    result := WebView2Manager._BridgeGetGroupListForValidation()
```

- [ ] **Step 2: 实现 _BridgeGetGroupListForValidation 方法**

在 `_BridgeExportRecording` 方法之后添加：

```ahk
static _BridgeGetGroupListForValidation() {
    try {
        items := []
        for id, group in SkillManager.Groups {
            items.Push(Map("id", id, "mode", group.mode, "active", group.active))
        }
        return JSONSerializer.Stringify(items)
    } catch as e {
        _DebugLog("_BridgeGetGroupListForValidation error: " e.Message)
        return "[]"
    }
}
```

- [ ] **Step 3: 验证语法正确**

运行: `D:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe /ErrorStdOut D:\1demo\AutoHotkeydemo\main.ahk`
预期: 程序正常启动，无语法错误

---

### Task 2: 后端 - 修改 StartValidation 支持自动触发

**Files:**
- Modify: `presentation/webview2_manager.ahk` (_BridgeStartValidation 方法 ~L675)

- [ ] **Step 1: 修改 _BridgeStartValidation 增加自动触发逻辑**

将现有的 `_BridgeStartValidation` 方法替换为：

```ahk
static _BridgeStartValidation(groupId) {
    try {
        if KeyValidator.IsActive()
            return 0
        if groupId = ""
            return 0
        if !IsSet(SkillManager) || !SkillManager.Groups.Has(groupId)
            return -1
        KeyValidator.Start(groupId, (evt) => WebView2Manager._PushSendEvent(evt))
        SkillManager.ToggleGroup(groupId)
        return 1
    } catch as e {
        _DebugLog("_BridgeStartValidation error: " e.Message)
        return 0
    }
}
```

- [ ] **Step 2: 修改 _BridgeStopValidation 增加自动停止分组**

将现有的 `_BridgeStopValidation` 方法替换为：

```ahk
static _BridgeStopValidation(groupId) {
    try {
        if !KeyValidator.IsActive()
            return "{}"
        if groupId != "" && IsSet(SkillManager) && SkillManager.Groups.Has(groupId) {
            if SkillManager.Groups[groupId].active
                SkillManager.ToggleGroup(groupId)
        }
        report := KeyValidator.Stop()
        return JSONSerializer.Stringify(report)
    } catch as e {
        _DebugLog("_BridgeStopValidation error: " e.Message)
        return "{}"
    }
}
```

- [ ] **Step 3: 修改 Bridge switch 中 StopValidation case 传递 groupId**

将 `case "StopValidation":` 行改为：

```ahk
case "StopValidation":
    result := WebView2Manager._BridgeStopValidation(WebView2Manager._GetField(msg, "groupId"))
```

- [ ] **Step 4: 验证语法正确**

运行: `D:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe /ErrorStdOut D:\1demo\AutoHotkeydemo\main.ahk`
预期: 程序正常启动

---

### Task 3: 后端 - 新增 Bridge 方法 ImportRecording

**Files:**
- Modify: `presentation/webview2_manager.ahk` (Bridge switch 区域, 新增方法)

- [ ] **Step 1: 在 Bridge switch 中添加新 case**

在 `case "GetGroupListForValidation":` 之后添加：

```ahk
case "ImportRecording":
    result := WebView2Manager._BridgeImportRecording(WebView2Manager._GetField(msg, "groupId"), WebView2Manager._GetField(msg, "name"), WebView2Manager._GetField(msg, "mode"), WebView2Manager._GetField(msg, "config"))
```

- [ ] **Step 2: 实现 _BridgeImportRecording 方法**

在 `_BridgeGetGroupListForValidation` 方法之后添加：

```ahk
static _BridgeImportRecording(groupId, name, mode, configJson) {
    try {
        if groupId = ""
            return JSONSerializer.Stringify(Map("ok", false, "message", "分组ID不能为空"))
        if SkillManager.Groups.Has(groupId)
            return JSONSerializer.Stringify(Map("ok", false, "message", "分组ID已存在"))
        config := JSONParser.Parse(configJson)
        config["hotkey"] := ""
        config["name"] := name
        if mode != ""
            config["mode"] := mode
        ok := SkillManager.AddGroup(groupId, config)
        if ok {
            ConfigService.SaveConfig()
            return JSONSerializer.Stringify(Map("ok", true, "groupId", groupId))
        }
        return JSONSerializer.Stringify(Map("ok", false, "message", "创建分组失败"))
    } catch as e {
        _DebugLog("_BridgeImportRecording error: " e.Message)
        return JSONSerializer.Stringify(Map("ok", false, "message", e.Message))
    }
}
```

- [ ] **Step 3: 验证语法正确**

运行: `D:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe /ErrorStdOut D:\1demo\AutoHotkeydemo\main.ahk`
预期: 程序正常启动

---

### Task 4: 前端 - 验证面板重构（分组选择器 + 自动触发流程）

**Files:**
- Modify: `presentation/app_ui.html` (验证面板 HTML ~L419, JS ~L1480)

- [ ] **Step 1: 替换验证面板 HTML**

将 `panel-validate` div 的内容替换为：

```html
<div class="keytest-panel" id="panel-validate" style="display:none;">
  <div style="display:flex;gap:8px;align-items:center;margin-bottom:12px;">
    <label style="font-size:13px;color:var(--text-secondary);">选择分组:</label>
    <select class="input" id="validateGroupId" style="width:200px;padding:4px 8px;"></select>
    <button class="btn btn-ghost btn-sm" data-action="refreshGroupList">🔄</button>
  </div>
  <div style="display:flex;gap:8px;margin-bottom:12px;">
    <button class="btn btn-primary btn-sm" data-action="startValidation">▶ 开始验证</button>
    <button class="btn btn-ghost btn-sm" data-action="stopValidation" disabled>⏹ 停止验证</button>
  </div>
  <div style="font-size:13px;color:var(--text-secondary);margin-bottom:8px;">
    验证事件: <span id="valEventCount">0</span> | 状态: <span id="valStatus">就绪</span>
  </div>
  <div style="background:var(--bg-secondary);border-radius:8px;padding:8px;margin-bottom:12px;">
    <canvas id="valCanvas" width="700" height="120" style="width:100%;height:120px;"></canvas>
  </div>
  <div id="valReport" style="display:none;">
    <div class="section-label" style="margin-bottom:8px;">验证报告</div>
    <div id="valReportContent" style="font-size:13px;"></div>
  </div>
</div>
```

- [ ] **Step 2: 添加 refreshGroupList 和修改 startValidation/stopValidation JS**

在 `startValidation` 函数之前添加：

```javascript
function refreshGroupList() {
  ahkCall("GetGroupListForValidation").then(function(r) {
    var sel = document.getElementById("validateGroupId");
    sel.innerHTML = '<option value="">-- 选择分组 --</option>';
    try {
      var groups = typeof r === "string" ? JSON.parse(r) : r;
      if (Array.isArray(groups)) {
        for (var i = 0; i < groups.length; i++) {
          var opt = document.createElement("option");
          opt.value = groups[i].id;
          opt.textContent = groups[i].id + " (" + groups[i].mode + ")" + (groups[i].active ? " ●" : "");
          sel.appendChild(opt);
        }
      }
    } catch(ex) {}
  });
}
```

修改 `startValidation` 函数，将 `document.getElementById("validateGroupId").value.trim()` 改为 `document.getElementById("validateGroupId").value`。

修改 `stopValidation` 函数，在 `bridgeCall` 中传递 groupId：

```javascript
function stopValidation() {
  var gid = document.getElementById("validateGroupId").value;
  bridgeCall("StopValidation", {groupId: gid}).then(function(r) {
    _isValidating = false;
    document.getElementById("valStatus").textContent = "已停止";
    document.getElementById("valStatus").style.color = "";
    document.querySelector('[data-action="startValidation"]').disabled = false;
    document.querySelector('[data-action="stopValidation"]').disabled = true;
    try {
      var report = JSON.parse(r);
      if (report && report.groupId) {
        showValReport(report);
      }
    } catch (ex) {
      showToast("报告解析失败", "error");
    }
    showToast("验证完成，共 " + _valEvents.length + " 个事件");
  });
}
```

- [ ] **Step 3: 添加 refreshGroupList 事件委托和初始化调用**

在事件委托区域添加：

```javascript
else if (action === 'refreshGroupList') refreshGroupList();
```

在 `initKeyTestPage` 函数末尾添加：

```javascript
refreshGroupList();
```

- [ ] **Step 4: 验证前端加载无报错**

运行程序，切换到按键测试页面，检查验证面板是否显示下拉框

---

### Task 5: 前端 - 导出导入功能（填充到编辑器）

**Files:**
- Modify: `presentation/app_ui.html` (exportRecording 函数 ~L1443)

- [ ] **Step 1: 修改 exportRecording 函数，增加导入到分组选项**

将 `exportRecording` 函数替换为：

```javascript
function exportRecording() {
  var mode = document.getElementById("exportMode").value;
  var dur = parseInt(document.getElementById("exportKeyPressDuration").value) || 15;
  if (dur < 5) dur = 5;
  if (dur > 500) dur = 500;
  bridgeCall("ExportRecording", {mode: mode, keyPressDuration: String(dur)}).then(function(r) {
    try {
      var config = JSON.parse(r);
      if (config && config.error) {
        showToast(config.message || "导出失败", "error");
      } else if (config && config.keys && config.keys.length > 0) {
        showImportDialog(mode, config);
      } else {
        showToast("无录制数据可导出", "error");
      }
    } catch (ex) {
      showToast("导出失败: " + ex.message, "error");
    }
  });
}

function showImportDialog(mode, config) {
  var overlay = document.createElement("div");
  overlay.className = "overlay";
  overlay.style.display = "flex";
  var html = '<div class="glass" style="padding:20px;border-radius:12px;max-width:400px;width:90%;">';
  html += '<div class="section-label" style="margin-bottom:12px;">导入录制到分组</div>';
  html += '<div class="form-field"><label style="font-size:13px;">分组ID</label><input class="input" id="importGroupId" placeholder="输入分组ID" style="width:100%;"></div>';
  html += '<div class="form-field" style="margin-top:8px;"><label style="font-size:13px;">分组名称</label><input class="input" id="importGroupName" placeholder="输入名称" style="width:100%;"></div>';
  html += '<div style="font-size:12px;color:var(--text-secondary);margin-top:8px;">模式: ' + escHtml(mode) + ' | 按键数: ' + config.keys.length + '</div>';
  html += '<div style="display:flex;gap:8px;margin-top:16px;">';
  html += '<button class="btn btn-primary btn-sm" id="btnDoImport">导入</button>';
  html += '<button class="btn btn-ghost btn-sm" id="btnDownloadJson">下载JSON</button>';
  html += '<button class="btn btn-ghost btn-sm" id="btnCancelImport">取消</button>';
  html += '</div></div>';
  overlay.innerHTML = html;
  document.body.appendChild(overlay);

  document.getElementById("btnDoImport").onclick = function() {
    var gid = document.getElementById("importGroupId").value.trim();
    var gname = document.getElementById("importGroupName").value.trim();
    if (!gid) { showToast("请输入分组ID", "error"); return; }
    bridgeCall("ImportRecording", {groupId: gid, name: gname, mode: mode, config: JSON.stringify(config)}).then(function(r) {
      try {
        var result = typeof r === "string" ? JSON.parse(r) : r;
        if (result.ok) {
          showToast("分组 " + gid + " 已创建", "success");
          document.body.removeChild(overlay);
          loadGroupsFromAhk();
          refreshGroupList();
          switchPage("editor");
        } else {
          showToast(result.message || "导入失败", "error");
        }
      } catch(ex) {
        showToast("导入失败: " + ex.message, "error");
      }
    });
  };

  document.getElementById("btnDownloadJson").onclick = function() {
    var json = JSON.stringify(config, null, 2);
    var blob = new Blob([json], {type: "application/json"});
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = "key_recording_" + mode + ".json";
    a.click();
    URL.revokeObjectURL(url);
  };

  document.getElementById("btnCancelImport").onclick = function() {
    document.body.removeChild(overlay);
  };
}
```

- [ ] **Step 2: 验证导出导入流程**

运行程序，录制按键 → 停止 → 导出 → 检查弹窗是否出现

---

### Task 6: 前端 - 录制可视化增强（持续时间色块 + 间隔标注 + 统计面板）

**Files:**
- Modify: `presentation/app_ui.html` (drawTimeline 函数 ~L1337, 录制面板 HTML ~L395)

- [ ] **Step 1: 增强录制面板 HTML - 添加统计面板**

在录制面板的 `recEventList` div 之前添加：

```html
<div id="recStats" style="display:flex;gap:12px;margin-bottom:12px;font-size:12px;">
  <div class="glass" style="padding:6px 12px;border-radius:6px;">按键: <span id="statKeyCount">0</span></div>
  <div class="glass" style="padding:6px 12px;border-radius:6px;">平均间隔: <span id="statAvgInterval">-</span>ms</div>
  <div class="glass" style="padding:6px 12px;border-radius:6px;">总时长: <span id="statDuration">0</span>ms</div>
  <div class="glass" style="padding:6px 12px;border-radius:6px;">键盘/鼠标: <span id="statDeviceRatio">0/0</span></div>
</div>
```

- [ ] **Step 2: 重写 drawTimeline 函数**

将 `drawTimeline` 函数替换为：

```javascript
function drawTimeline(canvasId, events) {
  var canvas = document.getElementById(canvasId);
  if (!canvas) return;
  var ctx = canvas.getContext("2d");
  var w = canvas.width;
  var h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  if (events.length === 0) {
    ctx.fillStyle = "#888";
    ctx.font = "12px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("等待事件...", w / 2, h / 2);
    return;
  }

  var maxTs = events[events.length - 1].timestamp || 1;
  if (maxTs < 100) maxTs = 100;
  var pad = 50;
  var usable = w - pad * 2;

  ctx.strokeStyle = "#555";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(pad, h - 20);
  ctx.lineTo(w - pad, h - 20);
  ctx.stroke();

  ctx.fillStyle = "#888";
  ctx.font = "10px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText("0ms", pad, h - 6);
  ctx.fillText(maxTs + "ms", w - pad, h - 6);

  var keyY = {};
  var yIdx = 0;
  for (var i = 0; i < events.length; i++) {
    if (!(events[i].key in keyY)) keyY[events[i].key] = yIdx++;
  }
  var laneH = Math.min(18, (h - 30) / Math.max(yIdx + 1, 1));

  var downMap = {};
  for (var i = 0; i < events.length; i++) {
    var e = events[i];
    var x = pad + (e.timestamp / maxTs) * usable;
    var yOff = keyY[e.key] * laneH;
    var y = h - 25 - yOff - laneH;
    var isDown = e.event === "down" || e.event === "click" || e.event === "press";
    var color = e.device === "mouse" ? "#2196F3" : "#4CAF50";

    if (isDown && e.event === "down") {
      downMap[e.key] = {x: x, ts: e.timestamp, y: y};
    } else if (e.event === "up" && downMap[e.key]) {
      var down = downMap[e.key];
      var endX = x;
      var barW = endX - down.x;
      if (barW < 2) barW = 2;
      ctx.fillStyle = color;
      ctx.globalAlpha = 0.4;
      ctx.fillRect(down.x, down.y - laneH / 2 + 2, barW, laneH - 4);
      ctx.globalAlpha = 1;
      ctx.strokeStyle = color;
      ctx.lineWidth = 1;
      ctx.strokeRect(down.x, down.y - laneH / 2 + 2, barW, laneH - 4);
      delete downMap[e.key];
    } else {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, 4, 0, Math.PI * 2);
      ctx.fill();
    }

    if (i === 0 || events[i - 1].key !== e.key) {
      ctx.fillStyle = "#ccc";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.fillText(e.key, x + 6, y + 3);
    }

    if (i > 0) {
      var prev = events[i - 1];
      var px = pad + (prev.timestamp / maxTs) * usable;
      var interval = e.timestamp - prev.timestamp;
      if (interval > 0 && interval < maxTs) {
        var midX = (px + x) / 2;
        ctx.fillStyle = "rgba(255,255,255,0.35)";
        ctx.font = "8px sans-serif";
        ctx.textAlign = "center";
        ctx.fillText(interval + "ms", midX, h - 25 - (keyY[prev.key] * laneH) - laneH / 2 - 6);
      }
    }
  }
}
```

- [ ] **Step 3: 添加 updateRecStats 函数并在 onBridgeEvent 中调用**

在 `onBridgeEvent` 函数之后添加：

```javascript
function updateRecStats() {
  var count = _recEvents.length;
  document.getElementById("statKeyCount").textContent = count;
  if (count > 1) {
    var sum = 0;
    var kb = 0, ms = 0;
    for (var i = 0; i < count; i++) {
      if (_recEvents[i].device === "mouse") ms++; else kb++;
      if (i > 0) sum += _recEvents[i].timestamp - _recEvents[i - 1].timestamp;
    }
    document.getElementById("statAvgInterval").textContent = Math.round(sum / (count - 1));
    document.getElementById("statDuration").textContent = _recEvents[count - 1].timestamp;
    document.getElementById("statDeviceRatio").textContent = kb + "/" + ms;
  } else {
    document.getElementById("statAvgInterval").textContent = "-";
    document.getElementById("statDuration").textContent = count > 0 ? _recEvents[0].timestamp : "0";
    var kb2 = 0, ms2 = 0;
    for (var i = 0; i < count; i++) { if (_recEvents[i].device === "mouse") ms2++; else kb2++; }
    document.getElementById("statDeviceRatio").textContent = kb2 + "/" + ms2;
  }
}
```

在 `onBridgeEvent` 中 `keyRecordEvent` 分支末尾添加 `updateRecStats();`。

- [ ] **Step 4: 验证可视化效果**

运行程序，录制按键，检查时间线是否显示色块、间隔标注和统计面板

---

### Task 7: 前端 - 验证报告增强（对比时间线 + 偏差热力图）

**Files:**
- Modify: `presentation/app_ui.html` (showValReport 函数 ~L1529)

- [ ] **Step 1: 增强 showValReport 函数**

将 `showValReport` 函数替换为：

```javascript
function showValReport(report) {
  var el = document.getElementById("valReportContent");
  var html = '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px;">';
  html += '<div class="glass" style="padding:8px;border-radius:6px;"><b>顺序正确:</b> ' + (report.orderCorrect ? '<span style="color:#4CAF50">✓</span>' : '<span style="color:#FF5722">✗</span>') + '</div>';
  html += '<div class="glass" style="padding:8px;border-radius:6px;"><b>发送成功率:</b> ' + (report.sendSuccessRate * 100).toFixed(0) + '%</div>';
  html += '<div class="glass" style="padding:8px;border-radius:6px;"><b>平均间隔偏差:</b> ' + report.avgIntervalDeviation + '%</div>';
  html += '<div class="glass" style="padding:8px;border-radius:6px;"><b>最大间隔偏差:</b> ' + report.maxIntervalDeviation + '%</div>';
  html += '<div class="glass" style="padding:8px;border-radius:6px;"><b>长按时序:</b> ' + (report.holdTimingCorrect ? '<span style="color:#4CAF50">✓</span>' : '<span style="color:#FF5722">✗</span>') + '</div>';
  html += '</div>';
  html += '<div style="font-size:12px;color:var(--text-secondary);margin-bottom:8px;">预期: ' + report.totalExpected + ' | 实际: ' + report.totalActual + ' | 时长: ' + report.duration + 'ms</div>';

  if (report.details && report.details.length > 0) {
    html += '<table style="width:100%;font-size:12px;margin-top:8px;border-collapse:collapse;">';
    html += '<tr style="border-bottom:1px solid var(--border);"><th style="text-align:left;padding:4px;">按键</th><th style="text-align:right;padding:4px;">预期(ms)</th><th style="text-align:right;padding:4px;">实际(ms)</th><th style="text-align:right;padding:4px;">偏差</th><th style="text-align:center;padding:4px;">状态</th></tr>';
    for (var i = 0; i < report.details.length; i++) {
      var d = report.details[i];
      var sc = d.status === "good" ? "#4CAF50" : (d.status === "acceptable" ? "#FF9800" : "#FF5722");
      var bg = d.status === "good" ? "rgba(76,175,80,0.08)" : (d.status === "acceptable" ? "rgba(255,152,0,0.08)" : "rgba(255,87,34,0.08)");
      html += '<tr style="border-bottom:1px solid var(--border);background:' + bg + ';"><td style="padding:4px;">' + escHtml(d.key) + '</td><td style="text-align:right;padding:4px;">' + d.expectedInterval + '</td><td style="text-align:right;padding:4px;">' + d.actualInterval + '</td><td style="text-align:right;padding:4px;color:' + sc + ';">' + d.deviation + '%</td><td style="text-align:center;padding:4px;color:' + sc + ';">' + d.status + '</td></tr>';
    }
    html += '</table>';
  }
  el.innerHTML = html;
  document.getElementById("valReport").style.display = "block";
}
```

- [ ] **Step 2: 验证报告显示**

运行程序，执行验证流程，检查报告是否显示偏差热力图颜色

---

### Task 8: 集成测试 - 完整流程验证

**Files:**
- No new files

- [ ] **Step 1: 测试录制→导出→导入流程**

1. 启动程序
2. 切换到按键测试页面
3. 点击"开始录制"，按几个键，点击"停止录制"
4. 点击"导出配置"，填写分组ID和名称，点击"导入"
5. 验证新分组出现在分组列表中

- [ ] **Step 2: 测试验证流程**

1. 切换到验证面板
2. 从下拉框选择一个分组
3. 点击"开始验证"
4. 验证分组自动执行
5. 点击"停止验证"
6. 检查验证报告

- [ ] **Step 3: 测试可视化增强**

1. 录制按键，检查时间线显示色块和间隔标注
2. 检查统计面板数据正确

- [ ] **Step 4: 提交所有改动**
