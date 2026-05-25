#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"

class HTMLEditor {
    static gui := ""
    static wb := ""
    static callback := ""

    static Open(id := "", isNew := false, config := "", onSaveCallback := "") {
        HTMLEditor.callback := onSaveCallback

        if HTMLEditor.gui {
            try HTMLEditor.gui.Destroy()
        }

        title := isNew ? "添加新分组" : "编辑分组 " id
        HTMLEditor.gui := Gui("+Resize +MinSize560x680", title)

        HTMLEditor.wb := HTMLEditor.gui.Add("ActiveX", "w560 h680", "Shell.Explorer")
        HTMLEditor.gui.OnEvent("Close", (*) => HTMLEditor._Close())
        HTMLEditor.gui.OnEvent("Size", HTMLEditor._OnResize)

        HTMLEditor.gui.Show("w560 h680")

        HTMLEditor._LoadHTML(id, isNew, config)
    }

    static _OnResize(g, m, w, h) {
        HTMLEditor.wb.Move(0, 0, w, h)
    }

    static _Close() {
        HTMLEditor.gui.Destroy()
        HTMLEditor.gui := ""
        HTMLEditor.wb := ""
    }

    static _LoadHTML(id, isNew, config) {
        html := HTMLEditor._GetHTML(id, isNew, config)
        HTMLEditor.wb.Navigate("about:blank")
        while HTMLEditor.wb.ReadyState != 4
            Sleep 10
        HTMLEditor.wb.Document.Write(html)
        HTMLEditor.wb.Document.Close()

        ComObjConnect(HTMLEditor.wb, HTMLEditor._CreateEventHandlers())
    }

    static _CreateEventHandlers() {
        handlers := {}
        handlers.DocumentComplete := (wb, pdisp, url) => {}
        return handlers
    }

