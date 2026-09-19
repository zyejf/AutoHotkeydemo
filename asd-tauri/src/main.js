import * as api from './api.js';

/**
 * 从错误对象提取可读消息。
 * 兼容 AppError 结构化序列化 {kind, message}（I34 之后）与 Error 实例、字符串，
 * 避免 "+ e" 拼接得到 "[object Object]"（R2）。
 *
 * @param {unknown} e - 错误对象，可能是 {kind, message}、Error 实例、字符串等
 * @param {string} [defaultMsg] - 无法提取时的默认消息（对应 extractErrorMessage 的 fallback）
 * @returns {string} 可读的错误消息：非空 message > 字符串 > [kind] > defaultMsg > '未知错误'
 *
 * ⚠️ 同步说明：本函数与 e2e/helpers/error_utils.js 的 extractErrorMessage 逻辑一致，
 * 需同步维护。两者运行环境不同（本函数运行于前端浏览器 WebView，extractErrorMessage
 * 运行于 Node.js E2E 测试环境），且 main.js 不使用 ES module（无法 import），
 * 故无法共享同一实现。修改任一处时必须同步更新另一处。
 */
function errMsg(e, defaultMsg) {
  if (e != null && typeof e.message === 'string' && e.message.length > 0) return e.message;
  if (typeof e === 'string' && e.length > 0) return e;
  // 空 message 但有 kind 时保留 kind 信息（与 extractErrorMessage 的 buildKindFallback 保持同步，Minor #3）
  if (e != null && typeof e === 'object' && typeof e.kind === 'string' && e.kind.length > 0) return '[' + e.kind + ']';
  return defaultMsg || '未知错误';
}

var _safeStorage = {
  get: function(key, def) { try { var v = localStorage.getItem(key); return v !== null ? v : def; } catch(ex) { return def; } },
  set: function(key, val) { try { localStorage.setItem(key, val); } catch(ex) { /* 忽略：localStorage 不可用（隐私模式/配额）时不应影响主流程 */ } }
};

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
    if (rect.width < 1 || rect.height < 1) return;
    var dpr = window.devicePixelRatio || 1;
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    canvas.getContext("2d").setTransform(dpr, 0, 0, dpr, 0, 0);
  },
  render: function(canvasId) {
    var chart = this._charts[canvasId];
    if (!chart) return;
    var rect = chart.canvas.getBoundingClientRect();
    var w = rect.width;
    var h = rect.height;
    if (w < 1 || h < 1) return;
    chart.ctx.clearRect(0, 0, w, h);
    switch (chart.type) {
      case "timeline": this._renderTimeline(chart, w, h); break;
      case "radar": this._renderRadar(chart, w, h); break;
      case "bar": this._renderBar(chart, w, h); break;
      case "hbar": this._renderHBar(chart, w, h); break;
      case "hold": this._renderHold(chart, w, h); break;
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
      ctx.fillStyle = "#888"; ctx.font = "13px sans-serif"; ctx.textAlign = "center";
      ctx.fillText("等待事件...", w / 2, h / 2); return;
    }
    var maxTs = 100;
    for (var i = 0; i < events.length; i++) { if (events[i].timestamp > maxTs) maxTs = events[i].timestamp; }
    for (i = 0; i < expected.length; i++) { if (expected[i].timestamp > maxTs) maxTs = expected[i].timestamp; }
    maxTs = Math.ceil(maxTs / 50) * 50; if (maxTs < 50) maxTs = 50;
    var keySet = {}; var keyOrder = [];
    for (i = 0; i < events.length; i++) { if (!keySet[events[i].key]) { keySet[events[i].key] = true; keyOrder.push(events[i].key); } }
    for (i = 0; i < expected.length; i++) { if (!keySet[expected[i].key]) { keySet[expected[i].key] = true; keyOrder.push(expected[i].key); } }
    var laneH = Math.min(24, plotH / Math.max(keyOrder.length, 1));
    ctx.strokeStyle = "#444"; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(pad.left, h - pad.bottom); ctx.lineTo(w - pad.right, h - pad.bottom); ctx.stroke();
    ctx.fillStyle = "#888"; ctx.font = "10px sans-serif"; ctx.textAlign = "center";
    ctx.fillText("0ms", pad.left, h - pad.bottom + 14);
    ctx.fillText(maxTs + "ms", w - pad.right, h - pad.bottom + 14);
    for (var ki = 0; ki < keyOrder.length; ki++) {
      var key = keyOrder[ki]; var y = pad.top + ki * laneH + laneH / 2;
      ctx.fillStyle = "#aaa"; ctx.font = "10px monospace"; ctx.textAlign = "right";
      ctx.fillText(key, pad.left - 6, y + 3);
    }
    if (expected.length > 0) {
      var expDownMap = {};
      for (i = 0; i < expected.length; i++) {
        var e = expected[i]; var x = pad.left + (e.timestamp / maxTs) * plotW;
        ki = keyOrder.indexOf(e.key); if (ki < 0) continue;
        y = pad.top + ki * laneH + laneH / 2;
        if (e.event === "down") { if (!expDownMap[e.key]) expDownMap[e.key] = []; expDownMap[e.key].push({ x: x, y: y }); }
        else if (e.event === "up" && expDownMap[e.key] && expDownMap[e.key].length > 0) {
          var down = expDownMap[e.key].shift(); var barW = x - down.x; if (barW < 3) barW = 3;
          ctx.strokeStyle = "rgba(255,255,255,0.2)"; ctx.lineWidth = 1; ctx.setLineDash([3, 3]);
          ctx.strokeRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6); ctx.setLineDash([]);
          if (expDownMap[e.key].length === 0) delete expDownMap[e.key];
        } else if (e.event === "up") {
          ctx.fillStyle = "rgba(255,255,255,0.2)"; ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill();
        }
      }
      for (var ek in expDownMap) { var pending = expDownMap[ek]; for (var pi = 0; pi < pending.length; pi++) { ctx.fillStyle = "rgba(255,255,255,0.15)"; ctx.beginPath(); ctx.arc(pending[pi].x, pending[pi].y, 3, 0, Math.PI * 2); ctx.fill(); } }
    }
    var downMap = {};
    for (i = 0; i < events.length; i++) {
      e = events[i]; x = pad.left + (e.timestamp / maxTs) * plotW;
      ki = keyOrder.indexOf(e.key); if (ki < 0) continue;
      y = pad.top + ki * laneH + laneH / 2;
      var color = e.device === "mouse" ? "#2196F3" : "#4CAF50";
      if (e.event === "down") { if (!downMap[e.key]) downMap[e.key] = []; downMap[e.key].push({ x: x, ts: e.timestamp, y: y, color: color }); }
      else if (e.event === "up" && downMap[e.key] && downMap[e.key].length > 0) {
        down = downMap[e.key].shift(); barW = x - down.x; if (barW < 3) barW = 3;
        ctx.fillStyle = down.color; ctx.globalAlpha = 0.35; ctx.fillRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6); ctx.globalAlpha = 1;
        ctx.strokeStyle = down.color; ctx.lineWidth = 1.5; ctx.strokeRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6);
        var dur = e.timestamp - down.ts;
        if (barW > 30) { ctx.fillStyle = "#fff"; ctx.font = "9px sans-serif"; ctx.textAlign = "center"; ctx.fillText(dur + "ms", down.x + barW / 2, down.y + 3); }
        if (downMap[e.key].length === 0) delete downMap[e.key];
      } else {
        ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
      }
      if (i > 0) {
        var prev = events[i - 1]; var px = pad.left + (prev.timestamp / maxTs) * plotW;
        var interval = e.timestamp - prev.timestamp;
        if (interval > 0 && interval < maxTs) {
          var midX = (px + x) / 2; ctx.fillStyle = "rgba(255,255,255,0.4)"; ctx.font = "9px sans-serif"; ctx.textAlign = "center";
          var prevKi = keyOrder.indexOf(prev.key); var labelY = pad.top + prevKi * laneH - 2;
          ctx.fillText(interval + "ms", midX, labelY);
        }
      }
    }
    Object.keys(downMap).forEach(function(key) {
      var down = downMap[key]; var endX = w - pad.right; var barW = endX - down.x; if (barW < 3) barW = 3;
      ctx.fillStyle = "#FF5722"; ctx.globalAlpha = 0.25; ctx.fillRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6); ctx.globalAlpha = 1;
      ctx.strokeStyle = "#FF5722"; ctx.lineWidth = 1; ctx.setLineDash([4, 4]); ctx.strokeRect(down.x, down.y - laneH / 2 + 3, barW, laneH - 6); ctx.setLineDash([]);
    });
  },
  _renderRadar: function(chart, w, h) {
    var ctx = chart.ctx; var data = chart.data; var labels = data.labels || []; var values = data.values || [];
    var cx = w / 2; var cy = h / 2 + 10; var r = Math.min(w, h) / 2 - 40; var n = labels.length; if (n < 3) return;
    ctx.strokeStyle = "#444"; ctx.lineWidth = 1;
    for (var ring = 1; ring <= 4; ring++) { var rr = r * ring / 4; ctx.beginPath(); for (var i = 0; i <= n; i++) { var angle = (Math.PI * 2 * (i % n)) / n - Math.PI / 2; var px = cx + rr * Math.cos(angle); var py = cy + rr * Math.sin(angle); if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py); } ctx.stroke(); }
    for (i = 0; i < n; i++) { angle = (Math.PI * 2 * i) / n - Math.PI / 2; ctx.strokeStyle = "#555"; ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + r * Math.cos(angle), cy + r * Math.sin(angle)); ctx.stroke(); ctx.fillStyle = "#aaa"; ctx.font = "10px sans-serif"; ctx.textAlign = "center"; var lx = cx + (r + 18) * Math.cos(angle); var ly = cy + (r + 18) * Math.sin(angle); ctx.fillText(labels[i], lx, ly + 3); }
    ctx.beginPath(); for (i = 0; i <= n; i++) { var idx = i % n; angle = (Math.PI * 2 * idx) / n - Math.PI / 2; var v = (values[idx] || 0) / 100; px = cx + r * v * Math.cos(angle); py = cy + r * v * Math.sin(angle); if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py); } ctx.closePath(); ctx.fillStyle = "rgba(76,175,80,0.25)"; ctx.fill(); ctx.strokeStyle = "#4CAF50"; ctx.lineWidth = 2; ctx.stroke();
    for (i = 0; i < n; i++) { angle = (Math.PI * 2 * i) / n - Math.PI / 2; v = (values[i] || 0) / 100; px = cx + r * v * Math.cos(angle); py = cy + r * v * Math.sin(angle); ctx.fillStyle = "#4CAF50"; ctx.beginPath(); ctx.arc(px, py, 4, 0, Math.PI * 2); ctx.fill(); }
    if (data.score != null) { ctx.fillStyle = "#fff"; ctx.font = "bold 24px sans-serif"; ctx.textAlign = "center"; ctx.fillText(data.score, cx, cy + 4); ctx.font = "10px sans-serif"; ctx.fillStyle = "#aaa"; ctx.fillText("综合评分", cx, cy + 18); }
  },
  _renderBar: function(chart, w, h) {
    var ctx = chart.ctx; var data = chart.data; var labels = data.labels || []; var values = data.values || []; var colors = data.colors || []; var avgLine = data.avgLine;
    var pad = { top: 10, right: 20, bottom: 30, left: 40 }; var plotW = w - pad.left - pad.right; var plotH = h - pad.top - pad.bottom; var n = labels.length; if (n === 0) return;
    var maxVal = 0; for (var i = 0; i < values.length; i++) { if (values[i] > maxVal) maxVal = values[i]; } maxVal = Math.max(maxVal, 100); maxVal = Math.ceil(maxVal / 25) * 25;
    ctx.strokeStyle = "#444"; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(pad.left, h - pad.bottom); ctx.lineTo(w - pad.right, h - pad.bottom); ctx.stroke();
    for (var g = 0; g <= 4; g++) { var gy = h - pad.bottom - (plotH * g / 4); ctx.strokeStyle = "#333"; ctx.beginPath(); ctx.moveTo(pad.left, gy); ctx.lineTo(w - pad.right, gy); ctx.stroke(); ctx.fillStyle = "#888"; ctx.font = "9px sans-serif"; ctx.textAlign = "right"; ctx.fillText(Math.round(maxVal * g / 4) + "%", pad.left - 4, gy + 3); }
    var barW = Math.min(30, (plotW / n) * 0.7); var gap = (plotW - barW * n) / (n + 1);
    for (i = 0; i < n; i++) { var x = pad.left + gap + i * (barW + gap); var barH = (values[i] / maxVal) * plotH; var y = h - pad.bottom - barH; ctx.fillStyle = colors[i] || "#4CAF50"; ctx.fillRect(x, y, barW, barH); ctx.fillStyle = "#aaa"; ctx.font = "9px sans-serif"; ctx.textAlign = "center"; ctx.fillText(labels[i], x + barW / 2, h - pad.bottom + 12); ctx.fillStyle = "#fff"; ctx.font = "9px sans-serif"; ctx.fillText(values[i] + "%", x + barW / 2, y - 4); }
    if (avgLine != null) { var avgY = h - pad.bottom - (avgLine / maxVal) * plotH; ctx.strokeStyle = "#FF9800"; ctx.lineWidth = 1; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(pad.left, avgY); ctx.lineTo(w - pad.right, avgY); ctx.stroke(); ctx.setLineDash([]); ctx.fillStyle = "#FF9800"; ctx.font = "9px sans-serif"; ctx.textAlign = "left"; ctx.fillText("avg " + avgLine + "%", w - pad.right + 2, avgY + 3); }
  },
  _renderHBar: function(chart, w, h) {
    var ctx = chart.ctx; var data = chart.data; var labels = data.labels || []; var values = data.values || []; var expectedValues = data.expectedValues || []; var colors = data.colors || [];
    var pad = { top: 10, right: 50, bottom: 10, left: 60 }; var plotW = w - pad.left - pad.right; var plotH = h - pad.top - pad.bottom; var n = labels.length; if (n === 0) return;
    var maxVal = 0; for (var i = 0; i < values.length; i++) { if (values[i] > maxVal) maxVal = values[i]; } for (i = 0; i < expectedValues.length; i++) { if (expectedValues[i] > maxVal) maxVal = expectedValues[i]; } maxVal = Math.max(maxVal, 50); maxVal = Math.ceil(maxVal / 50) * 50;
    var barH = Math.min(16, (plotH / n) * 0.6); var gap = (plotH - barH * n) / (n + 1); var hasExpected = expectedValues.length > 0; var groupW = hasExpected ? plotW * 0.45 : plotW;
    for (i = 0; i < n; i++) { var y = pad.top + gap + i * (barH + gap); ctx.fillStyle = "#aaa"; ctx.font = "10px monospace"; ctx.textAlign = "right"; ctx.fillText(labels[i], pad.left - 6, y + barH / 2 + 3); if (hasExpected) { var expW = (expectedValues[i] / maxVal) * groupW; ctx.fillStyle = "rgba(255,255,255,0.15)"; ctx.fillRect(pad.left, y, expW, barH); ctx.strokeStyle = "rgba(255,255,255,0.3)"; ctx.lineWidth = 1; ctx.strokeRect(pad.left, y, expW, barH); ctx.fillStyle = "#888"; ctx.font = "8px sans-serif"; ctx.textAlign = "left"; ctx.fillText(expectedValues[i] + "ms", pad.left + expW + 3, y + barH / 2 + 3); } var offset = hasExpected ? groupW + 10 : 0; var valW = (values[i] / maxVal) * groupW; ctx.fillStyle = colors[i] || "#4CAF50"; ctx.fillRect(pad.left + offset, y, valW, barH); ctx.fillStyle = "#fff"; ctx.font = "9px sans-serif"; ctx.textAlign = "left"; ctx.fillText(values[i] + "ms", pad.left + offset + valW + 4, y + barH / 2 + 3); }
  },
  _renderHold: function(chart, w, h) {
    var ctx = chart.ctx; var details = chart.data.details || [];
    if (details.length === 0) { var correct = chart.data.correct; ctx.fillStyle = correct ? "#4CAF50" : "#FF5722"; ctx.font = "bold 14px sans-serif"; ctx.textAlign = "center"; ctx.fillText(correct ? "✓ 长按时序全部正常" : "✗ 存在长按时序异常", w / 2, h / 2); return; }
    var pad = { top: 20, right: 20, bottom: 30, left: 60 }; var plotW = w - pad.left - pad.right; var plotH = h - pad.top - pad.bottom;
    var maxDur = 250; for (var i = 0; i < details.length; i++) { if (details[i].holdDuration > maxDur) maxDur = details[i].holdDuration; } maxDur = Math.ceil(maxDur / 50) * 50;
    var barW = Math.min(40, (plotW / details.length) * 0.7); var gap = (plotW - barW * details.length) / (details.length + 1);
    ctx.fillStyle = "rgba(74,222,128,0.1)"; ctx.fillRect(pad.left, pad.top + plotH * (1 - 200 / maxDur), plotW, plotH * (200 - 5) / maxDur);
    ctx.strokeStyle = "rgba(74,222,128,0.3)"; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(pad.left, pad.top + plotH * (1 - 200 / maxDur)); ctx.lineTo(pad.left + plotW, pad.top + plotH * (1 - 200 / maxDur)); ctx.moveTo(pad.left, pad.top + plotH * (1 - 5 / maxDur)); ctx.lineTo(pad.left + plotW, pad.top + plotH * (1 - 5 / maxDur)); ctx.stroke(); ctx.setLineDash([]);
    for (i = 0; i < details.length; i++) { var d = details[i]; var x = pad.left + gap + i * (barW + gap); var barH = (d.holdDuration / maxDur) * plotH; var y = pad.top + plotH - barH; ctx.fillStyle = d.valid ? "#4CAF50" : "#FF5722"; ctx.fillRect(x, y, barW, barH); ctx.fillStyle = "#ccc"; ctx.font = "9px sans-serif"; ctx.textAlign = "center"; ctx.fillText(d.key, x + barW / 2, pad.top + plotH + 14); ctx.fillText(d.holdDuration + "ms", x + barW / 2, y - 4); }
    ctx.fillStyle = "#888"; ctx.font = "10px sans-serif"; ctx.textAlign = "right"; for (var v = 0; v <= maxDur; v += maxDur / 4) { var yy = pad.top + plotH * (1 - v / maxDur); ctx.fillText(Math.round(v), pad.left - 6, yy + 3); }
  }
};

