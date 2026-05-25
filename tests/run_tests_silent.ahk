; =================================================================
; AutoHotUnit 测试运行器 - 无弹窗版本
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "AutoHotUnit.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"

class SilentReporter {
    failures := []
    passed := 0
    total := 0
    outputFile := ""
    
    __New(filePath) {
        this.outputFile := filePath
        if FileExist(filePath)
            FileDelete(filePath)
    }
    
    write(str) {
        FileAppend(str, this.outputFile, "UTF-8")
    }
    
    writeLine(str) {
        this.write(str . "`r`n")
    }
    
    onRunStart() {
        this.writeLine("========================================")
        this.writeLine("AutoHotUnit 测试报告")
        this.writeLine("时间: " A_Now)
        this.writeLine("========================================")
        this.writeLine("")
    }
    
    onSuiteStart(suiteName) {
        this.writeLine("【测试套件】" suiteName)
    }
    
    onTestResult(testName, status, where, error) {
        this.total++
        if (status == "passed") {
            this.passed++
            this.writeLine("  ✓ " testName)
        } else {
            this.writeLine("  ✗ " testName " - 失败")
            this.writeLine("      位置: " where)
            this.writeLine("      错误: " error.Message)
            this.failures.push({suite: "", test: testName, error: error.Message})
        }
    }
    
    onSuiteEnd(suiteName) {
        this.writeLine("")
    }
    
    onRunComplete() {
        this.writeLine("========================================")
        this.writeLine("测试结果汇总")
        this.writeLine("========================================")
        this.writeLine("总计: " this.total " 个测试")
        this.writeLine("通过: " this.passed " 个")
        this.writeLine("失败: " this.failures.Length " 个")
        
        if (this.failures.Length > 0) {
            this.writeLine("")
            this.writeLine("失败的测试:")
            for i, f in this.failures {
                this.writeLine("  - " f.test ": " f.error)
            }
        }
        
        this.writeLine("")
        if (this.failures.Length = 0) {
            this.writeLine("✓ 所有测试通过!")
        } else {
            this.writeLine("✗ 存在失败的测试")
        }
    }
}

class InterfaceContractTests extends AutoHotUnitSuite {
    Test_ILogger_Log_Throws() {
        try {
            ILogger().Log("INFO", "test")
            this.assert.fail("ILogger.Log 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
    
    Test_INotifier_Notify_Throws() {
        try {
            INotifier().Notify("test")
            this.assert.fail("INotifier.Notify 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
    
    Test_IConfigStore_Load_Throws() {
        try {
            IConfigStore().Load()
            this.assert.fail("IConfigStore.Load 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
    
    Test_IExecutor_Execute_Throws() {
        try {
            IExecutor().Execute("")
            this.assert.fail("IExecutor.Execute 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
}

class ModeRegistryTests extends AutoHotUnitSuite {
    Test_PeriodicMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("periodic"))
    }
    
    Test_SequenceMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("sequence"))
    }
    
    Test_HybridMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("hybrid"))
    }
    
    Test_EnhancedPeriodicMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("enhanced_periodic"))
    }
    
    Test_EnhancedSequenceMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("enhanced_sequence"))
    }
    
    Test_EnhancedHybridMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("enhanced_hybrid"))
    }
    
    Test_HoldMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("hold"))
    }
    
    Test_GetRegisteredModes_ReturnsAtLeast7() {
        modes := ModeRegistry.GetRegisteredModes()
        this.assert.isAtLeast(modes.Length, 7)
    }
    
    Test_GetModeDisplayNames_ReturnsMap() {
        displayNames := ModeRegistry.GetModeDisplayNames()
        this.assert.isTrue(displayNames is Map)
    }
}

class ModeRegistryExecutorTests extends AutoHotUnitSuite {
    Test_PeriodicExecutor_Valid() {
        exec := ModeRegistry.GetExecutor("periodic")
        this.assert.isTrue(exec is IExecutor)
        this.assert.equal(exec.GetModeName(), "periodic")
    }
    
    Test_SequenceExecutor_Valid() {
        exec := ModeRegistry.GetExecutor("sequence")
        this.assert.isTrue(exec is IExecutor)
        this.assert.equal(exec.GetModeName(), "sequence")
    }
    
    Test_HybridExecutor_Valid() {
        exec := ModeRegistry.GetExecutor("hybrid")
        this.assert.isTrue(exec is IExecutor)
        this.assert.equal(exec.GetModeName(), "hybrid")
    }
    
    Test_NonExistentMode_ReturnsEmpty() {
        exec := ModeRegistry.GetExecutor("not_a_real_mode_xyz")
        this.assert.equal(exec, "")
    }
}

class SkillGroupTests extends AutoHotUnitSuite {
    Test_KeyPressDuration_MinValueCorrection() {
        sg := SkillGroup("test1", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 1})
        this.assert.equal(sg.keyPressDuration, 5)
    }
    
    Test_KeyPressDuration_NormalValuePreserved() {
        sg := SkillGroup("test2", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 80})
        this.assert.equal(sg.keyPressDuration, 80)
    }
}

class MathTests extends AutoHotUnitSuite {
    Test_Addition() {
        this.assert.equal(2 + 2, 4)
    }
    
    Test_Subtraction() {
        this.assert.equal(10 - 3, 7)
    }
    
    Test_Multiplication() {
        this.assert.equal(6 * 7, 42)
    }
}

class StringTests extends AutoHotUnitSuite {
    Test_Trim() {
        this.assert.equal(Trim("  hello  "), "hello")
    }
    
    Test_InStr() {
        this.assert.equal(InStr("hello world", "world"), 7)
    }
}

; 创建静默报告器
reporter := SilentReporter(A_ScriptDir "\test_results.log")

; 创建测试管理器
testManager := AutoHotUnitManager(reporter)

; 初始化 ModeRegistry（注册所有内置模式）
ModeRegistry._Init()

; 注册所有测试套件
testManager.RegisterSuite(InterfaceContractTests, ModeRegistryTests, ModeRegistryExecutorTests, SkillGroupTests, MathTests, StringTests)

; 运行测试
testManager.RunSuites()

; 退出程序
ExitApp(0)
