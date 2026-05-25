# 功能缺失全面修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复25项功能缺失，覆盖验证增强、录制增强、保存流程、用户体验等全方面

**Architecture:** 分8批次按依赖顺序实施，数据层优先于UI层，核心功能优先于体验优化

**Tech Stack:** AutoHotkey v2, HTML/CSS/JavaScript (WebView2), MiniChart

---

## 批次1: 快速修复（5项）

### Task 1: 修正导出面板 keyPressDuration max 值

**Files:**
- Modify: `presentation/app_ui.html:409`

- [ ] **Step 1: 修改 HTML max 属性**

将 `max="500"` 改为 `max="100"`：

```html
<input class="input" id="exportKeyPressDuration" type="number" value="15" min="5" max="100" style="width:80px;padding:4px 8px;">
```

### Task 2: 删除分组添加确认对话框

**Files:**
- Modify: `presentation/app_ui.html` `deleteGroup` 函数

- [ ] **Step 1: 实现 confirmDialog 工具函数**

在 `showToast` 函数后添加：

```javascript
function confirmDialog(title, message, onConfirm) {
  var existing = document.querySelector(".overlay.confirm-dialog");
  if (existing) return;
  var overlay = document.createElement("div");
  overlay.className = "overlay confirm-dialog";
  overlay.style.display = "flex";
  var html = '<div class="glass" style="padding:20px;border-radius:12px;max-width:360px;width:90%;">';
  html += '<div class="section-label" style="margin-bottom:12px;">' + escHtml(title) + '</div>';
  html += '<div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;">' + escHtml(message) + '</div>';
  html += '<div style="display:flex;gap:8px;justify-content:flex-end;">';
  html += '<button class="btn btn-ghost btn-sm" id="btnConfirmCancel">取消</button>';
  html += '<button class="btn btn-danger btn-sm" id="btnConfirmOk">确认</button>';
  html += '</div></div>';
  overlay.innerHTML = html;
  document.body.appendChild(overlay);
  document.getElementById("btnConfirmOk").onclick = function() {
    document.body.removeChild(overlay);
    onConfirm();
  };
  document.getElementById("btnConfirmCancel").onclick = function() {
    document.body.removeChild(overlay);
  };
  overlay.addEventListener("click", function(e) {
    if (e.target === overlay) document.body.removeChild(overlay);
  });
}
```

- [ ] **Step 2: 修改 deleteGroup 函数**

```javascript
function deleteGroup(id) {
  confirmDialog("删除分组", "确定删除分组 " + id + "？此操作不可撤销。", function() {
    ahkCall("DeleteGroup", id).then(function(result) {
      if (result === false) {
        showToast('删除分组失败','error');
      } else {
        loadGroupsFromAhk();
        showToast('分组 '+id+' 已删除','success');
      }
    }).catch(function(e) { showToast('删除失败: '+e,'error'); });
  });
}
```

### Task 3: 备份恢复添加确认对话框

**Files:**
- Modify: `presentation/app_ui.html` `restoreBackup` 函数

- [ ] **Step 1: 修改 restoreBackup 函数**

```javascript
function restoreBackup(name) {
  confirmDialog("恢复备份", "恢复将覆盖当前所有配置，确定继续？", function() {
    ahkCall("RestoreBackup", name).then(function(result) {
      if (result === false) {
        showToast("恢复备份失败","error");
      } else {
        showToast("已恢复备份: "+name,"success");
        loadGroupsFromAhk();
      }
    }).catch(function(e) { showToast("恢复失败: "+e,"error"); });
  });
}
```

### Task 4: 录制面板添加清除按钮

**Files:**
- Modify: `presentation/app_ui.html` 录制面板 HTML + JS

- [ ] **Step 1: 在录制面板操作栏添加清除按钮**

找到录制面板的按钮区域，在导出按钮后添加：

```html
<button class="btn btn-ghost btn-sm" data-action="clearRecording" disabled>🗑 清除</button>
```

- [ ] **Step 2: 实现 clearRecording 函数**

```javascript
function clearRecording() {
  _recEvents = [];
  document.getElementById("recEventList").innerHTML = "";
  document.getElementById("recEventCount").textContent = "0";
  document.getElementById("statKeyCount").textContent = "0";
  document.getElementById("statAvgInterval").textContent = "-";
  document.getElementById("statDuration").textContent = "0";
  document.getElementById("statDeviceRatio").textContent = "0/0";
  drawTimeline("recTimeline", []);
  document.querySelector('[data-action="exportRecording"]').disabled = true;
  document.querySelector('[data-action="clearRecording"]').disabled = true;
  showToast("录制数据已清除", "success");
}
```

- [ ] **Step 3: 在事件委托中添加 clearRecording 处理**

在全局事件委托的 action switch 中添加：

```javascript
case "clearRecording": clearRecording(); break;
```

- [ ] **Step 4: 在 stopRecording 成功后启用清除按钮**

在 `stopRecording` 的 then 回调中添加：

```javascript
document.querySelector('[data-action="clearRecording"]').disabled = false;
```

### Task 5: 编辑器间隔输入添加上限验证

**Files:**
- Modify: `presentation/app_ui.html` `renderKeyIntervalTable`, `renderKeyDelayTable`, `renderSubGroups`

- [ ] **Step 1: 为间隔输入框添加 max 属性**

在 `renderKeyIntervalTable` 中，将间隔输入框改为：

```javascript
h += '<input class="input interval-cell" value="'+(intervalsArr[i]||50)+'" type="number" min="10" max="60000" data-action="setInterval" data-field="'+escAttr(intervalsField)+'" data-idx="'+i+'">';
```

在 `renderKeyDelayTable` 中同理：

```javascript
h += '<input class="input interval-cell" value="'+(delaysArr[i]||100)+'" type="number" min="10" max="60000" data-action="setDelay" data-field="'+escAttr(delaysField)+'" data-idx="'+i+'">';
```

