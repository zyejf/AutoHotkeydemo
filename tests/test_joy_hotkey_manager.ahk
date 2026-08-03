; =================================================================
; joy_hotkey_manager 测试 - 手柄热键/轴轮询/热插拔检测
; =================================================================
; 覆盖 infrastructure/joy_hotkey_manager.ahk 的关键功能路径：
;   1. 热键注册/注销（按钮 Joy1~Joy32、轴、POV、扳机）
;   2. 轴/POV 轮询逻辑（值变化检测、回调触发）
;   3. 热插拔检测（连接轮询、IsConnected）
;   4. 多手柄支持（joystickId 切换影响注册 key）
;   5. 错误处理（无效 key、未注册注销、不存在 groupId）
; 测试策略：不依赖真实硬件，直接测试状态管理逻辑与纯逻辑内部方法
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\infrastructure\joy_hotkey_manager.ahk"
#Include "..\infrastructure\error_system.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 全局回调记录器
; 说明: 用全局数组记录回调触发，避免箭头函数闭包捕获局部变量的问题
; =================================================================
global G_CB_LOG := []

_TestCb(gid) {
    global G_CB_LOG
    G_CB_LOG.Push(gid)
}

; =================================================================
; 断言辅助函数
; =================================================================
AssertTrue(cond, msg) {
    if !cond
        throw Error(msg)
}

AssertFalse(cond, msg) {
    if cond
        throw Error(msg)
}

AssertEqual(actual, expected, msg) {
    if !(actual = expected)
        throw Error(msg " 期望[" String(expected) "] 实际[" String(actual) "]")
}

AssertNoThrow(fn, msg) {
    try fn()
    catch as e
        throw Error(msg " 抛异常: " e.Message)
}

; =================================================================
; 测试运行器
; =================================================================
class JoyHkTestRunner {
    static total := 0
    static passed := 0
    static failed := 0

    ; 重置 JoyHotkeyManager 静态状态，确保测试隔离
    ; 注意: 不重置 _connPollActive，避免重复启动 30s 连接轮询定时器
    static Reset() {
        global G_CB_LOG
        ; 先停止可能存在的轮询定时器
        if JoyHotkeyManager._pollFn {
            try SetTimer(JoyHotkeyManager._pollFn, 0)
        }
        JoyHotkeyManager._registered := Map()
        JoyHotkeyManager._pollActive := false
        JoyHotkeyManager._pollFn := 0
        JoyHotkeyManager._povLastState := -1
        JoyHotkeyManager._wasConnected := false
        JoyHotkeyManager._joystickId := 1
        JoyHotkeyManager._lastAxisState := Map()
        JoyHotkeyManager._lastTriggerState := Map()
        G_CB_LOG := []
    }

    static RunTest(name, fn) {
        JoyHkTestRunner.total++
        try {
            fn()
            JoyHkTestRunner.passed++
            FileAppend("  PASS: " name "`n", "*")
        } catch as e {
            JoyHkTestRunner.failed++
            FileAppend("  FAIL: " name " -> " e.Message "`n", "*")
        }
    }

    static Report() {
        FileAppend("`n===== 测试汇总 =====`n", "*")
        FileAppend("总计: " JoyHkTestRunner.total " | 通过: " JoyHkTestRunner.passed " | 失败: " JoyHkTestRunner.failed "`n", "*")
    }
}

; =================================================================
; 场景A: 热键注册（按钮/POV/轴/扳机/无效key）
; =================================================================
FileAppend("=== Test Start ===`n", "*")
FileAppend("--- 场景A: 热键注册 ---`n", "*")

JoyHkTestRunner.RunTest("A1_RegisterHotkey_Joy1_按钮注册返回true", () => (
    JoyHkTestRunner.Reset(),
    result := JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    AssertTrue(result, "Joy1注册应返回true"),
    AssertTrue(JoyHotkeyManager._registered.Has("1Joy1"), "应注册1Joy1"),
    AssertTrue(JoyHotkeyManager._registered["1Joy1"] is Array, "按钮注册应为Array")
))

JoyHkTestRunner.RunTest("A2_RegisterHotkey_JoyPOV_UP_POV注册返回true", () => (
    JoyHkTestRunner.Reset(),
    result := JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid)),
    AssertTrue(result, "POV注册应返回true"),
    AssertTrue(JoyHotkeyManager._registered.Has("JoyPOV_UP"), "应注册JoyPOV_UP")
))

JoyHkTestRunner.RunTest("A3_RegisterHotkey_JoyX_RIGHT_轴注册返回true", () => (
    JoyHkTestRunner.Reset(),
    result := JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    AssertTrue(result, "轴注册应返回true"),
    AssertTrue(JoyHotkeyManager._registered.Has("JoyX_RIGHT"), "应注册JoyX_RIGHT")
))

