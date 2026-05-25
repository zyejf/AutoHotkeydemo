#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

Persistent(true)

OnError((e, mode) => {
    FileAppend(Format("ERROR[{}]: {}`n  File: {} Line: {}`n", mode, e.Message, e.File, e.Line), "D:\1demo\AutoHotkeydemo\tests\debug_error.log", "UTF-8")
    return -1
})

try {
    g := Gui("+Resize", "HTML Editor Test")
    wb := g.Add("ActiveX", "w560 h680", "Shell.Explorer")
    g.OnEvent("Close", (*) => ExitApp())
    g.OnEvent("Size", (guiObj, minMax, w, h) => wb.Move(0, 0, w, h))
    g.Show("w560 h680")

    wb.Navigate("about:blank")
    loop 100 {
        if wb.ReadyState = 4
            break
        Sleep 50
    }

    if wb.ReadyState != 4 {
        FileAppend("WARN: ReadyState=" wb.ReadyState " after timeout`n", "D:\1demo\AutoHotkeydemo\tests\debug_error.log", "UTF-8")
    }

    html := "<!DOCTYPE html><html><head><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:'Segoe UI','Microsoft YaHei',sans-serif;min-height:100vh;background:linear-gradient(135deg,#667eea 0%,#764ba2 50%,#f093fb 100%);display:flex;justify-content:center;align-items:flex-start;padding:16px;}.glass{background:rgba(255,255,255,0.12);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.18);border-radius:16px;}.panel{width:520px;padding:18px;}.panel h1{color:#fff;font-size:14px;margin-bottom:14px;}.form-row{display:flex;gap:8px;margin-bottom:8px;align-items:center;}.form-row label{color:rgba(255,255,255,0.6);font-size:11px;min-width:60px;}.form-row input,.form-row select{background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.2);border-radius:8px;color:#fff;padding:7px 10px;font-size:12px;outline:none;flex:1;}.mode-select{display:flex;gap:4px;flex-wrap:wrap;margin-bottom:12px;}.mode-opt{background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.1);border-radius:6px;padding:4px 10px;color:rgba(255,255,255,0.5);font-size:10px;cursor:pointer;}.mode-opt.active{background:rgba(103,126,234,0.3);border-color:rgba(103,126,234,0.5);color:#c5caff;}.hotkey-display{background:rgba(103,126,234,0.2);border:1px solid rgba(103,126,234,0.4);border-radius:8px;color:#b3c6ff;padding:6px 14px;font-size:13px;font-weight:600;cursor:pointer;min-width:60px;text-align:center;}.section-title{color:rgba(255,255,255,0.5);font-size:9px;text-transform:uppercase;letter-spacing:1px;margin:12px 0 8px;padding-bottom:4px;border-bottom:1px solid rgba(255,255,255,0.06);}.preview-box{background:rgba(0,0,0,0.15);border:1px solid rgba(255,255,255,0.08);border-radius:10px;padding:12px;margin-top:8px;}.preview-key{background:rgba(103,126,234,0.25);color:#c5caff;padding:2px 8px;border-radius:4px;font-weight:500;font-size:10px;}.preview-arrow{color:rgba(255,255,255,0.2);font-size:10px;}.preview-time{color:rgba(255,255,255,0.3);font-size:8px;}.footer{margin-top:14px;display:flex;justify-content:space-between;}.btn{border:none;border-radius:8px;padding:7px 16px;font-size:11px;cursor:pointer;}.btn-success{background:rgba(76,175,80,0.5);color:#fff;}.btn-ghost{background:rgba(255,255,255,0.08);color:rgba(255,255,255,0.7);border:1px solid rgba(255,255,255,0.12);}</style></head><body><div class='panel glass'><h1>添加新分组</h1><div class='form-row'><label>ID</label><input value='1' style='width:70px;'></div><div class='form-row'><label>热键</label><div class='hotkey-display'>F1</div></div><div class='section-title'>模式</div><div class='mode-select'><span class='mode-opt'>周期性</span><span class='mode-opt'>序列</span><span class='mode-opt active'>增强周期</span><span class='mode-opt'>增强序列</span><span class='mode-opt'>混合</span><span class='mode-opt'>增强混合</span><span class='mode-opt'>长按</span></div><div class='section-title'>按键配置</div><div class='form-row'><label>按键1</label><input value='Space' style='width:80px;text-align:center;'><label>间隔</label><input value='50' type='number' style='width:65px;text-align:center;'><span style='color:rgba(255,255,255,0.3);font-size:9px;'>ms</span></div><div class='form-row'><label>按键2</label><input value='1' style='width:80px;text-align:center;'><label>间隔</label><input value='100' type='number' style='width:65px;text-align:center;'><span style='color:rgba(255,255,255,0.3);font-size:9px;'>ms</span></div><div class='form-row'><label>按键3</label><input value='2' style='width:80px;text-align:center;'><label>间隔</label><input value='100' type='number' style='width:65px;text-align:center;'><span style='color:rgba(255,255,255,0.3);font-size:9px;'>ms</span></div><div class='section-title'>执行预览</div><div class='preview-box'><span class='preview-key'>Space</span><span class='preview-arrow'> → </span><span class='preview-time'>50ms</span><span class='preview-arrow'> → </span><span class='preview-key'>1</span><span class='preview-arrow'> → </span><span class='preview-time'>100ms</span><span class='preview-arrow'> → </span><span class='preview-key'>2</span><span style='color:rgba(76,175,80,0.5);font-size:10px;'> ↻ 循环</span></div><div class='footer'><div><button class='btn btn-ghost' style='font-size:9px;padding:4px 10px;'>📥 导入</button> <button class='btn btn-ghost' style='font-size:9px;padding:4px 10px;'>📤 导出</button></div><div><button class='btn btn-ghost'>取消</button> <button class='btn btn-success'>💾 保存</button></div></div></div></body></html>"
    wb.Document.Write(html)
    wb.Document.Close()

    FileAppend("SUCCESS: HTML editor loaded`n", "D:\1demo\AutoHotkeydemo\tests\debug_error.log", "UTF-8")
} catch as e {
    FileAppend(Format("CAUGHT: {}`n  File: {} Line: {}`n", e.Message, e.File, e.Line), "D:\1demo\AutoHotkeydemo\tests\debug_error.log", "UTF-8")
}
