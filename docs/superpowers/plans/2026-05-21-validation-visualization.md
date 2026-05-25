# 验证数据直观性全面重构 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用Chart.js替代Canvas手绘，实现4种专业图表+交互式时间轴+实时统计面板，修复停止验证按钮Bug

**Architecture:** 在app_ui.html中内嵌Chart.js 4.x，替换现有drawTimeline函数为Chart.js时间轴，重构showValReport为4图表布局，增加实时统计面板和验证事件列表

**Tech Stack:** Chart.js 4.x (内嵌), HTML5 Canvas, CSS Grid/Flexbox

---

### Task 1: 内嵌Chart.js并替换HTML结构

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:1-460` (HTML部分)

- [ ] **Step 1: 下载Chart.js精简版并内嵌到HTML**

在`<head>`标签结束前添加Chart.js内嵌脚本。使用Chart.js 4.x的UMD精简版(仅含core+bar+radar+tooltip+legend模块)。

在`</head>`前添加:
```html
<script>
/* Chart.js 4.x Minimal Build - core+bar+radar+tooltip+legend */
/* 内嵌精简版Chart.js代码 */
</script>
```

注意: 由于Chart.js完整版约200KB+，这里使用CDN fallback策略 - 先尝试从本地加载，失败则使用内嵌的最小化渲染函数。实际做法是在script标签中内嵌一个轻量级图表渲染器(约15KB)，支持bar/radar两种图表类型。

- [ ] **Step 2: 替换验证面板HTML结构**

将`panel-validate`的HTML替换为包含4个图表canvas的新结构:

找到现有验证面板(约第425-444行):
```html
<div class="keytest-panel" id="panel-validate" style="display:none;">
  ...
  <canvas id="valCanvas" ...></canvas>
  <div id="valReport" style="display:none;">
    <div id="valReportContent" ...></div>
  </div>
</div>
```

替换为:
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
  <div id="valLiveStats" style="display:none;background:var(--bg-secondary);border-radius:8px;padding:8px 12px;margin-bottom:12px;font-size:12px;">
    <span>事件: <b id="valLiveCount">0</b></span> |
    <span>发送率: <b id="valLiveRate">-</b></span> |
    <span>平均偏差: <b id="valLiveAvgDev">-</b></span> |
    <span>最差偏差: <b id="valLiveMaxDev">-</b></span> |
    <span>时长: <b id="valLiveDuration">0</b>s</span>
  </div>
  <div style="background:var(--bg-secondary);border-radius:8px;padding:8px;margin-bottom:12px;">
    <canvas id="valTimeline" style="width:100%;height:200px;"></canvas>
  </div>
  <div id="valEventList" style="max-height:150px;overflow-y:auto;font-size:12px;font-family:monospace;margin-bottom:12px;"></div>
  <div id="valReport" style="display:none;">
    <div class="section-label" style="margin-bottom:8px;">验证报告</div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:12px;">
      <div style="background:var(--bg-secondary);border-radius:8px;padding:8px;">
        <div style="font-size:11px;color:var(--text-secondary);margin-bottom:4px;">综合评分</div>
        <canvas id="radarCanvas" style="width:100%;height:220px;"></canvas>
      </div>
      <div style="background:var(--bg-secondary);border-radius:8px;padding:8px;">
        <div style="font-size:11px;color:var(--text-secondary);margin-bottom:4px;">偏差分布</div>
        <canvas id="deviationCanvas" style="width:100%;height:220px;"></canvas>
      </div>
    </div>
    <div style="background:var(--bg-secondary);border-radius:8px;padding:8px;margin-bottom:12px;">
      <div style="font-size:11px;color:var(--text-secondary);margin-bottom:4px;">间隔对比</div>
      <canvas id="intervalCanvas" style="width:100%;height:200px;"></canvas>
    </div>
    <div style="background:var(--bg-secondary);border-radius:8px;padding:8px;">
      <div style="font-size:11px;color:var(--text-secondary);margin-bottom:4px;">长按时序</div>
      <canvas id="holdCanvas" style="width:100%;height:160px;"></canvas>
    </div>
  </div>
</div>
```

- [ ] **Step 3: 替换录制面板Canvas**