var ALL_KEYS = [
  {section:"功能键",keys:["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"]},
  {section:"数字",keys:["1","2","3","4","5","6","7","8","9","0"]},
  {section:"字母",keys:"ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")},
  {section:"特殊",keys:["Space","Enter","Tab","Esc","Backspace","Delete","Insert","Home","End","PgUp","PgDn","CapsLock","ScrollLock","NumLock","PrintScreen","Pause"]},
  {section:"方向",keys:["Up","Down","Left","Right"]},
  {section:"修饰",keys:["Shift","Ctrl","Alt","Win","LShift","RShift","LCtrl","RCtrl","LAlt","RAlt","LWin","RWin"]},
  {section:"鼠标",keys:["LButton","RButton","MButton","XButton1","XButton2","WheelUp","WheelDown"]},
  {section:"符号",keys:["`","-","=","[","]","\\",";","'",",",".","/"]},
  {section:"小键盘",keys:["Numpad0","Numpad1","Numpad2","Numpad3","Numpad4","Numpad5","Numpad6","Numpad7","Numpad8","Numpad9","NumpadAdd","NumpadSub","NumpadMult","NumpadDiv","NumpadEnter","NumpadDot"]}
];

var MODE_INFO = {
  periodic: {name:"周期性",desc:"每个按键按独立间隔循环触发。",fields:["keys","intervals"],fieldKey:"keys"},
  sequence: {name:"序列",desc:"按键按顺序依次执行，每步之间有延迟，循环往复。",fields:["keys","delays"],fieldKey:"keys"},
  hybrid: {name:"混合",desc:"多个子组同时运行，每个子组可以是周期性或序列。",fields:["groups"],fieldKey:"groups"},
  enhanced_periodic: {name:"增强周期",desc:"周期性按键 + 长按键。",fields:["pressKeys","intervals"],fieldKey:"pressKeys",enhanced:true},
  enhanced_sequence: {name:"增强序列",desc:"序列按键 + 长按键。",fields:["pressKeys","pressDelays"],fieldKey:"pressKeys",enhanced:true},
  enhanced_hybrid: {name:"增强混合",desc:"混合模式 + 长按键。",fields:["groups"],fieldKey:"groups",enhanced:true},
  hold: {name:"长按",desc:"持续按住指定按键。",fields:["holdKeys","holdDuration"],fieldKey:"holdKeys"},
  joystick_periodic: {name:"手柄周期",desc:"周期性发送手柄按键。",fields:["joyKeys","joyIntervals"],fieldKey:"joyKeys",joystick:true},
  joystick_sequence: {name:"手柄序列",desc:"手柄按键按顺序依次发送。",fields:["joyKeys","joyDelays"],fieldKey:"joyKeys",joystick:true},
  joystick_hold: {name:"手柄长按",desc:"持续按住手柄按键不放。",fields:["joyKeys"],fieldKey:"joyKeys",joystick:true}
};

var MODE_NAMES = {periodic:"周期性",sequence:"序列",hybrid:"混合",hold:"长按",enhanced_periodic:"增强周期",enhanced_sequence:"增强序列",enhanced_hybrid:"增强混合",joystick_periodic:"手柄周期",joystick_sequence:"手柄序列",joystick_hold:"手柄长按"};

function escHtml(s) { if (typeof s !== 'string') s = String(s); return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }
function escAttr(s) { return escHtml(s); }

var currentMode = "enhanced_periodic";
var keyPickerTarget = null;
var joyKeyPickerTarget = null;
var _fullConfig = null;

function _ensureFullConfig() {
  if (_fullConfig) return Promise.resolve(_fullConfig);
  return api.getConfig().then(function(cfg) {
    _fullConfig = cfg;
    return cfg;
  });
}

var sampleGroups = [];
var _searchTerm = "";
var _filterMode = "all";

function getFilteredGroups() {
  var result = [];
  for (var i = 0; i < sampleGroups.length; i++) {
    var g = sampleGroups[i];
    if (_filterMode === "active" && !g.active) continue;
    if (_filterMode === "stopped" && g.active) continue;
    if (_filterMode !== "all" && _filterMode !== "active" && _filterMode !== "stopped") { if (g.mode !== _filterMode) continue; }
    if (_searchTerm) { var term = _searchTerm.toLowerCase(); var name = (g.name || g.id || "").toLowerCase(); var hotkey = (g.hotkey || "").toLowerCase(); var mode = (g.mode || "").toLowerCase(); if (name.indexOf(term) < 0 && hotkey.indexOf(term) < 0 && mode.indexOf(term) < 0) continue; }
    result.push(g);
  }
  return result;
}

var _batchMode = false;
var _selectedGroups = {};

function toggleBatchMode() {
  _batchMode = !_batchMode; _selectedGroups = {};
  var toolbar = document.getElementById("batchToolbar"); if (toolbar) toolbar.style.display = _batchMode ? "flex" : "none";
  renderDashboard(); updateBatchUI();
}

function updateBatchUI() {
  var count = Object.keys(_selectedGroups).length; var countEl = document.getElementById("batchCount");
  if (countEl) countEl.textContent = count > 0 ? "已选 " + count + " 个" : "";
  var btns = ["batchActivate", "batchDeactivate", "batchDelete"];
  for (var i = 0; i < btns.length; i++) { var btn = document.querySelector('[data-action="' + btns[i] + '"]'); if (btn) btn.disabled = count === 0; }
}

function batchToggleSelected(activate) {
  var ids = Object.keys(_selectedGroups); if (ids.length === 0) return;
  api.batchToggleGroups(ids, activate).then(function() {
    showToast("批量操作完成", "success"); _selectedGroups = {}; updateBatchUI(); loadGroupsFromTauri();
  }).catch(function(e) { showToast(errMsg(e, "批量操作失败"), "error"); });
}

function batchDeleteSelected() {
  var ids = Object.keys(_selectedGroups); if (ids.length === 0) return;
  confirmDialog("确认删除", "确定要删除选中的 " + ids.length + " 个分组吗？", function() {
    api.batchDeleteGroups(ids).then(function() {
      _fullConfig = null;
      showToast("批量删除完成", "success"); _selectedGroups = {}; updateBatchUI(); loadGroupsFromTauri(); refreshGroupList();
    }).catch(function(e) { showToast(errMsg(e, "批量删除失败"), "error"); });
  });
}

var perfData = { timers: [], active: [] };
var PERF_MAX_POINTS = 60;

function updatePerfChart(debug) {
  if (!debug) return;
  perfData.timers.push(debug.timers || 0); perfData.active.push(debug.activeGroups || 0);
  if (perfData.timers.length > PERF_MAX_POINTS) perfData.timers.shift();
  if (perfData.active.length > PERF_MAX_POINTS) perfData.active.shift();
  var canvas = document.getElementById("perfChart"); if (!canvas) return;
  var ctx = canvas.getContext("2d"); var w = canvas.width = canvas.offsetWidth; var h = canvas.height = canvas.offsetHeight; ctx.clearRect(0, 0, w, h);
  var maxTimers = 1; for (var i = 0; i < perfData.timers.length; i++) { if (perfData.timers[i] > maxTimers) maxTimers = perfData.timers[i]; }
  var maxActive = 1; for (i = 0; i < perfData.active.length; i++) { if (perfData.active[i] > maxActive) maxActive = perfData.active[i]; }
  ctx.strokeStyle = "#7c5cfc"; ctx.lineWidth = 2; ctx.beginPath();
  for (i = 0; i < perfData.timers.length; i++) { var x = (i / (PERF_MAX_POINTS - 1)) * w; var y = h - (perfData.timers[i] / maxTimers) * (h - 10) - 5; if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); } ctx.stroke();
  ctx.strokeStyle = "#4ade80"; ctx.lineWidth = 1.5; ctx.beginPath();
  for (i = 0; i < perfData.active.length; i++) { x = (i / (PERF_MAX_POINTS - 1)) * w; y = h - (perfData.active[i] / maxActive) * (h - 10) - 5; if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); } ctx.stroke();
  if (debug.uptimeSeconds !== undefined) { var s = debug.uptimeSeconds; var m = Math.floor(s / 60); var hr = Math.floor(m / 60); document.getElementById("perfUptime").textContent = hr > 0 ? hr + "h" + (m % 60) + "m" : m > 0 ? m + "m" + (s % 60) + "s" : s + "s"; }
  if (debug.timers !== undefined) document.getElementById("perfTimers").textContent = debug.timers;
  if (debug.activeGroups !== undefined) document.getElementById("perfActive").textContent = debug.activeGroups;
}

var _backupList = [];
var sampleBackups = [];

function loadBackupList() {
  api.listBackups().then(function(r) {
    if (!r) return;
    try {
      _backupList = typeof r === "string" ? JSON.parse(r) : r;
      var baseSel = document.getElementById("diffBase"); var targetSel = document.getElementById("diffTarget");
      if (!baseSel || !targetSel) return;
      baseSel.innerHTML = '<option value="">选择基准配置</option>'; targetSel.innerHTML = '<option value="">选择目标配置</option>';
      for (var i = 0; i < _backupList.length; i++) { var b = _backupList[i]; var label = b.filename || b.timestamp || ("备份 " + (i+1)); baseSel.innerHTML += '<option value="'+escAttr(b.filename)+'">'+escHtml(label)+'</option>'; targetSel.innerHTML += '<option value="'+escAttr(b.filename)+'">'+escHtml(label)+'</option>'; }
    } catch(ex) { /* 忽略：localStorage 不可用（隐私模式/配额）时不应影响主流程 */ }
  }).catch(function() {});
}

function compareConfigs() {
  var basePath = document.getElementById("diffBase").value; var targetPath = document.getElementById("diffTarget").value;
  if (!basePath || !targetPath) { showToast("请选择两个配置", "warning"); return; }
  api.compareConfigs(basePath, targetPath).then(function(r) {
    if (!r) { showToast("比较失败", "error"); return; }
    try { var result = typeof r === "string" ? JSON.parse(r) : r; if (result.error) { showToast(result.error, "error"); return; } var diffs = result.diffs || []; var el = document.getElementById("diffResult"); if (!el) return; if (diffs.length === 0) { el.innerHTML = '<div style="color:var(--success);">两个配置完全相同</div>'; return; } var html = ''; for (var i = 0; i < diffs.length; i++) { var d = diffs[i]; if (d.type === 'added') html += '<div style="color:var(--success);">+ 新增分组: '+escHtml(d.id)+'</div>'; else if (d.type === 'removed') html += '<div style="color:var(--danger);">- 删除分组: '+escHtml(d.id)+'</div>'; else if (d.type === 'changed') html += '<div style="color:var(--warning);">~ '+escHtml(d.id)+'.'+escHtml(d.field)+': '+escHtml(d.oldValue)+' → '+escHtml(d.newValue)+'</div>'; } el.innerHTML = html; } catch(ex) { showToast("解析结果失败", "error"); }
  }).catch(function(e) { showToast(errMsg(e, "比较失败"), "error"); });
}

var _currentTheme = _safeStorage.get("ahk_theme", "dark");

function toggleTheme() { _currentTheme = _currentTheme === "dark" ? "light" : "dark"; applyTheme(); }

function applyTheme() {
  if (_currentTheme === "light") document.documentElement.setAttribute("data-theme", "light");
  else document.documentElement.removeAttribute("data-theme");
  var btn = document.getElementById("themeBtn"); if (btn) btn.textContent = _currentTheme === "dark" ? "🌙 暗色" : "☀️ 亮色";
  try { _safeStorage.set("ahk_theme", _currentTheme); } catch(ex) { /* 忽略：localStorage 不可用（隐私模式/配额）时不应影响主流程 */ }
}

