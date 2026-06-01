; =================================================================
; IPC 客户端 - Named Pipe 客户端（核心）
; 版本: 1.0
; 说明: AHK 子进程通过 Windows Named Pipe 连接 Rust 主进程
;       实现 JSON Lines 协议、seq/ack_seq 确认、心跳、断线重连
;       内含精简 JSON 解析器，无外部依赖
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; =================================================================
; 常量
; =================================================================

class IPCConst {
    static PIPE_NAME := "\\.\pipe\asd_ipc"
    static MAX_MSG_SIZE := 65536       ; 64KB
    static READ_BUF_SIZE := 4096
    static HEARTBEAT_TIMEOUT_MS := 5000
    static RECONNECT_BASE_MS := 1000
    static RECONNECT_MAX_MS := 30000
    static POLL_INTERVAL_MS := 50
    static INVALID_HANDLE := -1
    static GENERIC_READ_WRITE := 0xC0000000
    static SHARE_NONE := 0
    static OPEN_EXISTING := 3
    static FILE_ATTRIBUTE_NORMAL := 0x80
    static FILE_FLAG_OVERLAPPED := 0x40000000
}

; =================================================================
; 精简 JSON 解析器 — 仅支持 IPC 协议所需的结构
; 返回 Map，数组返回 Array
; =================================================================

class MiniJson {
    static NULL_MARKER := Chr(0xFFFE)
    ; 布尔标记：AHK v2 中 true=1, false=0，无法通过 = 或 Type() 区分。
    ; 使用专用 Unicode 私用区字符作为标记，在 _StringifyScalar 中匹配后
    ; 输出 JSON true/false，确保 Rust 端 serde_json 能正确反序列化 bool 字段。
    ; 用法：Map("active", MiniJson.BOOL_TRUE) 而非 Map("active", true)
    static BOOL_TRUE := Chr(0xFFFC)
    static BOOL_FALSE := Chr(0xFFFB)

    static Parse(jsonStr) {
        if jsonStr = ""
            return Map()
        ctx := MiniJsonCtx(jsonStr)
        return ctx.ParseValue()
    }

    static Stringify(obj) {
        if obj is Map
            return MiniJson._StringifyMap(obj)
        if obj is Array
            return MiniJson._StringifyArray(obj)
        if IsObject(obj)
            return MiniJson._StringifyObject(obj)
        return MiniJson._StringifyScalar(obj)
    }

    static _StringifyMap(m) {
        parts := []
        for k, v in m {
            keyStr := '"' k '"'
            valStr := MiniJson.Stringify(v)
            parts.Push(keyStr ':' valStr)
        }
        result := '{'
        for i, p in parts {
            if i > 1
                result .= ','
            result .= p
        }
        result .= '}'
        return result
    }

    static _StringifyArray(arr) {
        parts := []
        for v in arr
            parts.Push(MiniJson.Stringify(v))
        result := '['
        for i, p in parts {
            if i > 1
                result .= ','
            result .= p
        }
        result .= ']'
        return result
    }

    static _StringifyObject(obj) {
        parts := []
        for k in ObjOwnProps(obj) {
            keyStr := '"' k '"'
            valStr := MiniJson.Stringify(obj.%k%)
            parts.Push(keyStr ':' valStr)
        }
        result := '{'
        for i, p in parts {
            if i > 1
                result .= ','
            result .= p
        }
        result .= '}'
        return result
    }

    static _StringifyScalar(val) {
        if val = MiniJson.NULL_MARKER
            return "null"
        ; 布尔标记检查：必须在整数检查之前，因为 AHK v2 中 true=1, false=0，
        ; "if val = true" 会同时匹配整数 1，导致 seq:1 被序列化为 "seq":true
        if val = MiniJson.BOOL_TRUE
            return "true"
        if val = MiniJson.BOOL_FALSE
            return "false"
        if val = ""
            return '""'
        if val is Integer
            return String(val)
        if val is Float
            return String(val)
        escaped := StrReplace(val, "\", "\\")
        escaped := StrReplace(escaped, '"', '\"')
        escaped := StrReplace(escaped, "`n", "\n")
        escaped := StrReplace(escaped, "`r", "\r")
        escaped := StrReplace(escaped, "`t", "\t")
        return '"' escaped '"'
    }
}

class MiniJsonCtx {
    json := ""
    pos := 1
    len := 0

    __New(jsonStr) {
        if StrLen(jsonStr) > 0 && Ord(SubStr(jsonStr, 1, 1)) = 0xFEFF
            jsonStr := SubStr(jsonStr, 2)
        this.json := jsonStr
        this.len := StrLen(jsonStr)
    }

