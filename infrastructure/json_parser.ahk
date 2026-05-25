; =================================================================
; 基础设施层 - JSON 解析器
; 版本: 3.1
; 说明: 强类型 JSON 解析器，支持完整错误诊断与上下文追踪
;       专为技能管理器配置文件设计
;       v3.1: 将解析状态从静态属性改为实例属性，解决并发安全问题
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_logger.ahk"

class JSONParser {
    static MAX_PARSE_DEPTH := 256
    static MAX_LOOP_ITERATIONS := 100000

    static Parse(jsonStr, filePath := "") {
        ctx := JSONParseContext(jsonStr, filePath)
        return ctx.Execute()
    }

    static LoadFile(filePath) {
        if !FileExist(filePath) {
            JSONLogger.Log("ERROR", "文件不存在: " filePath,
                          Map("module", "JSONParser", "code", JSONErrorType.FILE_NOT_FOUND))
            throw Error("文件不存在: " filePath)
        }

        try {
            content := FileRead(filePath, "UTF-8")
        } catch as e {
            JSONLogger.Log("ERROR", "无法读取文件: " e.Message,
                          Map("module", "JSONParser", "code", JSONErrorType.FILE_READ_ERROR))
            throw e
        }

        try {
            return JSONParser.Parse(content, filePath)
        } catch as parseErr {
            return JSONParser._GetFallbackConfig()
        }
    }

    static _GetFallbackConfig() {
        return Map(
            "version", "3.0",
            "lastModified", A_Now,
            "GroupSettings", Map(
                "1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50])
            ),
            "CONTROL_HOTKEYS", Map(
                "emergency", "F12", "toggleAll", "^1", "showStatus", "^0",
                "toggleHoldMode", "^h", "releaseAllHolds", "^r"
            ),
            "HoldSettings", Map(
                "debounceDelay", 20, "checkInterval", 50,
                "allowOverlap", false, "pressSpeed", 80, "releaseOnEmergency", true
            )
        )
    }
}

class JSONParseContext {
    json := ""
    pos := 1
    len := 0
    filePath := ""
    _depth := 0

    __New(jsonStr, filePath := "") {
        if StrLen(jsonStr) > 0 && Ord(SubStr(jsonStr, 1, 1)) = 0xFEFF
            jsonStr := SubStr(jsonStr, 2)

        this.json := jsonStr
        this.len := StrLen(jsonStr)
        this.filePath := filePath
    }

    Execute() {
        JSONLogger.Log("DEBUG", "开始解析JSON" (this.filePath ? " (文件: " this.filePath ")" : ""),
                       Map("module", "JSONParser", "code", JSONErrorType.INFO_PARSE_START))

        if this.len = 0 {
            JSONLogger.Log("WARNING", "JSON字符串为空",
                          Map("module", "JSONParser", "code", JSONErrorType.SYNTAX_EMPTY_INPUT))
            return Map()
        }

        try {
            result := this.ParseValue()
            this.SkipWhitespace()
            if this.pos <= this.len {
                JSONLogger.Log("WARNING", "解析完成后仍有额外字符",
                              Map("module", "JSONParser", "code", JSONErrorType.SYNTAX_EXTRA_CHARS))
            }
            JSONLogger.Log("DEBUG", "JSON解析完成",
                          Map("module", "JSONParser", "code", JSONErrorType.INFO_PARSE_SUCCESS))
            return result
        } catch as e {
            JSONLogger.Log("ERROR", "解析失败: " e.Message,
                          Map("module", "JSONParser", "code", JSONErrorType.SYNTAX_UNEXPECTED))
            throw e
        }
    }

    ParseValue() {
        this._depth++
        if this._depth > JSONParser.MAX_PARSE_DEPTH
            throw Error("JSON 嵌套深度超限 (MAX=" JSONParser.MAX_PARSE_DEPTH ")")

        this.SkipWhitespace()
        if this.pos > this.len
            throw Error("JSON意外结束")

        c := SubStr(this.json, this.pos, 1)
        result := ""

        switch c {
            case "{":
                result := this.ParseObject()
            case "[":
                result := this.ParseArray()
            case '"':
                result := this.ParseString()
            case "t", "f":
                result := this.ParseBool()
            case "n":
                result := this.ParseNull()
            case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                result := this.ParseNumber()
            default:
                throw Error("意外字符: '" c "' (ASCII: " Ord(c) ")")
        }

        this._depth--
        return result
    }

    ParseObject() {
        obj := Map()
        this.pos++
        this.SkipWhitespace()
        iterations := 0

        if SubStr(this.json, this.pos, 1) = "}" {
            this.pos++
            return obj
        }

        loop {
            iterations++
            if iterations > JSONParser.MAX_LOOP_ITERATIONS
                throw Error("对象解析超过最大迭代次数")
            this.SkipWhitespace()
            if SubStr(this.json, this.pos, 1) != '"'
                throw Error("对象键必须是字符串")

            key := this.ParseString()
            this.SkipWhitespace()

            if SubStr(this.json, this.pos, 1) != ":"
                throw Error("缺少冒号分隔符")

            this.pos++
            value := this.ParseValue()
            obj[key] := value

            this.SkipWhitespace()
            c := SubStr(this.json, this.pos, 1)

            if c = "," {
                this.pos++
                this.SkipWhitespace()
                if SubStr(this.json, this.pos, 1) = "}" {
                    this.pos++
                    return obj
                }
                continue
            } else if c = "}" {
                this.pos++
                return obj
            } else {
                throw Error("缺少逗号或对象未闭合")
            }
        }
    }

