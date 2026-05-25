; =================================================================
; 表现层 - UI 管理器（Toast 通知实现）
; 版本: 3.0
; 说明: 实现 INotifier 接口，提供桌面 Toast 通知
;       支持定时自动隐藏，简洁状态摘要
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/interfaces.ahk"
#Include "../infrastructure/error_system.ahk"

class UIManager extends INotifier {
    static toastGui := ""
    static infoGui := ""
    static _toastTimer := 0

    static Init() {
        try {
            UIManager.infoGui := Gui("+ToolWindow -Caption +AlwaysOnTop", "技能管理器")
            UIManager.infoGui.SetFont("s10", "Segoe UI")
            UIManager.infoGui.Add("Text", "w200 h30 Center vInfoText", "技能管理器 - 待机")
            UIManager.infoGui.Show("x10 y10 NoActivate")

            UIManager.toastGui := Gui("+ToolWindow -Caption +AlwaysOnTop +Owner" UIManager.infoGui.Hwnd, "通知")
            UIManager.toastGui.BackColor := "333333"
            UIManager.toastGui.SetFont("s10 cWhite", "Segoe UI")
            UIManager.toastGui.Add("Text", "w250 h40 Center vToastText", "")
            UIManager.toastGui.Hide()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; INotifier 接口实现
    ; =================================================================
    static Notify(message, type := "info", duration := 0) {
        try {
            if !UIManager.toastGui
                UIManager.Init()

            switch type {
                case "error":
                    UIManager.toastGui.BackColor := "CC3333"
                case "warning":
                    UIManager.toastGui.BackColor := "CC9933"
                case "success":
                    UIManager.toastGui.BackColor := "33AA33"
                default:
                    UIManager.toastGui.BackColor := "3355AA"
            }

            UIManager.toastGui["ToastText"].Text := message
            UIManager.toastGui.Show("x10 y45 NoActivate")

            if UIManager._toastTimer
                SetTimer(UIManager._toastTimer, 0)
            UIManager._toastTimer := ObjBindMethod(UIManager, "HideToast")
            SetTimer(UIManager._toastTimer, -(duration > 0 ? duration : 3000))
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static ShowBriefInfo(activeCount, emergencyMode) {
        try {
            if !UIManager.infoGui
                UIManager.Init()

            if emergencyMode {
                UIManager.infoGui["InfoText"].Text := "紧急停止模式 | F12 恢复"
                UIManager.infoGui.BackColor := "FF3333"
            } else if activeCount > 0 {
                UIManager.infoGui["InfoText"].Text := "运行中 | " activeCount " 个分组"
                UIManager.infoGui.BackColor := "33AA33"
            } else {
                UIManager.infoGui["InfoText"].Text := "技能管理器 - 待机"
                UIManager.infoGui.BackColor := "3355AA"
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static HideToast() {
        try {
            if UIManager.toastGui {
                try
                    UIManager.toastGui.Hide()
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}
