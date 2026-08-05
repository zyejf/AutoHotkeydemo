; =================================================================
; joy_hotkey_manager 测试（AutoHotUnitSuite 风格）
; =================================================================
; 覆盖 infrastructure/joy_hotkey_manager.ahk 的关键功能路径：
;   1. 热键注册/注销（按钮 Joy1~Joy32、轴、POV、扳机）
;   2. 轴/POV 轮询逻辑（值变化检测、回调触发）
;   3. 热插拔检测（连接轮询、IsConnected）
;   4. 多手柄支持（joystickId 切换影响注册 key）
;   5. 错误处理（无效 key、未注册注销、不存在 groupId）
; 测试策略：不依赖真实硬件，直接测试状态管理逻辑与纯逻辑内部方法
; 本文件设计为被 run_all_tests.ahk #Include，不包含 OnError 回调
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 被测模块（run_all_tests.ahk 未引入，需在此引入）
#Include "../infrastructure/joy_hotkey_manager.ahk"

; =================================================================
; 全局回调记录器
; 说明: 用全局数组记录回调触发，避免箭头函数闭包捕获局部变量的问题
; 使用 global 关键字声明为超级全局变量，所有函数/方法内自动可见
; =================================================================
global G_CB_LOG := []

_TestCb(gid) {
    global G_CB_LOG
    G_CB_LOG.Push(gid)
}

; =================================================================
; 状态重置辅助函数
; 重置 JoyHotkeyManager 静态状态，确保测试隔离
; 注意: 不重置 _connPollActive，避免重复启动 30s 连接轮询定时器
; =================================================================
_ResetJoyHotkeyState() {
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

; =================================================================
; 场景A+B: 热键注册测试（按钮/POV/轴/扳机/无效key + 重复注册/多groupId）
; =================================================================
class JoyHotkeyRegisterTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    ; 场景A: 热键注册

    Test_RegisterJoy1_ButtonReturnsTrue() {
        result := JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        this.assert.isTrue(result)
        this.assert.isTrue(JoyHotkeyManager._registered.Has("1Joy1"))
        this.assert.isTrue(JoyHotkeyManager._registered["1Joy1"] is Array)
    }

    Test_RegisterJoyPOV_UP_PovReturnsTrue() {
        result := JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid))
        this.assert.isTrue(result)
        this.assert.isTrue(JoyHotkeyManager._registered.Has("JoyPOV_UP"))
    }

    Test_RegisterJoyX_RIGHT_AxisReturnsTrue() {
        result := JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        this.assert.isTrue(result)
        this.assert.isTrue(JoyHotkeyManager._registered.Has("JoyX_RIGHT"))
    }

    Test_RegisterJoyZ_DOWN_TriggerReturnsTrue() {
        result := JoyHotkeyManager.RegisterHotkey("JoyZ_DOWN", "g1", (gid) => _TestCb(gid))
        this.assert.isTrue(result)
        this.assert.isTrue(JoyHotkeyManager._registered.Has("JoyZ_DOWN"))
    }

    Test_RegisterInvalidKey_ReturnsFalse() {
        result := JoyHotkeyManager.RegisterHotkey("InvalidKey", "g1", (gid) => _TestCb(gid))
        this.assert.isFalse(result)
    }

    ; 场景B: 重复注册/多groupId

    Test_DuplicateRegister_SameGroupId_NoDuplicate() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        result := JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        this.assert.isTrue(result)
        this.assert.equal(JoyHotkeyManager._registered["1Joy1"].Length, 1)
    }

    Test_DifferentGroupId_SameButton_Coexist() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager.RegisterHotkey("Joy1", "g2", (gid) => _TestCb(gid))
        this.assert.equal(JoyHotkeyManager._registered["1Joy1"].Length, 2)
    }
}

; =================================================================
; 场景C: 注销测试
; =================================================================
class JoyHotkeyUnregisterTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    Test_UnregisterButton_ClearsRegistry() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager.UnregisterHotkey("Joy1", "g1")
        this.assert.isFalse(JoyHotkeyManager._registered.Has("1Joy1"))
    }

    Test_UnregisterAxis_ClearsRegistry() {
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager.UnregisterHotkey("JoyX_RIGHT", "g1")
        this.assert.isFalse(JoyHotkeyManager._registered.Has("JoyX_RIGHT"))
    }

    Test_UnregisterUnregisteredKey_NoThrow() {
        try {
            JoyHotkeyManager.UnregisterHotkey("Joy1", "g1")
        } catch as e {
            this.assert.fail("注销未注册key不应抛异常: " e.Message)
        }
    }

    Test_UnregisterAll_ClearsSpecifiedGroupId() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g2", (gid) => _TestCb(gid))
        JoyHotkeyManager.UnregisterAll("g1")
        this.assert.isFalse(JoyHotkeyManager._registered.Has("1Joy1"))
        this.assert.isFalse(JoyHotkeyManager._registered.Has("JoyPOV_UP"))
        this.assert.isTrue(JoyHotkeyManager._registered.Has("JoyX_RIGHT"))
    }

    Test_UnregisterAll_NonExistentGroupId_NoThrow() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        try {
            JoyHotkeyManager.UnregisterAll("g999")
        } catch as e {
            this.assert.fail("注销不存在groupId不应抛异常: " e.Message)
        }
        this.assert.isTrue(JoyHotkeyManager._registered.Has("1Joy1"))
    }
}

