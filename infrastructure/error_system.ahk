; =================================================================
; 基础设施层 - 错误处理系统
; 版本: 3.0
; 说明: 单一模块处理所有错误类型，支持错误分级和结构化日志
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "utils.ahk"
#Include "json_serializer.ahk"

; =================================================================
; 错误级别常量
; =================================================================
class ErrorLevel {
    static CRITICAL := "CRITICAL"
    static ERROR := "ERROR"
    static WARNING := "WARNING"
}

; =================================================================
; 错误类型常量
; =================================================================
class ErrorType {
    static LOADTIME := "LoadTimeError"
    static RUNTIME := "RuntimeError"
    static UNCAUGHT := "UncaughtError"
}

; =================================================================
; 错误处理系统类
; =================================================================
class ErrorSystem {
    static logFile := ""
    static _initialized := false
    static _errorCount := 0
    static _writeCount := 0
    static _sizeCheckInterval := 10
    static _rateLastTime := Map()
    static _rateSuppressed := Map()

    ; =================================================================
    ; 初始化
    ; =================================================================
    static Init() {
        if this._initialized
            return

        ; 设置日志文件路径（使用绝对路径）
        if this.logFile = ""
            this.logFile := A_ScriptDir "\logs\errors.log"

        ; 确保日志目录存在
        SplitPath(this.logFile, , &logDir)
        if !DirExist(logDir)
            DirCreate(logDir)

        this._initialized := true
    }

    ; =================================================================
    ; 错误处理回调（OnError 使用）
    ; =================================================================
    static HandleError(Thrown, Mode) {
        this.Init()

        try {
            this._errorCount++

            ; 构建错误记录
            record := this._BuildErrorRecord(Thrown, Mode)

            ; 写入日志
            this._WriteLog(record)

        } catch {
            OutputDebug("ErrorSystem.HandleError: 内部错误")
        }

        if IsObject(Thrown) && Type(Thrown) = "MemoryError"
            return 0

        return 1
    }

    ; =================================================================
    ; 构建错误记录
    ; =================================================================
    static _BuildErrorRecord(Thrown, Mode) {
        record := Map()
        
        ; 时间戳（ISO 8601 格式）
        record["timestamp"] := this._FormatISO8601(A_Now)
        
        ; 错误级别
        record["level"] := this._DetermineErrorLevel(Thrown, Mode)
        
        ; 错误类型
        record["type"] := ErrorType.RUNTIME
        
        ; 错误模式
        record["mode"] := Mode

        ; 提取错误信息
        if IsObject(Thrown) {
            ; 具体错误类型
            if HasBase(Thrown, Error.Prototype)
                record["errorType"] := Type(Thrown)
            else
                record["errorType"] := "Unknown"

            if HasProp(Thrown, "Message")
                record["message"] := Thrown.Message
            else
                record["message"] := "Unknown error"

            if HasProp(Thrown, "What")
                record["what"] := Thrown.What

            if HasProp(Thrown, "File")
                record["file"] := Thrown.File

            if HasProp(Thrown, "Line")
                record["line"] := Thrown.Line

            if HasProp(Thrown, "Extra")
                record["extra"] := Thrown.Extra

            if HasProp(Thrown, "Stack")
                record["stack"] := Thrown.Stack
        } else {
            record["errorType"] := "Unknown"
            record["message"] := String(Thrown)
        }

        return record
    }

    ; =================================================================
    ; 确定错误级别
    ; =================================================================
    static _DetermineErrorLevel(Thrown, Mode) {
        ; 根据错误模式确定级别
        if Mode = "ExitApp"
            return ErrorLevel.CRITICAL
        
        if Mode = "Exit"
            return ErrorLevel.ERROR

        ; 根据错误类型确定级别
        if IsObject(Thrown) && HasBase(Thrown, Error.Prototype) {
            errorType := Type(Thrown)
            
            if errorType = "MemoryError"
                return ErrorLevel.CRITICAL

            if errorType = "TypeError" || errorType = "ValueError"
                return ErrorLevel.WARNING
            
            if InStr(errorType, "Error")
                return ErrorLevel.ERROR
        }

        return ErrorLevel.ERROR
    }