    static _GetHTML(id, isNew, config) {
        configJSON := config != "" ? JSONSerializer.Stringify(config) : "{}"

        return '
        (LTrim
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: "Segoe UI", "Microsoft YaHei", sans-serif;
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 50%, #f093fb 100%);
  background-attachment: fixed;
  display: flex;
  justify-content: center;
  align-items: flex-start;
  padding: 16px;
}
.glass { background: rgba(255,255,255,0.12); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.18); border-radius: 16px; }
.glass-input { background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.2); border-radius: 8px; color: #fff; padding: 7px 10px; font-size: 12px; outline: none; width: 100%; transition: border-color 0.2s; }
.glass-input:focus { border-color: rgba(255,255,255,0.5); }
.glass-input::placeholder { color: rgba(255,255,255,0.35); }
select.glass-input { appearance: none; background-image: url("data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 width=%2712%27 height=%2712%27 fill=%27rgba(255,255,255,0.6)%27 viewBox=%270 0 16 16%27%3E%3Cpath d=%27M8 11L3 6h10z%27/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 8px center; padding-right: 24px; cursor: pointer; }
select.glass-input option { background: #2d1b69; color: #fff; }
.btn { border: none; border-radius: 8px; padding: 7px 16px; font-size: 11px; cursor: pointer; transition: all 0.15s; font-family: inherit; }
.btn:hover { filter: brightness(1.1); }
.btn-success { background: rgba(76,175,80,0.5); color: #fff; }
.btn-ghost { background: rgba(255,255,255,0.08); color: rgba(255,255,255,0.7); border: 1px solid rgba(255,255,255,0.12); }
.btn-sm { padding: 4px 10px; font-size: 10px; border-radius: 6px; }
.btn-icon { background: rgba(255,255,255,0.1); color: rgba(255,255,255,0.7); border: none; border-radius: 6px; width: 28px; height: 28px; display: inline-flex; align-items: center; justify-content: center; cursor: pointer; font-size: 12px; }

.panel { width: 520px; max-height: 96vh; display: flex; flex-direction: column; }
.panel-header { display: flex; justify-content: space-between; align-items: center; padding: 14px 18px; border-bottom: 1px solid rgba(255,255,255,0.1); }
.panel-title { color: #fff; font-size: 14px; font-weight: 600; }
.panel-body { padding: 14px 18px; overflow-y: auto; flex: 1; }
.panel-footer { padding: 10px 18px; border-top: 1px solid rgba(255,255,255,0.1); display: flex; justify-content: space-between; align-items: center; }

.section { margin-bottom: 14px; }
.section-title { color: rgba(255,255,255,0.5); font-size: 9px; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; padding-bottom: 4px; border-bottom: 1px solid rgba(255,255,255,0.06); }
.form-row { display: flex; gap: 8px; margin-bottom: 8px; align-items: center; }
.form-row .label { color: rgba(255,255,255,0.6); font-size: 11px; min-width: 60px; flex-shrink: 0; }
.form-row .field { flex: 1; }

.mode-select { display: flex; gap: 4px; flex-wrap: wrap; }
.mode-opt { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.1); border-radius: 6px; padding: 4px 10px; color: rgba(255,255,255,0.5); font-size: 10px; cursor: pointer; transition: all 0.15s; }
.mode-opt:hover { background: rgba(255,255,255,0.1); color: rgba(255,255,255,0.8); }
.mode-opt.active { background: rgba(103,126,234,0.3); border-color: rgba(103,126,234,0.5); color: #c5caff; }

.hotkey-display { background: rgba(103,126,234,0.2); border: 1px solid rgba(103,126,234,0.4); border-radius: 8px; color: #b3c6ff; padding: 6px 14px; font-size: 13px; font-weight: 600; cursor: pointer; min-width: 60px; text-align: center; transition: all 0.15s; letter-spacing: 1px; }
.hotkey-display:hover { background: rgba(103,126,234,0.35); }

.key-table { width: 100%; border-collapse: separate; border-spacing: 0 3px; }
.key-table th { color: rgba(255,255,255,0.4); font-size: 9px; text-transform: uppercase; letter-spacing: 0.5px; padding: 4px 8px; text-align: left; font-weight: 400; }
.key-table td { padding: 2px 4px; }
.key-table input { background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.12); border-radius: 6px; color: #fff; padding: 6px 8px; font-size: 11px; width: 100%; outline: none; transition: border-color 0.15s; }
.key-table input:focus { border-color: rgba(103,126,234,0.5); }
.key-table .key-input { width: 80px; text-align: center; font-weight: 500; cursor: pointer; }
.key-table .key-input:hover { border-color: rgba(103,126,234,0.4); }
.key-table .interval-input { width: 65px; text-align: center; }
.key-table .unit { color: rgba(255,255,255,0.3); font-size: 9px; margin-left: 2px; }
.key-table .row-btn { background: none; border: none; color: rgba(255,255,255,0.3); cursor: pointer; font-size: 14px; padding: 2px 4px; border-radius: 4px; transition: all 0.15s; }
.key-table .row-btn:hover { color: rgba(255,255,255,0.8); background: rgba(255,255,255,0.1); }
.key-table .row-btn.del:hover { color: #ef5350; }

.sub-tabs { display: flex; gap: 2px; margin-bottom: 10px; background: rgba(0,0,0,0.1); border-radius: 8px; padding: 3px; }
.sub-tab { flex: 1; background: transparent; border: none; color: rgba(255,255,255,0.4); padding: 6px 8px; border-radius: 6px; font-size: 10px; cursor: pointer; transition: all 0.15s; font-family: inherit; display: flex; align-items: center; justify-content: center; gap: 4px; }
.sub-tab:hover { color: rgba(255,255,255,0.7); }
.sub-tab.active { background: rgba(103,126,234,0.3); color: #c5caff; }

.preview-box { background: rgba(0,0,0,0.15); border: 1px solid rgba(255,255,255,0.08); border-radius: 10px; padding: 12px; margin-top: 8px; }
.preview-title { color: rgba(76,175,80,0.6); font-size: 9px; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }
.preview-timeline { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; font-size: 10px; }
.preview-key { background: rgba(103,126,234,0.25); color: #c5caff; padding: 2px 8px; border-radius: 4px; font-weight: 500; }
.preview-arrow { color: rgba(255,255,255,0.2); font-size: 10px; }
.preview-time { color: rgba(255,255,255,0.3); font-size: 8px; }
.preview-loop { color: rgba(76,175,80,0.5); font-size: 9px; margin-top: 4px; }

.quick-actions { display: flex; gap: 4px; flex-wrap: wrap; }
.quick-btn { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08); border-radius: 6px; color: rgba(255,255,255,0.5); padding: 3px 8px; font-size: 9px; cursor: pointer; transition: all 0.15s; font-family: inherit; }
.quick-btn:hover { background: rgba(255,255,255,0.12); color: rgba(255,255,255,0.8); }

.toast { position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%) translateY(80px); background: rgba(0,0,0,0.7); backdrop-filter: blur(10px); color: #fff; padding: 10px 24px; border-radius: 24px; font-size: 12px; z-index: 200; transition: transform 0.3s; pointer-events: none; }
.toast.show { transform: translateX(-50%) translateY(0); }

.key-picker-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.3); z-index: 100; display: none; justify-content: center; align-items: center; }
.key-picker-overlay.show { display: flex; }
.key-picker { width: 360px; padding: 16px; }
.key-picker-title { color: #fff; font-size: 13px; font-weight: 600; margin-bottom: 12px; }
.key-picker-grid { display: grid; grid-template-columns: repeat(8, 1fr); gap: 3px; max-height: 200px; overflow-y: auto; }
.key-pick-btn { background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.1); border-radius: 4px; color: rgba(255,255,255,0.7); padding: 4px 2px; font-size: 9px; cursor: pointer; text-align: center; transition: all 0.1s; font-family: inherit; }
.key-pick-btn:hover { background: rgba(103,126,234,0.3); color: #c5caff; border-color: rgba(103,126,234,0.4); }
.key-picker-section { color: rgba(255,255,255,0.4); font-size: 8px; text-transform: uppercase; letter-spacing: 0.5px; margin: 8px 0 4px; grid-column: span 8; }
</style>
</head>
<body>
<div class="panel glass" id="mainPanel">
  <div class="panel-header">
    <span class="panel-title" id="panelTitle">添加新分组</span>
    <div style="display:flex;gap:4px;">
      <button class="quick-btn" onclick="showToast('已复制分组')">📋 复制</button>
      <button class="quick-btn" onclick="showToast('已应用模板')">📄 模板</button>
    </div>
  </div>
  <div class="panel-body">
    <div class="section">
      <div class="section-title">基本信息</div>
      <div class="form-row">
        <span class="label">ID</span>
        <div class="field"><input class="glass-input" id="idInput" value="" style="width:70px;"></div>
      </div>
      <div class="form-row">
        <span class="label">热键</span>
        <div class="field">
          <div style="display:flex;align-items:center;gap:6px;">
            <div class="hotkey-display" id="hotkeyDisp" onclick="captureHotkey()">点击设置</div>
            <span style="color:rgba(255,255,255,0.3);font-size:9px;">点击后按键设置</span>
          </div>
        </div>
      </div>
      <div class="form-row">
        <span class="label">模式</span>
        <div class="field">
          <div class="mode-select" id="modeSelect">
            <span class="mode-opt" onclick="pickMode(this,'periodic')">周期性</span>
            <span class="mode-opt" onclick="pickMode(this,'sequence')">序列</span>
            <span class="mode-opt active" onclick="pickMode(this,'enhanced_periodic')">增强周期</span>
            <span class="mode-opt" onclick="pickMode(this,'enhanced_sequence')">增强序列</span>
            <span class="mode-opt" onclick="pickMode(this,'hybrid')">混合</span>
            <span class="mode-opt" onclick="pickMode(this,'enhanced_hybrid')">增强混合</span>
            <span class="mode-opt" onclick="pickMode(this,'hold')">长按</span>
          </div>
        </div>
      </div>
    </div>
    <div class="section" id="keysSection">
      <div class="section-title">按键配置</div>
      <div id="modeContent"></div>
    </div>
    <div class="section">
      <div class="section-title">执行预览</div>
      <div class="preview-box" id="previewBox">
        <div class="preview-title">按热键启动后</div>
        <div class="preview-timeline" id="previewTimeline">
          <span class="preview-key">Space</span><span class="preview-arrow">→</span>
          <span class="preview-time">50ms</span><span class="preview-arrow">→</span>
          <span class="preview-key">1</span><span class="preview-arrow">→</span>
          <span class="preview-time">100ms</span><span class="preview-arrow">→</span>
          <span class="preview-key">2</span><span class="preview-arrow">→</span>
          <span style="color:rgba(76,175,80,0.5);font-size:10px;">↻ 循环</span>
        </div>
      </div>
    </div>
  </div>
  <div class="panel-footer">
    <div class="quick-actions">
      <button class="quick-btn" onclick="showToast('已导入配置')">📥 导入</button>
      <button class="quick-btn" onclick="showToast('已导出配置')">📤 导出</button>
      <button class="quick-btn" onclick="showToast('已重置')">🔄 重置</button>
    </div>
    <div style="display:flex;gap:8px;">
      <button class="btn btn-ghost" onclick="cancelEdit()">取消</button>
      <button class="btn btn-success" onclick="saveConfig()">💾 保存</button>
    </div>
  </div>
</div>

<div class="key-picker-overlay" id="keyPickerOverlay">
  <div class="key-picker glass" id="keyPicker">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
      <span class="key-picker-title">选择按键</span>
      <button class="btn-icon" onclick="closeKeyPicker()" style="width:24px;height:24px;font-size:10px;">✕</button>
    </div>
    <div style="margin-bottom:10px;">
      <input class="glass-input" id="keySearch" placeholder="搜索按键..." oninput="filterKeys()">
    </div>
    <div class="key-picker-grid" id="keyGrid"></div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
var ALL_KEYS = [
  {section:"功能键",keys:["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"]},
  {section:"数字",keys:["1","2","3","4","5","6","7","8","9","0"]},
  {section:"字母",keys:"ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")},
  {section:"特殊",keys:["Space","Enter","Tab","Esc","Backspace","Delete","Insert","Home","End","PgUp","PgDn"]},
  {section:"方向",keys:["Up","Down","Left","Right"]},
  {section:"修饰",keys:["Shift","Ctrl","Alt","Win"]},
  {section:"鼠标",keys:["LButton","RButton","MButton","XButton1","XButton2"]},
  {section:"符号",keys:["`","-","=","[","]","\\",";","'",",",".","/"]}
];

var currentMode = "enhanced_periodic";
var keyPickerTarget = null;
var simpleKeys = [{key:"Space",interval:50},{key:"1",interval:100},{key:"2",interval:100}];
var subGroups = [
  {type:"periodic",keys:[{key:"m",interval:50},{key:"a",interval:50}]},
  {type:"sequence",keys:[{key:"1",interval:200},{key:"2",interval:220},{key:"3",interval:240},{key:"4",interval:2500}],seqInterval:100}
];
var activeSub = 0;

function init() {
  renderModeContent();
  renderKeyGrid();
  updatePreview();
}

function renderKeyGrid() {
  var grid = document.getElementById("keyGrid");
  var html = "";
  for (var s=0; s<ALL_KEYS.length; s++) {
    html += '<div class="key-picker-section">'+ALL_KEYS[s].section+'</div>';
    for (var k=0; k<ALL_KEYS[s].keys.length; k++) {
      html += '<button class="key-pick-btn" onclick="pickKey(\''+ALL_KEYS[s].keys[k]+'\')">'+ALL_KEYS[s].keys[k]+'</button>';
    }
  }
  grid.innerHTML = html;
}

function filterKeys() {
  var q = document.getElementById("keySearch").value.toLowerCase();
  var btns = document.querySelectorAll(".key-pick-btn");
  for (var i=0; i<btns.length; i++) {
    btns[i].style.display = btns[i].textContent.toLowerCase().indexOf(q)>=0 ? "" : "none";
  }
}

function openKeyPicker(target) {
  keyPickerTarget = target;
  document.getElementById("keyPickerOverlay").classList.add("show");
  document.getElementById("keySearch").value = "";
  filterKeys();
}

function closeKeyPicker() {
  document.getElementById("keyPickerOverlay").classList.remove("show");
  keyPickerTarget = null;
}

function pickKey(key) {
  if (keyPickerTarget) {
    keyPickerTarget.value = key;
  }
  closeKeyPicker();
  updatePreview();
}

function captureHotkey() {
  var d = document.getElementById("hotkeyDisp");
  d.textContent = "请按键...";
  d.style.background = "rgba(239,83,80,0.2)";
  d.style.borderColor = "rgba(239,83,80,0.4)";
  document.addEventListener("keydown", function handler(e) {
    e.preventDefault();
    var name = e.key.length===1 ? e.key.toUpperCase() : e.key;
    d.textContent = name;
    d.style.background = "";
    d.style.borderColor = "";
    document.removeEventListener("keydown", handler);
    updatePreview();
  });
}

function pickMode(el, mode) {
  var opts = document.querySelectorAll(".mode-opt");
  for (var i=0; i<opts.length; i++) opts[i].classList.remove("active");
  el.classList.add("active");
  currentMode = mode;
  renderModeContent();
  updatePreview();
}

function renderModeContent() {
  var container = document.getElementById("modeContent");
  if (currentMode==="hybrid" || currentMode==="enhanced_hybrid") {
    container.innerHTML = renderHybridMode();
  } else if (currentMode==="hold") {
    container.innerHTML = renderHoldMode();
  } else {
    container.innerHTML = renderSimpleMode();
  }
}

function renderSimpleMode() {
  var timeLabel = currentMode.indexOf("periodic")>=0 ? "间隔" : "延迟";
  var hasHold = currentMode.indexOf("enhanced")>=0;
  var html = '<table class="key-table"><thead><tr><th style="width:90px;">按键</th><th style="width:80px;">'+timeLabel+' (ms)</th><th style="width:30px;"></th></tr></thead><tbody>';
  for (var i=0; i<simpleKeys.length; i++) {
    html += '<tr><td><input class="key-input" value="'+simpleKeys[i].key+'" onclick="openKeyPicker(this)" readonly></td>';
    html += '<td><input class="interval-input" value="'+simpleKeys[i].interval+'" type="number" min="10" onchange="updatePreview()"><span class="unit">ms</span></td>';
    html += '<td><button class="row-btn del" onclick="removeSimpleKey('+i+')">✕</button></td></tr>';
  }
  html += '</tbody></table>';
  html += '<button class="btn btn-ghost btn-sm" onclick="addSimpleKey()" style="margin-top:6px;">+ 添加按键</button>';
  if (hasHold) {
    html += '<div class="form-row" style="margin-top:10px;"><span class="label">长按键</span><div class="field"><input class="glass-input" placeholder="如 Shift, Ctrl（逗号分隔）" onchange="updatePreview()"></div></div>';
    html += '<div class="form-row"><span class="label">长按模式</span><div class="field"><select class="glass-input" style="width:120px;" onchange="updatePreview()"><option value="continuous">持续按住</option><option value="periodic">周期按压</option></select></div></div>';
  }
  return html;
}

function renderHybridMode() {
  var html = '<div class="sub-tabs">';
  for (var i=0; i<subGroups.length; i++) {
    html += '<button class="sub-tab'+(i===activeSub?' active':'')+'" onclick="switchSub('+i+')">子组 '+(i+1)+'</button>';
  }
  html += '<button class="sub-tab" onclick="addSub()" style="flex:0;padding:6px 10px;">+</button></div>';
  var sub = subGroups[activeSub];
  var timeLabel = sub.type==="sequence" ? "延迟" : "间隔";
  html += '<div class="form-row" style="margin-bottom:8px;"><span class="label" style="min-width:40px;">类型</span><select class="glass-input" style="width:100px;" onchange="changeSubType(this.value)"><option value="periodic"'+(sub.type==="periodic"?" selected":"")+'>周期性</option><option value="sequence"'+(sub.type==="sequence"?" selected":"")+'>序列</option></select></div>';
  html += '<table class="key-table"><thead><tr><th style="width:90px;">按键</th><th style="width:80px;">'+timeLabel+' (ms)</th><th style="width:30px;"></th></tr></thead><tbody>';
  for (var i=0; i<sub.keys.length; i++) {
    html += '<tr><td><input class="key-input" value="'+sub.keys[i].key+'" onclick="openKeyPicker(this)" readonly></td>';
    html += '<td><input class="interval-input" value="'+sub.keys[i].interval+'" type="number" min="10"><span class="unit">ms</span></td>';
    html += '<td><button class="row-btn del" onclick="removeSubKey('+i+')">✕</button></td></tr>';
  }
  html += '</tbody></table>';
  html += '<button class="btn btn-ghost btn-sm" onclick="addSubKey()" style="margin-top:6px;">+ 添加按键</button>';
  if (currentMode==="enhanced_hybrid") {
    html += '<div class="form-row" style="margin-top:10px;"><span class="label">长按键</span><div class="field"><input class="glass-input" placeholder="如 Shift, Ctrl（逗号分隔）"></div></div>';
  }
  return html;
}

function renderHoldMode() {
  return '<div class="form-row"><span class="label">长按键</span><div class="field"><input class="glass-input" value="Shift" placeholder="如 Shift, Ctrl（逗号分隔）"></div></div><div class="form-row"><span class="label">持续时长</span><div class="field" style="display:flex;align-items:center;gap:4px;"><input class="glass-input" type="number" value="1000" min="100" style="width:90px;"><span style="color:rgba(255,255,255,0.3);font-size:9px;">ms (0=无限)</span></div></div><div class="form-row"><span class="label">自动重复</span><div class="field" style="display:flex;align-items:center;gap:8px;"><label style="color:rgba(255,255,255,0.7);font-size:11px;display:flex;align-items:center;gap:4px;cursor:pointer;"><input type="checkbox"> 启用</label><input class="glass-input" type="number" value="1000" min="100" style="width:70px;" placeholder="间隔"><span style="color:rgba(255,255,255,0.3);font-size:9px;">ms</span></div></div>';
}

function addSimpleKey() { simpleKeys.push({key:"",interval:50}); renderModeContent(); }
function removeSimpleKey(i) { simpleKeys.splice(i,1); renderModeContent(); updatePreview(); }
function switchSub(i) { activeSub=i; renderModeContent(); }
function addSub() { subGroups.push({type:"periodic",keys:[],seqInterval:100}); activeSub=subGroups.length-1; renderModeContent(); }
function changeSubType(t) { subGroups[activeSub].type=t; renderModeContent(); }
function addSubKey() { subGroups[activeSub].keys.push({key:"",interval:50}); renderModeContent(); }
function removeSubKey(i) { subGroups[activeSub].keys.splice(i,1); renderModeContent(); }

function updatePreview() {
  var hotkey = document.getElementById("hotkeyDisp").textContent;
  if (hotkey==="点击设置"||hotkey==="请按键...") return;
  var tl = document.getElementById("previewTimeline");
  var html = "";
  var keys = [];
  if (currentMode.indexOf("hybrid")<0) {
    for (var i=0;i<simpleKeys.length;i++) keys.push(simpleKeys[i]);
  }
  for (var i=0;i<keys.length;i++) {
    if (i>0) html += '<span class="preview-arrow">→</span><span class="preview-time">'+keys[i].interval+'ms</span><span class="preview-arrow">→</span>';
    html += '<span class="preview-key">'+keys[i].key+'</span>';
  }
  if (keys.length>0) html += '<span style="color:rgba(76,175,80,0.5);font-size:10px;">↻ 循环</span>';
  tl.innerHTML = html || '<span style="color:rgba(255,255,255,0.3);">[请添加按键]</span>';
}

function showToast(msg) {
  var t = document.getElementById("toast");
  t.textContent = msg;
  t.classList.add("show");
  setTimeout(function(){t.classList.remove("show");},2000);
}

function saveConfig() {
  var id = document.getElementById("idInput").value;
  var hotkey = document.getElementById("hotkeyDisp").textContent;
  if (!id) { showToast("⚠ 请输入分组ID"); return; }
  if (hotkey==="点击设置") { showToast("⚠ 请设置热键"); return; }
  showToast("✅ 已保存！");
  if (window.external) window.external.onSave(id, hotkey, currentMode);
}

function cancelEdit() {
  if (window.external) window.external.onCancel();
}

init();
</script>
</body>
</html>
        )'
    }
}

Persistent(true)
HTMLEditor.Open("1", false)