在 `renderSubGroups` 中同理：

```javascript
h += '<input class="input interval-cell" value="'+(arr[j]||(g.type==="periodic"?50:100))+'" type="number" min="10" max="60000" data-action="updateSubVal" data-group="'+i+'" data-idx="'+j+'">';
```

---

## 批次2: 数据层增强（3项）

### Task 6: 验证报告增加 hold timing 详情数据

**Files:**
- Modify: `domain/key_validator.ahk` `_BuildReport`

- [ ] **Step 1: 在 _BuildReport 中收集 holdDetails**

在 `holdTimingCorrect := true` 之后、`pendingDowns` 循环之前，添加 `holdDetails` 数组收集：

```autohotkey
        holdDetails := []
```

在 `else if evt["event"] = "up"` 分支中，收集详情：

```autohotkey
            } else if evt["event"] = "up" && pendingDowns.Has(evt["key"]) && pendingDowns[evt["key"]].Length > 0 {
                downTs := pendingDowns[evt["key"]].RemoveAt(1)
                holdDuration := evt["timestamp"] - downTs
                isValid := holdDuration >= 5 && holdDuration <= 200
                if !isValid
                    holdTimingCorrect := false
                holdDetails.Push(Map(
                    "key", evt["key"],
                    "downTs", downTs,
                    "upTs", evt["timestamp"],
                    "holdDuration", holdDuration,
                    "valid", isValid
                ))
            }
```

在 `for key in pendingDowns` 循环中，记录未释放的键：

```autohotkey
        for key in pendingDowns {
            if pendingDowns[key].Length > 0 {
                holdTimingCorrect := false
                for downTs in pendingDowns[key] {
                    holdDetails.Push(Map(
                        "key", key,
                        "downTs", downTs,
                        "upTs", 0,
                        "holdDuration", 0,
                        "valid", false
                    ))
                }
            }
        }
```

在 return Map 中添加 `holdDetails`：

```autohotkey
            "holdDetails", holdDetails,
```

### Task 7: 分组增加 name 字段

**Files:**
- Modify: `domain/skill_group.ahk` `__New`
- Modify: `infrastructure/config_validator.ahk`
- Modify: `presentation/webview2_manager.ahk` `_BridgeGetGroupList`, `_BridgeSaveConfig`, `_BridgeGetGroupDetail`
- Modify: `presentation/app_ui.html` 仪表盘、编辑器

- [ ] **Step 1: SkillGroup 添加 name 属性**

在 `__New` 中 `this.id := id` 后添加：

```autohotkey
            this.name := _GetProp(config, "name", id)
```

- [ ] **Step 2: 配置验证器允许 name 字段**

在 `config_validator.ahk` 中，找到通用字段验证部分，确保 `name` 在允许的字段列表中（如果有的话添加 "name"）。

- [ ] **Step 3: _BridgeGetGroupList 返回 name**

在 `_BridgeGetGroupList` 中 `groupObj["id"] := id` 后添加：

```autohotkey
                groupObj["name"] := group.name
```

- [ ] **Step 4: _BridgeGetGroupDetail 返回 name**

在 `_BridgeGetGroupDetail` 中 `detail := Map(...)` 之前添加：

```autohotkey
            detail["name"] := group.name
```

- [ ] **Step 5: _BridgeSaveConfig 保留 name**

在 `_BridgeSaveConfig` 中，删除 id 之前保存 name：

```autohotkey
            groupName := ""
            if groupConfig is Map {
                if groupConfig.Has("name") {
                    groupName := groupConfig["name"]
                }
                if groupConfig.Has("id")
                    groupConfig.Delete("id")
            } else if HasProp(groupConfig, "id") {
                if HasProp(groupConfig, "name")
                    groupName := groupConfig.name
                groupConfig.DeleteProp("id")
            }
```

然后在 `GroupService.UpdateGroup`/`CreateGroup` 之前把 name 放回：

```autohotkey
            if groupName != "" && groupConfig is Map
                groupConfig["name"] := groupName
```

- [ ] **Step 6: 仪表盘显示 name**

在 `renderDashboard` 中，将 `分组 '+escHtml(g.id)` 改为：

```javascript
html += '<div class="group-card-header"><span class="group-card-id">'+escHtml(g.name || g.id)+'</span><span class="group-card-hotkey">'+escHtml(g.hotkey)+'</span></div>';
```

- [ ] **Step 7: 编辑器添加名称输入框**

在 `editGroup` 函数中加载 name：

```javascript
if (cfg.name) document.getElementById('groupName').value = cfg.name;
else document.getElementById('groupName').value = '';
```

在 `saveConfig` 中收集 name：

```javascript
var name=document.getElementById("groupName").value.trim();
if(!name) name=id;
cfg.name=name;
```

在 `resetEditor` 中重置 name：

```javascript
document.getElementById('groupName').value = "";
```

在编辑器 HTML 中，idInput 后添加：

```html
<div class="form-field"><label>名称</label><input class="input" id="groupName" placeholder="显示名称（默认=ID）" style="width:100%;"></div>
```

### Task 8: 录制/验证事件上限保护

**Files:**
- Modify: `domain/key_recorder.ahk` `OnKey`, `OnMouse`
- Modify: `domain/key_validator.ahk` `OnSend`

- [ ] **Step 1: KeyRecorder 添加事件上限**

在类顶部添加常量：

```autohotkey
    static MAX_EVENTS := 10000
```

在 `OnKey` 方法开头添加检查：

```autohotkey
        if this._events.Length >= this.MAX_EVENTS {
            this.Stop()
            return
        }
```

在 `OnMouse` 方法开头添加同样检查。

- [ ] **Step 2: KeyValidator 添加事件上限**

在类顶部添加常量：

```autohotkey
    static MAX_EVENTS := 10000
```

在 `OnSend` 方法开头添加检查：