    ; =================================================================
    ; 格式化 ISO 8601 时间
    ; =================================================================
    static _FormatISO8601(timestamp) {
        ; 格式: 2026-05-12T00:00:00
        return SubStr(timestamp, 1, 4) "-" 
             . SubStr(timestamp, 5, 2) "-" 
             . SubStr(timestamp, 7, 2) "T" 
             . SubStr(timestamp, 9, 2) ":" 
             . SubStr(timestamp, 11, 2) ":" 
             . SubStr(timestamp, 13, 2)
    }

    ; =================================================================
    ; 写入日志
    ; =================================================================
    static _WriteLog(record) {
        global LOG_RATE_LIMIT_MS
        this.Init()

        try {
            source := this._ResolveSource(record)
            now := A_TickCount

            ; 限速：同一源在窗口内仅累加抑制计数并跳过落盘
            if this._rateLastTime.Has(source) && (now - this._rateLastTime[source] < LOG_RATE_LIMIT_MS) {
                if !this._rateSuppressed.Has(source)
                    this._rateSuppressed[source] := 0
                this._rateSuppressed[source] += 1
                return
            }
            suppressed := this._rateSuppressed.Has(source) ? this._rateSuppressed[source] : 0
            this._rateLastTime[source] := now
            this._rateSuppressed[source] := 0

            this._writeCount++
            if this._writeCount >= this._sizeCheckInterval {
                this._writeCount := 0
                if FileExist(this.logFile) {
                    size := FileGetSize(this.logFile)
                    if size > 10485760
                        this._RotateLog()
                }
            }

            if suppressed > 0
                record["suppressedCount"] := suppressed

            jsonLine := this._ToJsonLine(record)

            if StrLen(jsonLine) > 65536
                jsonLine := SubStr(jsonLine, 1, 65536) . ',"_truncated":true}'

            try {
                FileAppend(jsonLine "`n", this.logFile, "UTF-8")
            } catch {
                OutputDebug("ErrorSystem._WriteLog: FileAppend 写入失败")
            }

        } catch {
            OutputDebug("ErrorSystem._WriteLog: 写入失败")
        }
    }

    ; =================================================================
    ; 解析日志写入源（用于限速分桶，避免不同来源互相抑制）
    ; =================================================================
    static _ResolveSource(record) {
        if record is Map {
            if record.Has("file") && record["file"] != ""
                return record["file"]
            if record.Has("what") && record["what"] != ""
                return record["what"]
            if record.Has("message")
                return record["message"]
        }
        return "unknown"
    }

    ; =================================================================
    ; 构建 JSON 行
    ; =================================================================
    static _ToJsonLine(record) {
        ; T6-09: 日志以单行紧凑 JSON 落盘（indent=0），避免多行 pretty 输出
        return JSONSerializer.Stringify(record, 0)
    }

    ; =================================================================
    ; 日志轮转
    ; =================================================================
    static _RotateLog() {
        LogRotator.Rotate(this.logFile, 5)
    }

    ; =================================================================
    ; 获取错误统计
    ; =================================================================
    static GetErrorCount() {
        return this._errorCount
    }

    ; =================================================================
    ; 手动记录错误
    ; =================================================================
    static LogError(message, level := "ERROR", file := "", line := 0) {
        this.Init()

        record := Map()
        record["timestamp"] := this._FormatISO8601(A_Now)
        record["level"] := level
        record["type"] := ErrorType.RUNTIME
        record["mode"] := "Manual"
        record["errorType"] := "ManualError"
        record["message"] := message

        if file != ""
            record["file"] := file

        if line > 0
            record["line"] := line

        this._WriteLog(record)
    }

    ; =================================================================
    ; 记录警告
    ; =================================================================
    static LogWarning(message, file := "", line := 0) {
        this.LogError(message, ErrorLevel.WARNING, file, line)
    }
}

; =================================================================
; 辅助函数
; =================================================================
; 全局错误处理回调函数（用于 OnError）
; =================================================================
ErrorSystem_HandleError(Thrown, Mode) {
    return ErrorSystem.HandleError(Thrown, Mode)
}