    ParseValue() {
        this.SkipWS()
        if this.pos > this.len
            return ""
        c := SubStr(this.json, this.pos, 1)
        switch c {
            case "{":
                return this.ParseObj()
            case "[":
                return this.ParseArr()
            case '"':
                return this.ParseStr()
            case "t", "f":
                return this.ParseBool()
            case "n":
                return this.ParseNull()
            case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                return this.ParseNum()
            default:
                return ""
        }
    }

    ParseObj() {
        obj := Map()
        this.pos++
        this.SkipWS()
        if SubStr(this.json, this.pos, 1) = "}" {
            this.pos++
            return obj
        }
        loop {
            this.SkipWS()
            if SubStr(this.json, this.pos, 1) != '"'
                return obj
            key := this.ParseStr()
            this.SkipWS()
            if SubStr(this.json, this.pos, 1) = ":"
                this.pos++
            val := this.ParseValue()
            obj[key] := val
            this.SkipWS()
            c := SubStr(this.json, this.pos, 1)
            if c = "," {
                this.pos++
                this.SkipWS()
                if SubStr(this.json, this.pos, 1) = "}" {
                    this.pos++
                    return obj
                }
                continue
            }
            if c = "}" {
                this.pos++
                return obj
            }
            return obj
        }
    }

    ParseArr() {
        arr := []
        this.pos++
        this.SkipWS()
        if SubStr(this.json, this.pos, 1) = "]" {
            this.pos++
            return arr
        }
        loop {
            this.SkipWS()
            val := this.ParseValue()
            arr.Push(val)
            this.SkipWS()
            c := SubStr(this.json, this.pos, 1)
            if c = "," {
                this.pos++
                this.SkipWS()
                if SubStr(this.json, this.pos, 1) = "]" {
                    this.pos++
                    return arr
                }
                continue
            }
            if c = "]" {
                this.pos++
                return arr
            }
            return arr
        }
    }

    ParseStr() {
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
                    return str
                nc := SubStr(this.json, this.pos, 1)
                switch nc {
                    case "n": str .= "`n"
                    case "t": str .= "`t"
                    case "r": str .= "`r"
                    case '"': str .= '"'
                    case "\": str .= "\"
                    case "/": str .= "/"
                    case "b": str .= "`b"
                    case "f": str .= "`f"
                    case "u": str := this._ParseUnicodeEscape(&str)
                    default: str .= nc
                }
                this.pos++
                start := this.pos
                continue
            }
            this.pos++
        }
        return str
    }

    ParseNum() {
        start := this.pos
        if SubStr(this.json, this.pos, 1) = "-"
            this.pos++
        hasDot := false
        hasExp := false
        while this.pos <= this.len {
            c := SubStr(this.json, this.pos, 1)
            cOrd := Ord(c)
            if cOrd >= 48 && cOrd <= 57
                this.pos++
            else if c = "." && !hasDot {
                hasDot := true
                this.pos++
            } else if (c = "e" || c = "E") && !hasExp {
                hasExp := true
                this.pos++
                if this.pos <= this.len {
                    es := SubStr(this.json, this.pos, 1)
                    if es = "+" || es = "-"
                        this.pos++
                }
            } else
                break
        }
        numStr := SubStr(this.json, start, this.pos - start)
        if hasDot || hasExp
            return Float(numStr)
        try
            return Integer(numStr)
        catch
            return Float(numStr)
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
        return false
    }

    ParseNull() {
        if SubStr(this.json, this.pos, 4) = "null" {
            this.pos += 4
            return MiniJson.NULL_MARKER
        }
        return ""
    }

    SkipWS() {
        while this.pos <= this.len {
            c := SubStr(this.json, this.pos, 1)
            if c = " " || c = "`t" || c = "`n" || c = "`r"
                this.pos++
            else
                break
        }
    }

    _ParseUnicodeEscape(&str) {
        this.pos++
        if this.pos + 3 > this.len
            return str
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
        }

        ; 代理对处理：高代理 D800-DBFF + 低代理 DC00-DFFF
        if (hexVal >= 0xD800 && hexVal <= 0xDBFF) {
            if (this.pos + 9 <= this.len && SubStr(this.json, this.pos + 4, 2) = "\u") {
                lowHexStr := SubStr(this.json, this.pos + 6, 4)
                lowHexVal := 0
                for lhc in lowHexStr {
                    lowHexVal <<= 4
                    lhcOrd := Ord(lhc)
                    if lhcOrd >= 48 && lhcOrd <= 57
                        lowHexVal |= (lhcOrd - 48)
                    else if lhcOrd >= 65 && lhcOrd <= 70
                        lowHexVal |= (lhcOrd - 55)
                    else if lhcOrd >= 97 && lhcOrd <= 102
                        lowHexVal |= (lhcOrd - 87)
                }
                if (lowHexVal >= 0xDC00 && lowHexVal <= 0xDFFF) {
                    codePoint := 0x10000 + ((hexVal - 0xD800) << 10) + (lowHexVal - 0xDC00)
                    str .= Chr(codePoint)
                    this.pos += 9
                    return str
                }
            }
        }

        str .= Chr(hexVal)
        this.pos += 3
        return str
    }
}

