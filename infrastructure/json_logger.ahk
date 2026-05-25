; =================================================================
; 基础设施层 - 统一结构化日志契约
; 版本: 3.0
; 说明: 提供完整的结构化 JSON 日志记录
;       统一字段: level / message / timestamp / traceId / module / context
;       支持日志轮转、错误计数、级别过滤
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_serializer.ahk"
#Include "utils.ahk"

; =================================================================
; 第一部分: 错误类型定义
; =================================================================

class JSONErrorType {
    static FILE_NOT_FOUND := "E001"
    static FILE_READ_ERROR := "E002"
    static FILE_ENCODING_ERROR := "E003"
    static FILE_WRITE_ERROR := "E004"
    static SYNTAX_UNEXPECTED := "E101"
    static SYNTAX_MISSING_COLON := "E102"
    static SYNTAX_MISSING_COMMA := "E103"
    static SYNTAX_UNCLOSED_STRING := "E104"
    static SYNTAX_UNCLOSED_OBJECT := "E105"
    static SYNTAX_UNCLOSED_ARRAY := "E106"
    static SYNTAX_INVALID_ESCAPE := "E107"
    static SYNTAX_TRAILING_COMMA := "W101"
    static SYNTAX_EMPTY_INPUT := "W102"
    static SYNTAX_EXTRA_CHARS := "W103"
    static TYPE_INVALID_VALUE := "E201"
    static TYPE_INVALID_KEY := "E202"
    static TYPE_INVALID_NUMBER := "E203"
    static TYPE_INVALID_BOOL := "E204"
    static STRUCT_DEPTH_EXCEEDED := "E301"
    static CONFIG_MISSING_FIELD := "W301"
    static CONFIG_INVALID_FIELD := "W302"
    static CONFIG_UNKNOWN_FIELD := "I301"
    static CONFIG_INVALID_MODE := "W303"
    static CONFIG_INVALID_HOTKEY := "W304"
    static INFO_PARSE_START := "I001"
    static INFO_PARSE_SUCCESS := "I002"
    static DEBUG_EDITOR_OPEN := "D001"
    static DEBUG_MODE_CHANGE := "D002"
    static DEBUG_KEY_ADD := "D003"
    static DEBUG_KEY_EDIT := "D004"
    static DEBUG_KEY_DELETE := "D005"
    static DEBUG_CONFIG_SAVE := "D006"
    static DEBUG_GROUP_ADD := "D007"
    static DEBUG_GROUP_DELETE := "D008"
    static DEBUG_HOTKEY_TRIGGER := "D010"
    static DEBUG_BACKUP_CREATE := "D020"
    static DEBUG_BACKUP_RESTORE := "D021"
    static DEBUG_VALIDATE_START := "D030"
    static WARN_EMPTY_CONFIG := "W401"
}

; =================================================================
; 第二部分: 错误对象
; =================================================================

class JSONError {
    type := ""
    level := "ERROR"
    message := ""
    position := 0
    line := 0
    column := 0
    context := ""
    suggestion := ""
    timestamp := ""
    callStack := ""
    filePath := ""
    traceId := ""
    module := ""

    __New(type, message, pos := 0, context := "", filePath := "") {
        this.type := type
        this.level := JSONError._GetLevel(type)
        this.message := message
        this.position := pos
        this.context := context
        this.timestamp := A_Now
        this.filePath := filePath
        this.traceId := this._GenerateTraceId()
    }

    static _GetLevel(type) {
        prefix := SubStr(type, 1, 1)
        switch prefix {
            case "C": return "CRITICAL"
            case "E": return "ERROR"
            case "W": return "WARNING"
            case "I": return "INFO"
            default: return "ERROR"
        }
    }

    _GenerateTraceId() {
        return Format("{1:08x}", A_TickCount) SubStr(A_Now, 1, 8)
    }

    SetPosition(pos, jsonStr) {
        if pos > 0 && StrLen(jsonStr) > 0 {
            this.position := pos
            this.line := 1
            this.column := 1
            loop Min(pos - 1, StrLen(jsonStr)) {
                c := SubStr(jsonStr, A_Index, 1)
                if c = "`n" {
                    this.line++
                    this.column := 1
                } else {
                    this.column++
                }
            }
            this.context := this._ExtractContext(pos, jsonStr)
        }
    }