将`recCanvas`替换为Chart.js兼容的canvas:
```html
<div style="background:var(--bg-secondary);border-radius:8px;padding:8px;margin-bottom:12px;">
  <canvas id="recTimeline" style="width:100%;height:200px;"></canvas>
</div>
```

- [ ] **Step 4: 添加disabled按钮CSS样式**

在`<style>`标签中添加:
```css
.btn:disabled, .btn[disabled] {
  opacity: 0.5;
  cursor: not-allowed;
  pointer-events: none;
}
```

---

### Task 2: 实现轻量级图表渲染器

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:461-470` (script开头)

- [ ] **Step 1: 在script标签开头添加MiniChart渲染器**

在`<script>`标签开头(约第461行后)添加轻量级图表渲染器。不依赖外部Chart.js，纯Canvas 2D实现4种图表:

```javascript
var MiniChart = {
  _charts: {},

  create: function(canvasId, type, data, options) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return null;
    var ctx = canvas.getContext("2d");
    var chart = { canvas: canvas, ctx: ctx, type: type, data: data, options: options || {} };
    this._charts[canvasId] = chart;
    this._resizeCanvas(canvas);
    this.render(canvasId);
    return chart;
  },

  update: function(canvasId, data) {
    var chart = this._charts[canvasId];
    if (!chart) return;
    chart.data = data;
    this.render(canvasId);
  },

  destroy: function(canvasId) {
    delete this._charts[canvasId];
  },

  _resizeCanvas: function(canvas) {
    var rect = canvas.getBoundingClientRect();
    var dpr = window.devicePixelRatio || 1;
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    canvas.getContext("2d").scale(dpr, dpr);
  },

  render: function(canvasId) {
    var chart = this._charts[canvasId];
    if (!chart) return;
    var ctx = chart.ctx;
    var w = chart.canvas.getBoundingClientRect().width;
    var h = chart.canvas.getBoundingClientRect().height;
    ctx.clearRect(0, 0, w, h);
    switch (chart.type) {
      case "timeline": this._renderTimeline(chart, w, h); break;
      case "radar": this._renderRadar(chart, w, h); break;
      case "bar": this._renderBar(chart, w, h); break;
      case "hbar": this._renderHBar(chart, w, h); break;
    }
  },

  _renderTimeline: function(chart, w, h) {
    var ctx = chart.ctx;
    var events = chart.data.events || [];
    var expected = chart.data.expected || [];
    var pad = { top: 20, right: 20, bottom: 30, left: 60 };
    var plotW = w - pad.left - pad.right;
    var plotH = h - pad.top - pad.bottom;

    if (events.length === 0 && expected.length === 0) {
      ctx.fillStyle = "#888";
      ctx.font = "13px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("等待事件...", w / 2, h / 2);
      return;
    }

    var allEvents = events.concat(expected.map(function(e) { e._expected = true; return e; }));
    var maxTs = 100;
    for (var i = 0; i < allEvents.length; i++) {
      if (allEvents[i].timestamp > maxTs) maxTs = allEvents[i].timestamp;
    }
    maxTs = Math.ceil(maxTs / 50) * 50;

    var keySet = {};
    var keyOrder = [];
    for (var i = 0; i < events.length; i++) {
      if (!keySet[events[i].key]) { keySet[events[i].key] = true; keyOrder.push(events[i].key); }
    }
    for (var i = 0; i < expected.length; i++) {
      if (!keySet[expected[i].key]) { keySet[expected[i].key] = true; keyOrder.push(expected[i].key); }
    }

    var laneH = Math.min(24, plotH / Math.max(keyOrder.length, 1));

    ctx.strokeStyle = "#444";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(pad.left, h - pad.bottom);
    ctx.lineTo(w - pad.right, h - pad.bottom);
    ctx.stroke();

    ctx.fillStyle = "#888";
    ctx.font = "10px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("0ms", pad.left, h - pad.bottom + 14);
    ctx.fillText(maxTs + "ms", w - pad.right, h - pad.bottom + 14);

    for (var ki = 0; ki < keyOrder.length; ki++) {
      var key = keyOrder[ki];
      var y = pad.top + ki * laneH + laneH / 2;
      ctx.fillStyle = "#aaa";
      ctx.font = "10px monospace";
      ctx.textAlign = "right";
      ctx.fillText(key, pad.left - 6, y + 3);
    }

    var downMap = {};
    for (var i = 0; i < events.length; i++) {
      var e = events[i];
      var x = pad.left + (e.timestamp / maxTs) * plotW;
      var ki = keyOrder.indexOf(e.key);
      if (ki < 0) continue;
      var y = pad.top + ki * laneH + laneH / 2;
      var color = e.device === "mouse" ? "#2196F3" : "#4CAF50";

      if (e.event === "down") {
        downMap[e.key] = { x: x, ts: e.timestamp, y: y, color: color };
      } else if (e.event === "up" && downMap[e.key]) {
        var down = downMap[e.key];
        var barW = x - down.x;
        if (barW < 3) barW = 3;
        ctx.fillStyle = down.color;
        ctx.globalAlpha = 0.35;
        ctx.fillRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6);
        ctx.globalAlpha = 1;
        ctx.strokeStyle = down.color;
        ctx.lineWidth = 1.5;
        ctx.strokeRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6);
        var dur = e.timestamp - down.ts;
        if (barW > 30) {
          ctx.fillStyle = "#fff";
          ctx.font = "9px sans-serif";
          ctx.textAlign = "center";
          ctx.fillText(dur + "ms", down.x + barW / 2, down.y + 3);
        }
        delete downMap[e.key];
      } else {
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(x, y, 4, 0, Math.PI * 2);
        ctx.fill();
      }

      if (i > 0) {
        var prev = events[i - 1];
        var px = pad.left + (prev.timestamp / maxTs) * plotW;
        var interval = e.timestamp - prev.timestamp;
        if (interval > 0 && interval < maxTs) {
          var midX = (px + x) / 2;
          ctx.fillStyle = "rgba(255,255,255,0.4)";
          ctx.font = "9px sans-serif";
          ctx.textAlign = "center";
          var prevKi = keyOrder.indexOf(prev.key);
          var labelY = pad.top + prevKi * laneH - 2;
          ctx.fillText(interval + "ms", midX, labelY);
        }
      }
    }

    for (var key in downMap) {
      var down = downMap[key];
      var endX = w - pad.right;
      var barW = endX - down.x;
      if (barW < 3) barW = 3;
      ctx.fillStyle = "#FF5722";
      ctx.globalAlpha = 0.25;
      ctx.fillRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6);
      ctx.globalAlpha = 1;
      ctx.strokeStyle = "#FF5722";
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.strokeRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6);
      ctx.setLineDash([]);
    }

    if (expected.length > 0) {
      var expDownMap = {};
      for (var i = 0; i < expected.length; i++) {
        var e = expected[i];
        var x = pad.left + (e.timestamp / maxTs) * plotW;
        var ki = keyOrder.indexOf(e.key);
        if (ki < 0) continue;
        var y = pad.top + ki * laneH + laneH / 2;
        if (e.event === "down") {
          expDownMap[e.key] = { x: x, y: y };
        } else if (e.event === "up" && expDownMap[e.key]) {
          var down = expDownMap[e.key];
          var barW = x - down.x;
          if (barW < 3) barW = 3;
          ctx.strokeStyle = "rgba(255,255,255,0.25)";
          ctx.lineWidth = 1;
          ctx.setLineDash([3, 3]);
          ctx.strokeRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6);
          ctx.setLineDash([]);
          delete expDownMap[e.key];
        }
      }
    }
  },

  _renderRadar: function(chart, w, h) {
    var ctx = chart.ctx;
    var data = chart.data;
    var labels = data.labels || [];
    var values = data.values || [];
    var cx = w / 2;
    var cy = h / 2 + 10;
    var r = Math.min(w, h) / 2 - 40;
    var n = labels.length;
    if (n < 3) return;

    ctx.strokeStyle = "#444";
    ctx.lineWidth = 1;
    for (var ring = 1; ring <= 4; ring++) {
      var rr = r * ring / 4;
      ctx.beginPath();
      for (var i = 0; i <= n; i++) {
        var angle = (Math.PI * 2 * (i % n)) / n - Math.PI / 2;
        var px = cx + rr * Math.cos(angle);
        var py = cy + rr * Math.sin(angle);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
      ctx.stroke();
    }

    for (var i = 0; i < n; i++) {
      var angle = (Math.PI * 2 * i) / n - Math.PI / 2;
      ctx.strokeStyle = "#555";
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + r * Math.cos(angle), cy + r * Math.sin(angle));
      ctx.stroke();
      ctx.fillStyle = "#aaa";
      ctx.font = "10px sans-serif";
      ctx.textAlign = "center";
      var lx = cx + (r + 18) * Math.cos(angle);
      var ly = cy + (r + 18) * Math.sin(angle);
      ctx.fillText(labels[i], lx, ly + 3);
    }

    ctx.beginPath();
    for (var i = 0; i <= n; i++) {
      var idx = i % n;
      var angle = (Math.PI * 2 * idx) / n - Math.PI / 2;
      var v = (values[idx] || 0) / 100;
      var px = cx + r * v * Math.cos(angle);
      var py = cy + r * v * Math.sin(angle);
      if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.fillStyle = "rgba(76,175,80,0.25)";
    ctx.fill();
    ctx.strokeStyle = "#4CAF50";
    ctx.lineWidth = 2;
    ctx.stroke();

    for (var i = 0; i < n; i++) {
      var angle = (Math.PI * 2 * i) / n - Math.PI / 2;
      var v = (values[i] || 0) / 100;
      var px = cx + r * v * Math.cos(angle);
      var py = cy + r * v * Math.sin(angle);
      ctx.fillStyle = "#4CAF50";
      ctx.beginPath();
      ctx.arc(px, py, 4, 0, Math.PI * 2);
      ctx.fill();
    }

    if (data.score != null) {
      ctx.fillStyle = "#fff";
      ctx.font = "bold 24px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(data.score, cx, cy + 4);
      ctx.font = "10px sans-serif";
      ctx.fillStyle = "#aaa";
      ctx.fillText("综合评分", cx, cy + 18);
    }
  },

  _renderBar: function(chart, w, h) {
    var ctx = chart.ctx;
    var data = chart.data;
    var labels = data.labels || [];
    var values = data.values || [];
    var colors = data.colors || [];
    var avgLine = data.avgLine;
    var pad = { top: 10, right: 20, bottom: 30, left: 40 };
    var plotW = w - pad.left - pad.right;
    var plotH = h - pad.top - pad.bottom;
    var n = labels.length;
    if (n === 0) return;

    var maxVal = 0;
    for (var i = 0; i < values.length; i++) { if (values[i] > maxVal) maxVal = values[i]; }
    maxVal = Math.max(maxVal, 100);
    maxVal = Math.ceil(maxVal / 25) * 25;

    ctx.strokeStyle = "#444";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(pad.left, h - pad.bottom);
    ctx.lineTo(w - pad.right, h - pad.bottom);
    ctx.stroke();

    for (var g = 0; g <= 4; g++) {
      var gy = h - pad.bottom - (plotH * g / 4);
      ctx.strokeStyle = "#333";
      ctx.beginPath();
      ctx.moveTo(pad.left, gy);
      ctx.lineTo(w - pad.right, gy);
      ctx.stroke();
      ctx.fillStyle = "#888";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.fillText(Math.round(maxVal * g / 4) + "%", pad.left - 4, gy + 3);
    }

    var barW = Math.min(30, (plotW / n) * 0.7);
    var gap = (plotW - barW * n) / (n + 1);
    for (var i = 0; i < n; i++) {
      var x = pad.left + gap + i * (barW + gap);
      var barH = (values[i] / maxVal) * plotH;
      var y = h - pad.bottom - barH;
      ctx.fillStyle = colors[i] || "#4CAF50";
      ctx.fillRect(x, y, barW, barH);
      ctx.fillStyle = "#aaa";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(labels[i], x + barW / 2, h - pad.bottom + 12);
      ctx.fillStyle = "#fff";
      ctx.font = "9px sans-serif";
      ctx.fillText(values[i] + "%", x + barW / 2, y - 4);
    }

    if (avgLine != null) {
      var avgY = h - pad.bottom - (avgLine / maxVal) * plotH;
      ctx.strokeStyle = "#FF9800";
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(pad.left, avgY);
      ctx.lineTo(w - pad.right, avgY);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = "#FF9800";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.fillText("avg " + avgLine + "%", w - pad.right + 2, avgY + 3);
    }
  },

  _renderHBar: function(chart, w, h) {
    var ctx = chart.ctx;
    var data = chart.data;
    var labels = data.labels || [];
    var values = data.values || [];
    var expectedValues = data.expectedValues || [];
    var colors = data.colors || [];
    var pad = { top: 10, right: 40, bottom: 10, left: 60 };
    var plotW = w - pad.left - pad.right;
    var plotH = h - pad.top - pad.bottom;
    var n = labels.length;
    if (n === 0) return;

    var maxVal = 0;
    for (var i = 0; i < values.length; i++) { if (values[i] > maxVal) maxVal = values[i]; }
    for (var i = 0; i < expectedValues.length; i++) { if (expectedValues[i] > maxVal) maxVal = expectedValues[i]; }
    maxVal = Math.max(maxVal, 50);
    maxVal = Math.ceil(maxVal / 50) * 50;

    var barH = Math.min(16, (plotH / n) * 0.6);
    var gap = (plotH - barH * n) / (n + 1);
    var hasExpected = expectedValues.length > 0;
    var groupW = hasExpected ? plotW * 0.45 : plotW;

    for (var i = 0; i < n; i++) {
      var y = pad.top + gap + i * (barH + gap);
      ctx.fillStyle = "#aaa";
      ctx.font = "10px monospace";
      ctx.textAlign = "right";
      ctx.fillText(labels[i], pad.left - 6, y + barH / 2 + 3);

      if (hasExpected) {
        var expW = (expectedValues[i] / maxVal) * groupW;
        ctx.fillStyle = "rgba(255,255,255,0.15)";
        ctx.fillRect(pad.left, y, expW, barH);
        ctx.strokeStyle = "rgba(255,255,255,0.3)";
        ctx.lineWidth = 1;
        ctx.strokeRect(pad.left, y, expW, barH);
      }

      var valW = (values[i] / maxVal) * groupW;
      var offset = hasExpected ? groupW + 10 : 0;
      ctx.fillStyle = colors[i] || "#4CAF50";
      ctx.fillRect(pad.left + offset, y, valW, barH);
      ctx.fillStyle = "#fff";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.fillText(values[i] + "ms", pad.left + offset + valW + 4, y + barH / 2 + 3);
    }
  }
};
```

- [ ] **Step 2: 验证MiniChart基本渲染**

在浏览器控制台测试: `MiniChart.create("radarCanvas", "radar", {labels:["A","B","C","D","E"], values:[80,90,70,60,85], score:77})`

---

### Task 3: 替换drawTimeline为MiniChart时间轴

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:1358-1497` (drawTimeline函数)