; =================================================================
; 场景D: 多手柄支持
; =================================================================
class JoyHotkeyMultiJoystickTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    Test_Init_SetsJoystickId() {
        JoyHotkeyManager.Init(3)
        this.assert.equal(JoyHotkeyManager._joystickId, 3)
    }

    Test_Init_MultiJoystickId_AffectsRegisterKey() {
        JoyHotkeyManager.Init(2)
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        this.assert.isTrue(JoyHotkeyManager._registered.Has("2Joy1"))
        this.assert.isFalse(JoyHotkeyManager._registered.Has("1Joy1"))
    }
}

; =================================================================
; 场景E: 轴/POV 轮询逻辑（直接调用纯逻辑内部方法）
; =================================================================
class JoyHotkeyPollingLogicTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    Test_CheckAxisState_HighValue_TriggersRightCallback() {
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._lastAxisState["JoyX"] := 0
        JoyHotkeyManager._CheckAxisState("JoyX", 80, "RIGHT", 70, "LEFT", 30)
        this.assert.equal(G_CB_LOG.Length, 1)
        this.assert.equal(G_CB_LOG[1], "g1")
    }

    Test_CheckAxisState_LowValue_TriggersLeftCallback() {
        JoyHotkeyManager.RegisterHotkey("JoyX_LEFT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._lastAxisState["JoyX"] := 0
        JoyHotkeyManager._CheckAxisState("JoyX", 20, "RIGHT", 70, "LEFT", 30)
        this.assert.equal(G_CB_LOG.Length, 1)
    }

    Test_CheckAxisState_MiddleValue_NoCallback() {
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._lastAxisState["JoyX"] := 0
        JoyHotkeyManager._CheckAxisState("JoyX", 50, "RIGHT", 70, "LEFT", 30)
        this.assert.equal(G_CB_LOG.Length, 0)
    }

    Test_CheckAxisState_StateUnchanged_NoRepeat() {
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._lastAxisState["JoyX"] := 1
        JoyHotkeyManager._CheckAxisState("JoyX", 80, "RIGHT", 70, "LEFT", 30)
        this.assert.equal(G_CB_LOG.Length, 0)
    }

    Test_TriggerPovCallback_RegisteredDirection_Triggers() {
        JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._TriggerPovCallback("UP", true)
        this.assert.equal(G_CB_LOG.Length, 1)
        this.assert.equal(G_CB_LOG[1], "g1")
    }

    Test_TriggerPovCallback_Inactive_NoTrigger() {
        JoyHotkeyManager.RegisterHotkey("JoyPOV_UP", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._TriggerPovCallback("UP", false)
        this.assert.equal(G_CB_LOG.Length, 0)
    }

    Test_TriggerJoyCallback_RegisteredAxis_Triggers() {
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._TriggerJoyCallback("JoyX_RIGHT")
        this.assert.equal(G_CB_LOG.Length, 1)
    }

    Test_TriggerJoyCallback_UnregisteredKey_NoTrigger() {
        JoyHotkeyManager.RegisterHotkey("JoyX_RIGHT", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._TriggerJoyCallback("JoyX_LEFT")
        this.assert.equal(G_CB_LOG.Length, 0)
    }
}

; =================================================================
; 场景F: 轮询定时器/连接检测
; =================================================================
class JoyHotkeyPollingTimerTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    Test_StartPolling_StopPolling_StateToggle() {
        JoyHotkeyManager._StartPolling()
        this.assert.isTrue(JoyHotkeyManager._pollActive)
        this.assert.isTrue(JoyHotkeyManager._pollFn != 0)
        JoyHotkeyManager._StopPolling()
        this.assert.isFalse(JoyHotkeyManager._pollActive)
        this.assert.equal(JoyHotkeyManager._pollFn, 0)
    }

    Test_Poll_PollActiveFalse_NoExecution() {
        JoyHotkeyManager._pollActive := false
        JoyHotkeyManager._Poll()
        this.assert.equal(G_CB_LOG.Length, 0)
    }

    Test_PollConnection_NoThrow() {
        try {
            JoyHotkeyManager._PollConnection()
        } catch as e {
            this.assert.fail("_PollConnection不应抛异常: " e.Message)
        }
    }

    Test_IsConnected_NoJoystick_ReturnsFalse() {
        this.assert.isFalse(JoyHotkeyManager.IsConnected())
    }
}

; =================================================================
; 场景G: 回调触发
; =================================================================
class JoyHotkeyCallbackTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    Test_OnButtonPress_RegisteredCallback_Triggers() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager._OnButtonPress("1Joy1")
        this.assert.equal(G_CB_LOG.Length, 1)
        this.assert.equal(G_CB_LOG[1], "g1")
    }

    Test_OnButtonPress_MultipleGroupIds_AllTrigger() {
        JoyHotkeyManager.RegisterHotkey("Joy1", "g1", (gid) => _TestCb(gid))
        JoyHotkeyManager.RegisterHotkey("Joy1", "g2", (gid) => _TestCb(gid))
        JoyHotkeyManager._OnButtonPress("1Joy1")
        this.assert.equal(G_CB_LOG.Length, 2)
    }

    Test_OnButtonPress_UnregisteredKey_NoTrigger() {
        JoyHotkeyManager._OnButtonPress("1Joy1")
        this.assert.equal(G_CB_LOG.Length, 0)
    }
}

