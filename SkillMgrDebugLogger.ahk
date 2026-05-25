; =================================================================
; 调试日志系统 - 提供带速率限制的文件调试日志功能
; 版本: 1.2
; 说明: 支持 Log() 方法写入 logs/debug.log，自动限速和文件大小限制(5MB)
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class SkillMgrDebugLogger {
    static logFile := "logs/debug.log"
    static enabled := true
    static maxSize := 5 * 1024 * 1024
    static initialized := false
    static _lastHotPathLog := 0
    static hotPathInterval := 50
    static _startupModeEndTick := 0

    static Init() {
        if this.initialized
            return
        this.initialized := true
        if !InStr(FileExist("logs"), "D")
            DirCreate("logs")
        try {
            FileAppend("`n========== " A_Now " ==========`n", this.logFile, "UTF-8")
        } catch as e {
            OutputDebug("SkillMgrDebugLogger.Init failed: " e.Message)
        }
    }

    static Log(message) {
        if !this.enabled
            return

        ; 初始化启动模式时间（仅在第一次调用时）
        if (this._startupModeEndTick = 0)
            this._startupModeEndTick := A_TickCount + 5000

        ; 启动前5秒放宽限制，之后正常限速
        effectiveInterval := (A_TickCount < this._startupModeEndTick) ? 0 : this.hotPathInterval

        ; 速率限制检查
        if (A_TickCount - this._lastHotPathLog < effectiveInterval)
            return
        this._lastHotPathLog := A_TickCount

        try {
            this.Init()
            this._EnforceSizeLimit()
            
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            logEntry := "[" timestamp "] " message "`n"
            FileAppend(logEntry, this.logFile, "UTF-8")
            
            OutputDebug(message)
        } catch as e {
            OutputDebug("SkillMgrDebugLogger.Log failed: " e.Message)
        }
    }

    static _EnforceSizeLimit() {
        try {
            fileSize := FileGetSize(this.logFile)
            if (fileSize = "" || fileSize <= this.maxSize)
                return
                
            content := FileRead(this.logFile, "UTF-8")
            lines := StrSplit(content, "`n", "`r")
            
            keepLines := Max(lines.Length // 2, 100)
            if (keepLines < lines.Length) {
                lines := lines.SubArray(lines.Length - keepLines + 1, keepLines)
                content := lines.Join("`n")
                FileDelete(this.logFile)
                FileAppend(content, this.logFile, "UTF-8")
            }
        } catch as e {
            OutputDebug("SkillMgrDebugLogger._EnforceSizeLimit failed: " e.Message)
        }
    }
}
