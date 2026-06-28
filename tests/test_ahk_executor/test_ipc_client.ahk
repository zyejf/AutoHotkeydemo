; =================================================================
; test_ipc_client.ahk - 测试 AHK 执行器 IPC 客户端
; 目标：验证 ipc_client.ahk 中 MiniJson 解析器与 IpcClient 消息构造
; 注意：不测试真实 named pipe 连接（依赖外部进程）
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; 被测脚本
#Include "../../asd-tauri/src-tauri/ahk_executor/ipc_client.ahk"

; 测试框架（提供 AutoHotUnitSuite 基类）
#Include "../AutoHotUnit.ahk"

; 警告设置（在 #Include 之后，覆盖 AutoHotUnit.ahk 的 #Warn All）
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 运行时错误接管
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试套件：IPCConst 常量
; =================================================================

class IPCConstTests extends AutoHotUnitSuite {
    Test_PipeName_HasPipePrefix() {
        this.assert.isTrue(InStr(IPCConst.PIPE_NAME, "\\.\pipe\") > 0)
    }

    Test_MaxMsgSize_Positive() {
        this.assert.isTrue(IPCConst.MAX_MSG_SIZE > 0)
    }

    Test_HeartbeatTimeout_Positive() {
        this.assert.isTrue(IPCConst.HEARTBEAT_TIMEOUT_MS > 0)
    }

    Test_ReconnectBaseMs_Positive() {
        this.assert.isTrue(IPCConst.RECONNECT_BASE_MS > 0)
    }

    Test_ReconnectMaxMs_GreaterThanBase() {
        this.assert.isTrue(IPCConst.RECONNECT_MAX_MS >= IPCConst.RECONNECT_BASE_MS)
    }

    Test_PollInterval_Positive() {
        this.assert.isTrue(IPCConst.POLL_INTERVAL_MS > 0)
    }

    Test_InvalidHandle_Negative() {
        this.assert.isTrue(IPCConst.INVALID_HANDLE < 0)
    }
}

; =================================================================
; 测试套件：MiniJson.Parse 对象解析
; =================================================================

class MiniJsonParseObjectTests extends AutoHotUnitSuite {
    Test_Parse_SimpleObject() {
        result := MiniJson.Parse('{"key":"value","num":42}')
        this.assert.isTrue(result is Map)
        this.assert.equal(result["key"], "value")
        this.assert.equal(result["num"], 42)
    }

    Test_Parse_EmptyObject() {
        result := MiniJson.Parse('{}')
        this.assert.isTrue(result is Map)
        this.assert.equal(result.Count, 0)
    }

    Test_Parse_NestedObject() {
        result := MiniJson.Parse('{"outer":{"inner":"val"}}')
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result["outer"] is Map)
        this.assert.equal(result["outer"]["inner"], "val")
    }

    Test_Parse_ObjectWithArray() {
        result := MiniJson.Parse('{"arr":[1,2,3]}')
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result["arr"] is Array)
        this.assert.equal(result["arr"].Length, 3)
    }

    Test_Parse_EmptyString_ReturnsEmptyMap() {
        result := MiniJson.Parse("")
        this.assert.isTrue(result is Map)
        this.assert.equal(result.Count, 0)
    }

    Test_Parse_BOMPrefix_Stripped() {
        bom := Chr(0xFEFF)
        result := MiniJson.Parse(bom '{"a":1}')
        this.assert.isTrue(result is Map)
        this.assert.equal(result["a"], 1)
    }
}

; =================================================================
; 测试套件：MiniJson.Parse 数组解析
; =================================================================

class MiniJsonParseArrayTests extends AutoHotUnitSuite {
    Test_Parse_SimpleArray() {
        result := MiniJson.Parse('[1, 2, 3]')
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 3)
        this.assert.equal(result[1], 1)
        this.assert.equal(result[2], 2)
        this.assert.equal(result[3], 3)
    }

    Test_Parse_EmptyArray() {
        result := MiniJson.Parse('[]')
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 0)
    }

    Test_Parse_ArrayOfStrings() {
        result := MiniJson.Parse('["a","b","c"]')
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 3)
        this.assert.equal(result[2], "b")
    }

    Test_Parse_ArrayOfMixed() {
        result := MiniJson.Parse('[1, "two", true, null]')
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 4)
        this.assert.equal(result[1], 1)
        this.assert.equal(result[2], "two")
        this.assert.equal(result[3], true)
    }

    Test_Parse_NestedArray() {
        result := MiniJson.Parse('[[1,2],[3,4]]')
        this.assert.isTrue(result is Array)
        this.assert.isTrue(result[1] is Array)
        this.assert.equal(result[1][1], 1)
        this.assert.equal(result[2][2], 4)
    }
}

; =================================================================
; 测试套件：MiniJson.Parse 标量解析
; =================================================================

class MiniJsonParseScalarTests extends AutoHotUnitSuite {
    Test_Parse_Integer() {
        this.assert.equal(MiniJson.Parse('42'), 42)
    }