JoyHkTestRunner.RunTest("A4_RegisterHotkey_JoyZ_DOWN_扳机注册返回true", () => (
    JoyHkTestRunner.Reset(),
    result := JoyHotkeyManager.RegisterHotkey("JoyZ_DOWN", "g1", (gid) => _TestCb(gid)),
    AssertTrue(result, "扳机注册应返回true"),
    AssertTrue(JoyHotkeyManager._registered.Has("JoyZ_DOWN"), "应注册JoyZ_DOWN")
))

JoyHkTestRunner.RunTest("A5_RegisterHotkey_无效key返回false", () => (
    JoyHkTestRunner.Reset(),
    result := JoyHotkeyManager.RegisterHotkey("InvalidKey", "g1", (gid) => _TestCb(gid)),
    AssertFalse(result, "无效key应返回false")
))

; =================================================================
; 场景B: 重复注册/多groupId
; =================================================================
FileAppend("--- 场景B: 重复注册/多groupId ---`n", "*")

JoyHkTestRunner.RunTest("B1_重复注册同groupId返回true不重复", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    result := JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    AssertTrue(result, "重复注册同groupId应返回true"),
    AssertEqual(JoyHotkeyManager._registered["1Joy1"].Length, 1, "重复注册不应增加条目")
))

JoyHkTestRunner.RunTest("B2_不同groupId同按钮可共存", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g2", (gid) => _TestCb(gid)),
    AssertEqual(JoyHotkeyManager._registered["1Joy1"].Length, 2, "不同groupId应共存2条")
))

; =================================================================
; 场景C: 注销
; =================================================================
FileAppend("--- 场景C: 注销 ---`n", "*")

JoyHkTestRunner.RunTest("C1_UnregisterHotkey_按钮注销清理注册表", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager.UnregisterHotkey("Joy1", "g1"),
    AssertFalse(JoyHotkeyManager._registered.Has("1Joy1"), "注销后不应有1Joy1")
))

JoyHkTestRunner.RunTest("C2_UnregisterHotkey_轴注销清理注册表", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager.UnregisterHotkey("JoyX_RIGHT", "g1"),
    AssertFalse(JoyHotkeyManager._registered.Has("JoyX_RIGHT"), "轴注销后不应有该key")
))

JoyHkTestRunner.RunTest("C3_UnregisterHotkey_未注册key不抛异常", () => (
    JoyHkTestRunner.Reset(),
    AssertNoThrow(() => JoyHotkeyManager.UnregisterHotkey("Joy1", "g1"), "注销未注册key不应抛异常")
))

JoyHkTestRunner.RunTest("C4_UnregisterAll_清理指定groupId所有注册", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g2", (gid) => _TestCb(gid)),
    JoyHotkeyManager.UnregisterAll("g1"),
    AssertFalse(JoyHotkeyManager._registered.Has("1Joy1"), "g1的Joy1应被清理"),
    AssertFalse(JoyHotkeyManager._registered.Has("JoyPOV_UP"), "g1的POV应被清理"),
    AssertTrue(JoyHotkeyManager._registered.Has("JoyX_RIGHT"), "g2的轴应保留")
))

JoyHkTestRunner.RunTest("C5_UnregisterAll_不存在groupId不抛异常", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    AssertNoThrow(() => JoyHotkeyManager.UnregisterAll("g999"), "注销不存在groupId不应抛异常"),
    AssertTrue(JoyHotkeyManager._registered.Has("1Joy1"), "不存在groupId注销不应影响其他注册")
))

; =================================================================
; 场景D: 多手柄支持
; =================================================================
FileAppend("--- 场景D: 多手柄支持 ---`n", "*")

JoyHkTestRunner.RunTest("D1_Init_设置joystickId", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.Init(3),
    AssertEqual(JoyHotkeyManager._joystickId, 3, "Init(3)应设置joystickId=3")
))

JoyHkTestRunner.RunTest("D2_Init_多手柄ID切换影响注册key", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.Init(2),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    AssertTrue(JoyHotkeyManager._registered.Has("2Joy1"), "ID=2应注册2Joy1"),
    AssertFalse(JoyHotkeyManager._registered.Has("1Joy1"), "不应有1Joy1")
))

; =================================================================
; 场景E: 轴/POV 轮询逻辑（直接调用纯逻辑内部方法）
; =================================================================
FileAppend("--- 场景E: 轴/POV 轮询逻辑 ---`n", "*")

JoyHkTestRunner.RunTest("E1_CheckAxisState_高值触发RIGHT回调", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._lastAxisState["JoyX"] := 0,
    JoyHotkeyManager._CheckAxisState("JoyX", 80, "RIGHT", 70, "LEFT", 30),
    AssertEqual(G_CB_LOG.Length, 1, "应触发1次回调"),
    AssertEqual(G_CB_LOG[1], "g1", "groupId应为g1")
))