- [ ] **Step 1: 删除旧drawTimeline函数**

删除整个`drawTimeline`函数(约第1372-1497行)。

- [ ] **Step 2: 替换为MiniChart时间轴调用**

添加新函数:
```javascript
function drawTimeline(canvasId, events) {
  var chartId = canvasId;
  var isValidate = canvasId === "valCanvas" || canvasId === "valTimeline";
  var expected = isValidate && _valExpectedSeq ? _valExpectedSeq : [];
  MiniChart.destroy(chartId);
  MiniChart.create(chartId, "timeline", { events: events, expected: expected });
}
```

- [ ] **Step 3: 更新initKeyTestPage中的canvas ID引用**

将`initKeyTestPage`中的:
```javascript
drawTimeline("recCanvas", []);
drawTimeline("valCanvas", []);
```
替换为:
```javascript
drawTimeline("recTimeline", []);
drawTimeline("valTimeline", []);
```

- [ ] **Step 4: 更新onBridgeEvent中的canvas ID引用**

将`onBridgeEvent`中的:
```javascript
drawTimeline("recCanvas", _recEvents);
drawTimeline("valCanvas", _valEvents);
```
替换为:
```javascript
drawTimeline("recTimeline", _recEvents);
drawTimeline("valTimeline", _valEvents);
```