    Test_Parse_NegativeInteger() {
        this.assert.equal(MiniJson.Parse('-10'), -10)
    }

    Test_Parse_Float() {
        result := MiniJson.Parse('3.14')
        this.assert.isTrue(result is Float)
        this.assert.equal(result, 3.14)
    }

    Test_Parse_True() {
        this.assert.equal(MiniJson.Parse('true'), true)
    }

    Test_Parse_False() {
        this.assert.equal(MiniJson.Parse('false'), false)
    }

    Test_Parse_Null_ReturnsMarker() {
        result := MiniJson.Parse('null')
        this.assert.equal(result, MiniJson.NULL_MARKER)
    }

    Test_Parse_String_WithEscapes() {
        result := MiniJson.Parse('"hello\nworld"')
        this.assert.equal(result, "hello`nworld")
    }

    Test_Parse_String_WithTab() {
        result := MiniJson.Parse('"a\tb"')
        this.assert.equal(result, "a`tb")
    }

    Test_Parse_String_WithQuote() {
        result := MiniJson.Parse('"say \"hi\""')
        this.assert.equal(result, 'say "hi"')
    }

    Test_Parse_String_WithBackslash() {
        result := MiniJson.Parse('"path\\file"')
        this.assert.equal(result, "path\file")
    }
}

; =================================================================
; 测试套件：MiniJson.Stringify 序列化
; =================================================================

class MiniJsonStringifyTests extends AutoHotUnitSuite {
    Test_Stringify_SimpleMap() {
        m := Map("key", "value")
        result := MiniJson.Stringify(m)
        this.assert.isTrue(InStr(result, '"key"') > 0)
        this.assert.isTrue(InStr(result, '"value"') > 0)
    }

    Test_Stringify_EmptyMap() {
        this.assert.equal(MiniJson.Stringify(Map()), "{}")
    }

    Test_Stringify_EmptyArray() {
        this.assert.equal(MiniJson.Stringify([]), "[]")
    }

    Test_Stringify_Integer() {
        result := MiniJson.Stringify(42)
        this.assert.equal(result, "42")
    }

    Test_Stringify_String() {
        result := MiniJson.Stringify("hello")
        this.assert.equal(result, '"hello"')
    }

    Test_Stringify_EmptyString() {
        this.assert.equal(MiniJson.Stringify(""), '""')
    }

    Test_Stringify_BoolTrue() {
        result := MiniJson.Stringify(MiniJson.BOOL_TRUE)
        this.assert.equal(result, "true")
    }

    Test_Stringify_BoolFalse() {
        result := MiniJson.Stringify(MiniJson.BOOL_FALSE)
        this.assert.equal(result, "false")
    }

    Test_Stringify_NullMarker() {
        result := MiniJson.Stringify(MiniJson.NULL_MARKER)
        this.assert.equal(result, "null")
    }

    Test_Stringify_ArrayWithIntegers() {
        result := MiniJson.Stringify([1, 2, 3])
        this.assert.equal(result, "[1,2,3]")
    }

    Test_Stringify_MapWithInteger() {
        m := Map("seq", 1)
        result := MiniJson.Stringify(m)
        this.assert.isTrue(InStr(result, '"seq":1') > 0)
    }

    Test_Stringify_EscapesBackslash() {
        result := MiniJson.Stringify("a\b")
        this.assert.isTrue(InStr(result, "\\") > 0)
    }

    Test_Stringify_EscapesQuote() {
        result := MiniJson.Stringify('say "hi"')
        this.assert.isTrue(InStr(result, '\"') > 0)
    }

    Test_Stringify_NestedMap() {
        inner := Map("a", 1)
        outer := Map("inner", inner)
        result := MiniJson.Stringify(outer)
        this.assert.isTrue(InStr(result, '"inner"') > 0)
        this.assert.isTrue(InStr(result, '"a":1') > 0)
    }
}

; =================================================================
; 测试套件：MiniJson 圆环往返（Round-trip）
; =================================================================

class MiniJsonRoundTripTests extends AutoHotUnitSuite {
    Test_RoundTrip_SimpleMap() {
        original := Map("key", "value", "num", 42)
        jsonStr := MiniJson.Stringify(original)
        parsed := MiniJson.Parse(jsonStr)
        this.assert.equal(parsed["key"], "value")
        this.assert.equal(parsed["num"], 42)
    }

    Test_RoundTrip_Array() {
        original := [1, 2, 3]
        jsonStr := MiniJson.Stringify(original)
        parsed := MiniJson.Parse(jsonStr)
        this.assert.equal(parsed.Length, 3)
        this.assert.equal(parsed[1], 1)
    }

    Test_RoundTrip_NestedStructure() {
        inner := Map("a", "b")
        outer := Map("inner", inner, "count", 5)
        jsonStr := MiniJson.Stringify(outer)
        parsed := MiniJson.Parse(jsonStr)
        this.assert.equal(parsed["count"], 5)
        this.assert.isTrue(parsed["inner"] is Map)
        this.assert.equal(parsed["inner"]["a"], "b")
    }
}

