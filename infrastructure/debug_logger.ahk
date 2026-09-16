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

; =================================================================
; 全局调试日志快捷函数
;
; 2026-09-16 从 presentation/gui_manager.ahk 下沉到这里（TD-037）。
; 原来它是一个写在 GUI 模块里的全局函数，而 `presentation/webview2_manager.ahk`
; 有 43 处调用却**没有 include gui_manager.ahk** —— 生产里只是因为 main.ahk
; 把两个文件都 include 了才没暴露。任何只 include webview2_manager 的消费者
; （例如 tests/test_webview2_bridge.ahk）都会在第一次 _DebugLog 时抛错，
; 进而让 _BridgeSaveConfig / _BridgeEmergencyStop 直接返回失败。
; 日志工具属于基础设施，不该藏在 GUI 模块里。
; =================================================================
_DebugLog(msg) {
    try {
        FileAppend(A_Now " " msg "`n", "logs/debug.log", "UTF-8")
    } catch as e {
        ; best-effort: 调试日志写入失败不影响主流程
        OutputDebug("ASD [WARN] _DebugLog: " e.Message " at line " e.Line)
    }
    OutputDebug(A_Now " " msg)
}