---

### Task 4: 重构showValReport为4图表布局

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:1680-1712` (showValReport函数)

- [ ] **Step 1: 替换showValReport函数**

删除旧`showValReport`函数，替换为:
```javascript
function showValReport(report) {
  if (!report) return;
  document.getElementById("valReport").style.display = "block";

  var orderScore = report.orderCorrect ? 100 : 0;
  var rateScore = Math.round((report.sendSuccessRate != null ? report.sendSuccessRate : 0) * 100);
  var avgDevScore = Math.max(0, 100 - (report.avgIntervalDeviation || 0));
  var maxDevScore = Math.max(0, 100 - (report.maxIntervalDeviation || 0));
  var holdScore = report.holdTimingCorrect ? 100 : 0;
  var totalScore = Math.round((orderScore + rateScore + avgDevScore + maxDevScore + holdScore) / 5);

  MiniChart.destroy("radarCanvas");
  MiniChart.create("radarCanvas", "radar", {
    labels: ["顺序", "发送率", "平均偏差", "最大偏差", "长按时序"],
    values: [orderScore, rateScore, avgDevScore, maxDevScore, holdScore],
    score: totalScore
  });

  var details = report.details || [];
  var devLabels = [];
  var devValues = [];
  var devColors = [];
  var devSum = 0;
  for (var i = 0; i < details.length; i++) {
    devLabels.push("#" + (i + 1));
    devValues.push(details[i].deviation || 0);
    devSum += details[i].deviation || 0;
    devColors.push(details[i].status === "good" ? "#4CAF50" : (details[i].status === "acceptable" ? "#FF9800" : "#FF5722"));
  }
  var devAvg = details.length > 0 ? Math.round(devSum / details.length) : 0;

  MiniChart.destroy("deviationCanvas");
  MiniChart.create("deviationCanvas", "bar", {
    labels: devLabels,
    values: devValues,
    colors: devColors,
    avgLine: devAvg
  });

  var intLabels = [];
  var intValues = [];
  var intExpected = [];
  var intColors = [];
  for (var i = 0; i < details.length; i++) {
    intLabels.push(details[i].key || ("#" + (i + 1)));
    intValues.push(details[i].actualInterval || 0);
    intExpected.push(details[i].expectedInterval || 0);
    intColors.push(details[i].status === "good" ? "#4CAF50" : (details[i].status === "acceptable" ? "#FF9800" : "#FF5722"));
  }

  MiniChart.destroy("intervalCanvas");
  MiniChart.create("intervalCanvas", "hbar", {
    labels: intLabels,
    values: intValues,
    expectedValues: intExpected,
    colors: intColors
  });

  MiniChart.destroy("holdCanvas");
  var holdCtx = document.getElementById("holdCanvas").getContext("2d");
  var hw = document.getElementById("holdCanvas").getBoundingClientRect().width;
  var hh = document.getElementById("holdCanvas").getBoundingClientRect().height;
  holdCtx.clearRect(0, 0, hw, hh);
  holdCtx.fillStyle = "#888";
  holdCtx.font = "12px sans-serif";
  holdCtx.textAlign = "center";
  holdCtx.fillText(report.holdTimingCorrect ? "✓ 长按时序全部正常" : "✗ 存在长按时序异常", hw / 2, hh / 2);
}
```

---

### Task 5: 实现实时统计面板和验证事件列表

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:1321-1340` (onBridgeEvent函数)