    ParseArray() {
        arr := []
        this.pos++
        this.SkipWhitespace()
        iterations := 0

        if SubStr(this.json, this.pos, 1) = "]" {
            this.pos++
            return arr
        }

        loop {
            iterations++
            if iterations > JSONParser.MAX_LOOP_ITERATIONS
                throw Error("数组解析超过最大迭代次数")
            this.SkipWhitespace()
            value := this.ParseValue()
            arr.Push(value)
            this.SkipWhitespace()

            c := SubStr(this.json, this.pos, 1)
            if c = "," {
                this.pos++
                this.SkipWhitespace()
                if SubStr(this.json, this.pos, 1) = "]" {
                    this.pos++
                    return arr
                }
                continue
            } else if c = "]" {
                this.pos++
                return arr
            } else {
                throw Error("缺少逗号或数组未闭合")
            }
        }
    }

    ParseString() {
        this.pos++
        start := this.pos
        str := ""

        while this.pos <= this.len {
            c := SubStr(this.json, this.pos, 1)
            if c = '"' {
                str .= SubStr(this.json, start, this.pos - start)
                this.pos++
                return str
            }
            if c = "\" {
                if start < this.pos
                    str .= SubStr(this.json, start, this.pos - start)
                this.pos++
                if this.pos > this.len
                    throw Error("字符串末尾有未完成的转义序列")
                nextChar := SubStr(this.json, this.pos, 1)
                if nextChar = "n"
                    str .= "`n"
                else if nextChar = "t"
                    str .= "`t"
                else if nextChar = "r"
                    str .= "`r"
                else if nextChar = '"'
                    str .= '"'
                else if nextChar = "\"
                    str .= "\"
                else if nextChar = "/"
                    str .= "/"
                else if nextChar = "b"
                    str .= "`b"
                else if nextChar = "f"
                    str .= "`f"
                else if nextChar = "u" {
                    this.pos++
                    if this.pos + 3 > this.len
                        throw Error("不完整的Unicode转义序列")
                    hexStr := SubStr(this.json, this.pos, 4)
                    hexVal := 0
                    for hc in hexStr {
                        hexVal <<= 4
                        hcOrd := Ord(hc)
                        if hcOrd >= 48 && hcOrd <= 57
                            hexVal |= (hcOrd - 48)
                        else if hcOrd >= 65 && hcOrd <= 70
                            hexVal |= (hcOrd - 55)
                        else if hcOrd >= 97 && hcOrd <= 102
                            hexVal |= (hcOrd - 87)
                        else
                            throw Error("无效的Unicode转义: \\u" hexStr)
                    }
                    str .= Chr(hexVal)
                    this.pos += 3
                } else
                    str .= nextChar
                this.pos++
                start := this.pos
                continue
            }
            this.pos++
        }
        throw Error("字符串未闭合")
    }

    ParseNumber() {
        start := this.pos

        if SubStr(this.json, this.pos, 1) = "-"
            this.pos++

        if this.pos > this.len
            throw Error("数字不完整")

        hasDecimal := false
        hasExponent := false

        while this.pos <= this.len {
            c := SubStr(this.json, this.pos, 1)
            cAscii := Ord(c)
            if cAscii >= 48 && cAscii <= 57 {
                this.pos++
            } else if c = "." && !hasDecimal {
                hasDecimal := true
                this.pos++
            } else if c = "e" || c = "E" {
                hasExponent := true
                this.pos++
                if this.pos <= this.len {
                    expSign := SubStr(this.json, this.pos, 1)
                    if expSign = "+" || expSign = "-"
                        this.pos++
                }
            } else {
                break
            }
        }

        numStr := SubStr(this.json, start, this.pos - start)
        if hasDecimal || hasExponent
            return Float(numStr)
        try {
            intVal := Integer(numStr)
            return intVal
        } catch {
            return Float(numStr)
        }
    }

    ParseBool() {
        if SubStr(this.json, this.pos, 4) = "true" {
            this.pos += 4
            return true
        }
        if SubStr(this.json, this.pos, 5) = "false" {
            this.pos += 5
            return false
        }
        throw Error("无效的布尔值")
    }

    ParseNull() {
        if SubStr(this.json, this.pos, 4) = "null" {
            this.pos += 4
            return ""
        }
        throw Error("无效的null值")
    }

    SkipWhitespace() {
        while this.pos <= this.len {
            c := SubStr(this.json, this.pos, 1)
            if c = " " || c = "`t" || c = "`n" || c = "`r"
                this.pos++
            else
                break
        }
    }
}