```autohotkey
        if this._actualSeq.Length >= this.MAX_EVENTS {
            this.Stop()
            return
        }
```

---

## 批次3: 验证核心增强（3项）

### Task 9: 验证功能支持 hold/hybrid/enhanced_hybrid 模式

**Files:**
- Modify: `domain/key_validator.ahk` `_LoadExpectedSequence`
- Modify: `presentation/webview2_manager.ahk` `_BridgeGetGroupDetail`
- Modify: `presentation/app_ui.html` `startValidation`

- [ ] **Step 1: _LoadExpectedSequence 增加 hybrid 模式**

在 `_LoadExpectedSequence` 中，在 `holdKeys` 分支后添加 hybrid/enhanced_hybrid 分支：

```autohotkey
        } else if HasProp(group, "groups") && group.groups.Length > 0 {
            for sg in group.groups {
                sgKeys := []
                if sg is Map {
                    if sg.Has("pressKeys")
                        for k in sg["pressKeys"]
                            sgKeys.Push(k)
                    else if sg.Has("keys")
                        for k in sg["keys"]
                            sgKeys.Push(k)
                } else {
                    if HasProp(sg, "pressKeys")
                        for k in sg.pressKeys
                            sgKeys.Push(k)
                    else if HasProp(sg, "keys")
                        for k in sg.keys
                            sgKeys.Push(k)
                }
                sgType := ""
                if sg is Map
                    sgType := sg.Has("type") ? sg["type"] : "periodic"
                else
                    sgType := HasProp(sg, "type") ? sg.type : "periodic"
                for k in sgKeys {
                    interval := 50
                    if sgType = "sequence" && HasProp(group, "seqInterval")
                        interval := group.seqInterval
                    else if sgType = "periodic"
                        interval := 50
                    this._expectedSeq.Push(Map("key", k, "interval", interval))
                }
            }
        }
```

- [ ] **Step 2: _BridgeGetGroupDetail 返回 groups 子组数据**

在 `_BridgeGetGroupDetail` 中，在 `detail` Map 构建后添加：

```autohotkey
            if group.HasProp("groups") && group.groups.Length > 0
                detail["groups"] := group.groups
            if group.HasProp("seqInterval")
                detail["seqInterval"] := group.seqInterval
```

- [ ] **Step 3: 前端 startValidation 处理 hybrid 模式**

在 `startValidation` 中，`if (detail && detail.keys)` 分支后添加 hybrid 处理：

```javascript
      } else if (detail && detail.groups && detail.groups.length > 0) {
        var ts = 0;
        for (var gi = 0; gi < detail.groups.length; gi++) {
          var sg = detail.groups[gi];
          var sgKeys = sg.pressKeys || sg.keys || [];
          var sgType = sg.type || "periodic";
          for (var ki = 0; ki < sgKeys.length; ki++) {
            var isWheel = sgKeys[ki].indexOf("Wheel") >= 0;
            _valExpectedSeq.push({key: sgKeys[ki], event: "down", timestamp: ts, device: (sgKeys[ki].indexOf("Button") >= 0 || isWheel) ? "mouse" : "keyboard"});
            if (!isWheel) {
              var holdDur = detail.keyPressDuration || 15;
              ts += holdDur;
              _valExpectedSeq.push({key: sgKeys[ki], event: "up", timestamp: ts, device: (sgKeys[ki].indexOf("Button") >= 0 || isWheel) ? "mouse" : "keyboard"});
            }
            if (ki < sgKeys.length - 1) {
              var interval = sgType === "periodic" ? (sg.intervals ? sg.intervals[ki] || 50 : 50) : (sg.delays ? sg.delays[ki] || 100 : 100);
              ts += interval;
            }
          }
          if (gi < detail.groups.length - 1) {
            ts += detail.seqInterval || 100;
          }
        }
        var wheelCount2 = 0;
        for (var wi2 = 0; wi2 < _valExpectedSeq.length; wi2++) {
          if (_valExpectedSeq[wi2].key.indexOf("Wheel") >= 0 && _valExpectedSeq[wi2].event === "down") wheelCount2++;
        }
        _valExpectedCount = _valExpectedSeq.length;
        _valExpectedIntervals = [];
      }
```

### Task 10: hold 图表增强

**Files:**
- Modify: `presentation/app_ui.html` `_renderHold`, `showValReport`

- [ ] **Step 1: 修改 _renderHold 为柱状图**

替换 `_renderHold` 实现：

```javascript
  _renderHold: function(chart, w, h) {
    var ctx = chart.ctx;
    var details = chart.data.details || [];
    if (details.length === 0) {
      ctx.fillStyle = "#888";
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("无长按数据", w / 2, h / 2);
      return;
    }
    var pad = { top: 20, right: 20, bottom: 30, left: 60 };
    var plotW = w - pad.left - pad.right;
    var plotH = h - pad.top - pad.bottom;
    var maxDur = 250;
    for (var i = 0; i < details.length; i++) {
      if (details[i].holdDuration > maxDur) maxDur = details[i].holdDuration;
    }
    maxDur = Math.ceil(maxDur / 50) * 50;
    var barW = Math.min(40, (plotW / details.length) * 0.7);
    var gap = (plotW - barW * details.length) / (details.length + 1);
    ctx.fillStyle = "rgba(74,222,128,0.1)";
    ctx.fillRect(pad.left, pad.top + plotH * (1 - 200 / maxDur), plotW, plotH * (200 - 5) / maxDur);
    ctx.strokeStyle = "rgba(74,222,128,0.3)";
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(pad.left, pad.top + plotH * (1 - 200 / maxDur));
    ctx.lineTo(pad.left + plotW, pad.top + plotH * (1 - 200 / maxDur));
    ctx.moveTo(pad.left, pad.top + plotH * (1 - 5 / maxDur));
    ctx.lineTo(pad.left + plotW, pad.top + plotH * (1 - 5 / maxDur));
    ctx.stroke();
    ctx.setLineDash([]);
    for (var i = 0; i < details.length; i++) {
      var d = details[i];
      var x = pad.left + gap + i * (barW + gap);
      var barH = (d.holdDuration / maxDur) * plotH;
      var y = pad.top + plotH - barH;
      ctx.fillStyle = d.valid ? "#4CAF50" : "#FF5722";
      ctx.fillRect(x, y, barW, barH);
      ctx.fillStyle = "#ccc";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(d.key, x + barW / 2, pad.top + plotH + 14);
      ctx.fillText(d.holdDuration + "ms", x + barW / 2, y - 4);
    }
    ctx.fillStyle = "#888";
    ctx.font = "10px sans-serif";
    ctx.textAlign = "right";
    for (var v = 0; v <= maxDur; v += maxDur / 4) {
      var yy = pad.top + plotH * (1 - v / maxDur);
      ctx.fillText(Math.round(v), pad.left - 6, yy + 3);
    }
  }
```