- [ ] **Step 1: 更新onBridgeEvent增加实时统计和事件列表**

替换`onBridgeEvent`函数:
```javascript
function onBridgeEvent(evt) {
  if (!evt || !evt.type) return;
  if (evt.type === "keyRecordEvent" && evt.data) {
    _recEvents.push(evt.data);
    document.getElementById("recEventCount").textContent = _recEvents.length;
    drawTimeline("recTimeline", _recEvents);
    appendRecEvent(evt.data);
    updateRecStats();
  } else if (evt.type === "keySendEvent" && evt.data) {
    _valEvents.push(evt.data);
    document.getElementById("valEventCount").textContent = _valEvents.length;
    drawTimeline("valTimeline", _valEvents);
    appendValEvent(evt.data);
    updateValLiveStats();
  }
}
```

- [ ] **Step 2: 添加appendValEvent函数**

在`appendRecEvent`函数后添加:
```javascript
function appendValEvent(evt) {
  var list = document.getElementById("valEventList");
  if (!list) return;
  var line = document.createElement("div");
  line.style.padding = "2px 0";
  line.style.borderBottom = "1px solid var(--border)";
  var dev = evt.device === "mouse" ? "🖱" : "⌨";
  var ev = evt.event === "down" ? "↓" : (evt.event === "up" ? "↑" : "●");
  var devColor = evt.device === "mouse" ? "#2196F3" : "#4CAF50";
  line.innerHTML = '<span style="color:' + devColor + '">' + dev + " " + ev + "</span> " + escHtml(evt.key) + "  " + evt.timestamp + "ms";
  list.appendChild(line);
  list.scrollTop = list.scrollHeight;
}
```

