; =================================================================
; test_hotkey_hook.ahk - 测试 AHK 执行器热键钩子
; 目标：验证 hotkey_hook.ahk 中 HotkeyHook 的规范化与注册逻辑
; 注意：真实热键注册依赖系统状态，仅测试无副作用的纯函数与错误处理
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; 被测脚本
#Include "../../asd-tauri/src-tauri/ahk_executor/hotkey_hook.ahk"

; 测试框架（提供 AutoHotUnitSuite 基类）
#Include "../AutoHotUnit.ahk"

; 警告设置（在 #Include 之后，覆盖 AutoHotUnit.ahk 的 #Warn All）
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 运行时错误接管
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试套件：HotkeyHook._NormalizeHotkey 修饰符规范化
; =================================================================

class HotkeyHookNormalizeTests extends AutoHotUnitSuite {
    Test_Normalize_SingleKey_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("F1"), "F1")
    }

    Test_Normalize_LetterKey_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("a"), "a")
    }

    Test_Normalize_NumberKey_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("1"), "1")
    }

    Test_Normalize_CtrlOnly_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("^1"), "^1")
    }

    Test_Normalize_ShiftOnly_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("+a"), "+a")
    }

    Test_Normalize_AltOnly_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("!F2"), "!F2")
    }

    Test_Normalize_WinOnly_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("#a"), "#a")
    }

    Test_Normalize_CtrlShift_PreservedOrder() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("^+a"), "^+a")
    }

    Test_Normalize_ShiftCtrl_ReorderedToCtrlShift() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("+^a"), "^+a")
    }

    Test_Normalize_AltCtrl_ReorderedToCtrlAlt() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("!^a"), "^!a")
    }

    Test_Normalize_AllFour_ReorderedToStandard() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("+^!#a"), "^!+#a")
    }

    Test_Normalize_AllFour_DifferentInput_SameOutput() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("#a"), "#a")
        this.assert.equal(HotkeyHook._NormalizeHotkey("#^a"), "^#a")
        this.assert.equal(HotkeyHook._NormalizeHotkey("^#!+a"), "^!+#a")
    }

    Test_Normalize_EmptyString_ReturnsEmpty() {
        this.assert.equal(HotkeyHook._NormalizeHotkey(""), "")
    }

    Test_Normalize_NoModifier_Preserved() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("Space"), "Space")
        this.assert.equal(HotkeyHook._NormalizeHotkey("Enter"), "Enter")
    }

    Test_Normalize_CtrlAltShift_StandardOrder() {
        this.assert.equal(HotkeyHook._NormalizeHotkey("^!+F1"), "^!+F1")
    }

    Test_Normalize_Idempotent() {
        once := HotkeyHook._NormalizeHotkey("+^!#F1")
        twice := HotkeyHook._NormalizeHotkey(once)
        this.assert.equal(once, twice)
    }
}

; =================================================================
; 测试套件：HotkeyHook 注册状态查询
; =================================================================

class HotkeyHookRegistrationStateTests extends AutoHotUnitSuite {
    afterAll() {
        HotkeyHook.UnregisterAll()
    }

    Test_IsRegistered_UnregisteredKey_ReturnsFalse() {
        HotkeyHook.UnregisterAll()
        this.assert.isFalse(HotkeyHook.IsRegistered("F13_xyz_unique"))
    }

    Test_GetCount_AfterClear_IsZero() {
        HotkeyHook.UnregisterAll()
        this.assert.equal(HotkeyHook.GetCount(), 0)
    }
}

; =================================================================
; 测试套件：HotkeyHook.Register 错误处理
; =================================================================

class HotkeyHookRegisterErrorTests extends AutoHotUnitSuite {
    afterAll() {
        HotkeyHook.UnregisterAll()
    }

    Test_Register_EmptyString_ReturnsFalse() {
        result := HotkeyHook.Register("", "g1")
        this.assert.isFalse(result)
    }

    Test_Register_EmptyString_DoesNotAddToMap() {
        HotkeyHook.UnregisterAll()
        HotkeyHook.Register("", "g1")
        this.assert.equal(HotkeyHook.GetCount(), 0)
    }
}

; =================================================================
; 测试套件：HotkeyHook.Unregister 错误处理
; =================================================================

class HotkeyHookUnregisterErrorTests extends AutoHotUnitSuite {
    afterAll() {
        HotkeyHook.UnregisterAll()
    }

    Test_Unregister_UnregisteredKey_ReturnsTrue() {
        HotkeyHook.UnregisterAll()
        result := HotkeyHook.Unregister("F99_unique_unregistered")
        this.assert.isTrue(result)
    }

    Test_Unregister_DoesNotThrow() {
        try {
            HotkeyHook.Unregister("F98_unique_unregistered")
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("Unregister 不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：HotkeyHook.UnregisterAll 清理
; =================================================================

class HotkeyHookUnregisterAllTests extends AutoHotUnitSuite {
    Test_UnregisterAll_DoesNotThrow() {
        try {
            HotkeyHook.UnregisterAll()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("UnregisterAll 不应抛出异常: " e.Message)
        }
    }

    Test_UnregisterAll_ClearsCount() {
        HotkeyHook.UnregisterAll()
        this.assert.equal(HotkeyHook.GetCount(), 0)
    }

    Test_UnregisterAll_MultipleCallsSafe() {
        HotkeyHook.UnregisterAll()
        HotkeyHook.UnregisterAll()
        HotkeyHook.UnregisterAll()
        this.assert.equal(HotkeyHook.GetCount(), 0)
    }
}

; =================================================================
; 测试套件：HotkeyHook.Init 初始化
; =================================================================

class HotkeyHookInitTests extends AutoHotUnitSuite {
    Test_Init_DoesNotThrow() {
        try {
            HotkeyHook.Init()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("Init 不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：HotkeyHook.OnKeyRecorded 回调
; =================================================================

class HotkeyHookCallbackTests extends AutoHotUnitSuite {
    afterAll() {
        HotkeyHook.OnKeyRecorded := ""
    }

    Test_OnKeyRecorded_InitialEmpty() {
        HotkeyHook.OnKeyRecorded := ""
        this.assert.equal(HotkeyHook.OnKeyRecorded, "")
    }

    Test_OnKeyRecorded_CanBeSet() {
        callbackCalled := false
        HotkeyHook.OnKeyRecorded := (key) => (callbackCalled := true)
        this.assert.isTrue(HotkeyHook.OnKeyRecorded != "")
        HotkeyHook.OnKeyRecorded := ""
    }
}