; =================================================================
; IPC 客户端类
; =================================================================

class IpcClient {
    ; 连接状态
    static hPipe := -1
    static connected := false
    static shuttingDown := false

    ; 序列号管理
    static _seqCounter := 0
    static _lastAckSeq := 0

    ; 重连退避
    static _reconnectDelay := IPCConst.RECONNECT_BASE_MS
    static _reconnectTimer := 0

    ; 心跳
    static _lastPingTime := 0
    static _heartbeatTimer := 0

    ; 消息循环
    static _pollTimer := 0
    static _readBuffer := ""

    ; 认证令牌（从 --auth-token 命令行参数读取）
    static _authToken := ""
    static _authParseRetries := 0

    ; 回调
    static OnCommand := ""        ; (action, data) => void
    static OnShutdown := ""       ; () => void
    static OnConnected := ""      ; () => void
    static OnDisconnected := ""   ; () => void

    ; =================================================================
    ; 公开方法
    ; =================================================================

    static Start() {
        IpcClient.shuttingDown := false
        IpcClient._ParseAuthToken()
        IpcClient._TryConnect()
    }

    static _ParseAuthToken() {
        if IpcClient._authToken != ""
            return

        try {
            envToken := EnvGet("ASD_AUTH_TOKEN")
            if envToken != "" {
                IpcClient._authToken := envToken
                OutputDebug("IpcClient: 从环境变量读取 auth_token")
                return
            }
        }

        loop A_Args.Length {
            if A_Args[A_Index] = "--auth-token" && A_Index < A_Args.Length {
                IpcClient._authToken := A_Args[A_Index + 1]
                OutputDebug("IpcClient: 从命令行参数读取 auth_token")
                return
            }
        }
        OutputDebug("IpcClient: 未找到 auth_token，将重试解析")
    }

    static Stop() {
        IpcClient.shuttingDown := true
        IpcClient._StopTimers()
        IpcClient._ClosePipe()
    }

    static IsConnected() {
        return IpcClient.connected
    }

    ; 发送 result 消息
    static SendResult(ackSeq, data) {
        msg := Map(
            "type", "result",
            "seq", IpcClient._NextSeq(),
            "ack_seq", ackSeq,
            "data", data
        )
        return IpcClient._SendMsg(msg)
    }

    ; 发送 hotkey 事件
    static SendHotkeyEvent(keys*) {
        msg := Map(
            "type", "hotkey",
            "seq", IpcClient._NextSeq(),
            "action", "hotkey_event",
            "keys", keys
        )
        return IpcClient._SendMsg(msg)
    }

    ; 发送 error 消息
    static SendError(code, message) {
        msg := Map(
            "type", "error",
            "seq", IpcClient._NextSeq(),
            "action", "error",
            "data", Map("code", code, "message", message)
        )
        return IpcClient._SendMsg(msg)
    }

    ; 发送 pong 响应
    static SendPong(ackSeq) {
        msg := Map(
            "type", "pong",
            "seq", IpcClient._NextSeq(),
            "ack_seq", ackSeq
        )
        return IpcClient._SendMsg(msg)
    }

    ; =================================================================
    ; 连接管理
    ; =================================================================