- [ ] **Step 3: 添加updateValLiveStats函数**

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
    for (var i = 1; i < n; i++) {
      var interval = _valEvents[i].timestamp - _valEvents[i - 1].timestamp;
      var expected = 50;
      var dev = Math.abs(interval - expected) / expected * 100;
      sumDev += dev;
      if (dev > maxDev) maxDev = dev;
      devCount++;
    }
    document.getElementById("valLiveAvgDev").textContent = devCount > 0 ? (sumDev / devCount).toFixed(1) + "%" : "-";
    document.getElementById("valLiveMaxDev").textContent = maxDev.toFixed(1) + "%";
  }
  var firstTs = _valEvents.length > 0 ? _valEvents[0].timestamp : 0;
  var lastTs = _valEvents.length > 0 ? _valEvents[_valEvents.length - 1].timestamp : 0;
  document.getElementById("valLiveDuration").textContent = ((lastTs - firstTs) / 1000).toFixed(1);
  var totalExpected = _valExpectedCount || 0;
  if (totalExpected > 0) {
    document.getElementById("valLiveRate").textContent = Math.min(100, Math.round(n / totalExpected * 100)) + "%";
  }
}
```

---

### Task 6: 修复停止验证按钮Bug

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:1610-1680` (startValidation/stopValidation函数)

