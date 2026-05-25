#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

DarkColors := Map(
    "Background", 0x1E1E2E,
    "Surface",    0x2D2D44,
    "Primary",    0x667EEA,
    "Text",       0xE0E0F0,
    "TextDim",    0x8888AA,
    "Success",    0x4CAF50,
    "Error",      0xEF5350,
    "Border",     0x3D3D5C
)

SetWindowAttribute(GuiObj, DarkMode := true) {
    global DarkColors
    static PreferredAppMode := Map("Default", 0, "AllowDark", 1, "ForceDark", 2, "ForceLight", 3, "Max", 4)

    if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
        DWMWA_USE_IMMERSIVE_DARK_MODE := 19
        if (VerCompare(A_OSVersion, "10.0.18985") >= 0)
            DWMWA_USE_IMMERSIVE_DARK_MODE := 20

        uxtheme := DllCall("kernel32\GetModuleHandle", "Str", "uxtheme", "Ptr")
        SetPreferredAppMode := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        FlushMenuThemes := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")

        if DarkMode {
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", GuiObj.Hwnd, "Int", DWMWA_USE_IMMERSIVE_DARK_MODE, "Int*", true, "Int", 4)
            if SetPreferredAppMode
                DllCall(SetPreferredAppMode, "Int", PreferredAppMode["ForceDark"])
            if FlushMenuThemes
                DllCall(FlushMenuThemes)
            GuiObj.BackColor := DarkColors["Background"]
        } else {
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", GuiObj.Hwnd, "Int", DWMWA_USE_IMMERSIVE_DARK_MODE, "Int*", false, "Int", 4)
            if SetPreferredAppMode
                DllCall(SetPreferredAppMode, "Int", PreferredAppMode["Default"])
            if FlushMenuThemes
                DllCall(FlushMenuThemes)
            GuiObj.BackColor := "Default"
        }
    }
}

SetWindowThemeForControls(GuiObj, DarkMode := true) {
    Mode_Explorer := DarkMode ? "DarkMode_Explorer" : "Explorer"
    Mode_CFD := DarkMode ? "DarkMode_CFD" : "CFD"

    for hWnd, GuiCtrlObj in GuiObj {
        switch GuiCtrlObj.Type {
            case "Button", "CheckBox", "ListBox", "UpDown":
                DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.Hwnd, "Str", Mode_Explorer, "Ptr", 0)
            case "ComboBox", "DDL":
                DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.Hwnd, "Str", Mode_CFD, "Ptr", 0)
            case "Edit":
                DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.Hwnd, "Str", Mode_CFD, "Ptr", 0)
            case "ListView":
                DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.Hwnd, "Str", Mode_Explorer, "Ptr", 0)
            case "Tab":
                DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.Hwnd, "Str", Mode_Explorer, "Ptr", 0)
        }
    }
}

g := Gui("+Resize", "技能管理器 - 深色主题原型")
g.SetFont("s10", "Segoe UI")
SetWindowAttribute(g)
g.BackColor := DarkColors["Background"]

y := 14

g.Add("Text", "x18 y" y " w520 h1 Background" DarkColors["Border"], "")
y += 8

g.Add("Text", "x18 y" y " w100 h18 c" DarkColors["TextDim"], "基本信息")
y += 22

g.Add("Text", "x18 y" y " w60 h22 c" DarkColors["Text"], "ID:")
idEdit := g.Add("Edit", "x80 y" y-2 " w70 h22", "1")
y += 30

g.Add("Text", "x18 y" y " w60 h22 c" DarkColors["Text"], "热键:")
hotkeyBtn := g.Add("Button", "x80 y" y-2 " w120 h26", "F1")
g.Add("Text", "x210 y" y+2 " w200 h18 c" DarkColors["TextDim"], "点击后按键设置")
y += 34

g.Add("Text", "x18 y" y " w60 h22 c" DarkColors["Text"], "模式:")

modeRadioX := 80
modes := ["周期性", "序列", "增强周期", "增强序列", "混合", "增强混合", "长按"]
modeRadios := []
for i, mode in modes {
    r := g.Add("Radio", "x" modeRadioX " y" y-2 " w70 h22 c" DarkColors["Text"], mode)
    modeRadios.Push(r)
    modeRadioX += 72
    if modeRadioX > 500 {
        modeRadioX := 80
        y += 24
    }
}
modeRadios[3].Value := 1
y += 30

g.Add("Text", "x18 y" y " w520 h1 Background" DarkColors["Border"], "")
y += 8

g.Add("Text", "x18 y" y " w100 h18 c" DarkColors["TextDim"], "按键配置")
y += 22

lv := g.Add("ListView", "x18 y" y " w520 h120 c" DarkColors["Text"] " Background" DarkColors["Surface"] " -HDR -Multi NoSortHdr", ["按键", "间隔(ms)", ""])
lv.ModifyCol(1, 100)
lv.ModifyCol(2, 100)
lv.ModifyCol(3, 40)
lv.Add("", "Space", "50", "X")
lv.Add("", "1", "100", "X")
lv.Add("", "2", "100", "X")
y += 128

addKeyBtn := g.Add("Button", "x18 y" y " w120 h24", "+ 添加按键")
y += 34

g.Add("Text", "x18 y" y " w60 h22 c" DarkColors["Text"], "长按键:")
holdEdit := g.Add("Edit", "x80 y" y-2 " w200 h22", "")
g.Add("Text", "x290 y" y+2 " w200 h18 c" DarkColors["TextDim"], "如 Shift, Ctrl（逗号分隔）")
y += 30

g.Add("Text", "x18 y" y " w70 h22 c" DarkColors["Text"], "长按模式:")
holdDDL := g.Add("DropDownList", "x90 y" y-2 " w120 h200", ["持续按住", "周期按压"])
y += 34

g.Add("Text", "x18 y" y " w520 h1 Background" DarkColors["Border"], "")
y += 8

g.Add("Text", "x18 y" y " w100 h18 c" DarkColors["TextDim"], "执行预览")
y += 20

previewBox := g.Add("Text", "x18 y" y " w520 h40 c" DarkColors["Text"] " 0x200 Background" DarkColors["Surface"], "  按 F1 启动后:  Space → 50ms → 1 → 100ms → 2  ↻ 循环")
y += 50

g.Add("Text", "x18 y" y " w520 h1 Background" DarkColors["Border"], "")
y += 10

importBtn := g.Add("Button", "x18 y" y " w70 h28", "📥 导入")
exportBtn := g.Add("Button", "x95 y" y " w70 h28", "📤 导出")
resetBtn := g.Add("Button", "x172 y" y " w70 h28", "🔄 重置")
cancelBtn := g.Add("Button", "x360 y" y " w80 h28", "取消")
saveBtn := g.Add("Button", "x450 y" y " w90 h28", "💾 保存")

SetWindowThemeForControls(g)

g.OnEvent("Close", (*) => ExitApp())
g.Show("w560 h" y+40)

Persistent