var I18N = {
  zh: { dashboard:"📊 仪表盘", editor:"✏️ 分组编辑", settings:"⚙️ 全局设置", debug:"🐛 调试监控", backup:"💾 备份管理", keytest:"🧪 按键测试", running:"运行中", stopped:"已停止", periodic:"周期性", sequence:"序列", hold:"长按", enhanced_periodic:"增强周期", enhanced_sequence:"增强序列" },
  en: { dashboard:"📊 Dashboard", editor:"✏️ Editor", settings:"⚙️ Settings", debug:"🐛 Debug", backup:"💾 Backup", keytest:"🧪 Key Test", running:"Running", stopped:"Stopped", periodic:"Periodic", sequence:"Sequence", hold:"Hold", enhanced_periodic:"Enhanced Periodic", enhanced_sequence:"Enhanced Sequence" }
};

var _currentLang = _safeStorage.get("ahk_lang", "zh");

function t(key) { return (I18N[_currentLang] && I18N[_currentLang][key]) || (I18N.zh[key]) || key; }
function switchLang(lang) { _currentLang = lang; try { _safeStorage.set("ahk_lang", lang); } catch(ex) { /* 忽略：localStorage 不可用（隐私模式/配额）时不应影响主流程 */ } var sel = document.getElementById("langSelect"); if (sel) sel.value = lang; applyTranslations(); }
function applyTranslations() {
  var searchEl = document.getElementById("groupSearch"); if (searchEl) searchEl.placeholder = t("searchPlaceholder");
  var themeBtn = document.getElementById("themeBtn"); if (themeBtn) themeBtn.textContent = _currentTheme === "dark" ? t("dark") : t("light");
  MODE_NAMES.periodic = t("periodic"); MODE_NAMES.sequence = t("sequence"); MODE_NAMES.hold = t("hold"); MODE_NAMES.enhanced_periodic = t("enhanced_periodic"); MODE_NAMES.enhanced_sequence = t("enhanced_sequence");
}

