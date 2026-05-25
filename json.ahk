; =================================================================
; JSON 解析�?+ 序列化器 + 错误日志系统
; 版本: 1.0
; 说明: 简易JSON解析器，专为技能管理器配置文件设计
;       支持详细错误日志记录和配置验�?; =================================================================

#Requires AutoHotkey v2.0

; =================================================================
; 第一部分: 错误类型定义
; =================================================================

class JSONErrorType {
    ; 文件相关错误 (C = CRITICAL, E = ERROR, W = WARNING, I = INFO)
    static FILE_NOT_FOUND := "E001"
    static FILE_READ_ERROR := "E002"
    static FILE_ENCODING_ERROR := "E003"
    static FILE_WRITE_ERROR := "E004"
    
    ; 语法相关错误
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
    
    ; 类型相关错误
    static TYPE_INVALID_VALUE := "E201"
    static TYPE_INVALID_KEY := "E202"
    static TYPE_INVALID_NUMBER := "E203"
    static TYPE_INVALID_BOOL := "E204"
    
    ; 结构相关错误
    static STRUCT_DEPTH_EXCEEDED := "E301"
    
    ; 配置相关错误
    static CONFIG_MISSING_FIELD := "W301"
    static CONFIG_INVALID_FIELD := "W302"
    static CONFIG_UNKNOWN_FIELD := "I301"
    static CONFIG_INVALID_MODE := "W303"
    static CONFIG_INVALID_HOTKEY := "W304"
    
; 信息类型
	static INFO_PARSE_START := "I001"
	static INFO_PARSE_SUCCESS := "I002"
    
    ; 调试信息 (D = DEBUG)
    static DEBUG_EDITOR_OPEN := "D001"
    static DEBUG_MODE_CHANGE := "D002"
    static DEBUG_KEY_ADD := "D003"
    static DEBUG_KEY_EDIT := "D004"
    static DEBUG_KEY_DELETE := "D005"
    static DEBUG_CONFIG_SAVE := "D006"
    static DEBUG_HOTKEY_TRIGGER := "D010"
    static DEBUG_BACKUP_CREATE := "D020"
    static DEBUG_BACKUP_RESTORE := "D021"
    static DEBUG_VALIDATE_START := "D030"
}

