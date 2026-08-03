; =================================================================
; DI 重构 C1 测试 - 领域层依赖倒置验证
; 验证 JoystickExecutor 不再直接依赖 infrastructure/joy_sender
; 通过 IJoySender 抽象接口 + 依赖注入解除违规引用
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 加载顺序: 先领域层（含 interfaces/joystick_input/error_system），再基础设施层 joy_sender
; GREEN 阶段后 joystick_executor.ahk 不再 #Include joy_sender，故此处单独加载
#Include "..\domain\joystick_executor.ahk"
#Include "..\infrastructure\joy_sender.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; MockJoySender - 测试替身（鸭子类型，记录所有调用）
; 不 extends IJoySender 以保证 RED 阶段（IJoySender 未定义时）也能加载
; =================================================================
class MockJoySender {
    static callLog := []

    SendBtn(btn, state, method := "vjoy") {
        MockJoySender.callLog.Push("SendBtn|" btn "|" state "|" method)
    }

    SendPov(direction, method := "vjoy") {
        MockJoySender.callLog.Push("SendPov|" direction "|" method)
    }

    SendAxis(axis, value, method := "vjoy") {
        MockJoySender.callLog.Push("SendAxis|" axis "|" value "|" method)
    }

    ReleaseAll() {
        MockJoySender.callLog.Push("ReleaseAll")
    }
}

; =================================================================
; 测试用例（每个返回 "" 表示 PASS，非空字符串表示 FAIL 原因）
; =================================================================

; TC1: IJoySender 类已定义于 domain/interfaces.ahk
Test_IJoySender_IsDefined() {
    global IJoySender
    if Type(IJoySender) = "Class"
        return ""
    return "IJoySender 未定义或非 Class 类型"
}

; TC2: IJoySender 拥有全部抽象方法
Test_IJoySender_AbstractMethods() {
    global IJoySender
    inst := IJoySender()
    if !HasMethod(inst, "SendBtn")
        return "缺少 SendBtn 方法"
    if !HasMethod(inst, "SendPov")
        return "缺少 SendPov 方法"
    if !HasMethod(inst, "SendAxis")
        return "缺少 SendAxis 方法"
    if !HasMethod(inst, "ReleaseAll")
        return "缺少 ReleaseAll 方法"
    return ""
}

; TC3: 直接调用 IJoySender 实例的抽象方法应抛出异常
Test_IJoySender_AbstractThrows() {
    global IJoySender
    try {
        inst := IJoySender()
        inst.SendBtn(1, true)
        return "SendBtn 未抛出异常"
    } catch as e {
        if InStr(e.Message, "未实现") || InStr(e.Message, "抽象")
            return ""
        return "抛出异常但非抽象方法异常: " e.Message
    }
}

; TC4: JoySender 类继承 IJoySender
Test_JoySender_ExtendsIJoySender() {
    global IJoySender
    if HasBase(JoySender.Prototype, IJoySender.Prototype)
        return ""
    return "JoySender 未继承 IJoySender"
}

; TC5: joystick_executor.ahk 源码不再 #Include joy_sender
Test_JoystickExecutor_NoInfraInclude() {
    src := FileRead(A_ScriptDir "\..\domain\joystick_executor.ahk", "UTF-8")
    if InStr(src, '#Include "../infrastructure/joy_sender')
        return "仍包含 #Include ../infrastructure/joy_sender"
    return ""
}

; TC6: JoystickExecutor 拥有 SetJoySender 静态方法
Test_JoystickExecutor_SetJoySender() {
    if HasMethod(JoystickExecutor, "SetJoySender")
        return ""
    return "JoystickExecutor 缺少 SetJoySender 方法"
}

; TC7: 未注入 JoySender 时调用 _SendJoyKey 应抛出异常
Test_JoystickExecutor_NotInjectedThrows() {
    JoystickExecutor._joySender := ""
    try {
        JoystickExecutor._SendJoyKey("Joy1", "down", "vjoy")
        return "未注入时未抛出异常"
    } catch as e {
        if InStr(e.Message, "未注入") || InStr(e.Message, "JoySender")
            return ""
        return "抛出异常但消息不符: " e.Message
    }
}

; TC8: 注入 mock JoySender 后 _SendJoyKey 正常工作
Test_JoystickExecutor_InjectedWorks() {
    MockJoySender.callLog := []
    JoystickExecutor.SetJoySender(MockJoySender())
    JoystickExecutor._SendJoyKey("Joy1", "down", "vjoy")
    if MockJoySender.callLog.Length = 0
        return "mock 未记录调用"
    if InStr(MockJoySender.callLog[1], "SendBtn")
        return ""
    return "mock 记录非 SendBtn: " MockJoySender.callLog[1]
}

; TC9: 反向依赖已解除 - 通过 mock 注入即可工作，不依赖 JoySender 全局符号
Test_ReverseDependency_Removed() {
    MockJoySender.callLog := []
    JoystickExecutor.SetJoySender(MockJoySender())
    JoystickExecutor._SendJoyKey("Joy1", "down", "vjoy")
    JoystickExecutor._SendJoyKey("JoyPOV_UP", "down", "vjoy")
    JoystickExecutor._SendJoyKey("JoyX_RIGHT", "down", "vjoy")
    if MockJoySender.callLog.Length < 3
        return "mock 调用次数不足: " MockJoySender.callLog.Length
    return ""
}

; =================================================================
; 测试运行器 - 接收箭头函数，内部 try-catch 隔离异常
; =================================================================
global g_passCount := 0
global g_failCount := 0

Check(name, fn) {
    global g_passCount, g_failCount
    try {
        result := fn()
        if result = "" {
            g_passCount++
            FileAppend("PASS: " name "`n", "*")
        } else {
            g_failCount++
            FileAppend("FAIL: " name " - " result "`n", "*")
        }
    } catch as e {
        g_failCount++
        FileAppend("FAIL: " name " - 异常: " e.Message "`n", "*")
    }
}

; =================================================================
; 执行测试
; =================================================================
FileAppend("=== DI Refactor C1 Test Start ===`n", "*")
Check("Test_IJoySender_IsDefined", () => Test_IJoySender_IsDefined())
Check("Test_IJoySender_AbstractMethods", () => Test_IJoySender_AbstractMethods())
Check("Test_IJoySender_AbstractThrows", () => Test_IJoySender_AbstractThrows())
Check("Test_JoySender_ExtendsIJoySender", () => Test_JoySender_ExtendsIJoySender())
Check("Test_JoystickExecutor_NoInfraInclude", () => Test_JoystickExecutor_NoInfraInclude())
Check("Test_JoystickExecutor_SetJoySender", () => Test_JoystickExecutor_SetJoySender())
Check("Test_JoystickExecutor_NotInjectedThrows", () => Test_JoystickExecutor_NotInjectedThrows())
Check("Test_JoystickExecutor_InjectedWorks", () => Test_JoystickExecutor_InjectedWorks())
Check("Test_ReverseDependency_Removed", () => Test_ReverseDependency_Removed())
FileAppend("=== Result: " g_passCount " passed, " g_failCount " failed ===`n", "*")
