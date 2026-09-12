; =================================================================
; 基础设施层 - 调试日志器
; 版本: 3.0
; 说明: 提供带速率限制和文件大小管理的文件调试日志
;       记录到 logs/debug.log
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "utils.ahk"

class DebugLogger {
    static logFile := "logs/debug.log"
    static enabled := true
    static maxSize := 5 * 1024 * 1024
    static initialized := false
    static _lastHotPathLog := 0
    static _startupModeEndTick := 0
    static _writeCount := 0
    static _sizeCheckInterval := 100

    static Init() {
        if this.initialized
            return
        this.initialized := true
        if !InStr(FileExist("logs"), "D")
            DirCreate("logs")
        try {
            FileAppend("`n========== " A_Now " ==========`n", this.logFile, "UTF-8")
        } catch as e {
            OutputDebug("DebugLogger.Init failed: " e.Message)
        }
    }

    ; =================================================================
    ; ILogger 接口实现
    ; =================================================================
    static Log(level, message, context := "") {
        global LOG_RATE_LIMIT_MS
        if !this.enabled
            return

        if this._startupModeEndTick = 0
            this._startupModeEndTick := A_TickCount + 5000

        inStartupMode := A_TickCount < this._startupModeEndTick

        if level = "DEBUG" && !inStartupMode {
            if A_TickCount - this._lastHotPathLog < LOG_RATE_LIMIT_MS
                return
            this._lastHotPathLog := A_TickCount
        }

        try {
            this.Init()
            this._writeCount++
            if this._writeCount >= this._sizeCheckInterval {
                this._writeCount := 0
                this._EnforceSizeLimit()
            }

            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            traceId := ""
            if IsObject(context) && context.Has("traceId")
                traceId := " [" context["traceId"] "]"

            logEntry := "[" timestamp "][" level "]" traceId " " message "`n"
            FileAppend(logEntry, this.logFile, "UTF-8")
            OutputDebug(message)
        } catch as e {
            OutputDebug("DebugLogger.Log failed: " e.Message)
        }
    }

    static _EnforceSizeLimit() {
        try {
            fileSize := FileGetSize(this.logFile)
            if fileSize = "" || fileSize <= this.maxSize
                return

            LogRotator.Rotate(this.logFile, 3)

            if !FileExist(this.logFile)
                FileAppend("", this.logFile, "UTF-8")
        } catch as e {
            OutputDebug("DebugLogger._EnforceSizeLimit failed: " e.Message)
        }
    }
}