; =================================================================
; 第二部分: 错误对象�?; =================================================================

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
    
    __New(type, message, pos := 0, context := "", filePath := "") {
        this.type := type
        this.level := JSONError._GetLevel(type)
        this.message := message
        this.position := pos
        this.context := context
        this.timestamp := A_Now
        this.filePath := filePath
        this.callStack := this._CaptureStack()
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
    
    _CaptureStack() {
        try {
            throw Error("stack")
        } catch as e {
            return e.Stack
        }
    }
    
    SetPosition(pos, jsonStr) {
        if (pos > 0 && StrLen(jsonStr) > 0) {
            this.position := pos
            this.line := 1
            this.column := 1
            
            loop Min(pos - 1, StrLen(jsonStr)) {
                c := SubStr(jsonStr, A_Index, 1)
                if (c = "`n") {
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
        if (pos < 1 || pos > StrLen(jsonStr))
            return ""
        
        start := Max(1, pos - contextLen // 2)
        end := Min(StrLen(jsonStr), pos + contextLen // 2)
        context := SubStr(jsonStr, start, end - start + 1)
        context := StrReplace(context, "`r`n", "<NL>")
        context := StrReplace(context, "`n", "<NL>")
        context := StrReplace(context, "`t", "<TAB>")
        return context
    }
    
    ToString() {
        str := "[" this.timestamp "] [" this.level "] " this.type "`n"
        str .= "  消息: " this.message "`n"
        
        if (this.filePath != "")
            str .= "  文件: " this.filePath "`n"
        
        if (this.position > 0) {
str .= " 位置: 第 " this.line " 行 第 " this.column " 列(字符" this.position ")`n"
            if (this.context != "") {
str .= " 上下文: " this.context "`n"
                marker := ""
                contextOffset := this.position > 20 ? 20 : this.position - 1
                loop contextOffset
                    marker .= " "
                marker .= "^"
                str .= "          " marker "`n"
            }
        }
        
        if (this.suggestion != "")
            str .= "  建议: " this.suggestion "`n"
        
        return str
    }
    
    ToShortString() {
        return "[" this.level "] " this.type ": " this.message
    }
}

; =================================================================
; 第三部分: 日志管理�?; =================================================================

class JSONLogger {
    static logFile := "logs/app.log"
    static maxLogSize := 2097152
    static logToConsole := false
    static logToFile := true
    static backupCount := 5

    static errors := []
    static errorCount := Map("CRITICAL", 0, "ERROR", 0, "WARNING", 0, "DEBUG", 0)
    static _initialized := false
    
    static Init() {
        if (this._initialized)
            return
        
        if !InStr(FileExist("logs"), "D")
            DirCreate("logs")
        
        this._initialized := true
    }
    
    static Log(errorObj) {
        this.Init()
        
        if !this._ShouldLog(errorObj.level)
            return
        
        this.errors.Push(errorObj)
        this.errorCount[errorObj.level]++
        
        if (this.logToConsole)
            this._LogToConsole(errorObj)
        
        if (this.logToFile)
            this._LogToFile(errorObj)
    }
    
    static _ShouldLog(level) {
        return level = "ERROR" || level = "CRITICAL" || level = "WARNING" || level = "DEBUG"
    }
    
    static _LogToConsole(errorObj) {
        OutputDebug("JSON: " errorObj.ToShortString())
    }
    
    static _LogToFile(errorObj) {
        this.Init()
        
        try {
            if (FileExist(this.logFile)) {
                size := FileGetSize(this.logFile)
                if (size > this.maxLogSize)
                    this._RotateLog()
            }
            
            jsonLine := this._ToJson(errorObj) . "`n"
            FileAppend(jsonLine, this.logFile, "UTF-8")
        }
    }
    
    static _ToJson(errorObj) {
        entry := Map(
            "timestamp", errorObj.timestamp,
            "level", errorObj.level,
            "module", errorObj.HasProp("module") ? errorObj.module : "JSONParser",
            "code", errorObj.type,
            "message", errorObj.message,
            "file", errorObj.filePath,
            "line", errorObj.HasProp("line") ? errorObj.line : 0
        )
        return JSONSerializer.Stringify(entry)
    }
    
static _RotateLog() {
        if !FileExist(this.logFile)
            return
        
        timestamp := StrReplace(StrReplace(A_Now, ":", ""), " ", "_")
        backupFile := StrReplace(this.logFile, ".log", "_" timestamp ".log.bak")
        
        try {
            FileMove(this.logFile, backupFile, 1)
        }
        
        this._CleanupOldBackups(this.backupCount)
    }
    
    static _CleanupOldBackups(keepCount) {
        pattern := StrReplace(this.logFile, ".log", "_*.log.bak")
        backups := []
        
        try {
            Loop Files, pattern
                backups.Push(A_LoopFileFullPath)
        }
        
        while (backups.Length > keepCount) {
            oldest := backups[1]
            oldestTime := FileGetTime(oldest, "M")
            
            for file in backups {
                fileTime := FileGetTime(file, "M")
                if (fileTime < oldestTime) {
                    oldest := file
                    oldestTime := fileTime
                }
            }
            
            try {
                FileDelete(oldest)
            }
            
            newBackups := []
            for file in backups {
                if (file != oldest)
                    newBackups.Push(file)
            }
            backups := newBackups
        }
    }
    
    static GetSummary() {
        summary := "════════════════════════════════════════`n"
        summary .= "        JSON 解析错误摘要`n"
        summary .= "════════════════════════════════════════`n"
        summary .= "总计: " this.errors.Length " 条记录`n"
        summary .= "  CRITICAL: " this.errorCount["CRITICAL"] "`n"
        summary .= "  ERROR: " this.errorCount["ERROR"] "`n"
        summary .= "  WARNING: " this.errorCount["WARNING"] "`n"
        summary .= "  INFO: " this.errorCount["INFO"] "`n"
        summary .= "────────────────────────────────────────`n"
        return summary
    }
    
    static Clear() {
        this.errors := []
        this.errorCount := Map("CRITICAL", 0, "ERROR", 0, "WARNING", 0, "INFO", 0)
    }
    
    static ExportReport(filePath := "") {
        if (filePath = "")
            filePath := "logs/json_error_report_" StrReplace(A_Now, ":", "") ".txt"
        
        report := "╔══════════════════════════════════════════╗`n"
report .= "【JSON 解析错误报告】`n"
report .= "【生成时间】: " A_Now "`n"
        report .= "╚══════════════════════════════════════════╝`n`n"
        report .= this.GetSummary() "`n"
        
        if (this.errors.Length > 0) {
            report .= "详细错误列表:`n"
            report .= "════════════════════════════════════════`n`n"
            
            for error in this.errors {
                report .= error.ToString() "`n"
            }
        } else {
            report .= "无错误记录`n"
        }
        
        try {
            FileAppend(report, filePath, "UTF-8")
            return filePath
        }
        return ""
    }
    
    static GetErrorsByLevel(level) {
        result := []
        for error in this.errors {
            if (error.level = level)
                result.Push(error)
        }
        return result
    }
    
    static HasErrors() {
        return this.errorCount["CRITICAL"] > 0 || this.errorCount["ERROR"] > 0
    }
    
    static HasWarnings() {
        return this.errorCount["WARNING"] > 0
    }
    
    static LogDebug(module, code, message) {
        errorObj := JSONError(code, message, 0, "", "")
        errorObj.module := module
        errorObj.level := "DEBUG"
        this.Log(errorObj)
    }
    
    static LogWarning(module, code, message) {
        errorObj := JSONError(code, message, 0, "", "")
        errorObj.module := module
        errorObj.level := "WARNING"
        this.Log(errorObj)
    }
    
    static LogError(module, code, message) {
        errorObj := JSONError(code, message, 0, "", "")
        errorObj.module := module
        errorObj.level := "ERROR"
        this.Log(errorObj)
    }
}

; =================================================================
; 第四部分: JSON 解析�?; =================================================================

class JSONParser {
    static json := ""
    static pos := 1
    static len := 0
    static filePath := ""
    static depth := 0
    static maxDepth := 100
    
static Parse(jsonStr, filePath := "") {
		; 移除 UTF-8 BOM
		if (StrLen(jsonStr) > 0 && Ord(SubStr(jsonStr, 1, 1)) = 0xFEFF) {
			DebugLogger.Log("Parse: Removed UTF-8 BOM")
			jsonStr := SubStr(jsonStr, 2)
		}

		this.json := jsonStr
		this.pos := 1
		this.len := StrLen(jsonStr)
		this.filePath := filePath
		this.depth := 0

		DebugLogger.Log("=== JSONParser.Parse START ===")
		DebugLogger.Log("File: " (filePath ? filePath : "(string)"))
		DebugLogger.Log("Input length: " this.len)
		if (this.len > 0 && this.len < 200)
			DebugLogger.Log("Input preview: " jsonStr)
		else if (this.len > 0)
			DebugLogger.Log("Input preview: " SubStr(jsonStr, 1, 100) "...")

		JSONLogger.Log(JSONError(
			JSONErrorType.INFO_PARSE_START,
			"开始解析JSON" (filePath ? " (文件: " filePath ")" : ""),
			0, "", filePath
		))

		if (this.len = 0) {
			DebugLogger.Log("Parse: Empty input, returning empty Map")
			error := JSONError(JSONErrorType.SYNTAX_EMPTY_INPUT, "JSON字符串为空", 0, "", filePath)
			JSONLogger.Log(error)
			return Map()
		}
        
        try {
            result := this.ParseValue()
            
            this.SkipWhitespace()
            if (this.pos <= this.len) {
                warning := JSONError(JSONErrorType.SYNTAX_EXTRA_CHARS, "解析完成后仍有额外字符", this.pos, "", filePath)
                warning.SetPosition(this.pos, this.json)
                warning.suggestion := "检查JSON是否完整，或是否有多余内容"
                JSONLogger.Log(warning)
            }
            
            elementCount := this._CountElements(result)
            JSONLogger.Log(JSONError(
                JSONErrorType.INFO_PARSE_SUCCESS,
                "JSON解析完成，共解析 " elementCount " 个元素",
                0, "", filePath
            ))
            
            return result
        } catch as e {
            error := JSONError(JSONErrorType.SYNTAX_UNEXPECTED, "解析失败: " e.Message, this.pos, "", filePath)
            error.SetPosition(this.pos, this.json)
            JSONLogger.Log(error)
            throw error
        }
    }
    
static LoadFile(filePath) {
	if !FileExist(filePath) {
		error := JSONError(JSONErrorType.FILE_NOT_FOUND, "文件不存在: " filePath, 0, "", filePath)
		error.suggestion := "请检查文件路径是否正确"
		JSONLogger.Log(error)
		throw error
	}

	try {
		content := FileRead(filePath, "UTF-8")
	} catch as e {
		error := JSONError(JSONErrorType.FILE_READ_ERROR, "无法读取文件: " e.Message, 0, "", filePath)
		JSONLogger.Log(error)
		throw error
	}

	DebugLogger.Log("Using custom JSON parser - with enhanced error handling")
	try {
		return this.Parse(content, filePath)
	} catch as parseErr {
		DebugLogger.Log("Custom parser exception: " parseErr.Message)
		DebugLogger.Log("Stack: " parseErr.Stack)
		DebugLogger.Log("Trying to return fallback config...")
		return this._GetFallbackConfig()
	}
}

static _GetFallbackConfig() {
	DebugLogger.Log("Creating fallback config")
	return Map(
		"version", "2.0",
		"lastModified", A_Now,
		"GroupSettings", Map(
			"1", Map(
				"hotkey", "F1",
				"mode", "periodic",
				"keys", ["Space"],
				"intervals", [50]
			)
		),
		"CONTROL_HOTKEYS", Map(
			"emergency", "F12",
			"toggleAll", "^1",
			"showStatus", "^0",
			"toggleHoldMode", "^h",
			"releaseAllHolds", "^r"
		),
		"HoldSettings", Map(
			"debounceDelay", 20,
			"checkInterval", 50,
			"allowOverlap", false,
			"pressSpeed", 80,
			"releaseOnEmergency", true
		)
	)
}

static ParseValue() {
		this.SkipWhitespace()
		DebugLogger.Log("ParseValue: START at pos " this.pos)

		if (this.pos > this.len) {
			DebugLogger.Log("ParseValue: ERROR - Unexpected end at pos " this.pos)
			error := JSONError(JSONErrorType.SYNTAX_UNEXPECTED, "JSON意外结束", this.pos, "", this.filePath)
			JSONLogger.Log(error)
			throw error
		}

		c := SubStr(this.json, this.pos, 1)
		cAscii := Ord(c)
		DebugLogger.Log("ParseValue: char='" c "' ASCII=" cAscii " at pos " this.pos)
		branch := ""
		switch c {
			case "{":
				DebugLogger.Log("ParseValue: branch -> object")
				return this.ParseObject()
			case "[":
				DebugLogger.Log("ParseValue: branch -> array")
				return this.ParseArray()
			case '"':
				DebugLogger.Log("ParseValue: branch -> string")
				return this.ParseString()
			case "t", "f":
				DebugLogger.Log("ParseValue: branch -> bool")
				return this.ParseBool()
			case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
				DebugLogger.Log("ParseValue: branch -> number")
				return this.ParseNumber()
			default:
				DebugLogger.Log("ParseValue: ERROR - Unexpected char '" c "' at pos " this.pos)
				errorMsg := "意外字符: '" c "' (ASCII: " Asc(c) ")"
				error := JSONError(JSONErrorType.SYNTAX_UNEXPECTED, errorMsg, this.pos, "", this.filePath)
				error.SetPosition(this.pos, this.json)
				error.suggestion := '期望: { [ " 数字 或 true/false'
				JSONLogger.Log(error)
				throw error
		}
	}
    
static ParseObject() {
		this.depth++
		DebugLogger.Log("ParseObject: START, depth=" this.depth " pos=" this.pos)
		if (this.depth > this.maxDepth) {
			error := JSONError(JSONErrorType.STRUCT_DEPTH_EXCEEDED, "嵌套深度超过限制 (" this.maxDepth ")", this.pos, "", this.filePath)
			JSONLogger.Log(error)
			throw error
		}

		obj := Map()
		this.pos++
		this.SkipWhitespace()

		if (SubStr(this.json, this.pos, 1) = "}") {
			DebugLogger.Log("ParseObject: empty object")
			this.pos++
			this.depth--
			return obj
		}

		propIndex := 0
		loop {
			this.SkipWhitespace()
			propIndex++
			DebugLogger.Log("ParseObject: parsing property #" propIndex " at pos " this.pos)

			if (SubStr(this.json, this.pos, 1) != '"') {
				error := JSONError(JSONErrorType.TYPE_INVALID_KEY, "对象键必须是字符串", this.pos, "", this.filePath)
				error.SetPosition(this.pos, this.json)
				error.suggestion := '键应该用双引号包围，如 "key": value'
				JSONLogger.Log(error)
				throw error
			}

			key := this.ParseString()
			DebugLogger.Log("ParseObject: key='" key "'")
			this.SkipWhitespace()

			if (SubStr(this.json, this.pos, 1) != ":") {
				error := JSONError(JSONErrorType.SYNTAX_MISSING_COLON, "缺少冒号分隔符", this.pos, "", this.filePath)
				error.SetPosition(this.pos, this.json)
				error.suggestion := '在键和值之间添加冒号: "key": value'
				JSONLogger.Log(error)
				throw error
			}

			this.pos++
			DebugLogger.Log("ParseObject: parsing value for key '" key "' at pos " this.pos)
			value := this.ParseValue()
			DebugLogger.Log("ParseObject: value for '" key "' parsed, type=" Type(value))
			obj[key] := value

			this.SkipWhitespace()
			c := SubStr(this.json, this.pos, 1)
			DebugLogger.Log("ParseObject: after key-value pair, char='" c "' at pos " this.pos)

			if (c = ",") {
				this.pos++
				this.SkipWhitespace()

				if (SubStr(this.json, this.pos, 1) = "}") {
					warning := JSONError(JSONErrorType.SYNTAX_TRAILING_COMMA, "对象有尾随逗号", this.pos, "", this.filePath)
					warning.SetPosition(this.pos, this.json)
					warning.suggestion := "移除最后一个逗号"
					JSONLogger.Log(warning)
					this.pos++
					this.depth--
					return obj
				}
				continue
			} else if (c = "}") {
				DebugLogger.Log("ParseObject: object closed, " obj.Count " properties")
				this.pos++
				this.depth--
				return obj
			} else {
				error := JSONError(JSONErrorType.SYNTAX_MISSING_COMMA, "缺少逗号或对象未闭合", this.pos, "", this.filePath)
				error.SetPosition(this.pos, this.json)
				error.suggestion := "元素间添加逗号，或用 } 闭合对象"
				JSONLogger.Log(error)
				throw error
			}
		}
	}
    
static ParseArray() {
		this.depth++
		DebugLogger.Log("ParseArray: START, depth=" this.depth " pos=" this.pos)
		if (this.depth > this.maxDepth) {
			error := JSONError(JSONErrorType.STRUCT_DEPTH_EXCEEDED, "嵌套深度超过限制 (" this.maxDepth ")", this.pos, "", this.filePath)
			JSONLogger.Log(error)
			throw error
		}

		arr := []
		this.pos++
		this.SkipWhitespace()

		if (SubStr(this.json, this.pos, 1) = "]") {
			DebugLogger.Log("ParseArray: empty array")
			this.pos++
			this.depth--
			return arr
		}

		elemIndex := 0
		loop {
			this.SkipWhitespace()
			elemIndex++
			DebugLogger.Log("ParseArray: parsing element #" elemIndex " at pos " this.pos)
			value := this.ParseValue()
			DebugLogger.Log("ParseArray: element #" elemIndex " parsed, type=" Type(value) " value='" (IsObject(value) ? "(object)" : value) "'")
			arr.Push(value)
			this.SkipWhitespace()

			c := SubStr(this.json, this.pos, 1)
			DebugLogger.Log("ParseArray: after element, char='" c "' at pos " this.pos)
			if (c = ",") {
				this.pos++
				this.SkipWhitespace()

				if (SubStr(this.json, this.pos, 1) = "]") {
					warning := JSONError(JSONErrorType.SYNTAX_TRAILING_COMMA, "数组有尾随逗号", this.pos, "", this.filePath)
					warning.SetPosition(this.pos, this.json)
					warning.suggestion := "移除最后一个逗号"
					JSONLogger.Log(warning)
					this.pos++
					this.depth--
					return arr
				}
				continue
			} else if (c = "]") {
				DebugLogger.Log("ParseArray: array closed, " arr.Length " elements")
				this.pos++
				this.depth--
				return arr
			} else {
				error := JSONError(JSONErrorType.SYNTAX_MISSING_COMMA, "缺少逗号或数组未闭合", this.pos, "", this.filePath)
				error.SetPosition(this.pos, this.json)
				error.suggestion := "元素间添加逗号，或用 ] 闭合数组"
				JSONLogger.Log(error)
				throw error
			}
		}
	}
    
static ParseString() {
	this.pos++
	start := this.pos
	str := ""

	while (this.pos <= this.len) {
		c := SubStr(this.json, this.pos, 1)
            
            if (c = '"') {
                str .= SubStr(this.json, start, this.pos - start)
                this.pos++
                return str
            }
            
            if (c = "\") {
                if (start < this.pos)
                    str .= SubStr(this.json, start, this.pos - start)
                
                this.pos++
                if (this.pos > this.len) {
                    error := JSONError(JSONErrorType.SYNTAX_INVALID_ESCAPE, "字符串末尾有未完成的转义序列", this.pos - 1, "", this.filePath)
                    error.SetPosition(this.pos - 1, this.json)
                    JSONLogger.Log(error)
                    throw error
                }
                
                nextChar := SubStr(this.json, this.pos, 1)
                switch nextChar {
                    case "n": str .= "`n"
                    case "t": str .= "`t"
                    case "r": str .= "`r"
                    case '"': str .= '"'
                    case "\": str .= "\"
                    case "/": str .= "/"
                    default: 
                        warning := JSONError(JSONErrorType.SYNTAX_INVALID_ESCAPE, '未知的转义序列: " nextChar', this.pos - 1, "", this.filePath)
                        warning.suggestion := '支持的转义: `n, `t, `r, ", \, /'
                        JSONLogger.Log(warning)
                        str .= nextChar
                }
                this.pos++
                start := this.pos
                continue
            }
            
            this.pos++
        }
        
        error := JSONError(JSONErrorType.SYNTAX_UNCLOSED_STRING, "字符串未闭合", start - 1, "", this.filePath)
        error.SetPosition(start - 1, this.json)
        error.suggestion := '在字符串末尾添加双引号"'
        JSONLogger.Log(error)
        throw error
    }
    
static ParseNumber() {
		start := this.pos
		hasDecimal := false
		hasExponent := false

		DebugLogger.Log("ParseNumber: START at pos " start)

		try {
			currentChar := SubStr(this.json, this.pos, 1)
			DebugLogger.Log("ParseNumber: char at pos " this.pos " is '" currentChar "' (ASCII " Ord(currentChar) ")")
		} catch as e {
			DebugLogger.Log("ParseNumber: ERROR getting char - " e.Message)
		}

		if (SubStr(this.json, this.pos, 1) = "-") {
			DebugLogger.Log("ParseNumber: found negative sign")
			this.pos++
		}

		if (this.pos > this.len) {
			DebugLogger.Log("ParseNumber: ERROR - incomplete number")
			error := JSONError(JSONErrorType.TYPE_INVALID_NUMBER, "数字不完整", start, "", this.filePath)
			error.SetPosition(start, this.json)
			JSONLogger.Log(error)
			throw error
		}

		firstChar := SubStr(this.json, this.pos, 1)
		DebugLogger.Log("ParseNumber: firstChar='" firstChar "'")
		if (firstChar < "0" || firstChar > "9") {
			DebugLogger.Log("ParseNumber: ERROR - invalid start char '" firstChar "'")
			error := JSONError(JSONErrorType.TYPE_INVALID_NUMBER, "无效的数字起始: '" firstChar "'", this.pos, "", this.filePath)
			error.SetPosition(this.pos, this.json)
			error.suggestion := "数字应以 0-9 或负号开始"
			JSONLogger.Log(error)
			throw error
		}

	DebugLogger.Log("ParseNumber: entering while loop...")
	loopCount := 0
	while (this.pos <= this.len) {
			loopCount++
			c := SubStr(this.json, this.pos, 1)
			cAscii := Ord(c)
			DebugLogger.Log("ParseNumber: loop #" loopCount " pos=" this.pos " char='" c "' ASCII=" cAscii)
			if (cAscii >= 48 && cAscii <= 57) {  ; ASCII 48='0', 57='9'
				DebugLogger.Log("ParseNumber: digit '" c "' found, pos++")
				this.pos++
			} else if (c = "." && !hasDecimal) {
				DebugLogger.Log("ParseNumber: decimal point found")
				hasDecimal := true
				this.pos++
			} else if (c = "e" || c = "E") {
				DebugLogger.Log("ParseNumber: exponent found")
				hasExponent := true
				this.pos++
				if (this.pos <= this.len) {
					expSign := SubStr(this.json, this.pos, 1)
					if (expSign = "+" || expSign = "-") {
						DebugLogger.Log("ParseNumber: exponent sign '" expSign "'")
						this.pos++
					}
				}
			} else {
				DebugLogger.Log("ParseNumber: checking else conditions...")
				isDigit := (cAscii >= 48 && cAscii <= 57)
				isDecimal := (c = ".")
				isExp := (c = "e" || c = "E")
				DebugLogger.Log("ParseNumber: isDigit=" isDigit " isDecimal=" isDecimal " isExp=" isExp)
				DebugLogger.Log("ParseNumber: non-number char '" c "' (ASCII " cAscii "), breaking loop")
				break
			}
		}

		DebugLogger.Log("ParseNumber: while loop done, pos=" this.pos)
		numStr := SubStr(this.json, start, this.pos - start)
		DebugLogger.Log("ParseNumber: extracted '" numStr "' (hasDecimal=" hasDecimal ", hasExponent=" hasExponent ")")

		try {
			if (hasDecimal || hasExponent) {
				result := Float(numStr)
				DebugLogger.Log("ParseNumber: result=" result " (Float)")
				return result
			} else {
				result := Integer(numStr)
				DebugLogger.Log("ParseNumber: result=" result " (Integer)")
				return result
			}
		} catch as e {
			DebugLogger.Log("ParseNumber: ERROR - cannot parse '" numStr "' - " e.Message)
			error := JSONError(JSONErrorType.TYPE_INVALID_NUMBER, "无法解析数字: '" numStr "'", start, "", this.filePath)
			error.SetPosition(start, this.json)
			JSONLogger.Log(error)
			throw error
		}
	}
    
    static ParseBool() {
        if (SubStr(this.json, this.pos, 4) = "true") {
            this.pos += 4
            return true
        }
        
        if (SubStr(this.json, this.pos, 5) = "false") {
            this.pos += 5
            return false
        }
        
        partial := SubStr(this.json, this.pos, 10)
        error := JSONError(JSONErrorType.TYPE_INVALID_BOOL, "无效的布尔值: '" partial "...'", this.pos, "", this.filePath)
        error.SetPosition(this.pos, this.json)
        error.suggestion := "布尔值应为 true 或 false (小写)"
        JSONLogger.Log(error)
        throw error
    }
    
static SkipWhitespace() {
	while (this.pos <= this.len) {
		c := SubStr(this.json, this.pos, 1)
            if (c = " " || c = "`t" || c = "`n" || c = "`r")
                this.pos++
            else
                break
        }
    }
    
    static _CountElements(value) {
        if (IsObject(value)) {
            if (value is Map)
                return value.Count
            else if (value is Array)
                return value.Length
        }
        return 1
    }
}

; =================================================================
; 第五部分: JSON 序列化器
; =================================================================

class JSONSerializer {
    static Stringify(value, indent := 0) {
        return this._StringifyValue(value, indent, 0)
    }
    
static _StringifyValue(value, indent, currentIndent) {
		if (IsObject(value)) {
			if (value is Map)
				return this._StringifyObject(value, indent, currentIndent)
			else if (value is Array)
				return this._StringifyArray(value, indent, currentIndent)
			else
				return this._StringifyObject(value, indent, currentIndent)
		} else if (value is String) {
			return '"' this._EscapeString(value) '"'
		} else if (value = true) {
			return "true"
		} else if (value = false) {
			return "false"
		} else if (value is Integer) {
			return String(value)
		}
		return "null"
	}
    
    static _StringifyObject(obj, indent, currentIndent) {
        if (obj.Count = 0)
            return "{}"
        
        spaces := ""
        loop currentIndent
            spaces .= " "
        
        nextSpaces := ""
        loop currentIndent + indent
            nextSpaces .= " "
        
        result := "{`n"
        first := true
        
        for key, value in obj {
            if !first
                result .= ",`n"
            first := false
            
            result .= nextSpaces '"' this._EscapeString(key) '": '
            result .= this._StringifyValue(value, indent, currentIndent + indent)
        }
        
        result .= "`n" spaces "}"
        return result
    }
    
    static _StringifyArray(arr, indent, currentIndent) {
        if (arr.Length = 0)
            return "[]"
        
        spaces := ""
        loop currentIndent
            spaces .= " "
        
        nextSpaces := ""
        loop currentIndent + indent
            nextSpaces .= " "
        
        result := "[`n"
        first := true
        
        for item in arr {
            if !first
                result .= ",`n"
            first := false
            
            result .= nextSpaces this._StringifyValue(item, indent, currentIndent + indent)
        }
        
        result .= "`n" spaces "]"
        return result
    }
    
    static _EscapeString(str) {
        str := StrReplace(str, '\', '\\')
        str := StrReplace(str, '"', '\"')
str := StrReplace(str, "`n", "\n")
	str := StrReplace(str, "`r", "\r")
	str := StrReplace(str, "`t", "\t")
        return str
    }
}

; =================================================================
; 第六部分: 配置验证�?; =================================================================

class ConfigValidator {
    static validModes := [
        "periodic", "sequence", "hybrid",
        "enhanced_periodic", "enhanced_sequence", "enhanced_hybrid", "hold"
    ]
    
    static validKeys := [
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "Space", "Enter", "Escape", "Backspace", "Tab", "CapsLock",
        "LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt",
        "LButton", "RButton", "MButton", "XButton1", "XButton2",
        "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn",
        "Insert", "Delete"
    ]
    
    static Validate(config) {
        errors := []
        
        if !this._HasField(config, "GroupSettings") {
            error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "缺少必需的配置节: GroupSettings", 0, "", "")
            error.suggestion := "确保配置包含 GroupSettings 对象"
            JSONLogger.Log(error)
            errors.Push(error)
            return errors
        }
        
        groupSettings := this._GetField(config, "GroupSettings")
        
        if (groupSettings is Map) {
            for id, groupConfig in groupSettings {
                errors.Push(this._ValidateGroup(id, groupConfig)*)
            }
        }
        
        if (this._HasField(config, "CONTROL_HOTKEYS")) {
            errors.Push(this._ValidateHotkeys(this._GetField(config, "CONTROL_HOTKEYS"))*)
        }
        
        if (this._HasField(config, "HoldSettings")) {
            errors.Push(this._ValidateHoldSettings(this._GetField(config, "HoldSettings"))*)
        }
        
        return errors
    }
    
    static _ValidateGroup(id, config) {
        errors := []
        
        if !this._HasField(config, "hotkey") {
            error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id "缺少热键(hotkey)", 0, "", "")
            JSONLogger.Log(error)
            errors.Push(error)
        } else {
            hotkey := this._GetField(config, "hotkey")
            if !this._ValidateHotkeyFormat(hotkey) {
                warning := JSONError(JSONErrorType.CONFIG_INVALID_HOTKEY, "分组" id "热键格式可能无效: " hotkey, 0, "", "")
                warning.suggestion := "热键格式如: F1, ^a, +1 等"
                JSONLogger.Log(warning)
                errors.Push(warning)
            }
        }
        
        if !this._HasField(config, "mode") {
            error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id "缺少模式(mode)", 0, "", "")
            JSONLogger.Log(error)
            errors.Push(error)
        } else {
            mode := this._GetField(config, "mode")
            if !this._ArrayContains(this.validModes, mode) {
                error := JSONError(JSONErrorType.CONFIG_INVALID_MODE, "分组" id "有无效的模式: " mode, 0, "", "")
                error.suggestion := "有效模式: " Join(this.validModes, ", ")
                JSONLogger.Log(error)
                errors.Push(error)
            }
            
            errors.Push(this._ValidateModeFields(id, mode, config)*)
        }
        
        return errors
    }
    
    static _ValidateModeFields(id, mode, config) {
        errors := []
        
        switch mode {
            case "periodic":
                if !this._HasField(config, "keys") || !this._HasField(config, "intervals") {
                    error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (periodic) 缺少 keys 或 intervals", 0, "", "")
                    JSONLogger.Log(error)
                    errors.Push(error)
                }
            case "sequence":
                if !this._HasField(config, "keys") || !this._HasField(config, "delays") {
                    error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (sequence) 缺少 keys 或 delays", 0, "", "")
                    JSONLogger.Log(error)
                    errors.Push(error)
                }
            case "hybrid":
                if !this._HasField(config, "periodic") || !this._HasField(config, "sequence") {
                    error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (hybrid) 缺少 periodic 或 sequence", 0, "", "")
                    JSONLogger.Log(error)
                    errors.Push(error)
                }
            case "enhanced_periodic":
                if !this._HasField(config, "pressKeys") || !this._HasField(config, "intervals") {
                    error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (enhanced_periodic) 缺少 pressKeys 或 intervals", 0, "", "")
                    JSONLogger.Log(error)
                    errors.Push(error)
                }
            case "enhanced_sequence":
                if !this._HasField(config, "pressKeys") || !this._HasField(config, "pressDelays") {
                    error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (enhanced_sequence) 缺少 pressKeys 或 pressDelays", 0, "", "")
                    JSONLogger.Log(error)
                    errors.Push(error)
                }
            case "enhanced_hybrid":
                if !this._HasField(config, "periodic") || !this._HasField(config, "sequence") {
                    error := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (enhanced_hybrid) 缺少 periodic 或 sequence", 0, "", "")
                    JSONLogger.Log(error)
                    errors.Push(error)
                }
            case "hold":
                if !this._HasField(config, "holdKeys") {
                    warning := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "分组" id " (hold) 缺少 holdKeys", 0, "", "")
                    warning.level := "WARNING"
                    warning.suggestion := "纯长按模式需要指定要长按的键"
                    JSONLogger.Log(warning)
                    errors.Push(warning)
                }
        }
        
        return errors
    }
    
    static _ValidateHotkeys(hotkeys) {
        errors := []
        requiredActions := ["emergency", "toggleAll", "showStatus", "toggleHoldMode", "releaseAllHolds"]
        
        for action in requiredActions {
            if !this._HasField(hotkeys, action) {
                warning := JSONError(JSONErrorType.CONFIG_MISSING_FIELD, "缺少热键配置: " action, 0, "", "")
                warning.level := "WARNING"
                warning.suggestion := "将使用默认热键"
                JSONLogger.Log(warning)
                errors.Push(warning)
            }
        }
        
        return errors
    }
    
static _ValidateHoldSettings(settings) {
		errors := []

		if (this._HasField(settings, "pressSpeed")) {
			speed := this._GetField(settings, "pressSpeed")
			try {
				speedNum := speed is Integer ? speed : Integer(speed)
				if (speedNum < 1 || speedNum > 100) {
					error := JSONError(JSONErrorType.CONFIG_INVALID_FIELD, "pressSpeed 应在 1-100 范围，当前: " speedNum, 0, "", "")
					JSONLogger.Log(error)
					errors.Push(error)
				}
			} catch {
				warning := JSONError(JSONErrorType.CONFIG_INVALID_FIELD, "pressSpeed 格式无效: " speed, 0, "", "")
				warning.level := "WARNING"
				JSONLogger.Log(warning)
				errors.Push(warning)
			}
		}

		if (this._HasField(settings, "debounceDelay")) {
			delay := this._GetField(settings, "debounceDelay")
			try {
				delayNum := delay is Integer ? delay : Integer(delay)
				if (delayNum < 0 || delayNum > 1000) {
					warning := JSONError(JSONErrorType.CONFIG_INVALID_FIELD, "debounceDelay 建议在 0-1000 范围，当前: " delayNum, 0, "", "")
					warning.level := "WARNING"
					JSONLogger.Log(warning)
					errors.Push(warning)
				}
			} catch {
				warning := JSONError(JSONErrorType.CONFIG_INVALID_FIELD, "debounceDelay 格式无效: " delay, 0, "", "")
				warning.level := "WARNING"
				JSONLogger.Log(warning)
				errors.Push(warning)
			}
		}

		return errors
	}
    
    static _ValidateHotkeyFormat(hotkey) {
        return true
    }
    
    static _HasField(obj, field) {
        if (obj is Map)
            return obj.Has(field)
        else if (IsObject(obj))
            return HasProp(obj, field)
        return false
    }
    
    static _GetField(obj, field) {
        if (obj is Map)
            return obj[field]
        else if (IsObject(obj) && HasProp(obj, field))
            return obj.%field%
        return ""
    }
    
    static _ArrayContains(arr, value) {
        for item in arr {
            if (item = value)
                return true
        }
        return false
    }
}

; =================================================================
; 结束: JSON 解析器模�?; =================================================================
