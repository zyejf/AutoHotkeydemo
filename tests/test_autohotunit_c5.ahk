; =================================================================
; test_autohotunit_c5.ahk - C5 合规违规修复验证测试
; 说明: 验证 AutoHotUnit.ahk 测试框架包含 AGENTS.md 强制要求的
;       错误接管指令（#Requires / #ErrorStdOut / #Warn / OnError）
; 运行: AutoHotkey.exe tests\test_autohotunit_c5.ahk
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "AutoHotUnit.ahk"

; 运行时错误接管回调：输出到 stdout 并阻止弹窗（表达式体，非块体）
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; 读取 AutoHotUnit.ahk 源码供所有测试共享（super-global，方法内可直接访问）
global AHU_SOURCE := FileRead(A_ScriptDir "\AutoHotUnit.ahk", "UTF-8")

; ============================================================
; C5 合规性测试套件 - 验证 AutoHotUnit.ahk 接管指令完整性
; ============================================================

class AutoHotUnitC5ComplianceTests extends AutoHotUnitSuite {
    Test_AutoHotUnit_HasRequires() {
        ; 验证源码包含 #Requires AutoHotkey v2.0
        this.assert.isTrue(InStr(AHU_SOURCE, "#Requires AutoHotkey v2.0") > 0)
    }

    Test_AutoHotUnit_HasErrorStdOut() {
        ; 验证源码包含 #ErrorStdOut（加载时错误重定向到 stderr）
        this.assert.isTrue(InStr(AHU_SOURCE, "#ErrorStdOut") > 0)
    }

    Test_AutoHotUnit_HasWarnVarUnset() {
        ; 验证源码包含 #Warn VarUnset, OutputDebug
        this.assert.isTrue(InStr(AHU_SOURCE, "#Warn VarUnset, OutputDebug") > 0)
    }

    Test_AutoHotUnit_HasWarnUnreachable() {
        ; 验证源码包含 #Warn Unreachable, OutputDebug
        this.assert.isTrue(InStr(AHU_SOURCE, "#Warn Unreachable, OutputDebug") > 0)
    }

    Test_AutoHotUnit_HasWarnLocalSameAsGlobal() {
        ; 验证源码包含 #Warn LocalSameAsGlobal, Off
        this.assert.isTrue(InStr(AHU_SOURCE, "#Warn LocalSameAsGlobal, Off") > 0)
    }

    Test_AutoHotUnit_HasOnError() {
        ; 验证源码包含 OnError 回调（运行时错误接管）
        this.assert.isTrue(InStr(AHU_SOURCE, "OnError") > 0)
    }

    Test_AutoHotUnit_NoWarnAllStdOut() {
        ; 验证源码不包含 #Warn All, StdOut（应已移除，与标准要求冲突）
        this.assert.isTrue(InStr(AHU_SOURCE, "#Warn All, StdOut") == 0)
    }
}

; 注册并运行测试套件（使用 AutoHotUnit.ahk 创建的全局 ahu 管理器）
ahu.RegisterSuite(AutoHotUnitC5ComplianceTests)
ahu.RunSuites()
