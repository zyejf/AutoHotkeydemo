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

; =================================================================
; 日志限速统一阈值（毫秒）：热路径日志每秒最多落盘一次
; 供 DebugLogger / ErrorSystem / JSONLogger 共享引用，避免口径分叉
; =================================================================
global LOG_RATE_LIMIT_MS := 1000

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
        return defaultVal
    } catch {
        return defaultVal
    }
}

; =================================================================
; 通用插入排序：按指定字段对数组元素排序（M13 代码重复消除）
; 兼容 Map（obj[key]）与 Object（obj.%key%）两种访问方式
; descending=true 降序（默认，大值在前），descending=false 升序（小值在前）
; =================================================================
_SortByField(arr, key, descending := true) {
    n := arr.Length
    if n <= 1
        return arr
    Loop n - 1 {
        i := A_Index + 1
        cur := arr[i]
        curVal := _GetProp(cur, key, 0)
        j := i - 1
        while j >= 1 {
            prevVal := _GetProp(arr[j], key, 0)
            if descending {
                if prevVal >= curVal
                    break
            } else {
                if prevVal <= curVal
                    break
            }
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := cur
    }
    return arr
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

            ; M13: 调用通用 _SortByField 替代手动插入排序（降序：新文件在前）
            _SortByField(backups, "time", true)

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