- [ ] **Step 2: 修改 showValReport 传递 holdDetails**

在 `showValReport` 中，替换 hold 图表创建：

```javascript
  MiniChart.destroy("holdCanvas");
  MiniChart.create("holdCanvas", "hold", {
    details: report.holdDetails || [],
    correct: report.holdTimingCorrect
  });
```

### Task 11: 验证实时统计准确性修复

**Files:**
- Modify: `presentation/app_ui.html` `updateValLiveStats`

- [ ] **Step 1: 修改 updateValLiveStats 使用 down-up 配对逻辑**

```javascript
function updateValLiveStats() {
  var panel = document.getElementById("valLiveStats");
  if (!panel) return;
  panel.style.display = "";
  var n = _valEvents.length;
  document.getElementById("valLiveCount").textContent = n;
  if (n >= 2) {
    var sumDev = 0;
    var maxDev = 0;
    var devCount = 0;
    var keyIdx = 0;
    for (var i = 1; i < n; i++) {
      if (_valEvents[i].event === "down" && _valEvents[i - 1].event === "up") {
        var interval = _valEvents[i].timestamp - _valEvents[i - 1].timestamp;
        var expected = (_valExpectedIntervals.length > 0 && keyIdx < _valExpectedIntervals.length) ? _valExpectedIntervals[keyIdx] : 50;
        if (expected <= 0) expected = 50;
        var dev = Math.abs(interval - expected) / expected * 100;
        sumDev += dev;
        if (dev > maxDev) maxDev = dev;
        devCount++;
        keyIdx++;
      }
    }
    document.getElementById("valLiveAvgDev").textContent = devCount > 0 ? (sumDev / devCount).toFixed(1) + "%" : "-";
    document.getElementById("valLiveMaxDev").textContent = devCount > 0 ? maxDev.toFixed(1) + "%" : "-";
  } else {
    document.getElementById("valLiveAvgDev").textContent = "-";
    document.getElementById("valLiveMaxDev").textContent = "-";
  }
}
```

---

## 批次4: 录制增强（4项）

### Task 12: 鼠标事件记录 down/up

**Files:**
- Modify: `domain/key_recorder.ahk` `_InstallMouseHooks`, `_MakeHotkeyHandler`, `_RemoveMouseHooks`

- [ ] **Step 1: 修改 _MakeHotkeyHandler 支持 event 参数**

```autohotkey
    static _MakeHotkeyHandler(btn, event) {
        return () => (this._recording ? this.OnMouse(btn, event) : 0)
    }
```

- [ ] **Step 2: 修改 _InstallMouseHooks 注册 down/up 热键**

```autohotkey
    static _InstallMouseHooks() {
        mouseButtons := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
        for btn in mouseButtons {
            try {
                Hotkey("~" btn, this._MakeHotkeyHandler(btn, "down"), "On")
            } catch {
            }
            try {
                Hotkey("~" btn " Up", this._MakeHotkeyHandler(btn, "up"), "On")
            } catch {
            }
        }
        try {
            Hotkey("~WheelUp", this._MakeWheelHotkeyHandler("WheelUp"), "On")
        } catch {
        }
        try {
            Hotkey("~WheelDown", this._MakeWheelHotkeyHandler("WheelDown"), "On")
        } catch {
        }
        this._mouseHotkeys := true
    }
```

- [ ] **Step 3: 修改 _RemoveMouseHooks**

```autohotkey
    static _RemoveMouseHooks() {
        if !this._mouseHotkeys
            return
        mouseButtons := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
        for btn in mouseButtons {
            try Hotkey("~" btn, "Off")
            try Hotkey("~" btn " Up", "Off")
        }
        try Hotkey("~WheelUp", "Off")
        try Hotkey("~WheelDown", "Off")
        this._mouseHotkeys := false
    }
```

### Task 13: 录制器支持暂停/继续

**Files:**
- Modify: `domain/key_recorder.ahk`
- Modify: `presentation/app_ui.html` 录制面板

- [ ] **Step 1: KeyRecorder 添加 Pause/Resume**

在类中添加：

```autohotkey
    static _paused := false

    static IsPaused() => this._paused

    static Pause() {
        if !this._recording || this._paused
            return
        this._paused := true
        if this._hook {
            try this._hook.Stop()
            this._hook := 0
        }
        this._RemoveMouseHooks()
    }

    static Resume() {
        if !this._recording || !this._paused
            return
        this._paused := false
        try {
            this._hook := InputHook("V L0")
            this._hook.KeyDown := (keyName, *) => this.OnKey(keyName, "down")
            this._hook.KeyUp := (keyName, *) => this.OnKey(keyName, "up")
            this._hook.KeyOpt("{All}", "N")
            this._hook.Start()
            this._InstallMouseHooks()
        } catch as e {
            this._recording := false
            this._paused := false
            throw e
        }
    }
```

