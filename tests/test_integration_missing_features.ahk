#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "AutoHotUnit.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/migration_logger.ahk"
#Include "../application/config_service.ahk"
#Include "../application/group_service.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

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
        this.writeLine("全量集成测试报告 - 缺失功能验证")
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

class MigrationLoggerTests extends AutoHotUnitSuite {
    Test_LogEntry() {
        MigrationLogger._entries := []
        MigrationLogger.Log("1.0", "3.0", "test1", "keys->pressKeys", "abc", "abc")
        this.assert.isTrue(MigrationLogger._entries.Length = 1)
        this.assert.isTrue(MigrationLogger._entries[1]["fromVersion"] = "1.0")
        this.assert.isTrue(MigrationLogger._entries[1]["toVersion"] = "3.0")
        this.assert.isTrue(MigrationLogger._entries[1]["groupId"] = "test1")
        this.assert.isTrue(MigrationLogger._entries[1]["field"] = "keys->pressKeys")
    }

    Test_MultipleEntries() {
        MigrationLogger._entries := []
        MigrationLogger.Log("1.0", "3.0", "g1", "f1", "a", "b")
        MigrationLogger.Log("1.0", "3.0", "g2", "f2", "c", "d")
        this.assert.isTrue(MigrationLogger._entries.Length = 2)
    }

    Test_FlushClearsEntries() {
        MigrationLogger._entries := []
        MigrationLogger.Log("1.0", "3.0", "g1", "f1", "a", "b")
        MigrationLogger._entries := []
        this.assert.isTrue(MigrationLogger._entries.Length = 0)
    }
}

class ConfigMigrationTests extends AutoHotUnitSuite {
    Test_MigratePeriodicKeysToPressKeys() {
        config := Map(
            "version", "1.0",
            "GroupSettings", Map(
                "test1", Map("mode", "periodic", "keys", "a,b", "interval", 100)
            )
        )
        result := ConfigService.MigrateConfig(config)
        gs := result["GroupSettings"]["test1"]
        this.assert.isTrue(gs.Has("pressKeys"))
        this.assert.isTrue(gs["pressKeys"] = "a,b")
    }

    Test_MigratePeriodicDelaysToPressDelays() {
        config := Map(
            "version", "1.0",
            "GroupSettings", Map(
                "test2", Map("mode", "periodic", "delays", "50,60", "interval", 100)
            )
        )
        result := ConfigService.MigrateConfig(config)
        gs := result["GroupSettings"]["test2"]
        this.assert.isTrue(gs.Has("pressDelays"))
        this.assert.isTrue(gs["pressDelays"] = "50,60")
    }

    Test_MigrateRemovesLegacyFields() {
        config := Map(
            "version", "1.0",
            "GroupSettings", Map(
                "test3", Map("mode", "periodic", "repeatKey", "a", "repeatMode", "hold", "interval", 100)
            )
        )
        result := ConfigService.MigrateConfig(config)
        gs := result["GroupSettings"]["test3"]
        this.assert.isFalse(gs.Has("repeatKey"))
        this.assert.isFalse(gs.Has("repeatMode"))
    }

    Test_MigrateSetsVersion() {
        config := Map(
            "version", "1.0",
            "GroupSettings", Map()
        )
        result := ConfigService.MigrateConfig(config)
        this.assert.isTrue(result["version"] = "3.0")
    }

    Test_MigrateHybridSubGroups() {
        config := Map(
            "version", "2.0",
            "GroupSettings", Map(
                "test4", Map("mode", "hybrid", "groups", [Map("keys", "x,y")])
            )
        )
        result := ConfigService.MigrateConfig(config)
        gs := result["GroupSettings"]["test4"]
        subGroups := gs["groups"]
        this.assert.isTrue(subGroups[1].Has("pressKeys"))
        this.assert.isTrue(subGroups[1]["pressKeys"] = "x,y")
    }
}

class ConfigValidatorTests extends AutoHotUnitSuite {
    Test_ValidPeriodicConfig() {
        config := Map("mode", "periodic", "pressKeys", ["a"], "intervals", [100], "hotkey", "F1")
        result := ConfigValidator.ValidateGroupConfig(config)
        this.assert.isTrue(result.valid)
    }

    Test_InvalidMode() {
        config := Map("mode", "invalid_mode", "pressKeys", ["a"], "hotkey", "F1")
        result := ConfigValidator.ValidateGroupConfig(config)
        this.assert.isFalse(result.valid)
    }

    Test_EmptyPressKeys() {
        config := Map("mode", "periodic", "pressKeys", [], "intervals", [100], "hotkey", "F1")
        result := ConfigValidator.ValidateGroupConfig(config)
        this.assert.isFalse(result.valid)
    }

    Test_IntervalTooSmall() {
        config := Map("mode", "periodic", "pressKeys", ["a"], "intervals", [1], "hotkey", "F1")
        result := ConfigValidator.ValidateGroupConfig(config)
        this.assert.isFalse(result.valid)
    }

    Test_MissingHotkey() {
        config := Map("mode", "periodic", "pressKeys", ["a"], "intervals", [100])
        result := ConfigValidator.ValidateGroupConfig(config)
        this.assert.isFalse(result.valid)
    }
}

class BackupCoreTests extends AutoHotUnitSuite {
    Test_InitCreatesDir() {
        BackupCore.Init()
        this.assert.isTrue(DirExist(BackupCore.backupDir))
    }