    static _TryConnect() {
        if IpcClient.shuttingDown
            return

        if IpcClient._authToken = "" {
            IpcClient._authParseRetries++
            if IpcClient._authParseRetries > 5 {
                OutputDebug("IpcClient: auth-token 缺失，超过最大重试次数，退出")
                ExitApp(1)
            }
            OutputDebug("IpcClient: auth-token 为空，500ms 后重试解析 (attempt=" IpcClient._authParseRetries ")")
            IpcClient._reconnectTimer := () => (IpcClient._ParseAuthToken(), IpcClient._TryConnect())
            SetTimer(IpcClient._reconnectTimer, -500)
            return
        }

        hPipe := DllCall("CreateFileW",
            "Str", IPCConst.PIPE_NAME,
            "UInt", IPCConst.GENERIC_READ_WRITE,
            "UInt", IPCConst.SHARE_NONE,
            "Ptr", 0,
            "UInt", IPCConst.OPEN_EXISTING,
            "UInt", IPCConst.FILE_ATTRIBUTE_NORMAL,
            "Ptr", 0,
            "Ptr")

        if (hPipe = -1 || hPipe = 0 || hPipe = 0xFFFFFFFF) {
            OutputDebug("IpcClient: 连接失败，" IpcClient._reconnectDelay "ms 后重试")
            IpcClient._reconnectTimer := () => IpcClient._TryConnect()
            SetTimer(IpcClient._reconnectTimer, -IpcClient._reconnectDelay)
            IpcClient._reconnectDelay := Min(IpcClient._reconnectDelay * 2, IPCConst.RECONNECT_MAX_MS)
            return
        }

        IpcClient.hPipe := hPipe
        IpcClient.connected := true
        IpcClient._reconnectDelay := IPCConst.RECONNECT_BASE_MS
        IpcClient._lastPingTime := A_TickCount
        IpcClient._readBuffer := ""
        IpcClient._lastAckSeq := 0

        OutputDebug("IpcClient: 已连接到 " IPCConst.PIPE_NAME)

        if IpcClient.OnConnected
            IpcClient.OnConnected.Call()

        ; 发送认证消息
        authMsg := Map(
            "type", "auth",
            "seq", IpcClient._NextSeq(),
            "data", Map("token", IpcClient._authToken)
        )
        IpcClient._SendMsg(authMsg)

        IpcClient._StartPolling()
        IpcClient._StartHeartbeatCheck()
    }

    static _ClosePipe() {
        if (IpcClient.hPipe != -1 && IpcClient.hPipe != 0) {
            try
                DllCall("CloseHandle", "Ptr", IpcClient.hPipe)
            IpcClient.hPipe := -1
        }
        IpcClient.connected := false
    }

    static _HandleDisconnect(reason) {
        if !IpcClient.connected
            return

        OutputDebug("IpcClient: 断开连接 - " reason)
        IpcClient._StopTimers()
        IpcClient._ClosePipe()

        if IpcClient.OnDisconnected
            IpcClient.OnDisconnected.Call()

        if !IpcClient.shuttingDown
            IpcClient._TryConnect()
    }

    ; =================================================================
    ; 消息轮询
    ; =================================================================

    static _StartPolling() {
        IpcClient._pollTimer := () => IpcClient._Poll()
        SetTimer(IpcClient._pollTimer, IPCConst.POLL_INTERVAL_MS)
    }

    static _StartHeartbeatCheck() {
        IpcClient._heartbeatTimer := () => IpcClient._CheckHeartbeat()
        SetTimer(IpcClient._heartbeatTimer, 1000)
    }

    static _StopTimers() {
        if IpcClient._pollTimer {
            SetTimer(IpcClient._pollTimer, 0)
            IpcClient._pollTimer := 0
        }
        if IpcClient._heartbeatTimer {
            SetTimer(IpcClient._heartbeatTimer, 0)
            IpcClient._heartbeatTimer := 0
        }
        if IpcClient._reconnectTimer {
            SetTimer(IpcClient._reconnectTimer, 0)
            IpcClient._reconnectTimer := 0
        }
    }

    static _Poll() {
        if (!IpcClient.connected || IpcClient.hPipe = -1 || IpcClient.hPipe = 0)
            return

        bytesAvail := 0
        result := DllCall("PeekNamedPipe",
            "Ptr", IpcClient.hPipe,
            "Ptr", 0, "UInt", 0, "Ptr", 0,
            "UInt*", &bytesAvail,
            "UInt*", 0, "UInt*", 0)

        if !result {
            IpcClient._HandleDisconnect("PeekNamedPipe 失败")
            return
        }

        if bytesAvail = 0
            return

        bufSize := Min(bytesAvail, IPCConst.READ_BUF_SIZE)
        buf := Buffer(bufSize, 0)
        bytesRead := 0

        ok := DllCall("ReadFile",
            "Ptr", IpcClient.hPipe,
            "Ptr", buf.Ptr,
            "UInt", bufSize,
            "UInt*", &bytesRead,
            "Ptr", 0)

        if !ok || bytesRead = 0 {
            IpcClient._HandleDisconnect("ReadFile 失败或管道关闭")
            return
        }

        chunk := StrGet(buf.Ptr, bytesRead, "UTF-8")
        IpcClient._readBuffer .= chunk

        if StrLen(IpcClient._readBuffer) > IPCConst.MAX_MSG_SIZE {
            IpcClient._readBuffer := ""
            OutputDebug("IpcClient: 读缓冲区溢出，已清空")
            return
        }

        IpcClient._ProcessBuffer()
    }