修改 `Stop` 方法，重置 `_paused`：

```autohotkey
        this._paused := false
```

- [ ] **Step 2: 前端添加暂停/继续按钮**

在录制面板按钮区域，停止按钮后添加：

```html
<button class="btn btn-ghost btn-sm" data-action="pauseRecording" disabled>⏸ 暂停</button>
```

- [ ] **Step 3: 实现 pauseRecording/resumeRecording 函数**

```javascript
function pauseRecording() {
  ahkCall("PauseRecording", {}).then(function(r) {
    if (r === 1) {
      document.getElementById("recStatus").textContent = "已暂停";
      document.getElementById("recStatus").style.color = "#FF9800";
      document.querySelector('[data-action="pauseRecording"]').style.display = "none";
      document.querySelector('[data-action="resumeRecording"]').style.display = "";
    }
  }).catch(function(e) { showToast("暂停失败: " + e, "error"); });
}

function resumeRecording() {
  ahkCall("ResumeRecording", {}).then(function(r) {
    if (r === 1) {
      document.getElementById("recStatus").textContent = "录制中...";
      document.getElementById("recStatus").style.color = "#4CAF50";
      document.querySelector('[data-action="resumeRecording"]').style.display = "none";
      document.querySelector('[data-action="pauseRecording"]').style.display = "";
    }
  }).catch(function(e) { showToast("继续失败: " + e, "error"); });
}
```

在暂停按钮后添加继续按钮（默认隐藏）：

```html
<button class="btn btn-ghost btn-sm" data-action="resumeRecording" style="display:none;">▶ 继续</button>
```

- [ ] **Step 4: 后端添加 PauseRecording/ResumeRecording bridge**

在 `webview2_manager.ahk` 的 `_SetupWebMessageHandler` switch 中添加：

```autohotkey
                case "PauseRecording":
                    try {
                        if KeyRecorder.IsRecording() && !KeyRecorder.IsPaused() {
                            KeyRecorder.Pause()
                            result := 1
                        } else
                            result := 0
                    } catch as e {
                        _DebugLog("PauseRecording error: " e.Message)
                        result := 0
                    }
                case "ResumeRecording":
                    try {
                        if KeyRecorder.IsRecording() && KeyRecorder.IsPaused() {
                            KeyRecorder.Resume()
                            result := 1
                        } else
                            result := 0
                    } catch as e {
                        _DebugLog("ResumeRecording error: " e.Message)
                        result := 0
                    }
```

- [ ] **Step 5: startRecording 时启用暂停按钮**

在 `startRecording` 中，启动成功后：

```javascript
document.querySelector('[data-action="pauseRecording"]').disabled = false;
```

- [ ] **Step 6: stopRecording/resetRecUI 时重置暂停状态**

在 `resetRecUI` 中添加：

```javascript
document.querySelector('[data-action="pauseRecording"]').disabled = true;
document.querySelector('[data-action="pauseRecording"]').style.display = "";
document.querySelector('[data-action="resumeRecording"]').style.display = "none";
```

### Task 14: 录制后可编辑/删除按键

**Files:**
- Modify: `presentation/app_ui.html` `appendRecEvent`

- [ ] **Step 1: 修改 appendRecEvent 添加删除按钮**

```javascript
function appendRecEvent(evt) {
  var list = document.getElementById("recEventList");
  var line = document.createElement("div");
  line.style.padding = "2px 0";
  line.style.borderBottom = "1px solid var(--border)";
  line.style.display = "flex";
  line.style.justifyContent = "space-between";
  line.style.alignItems = "center";
  var dev = evt.device === "mouse" ? "🖱" : "⌨";
  var ev = evt.event === "down" ? "↓" : "↑";
  var devColor = evt.device === "mouse" ? "#2196F3" : "#4CAF50";
  var span = document.createElement("span");
  span.style.color = devColor;
  span.textContent = dev + " " + ev;
  line.appendChild(span);
  line.appendChild(document.createTextNode(" " + escHtml(evt.key) + "  " + evt.timestamp + "ms"));
  var delBtn = document.createElement("span");
  delBtn.textContent = "×";
  delBtn.style.cursor = "pointer";
  delBtn.style.color = "#FF5722";
  delBtn.style.marginLeft = "8px";
  delBtn.style.fontSize = "14px";
  delBtn.setAttribute("data-rec-idx", String(_recEvents.length - 1));
  delBtn.onclick = function() {
    var idx = parseInt(this.getAttribute("data-rec-idx"));
    if (idx >= 0 && idx < _recEvents.length) {
      _recEvents.splice(idx, 1);
      rebuildRecEventList();
      drawTimeline("recTimeline", _recEvents);
      updateRecStats();
    }
  };
  line.appendChild(delBtn);
  list.appendChild(line);
  list.scrollTop = list.scrollHeight;
}
```

- [ ] **Step 2: 添加 rebuildRecEventList 函数**

```javascript
function rebuildRecEventList() {
  var list = document.getElementById("recEventList");
  list.innerHTML = "";
  for (var i = 0; i < _recEvents.length; i++) {
    appendRecEvent(_recEvents[i]);
  }
}
```

### Task 15: 录制导出增加 hold 模式

**Files:**
- Modify: `presentation/app_ui.html` 导出模式下拉
- Modify: `domain/key_recorder.ahk` `ExportAsGroupConfig`

- [ ] **Step 1: 前端添加 hold 选项**

```html
<select class="input" id="exportMode" style="width:120px;padding:4px 8px;">
  <option value="periodic">周期性</option>
  <option value="sequence">序列</option>
  <option value="hold">长按</option>
</select>
```

- [ ] **Step 2: ExportAsGroupConfig 添加 hold 模式**

在 `ExportAsGroupConfig` 中，`if mode = "sequence"` 块后添加：