- [ ] **Step 1: 重写startValidation函数**

替换`startValidation`函数:
```javascript
function startValidation() {
  var gid = document.getElementById("validateGroupId").value;
  if (!gid) {
    showToast("请先选择分组", "error");
    return;
  }
  _valEvents = [];
  _valExpectedSeq = [];
  _valExpectedCount = 0;
  _isValidating = true;
  document.getElementById("valEventList").innerHTML = "";
  document.getElementById("valEventCount").textContent = "0";
  document.getElementById("valStatus").textContent = "验证中...";
  document.getElementById("valStatus").style.color = "#4CAF50";
  document.getElementById("valReport").style.display = "none";
  document.getElementById("valLiveStats").style.display = "";
  document.querySelector('[data-action="startValidation"]').disabled = true;
  document.querySelector('[data-action="stopValidation"]').disabled = false;
  drawTimeline("valTimeline", []);
  ahkCall("StartValidation", {groupId: gid}).then(function(r) {
    if (r === -1) {
      showToast("分组不存在，请检查分组ID", "error");
      resetValUI();
    } else if (r !== 1) {
      showToast("验证启动失败(可能已有验证在运行)", "error");
      resetValUI();
    } else {
      try {
        var group = SkillManager_Groups ? SkillManager_Groups[gid] : null;
        if (group) {
          _valExpectedCount = (group.keys || group.pressKeys || []).length;
        }
      } catch(e) {}
    }
  }).catch(function(e) {
    resetValUI();
    showToast("启动验证失败: " + e, "error");
  });
}
```

- [ ] **Step 2: 重写stopValidation函数增加超时保护**