; =================================================================
; 场景H: 代码审查修复测试（I3/I4/I8/I10）
; =================================================================
class JoyHotkeyReviewFixTests extends AutoHotUnitSuite {
    beforeEach() {
        _ResetJoyHotkeyState()
    }

    ; Minor-3 脆弱性说明：以下 Test_Source_* 测试通过 FileRead + InStr 搜索源码
    ; 文本验证代码约束（#Include 存在性、日志级别、方法调用等）。这些测试对
    ; 源码格式改动敏感，属于已知脆弱性。它们检查的是"代码模式存在/不存在"，
    ; 难以通过行为测试完全替代。修改被检源码时应同步检查这些测试。

    ; I4: 日志级别不应使用 INFO，应为 DEBUG（AGENTS.md 规定：ERROR/WARNING/DEBUG）
    Test_Source_NoInfoLogLevel() {
        src := FileRead(A_ScriptDir "\..\infrastructure\joy_hotkey_manager.ahk", "UTF-8")
        ; InStr 返回 0 表示未找到，正整数表示找到位置
        this.assert.equal(InStr(src, '"INFO"'), 0)
    }

    ; I8: 注销未注册的非按钮 key 不应写错误日志
    ; 修复前：else 分支直接 Delete 不存在的 key → 抛异常 → catch 调用 LogError → _writeCount 增加
    ; 修复后：Has 检查失败 → 跳过 Delete → 不抛异常 → _writeCount 不变
    Test_UnregisterAxis_NotRegistered_NoErrorLog() {
        ErrorSystem.Init()
        beforeCount := ErrorSystem._writeCount
        ; JoyX_RIGHT 未注册，走 else 分支（非按钮类型）
        JoyHotkeyManager.UnregisterHotkey("JoyX_RIGHT", "g1")
        afterCount := ErrorSystem._writeCount
        this.assert.equal(afterCount, beforeCount)
    }

    ; I10: 连接轮询定时器引用必须存储且可停止
    ; 修复前：SetTimer 未存储引用，无法停止（_connPollTimer 不存在）
    ; 修复后：存储到 _connPollTimer，_StopConnectionPoll 可停止并清除
    Test_ConnPollTimer_StoredAndStoppable() {
        ; 重置连接轮询状态（_ResetJoyHotkeyState 不重置 _connPollActive）
        JoyHotkeyManager._connPollActive := false
        if JoyHotkeyManager.HasProp("_connPollTimer") && JoyHotkeyManager._connPollTimer {
            try SetTimer(JoyHotkeyManager._connPollTimer, 0)
        }
        ; 启动连接轮询
        JoyHotkeyManager._StartConnectionPoll()
        ; 验证定时器引用已存储（是 Func 对象）
        this.assert.isTrue(JoyHotkeyManager._connPollTimer is Func)
        ; 停止连接轮询
        JoyHotkeyManager._StopConnectionPoll()
        ; 验证定时器引用已清除
        this.assert.equal(JoyHotkeyManager._connPollTimer, 0)
    }