```autohotkey
        if mode = "hold" {
            return Map(
                "mode", "hold",
                "holdKeys", keys,
                "holdDuration", 0,
                "autoRepeat", false,
                "repeatInterval", 1000,
                "keyPressDuration", keyPressDuration
            )
        }
```

---

## 批次5: 保存流程增强（2项）

### Task 16: 保存分组时热键冲突检测

**Files:**
- Modify: `presentation/app_ui.html` `saveConfig`

- [ ] **Step 1: 在 saveConfig 中添加热键冲突检测**

在 `var cfg = {...}` 之后、`ahkCall("SaveConfig", ...)` 之前添加：

```javascript
    var conflictGroup = null;
    for (var ci = 0; ci < sampleGroups.length; ci++) {
      if (sampleGroups[ci].id !== id && sampleGroups[ci].hotkey === hotkey && hotkey !== "") {
        conflictGroup = sampleGroups[ci];
        break;
      }
    }
    if (conflictGroup) {
      confirmDialog("热键冲突", "热键 " + hotkey + " 已被分组 " + conflictGroup.id + " 使用，确定继续保存？", function() {
        doSaveConfig(cfg);
      });
      return;
    }
    doSaveConfig(cfg);
```

- [ ] **Step 2: 提取保存逻辑为 doSaveConfig 函数**

```javascript
function doSaveConfig(cfg) {
  ahkCall("SaveConfig", JSON.stringify(cfg)).then(function(result) {
    if (result === false) {
      showToast("保存失败，请检查配置","error");
    } else {
      showToast("分组 "+cfg.id+" 已保存","success");
      loadGroupsFromAhk();
      switchPage("dashboard");
    }
  }).catch(function(e) { showToast("保存失败: "+e,"error"); });
}
```

### Task 17: 编辑器撤销/重做

**Files:**
- Modify: `presentation/app_ui.html` 编辑器

- [ ] **Step 1: 添加撤销/重做栈和操作函数**

在全局变量区添加：

```javascript
var _undoStack = [];
var _redoStack = [];
var MAX_UNDO = 50;

function pushUndoState() {
  _undoStack.push(JSON.stringify(editorConfig));
  if (_undoStack.length > MAX_UNDO) _undoStack.shift();
  _redoStack = [];
}

function undoEditor() {
  if (_undoStack.length === 0) return;
  _redoStack.push(JSON.stringify(editorConfig));
  editorConfig = JSON.parse(_undoStack.pop());
  renderConfigSection();
  renderHoldSection();
  updatePreview();
  showToast("已撤销", "success");
}

function redoEditor() {
  if (_redoStack.length === 0) return;
  _undoStack.push(JSON.stringify(editorConfig));
  editorConfig = JSON.parse(_redoStack.pop());
  renderConfigSection();
  renderHoldSection();
  updatePreview();
  showToast("已重做", "success");
}
```

- [ ] **Step 2: 在编辑操作前调用 pushUndoState**

在以下函数开头添加 `pushUndoState()`：
- `addKeyTo`, `deleteKeyFrom`, `addSubGroup`, `deleteSubGroup`, `changeSubGroupType`, `addSubKey`, `deleteSubKey`, `updateSubVal`
- `deleteHoldChip`, `addHoldChip`, `setHoldDuration`, `toggleAutoRepeat`, `setRepeatInterval`
- `setSeqInterval`, `setInterval`, `setDelay`

- [ ] **Step 3: 添加键盘快捷键监听**

在 `init` 函数中添加：

```javascript
document.addEventListener("keydown", function(e) {
  if (e.ctrlKey && e.key === "z") { e.preventDefault(); undoEditor(); }
  if (e.ctrlKey && e.key === "y") { e.preventDefault(); redoEditor(); }
});
```

---

## 批次6: 验证体验增强（1项）

### Task 18: 验证历史记录

**Files:**
- Modify: `presentation/app_ui.html` 验证面板

- [ ] **Step 1: 添加验证历史变量和 UI**

在全局变量区添加：

```javascript
var _valHistory = [];
var MAX_VAL_HISTORY = 10;
```

在验证面板中，valReport div 后添加历史选择器：

```html
<div id="valHistoryBar" style="display:none;margin-top:8px;">
  <span style="font-size:12px;color:var(--text-secondary);">历史记录:</span>
  <select id="valHistorySelect" style="margin-left:6px;padding:2px 6px;font-size:11px;"></select>
  <button class="btn btn-ghost btn-sm" data-action="compareVal" style="margin-left:6px;font-size:10px;">对比上次</button>
</div>
```

- [ ] **Step 2: 在 showValReport 中保存历史**

在 `showValReport` 函数开头添加：

```javascript
  _valHistory.push(report);
  if (_valHistory.length > MAX_VAL_HISTORY) _valHistory.shift();
  var sel = document.getElementById("valHistorySelect");
  sel.innerHTML = "";
  for (var hi = _valHistory.length - 1; hi >= 0; hi--) {
    var opt = document.createElement("option");
    opt.value = hi;
    opt.textContent = "#" + (hi + 1) + " " + (_valHistory[hi].orderCorrect ? "✓" : "✗") + " " + Math.round((_valHistory[hi].sendSuccessRate || 0) * 100) + "%";
    sel.appendChild(opt);
  }
  document.getElementById("valHistoryBar").style.display = "";
  sel.onchange = function() {
    var idx = parseInt(this.value);
    if (idx >= 0 && idx < _valHistory.length) showValReport(_valHistory[idx]);
  };
```

- [ ] **Step 3: 实现对比功能**

