; =================================================================
; UI管理器 - 用户界面状态提示与管理
; 版本: 1.0
; 说明: 提供 ShowStatus() Toast 提示和 ShowBriefInfo() 系统状态摘要显示
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class UIManager {
    static _lastToastTime := 0
    static _toastDuration := 1500
    static _activeToasts := []
    
    ; 显示状态提示消息
    static ShowStatus(message, type := "info") {
        if (A_TickCount - this._lastToastTime < 500)
            return
        
        this._lastToastTime := A_TickCount
        
        toast := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound")
        
        colors := Map(
            "success", "00AA00",
            "error", "FF4444",
            "warning", "FF9900",
            "info", "3366CC"
        )
        
        bgColor := colors.Has(type) ? colors[type] : "3366CC"
        toast.BackColor := bgColor
        toast.SetFont("cFFFFFF s11 Bold", "Microsoft YaHei UI")
        toast.MarginX := 20
        toast.MarginY := 8
        
        textControl := toast.Add("Text", "Center", message)
        toast.Show("NoActivate")
        
        toast.GetPos(, , &width, &height)
        xPos := (A_ScreenWidth - width) // 2
        yPos := A_ScreenHeight - 100
        
        toast.Show("x" xPos " y" yPos " NoActivate")
        WinSetTransparent(240, toast.Hwnd)
        
        this._activeToasts.Push(toast)
        SetTimer((*) => this._DestroyToast(toast), -this._toastDuration)
    }
    
    ; 销毁单个 Toast 并从数组中移除
    static _DestroyToast(toast) {
        for i, t in this._activeToasts {
            if (t = toast) {
                this._activeToasts.RemoveAt(i)
                break
            }
        }
        if WinExist(toast.Hwnd) {
            toast.Destroy()
        }
    }
    
    ; 清理所有活跃的 Toast 窗口
    static _CleanupAllToasts() {
        for toast in this._activeToasts {
            if WinExist(toast.Hwnd) {
                toast.Destroy()
            }
        }
        this._activeToasts := []
    }
    
    ; 显示简要信息
    static ShowBriefInfo(activeCount, emergencyMode) {
        if emergencyMode {
            this.ShowStatus("🔴 紧急停止已激活", "error")
        } else if activeCount > 0 {
            this.ShowStatus("🟢 运行中 (" activeCount "个分组)", "success")
        } else {
            this.ShowStatus("⚪ 系统待机", "info")
        }
    }
}

; 脚本退出时清理所有 Toast 窗口
OnExit(*) => UIManager._CleanupAllToasts()