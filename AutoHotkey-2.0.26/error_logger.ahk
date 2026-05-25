#Requires AutoHotkey v2.0
#SingleInstance Force

class ErrorLogger {
    static Version := "1.0.0"
    static LogFile := ""
    static MaxLogSize := 10485760
    static MaxLogFiles := 10
    static DebugMode := false
    static LogToConsole := false
    static Initialized := false
    
    static Call(logFile := "", options := "") {
        if !this.Initialized {
            this.Initialize(logFile, options)
        }
        return this
    }
    
    static Initialize(logFile := "", options := "") {
        if this.Initialized
            return
        
        this.LogFile := logFile != "" ? logFile : A_ScriptDir "\logs\error_" A_YYYY A_MM A_DD ".log"
        
        if IsObject(options) {
            if HasProp(options, "MaxLogSize")
                this.MaxLogSize := options.MaxLogSize
            if HasProp(options, "MaxLogFiles")
                this.MaxLogFiles := options.MaxLogFiles
            if HasProp(options, "DebugMode")
                this.DebugMode := options.DebugMode
            if HasProp(options, "LogToConsole")
                this.LogToConsole := options.LogToConsole
        }
        
        SplitPath(this.LogFile, , &logDir)
        if !DirExist(logDir)
            DirCreate(logDir)
        
        OnError(this.LogError.Bind(this), -1)
        
        this.Initialized := true
        this.Log("INFO", "ErrorLogger initialized", {Version: this.Version, LogFile: this.LogFile})
    }
    
    static LogError(Thrown, Mode) {
        if !this.Initialized
            this.Initialize()
        
        try {
            this.CheckLogRotation()
            
            errorInfo := this.ExtractErrorInfo(Thrown)
            errorInfo.Mode := Mode
            
            logEntry := this.FormatLogEntry(errorInfo)
            
            this.WriteToLog(logEntry)
            
            if this.DebugMode
                OutputDebug(logEntry)
            
            if this.LogToConsole
                FileAppend(logEntry, "*")
            
        } catch as e {
            OutputDebug("ErrorLogger: Failed to log error - " e.Message)
        }
        
        return 1
    }
    
    static Log(level, message, extra := "") {
        if !this.Initialized
            this.Initialize()
        
        try {
            entry := Map()
            entry["Timestamp"] := A_Now
            entry["Level"] := level
            entry["Message"] := message
            entry["File"] := A_ScriptName
            entry["Line"] := A_LineNumber
            entry["Function"] := A_ThisFunc
            
            if extra != ""
                entry["Extra"] := extra
            
            logEntry := this.FormatLogEntry(entry)
            this.WriteToLog(logEntry)
            
            if this.DebugMode
                OutputDebug(logEntry)
            
        } catch {
            OutputDebug("ErrorLogger: Failed to write log")
        }
    }
    
    static ExtractErrorInfo(Thrown) {
        info := Map()
        info["Timestamp"] := A_Now
        
        if IsObject(Thrown) {
            if HasProp(Thrown, "Message")
                info["Message"] := Thrown.Message
            else
                info["Message"] := "Unknown error"
            
            if HasProp(Thrown, "What")
                info["What"] := Thrown.What
            
            if HasProp(Thrown, "File")
                info["File"] := Thrown.File
            else
                info["File"] := A_ScriptFullPath
            
            if HasProp(Thrown, "Line")
                info["Line"] := Thrown.Line
            else
                info["Line"] := "Unknown"
            
            if HasProp(Thrown, "Extra")
                info["Extra"] := Thrown.Extra
            
            if HasProp(Thrown, "Stack")
                info["Stack"] := Thrown.Stack
            
            if HasBase(Thrown, Error.Prototype)
                info["Type"] := Type(Thrown)
            else
                info["Type"] := "CustomError"
            
        } else {
            info["Message"] := String(Thrown)
            info["File"] := A_ScriptFullPath
            info["Line"] := "Unknown"
            info["Type"] := "Unknown"
        }
        
        return info
    }
    
    static FormatLogEntry(info) {
        entry := "========================================`n"
        entry .= "Timestamp: " info["Timestamp"] "`n"
        
        if HasProp(info, "Level")
            entry .= "Level: " info["Level"] "`n"
        
        if HasProp(info, "Type")
            entry .= "Type: " info["Type"] "`n"
        
        if HasProp(info, "Mode")
            entry .= "Mode: " info["Mode"] "`n"
        
        entry .= "----------------------------------------`n"
        entry .= "Message: " info["Message"] "`n"
        
        if HasProp(info, "What")
            entry .= "What: " info["What"] "`n"
        
        if HasProp(info, "File")
            entry .= "File: " info["File"] "`n"
        
        if HasProp(info, "Line")
            entry .= "Line: " info["Line"] "`n"
        
        if HasProp(info, "Extra")
            entry .= "Extra: " info["Extra"] "`n"
        
        if HasProp(info, "Stack") {
            entry .= "Stack:`n"
            stackLines := StrSplit(info["Stack"], "`n", "`r")
            for line in stackLines
                entry .= "  " line "`n"
        }
        
        if HasProp(info, "Extra") && IsObject(info["Extra"]) {
            entry .= "Additional Info:`n"
            for key, value in info["Extra"]
                entry .= "  " key ": " value "`n"
        }
        
        entry .= "========================================`n`n"
        
        return entry
    }
    