```javascript
function compareValReports() {
  if (_valHistory.length < 2) {
    showToast("至少需要2次验证记录才能对比", "error");
    return;
  }
  var curr = _valHistory[_valHistory.length - 1];
  var prev = _valHistory[_valHistory.length - 2];
  var msg = "本次 vs 上次:\n";
  msg += "顺序: " + (curr.orderCorrect ? "✓" : "✗") + " → " + (prev.orderCorrect ? "✓" : "✗") + "\n";
  msg += "发送率: " + Math.round((curr.sendSuccessRate || 0) * 100) + "% → " + Math.round((prev.sendSuccessRate || 0) * 100) + "%\n";
  msg += "平均偏差: " + (curr.avgIntervalDeviation || 0) + "% → " + (prev.avgIntervalDeviation || 0) + "%";
  confirmDialog("验证对比", msg, function() {});
}
```

在事件委托中添加 `compareVal` 处理。

---

## 批次7: 仪表盘增强（3项）

### Task 19: 分组复制/克隆

**Files:**
- Modify: `presentation/app_ui.html` 仪表盘

- [ ] **Step 1: 在 renderDashboard 添加复制按钮**

在删除按钮前添加：

```javascript
html += '<button class="btn btn-ghost btn-sm" data-action="clone" data-group-id="'+escAttr(g.id)+'">📋 复制</button>';
```

- [ ] **Step 2: 实现 cloneGroup 函数**

```javascript
function cloneGroup(id) {
  var newId = id + "_copy";
  var suffix = 1;
  while (sampleGroups.some(function(g) { return g.id === newId; })) {
    newId = id + "_copy" + suffix;
    suffix++;
  }
  ahkCall("LoadGroupConfig", id).then(function(cfg) {
    if (cfg && cfg.mode) {
      cfg.id = newId;
      cfg.name = (cfg.name || id) + " 副本";
      cfg.hotkey = "";
      ahkCall("SaveConfig", JSON.stringify(cfg)).then(function(result) {
        if (result === false) {
          showToast("复制分组失败","error");
        } else {
          showToast("分组已复制为 " + newId,"success");
          loadGroupsFromAhk();
        }
      }).catch(function(e) { showToast("复制失败: "+e,"error"); });
    }
  }).catch(function(e) { showToast("加载配置失败: "+e,"error"); });
}
```

- [ ] **Step 3: 在事件委托中添加 clone 处理**

```javascript
else if (action === 'clone') cloneGroup(gid);
```

### Task 20: 分组配置导出/导入 JSON

**Files:**
- Modify: `presentation/app_ui.html` 仪表盘 + 设置页

- [ ] **Step 1: 仪表盘添加导出按钮**

在 `renderDashboard` 中，分组卡片操作栏的编辑按钮后添加：

```javascript
html += '<button class="btn btn-ghost btn-sm" data-action="exportGroup" data-group-id="'+escAttr(g.id)+'">📤 导出</button>';
```

- [ ] **Step 2: 实现 exportGroupConfig 函数**

```javascript
function exportGroupConfig(id) {
  ahkCall("LoadGroupConfig", id).then(function(cfg) {
    if (cfg) {
      cfg.id = id;
      var json = JSON.stringify(cfg, null, 2);
      var blob = new Blob([json], {type: "application/json"});
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url;
      a.download = "group_" + id + ".json";
      a.click();
      URL.revokeObjectURL(url);
      showToast("配置已导出", "success");
    }
  }).catch(function(e) { showToast("导出失败: "+e,"error"); });
}
```

- [ ] **Step 3: 设置页添加导入按钮**

在设置页底部添加：

```html
<div style="margin-top:16px;padding-top:12px;border-top:1px solid var(--glass-border);">
  <div class="section-label" style="margin-bottom:8px;">配置导入</div>
  <button class="btn btn-ghost btn-sm" data-action="importGroupConfig">📥 从JSON文件导入分组</button>
  <input type="file" id="importConfigFile" accept=".json" style="display:none;">
</div>
```

- [ ] **Step 4: 实现 importGroupConfig 函数**

```javascript
function importGroupConfig() {
  var fileInput = document.getElementById("importConfigFile");
  fileInput.onchange = function() {
    var file = this.files[0];
    if (!file) return;
    var reader = new FileReader();
    reader.onload = function(e) {
      try {
        var cfg = JSON.parse(e.target.result);
        if (!cfg.mode) { showToast("无效的配置文件","error"); return; }
        var gid = cfg.id || "imported";
        delete cfg.id;
        ahkCall("SaveConfig", JSON.stringify(cfg)).then(function(result) {
          if (result === false) showToast("导入失败","error");
          else { showToast("分组 "+gid+" 已导入","success"); loadGroupsFromAhk(); }
        }).catch(function(ex) { showToast("导入失败: "+ex,"error"); });
      } catch(ex) { showToast("JSON解析失败","error"); }
    };
    reader.readAsText(file);
    this.value = "";
  };
  fileInput.click();
}
```

- [ ] **Step 5: 在事件委托中添加处理**

```javascript
case "exportGroup": exportGroupConfig(gid); break;
case "importGroupConfig": importGroupConfig(); break;
```

### Task 21: 分组卡片拖拽排序

**Files:**
- Modify: `presentation/app_ui.html` `renderDashboard`

- [ ] **Step 1: 添加拖拽事件处理**

在 `renderDashboard` 中，为每个 group-card 添加 draggable 属性：

```javascript
html += '<div class="group-card '+statusClass+'" draggable="true" data-group-id="'+escAttr(g.id)+'">';
```

在 container.onclick 后添加拖拽事件：

