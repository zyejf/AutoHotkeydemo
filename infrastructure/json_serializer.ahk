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
            try {
                if value is Map
                    result := this._StringifyObject(value, indent, currentIndent, visited)
                else if value is Array
                    result := this._StringifyArray(value, indent, currentIndent, visited)
                else
                    result := this._StringifyObject(value, indent, currentIndent, visited)
            } finally {
                visited.Delete(ptr)
            }
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

    ; JSON 字符串转义（T1 快路径）。
    ;
    ; 需转义的字符集合（与 JSON 规范一致，也是 _EscapeStringCharByChar 的行为）：
    ;   0x00-0x1F 全部控制字符 —— 其中 08/09/0A/0C/0D 有短写法（\b \t \n \f \r），
    ;   其余（00-07、0B、0E-1F）走 \uXXXX；
    ;   外加 0x22（"）与 0x5C（\）。
    ;
    ; ⚠️ 快路径的三个判定必须**合起来恰好覆盖**上面这个集合，漏一个就会静默产出非法 JSON。
    ;   等价性已逐字符验证：单字符 0..127 + 前后夹字符 0..127 + 24 个组合场景，diffs=0
    ;   （含 NUL / DEL / U+2028 / 首尾反斜杠等），见 JSONSerializerEscapeTests。
    ;
    ; 基准（tools/ahk-bench/bench_json_escape.ahk）：
    ;   2KB 0.8776 → 0.4995 ms、8KB 3.5606 → 2.0600 ms（≈1.75×）。
    static _EscapeString(str) {
        ; ① 快路径：不含引号、不含反斜杠、不含任何控制字符 → 原样返回。
        ;    配置与日志里绝大多数字符串走这一条。
        ;    ⚠️ AHK 的 RegExMatch 能正确识别字符串中的 NUL（实测 Chr(0) 匹配成功），
        ;       不存在 C 字符串截断问题。
        if !InStr(str, '"') && !InStr(str, "\") && !RegExMatch(str, "[\x00-\x1F]")
            return str

        ; ② 含「没有短写法的控制字符」（00-07、0B、0E-1F，需 \uXXXX）→ 退回逐字符版，
        ;    保证与原来的输出逐字节一致。
        if RegExMatch(str, "[\x00-\x07\x0B\x0E-\x1F]")
            return JSONSerializer._EscapeStringCharByChar(str)

        ; ③ 其余：用原生 StrReplace 批量替换（一次遍历，避免 n 次字符串重建）。
        ;    ⚠️ 反斜杠必须**第一个**替换：若先替换引号会引入新的反斜杠，
        ;       再被反斜杠那一轮二次转义成 \\（顺序反了输出就错）。
        s := StrReplace(str, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        return s
    }

    ; 逐字符版：原实现，现只作为「含 \uXXXX 控制字符」的兜底路径。
    ; 同时它是 _EscapeString 快路径的等价性基准（测试里用作 oracle）。
    static _EscapeStringCharByChar(str) {
        result := ""
        pos := 1
        len := StrLen(str)
        while pos <= len {
            c := SubStr(str, pos, 1)
            code := Ord(c)
            if code = 8
                result .= "\b"
            else if code = 9
                result .= "\t"
            else if code = 10
                result .= "\n"
            else if code = 12
                result .= "\f"
            else if code = 13
                result .= "\r"
            else if code = 34
                result .= "\`""
            else if code = 92
                result .= "\\"
            else if code < 32
                result .= "\u" Format("{:04X}", code)
            else
                result .= c
            pos++
        }
        return result
    }
}