function validateHotkeyFormat(value) {
  if (!value || value.trim() === "") return { valid: false, msg: "热键不能为空" };
  var v = value.trim(); var modifiers = /^[~!^+#]*/; var rest = v.replace(modifiers, "");
  if (rest === "") return { valid: false, msg: "缺少按键" };
  var validKeys = /^[a-zA-Z0-9]{1}$|^(F\d{1,2})$|^(Enter|Esc|Tab|Space|Backspace|Delete|Insert|Home|End|PgUp|PgDn|Up|Down|Left|Right|CapsLock|ScrollLock|NumLock|Numpad\d)$/i;
  if (!validKeys.test(rest)) return { valid: false, msg: "无效按键: " + rest };
  return { valid: true, msg: "" };
}

function validateAllHotkeys() {
  var ids = ["hkEmergency", "hkToggleAll", "hkShowStatus", "hkToggleHold", "hkReleaseHolds"]; var allValid = true;
  for (var i = 0; i < ids.length; i++) { var el = document.getElementById(ids[i]); var errEl = document.getElementById(ids[i] + "Error"); if (!el || !errEl) continue; var result = validateHotkeyFormat(el.value); if (!result.valid) { errEl.textContent = result.msg; errEl.className = "validation-msg error"; allValid = false; } else { errEl.textContent = ""; errEl.className = "validation-msg"; } }
  return allValid;
}

var TEMPLATES = {
  periodic: { mode: "periodic", pressKeys: ["a"], intervals: [100], pressDelays: [50], hotkey: "F1" },
  sequence: { mode: "sequence", pressKeys: ["a","b","c"], intervals: [100,100,100], pressDelays: [50,50,50], hotkey: "F2" },
  hold: { mode: "hold", holdKeys: ["a"], holdDelay: 100, hotkey: "F3" },
  hybrid: { mode: "hybrid", groups: [{type:"periodic",pressKeys:["a"],intervals:[100]},{type:"periodic",pressKeys:["b"],intervals:[150]}], seqInterval: 200, hotkey: "F4" },
  enhanced_periodic: { mode: "enhanced_periodic", pressKeys: ["a"], intervals: [100], pressDelays: [50], hotkey: "F5" },
  enhanced_sequence: { mode: "enhanced_sequence", pressKeys: ["a","b"], intervals: [100,100], pressDelays: [50,50], hotkey: "F6" },
  enhanced_hybrid: { mode: "enhanced_hybrid", groups: [{type:"periodic",pressKeys:["a"],intervals:[100]},{type:"periodic",pressKeys:["b"],intervals:[150]}], seqInterval: 200, holdKeys: ["c"], holdMode: "continuous", hotkey: "F7" }
};

function applyTemplate(templateName) {
  var tpl = TEMPLATES[templateName]; if (!tpl) return;
  currentMode = tpl.mode; pickModeByValue(currentMode);
  if (tpl.pressKeys) { editorConfig.pressKeys = tpl.pressKeys.slice(); editorConfig.keys = tpl.pressKeys.slice(); }
  if (tpl.intervals) editorConfig.intervals = tpl.intervals.slice();
  if (tpl.pressDelays) editorConfig.pressDelays = tpl.pressDelays.slice();
  if (tpl.delays) editorConfig.delays = tpl.delays.slice();
  if (tpl.holdKeys) editorConfig.holdKeys = tpl.holdKeys.slice();
  if (tpl.holdDelay) editorConfig.holdDelay = tpl.holdDelay;
  if (tpl.holdMode) editorConfig.holdMode = tpl.holdMode;
  if (tpl.groups) editorConfig.groups = JSON.parse(JSON.stringify(tpl.groups));
  if (tpl.seqInterval) editorConfig.seqInterval = tpl.seqInterval;
  if (tpl.hotkey) { var el = document.getElementById("hotkeyDisp"); if (el) el.textContent = tpl.hotkey; }
  renderKeyGrid(); showToast("已应用模板: " + (MODE_NAMES[templateName] || templateName), "success");
}

var editorConfig = {
  keys:["?"],intervals:[50],delays:[100],pressKeys:["?"],pressDelays:[100],
  groups:[{type:"periodic",pressKeys:["?"],intervals:[50]}],seqInterval:100,holdKeys:[],holdMode:"continuous",
  holdPattern:[500,200],holdTriggers:[],holdDuration:0,autoRepeat:false,repeatInterval:1000,
  joyKeys:["?"],joyIntervals:[50],joyDelays:[100],joySendMethod:"auto",joyKeyDuration:15
};

var _undoStack = []; var _redoStack = []; var _undoMaxSize = 50; var _captureTimer = null;

function pushUndoState() { _undoStack.push(JSON.stringify({config: editorConfig, mode: currentMode})); if (_undoStack.length > _undoMaxSize) _undoStack.shift(); _redoStack = []; }
function undoEditor() { if (_undoStack.length === 0) return; _redoStack.push(JSON.stringify({config: editorConfig, mode: currentMode})); var prev = _undoStack.pop(); try { var restored = JSON.parse(prev); if (restored.config) { for (var k in restored.config) { if (Object.prototype.hasOwnProperty.call(restored.config, k)) editorConfig[k] = restored.config[k]; } } else { for (k in restored) { if (Object.prototype.hasOwnProperty.call(restored, k)) editorConfig[k] = restored[k]; } } if (restored.mode) pickModeByValue(restored.mode); renderConfigSection(); renderHoldSection(); updatePreview(); showToast("已撤销", "success"); } catch(ex) { /* 忽略：localStorage 不可用（隐私模式/配额）时不应影响主流程 */ } }
function redoEditor() { if (_redoStack.length === 0) return; _undoStack.push(JSON.stringify({config: editorConfig, mode: currentMode})); var next = _redoStack.pop(); try { var restored = JSON.parse(next); if (restored.config) { for (var k in restored.config) { if (Object.prototype.hasOwnProperty.call(restored.config, k)) editorConfig[k] = restored.config[k]; } } else { for (k in restored) { if (Object.prototype.hasOwnProperty.call(restored, k)) editorConfig[k] = restored[k]; } } if (restored.mode) pickModeByValue(restored.mode); renderConfigSection(); renderHoldSection(); updatePreview(); showToast("已重做", "success"); } catch(ex) { /* 忽略：localStorage 不可用（隐私模式/配额）时不应影响主流程 */ } }

function loadGroupsFromTauri() {
  api.getGroups().then(function(groups) {
    if (Array.isArray(groups)) { sampleGroups = groups; }
    renderDashboard();
  }).catch(function(e) { console.log("[Tauri] getGroups error: " + errMsg(e)); renderDashboard(); });
}

function loadBackupsFromTauri() {
  api.listBackups().then(function(backups) {
    if (Array.isArray(backups)) { sampleBackups = backups; }
    renderBackupList();
  }).catch(function() { renderBackupList(); });
}

function loadSettingsFromTauri() {
  api.getConfig().then(function(cfg) {
    if (cfg) _fullConfig = cfg;
    if (cfg && cfg.CONTROL_HOTKEYS) {
      var ch = cfg.CONTROL_HOTKEYS;
      if (ch.emergency) document.getElementById("hkEmergency").value = ch.emergency;
      if (ch.toggleAll) document.getElementById("hkToggleAll").value = ch.toggleAll;
      if (ch.showStatus) document.getElementById("hkShowStatus").value = ch.showStatus;
      if (ch.toggleHoldMode) document.getElementById("hkToggleHold").value = ch.toggleHoldMode;
      if (ch.releaseAllHolds) document.getElementById("hkReleaseHolds").value = ch.releaseAllHolds;
    }
    if (cfg && cfg.HoldSettings) {
      var hs = cfg.HoldSettings;
      if (hs.allowOverlap !== undefined) document.getElementById("hsAllowOverlap").classList.toggle("on", hs.allowOverlap);
      if (hs.releaseOnEmergency !== undefined) document.getElementById("hsReleaseOnEmergency").classList.toggle("on", hs.releaseOnEmergency);
      if (hs.debounceDelay !== undefined) document.getElementById("hsDebounce").value = hs.debounceDelay;
      if (hs.checkInterval !== undefined) document.getElementById("hsCheckInterval").value = hs.checkInterval;
      if (hs.pressSpeed !== undefined) document.getElementById("hsPressSpeed").value = hs.pressSpeed;
    }
  }).catch(function() {});
}

function updateDashboard(data) {
  if (typeof data === "string") { try { data = JSON.parse(data); } catch(ex) { return; } }
  if (!data) return;
  if (data.debug) {
    var d = data.debug;
    if (d.activeGroups !== undefined) document.getElementById("statRunning").textContent = d.activeGroups;
    if (d.totalGroups !== undefined) document.getElementById("statTotal").textContent = d.totalGroups;
    if (d.timers !== undefined) document.getElementById("dbgTimers").textContent = d.timers;
  }
  if (data.groups) { sampleGroups = data.groups; renderDashboard(); }
  updatePerfChart(data.debug);
}

function switchPage(page) {
  document.querySelectorAll('.page').forEach(function(p) { p.classList.remove('active'); });
  document.querySelectorAll('.nav-item').forEach(function(n) { n.classList.remove('active'); });
  var pageEl = document.getElementById('page-' + page); var navEl = document.querySelector('.nav-item[data-page="'+page+'"]');
  if (!pageEl || !navEl) return;
  pageEl.classList.add('active'); navEl.classList.add('active');
  var titles = {dashboard:'📊 仪表盘',editor:'✏️ 分组编辑',settings:'⚙️ 全局设置',debug:'🐛 调试监控',backup:'💾 备份管理',keytest:'🧪 按键测试',diagnostics:'🩺 诊断信息'};
  document.getElementById('pageTitle').textContent = titles[page] || page;
  if (page === 'settings') { loadBackupList(); loadSettingsFromTauri(); }
  if (page === 'keytest') refreshGroupList();
  if (page === 'diagnostics') loadDiagnostics();
}

function renderDashboard() {
  var html = ''; var running = 0; var filtered = getFilteredGroups();
  for (var i=0; i<filtered.length; i++) {
    var g = filtered[i]; if (g.active) running++;
    var statusClass = g.active ? 'running' : 'stopped'; var statusText = g.active ? '运行中' : '已停止';
    var modeName = MODE_NAMES[g.mode] || escHtml(g.mode);
    var md = g.modeData || {};
    var keysArr = md.pressKeys || md.keys || g.holdKeys || md.joyKeys || [];
    var keysPreview = escHtml(keysArr.slice(0,4).join(', ')) + (keysArr.length > 4 ? '...' : '');
    html += '<div class="group-card '+statusClass+'" data-group-id="'+escAttr(g.id)+'" draggable="true">';
    if (_batchMode) { var checked = _selectedGroups[g.id] ? ' checked' : ''; html += '<label style="display:flex;align-items:center;gap:6px;margin-bottom:4px;"><input type="checkbox" class="batch-check" data-group-id="'+escAttr(g.id)+'"'+checked+'><span class="group-card-id">'+escHtml(g.name || g.id)+'</span></label>'; }
    else { html += '<div class="group-card-header"><span class="group-card-id">'+escHtml(g.name || g.id)+'</span><span class="group-card-hotkey">'+escHtml(g.hotkey)+'</span></div>'; }
    html += '<div class="group-card-body"><span class="group-card-mode">'+modeName+'</span><span class="group-card-keys">'+keysPreview+'</span>';
    html += '<div class="group-card-status"><div class="status-dot '+statusClass+'"></div>'+statusText+'</div></div>';
    html += '<div class="group-card-actions">';
    html += '<button class="btn btn-ghost btn-sm" data-action="toggle" data-group-id="'+escAttr(g.id)+'">'+(g.active?'⏹ 停止':'▶ 启动')+'</button>';
    html += '<button class="btn btn-ghost btn-sm" data-action="edit" data-group-id="'+escAttr(g.id)+'">✏️ 编辑</button>';
    html += '<button class="btn btn-ghost btn-sm" data-action="clone" data-group-id="'+escAttr(g.id)+'">📋 克隆</button>';
    html += '<button class="btn btn-danger btn-sm" data-action="delete" data-group-id="'+escAttr(g.id)+'">🗑 删除</button>';
    html += '</div></div>';
  }
  if (filtered.length === 0) { html = '<div class="empty-state" style="text-align:center;padding:40px;color:var(--text-muted);">📭 暂无分组<br><small>点击"+ 添加新分组"开始</small></div>'; }
  var container = document.getElementById('groupCards'); container.innerHTML = html;
  container.onclick = function(e) {
    var chk = e.target.closest('.batch-check'); if (chk) { var gid = chk.getAttribute('data-group-id'); if (chk.checked) _selectedGroups[gid] = true; else delete _selectedGroups[gid]; updateBatchUI(); return; }
    var btn = e.target.closest('[data-action]'); if (btn) { var action = btn.getAttribute('data-action'); gid = btn.getAttribute('data-group-id'); if (action === 'toggle') toggleGroup(gid); else if (action === 'edit') editGroup(gid); else if (action === 'clone') cloneGroup(gid); else if (action === 'delete') deleteGroup(gid); return; }
    var card = e.target.closest('.group-card[data-group-id]'); if (card) editGroup(card.getAttribute('data-group-id'));
  };
  container.ondragstart = function(e) { var card = e.target.closest('.group-card'); if (card) { e.dataTransfer.setData('text/plain', card.getAttribute('data-group-id')); card.style.opacity = '0.5'; } };
  container.ondragend = function(e) { var card = e.target.closest('.group-card'); if (card) card.style.opacity = ''; };
  container.ondragover = function(e) { e.preventDefault(); };
  container.ondrop = function(e) {
    e.preventDefault(); e.stopPropagation(); var draggedId = e.dataTransfer.getData('text/plain'); var targetCard = e.target.closest('.group-card');
    if (!targetCard || !draggedId) return; var targetId = targetCard.getAttribute('data-group-id'); if (draggedId === targetId) return;
    var fromIdx = sampleGroups.findIndex(function(g) { return g.id === draggedId; }); var toIdx = sampleGroups.findIndex(function(g) { return g.id === targetId; });
    if (fromIdx < 0 || toIdx < 0) return; var savedGroups = sampleGroups.slice(); var item = sampleGroups.splice(fromIdx, 1)[0]; sampleGroups.splice(toIdx, 0, item); renderDashboard();
    var orderIds = sampleGroups.map(function(g) { return g.id; });
    api.reorderGroups(orderIds).then(function() { showToast("分组顺序已更新", "success"); }).catch(function() { showToast("排序保存失败", "warning"); sampleGroups = savedGroups; renderDashboard(); });
  };
  document.getElementById('statTotal').textContent = sampleGroups.length;
  document.getElementById('statRunning').textContent = running;
}

function editGroup(id) {
  _undoStack = []; _redoStack = [];
  api.getGroupDetail(id).then(function(cfg) {
    if (cfg && cfg.mode) {
      document.getElementById('idInput').value = cfg.id || id;
      if (cfg.name) document.getElementById('groupName').value = cfg.name; else document.getElementById('groupName').value = '';
      document.getElementById('hotkeyDisp').textContent = cfg.hotkey || "点击设置";
      document.getElementById('keyPressDuration').value = cfg.keyPressDuration || 15;
      var md = cfg.modeData || {};
      editorConfig.keys = md.keys ? md.keys.slice() : ["?"]; editorConfig.intervals = md.intervals ? md.intervals.slice() : [50];
      editorConfig.delays = md.delays ? md.delays.slice() : [100]; editorConfig.pressKeys = md.pressKeys ? md.pressKeys.slice() : ["?"];
      editorConfig.pressDelays = md.pressDelays ? md.pressDelays.slice() : [100];
      editorConfig.groups = md.groups ? JSON.parse(JSON.stringify(md.groups)) : [{type:"periodic",pressKeys:["?"],intervals:[50]}];
      editorConfig.seqInterval = md.seqInterval || 100; editorConfig.holdKeys = cfg.holdKeys ? cfg.holdKeys.slice() : [];
      editorConfig.holdMode = cfg.holdMode || "continuous"; editorConfig.holdPattern = [500,200];
      editorConfig.holdTriggers = []; editorConfig.holdDuration = md.holdDuration !== undefined ? md.holdDuration : 0;
      editorConfig.autoRepeat = md.autoRepeat !== undefined ? md.autoRepeat : false; editorConfig.repeatInterval = md.repeatInterval || 1000;
      editorConfig.joyKeys = md.pressKeys ? md.pressKeys.slice() : ["?"]; editorConfig.joyIntervals = md.intervals ? md.intervals.slice() : [50];
      editorConfig.joyDelays = md.delays ? md.delays.slice() : [100]; editorConfig.joySendMethod = "auto";
      editorConfig.joyKeyDuration = 15; pickModeByValue(cfg.mode); renderConfigSection(); renderHoldSection(); updatePreview();
    }
  }).catch(function() {
    var g = sampleGroups.find(function(x) { return x.id === id; });
    if (g) { document.getElementById('idInput').value = g.id; document.getElementById('hotkeyDisp').textContent = g.hotkey; document.getElementById('keyPressDuration').value = g.keyPressDuration || 15; pickModeByValue(g.mode); }
  });
  switchPage('editor');
}

function resetEditor() {
  _undoStack = []; _redoStack = [];
  if (_captureTimer) { clearTimeout(_captureTimer); _captureTimer = null; }
  document.getElementById('idInput').value = ""; document.getElementById('groupName').value = "";
  var d = document.getElementById('hotkeyDisp'); d.textContent = "点击设置"; d.classList.remove("capturing");
  document.getElementById('keyPressDuration').value = "15";
  editorConfig = { keys:["?"],intervals:[50],delays:[100],pressKeys:["?"],pressDelays:[100],groups:[{type:"periodic",pressKeys:["?"],intervals:[50]}],seqInterval:100,holdKeys:[],holdMode:"continuous",holdPattern:[500,200],holdTriggers:[],holdDuration:0,autoRepeat:false,repeatInterval:1000,joyKeys:["?"],joyIntervals:[50],joyDelays:[100],joySendMethod:"auto",joyKeyDuration:15 };
  pickModeByValue("enhanced_periodic");
}

function toggleGroup(id) {
  api.toggleGroup(id).then(function() { loadGroupsFromTauri(); showToast('分组 '+id+' 已切换','success'); }).catch(function(e) { showToast('操作失败: '+errMsg(e),'error'); });
}

function deleteGroup(id) {
  confirmDialog("删除分组", "确定删除分组 " + id + "？此操作不可撤销。", function() {
    api.deleteGroup(id).then(function() { _fullConfig = null; loadGroupsFromTauri(); refreshGroupList(); showToast('分组 '+id+' 已删除','success'); }).catch(function(e) { showToast('删除失败: '+errMsg(e),'error'); });
  });
}

function cloneGroup(id) {
  api.getGroupDetail(id).then(function(r) {
    try {
      var detail = typeof r === "string" ? JSON.parse(r) : r;
      if (!detail || !detail.mode) { showToast("无法读取分组配置","error"); return; }
      var newId = id + "_copy_" + Date.now().toString(36);
      var baseName = detail.name || id;
      var copyCount = sampleGroups.filter(function(g) { return g.id.indexOf(id + "_copy") === 0; }).length;
      var newName = baseName + " 副本" + (copyCount > 0 ? (copyCount + 1) : "");
      var cfg = {hotkey: "", mode: detail.mode, keyPressDuration: detail.keyPressDuration || 15, name: newName};
      var md = detail.modeData || {};
      if (md.keys) cfg.keys = md.keys.slice(); if (md.intervals) cfg.intervals = md.intervals.slice();
      if (md.delays) cfg.delays = md.delays.slice(); if (md.pressKeys) cfg.pressKeys = md.pressKeys.slice();
      if (md.pressDelays) cfg.pressDelays = md.pressDelays.slice();
      if (md.groups) cfg.groups = JSON.parse(JSON.stringify(md.groups));
      if (md.seqInterval) cfg.seqInterval = md.seqInterval;
      if (md.holdDuration !== undefined) cfg.holdDuration = md.holdDuration;
      if (md.autoRepeat !== undefined) cfg.autoRepeat = md.autoRepeat;
      if (md.repeatInterval) cfg.repeatInterval = md.repeatInterval;
      if (detail.holdKeys) cfg.holdKeys = detail.holdKeys.slice();
      if (detail.holdMode) cfg.holdMode = detail.holdMode;
      return _ensureFullConfig().then(function(currentConfig) {
        var fullConfig = JSON.parse(JSON.stringify(currentConfig));
        if (!fullConfig.GroupSettings) fullConfig.GroupSettings = {};
        fullConfig.GroupSettings[newId] = cfg;
        return api.saveConfig(fullConfig);
      });
    } catch(ex) { showToast("克隆失败: " + ex.message, "error"); }
  }).then(function(r) { if (r !== undefined) { _fullConfig = null; loadGroupsFromTauri(); showToast("分组已克隆","success"); } }).catch(function(e) { showToast("克隆失败: " + errMsg(e), "error"); });
}

function exportAllGroups() {
  if (sampleGroups.length === 0) { showToast("没有分组可导出","error"); return; }
  var promises = sampleGroups.map(function(g) {
    return api.getGroupDetail(g.id).then(function(r) { var detail = typeof r === "string" ? JSON.parse(r) : r; detail.id = g.id; return detail; }).catch(function() { return null; });
  });
  Promise.all(promises).then(function(results) {
    var valid = results.filter(function(r) { return r && r.mode; });
    if (valid.length === 0) { showToast("导出失败","error"); return; }
    var json = JSON.stringify(valid, null, 2); var blob = new Blob([json], {type: "application/json"}); var url = URL.createObjectURL(blob);
    var a = document.createElement("a"); a.href = url; a.download = "keygroups_" + new Date().toISOString().slice(0,10) + ".json"; a.click();
    setTimeout(function() { URL.revokeObjectURL(url); }, 1000); showToast("已导出 " + valid.length + " 个分组","success");
  });
}

function importGroupsFromFile(file) {
  if (file.size > 5 * 1024 * 1024) { showToast("文件过大，最大支持5MB","error"); return; }
  var reader = new FileReader();
  reader.onload = function(e) {
    try {
      var groups = JSON.parse(e.target.result); if (!Array.isArray(groups)) groups = [groups];
      var overwriteIds = []; groups.forEach(function(cfg) { if (cfg.id && sampleGroups.some(function(g) { return g.id === cfg.id; })) overwriteIds.push(cfg.id); });
      var doImport = function() {
        var count = 0; var chain = Promise.resolve();
        groups.forEach(function(cfg) { chain = chain.then(function() {
          var groupId = cfg.id || ("imported_" + Date.now().toString(36));
          delete cfg.id;
          return _ensureFullConfig().then(function(currentConfig) {
            var fullConfig = JSON.parse(JSON.stringify(currentConfig));
            if (!fullConfig.GroupSettings) fullConfig.GroupSettings = {};
            fullConfig.GroupSettings[groupId] = cfg;
            return api.saveConfig(fullConfig);
          }).then(function() { count++; }).catch(function() { showToast("导入 " + (groupId || "?") + " 失败", "error"); });
        }); });
        chain.then(function() { _fullConfig = null; loadGroupsFromTauri(); showToast("已导入 " + count + " 个分组","success"); });
      };
      if (overwriteIds.length > 0) confirmDialog("导入确认", "以下分组已存在，将被覆盖: " + overwriteIds.join(", "), doImport);
      else doImport();
    } catch(ex) { showToast("文件格式错误","error"); }
  };
  reader.readAsText(file);
}

function saveConfig() {
  var id = document.getElementById('idInput').value.trim();
  if (!id) { showToast("请输入分组ID","error"); return; }
  var name = document.getElementById('groupName').value.trim() || id;
  var hotkey = document.getElementById('hotkeyDisp').textContent;
  if (hotkey === "点击设置") hotkey = "";
  var keyPressDuration = parseInt(document.getElementById('keyPressDuration').value) || 15;
  var cfg = { name: name, hotkey: hotkey, mode: currentMode, keyPressDuration: keyPressDuration };
  function hasUnsetKey(arr) { for (var i = 0; i < arr.length; i++) { if (arr[i] === "?" || arr[i] === "") return true; } return false; }

  if (currentMode === "periodic") {
    if (editorConfig.keys.length === 0 || hasUnsetKey(editorConfig.keys)) { showToast("请设置所有按键","error"); return; }
    cfg.keys = editorConfig.keys.slice(); cfg.intervals = editorConfig.intervals.slice();
  } else if (currentMode === "sequence") {
    if (editorConfig.keys.length === 0 || hasUnsetKey(editorConfig.keys)) { showToast("请设置所有按键","error"); return; }
    cfg.keys = editorConfig.keys.slice(); cfg.delays = editorConfig.delays.slice();
  } else if (currentMode === "enhanced_periodic") {
    if (editorConfig.pressKeys.length === 0 || hasUnsetKey(editorConfig.pressKeys)) { showToast("请设置所有按键","error"); return; }
    cfg.pressKeys = editorConfig.pressKeys.slice(); cfg.intervals = editorConfig.intervals.slice();
    if (editorConfig.holdKeys.length > 0) { cfg.holdKeys = editorConfig.holdKeys.slice(); cfg.holdMode = editorConfig.holdMode; if (editorConfig.holdMode === "periodic") cfg.holdPattern = editorConfig.holdPattern.slice(); }
  } else if (currentMode === "enhanced_sequence") {
    if (editorConfig.pressKeys.length === 0 || hasUnsetKey(editorConfig.pressKeys)) { showToast("请设置所有按键","error"); return; }
    cfg.pressKeys = editorConfig.pressKeys.slice(); cfg.pressDelays = editorConfig.pressDelays.slice();
    if (editorConfig.holdKeys.length > 0) { cfg.holdKeys = editorConfig.holdKeys.slice(); cfg.holdMode = editorConfig.holdMode; if (editorConfig.holdMode === "sequence") cfg.holdTriggers = editorConfig.holdTriggers.slice(); }
  } else if (currentMode === "hybrid" || currentMode === "enhanced_hybrid") {
    if (editorConfig.groups.length === 0) { showToast("请添加至少一个子组","error"); return; }
    cfg.groups = JSON.parse(JSON.stringify(editorConfig.groups)); cfg.seqInterval = editorConfig.seqInterval;
    if (editorConfig.holdKeys.length > 0) { cfg.holdKeys = editorConfig.holdKeys.slice(); cfg.holdMode = editorConfig.holdMode; if (editorConfig.holdMode === "periodic") cfg.holdPattern = editorConfig.holdPattern.slice(); if (editorConfig.holdMode === "sequence") cfg.holdTriggers = editorConfig.holdTriggers.slice(); }
  } else if (currentMode === "hold") {
    if (editorConfig.holdKeys.length === 0 || hasUnsetKey(editorConfig.holdKeys)) { showToast("请设置所有长按键","error"); return; }
    cfg.holdKeys = editorConfig.holdKeys.slice(); cfg.holdDuration = Math.max(0, editorConfig.holdDuration); cfg.autoRepeat = editorConfig.autoRepeat; cfg.repeatInterval = editorConfig.repeatInterval;
  } else if (currentMode === "joystick_periodic") {
    if (editorConfig.joyKeys.length === 0 || hasUnsetKey(editorConfig.joyKeys)) { showToast("请设置所有手柄按键","error"); return; }
    cfg.joyKeys = editorConfig.joyKeys.slice(); cfg.joyIntervals = editorConfig.joyIntervals.slice(); cfg.joySendMethod = editorConfig.joySendMethod || "auto"; cfg.joyKeyDuration = editorConfig.joyKeyDuration || 15;
  } else if (currentMode === "joystick_sequence") {
    if (editorConfig.joyKeys.length === 0 || hasUnsetKey(editorConfig.joyKeys)) { showToast("请设置所有手柄按键","error"); return; }
    cfg.joyKeys = editorConfig.joyKeys.slice(); cfg.joyDelays = editorConfig.joyDelays.slice(); cfg.joySendMethod = editorConfig.joySendMethod || "auto"; cfg.joyKeyDuration = editorConfig.joyKeyDuration || 15;
  } else if (currentMode === "joystick_hold") {
    if (editorConfig.joyKeys.length === 0 || hasUnsetKey(editorConfig.joyKeys)) { showToast("请设置所有手柄按键","error"); return; }
    cfg.joyKeys = editorConfig.joyKeys.slice(); cfg.joySendMethod = editorConfig.joySendMethod || "auto"; cfg.joyKeyDuration = editorConfig.joyKeyDuration || 15;
  }

  _ensureFullConfig().then(function(currentConfig) {
    var fullConfig = JSON.parse(JSON.stringify(currentConfig));
    if (!fullConfig.GroupSettings) fullConfig.GroupSettings = {};
    fullConfig.GroupSettings[id] = cfg;
    return api.saveConfig(fullConfig);
  }).then(function() {
    _fullConfig = null;
    showToast("分组 "+id+" 已保存","success"); loadGroupsFromTauri(); refreshGroupList(); switchPage("dashboard");
  }).catch(function(e) { showToast("保存失败: "+errMsg(e),"error"); });
}

function saveSettings() {
  if (!validateAllHotkeys()) { showToast("请修正热键格式错误", "error"); return; }
  var ch = {};
  var eEl = document.getElementById("hkEmergency"); var taEl = document.getElementById("hkToggleAll");
  var ssEl = document.getElementById("hkShowStatus"); var thEl = document.getElementById("hkToggleHold");
  var rhEl = document.getElementById("hkReleaseHolds");
  if (eEl) ch.emergency = eEl.value; if (taEl) ch.toggleAll = taEl.value; if (ssEl) ch.showStatus = ssEl.value;
  if (thEl) ch.toggleHoldMode = thEl.value; if (rhEl) ch.releaseAllHolds = rhEl.value;
  var hs = {}; var aoEl = document.getElementById("hsAllowOverlap"); var reEl = document.getElementById("hsReleaseOnEmergency");
  var dbEl = document.getElementById("hsDebounce"); var ciEl = document.getElementById("hsCheckInterval"); var psEl = document.getElementById("hsPressSpeed");
  if (aoEl) hs.allowOverlap = aoEl.classList.contains("on"); if (reEl) hs.releaseOnEmergency = reEl.classList.contains("on");
  if (dbEl) { var dbv=parseInt(dbEl.value); hs.debounceDelay = dbv>=0 ? dbv : 20; }
  if (ciEl) { var civ=parseInt(ciEl.value); hs.checkInterval = civ>0 ? civ : 50; }
  if (psEl) { var psv=parseInt(psEl.value); hs.pressSpeed = psv>0 ? psv : 80; }
  _ensureFullConfig().then(function(currentConfig) {
    var fullConfig = JSON.parse(JSON.stringify(currentConfig));
    fullConfig.CONTROL_HOTKEYS = ch;
    fullConfig.HoldSettings = hs;
    return api.saveConfig(fullConfig);
  }).then(function() { _fullConfig = null; showToast("全局设置已保存","success"); loadSettingsFromTauri(); }).catch(function(e) { showToast("保存失败: "+errMsg(e),"error"); });
}

function renderBackupList() {
  var h = '';
  for(var i=0;i<sampleBackups.length;i++){
    var b=sampleBackups[i]; var name = b.name || b.filename || ""; var time = b.timestamp || "";
    var size = b.size ? (typeof b.size === "number" ? (b.size/1024).toFixed(1)+" KB" : b.size) : "";
    h+='<div class="backup-item"><div class="backup-info"><span class="backup-name">'+escHtml(name)+'</span><span class="backup-meta">'+escHtml(time)+(size?' · '+escHtml(String(size)):'')+'</span></div>';
    h+='<div class="backup-actions"><button class="btn btn-ghost btn-sm" data-action="restore" data-backup="'+escAttr(name)+'">恢复</button><button class="btn btn-danger btn-sm" data-action="delete" data-backup="'+escAttr(name)+'">删除</button></div></div>';
  }
  var container = document.getElementById("backupList"); container.innerHTML=h;
  container.onclick = function(e) { var btn = e.target.closest('[data-action]'); if (!btn) return; var action = btn.getAttribute('data-action'); var backupName = btn.getAttribute('data-backup'); if (action === 'restore') restoreBackup(backupName); else if (action === 'delete') deleteBackup(backupName); };
}

function createBackup() { api.createBackup().then(function() { showToast("备份已创建","success"); loadBackupsFromTauri(); }).catch(function(e) { showToast(errMsg(e, "备份失败"),"error"); }); }
function restoreBackup(name) { confirmDialog("恢复备份", "恢复将覆盖当前所有配置，确定继续？", function() { api.restoreBackup(name).then(function() { _fullConfig = null; showToast("已恢复备份: "+name,"success"); loadGroupsFromTauri(); }).catch(function(e) { showToast(errMsg(e, "恢复失败"),"error"); }); }); }
function deleteBackup(name) { api.deleteBackup(name).then(function() { showToast("已删除备份: "+name,"success"); loadBackupsFromTauri(); }).catch(function(e) { showToast(errMsg(e, "删除失败"),"error"); }); }

var MAX_LOG_LINES = 200; var _autoScroll = true;
function addLog(msg, level) {
  var c = document.getElementById("logContainer"); var now = new Date(); var ts = now.toTimeString().split(' ')[0];
  var div = document.createElement('div'); div.className = 'log-line ' + (level||'debug');
  var span = document.createElement('span'); span.className = 'log-time'; span.textContent = ts;
  div.appendChild(span); div.appendChild(document.createTextNode(msg)); c.appendChild(div);
  while (c.childNodes.length > MAX_LOG_LINES) c.removeChild(c.firstChild);
  if (level === 'error' || level === 'critical') { var errEl = document.getElementById('dbgErrors'); if (errEl) errEl.textContent = parseInt(errEl.textContent || '0') + 1; }
  if (_autoScroll) c.scrollTop = c.scrollHeight;
}
function clearLogs() { document.getElementById("logContainer").innerHTML = ''; }
function toggleAutoScroll() { _autoScroll = !_autoScroll; var btn = document.querySelector('[data-action="toggleAutoScroll"]'); if (btn) btn.textContent = "自动滚动: " + (_autoScroll ? "开" : "关"); showToast("自动滚动已" + (_autoScroll ? "开启" : "关闭"), "success"); }

// ── 诊断信息（TD-076：运行时遥测缺位的低成本先行项）──────────────────────
// 用户报错时能一键拿到「版本 + 日志目录 + 时间」，直接粘进反馈，替代口头描述。
// 纯前端：版本/目录分别来自 Tauri 内置的 app.getVersion() 与 path.appDataDir()，
// 权限由 capabilities 的 core:default 覆盖，**没有新增 Rust 命令**。
var _diagInfo = { version: '', logDir: '', execStatus: '', execRestart: null };

function loadDiagnostics() {
  var vEl = document.getElementById('diagVersion');
  var dEl = document.getElementById('diagLogDir');
  var sEl = document.getElementById('diagExecStatus');
  var rEl = document.getElementById('diagExecRestart');
  if (vEl) vEl.textContent = '读取中…';
  if (dEl) dEl.textContent = '读取中…';
  if (sEl) sEl.textContent = '读取中…';
  if (rEl) rEl.textContent = '';
  hideDiagFallback();
  var pv = api.getAppVersion().then(function(v) {
    _diagInfo.version = v || '';
    if (vEl) vEl.textContent = _diagInfo.version || '未知';
  }).catch(function(e) {
    _diagInfo.version = '';
    if (vEl) vEl.textContent = '读取失败: ' + errMsg(e, '未知错误');
  });
  var pd = api.getLogDirPath().then(function(p) {
    _diagInfo.logDir = p || '';
    if (dEl) dEl.textContent = _diagInfo.logDir || '未知';
  }).catch(function(e) {
    _diagInfo.logDir = '';
    if (dEl) dEl.textContent = '读取失败: ' + errMsg(e, '未知错误');
  });
  // 拉一次当前快照：事件只推送「变化」，刚进页面时若状态没变过就拿不到值。
  var ps = api.getExecutorStatus().then(renderExecutorStatus).catch(function(e) {
    _diagInfo.execStatus = '';
    if (sEl) sEl.textContent = '读取失败: ' + errMsg(e, '未知错误');
  });
  return Promise.all([pv, pd, ps]);
}

function buildDiagnosticText() {
  return 'ASD 技能管理器诊断信息\n'
    + '应用版本: ' + (_diagInfo.version || '读取失败') + '\n'
    + '日志目录: ' + (_diagInfo.logDir || '读取失败') + '\n'
    + '执行器状态: ' + (EXEC_STATUS_MAP[_diagInfo.execStatus] || _diagInfo.execStatus || '读取失败') + '\n'
    + ((typeof _diagInfo.execRestart === 'number' && _diagInfo.execRestart > 0)
        ? ('重启次数: ' + _diagInfo.execRestart + '\n') : '')
    + '生成时间: ' + new Date().toLocaleString();
}

// ── 执行器状态（TD-082 / B4 的真实缺口）────────────────────────────────
// ⚠️ 与「UI 零提示」相反：导航栏圆点其实一直在工作 —— Rust 的
// `update_watchdog_state`(state.rs:343) 轮询到状态变化就 emit `executor_status`，
// 前端 onExecutorStatus 会把圆点变红、文字改「失败」。**真正的缺口是另外两条**：
//   ① 进入 Failed 时只有 6px 的圆点变色，**没有 toast / 日志**，用户不看导航栏就不知道；
//   ② `resetWatchdog()` 在 api.js 里有封装，但 UI 从未调用 —— 没有任何自助恢复入口。
// 这里补齐 ②（诊断页可刷新状态 + 一键重置），① 由下方 onExecutorStatus 补 toast。
var EXEC_STATUS_MAP = { Idle: "就绪", Starting: "启动中", Running: "运行中", Hung: "挂起", Restarting: "重启中", Recovering: "恢复中", Failed: "失败" };
// 上一次的状态：用于「只在刚变成 Failed 时提示一次」，避免每次事件都弹 toast。
var _lastExecStatus = '';

function renderExecutorStatus(s) {
  if (!s) return;
  _diagInfo.execStatus = s.status || '';
  _diagInfo.execRestart = (typeof s.restartCount === 'number') ? s.restartCount : null;
  var sEl = document.getElementById('diagExecStatus');
  var rEl = document.getElementById('diagExecRestart');
  if (sEl) {
    sEl.textContent = EXEC_STATUS_MAP[s.status] || s.status || '未知';
    sEl.style.color = (s.status === 'Failed') ? 'var(--danger)'
                    : (s.status === 'Running') ? 'var(--success)' : '';
  }
  if (rEl) {
    rEl.textContent = (typeof s.restartCount === 'number' && s.restartCount > 0)
      ? ('重启次数: ' + s.restartCount) : '';
  }
}

// 自助恢复：看门狗卡在 Failed（重启次数耗尽）时清空计数，把状态拉回就绪并重新拉起子进程。
function resetWatchdogDiag() {
  api.resetWatchdog().then(function() {
    showToast('看门狗已重置，正在重新拉起执行器', 'success');
    return loadDiagnostics();
  }).catch(function(e) {
    showToast('重置失败: ' + errMsg(e, '未知错误'), 'error');
  });
}

function hideDiagFallback() {
  var hint = document.getElementById('diagFallbackHint');
  var ta = document.getElementById('diagFallbackText');
  if (hint) hint.style.display = 'none';
  if (ta) { ta.style.display = 'none'; ta.value = ''; }
}

// 剪贴板不可用时的兜底：把文本摊在页面上让用户手动复制 —— 绝不静默失败。
function showDiagFallback(text) {
  var hint = document.getElementById('diagFallbackHint');
  var ta = document.getElementById('diagFallbackText');
  if (!hint || !ta) { showToast('复制失败，且页面缺少手动复制区域', 'error'); return; }
  hint.style.display = 'block';
  ta.style.display = 'block';
  ta.value = text;
  ta.focus();
  ta.select();
  showToast('自动复制失败，请手动复制下方内容', 'error');
}

// navigator.clipboard 在非安全上下文不可用时的退路（textarea + execCommand）。
function legacyCopyText(text) {
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.top = '-1000px';
  document.body.appendChild(ta);
  ta.select();
  var ok = false;
  try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
  document.body.removeChild(ta);
  return ok;
}

function copyDiagnostics() {
  var ready = (_diagInfo.version && _diagInfo.logDir) ? Promise.resolve() : loadDiagnostics();
  ready.then(function() {
    var text = buildDiagnosticText();
    var done = function() { showToast('诊断信息已复制，可直接粘贴到反馈中', 'success'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(function() {
        if (legacyCopyText(text)) done(); else showDiagFallback(text);
      });
    } else if (legacyCopyText(text)) {
      done();
    } else {
      showDiagFallback(text);
    }
  });
}

function showToast(msg, type) {
  var c = document.getElementById("toastContainer"); while (c.children.length >= 5) c.removeChild(c.firstChild);
  var t = document.createElement("div"); t.className = "toast" + (type ? " " + type : ""); t.textContent = msg; c.appendChild(t);
  setTimeout(function() { if (t.parentNode) t.remove(); }, 2500);
}

function confirmDialog(title, message, onConfirm) {
  var existing = document.querySelector(".overlay.confirm-dialog"); if (existing) return;
  var overlay = document.createElement("div"); overlay.className = "overlay confirm-dialog"; overlay.style.display = "flex";
  var html = '<div class="glass" style="padding:20px;border-radius:12px;max-width:360px;width:90%;">';
  html += '<div class="section-label" style="margin-bottom:12px;">' + escHtml(title) + '</div>';
  html += '<div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;">' + escHtml(message) + '</div>';
  html += '<div style="display:flex;gap:8px;justify-content:flex-end;">';
  html += '<button class="btn btn-ghost btn-sm" id="btnConfirmCancel">取消</button>';
  html += '<button class="btn btn-danger btn-sm" id="btnConfirmOk">确认</button></div></div>';
  overlay.innerHTML = html; document.body.appendChild(overlay);
  document.getElementById("btnConfirmOk").onclick = function() { document.body.removeChild(overlay); onConfirm(); };
  document.getElementById("btnConfirmCancel").onclick = function() { document.body.removeChild(overlay); };
  overlay.addEventListener("click", function(e) { if (e.target === overlay) document.body.removeChild(overlay); });
}

function exportConfig() { api.exportConfig().then(function() { showToast("配置已导出","success"); }).catch(function(e) { showToast(errMsg(e, "导出失败"),"error"); }); }
function importConfig() { document.getElementById("importFileInput").click(); }

function emergencyStop() { api.emergencyRelease().then(function() { showToast("紧急停止已执行","success"); loadGroupsFromTauri(); }).catch(function(e) { showToast("紧急停止失败: "+errMsg(e),"error"); }); }
function toggleAll() {
  var anyActive = sampleGroups.some(function(g) { return g.active; });
  api.toggleAll(!anyActive).then(function() {
    _fullConfig = null;
    showToast("全局开关已切换","success");
    loadGroupsFromTauri();
  }).catch(function(e) { showToast(errMsg(e, "操作失败"),"error"); });
}
function hotReload() { api.hotReload().then(function() { _fullConfig = null; showToast("热重载完成","success"); loadGroupsFromTauri(); }).catch(function(e) { showToast(errMsg(e, "热重载失败"),"error"); }); }

function captureHotkey() {
  var d = document.getElementById('hotkeyDisp'); d.classList.add("capturing"); d.textContent = "按键中...";
  var handler = function(e) {
    e.preventDefault(); e.stopPropagation();
    var parts = []; if (e.ctrlKey) parts.push("^"); if (e.altKey) parts.push("!"); if (e.shiftKey) parts.push("+");
    var key = e.key;
    if (key.length === 1) parts.push(key.toUpperCase());
    else if (key.startsWith("F") && key.length <= 3) parts.push(key);
    else if (key === "Enter" || key === "Escape" || key === "Tab" || key === "Space" || key === "Backspace" || key === "Delete") parts.push(key);
    else return;
    d.textContent = parts.join(""); d.classList.remove("capturing");
    document.removeEventListener("keydown", handler, true);
  };
  document.addEventListener("keydown", handler, true);
  _captureTimer = setTimeout(function() { d.classList.remove("capturing"); d.textContent = "点击设置"; document.removeEventListener("keydown", handler, true); }, 5000);
}

function pickMode(el) { var mode = el.getAttribute('data-mode'); if (mode) pickModeByValue(mode); }

function pickModeByValue(mode) {
  currentMode = mode;
  document.querySelectorAll('.mode-pill').forEach(function(p) { p.classList.toggle('active', p.getAttribute('data-mode') === mode); });
  var info = MODE_INFO[mode]; var descEl = document.getElementById('modeDesc');
  if (descEl) descEl.textContent = info ? info.desc : mode;
  var holdSection = document.getElementById('holdSection');
  if (holdSection) holdSection.style.display = (info && info.enhanced) ? 'block' : 'none';
  renderConfigSection(); renderHoldSection(); updatePreview();
}

function renderKeyGrid() {
  var grid = document.getElementById('keyGrid'); if (!grid) return;
  var html = '';
  for (var i = 0; i < ALL_KEYS.length; i++) {
    html += '<div class="picker-section-label">' + ALL_KEYS[i].section + '</div>';
    for (var j = 0; j < ALL_KEYS[i].keys.length; j++) {
      html += '<button class="picker-key" data-key="' + ALL_KEYS[i].keys[j] + '">' + ALL_KEYS[i].keys[j] + '</button>';
    }
  }
  grid.innerHTML = html;
}

function filterKeys() {
  var search = document.getElementById('keySearch').value.toLowerCase();
  var keys = document.querySelectorAll('#keyGrid .picker-key');
  keys.forEach(function(k) { k.style.display = k.textContent.toLowerCase().indexOf(search) >= 0 ? '' : 'none'; });
}

function openKeyPicker(el) {
  keyPickerTarget = el; document.getElementById('keyPickerOverlay').classList.add('show');
  document.getElementById('keySearch').value = ''; filterKeys();
}

function closeKeyPicker() { document.getElementById('keyPickerOverlay').classList.remove('show'); keyPickerTarget = null; }

function openJoyKeyPicker(el) { joyKeyPickerTarget = el; document.getElementById('joyKeyPickerOverlay').classList.add('show'); }
function closeJoyKeyPicker() { document.getElementById('joyKeyPickerOverlay').classList.remove('show'); joyKeyPickerTarget = null; }
function pickJoyKey(key) { if (joyKeyPickerTarget) { joyKeyPickerTarget.textContent = key; closeJoyKeyPicker(); } }

function renderConfigSection() {
  var section = document.getElementById('configSection'); if (!section) return;
  var info = MODE_INFO[currentMode]; if (!info) { section.innerHTML = ''; return; }
  var html = '';
  if (currentMode === "periodic" || currentMode === "sequence") {
    html += '<div class="section-label">按键配置</div>';
    for (var i = 0; i < editorConfig.keys.length; i++) {
      html += '<div class="key-row"><span class="key-cell" data-action="pickKey" data-keys-field="keys" data-intervals-field="intervals" data-idx="'+i+'">'+escHtml(editorConfig.keys[i])+'</span>';
      if (currentMode === "periodic") html += '<input class="input interval-cell" type="number" value="'+editorConfig.intervals[i]+'" data-action="setInterval" data-field="intervals" data-idx="'+i+'" min="10"><span class="unit-label">ms</span>';
      else html += '<input class="input interval-cell" type="number" value="'+editorConfig.delays[i]+'" data-action="setDelay" data-field="delays" data-idx="'+i+'" min="10"><span class="unit-label">ms</span>';
      html += '<button class="del-btn" data-action="deleteKey" data-keys-field="keys" data-intervals-field="intervals" data-idx="'+i+'">×</button></div>';
    }
    html += '<button class="btn-add" data-action="addKey" data-keys-field="keys" data-intervals-field="intervals">+ 添加按键</button>';
  } else if (currentMode === "enhanced_periodic" || currentMode === "enhanced_sequence") {
    html += '<div class="section-label">按键配置</div>';
    for (i = 0; i < editorConfig.pressKeys.length; i++) {
      html += '<div class="key-row"><span class="key-cell" data-action="pickKey" data-keys-field="pressKeys" data-intervals-field="intervals" data-idx="'+i+'">'+escHtml(editorConfig.pressKeys[i])+'</span>';
      if (currentMode === "enhanced_periodic") html += '<input class="input interval-cell" type="number" value="'+editorConfig.intervals[i]+'" data-action="setInterval" data-field="intervals" data-idx="'+i+'" min="10"><span class="unit-label">ms</span>';
      else html += '<input class="input interval-cell" type="number" value="'+editorConfig.pressDelays[i]+'" data-action="setDelay" data-field="pressDelays" data-idx="'+i+'" min="10"><span class="unit-label">ms</span>';
      html += '<button class="del-btn" data-action="deleteKey" data-keys-field="pressKeys" data-intervals-field="intervals" data-idx="'+i+'">×</button></div>';
    }
    html += '<button class="btn-add" data-action="addKey" data-keys-field="pressKeys" data-intervals-field="intervals">+ 添加按键</button>';
  } else if (currentMode === "hybrid" || currentMode === "enhanced_hybrid") {
    html += '<div class="section-label">子组配置</div>';
    for (var gi = 0; gi < editorConfig.groups.length; gi++) {
      var sg = editorConfig.groups[gi];
      html += '<div class="sub-group-card"><div class="sub-group-header"><span class="sub-group-title">子组 '+(gi+1)+' - '+(sg.type||"periodic")+'</span>';
      html += '<button class="del-btn" data-action="deleteSubGroup" data-group="'+gi+'">×</button></div>';
      for (var ki = 0; ki < sg.pressKeys.length; ki++) {
        html += '<div class="key-row"><span class="key-cell" data-action="pickSubKey" data-group="'+gi+'" data-idx="'+ki+'">'+escHtml(sg.pressKeys[ki])+'</span>';
        if (sg.type === "periodic" && sg.intervals) html += '<input class="input interval-cell" type="number" value="'+(sg.intervals[ki]||50)+'" data-action="updateSubVal" data-group="'+gi+'" data-idx="'+ki+'" min="10"><span class="unit-label">ms</span>';
        else if (sg.type === "sequence" && sg.delays) html += '<input class="input interval-cell" type="number" value="'+(sg.delays[ki]||100)+'" data-action="updateSubVal" data-group="'+gi+'" data-idx="'+ki+'" min="10"><span class="unit-label">ms</span>';
        html += '<button class="del-btn" data-action="deleteSubKey" data-group="'+gi+'" data-idx="'+ki+'">×</button></div>';
      }
      html += '<button class="btn-add" data-action="addSubKey" data-group="'+gi+'">+ 添加按键</button></div>';
    }
    html += '<button class="btn-add" data-action="addSubGroup">+ 添加子组</button>';
    html += '<div class="form-row" style="margin-top:8px;"><span class="form-label">子组间隔</span><div class="form-field"><input class="input" type="number" value="'+editorConfig.seqInterval+'" data-action="setSeqInterval" min="10" style="width:80px;text-align:center;"><span class="unit-label">ms</span></div></div>';
  } else if (currentMode === "hold") {
    html += '<div class="section-label">长按配置</div>';
    html += '<div class="form-row"><span class="form-label">持续时长</span><div class="form-field"><div style="display:flex;align-items:center;gap:4px;"><input class="input" type="number" value="'+editorConfig.holdDuration+'" data-action="setHoldDuration" min="0" style="width:80px;text-align:center;"><span class="unit-label">ms (0=无限)</span></div></div></div>';
    html += '<div class="form-row"><span class="form-label">自动重复</span><div class="form-field"><div style="display:flex;align-items:center;gap:8px;"><input type="checkbox" '+(editorConfig.autoRepeat?'checked':'')+' data-action="toggleAutoRepeat"><span style="font-size:10px;color:var(--text-muted);">启用自动重复</span></div></div></div>';
    if (editorConfig.autoRepeat) html += '<div class="form-row"><span class="form-label">重复间隔</span><div class="form-field"><input class="input" type="number" value="'+editorConfig.repeatInterval+'" data-action="setRepeatInterval" min="100" style="width:80px;text-align:center;"><span class="unit-label">ms</span></div></div>';
  } else if (currentMode.startsWith("joystick_")) {
    html += '<div class="section-label">手柄按键配置</div>';
    for (i = 0; i < editorConfig.joyKeys.length; i++) {
      html += '<div class="key-row"><span class="key-cell" data-action="pickJoyKey" data-idx="'+i+'">'+escHtml(editorConfig.joyKeys[i])+'</span>';
      if (currentMode === "joystick_periodic") html += '<input class="input interval-cell" type="number" value="'+editorConfig.joyIntervals[i]+'" data-action="setJoyInterval" data-idx="'+i+'" min="10"><span class="unit-label">ms</span>';
      else if (currentMode === "joystick_sequence") html += '<input class="input interval-cell" type="number" value="'+editorConfig.joyDelays[i]+'" data-action="setJoyDelay" data-idx="'+i+'" min="10"><span class="unit-label">ms</span>';
      html += '<button class="del-btn" data-action="deleteJoyKey" data-idx="'+i+'">×</button></div>';
    }
    html += '<button class="btn-add" data-action="addJoyKey">+ 添加手柄按键</button>';
  }
  section.innerHTML = html;
}

function renderHoldSection() {
  var container = document.getElementById('holdKeysContainer'); if (!container) return;
  var html = '';
  for (var i = 0; i < editorConfig.holdKeys.length; i++) {
    html += '<span class="chip" style="margin:2px;" data-action="deleteHoldChip" data-idx="'+i+'">'+escHtml(editorConfig.holdKeys[i])+' ×</span>';
  }
  html += '<span class="chip" style="margin:2px;border-style:dashed;" data-action="addHoldChip">+</span>';
  container.innerHTML = html;
  renderHoldDetail();
}

function renderHoldDetail() {
  var section = document.getElementById('holdDetailSection'); if (!section) return;
  var html = '';
  if (editorConfig.holdMode === "periodic") {
    // 内联 onchange 属性在 CSP `script-src 'self'` 下会被拦截（且 module 作用域里的
    // 函数本来就取不到），改用 id + addEventListener（见 bindHoldPatternInputs）。
    html += '<div class="form-row"><span class="form-label">按压节律</span><div class="form-field"><span style="font-size:11px;color:var(--text-secondary);">按下 <input class="input" id="holdPatternPress" type="number" value="'+editorConfig.holdPattern[0]+'" style="width:60px;text-align:center;"> ms，释放 <input class="input" id="holdPatternRelease" type="number" value="'+editorConfig.holdPattern[1]+'" style="width:60px;text-align:center;"> ms</span></div></div>';
  } else if (editorConfig.holdMode === "sequence") {
    html += '<div class="form-row"><span class="form-label">触发序列</span><div class="form-field"><span style="font-size:11px;color:var(--text-secondary);">1=按下, 0=释放</span></div></div>';
    for (var i = 0; i < editorConfig.holdTriggers.length; i++) {
      html += '<span class="chip" style="margin:2px;">'+(editorConfig.holdTriggers[i]?'↓':'↑')+'</span>';
    }
  }
  section.innerHTML = html;
  bindHoldPatternInputs();
}

// 按压节律两个输入框的绑定。它们由 renderHoldDetail 动态生成，故每次渲染后重新绑定。
function bindHoldPatternInputs() {
  var press = document.getElementById('holdPatternPress');
  var release = document.getElementById('holdPatternRelease');
  if (press) press.addEventListener('change', function() { pushUndoState(); editorConfig.holdPattern[0] = parseInt(this.value) || 500; });
  if (release) release.addEventListener('change', function() { pushUndoState(); editorConfig.holdPattern[1] = parseInt(this.value) || 200; });
}

function updatePreview() {
  var timeline = document.getElementById('previewTimeline'); if (!timeline) return;
  var html = ''; var info = MODE_INFO[currentMode]; if (!info) return;
  var keys, intervals;
  if (currentMode === "periodic" || currentMode === "sequence") { keys = editorConfig.keys; intervals = currentMode === "periodic" ? editorConfig.intervals : editorConfig.delays; }
  else if (currentMode === "enhanced_periodic" || currentMode === "enhanced_sequence") { keys = editorConfig.pressKeys; intervals = currentMode === "enhanced_periodic" ? editorConfig.intervals : editorConfig.pressDelays; }
  else if (currentMode === "hold") { keys = editorConfig.holdKeys; intervals = []; }
  else { keys = []; intervals = []; }
  if (keys.length === 0) { timeline.innerHTML = '<span style="color:var(--text-muted);font-size:11px;">添加按键后显示预览</span>'; return; }
  for (var i = 0; i < Math.min(keys.length, 8); i++) {
    if (i > 0) html += '<span class="timeline-arrow">→</span>';
    html += '<span class="timeline-key">'+escHtml(keys[i])+'</span>';
    if (i < intervals.length) html += '<span class="timeline-time">'+intervals[i]+'ms</span>';
  }
  if (keys.length > 8) html += '<span class="timeline-arrow">...</span>';
  html += '<span class="timeline-loop">↻ 循环</span>';
  if (editorConfig.holdKeys && editorConfig.holdKeys.length > 0 && info.enhanced) {
    html += '<span class="timeline-arrow">+</span><span class="timeline-hold">⏳ ' + escHtml(editorConfig.holdKeys.join(',')) + '</span>';
  }
  timeline.innerHTML = html;
}

function addKeyTo(keysField, intervalsField) {
  pushUndoState();
  editorConfig[keysField].push("?"); editorConfig[intervalsField].push(50);
  renderConfigSection(); updatePreview();
}

function deleteKeyFrom(keysField, intervalsField, idx) {
  pushUndoState();
  editorConfig[keysField].splice(idx, 1); editorConfig[intervalsField].splice(idx, 1);
  renderConfigSection(); updatePreview();
}

function addSubGroup() { pushUndoState(); editorConfig.groups.push({type:"periodic",pressKeys:["?"],intervals:[50]}); renderConfigSection(); updatePreview(); }
function deleteSubGroup(gi) { pushUndoState(); editorConfig.groups.splice(gi, 1); renderConfigSection(); updatePreview(); }
function addSubKey(gi) { pushUndoState(); editorConfig.groups[gi].pressKeys.push("?"); if (editorConfig.groups[gi].intervals) editorConfig.groups[gi].intervals.push(50); if (editorConfig.groups[gi].delays) editorConfig.groups[gi].delays.push(100); renderConfigSection(); updatePreview(); }
function deleteSubKey(gi, ki) { pushUndoState(); editorConfig.groups[gi].pressKeys.splice(ki, 1); if (editorConfig.groups[gi].intervals) editorConfig.groups[gi].intervals.splice(ki, 1); if (editorConfig.groups[gi].delays) editorConfig.groups[gi].delays.splice(ki, 1); renderConfigSection(); updatePreview(); }
function updateSubVal(gi, ki, val) { pushUndoState(); var v = parseInt(val); var sg = editorConfig.groups[gi]; if (sg.type === "periodic" && sg.intervals) sg.intervals[ki] = v >= 10 ? v : 50; else if (sg.type === "sequence" && sg.delays) sg.delays[ki] = v >= 10 ? v : 100; updatePreview(); }
function changeSubGroupType(gi, type) { pushUndoState(); editorConfig.groups[gi].type = type; if (type === "periodic" && !editorConfig.groups[gi].intervals) editorConfig.groups[gi].intervals = editorConfig.groups[gi].pressKeys.map(function() { return 50; }); if (type === "sequence" && !editorConfig.groups[gi].delays) editorConfig.groups[gi].delays = editorConfig.groups[gi].pressKeys.map(function() { return 100; }); renderConfigSection(); updatePreview(); }

function deleteJoyKeyField(idx) { pushUndoState(); editorConfig.joyKeys.splice(idx, 1); editorConfig.joyIntervals.splice(idx, 1); editorConfig.joyDelays.splice(idx, 1); renderConfigSection(); updatePreview(); }
function addJoyKeyField() { pushUndoState(); editorConfig.joyKeys.push("?"); editorConfig.joyIntervals.push(50); editorConfig.joyDelays.push(100); renderConfigSection(); updatePreview(); }

var _recEvents = []; var _valEvents = [];
var _eventListMaxNodes = 200; 
var _valExpectedSeq = []; var _valExpectedIntervals = [];

function onBridgeEvent(evt) {
  if (typeof evt === "string") { try { evt = JSON.parse(evt); } catch(ex) { return; } }
  if (!evt || !evt.type) return;
  if (evt.type === "keyRecordEvent" && evt.data) {
    if (_recEvents.length >= 10000) return;
    _recEvents.push(evt.data); document.getElementById("recEventCount").textContent = _recEvents.length;
    drawTimeline("recTimeline", _recEvents); appendRecEvent(evt.data); updateRecStats();
  } else if (evt.type === "keySendEvent" && evt.data) {
    if (_valEvents.length >= 10000) return;
    _valEvents.push(evt.data); document.getElementById("valEventCount").textContent = _valEvents.length;
    drawTimeline("valTimeline", _valEvents); appendValEvent(evt.data); updateValLiveStats();
  }
}

function appendValEvent(evt) {
  var list = document.getElementById("valEventList"); if (!list) return;
  while (list.childNodes.length >= _eventListMaxNodes) list.removeChild(list.firstChild);
  var line = document.createElement("div"); line.style.padding = "2px 0"; line.style.borderBottom = "1px solid var(--border)";
  var dev = evt.device === "mouse" ? "🖱" : "⌨"; var ev = evt.event === "down" ? "↓" : (evt.event === "up" ? "↑" : "●");
  var devColor = evt.device === "mouse" ? "#2196F3" : "#4CAF50";
  var span = document.createElement("span"); span.style.color = devColor; span.textContent = dev + " " + ev;
  line.appendChild(span); line.appendChild(document.createTextNode(" " + evt.key + "  " + evt.timestamp + "ms"));
  list.appendChild(line); list.scrollTop = list.scrollHeight;
}

function updateValLiveStats() {
  var panel = document.getElementById("valLiveStats"); if (!panel) return; panel.style.display = "";
  var n = _valEvents.length; document.getElementById("valLiveCount").textContent = n;
  if (n >= 2) { var sumDev = 0; var maxDev = 0; var devCount = 0; var keyIdx = 0;
    for (var i = 1; i < n; i++) { var interval = _valEvents[i].timestamp - _valEvents[i - 1].timestamp;
      if (_valEvents[i].event === "down" && _valEvents[i - 1].event === "up") { var expected = (_valExpectedIntervals.length > 0 && keyIdx < _valExpectedIntervals.length) ? _valExpectedIntervals[keyIdx] : 50; if (expected <= 0) expected = 50; var dev = Math.abs(interval - expected) / expected * 100; sumDev += dev; if (dev > maxDev) maxDev = dev; devCount++; keyIdx++; } }
    document.getElementById("valLiveAvgDev").textContent = devCount > 0 ? (sumDev / devCount).toFixed(1) + "%" : "-";
    document.getElementById("valLiveMaxDev").textContent = devCount > 0 ? maxDev.toFixed(1) + "%" : "-";
  } else { document.getElementById("valLiveAvgDev").textContent = "-"; document.getElementById("valLiveMaxDev").textContent = "-"; }
  var firstTs = _valEvents.length > 0 ? _valEvents[0].timestamp : 0; var lastTs = _valEvents.length > 0 ? _valEvents[_valEvents.length - 1].timestamp : 0;
  document.getElementById("valLiveDuration").textContent = ((lastTs - firstTs) / 1000).toFixed(1);
}

function updateRecStats() {
  var count = _recEvents.length; document.getElementById("statKeyCount").textContent = count;
  if (count > 1) { var sum = 0; var kb = 0, ms = 0;
    for (var i = 0; i < count; i++) { if (_recEvents[i].device === "mouse") ms++; else kb++; if (i > 0) sum += _recEvents[i].timestamp - _recEvents[i - 1].timestamp; }
    document.getElementById("statAvgInterval").textContent = Math.round(sum / (count - 1)); document.getElementById("statDuration").textContent = _recEvents[count - 1].timestamp; document.getElementById("statDeviceRatio").textContent = kb + "/" + ms;
  } else { document.getElementById("statAvgInterval").textContent = "-"; document.getElementById("statDuration").textContent = count > 0 ? _recEvents[0].timestamp : "0"; var kb2 = 0, ms2 = 0; for (i = 0; i < count; i++) { if (_recEvents[i].device === "mouse") ms2++; else kb2++; } document.getElementById("statDeviceRatio").textContent = kb2 + "/" + ms2; }
}

function appendRecEvent(evt) {
  var list = document.getElementById("recEventList"); while (list.childNodes.length >= _eventListMaxNodes) list.removeChild(list.firstChild);
  var line = document.createElement("div"); line.style.padding = "2px 0"; line.style.borderBottom = "1px solid var(--border)";
  line.style.display = "flex"; line.style.justifyContent = "space-between"; line.style.alignItems = "center";
  var dev = evt.device === "mouse" ? "🖱" : "⌨"; var ev = evt.event === "down" ? "↓" : "↑";
  var span = document.createElement("span"); span.textContent = dev + " " + ev + " " + evt.key + "  " + evt.timestamp + "ms";
  line.appendChild(span); list.appendChild(line); list.scrollTop = list.scrollHeight;
}

var _timelineRafPending = {};
function drawTimeline(canvasId, events) {
  if (_timelineRafPending[canvasId]) return;
  _timelineRafPending[canvasId] = requestAnimationFrame(function() { _timelineRafPending[canvasId] = null; var isValidate = canvasId === "valTimeline"; var expected = isValidate && typeof _valExpectedSeq !== "undefined" ? _valExpectedSeq : []; MiniChart.update(canvasId, { events: events, expected: expected }); });
}

function startRecording() {
  var gid = document.getElementById("recGroupId").value;
  if (!gid) { showToast("请选择录制分组","error"); return; }
  _recEvents = [];
  document.getElementById("recEventList").textContent = ""; document.getElementById("recEventCount").textContent = "0";
  document.getElementById("recStatus").textContent = "录制中..."; document.getElementById("recStatus").style.color = "#4CAF50";
  document.querySelector('[data-action="startRecording"]').disabled = true; document.querySelector('[data-action="pauseRecording"]').disabled = false;
  document.querySelector('[data-action="stopRecording"]').disabled = false; document.querySelector('[data-action="exportRecording"]').disabled = true;
  api.startRecording(gid, "periodic").then(function() {}).catch(function(e) { resetRecUI(); showToast("启动录制失败: " + errMsg(e), "error"); });
}

function pauseRecording() {
  api.pauseRecording().then(function() { showToast("暂停/继续功能开发中","warning"); }).catch(function(e) { showToast(errMsg(e, "暂停录制失败"), "error"); });
}

function stopRecording() {
  api.stopRecording().then(function() {
    document.getElementById("recStatus").textContent = "已停止"; document.getElementById("recStatus").style.color = "";
    document.querySelector('[data-action="startRecording"]').disabled = false; document.querySelector('[data-action="pauseRecording"]').disabled = true;
    document.querySelector('[data-action="stopRecording"]').disabled = true; document.querySelector('[data-action="exportRecording"]').disabled = false;
    document.querySelector('[data-action="clearRecording"]').disabled = false; showToast("录制完成，共 " + _recEvents.length + " 个事件");
  }).catch(function(e) { resetRecUI(); showToast("停止录制失败: " + errMsg(e), "error"); });
}

function exportRecording() {
  // ⚠️ 这里原先调用 api.exportRecording(mode, dur)，与 Rust 命令的签名
  //    (path, keys, intervals, delays, mode) 完全对不上（参数错位且漏传 delays），
  //    于是每次点导出都走 catch —— 用户看到的是「导出失败」而不是下面这句「开发中」。
  //    录制导出需要文件路径与按键/间隔序列，而当前 UI 还没有路径选择器，
  //    所以如实告知「开发中」，不再发一个必然失败的请求。
  //    （api.js 与 Rust 的签名一致性由 src/__tests__/api_contract.test.js 守住）
  showToast("导出功能开发中", "warning");
}

function clearRecording() {
  _recEvents = []; document.getElementById("recEventList").innerHTML = ""; document.getElementById("recEventCount").textContent = "0";
  document.getElementById("statKeyCount").textContent = "0"; document.getElementById("statAvgInterval").textContent = "-";
  document.getElementById("statDuration").textContent = "0"; document.getElementById("statDeviceRatio").textContent = "0/0";
  drawTimeline("recTimeline", []); document.querySelector('[data-action="exportRecording"]').disabled = true;
  document.querySelector('[data-action="clearRecording"]').disabled = true; showToast("录制数据已清除", "success");
}

function resetRecUI() {
  document.getElementById("recStatus").textContent = "就绪"; document.getElementById("recStatus").style.color = "";
  document.querySelector('[data-action="startRecording"]').disabled = false; document.querySelector('[data-action="pauseRecording"]').disabled = true;
  document.querySelector('[data-action="stopRecording"]').disabled = true; document.querySelector('[data-action="exportRecording"]').disabled = true;
  document.querySelector('[data-action="clearRecording"]').disabled = true;
}

var _refreshGroupListRetries = 0;
function refreshGroupList() {
  api.getGroupListForValidation().then(function(r) {
    _refreshGroupListRetries = 0;
    var groups = typeof r === "string" ? JSON.parse(r) : r;
    if (Array.isArray(groups)) {
      var sel = document.getElementById("validateGroupId");
      sel.innerHTML = '<option value="">-- 选择分组 --</option>';
      for (var i = 0; i < groups.length; i++) { var opt = document.createElement("option"); opt.value = groups[i].id; opt.textContent = groups[i].id + " (" + groups[i].mode + ")" + (groups[i].active ? " ●" : ""); sel.appendChild(opt); }
      var recSel = document.getElementById("recGroupId");
      if (recSel) {
        recSel.innerHTML = '<option value="">-- 选择分组 --</option>';
        for (i = 0; i < groups.length; i++) { var opt2 = document.createElement("option"); opt2.value = groups[i].id; opt2.textContent = groups[i].id + " (" + groups[i].mode + ")" + (groups[i].active ? " ●" : ""); recSel.appendChild(opt2); }
      }
    }
  }).catch(function() { if (_refreshGroupListRetries < 3) { _refreshGroupListRetries++; setTimeout(refreshGroupList, 1000 * _refreshGroupListRetries); } });
}

function startValidation() {
  var gid = document.getElementById("validateGroupId").value; if (!gid) { showToast("请选择分组","error"); return; }
  _valEvents = []; _valExpectedSeq = []; _valExpectedIntervals = [];
  document.getElementById("valEventCount").textContent = "0"; document.getElementById("valStatus").textContent = "验证中...";
  document.getElementById("valStatus").style.color = "#4CAF50";
  document.getElementById("valEventList").innerHTML = ""; document.getElementById("valLiveStats").style.display = "none";
  document.querySelector('[data-action="startValidation"]').disabled = true; document.querySelector('[data-action="stopValidation"]').disabled = false;
  api.startValidation(gid).then(function() {}).catch(function(e) { resetValUI(); showToast(errMsg(e, "启动验证失败"),"error"); });
}

function stopValidation() {
  var gid = document.getElementById("validateGroupId").value;
  api.stopValidation(gid).then(function() {
    document.getElementById("valStatus").textContent = "已完成"; document.getElementById("valStatus").style.color = "#4CAF50";
    document.querySelector('[data-action="startValidation"]').disabled = false; document.querySelector('[data-action="stopValidation"]').disabled = true;
    showToast("验证完成，共 " + _valEvents.length + " 个事件");
  }).catch(function(e) { resetValUI(); showToast(errMsg(e, "停止验证失败"),"error"); });
}

function resetValUI() {
  document.getElementById("valStatus").textContent = "就绪"; document.getElementById("valStatus").style.color = "";
  document.querySelector('[data-action="startValidation"]').disabled = false; var stopBtn = document.querySelector('[data-action="stopValidation"]'); stopBtn.disabled = true;
  var liveStats = document.getElementById("valLiveStats"); if (liveStats) liveStats.style.display = "none";
  var eventList = document.getElementById("valEventList"); if (eventList) eventList.innerHTML = "";
  document.getElementById("valEventCount").textContent = "0";
}



function initKeyTestPage() {
  var tabs = document.querySelectorAll(".keytest-tab");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].addEventListener("click", function() {
      for (var j = 0; j < tabs.length; j++) { tabs[j].classList.remove("active"); tabs[j].classList.remove("btn-primary"); tabs[j].classList.add("btn-ghost"); }
      this.classList.add("active"); this.classList.remove("btn-ghost"); this.classList.add("btn-primary");
      var tab = this.getAttribute("data-tab");
      document.getElementById("panel-record").style.display = tab === "record" ? "" : "none";
      document.getElementById("panel-validate").style.display = tab === "validate" ? "" : "none";
      if (tab === "validate") refreshGroupList();
    });
  }
  drawTimeline("recTimeline", []); drawTimeline("valTimeline", []);
  refreshGroupList();
  var _resizeTimer = null;
  window.addEventListener("resize", function() { clearTimeout(_resizeTimer); _resizeTimer = setTimeout(function() { var chartIds = Object.keys(MiniChart._charts); for (var i = 0; i < chartIds.length; i++) { var c = MiniChart._charts[chartIds[i]]; if (c && c.canvas) { MiniChart._resizeCanvas(c.canvas); MiniChart.render(chartIds[i]); } } }, 200); });
}

