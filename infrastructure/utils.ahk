; =================================================================
; 基础设施层 - 通用工具函数
; 版本: 3.0
; 说明: 跨模块共享的通用工具函数
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_parser.ahk"

StrJoin(sep, parts*) {
    result := ""
    for part in parts {
        if result != ""
            result .= sep
        result .= part
    }
    return result
}

_GetProp(obj, key, default := "") {
    if obj is Map
        return obj.Has(key) ? obj[key] : default
    else if IsObject(obj) && HasProp(obj, key)
        return obj.%key%
    return default
}

_GetField(obj, key, defaultVal := "") {
    try {
        if obj is Map {
            return obj.Has(key) ? obj[key] : defaultVal
        }
        if IsObject(obj) && HasProp(obj, key) {
            return obj.%key%
        }
        if IsString(obj) {
            trimmed := LTrim(obj)
            firstChar := SubStr(trimmed, 1, 1)
            if (firstChar = "{" || firstChar = "[") {
                try {
                    parsed := JSONParser.Parse(obj)
                    if parsed is Map
                        return parsed.Has(key) ? parsed[key] : defaultVal
                    if IsObject(parsed) && HasProp(parsed, key)
                        return parsed.%key%
                } catch as e {
                    ; best-effort: JSON 字符串解析失败时返回默认值
                    OutputDebug("ASD [WARN] utils._GetField: " e.Message " at line " e.Line)
                }
            }
        }
        return defaultVal
    } catch {
        return defaultVal
    }
}

class LogRotator {
    static Rotate(logFile, keepCount := 5) {
        try {
            if !FileExist(logFile)
                return true

            timestamp := StrReplace(StrReplace(A_Now, ":", ""), " ", "_") "_" A_MSec
            backupFile := RegExReplace(logFile, "\.log$", "_" timestamp ".log.bak")
            FileMove(logFile, backupFile, 1)

            LogRotator._CleanupOldBackups(logFile, keepCount)
            return true
        } catch as e {
            OutputDebug("LogRotator.Rotate failed: " e.Message)
            return false
        }
    }

    static _CleanupOldBackups(logFile, keepCount) {
        try {
            pattern := RegExReplace(logFile, "\.log$", "_*.log.bak")
            backups := []

            Loop Files, pattern {
                try {
                    ft := FileGetTime(A_LoopFileFullPath, "M")
                    backups.Push({path: A_LoopFileFullPath, time: ft})
                } catch {
                    backups.Push({path: A_LoopFileFullPath, time: "0"})
                }
            }

            if backups.Length <= keepCount
                return

            n := backups.Length
            loop n - 1 {
                i := A_Index + 1
                key := backups[i]
                j := i - 1
                while j >= 1 && backups[j].time < key.time {
                    backups[j + 1] := backups[j]
                    j--
                }
                backups[j + 1] := key
            }

            deleteCount := backups.Length - keepCount
            loop deleteCount {
                try
                    FileDelete(backups[A_Index].path)
                catch as e
                    OutputDebug("LogRotator: failed to delete " backups[A_Index].path ": " e.Message)
            }
        } catch as e {
            OutputDebug("LogRotator._CleanupOldBackups failed: " e.Message)
        }
    }
}