JoyHkTestRunner.RunTest("E2_CheckAxisState_低值触发LEFT回调", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_LEFT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._lastAxisState["JoyX"] := 0,
    JoyHotkeyManager._CheckAxisState("JoyX", 20, "RIGHT", 70, "LEFT", 30),
    AssertEqual(G_CB_LOG.Length, 1, "应触发1次LEFT回调")
))

JoyHkTestRunner.RunTest("E3_CheckAxisState_中值不触发回调", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._lastAxisState["JoyX"] := 0,
    JoyHotkeyManager._CheckAxisState("JoyX", 50, "RIGHT", 70, "LEFT", 30),
    AssertEqual(G_CB_LOG.Length, 0, "中值(50)不应触发回调")
))

JoyHkTestRunner.RunTest("E4_CheckAxisState_状态不变不重复触发", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._lastAxisState["JoyX"] := 1,
    JoyHotkeyManager._CheckAxisState("JoyX", 80, "RIGHT", 70, "LEFT", 30),
    AssertEqual(G_CB_LOG.Length, 0, "状态不变(已是高)不应重复触发")
))

JoyHkTestRunner.RunTest("E5_TriggerPovCallback_触发注册方向回调", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._TriggerPovCallback("UP", true),
    AssertEqual(G_CB_LOG.Length, 1, "应触发UP方向回调"),
    AssertEqual(G_CB_LOG[1], "g1", "groupId应为g1")
))

JoyHkTestRunner.RunTest("E6_TriggerPovCallback_isActive为false不触发", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._TriggerPovCallback("UP", false),
    AssertEqual(G_CB_LOG.Length, 0, "isActive=false时不应触发回调")
))

JoyHkTestRunner.RunTest("E7_TriggerJoyCallback_触发轴回调", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._TriggerJoyCallback("JoyX_RIGHT"),
    AssertEqual(G_CB_LOG.Length, 1, "应触发轴回调")
))

JoyHkTestRunner.RunTest("E8_TriggerJoyCallback_未注册key不触发", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._TriggerJoyCallback("JoyX_LEFT"),
    AssertEqual(G_CB_LOG.Length, 0, "未注册的key不应触发回调")
))

; =================================================================
; 场景F: 轮询定时器/连接检测
; =================================================================
FileAppend("--- 场景F: 轮询定时器/连接检测 ---`n", "*")

JoyHkTestRunner.RunTest("F1_StartPolling_StopPolling_状态切换", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager._StartPolling(),
    AssertTrue(JoyHotkeyManager._pollActive, "StartPolling后应激活"),
    AssertTrue(JoyHotkeyManager._pollFn != 0, "StartPolling后pollFn应非0"),
    JoyHotkeyManager._StopPolling(),
    AssertFalse(JoyHotkeyManager._pollActive, "StopPolling后应未激活"),
    AssertEqual(JoyHotkeyManager._pollFn, 0, "StopPolling后pollFn应为0")
))

JoyHkTestRunner.RunTest("F2_Poll_pollActive为false时不执行", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager._pollActive := false,
    JoyHotkeyManager._Poll(),
    AssertEqual(G_CB_LOG.Length, 0, "未激活时_Poll应直接返回不触发回调")
))

JoyHkTestRunner.RunTest("F3_PollConnection_无异常执行", () => (
    JoyHkTestRunner.Reset(),
    AssertNoThrow(() => JoyHotkeyManager._PollConnection(), "_PollConnection不应抛异常")
))

JoyHkTestRunner.RunTest("F4_IsConnected_无手柄返回false", () => (
    JoyHkTestRunner.Reset(),
    AssertFalse(JoyHotkeyManager.IsConnected(), "无手柄环境应返回false")
))

; =================================================================
; 场景G: 回调触发
; =================================================================
FileAppend("--- 场景G: 回调触发 ---`n", "*")

JoyHkTestRunner.RunTest("G1_OnButtonPress_触发注册回调", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager._OnButtonPress("1Joy1"),
    AssertEqual(G_CB_LOG.Length, 1, "应触发1次回调"),
    AssertEqual(G_CB_LOG[1], "g1", "groupId应为g1")
))

JoyHkTestRunner.RunTest("G2_OnButtonPress_多groupId都触发", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid)),
    JoyHotkeyManager.RegisterHotkey("Joy1", "g2", (gid) => _TestCb(gid)),
    JoyHotkeyManager._OnButtonPress("1Joy1"),
    AssertEqual(G_CB_LOG.Length, 2, "两个groupId都应被触发")
))

JoyHkTestRunner.RunTest("G3_OnButtonPress_未注册key不触发", () => (
    JoyHkTestRunner.Reset(),
    JoyHotkeyManager._OnButtonPress("1Joy1"),
    AssertEqual(G_CB_LOG.Length, 0, "未注册key不应触发回调")
))

; =================================================================
; 汇总与退出
; =================================================================
JoyHkTestRunner.Report()
FileAppend("=== Test End ===`n", "*")
ExitApp(JoyHkTestRunner.failed > 0 ? 1 : 0)