    static WriteToLog(entry) {
        try {
            FileAppend(entry, this.LogFile, "UTF-8")
        } catch as e {
            OutputDebug("ErrorLogger: Cannot write to log file - " e.Message)
        }
    }
    
    static CheckLogRotation() {
        try {
            if FileExist(this.LogFile) {
                fileSize := FileGetSize(this.LogFile)
                if fileSize > this.MaxLogSize
                    this.RotateLog()
            }
        } catch {
            OutputDebug("ErrorLogger: Failed to check log rotation")
        }
    }
    
    static RotateLog() {
        try {
            baseFile := this.LogFile
            ext := ""
            name := ""
            
            SplitPath(baseFile, , , &ext, &name)
            
            oldestIdx := this.MaxLogFiles
            oldestFile := baseFile "." oldestIdx
            if FileExist(oldestFile)
                FileDelete(oldestFile)
            
            for i in range(this.MaxLogFiles - 1, 1, -1) {
                oldFile := baseFile "." i
                newFile := baseFile "." (i + 1)
                if FileExist(oldFile)
                    FileMove(oldFile, newFile, 1)
            }
            
            if FileExist(baseFile)
                FileMove(baseFile, baseFile ".1", 1)
            
        } catch as e {
            OutputDebug("ErrorLogger: Failed to rotate log - " e.Message)
        }
    }
    
    static CleanOldLogs(logDir := "", daysToKeep := 30) {
        if logDir = ""
            SplitPath(this.LogFile, , &logDir)
        
        try {
            cutoffDate := DateAdd(A_Now, -daysToKeep, "Days")
            
            loop files logDir "\error_*.log" {
                fileDate := StrReplace(A_LoopFileName, "error_", "")
                fileDate := StrReplace(fileDate, ".log", "")
                fileDate := StrReplace(fileDate, ".", "")
                
                if StrLen(fileDate) = 8 {
                    try {
                        if fileDate < cutoffDate
                            FileDelete(A_LoopFileFullPath)
                    } catch {
                        continue
                    }
                }
            }
        } catch as e {
            OutputDebug("ErrorLogger: Failed to clean old logs - " e.Message)
        }
    }
    
    static GetLogStats() {
        stats := Map()
        
        try {
            if FileExist(this.LogFile) {
                stats["Size"] := FileGetSize(this.LogFile)
                stats["Modified"] := FileGetTime(this.LogFile, "M")
                
                content := FileRead(this.LogFile)
                stats["ErrorCount"] := StrCount(content, "========================================`n")
            }
        } catch {
            stats["Error"] := "Failed to get stats"
        }
        
        return stats
    }
}

range(start, end, step := 1) {
    result := []
    if step > 0 {
        while start <= end {
            result.Push(start)
            start += step
        }
    } else {
        while start >= end {
            result.Push(start)
            start += step
        }
    }
    return result
}

StrCount(haystack, needle) {
    count := 0
    pos := 1
    while pos := InStr(haystack, needle, , pos) {
        count++
        pos += StrLen(needle)
    }
    return count
}

ErrorLogger(A_ScriptDir "\logs\error_" A_YYYY A_MM A_DD ".log", {
    MaxLogSize: 10485760,
    MaxLogFiles: 10,
    DebugMode: true,
    LogToConsole: false
})

Main()

Main() {
    ErrorLogger.Log("INFO", "Application started")
    
    try {
        DemoErrorHandling()
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
    }
    
    ErrorLogger.Log("INFO", "Application finished")
}

DemoErrorHandling() {
    ErrorLogger.Log("INFO", "Testing error handling...")
    
    TestDivisionByZero()
    
    TestFileNotFound()
    
    TestCustomError()
    
    TestMethodNotExist()
}

TestDivisionByZero() {
    ErrorLogger.Log("DEBUG", "Testing division by zero")
    try {
        result := 1 / 0
    } catch as e {
        ErrorLogger.Log("WARNING", "Division by zero caught", {Test: "DivisionByZero"})
        throw e
    }
}

TestFileNotFound() {
    ErrorLogger.Log("DEBUG", "Testing file not found")
    try {
        content := FileRead("nonexistent_file_12345.txt")
    } catch as e {
        ErrorLogger.Log("WARNING", "File not found caught", {Test: "FileNotFound"})
        throw e
    }
}

TestCustomError() {
    ErrorLogger.Log("DEBUG", "Testing custom error")
    try {
        throw Error("This is a custom error", -1, "Custom error for testing")
    } catch as e {
        ErrorLogger.Log("WARNING", "Custom error caught", {Test: "CustomError"})
        throw e
    }
}

TestMethodNotExist() {
    ErrorLogger.Log("DEBUG", "Testing method not exist")
    try {
        arr := [1, 2, 3]
        arr.NonExistentMethod()
    } catch as e {
        ErrorLogger.Log("WARNING", "Method not exist caught", {Test: "MethodNotExist"})
        throw e
    }
}