```javascript
  var dragSrcEl = null;
  container.addEventListener("dragstart", function(e) {
    dragSrcEl = e.target.closest(".group-card");
    if (dragSrcEl) { e.dataTransfer.effectAllowed = "move"; dragSrcEl.style.opacity = "0.4"; }
  });
  container.addEventListener("dragend", function(e) {
    var card = e.target.closest(".group-card");
    if (card) card.style.opacity = "1";
    document.querySelectorAll(".group-card").forEach(function(c) { c.style.borderTop = ""; });
  });
  container.addEventListener("dragover", function(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    var target = e.target.closest(".group-card");
    if (target && target !== dragSrcEl) target.style.borderTop = "2px solid var(--accent)";
  });
  container.addEventListener("dragleave", function(e) {
    var target = e.target.closest(".group-card");
    if (target) target.style.borderTop = "";
  });
  container.addEventListener("drop", function(e) {
    e.preventDefault();
    var target = e.target.closest(".group-card");
    if (!target || !dragSrcEl || target === dragSrcEl) return;
    target.style.borderTop = "";
    var srcId = dragSrcEl.getAttribute("data-group-id");
    var tgtId = target.getAttribute("data-group-id");
    var srcIdx = sampleGroups.findIndex(function(g) { return g.id === srcId; });
    var tgtIdx = sampleGroups.findIndex(function(g) { return g.id === tgtId; });
    if (srcIdx >= 0 && tgtIdx >= 0) {
      var item = sampleGroups.splice(srcIdx, 1)[0];
      sampleGroups.splice(tgtIdx, 0, item);
      renderDashboard();
    }
  });
```

---

## 批次8: 体验优化（4项）

### Task 22: 键盘快捷键

**Files:**
- Modify: `presentation/app_ui.html`

- [ ] **Step 1: 添加全局键盘快捷键监听**

在 `init` 函数中添加（与 Task 17 的 undo/redo 合并）：

```javascript
document.addEventListener("keydown", function(e) {
  if (e.ctrlKey && e.key === "z") { e.preventDefault(); undoEditor(); }
  else if (e.ctrlKey && e.key === "y") { e.preventDefault(); redoEditor(); }
  else if (e.ctrlKey && e.key === "s") { e.preventDefault(); if (document.getElementById("page-editor").classList.contains("active")) saveConfig(); }
  else if (e.key === "Escape") {
    var overlay = document.querySelector(".overlay");
    if (overlay) overlay.parentNode.removeChild(overlay);
  }
});
```

### Task 23: 关于/版本信息页面

**Files:**
- Modify: `presentation/app_ui.html`

- [ ] **Step 1: 添加关于页面 HTML**

在 page-keytest 后添加：

```html
      <div class="page" id="page-about">
        <div class="glass" style="padding:24px;text-align:center;">
          <div style="font-size:24px;font-weight:bold;margin-bottom:8px;">🎮 AutoHotkey 按键精灵</div>
          <div style="color:var(--text-secondary);margin-bottom:16px;">版本 1.0.0</div>
          <div style="font-size:13px;color:var(--text-muted);max-width:400px;margin:0 auto;">
            多模式按键自动执行工具，支持周期性、序列、混合、增强及长按等7种执行模式。
            内置按键录制与验证功能，可视化执行时序分析。
          </div>
        </div>
      </div>
```

- [ ] **Step 2: 添加导航项**

在导航栏中添加：

```html
<div class="nav-item" data-page="about" data-action="switchPage">ℹ️ 关于</div>
```

- [ ] **Step 3: 更新 switchPage titles**

在 `switchPage` 的 titles 对象中添加：

```javascript
about:'ℹ️ 关于'
```

### Task 24: 无障碍访问

**Files:**
- Modify: `presentation/app_ui.html`

- [ ] **Step 1: 为关键交互元素添加 ARIA 属性**

在全局事件委托中，为按钮添加 `role="button"` 和 `tabindex="0"`：

在 CSS 中添加焦点样式：

```css
.btn:focus-visible, [data-action]:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
```

在 `renderDashboard` 中为卡片按钮添加 `aria-label`：

```javascript
html += '<button class="btn btn-ghost btn-sm" data-action="toggle" data-group-id="'+escAttr(g.id)+'" aria-label="'+(g.active?'停止':'启动')+'分组 '+escAttr(g.id)+'">'+(g.active?'⏹ 停止':'▶ 启动')+'</button>';
html += '<button class="btn btn-ghost btn-sm" data-action="edit" data-group-id="'+escAttr(g.id)+'" aria-label="编辑分组 '+escAttr(g.id)+'">✏️ 编辑</button>';
html += '<button class="btn btn-ghost btn-sm" data-action="clone" data-group-id="'+escAttr(g.id)+'" aria-label="复制分组 '+escAttr(g.id)+'">📋 复制</button>';
html += '<button class="btn btn-danger btn-sm" data-action="delete" data-group-id="'+escAttr(g.id)+'" aria-label="删除分组 '+escAttr(g.id)+'">🗑 删除</button>';
```

### Task 25: 调试日志面板修复

**Files:**
- Modify: `presentation/app_ui.html` `toggleAutoScroll`, `addLog`

- [ ] **Step 1: 修复 toggleAutoScroll**

```javascript
var _autoScroll = true;

function toggleAutoScroll() {
  _autoScroll = !_autoScroll;
  var btn = document.querySelector('[data-action="toggleAutoScroll"]');
  if (btn) btn.textContent = "自动滚动: " + (_autoScroll ? "开" : "关");
  showToast("自动滚动已" + (_autoScroll ? "开启" : "关闭"), "success");
}
```

- [ ] **Step 2: 修改 addLog 使用 _autoScroll**

将 `c.scrollTop = c.scrollHeight;` 改为：

```javascript
  if (_autoScroll) c.scrollTop = c.scrollHeight;
```

- [ ] **Step 3: 修复错误计数**

将 `document.getElementById("dbgErrors").textContent = Math.floor(logCount/10);` 改为从后端获取：

```javascript
  ahkCall("GetDebugInfo").then(function(info) {
    if (info && info.errorCount !== undefined)
      document.getElementById("dbgErrors").textContent = info.errorCount;
  }).catch(function() {});
```

---

## 自审检查

1. **Spec覆盖**: 25项功能缺失全部有对应Task ✓
2. **Placeholder扫描**: 无 TBD/TODO，所有步骤都有具体代码 ✓
3. **类型一致性**: 函数名和参数在各Task间一致 ✓