    static _ProcessBuffer() {
        loop {
            nlPos := InStr(IpcClient._readBuffer, "`n")
            if nlPos = 0
                break

            line := SubStr(IpcClient._readBuffer, 1, nlPos - 1)
            line := StrReplace(line, "`r", "")
            IpcClient._readBuffer := SubStr(IpcClient._readBuffer, nlPos + 1)

            if line = ""
                continue

            if StrLen(line) > IPCConst.MAX_MSG_SIZE {
                OutputDebug("IpcClient: 单行消息超限，跳过")
                continue
            }

            IpcClient._HandleLine(line)
        }
    }

    static _HandleLine(line) {
        try {
            msg := MiniJson.Parse(line)
        } catch as e {
            OutputDebug("IpcClient: JSON 解析失败 - " e.Message)
            return
        }

        if !(msg is Map) {
            OutputDebug("IpcClient: 消息不是 Map 对象")
            return
        }

        msgType := msg.Has("type") ? msg["type"] : ""
        seq := msg.Has("seq") ? msg["seq"] : 0

        ; seq/ack_seq 去重
        if seq > 0 && seq <= IpcClient._lastAckSeq && msgType != "ping" {
            OutputDebug("IpcClient: 忽略重复消息 seq=" seq)
            return
        }

        switch msgType {
            case "command":
                IpcClient._HandleCommand(msg, seq)
            case "ping":
                IpcClient._HandlePing(seq)
            case "shutdown":
                IpcClient._HandleShutdown(seq)
            default:
                OutputDebug("IpcClient: 未知消息类型 - " msgType)
        }
    }

    ; =================================================================
    ; 消息处理
    ; =================================================================

    static _HandleCommand(msg, seq) {
        action := msg.Has("action") ? msg["action"] : ""
        data := msg.Has("data") ? msg["data"] : Map()

        if seq > IpcClient._lastAckSeq
            IpcClient._lastAckSeq := seq

        ; 防御性路由：即使 Rust 侧误用 IpcCommand::Ping/Shutdown（type="command"），
        ; 也能正确转发到对应的处理器
        switch action {
            case "ping":
                IpcClient._HandlePing(seq)
                return
            case "shutdown":
                IpcClient._HandleShutdown(seq)
                return
        }

        OutputDebug("IpcClient: 收到命令 action=" action " seq=" seq)

        if IpcClient.OnCommand
            IpcClient.OnCommand.Call(action, data, seq)
    }

    static _HandlePing(seq) {
        IpcClient._lastPingTime := A_TickCount
        IpcClient.SendPong(seq)
        OutputDebug("IpcClient: ping→pong seq=" seq)
    }

    static _HandleShutdown(seq) {
        OutputDebug("IpcClient: 收到关机指令 seq=" seq)

        IpcClient.SendResult(seq, Map("status", "ok"))

        if IpcClient.OnShutdown
            IpcClient.OnShutdown.Call()

        IpcClient.Stop()
        ExitApp(0)
    }

    static _CheckHeartbeat() {
        if !IpcClient.connected
            return

        elapsed := A_TickCount - IpcClient._lastPingTime
        if elapsed > IPCConst.HEARTBEAT_TIMEOUT_MS {
            OutputDebug("IpcClient: 心跳超时 " elapsed "ms")
            IpcClient._HandleDisconnect("心跳超时")
        }
    }

    ; =================================================================
    ; 发送
    ; =================================================================

    static _SendMsg(msg) {
        if (!IpcClient.connected || IpcClient.hPipe = -1 || IpcClient.hPipe = 0)
            return false

        jsonStr := MiniJson.Stringify(msg)
        jsonStr .= "`n"

        bytes := Buffer(StrPut(jsonStr, "UTF-8"))
        StrPut(jsonStr, bytes.Ptr, bytes.Size, "UTF-8")
        bytesToWrite := bytes.Size - 1

        bytesWritten := 0
        ok := DllCall("WriteFile",
            "Ptr", IpcClient.hPipe,
            "Ptr", bytes.Ptr,
            "UInt", bytesToWrite,
            "UInt*", &bytesWritten,
            "Ptr", 0)

        if !ok || bytesWritten != bytesToWrite {
            OutputDebug("IpcClient: 写入失败 ok=" ok " written=" bytesWritten "/" bytesToWrite)
            IpcClient._HandleDisconnect("WriteFile 失败")
            return false
        }

        return true
    }

    static _NextSeq() {
        IpcClient._seqCounter++
        return IpcClient._seqCounter
    }
}