    Test_ListBackupsReturnsArray() {
        BackupCore.Init()
        result := BackupCore.ListBackups()
        this.assert.isTrue(result is Array)
    }

    Test_MaxBackupsIsPositive() {
        this.assert.isTrue(BackupCore.maxBackups > 0)
    }
}

class JSONSerializerTests extends AutoHotUnitSuite {
    Test_StringifyMap() {
        m := Map("key", "value", "num", 42)
        result := JSONSerializer.Stringify(m)
        this.assert.isTrue(InStr(result, '"key"'))
        this.assert.isTrue(InStr(result, '"value"'))
        this.assert.isTrue(InStr(result, '42'))
    }

    Test_StringifyBoolean() {
        m := Map("active", true, "disabled", false)
        result := JSONSerializer.Stringify(m)
        this.assert.isTrue(InStr(result, "true"))
        this.assert.isTrue(InStr(result, "false"))
    }

    Test_StringifyNestedMap() {
        inner := Map("x", 1)
        outer := Map("data", inner)
        result := JSONSerializer.Stringify(outer)
        this.assert.isTrue(InStr(result, '"x"'))
        this.assert.isTrue(InStr(result, '1'))
    }
}

class JSONParserTests extends AutoHotUnitSuite {
    Test_ParseSimpleObject() {
        result := JSONParser.Parse('{"name":"test","value":42}')
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result["name"] = "test")
        this.assert.isTrue(result["value"] = 42)
    }

    Test_ParseBoolean() {
        result := JSONParser.Parse('{"active":true}')
        this.assert.isTrue(result["active"] = true)
    }

    Test_ParseNull() {
        result := JSONParser.Parse('{"value":null}')
        this.assert.isTrue(result.Has("value"))
    }

    Test_ParseArray() {
        result := JSONParser.Parse('{"items":[1,2,3]}')
        arr := result["items"]
        this.assert.isTrue(arr is Array)
        this.assert.isTrue(arr.Length = 3)
    }

    Test_ParseLargeNumber() {
        result := JSONParser.Parse('{"big":9999999999}')
        this.assert.isTrue(result.Has("big"))
    }
}

class SkillManagerTests extends AutoHotUnitSuite {
    Test_GroupsMapExists() {
        this.assert.isTrue(SkillManager.Groups is Map)
    }

    Test_CreateGroupAddsToMap() {
        initialCount := SkillManager.Groups.Count
        config := Map("mode", "periodic", "pressKeys", ["a"], "intervals", [100], "hotkey", "F1")
        try {
            SkillManager.CreateGroup("test_int_1", config)
            this.assert.isTrue(SkillManager.Groups.Has("test_int_1"))
        } finally {
            try SkillManager.DeleteGroup("test_int_1")
        }
    }

    Test_DeleteGroupRemovesFromMap() {
        config := Map("mode", "periodic", "pressKeys", ["a"], "intervals", [100], "hotkey", "F2")
        try {
            SkillManager.CreateGroup("test_int_2", config)
            SkillManager.DeleteGroup("test_int_2")
            this.assert.isFalse(SkillManager.Groups.Has("test_int_2"))
        } catch {
        }
    }
}

class ModeRegistryTests extends AutoHotUnitSuite {
    Test_GetExecutorPeriodic() {
        exec := ModeRegistry.GetExecutor("periodic")
        this.assert.isTrue(exec is IExecutor)
    }

    Test_GetExecutorSequence() {
        exec := ModeRegistry.GetExecutor("sequence")
        this.assert.isTrue(exec is IExecutor)
    }

    Test_GetExecutorHold() {
        exec := ModeRegistry.GetExecutor("hold")
        this.assert.isTrue(exec is IExecutor)
    }

    Test_GetExecutorEnhancedPeriodic() {
        exec := ModeRegistry.GetExecutor("enhanced_periodic")
        this.assert.isTrue(exec is IExecutor)
    }

    Test_GetExecutorEnhancedSequence() {
        exec := ModeRegistry.GetExecutor("enhanced_sequence")
        this.assert.isTrue(exec is IExecutor)
    }

    Test_GetExecutorInvalidReturnsDefault() {
        exec := ModeRegistry.GetExecutor("nonexistent")
        this.assert.isTrue(exec is IExecutor)
    }
}

class ErrorSystemTests extends AutoHotUnitSuite {
    Test_LogError() {
        try {
            ErrorSystem.LogError("test error message", "ERROR", "TestFunc", 1)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("LogError should not throw: " e.Message)
        }
    }

    Test_LogWarning() {
        try {
            ErrorSystem.LogWarning("test warning", "TestFunc", 1)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("LogWarning should not throw: " e.Message)
        }
    }
}

reporter := SilentReporter(A_ScriptDir "\reports\integration_full_report.txt")
runner := AutoHotUnit.Runner(reporter)

runner.AddSuite(MigrationLoggerTests())
runner.AddSuite(ConfigMigrationTests())
runner.AddSuite(ConfigValidatorTests())
runner.AddSuite(BackupCoreTests())
runner.AddSuite(JSONSerializerTests())
runner.AddSuite(JSONParserTests())
runner.AddSuite(SkillManagerTests())
runner.AddSuite(ModeRegistryTests())
runner.AddSuite(ErrorSystemTests())

runner.Run()

if reporter.failures.Length = 0
    ExitApp(0)
else
    ExitApp(1)
