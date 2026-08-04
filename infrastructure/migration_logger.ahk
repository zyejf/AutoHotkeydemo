#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "utils.ahk"

class MigrationLogger {
    static _logFile := A_ScriptDir "\logs\migrations.log"
    static _entries := []

    static _ToString(val) {
        if val is Array || val is Map
            return JSONSerializer.Stringify(val)
        if IsObject(val)
            return JSONSerializer.Stringify(val)
        return String(val)
    }

    static Log(fromVersion, toVersion, groupId, field, oldValue, newValue) {
        entry := Map(
            "timestamp", A_Now,
            "fromVersion", fromVersion,
            "toVersion", toVersion,
            "groupId", groupId,
            "field", field,
            "oldValue", MigrationLogger._ToString(oldValue),
            "newValue", MigrationLogger._ToString(newValue)
        )
        MigrationLogger._entries.Push(entry)
    }

    static Flush() {
        if MigrationLogger._entries.Length = 0
            return
        try {
            logDir := A_ScriptDir "\logs"
            if !DirExist(logDir)
                DirCreate(logDir)
            lines := []
            for entry in MigrationLogger._entries {
                parts := []
                for k, v in entry
                    parts.Push(k "=" v)
                lines.Push(StrJoin("|", parts*))
            }
            content := StrJoin("`n", lines*)
            FileAppend(content "`n", MigrationLogger._logFile)
            MigrationLogger._entries := []
        } catch as e {
            OutputDebug("MigrationLogger.Flush failed: " e.Message)
        }
    }

    static GetHistory() {
        try {
            if !FileExist(MigrationLogger._logFile)
                return []
            content := FileRead(MigrationLogger._logFile)
            lines := StrSplit(content, "`n")
            result := []
            for line in lines {
                line := Trim(line)
                if line = ""
                    continue
                entry := Map()
                parts := StrSplit(line, "|")
                for part in parts {
                    kv := StrSplit(part, "=", , 2)
                    if kv.Length = 2
                        entry[kv[1]] := kv[2]
                }
                if entry.Count > 0
                    result.Push(entry)
            }
            return result
        } catch {
            return []
        }
    }
}
