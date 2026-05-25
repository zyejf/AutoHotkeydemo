#Requires AutoHotkey v2.0
#SingleInstance Force

OnError(LogError, -1)

global LogFile := A_ScriptDir "\simple_test.log"

try {
    Main()
} catch as e {
    LogError(e, "Exit")
}

Main() {
    FileAppend("Test started at " A_Now "`n", LogFile)
    
    try {
        result := 1 / 0
    } catch as e {
        FileAppend("Error caught: " e.Message "`n", LogFile)
    }
    
    FileAppend("Test completed at " A_Now "`n", LogFile)
    MsgBox("Test completed! Check " LogFile)
}

LogError(Thrown, Mode) {
    global LogFile
    
    try {
        errorMsg := "Error: "
        
        if IsObject(Thrown) && HasProp(Thrown, "Message") {
            errorMsg .= Thrown.Message
            
            if HasProp(Thrown, "File")
                errorMsg .= " in " Thrown.File
            
            if HasProp(Thrown, "Line")
                errorMsg .= " (Line " Thrown.Line ")"
        } else {
            errorMsg .= String(Thrown)
        }
        
        FileAppend(errorMsg "`n", LogFile)
        
    } catch {
        OutputDebug("Failed to log error")
    }
    
    return 1
}