    _ExtractContext(pos, jsonStr, contextLen := 40) {
        if pos < 1 || pos > StrLen(jsonStr)
            return ""
        start := Max(1, pos - contextLen // 2)
        end := Min(StrLen(jsonStr), pos + contextLen // 2)
        ctx := SubStr(jsonStr, start, end - start + 1)
        ctx := StrReplace(ctx, "`r`n", "<NL>")
        ctx := StrReplace(ctx, "`n", "<NL>")
        ctx := StrReplace(ctx, "`t", "<TAB>")
        return ctx
    }

    ToString() {
        base := "[" this.timestamp "][" this.level "][" this.traceId "] " this.type ": " this.message
        if this.filePath
            base .= " (文件: " this.filePath ")"
        return base
    }
}

; =================================================================
; 第三部分: 结构化日志记录器
; =================================================================

class JSONLogger {
    static logFile := "logs/app.log"
    static maxLogSize := 2097152
    static backupCount := 5
    static maxErrors := 500
    static _initialized := false
    static _writeCount := 0
    static _sizeCheckInterval := 100

    static errors := []
    static errorCount := Map("CRITICAL", 0, "ERROR", 0, "WARNING", 0, "INFO", 0, "DEBUG", 0)

    static Init() {
        if this._initialized
            return
        if !InStr(FileExist("logs"), "D")
            DirCreate("logs")
        this._initialized := true
    }

    ; =================================================================
    ; ILogger 接口实现
    ; =================================================================
    static Log(level, message, context := "") {
        this.Init()
        this._WriteLog(level, message, context)
    }

    static _WriteLog(level, message, context := "") {
        this.Init()

        if !this._ShouldLog(level)
            return

        errorObj := JSONError("", message, 0, "", "")
        errorObj.level := level
        if IsObject(context) {
            if context.Has("module")
                errorObj.module := context["module"]
            if context.Has("traceId")
                errorObj.traceId := context["traceId"]
            if context.Has("code")
                errorObj.type := context["code"]
        }

        this.errors.Push(errorObj)
        if this.errors.Length > this.maxErrors
            this.errors.RemoveAt(1)
        if !this.errorCount.Has(level)
            this.errorCount[level] := 0
        this.errorCount[level]++

        this._LogToFile(errorObj)
    }

    static _ShouldLog(level) {
        return level = "ERROR" || level = "CRITICAL" || level = "WARNING" || level = "INFO" || level = "DEBUG"
    }

    static _LogToFile(errorObj) {
        this.Init()
        try {
            this._writeCount++
            if this._writeCount >= this._sizeCheckInterval {
                this._writeCount := 0
                if FileExist(this.logFile) {
                    size := FileGetSize(this.logFile)
                    if size > this.maxLogSize
                        this._RotateLog()
                }
            }
            jsonLine := this._BuildLogLine(errorObj) "`n"
            FileAppend(jsonLine, this.logFile, "UTF-8")
        } catch {
            OutputDebug("JSONLogger._LogToFile: 写入失败")
        }
    }

    static _BuildLogLine(errorObj) {
        entry := Map(
            "timestamp", errorObj.timestamp,
            "level", errorObj.level,
            "traceId", errorObj.traceId,
            "module", errorObj.module != "" ? errorObj.module : "Unknown",
            "code", errorObj.type,
            "message", errorObj.message
        )
        if errorObj.filePath != ""
            entry["file"] := errorObj.filePath
        return JSONSerializer.Stringify(entry)
    }

    static _RotateLog() {
        LogRotator.Rotate(this.logFile, this.backupCount)
    }

    static GetSummary() {
        summary := "════════════════════════════════════════`n"
        summary .= "        应用日志摘要`n"
        summary .= "════════════════════════════════════════`n"
        summary .= "总计: " this.errors.Length " 条记录`n"
        for level, count in this.errorCount
            summary .= "  " level ": " count "`n"
        summary .= "────────────────────────────────────────`n"
        return summary
    }

    static Clear() {
        this.errors := []
        this.errorCount := Map("CRITICAL", 0, "ERROR", 0, "WARNING", 0, "INFO", 0, "DEBUG", 0)
    }

    static HasErrors() {
        return this.errorCount["CRITICAL"] > 0 || this.errorCount["ERROR"] > 0
    }

    static HasWarnings() {
        return this.errorCount["WARNING"] > 0
    }
}