; =================================================================
; 测试套件：MiniJson 布尔标记常量
; =================================================================

class MiniJsonBoolMarkerTests extends AutoHotUnitSuite {
    Test_BoolTrue_NotEmpty() {
        this.assert.isTrue(MiniJson.BOOL_TRUE != "")
    }

    Test_BoolFalse_NotEmpty() {
        this.assert.isTrue(MiniJson.BOOL_FALSE != "")
    }

    Test_BoolTrue_NotEqualsBoolFalse() {
        this.assert.isTrue(MiniJson.BOOL_TRUE != MiniJson.BOOL_FALSE)
    }

    Test_NullMarker_NotEmpty() {
        this.assert.isTrue(MiniJson.NULL_MARKER != "")
    }
}

; =================================================================
; 测试套件：IpcClient 初始状态
; =================================================================

class IpcClientInitialStateTests extends AutoHotUnitSuite {
    Test_IsConnected_InitialFalse() {
        this.assert.isFalse(IpcClient.IsConnected())
    }

    Test_SeqCounter_NonNegative() {
        this.assert.isTrue(IpcClient._seqCounter >= 0)
    }

    Test_AuthToken_InitialEmpty() {
        this.assert.equal(IpcClient._authToken, "")
    }

    Test_LastAckSeq_InitialZero() {
        this.assert.equal(IpcClient._lastAckSeq, 0)
    }
}

; =================================================================
; 测试套件：IpcClient._NextSeq 序列号管理
; =================================================================

class IpcClientNextSeqTests extends AutoHotUnitSuite {
    Test_NextSeq_Increments() {
        before := IpcClient._seqCounter
        result := IpcClient._NextSeq()
        this.assert.equal(result, before + 1)
        this.assert.equal(IpcClient._seqCounter, before + 1)
    }

    Test_NextSeq_ReturnsUniqueValues() {
        s1 := IpcClient._NextSeq()
        s2 := IpcClient._NextSeq()
        s3 := IpcClient._NextSeq()
        this.assert.isTrue(s2 > s1)
        this.assert.isTrue(s3 > s2)
    }
}

; =================================================================
; 测试套件：IpcClient 消息发送（未连接状态）
; =================================================================

class IpcClientSendDisconnectedTests extends AutoHotUnitSuite {
    Test_SendResult_Disconnected_ReturnsFalse() {
        IpcClient.connected := false
        result := IpcClient.SendResult(1, Map("status", "ok"))
        this.assert.isFalse(result)
    }

    Test_SendHotkeyEvent_Disconnected_ReturnsFalse() {
        IpcClient.connected := false
        result := IpcClient.SendHotkeyEvent("F1")
        this.assert.isFalse(result)
    }

    Test_SendError_Disconnected_ReturnsFalse() {
        IpcClient.connected := false
        result := IpcClient.SendError("E001", "test error")
        this.assert.isFalse(result)
    }

    Test_SendPong_Disconnected_ReturnsFalse() {
        IpcClient.connected := false
        result := IpcClient.SendPong(1)
        this.assert.isFalse(result)
    }

    Test_SendResult_Disconnected_DoesNotThrow() {
        IpcClient.connected := false
        try {
            IpcClient.SendResult(2, Map("status", "ok"))
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("SendResult 未连接不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：IpcClient._ParseAuthToken 认证令牌解析
; =================================================================

class IpcClientParseAuthTokenTests extends AutoHotUnitSuite {
    afterAll() {
        IpcClient._authToken := ""
        IpcClient._authParseRetries := 0
    }

    Test_ParseAuthToken_NoEnvNoArg_LeavesEmpty() {
        IpcClient._authToken := ""
        IpcClient._authParseRetries := 0
        try {
            IpcClient._ParseAuthToken()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("_ParseAuthToken 不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：IpcClient._HandleLine 消息去重
; =================================================================

class IpcClientDeduplicationTests extends AutoHotUnitSuite {
    afterAll() {
        IpcClient._lastAckSeq := 0
    }

    Test_HandleLine_InvalidJSON_DoesNotThrow() {
        IpcClient._lastAckSeq := 0
        try {
            IpcClient._HandleLine("not valid json {{{")
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("_HandleLine 无效 JSON 不应抛出异常: " e.Message)
        }
    }

    Test_HandleLine_NonMapMessage_DoesNotThrow() {
        IpcClient._lastAckSeq := 0
        try {
            IpcClient._HandleLine('"just a string"')
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("_HandleLine 非 Map 消息不应抛出异常: " e.Message)
        }
    }

    Test_HandleLine_EmptyLine_DoesNotThrow() {
        IpcClient._lastAckSeq := 0
        try {
            IpcClient._HandleLine("")
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("_HandleLine 空行不应抛出异常: " e.Message)
        }
    }
}
