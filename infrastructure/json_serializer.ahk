; =================================================================
; 基础设施层 - JSON 序列化器
; 版本: 3.0
; 说明: 将 AHK 数据结构序列化为 JSON 字符串
;       支持 Map / Array / 基本类型的递归序列化
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class JSONSerializer {
    static _spacesCache := Map()

    static Stringify(value, indent := 2) {
        visited := Map()
        return this._StringifyValue(value, indent, 0, visited)
    }

    static _StringifyValue(value, indent, currentIndent, visited) {
        if IsObject(value) {
            ptr := ObjPtr(value)
            if visited.Has(ptr)
                return '"<circular>"'
            visited[ptr] := true

            if value is Map
                result := this._StringifyObject(value, indent, currentIndent, visited)
            else if value is Array
                result := this._StringifyArray(value, indent, currentIndent, visited)
            else
                result := this._StringifyObject(value, indent, currentIndent, visited)

            visited.Delete(ptr)
            return result
        } else if value is String {
            return '"' this._EscapeString(value) '"'
        } else if Type(value) = "Boolean" || value = true || value = false {
            return value ? "true" : "false"
        } else if value is Integer || value is Float {
            return String(value)
        }
        return "null"
    }

    static _StringifyObject(obj, indent, currentIndent, visited) {
        if obj.Count = 0
            return "{}"

        spaces := this._BuildSpaces(currentIndent)
        nextSpaces := this._BuildSpaces(currentIndent + indent)
        result := "{`n"
        first := true

        for key, value in obj {
            if !first
                result .= ",`n"
            first := false
            result .= nextSpaces '"' this._EscapeString(key) '": '
            result .= this._StringifyValue(value, indent, currentIndent + indent, visited)
        }

        result .= "`n" spaces "}"
        return result
    }

    static _StringifyArray(arr, indent, currentIndent, visited) {
        if arr.Length = 0
            return "[]"

        spaces := this._BuildSpaces(currentIndent)
        nextSpaces := this._BuildSpaces(currentIndent + indent)
        result := "[`n"
        first := true

        for item in arr {
            if !first
                result .= ",`n"
            first := false
            result .= nextSpaces this._StringifyValue(item, indent, currentIndent + indent, visited)
        }

        result .= "`n" spaces "]"
        return result
    }

    static _BuildSpaces(count) {
        if JSONSerializer._spacesCache.Has(count)
            return JSONSerializer._spacesCache[count]
        spaces := ""
        loop count
            spaces .= " "
        JSONSerializer._spacesCache[count] := spaces
        return spaces
    }

    static _EscapeString(str) {
        str := StrReplace(str, '\', '\\')
        str := StrReplace(str, '"', '\"')
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        str := StrReplace(str, "`b", "\b")
        str := StrReplace(str, "`f", "\f")
        result := ""
        pos := 1
        len := StrLen(str)
        while pos <= len {
            c := SubStr(str, pos, 1)
            code := Ord(c)
            if code < 32 && code != 10 && code != 13 && code != 9 && code != 8 && code != 12 {
                result .= "\u" Format("{:04X}", code)
            } else {
                result .= c
            }
            pos++
        }
        return result
    }
}