function init() {
  applyTheme();
  // 原先写在 index.html 上的内联 onchange/oninput 已被移除：它们在 module 作用域下
  // 取不到函数（本来就抛 ReferenceError），且 CSP `script-src 'self'` 会拦截内联处理器。
  var holdModeSel = document.getElementById("holdModeSelect");
  if (holdModeSel) holdModeSel.addEventListener("change", function() { pushUndoState(); editorConfig.holdMode = this.value; renderHoldDetail(); updatePreview(); });
  var keySearchEl = document.getElementById("keySearch");
  if (keySearchEl) keySearchEl.addEventListener("input", filterKeys);
  var langSel = document.getElementById("langSelect"); if (langSel) { langSel.value = _currentLang; langSel.addEventListener("change", function() { switchLang(this.value); }); }
  applyTranslations(); renderKeyGrid(); pickModeByValue(currentMode);
  renderDashboard(); renderBackupList(); initKeyTestPage();

  document.getElementById('importFileInput').addEventListener('change', function(e) {
    if (e.target.files && e.target.files[0]) { importGroupsFromFile(e.target.files[0]); e.target.value = ''; }
  });

  document.querySelector('.nav-items').onclick = function(e) { var item = e.target.closest('.nav-item[data-page]'); if (item) switchPage(item.getAttribute('data-page')); };
  document.querySelector('.topbar-actions').onclick = function(e) {
    var btn = e.target.closest('[data-action]'); if (!btn) return;
    var action = btn.getAttribute('data-action');
    if (action === 'emergencyStop') emergencyStop(); else if (action === 'toggleAll') toggleAll(); else if (action === 'hotReload') hotReload();
  };

  document.getElementById('configSection').onclick = function(e) {
    var el = e.target.closest('[data-action]'); if (!el) return;
    var action = el.getAttribute('data-action');
    if (action === 'pickKey' || action === 'pickSubKey') openKeyPicker(el);
    else if (action === 'deleteKey') deleteKeyFrom(el.getAttribute('data-keys-field'), el.getAttribute('data-intervals-field'), parseInt(el.getAttribute('data-idx')));
    else if (action === 'addKey') addKeyTo(el.getAttribute('data-keys-field'), el.getAttribute('data-intervals-field'));
    else if (action === 'addSubGroup') addSubGroup();
    else if (action === 'deleteSubGroup') deleteSubGroup(parseInt(el.getAttribute('data-group')));
    else if (action === 'addSubKey') addSubKey(parseInt(el.getAttribute('data-group')));
    else if (action === 'deleteSubKey') deleteSubKey(parseInt(el.getAttribute('data-group')), parseInt(el.getAttribute('data-idx')));
    else if (action === 'deleteHoldKey') { pushUndoState(); editorConfig.holdKeys.splice(parseInt(el.getAttribute('data-idx')),1); renderConfigSection(); updatePreview(); }
    else if (action === 'addHoldKey') { pushUndoState(); editorConfig.holdKeys.push('?'); renderConfigSection(); updatePreview(); }
    else if (action === 'pickJoyKey') openJoyKeyPicker(el);
    else if (action === 'deleteJoyKey') deleteJoyKeyField(parseInt(el.getAttribute('data-idx')));
    else if (action === 'addJoyKey') addJoyKeyField();
  };

  document.getElementById('configSection').addEventListener('change', function(e) {
    var el = e.target.closest('[data-action]'); if (!el) return;
    var action = el.getAttribute('data-action');
    if (action === 'setInterval') { pushUndoState(); var v=parseInt(el.value); editorConfig[el.getAttribute('data-field')][parseInt(el.getAttribute('data-idx'))]=(v>=10?v:50); updatePreview(); }
    else if (action === 'setDelay') { pushUndoState(); var v2=parseInt(el.value); editorConfig[el.getAttribute('data-field')][parseInt(el.getAttribute('data-idx'))]=(v2>=10?v2:100); updatePreview(); }
    else if (action === 'updateSubVal') updateSubVal(parseInt(el.getAttribute('data-group')), parseInt(el.getAttribute('data-idx')), el.value);
    else if (action === 'changeSubGroupType') changeSubGroupType(parseInt(el.getAttribute('data-group')), el.value);
    else if (action === 'setSeqInterval') { pushUndoState(); var sv=parseInt(el.value); editorConfig.seqInterval=(sv>0?sv:100); }
    else if (action === 'setHoldDuration') { pushUndoState(); editorConfig.holdDuration=parseInt(el.value)||0; updatePreview(); }
    else if (action === 'toggleAutoRepeat') { pushUndoState(); editorConfig.autoRepeat=el.checked; updatePreview(); }
    else if (action === 'setRepeatInterval') { pushUndoState(); var rv=parseInt(el.value); editorConfig.repeatInterval=(rv>0?rv:1000); updatePreview(); }
    else if (action === 'setJoyInterval') { pushUndoState(); v=parseInt(el.value); editorConfig.joyIntervals[parseInt(el.getAttribute('data-idx'))]=(v>=10?v:50); updatePreview(); }
    else if (action === 'setJoyDelay') { pushUndoState(); v=parseInt(el.value); editorConfig.joyDelays[parseInt(el.getAttribute('data-idx'))]=(v>=10?v:100); updatePreview(); }
  });

  document.getElementById('holdKeysContainer').onclick = function(e) {
    var el = e.target.closest('[data-action]'); if (!el) return;
    var action = el.getAttribute('data-action');
    if (action === 'deleteHoldChip') { pushUndoState(); editorConfig.holdKeys.splice(parseInt(el.getAttribute('data-idx')),1); renderHoldSection(); updatePreview(); }
    else if (action === 'addHoldChip') { pushUndoState(); editorConfig.holdKeys.push('?'); renderHoldSection(); updatePreview(); }
  };

  document.querySelector('.content').onclick = function(e) {
    var el = e.target.closest('[data-action]'); if (!el) return;
    var action = el.getAttribute('data-action');
    if (action === 'addNewGroup') { switchPage('editor'); resetEditor(); }
    else if (action === 'exportAllGroups') exportAllGroups();
    else if (action === 'importGroups') document.getElementById('importFileInput').click();
    else if (action === 'captureHotkey') captureHotkey();
    else if (action === 'undoEditor') undoEditor();
    else if (action === 'redoEditor') redoEditor();
    else if (action === 'cancelEditor') switchPage('dashboard');
    else if (action === 'saveConfig') saveConfig();
    else if (action === 'toggleOverlap') el.classList.toggle('on');
    else if (action === 'toggleRelease') el.classList.toggle('on');
    else if (action === 'cancelSettings') showToast('已取消','');
    else if (action === 'saveSettings') saveSettings();
    else if (action === 'exportConfig') exportConfig();
    else if (action === 'importConfig') importConfig();
    else if (action === 'toggleBatchMode') toggleBatchMode();
    else if (action === 'exitBatchMode') toggleBatchMode();
    else if (action === 'batchActivate') batchToggleSelected(true);
    else if (action === 'batchDeactivate') batchToggleSelected(false);
    else if (action === 'batchDelete') batchDeleteSelected();
    else if (action === 'compareConfig') compareConfigs();
    else if (action === 'toggleTheme') toggleTheme();
    else if (action === 'templatePeriodic') applyTemplate('periodic');
    else if (action === 'templateSequence') applyTemplate('sequence');
    else if (action === 'templateHold') applyTemplate('hold');
    else if (action === 'templateEnhancedPeriodic') applyTemplate('enhanced_periodic');
    else if (action === 'templateEnhancedSequence') applyTemplate('enhanced_sequence');
    else if (action === 'clearLogs') clearLogs();
    else if (action === 'toggleAutoScroll') toggleAutoScroll();
    else if (action === 'createBackup') createBackup();
    else if (action === 'closeKeyPicker') closeKeyPicker();
    else if (action === 'closeJoyKeyPicker') closeJoyKeyPicker();
    else if (action === 'selectJoyKey') { pickJoyKey(el.getAttribute('data-key')); }
    else if (action === 'templateJoystickPeriodic') applyTemplate('joystick_periodic');
    else if (action === 'templateJoystickSequence') applyTemplate('joystick_sequence');
    else if (action === 'templateJoystickHold') applyTemplate('joystick_hold');
    else if (action === 'pickMode') pickMode(el);
    else if (action === 'startRecording') startRecording();
    else if (action === 'pauseRecording') pauseRecording();
    else if (action === 'stopRecording') stopRecording();
    else if (action === 'exportRecording') exportRecording();
    else if (action === 'clearRecording') clearRecording();
    else if (action === 'startValidation') startValidation();
    else if (action === 'stopValidation') stopValidation();
    else if (action === 'refreshGroupList') refreshGroupList();
    else if (action === 'copyDiagnostics') copyDiagnostics();
    else if (action === 'refreshDiagnostics') loadDiagnostics();
    else if (action === 'resetWatchdog') resetWatchdogDiag();
  };

  document.getElementById('keyPickerOverlay').onclick = function(e) {
    var key = e.target.closest('.picker-key');
    if (key && keyPickerTarget) { keyPickerTarget.textContent = key.getAttribute('data-key'); closeKeyPicker(); return; }
    if (e.target === this || e.target.closest('[data-action="closeKeyPicker"]')) closeKeyPicker();
  };

  document.getElementById('joyKeyPickerOverlay').onclick = function(e) {
    if (e.target === this || e.target.closest('[data-action="closeJoyKeyPicker"]')) closeJoyKeyPicker();
  };

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') { var overlays = document.querySelectorAll('.overlay.show'); if (overlays.length > 0) overlays[overlays.length - 1].classList.remove('show'); }
  });

  var _groupSearchInput = document.getElementById("groupSearch");
  if (_groupSearchInput) _groupSearchInput.addEventListener("input", function() { _searchTerm = this.value; renderDashboard(); });
  var _groupFilterSelect = document.getElementById("groupFilter");
  if (_groupFilterSelect) _groupFilterSelect.addEventListener("change", function() { _filterMode = this.value; renderDashboard(); });

  var _hotkeyInputs = document.querySelectorAll(".hotkey-input");
  for (var _hi = 0; _hi < _hotkeyInputs.length; _hi++) {
    _hotkeyInputs[_hi].addEventListener("input", function() {
      var errEl = document.getElementById(this.id + "Error"); if (!errEl) return;
      var result = validateHotkeyFormat(this.value);
      if (!result.valid) { errEl.textContent = result.msg; errEl.className = "validation-msg error"; }
      else { errEl.textContent = ""; errEl.className = "validation-msg"; }
    });
  }

  var _captureBtns = document.querySelectorAll(".capture-btn");
  for (var _ci = 0; _ci < _captureBtns.length; _ci++) {
    _captureBtns[_ci].addEventListener("click", function() {
      var targetId = this.getAttribute("data-capture"); var input = document.getElementById(targetId); if (!input) return;
      var btn = this; btn.textContent = "..."; btn.style.background = "var(--accent-glow)";
      var handler = function(e) {
        e.preventDefault(); e.stopPropagation(); var parts = [];
        if (e.ctrlKey) parts.push("^"); if (e.altKey) parts.push("!"); if (e.shiftKey) parts.push("+");
        var key = e.key;
        if (key.length === 1) parts.push(key.toUpperCase());
        else if (key.startsWith("F") && key.length <= 3) parts.push(key);
        else if (key === "Enter" || key === "Escape" || key === "Tab" || key === "Space" || key === "Backspace" || key === "Delete") parts.push(key);
        else return;
        input.value = parts.join(""); input.dispatchEvent(new Event("input")); btn.textContent = "⌨"; btn.style.background = "";
        document.removeEventListener("keydown", handler, true);
      };
      document.addEventListener("keydown", handler, true);
      setTimeout(function() { document.removeEventListener("keydown", handler, true); btn.textContent = "⌨"; btn.style.background = ""; }, 5000);
    });
  }

  api.onStatusUpdate(function(data) {
    if (data && data.groups) {
      sampleGroups = data.groups;
    }
    updateDashboard(data);
  });
  api.onHotkeyEvent(function(data) { addLog("热键触发: " + (data.hotkey || data.key || JSON.stringify(data)), "debug"); });
  api.onExecutorStatus(function(data) {
    var statusDot = document.getElementById("statusDot"); var statusText = document.getElementById("statusText");
    if (statusDot && data.status) {
      statusText.textContent = EXEC_STATUS_MAP[data.status] || data.status;
      statusDot.className = "nav-status-dot" + (data.status === "Running" ? "" : data.status === "Failed" ? " error" : " warning");
    }
    renderExecutorStatus(data);
    // 只在「刚变成 Failed」时提示一次：圆点变色容易被忽略，必须给一个明确的失败告知
    // 与自助恢复指引（对应 TD-082；onIpcListenerFailed 已有同样的 addLog+showToast 模式）。
    if (data.status === "Failed" && _lastExecStatus !== "Failed") {
      addLog("执行器进入失败态（重启次数已耗尽），自动化功能不可用", "error");
      showToast("执行器启动失败：可在「诊断信息」页点「重置看门狗」自助恢复", "error");
    }
    _lastExecStatus = data.status || _lastExecStatus;
  });
  api.onKeyRecordEvent(function(data) { onBridgeEvent({type: "keyRecordEvent", data: data}); });
  api.onKeySendEvent(function(data) { onBridgeEvent({type: "keySendEvent", data: data}); });
  // IPC 监听端建不起来时 AHK 子进程永远连不上，必须弹提示，不能静默降级。
  api.onIpcListenerFailed(function(msg) {
    addLog("IPC 不可用: " + (msg || "未知原因"), "error");
    showToast("IPC 连接失败，自动化功能不可用", "error");
  });

  loadGroupsFromTauri();
  loadBackupsFromTauri();
  loadSettingsFromTauri();
}

init();