    ; A1: 消除代码重复 — 删除 infrastructure/joystick_input_utils.ahk，
    ; 改为直接引用 domain/joystick_input.ahk 的 JoystickInput 类。
    ; 决策依据：AGENTS.md 妥协 #1 已允许领域层纯工具函数被基础设施层引用；
    ; joystick_input.ahk 是无副作用、无状态的纯工具函数，代码重复比反向依赖更优。
    ; 此测试集反转了 I3 的决策（I3 为避免反向依赖创建了重复代码，A1 认为重复更糟）。

    ; RED 测试1: joy_hotkey_manager.ahk 应包含 domain/joystick_input.ahk 的 #Include
    Test_Source_UsesDomainJoystickInputInclude() {
        src := FileRead(A_ScriptDir "\..\infrastructure\joy_hotkey_manager.ahk", "UTF-8")
        this.assert.isTrue(InStr(src, '#Include "../domain/joystick_input.ahk"') > 0)
    }

    ; RED 测试2: joy_hotkey_manager.ahk 不应再包含 joystick_input_utils.ahk 的 #Include
    Test_Source_NoJoystickInputUtilsInclude() {
        src := FileRead(A_ScriptDir "\..\infrastructure\joy_hotkey_manager.ahk", "UTF-8")
        this.assert.equal(InStr(src, '#Include "joystick_input_utils.ahk"'), 0)
    }

    ; RED 测试3: joy_hotkey_manager.ahk 不应再调用 JoystickInputUtils 类
    Test_Source_NoJoystickInputUtilsCalls() {
        src := FileRead(A_ScriptDir "\..\infrastructure\joy_hotkey_manager.ahk", "UTF-8")
        this.assert.equal(InStr(src, 'JoystickInputUtils.'), 0)
    }

    ; RED 测试4: infrastructure/joystick_input_utils.ahk 冗余文件应被删除
    Test_JoystickInputUtils_FileDeleted() {
        utilPath := A_ScriptDir "\..\infrastructure\joystick_input_utils.ahk"
        this.assert.equal(FileExist(utilPath), "")
    }

    ; RED 测试5: JoystickInputUtils 类应不再被定义（冗余文件删除后无人引入）
    Test_JoystickInputUtils_ClassRemoved() {
        utilDefined := false
        try {
            if IsObject(JoystickInputUtils)
                utilDefined := true
        } catch {
            utilDefined := false
        }
        this.assert.isFalse(utilDefined)
    }

    ; 回归保护: JoystickInput 纯工具方法可用（确保删除 utils 后功能不丢失）
    Test_JoystickInput_MethodsAvailable() {
        this.assert.isTrue(JoystickInput.IsButton("Joy1"))
        this.assert.isTrue(JoystickInput.IsPov("JoyPOV_UP"))
        this.assert.isTrue(JoystickInput.IsAxis("JoyX_RIGHT"))
        this.assert.isTrue(JoystickInput.IsTrigger("JoyZ_DOWN"))
    }

    ; A2: _StopConnectionPoll 方法集成到生命周期
    ; 问题：_StopConnectionPoll 已定义但从未在生产代码中调用，
    ;       连接轮询定时器无法在退出时停止，存在资源泄漏
    ; 修复：新增 Shutdown() 公共方法调用 _StopConnectionPoll()，
    ;       在 main.ahk 的 OnExit 回调中调用 JoyHotkeyManager.Shutdown()

    ; RED 测试1: JoyHotkeyManager 应有 Shutdown 公共方法
    Test_Shutdown_Exists() {
        this.assert.isTrue(HasProp(JoyHotkeyManager, "Shutdown"))
    }

    ; RED 测试2: Shutdown() 应停止连接轮询定时器（_connPollTimer 置 0）
    Test_Shutdown_StopsConnectionPoll() {
        ; 重置连接轮询状态（_ResetJoyHotkeyState 不重置 _connPollActive）
        JoyHotkeyManager._connPollActive := false
        if JoyHotkeyManager.HasProp("_connPollTimer") && JoyHotkeyManager._connPollTimer {
            try SetTimer(JoyHotkeyManager._connPollTimer, 0)
        }
        ; 启动连接轮询
        JoyHotkeyManager._StartConnectionPoll()
        this.assert.isTrue(JoyHotkeyManager._connPollTimer is Func)
        ; 调用 Shutdown 应停止连接轮询
        JoyHotkeyManager.Shutdown()
        this.assert.equal(JoyHotkeyManager._connPollTimer, 0)
    }

    ; RED 测试3: main.ahk 退出路径应调用 JoyHotkeyManager.Shutdown()
    Test_Source_MainCallsShutdownOnExit() {
        src := FileRead(A_ScriptDir "\..\main.ahk", "UTF-8")
        this.assert.isTrue(InStr(src, 'JoyHotkeyManager.Shutdown()') > 0)
    }
}