替换`stopValidation`函数:
```javascript
function stopValidation() {
  var gid = document.getElementById("validateGroupId").value;
  var btn = document.querySelector('[data-action="stopValidation"]');
  btn.textContent = "⏳ 停止中...";
  btn.disabled = true;

  var timeoutId = setTimeout(function() {
    _isValidating = false;
    document.getElementById("valStatus").textContent = "已停止(超时)";
    document.getElementById("valStatus").style.color = "#FF9800";
    document.querySelector('[data-action="startValidation"]').disabled = false;
    btn.textContent = "⏹ 停止验证";
    btn.disabled = true;
    showToast("停止验证超时，已强制重置", "warning");
  }, 3000);

  ahkCall("StopValidation", {groupId: gid}).then(function(r) {
    clearTimeout(timeoutId);
    _isValidating = false;
    document.getElementById("valStatus").textContent = "已完成";
    document.getElementById("valStatus").style.color = "#4CAF50";
    document.querySelector('[data-action="startValidation"]').disabled = false;
    btn.textContent = "⏹ 停止验证";
    btn.disabled = true;
    document.getElementById("valLiveStats").style.display = "none";
    try {
      var report = typeof r === "string" ? JSON.parse(r) : r;
      if (report && report.groupId) {
        showValReport(report);
      }
    } catch (ex) {
      showToast("报告解析失败", "error");
    }
    showToast("验证完成，共 " + _valEvents.length + " 个事件");
  }).catch(function(e) {
    clearTimeout(timeoutId);
    resetValUI();
    btn.textContent = "⏹ 停止验证";
    showToast("停止验证失败: " + e, "error");
  });
}
```

- [ ] **Step 3: 更新resetValUI函数**

替换`resetValUI`函数:
```javascript
function resetValUI() {
  _isValidating = false;
  document.getElementById("valStatus").textContent = "就绪";
  document.getElementById("valStatus").style.color = "";
  document.getElementById("valLiveStats").style.display = "none";
  document.querySelector('[data-action="startValidation"]').disabled = false;
  var stopBtn = document.querySelector('[data-action="stopValidation"]');
  stopBtn.disabled = true;
  stopBtn.textContent = "⏹ 停止验证";
}
```

---

### Task 7: 更新全局变量和初始化

**Files:**
- Modify: `D:\1demo\AutoHotkeydemo\presentation\app_ui.html:465-480` (全局变量区)

- [ ] **Step 1: 添加新的全局变量**

在全局变量区添加:
```javascript
var _valExpectedSeq = [];
var _valExpectedCount = 0;
```

- [ ] **Step 2: 更新initKeyTestPage函数**

确保`initKeyTestPage`正确初始化新组件:
```javascript
function initKeyTestPage() {
  var tabs = document.querySelectorAll(".keytest-tab");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].addEventListener("click", function() {
      for (var j = 0; j < tabs.length; j++) {
        tabs[j].classList.remove("active");
        tabs[j].classList.remove("btn-primary");
        tabs[j].classList.add("btn-ghost");
      }
      this.classList.add("active");
      this.classList.remove("btn-ghost");
      this.classList.add("btn-primary");
      var tab = this.getAttribute("data-tab");
      document.getElementById("panel-record").style.display = tab === "record" ? "" : "none";
      document.getElementById("panel-validate").style.display = tab === "validate" ? "" : "none";
      setTimeout(function() {
        MiniChart._resizeCanvas(document.getElementById("recTimeline"));
        MiniChart._resizeCanvas(document.getElementById("valTimeline"));
        drawTimeline("recTimeline", _recEvents);
        drawTimeline("valTimeline", _valEvents);
      }, 50);
    });
  }
  drawTimeline("recTimeline", []);
  drawTimeline("valTimeline", []);
  refreshGroupList();
}
```

---

### Task 8: 运行验证

**Files:** 无修改

- [ ] **Step 1: 停止旧进程并启动程序**

```powershell
Get-Process -Name AutoHotkey* | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process -FilePath 'D:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe' -ArgumentList 'D:\1demo\AutoHotkeydemo\main.ahk'
```

- [ ] **Step 2: 检查日志无错误**

```powershell
Get-Content 'D:\1demo\AutoHotkeydemo\logs\errors.log' -Tail 5
Get-Content 'D:\1demo\AutoHotkeydemo\logs\debug.log' -Tail 10
```

预期: 无JavaScript错误，程序正常启动

- [ ] **Step 3: 功能测试清单**

1. 打开按键测试页面
2. 点击"验证"标签页 → 应能正常切换
3. 选择分组 → 下拉列表应非空
4. 点击"开始验证" → 实时统计面板应显示
5. 验证过程中 → 时间轴应实时更新
6. 点击"停止验证" → 应显示4种图表报告
7. 录制面板时间轴也应正常工作
