; =================================================================
; 基础设施层 - IPC 进程间通信预留接口
; 版本: 3.0
; 说明: 为未来跨进程通信提供预留接口
;       当前实现基于文件管道的最简通道
;       后续可升级为 WM_COPYDATA / TCP Socket / Named Pipe
;       使用 OnMessage 监听外部消息
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_logger.ahk"
#Include "json_parser.ahk"
#Include "json_serializer.ahk"

class IPCChannel {
    static channelDir := "ipc"
    static inboundPipe := ""
    static outboundPipe := ""
    static listeners := Map()
    static msgType := 0x8001
    static initialized := false

    static Init() {
        if IPCChannel.initialized
            return true

        ; M17: 目录创建包裹 try-catch，失败时记录明确错误并返回
        ; 不设置 initialized，允许下次 Init 重试
        ; Minor-2: 失败时返回 false，成功时返回 true
        if !InStr(FileExist(IPCChannel.channelDir), "D") {
            try
                DirCreate(IPCChannel.channelDir)
            catch as ex {
                JSONLogger.Log("ERROR", "IPC通道目录创建失败: " ex.Message,
                              Map("module", "IPCChannel"))
                return false
            }
        }

        IPCChannel.inboundPipe := IPCChannel.channelDir "\inbound.json"
        IPCChannel.outboundPipe := IPCChannel.channelDir "\outbound.json"

        OnMessage(IPCChannel.msgType, IPCChannel._OnReceived)

        ; M17: initialized 标志移到所有初始化步骤成功后
        IPCChannel.initialized := true

        JSONLogger.Log("DEBUG", "IPC通道已初始化",
                      Map("module", "IPCChannel"))
        return true
    }

    ; 注册消息监听器
    static On(eventName, callback) {
        if !IPCChannel.listeners.Has(eventName)
            IPCChannel.listeners[eventName] := []
        IPCChannel.listeners[eventName].Push(callback)
    }

    ; 发送消息到外部进程
    static Send(target, message) {
        IPCChannel.Init()

        try {
            IPCChannel._EnforcePipeSize(IPCChannel.outboundPipe)
            msgObj := Map(
                "type", "message",
                "target", target,
                "data", message,
                "timestamp", A_Now,
                "traceId", IPCChannel._GenerateTraceId()
            )
            jsonStr := JSONSerializer.Stringify(msgObj)
            FileAppend(jsonStr "`n", IPCChannel.outboundPipe, "UTF-8")
            return true
        } catch as e {
            JSONLogger.Log("ERROR", "IPC发送失败: " e.Message,
                          Map("module", "IPCChannel"))
            return false
        }
    }

    ; 广播事件
    static Emit(eventName, data := "") {
        IPCChannel.Init()

        try {
            IPCChannel._EnforcePipeSize(IPCChannel.outboundPipe)
            msgObj := Map(
                "type", "event",
                "event", eventName,
                "data", data,
                "timestamp", A_Now,
                "traceId", IPCChannel._GenerateTraceId()
            )
            jsonStr := JSONSerializer.Stringify(msgObj)
            FileAppend(jsonStr "`n", IPCChannel.outboundPipe, "UTF-8")
            return true
        } catch as e {
            JSONLogger.Log("ERROR", "IPC事件发送失败: " e.Message,
                          Map("module", "IPCChannel"))
            return false
        }
    }

    ; 检查入站消息
    static PollMessages() {
        IPCChannel.Init()

        if !FileExist(IPCChannel.inboundPipe)
            return []

        messages := []
        try {
            tempPipe := IPCChannel.inboundPipe ".reading"
            moved := true
            try
                FileMove(IPCChannel.inboundPipe, tempPipe)
            catch
                moved := false

            content := ""
            if moved {
                try {
                    content := FileRead(tempPipe, "UTF-8")
                }
                try
                    FileDelete(tempPipe)
                catch as ex {
                    ; best-effort: 临时管道文件清理失败不影响消息读取
                    OutputDebug("ASD [WARN] IPCChannel.PollMessages: " ex.Message " at line " ex.Line)
                }
            } else {
                try {
                    content := FileRead(IPCChannel.inboundPipe, "UTF-8")
                    try
                        FileDelete(IPCChannel.inboundPipe)
                    catch as ex {
                        ; best-effort: 入站管道文件清理失败不影响消息读取
                        OutputDebug("ASD [WARN] IPCChannel.PollMessages: " ex.Message " at line " ex.Line)
                    }
                } catch {
                    return messages
                }
            }

            lines := StrSplit(content, "`n", "`r")

            for line in lines {
                line := Trim(line)
                if line = ""
                    continue
                try {
                    msg := JSONParser.Parse(line)
                    if msg is Map
                        messages.Push(msg)
                }
            }
        } catch as e {
            JSONLogger.Log("WARNING", "IPC消息轮询失败: " e.Message,
                          Map("module", "IPCChannel"))
        }

        return messages
    }

    ; 内部消息处理器
    static _OnReceived(wParam, lParam, msg, hwnd) {
        messages := IPCChannel.PollMessages()

        for msgObj in messages {
            eventName := msgObj.Has("event") ? msgObj["event"] : ""
            if eventName = "" || !IPCChannel.listeners.Has(eventName)
                continue

            for callback in IPCChannel.listeners[eventName] {
                try
                    callback(msgObj)
            }
        }
    }

    static _GenerateTraceId() {
        return Format("{1:04x}", Random(1, 0xFFFF)) SubStr(A_Now, 1, 12)
    }

    static _EnforcePipeSize(pipePath) {
        try {
            if !FileExist(pipePath)
                return
            size := FileGetSize(pipePath)
            if size > 1048576 {
                FileDelete(pipePath)
            }
        } catch as e {
            ; best-effort: 管道大小检查/清理失败不影响正常通信
            OutputDebug("ASD [WARN] IPCChannel._EnforcePipeSize: " e.Message " at line " e.Line)
        }
    }
}
