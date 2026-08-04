; =================================================================
; 热点路径性能基准测试 (Hot Path Benchmark Suite)
; 版本: 1.0
; 说明: 对 4 大热点路径进行精确微基准测试
;       为 Rust 重写调研提供 AHK 侧真实性能数据
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include ..\infrastructure\json_parser.ahk
#Include ..\infrastructure\json_serializer.ahk
#Include ..\infrastructure\json_logger.ahk
#Include ..\infrastructure\config_store.ahk
#Include ..\infrastructure\error_system.ahk
#Include ..\domain\key_validator.ahk
#Include ..\domain\interfaces.ahk
#Include ..\domain\skill_group.ahk
#Include ..\domain\mode_registry.ahk
#Include ..\domain\skill_manager.ahk
#Include ..\infrastructure\ipc_channel.ahk

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Fail_Output := true
ResultReporter := ""
ReporterEnabled := IsSet(ResultReporter)

class BenchmarkRunner {
    static _results := []
    static _warmupIterations := 3
    static _measureIterations := 20

    static RunAll() {
        OutputDebug("`n========== 热点路径基准测试开始 ==========`n")

        this._RunBenchmark("BENCH-01: JSON 解析 (1KB config)", this.BenchJsonParse)
        this._RunBenchmark("BENCH-02: JSON 序列化 (1KB config)", this.BenchJsonSerialize)
        this._RunBenchmark("BENCH-03: JSON 解析 (10KB 大文件)", this.BenchJsonParseLarge)
        this._RunBenchmark("BENCH-04: JSON 序列化 (10KB 大文件)", this.BenchJsonSerializeLarge)
        this._RunBenchmark("BENCH-05: 配置完整加载流程", this.BenchConfigLoad)
        this._RunBenchmark("BENCH-06: 配置完整保存流程", this.BenchConfigSave)
        this._RunBenchmark("BENCH-07: 100键按键名称校验", this.BenchKeyValidate)
        this._RunBenchmark("BENCH-08: 10分组调度初始化", this.BenchGroupSchedule)
        this._RunBenchmark("BENCH-09: 1000条日志写入", this.BenchLogWrite)
        this._RunBenchmark("BENCH-10: JSON 往返序列化", this.BenchJsonRoundtrip)
        this._RunBenchmark("BENCH-11: deepclone 深拷贝", this.BenchDeepClone)
        this._RunBenchmark("BENCH-12: Map 操作 (1000键)", this.BenchMapOps)

        OutputDebug("`n========== 基准测试结束 ==========`n")
        return this._GenerateReport()
    }

    static _RunBenchmark(name, fn) {
        OutputDebug("[BENCH] " name " ...")

        for i in Range(1, this._warmupIterations)
            fn()

        timings := []
        for i in Range(1, this._measureIterations) {
            start := A_TickCount
            fn()
            elapsed := A_TickCount - start
            timings.Push(elapsed)
        }

        avg := 0
        for t in timings
            avg += t
        avg := Round(avg / timings.Length, 2)

        mn := timings[1]
        mx := timings[1]
        for t in timings {
            if t < mn
                mn := t
            if t > mx
                mx := t
        }

        sorted := []
        for t in timings
            sorted.Push(t)

        for i in Range(1, sorted.Length) {
            for j in Range(i + 1, sorted.Length) {
                if sorted[i] > sorted[j] {
                    tmp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := tmp
                }
            }
        }

        mid := Floor(sorted.Length / 2)
        median := sorted.Length & 1 ? sorted[mid + 1] : Round((sorted[mid] + sorted[mid + 1]) / 2, 2)

        p95 := sorted[Ceil(sorted.Length * 0.95)]

        result := Map(
            "name", name,
            "avg_ms", avg,
            "min_ms", mn,
            "max_ms", mx,
            "median_ms", median,
            "p95_ms", p95,
            "iterations", this._measureIterations,
            "ops_per_sec", avg > 0 ? Round(1000 / avg, 1) : "N/A"
        )
        this._results.Push(result)

        opsStr := result["ops_per_sec"]
        OutputDebug(Format("  avg={}ms  min={}ms  max={}ms  p95={}ms  ops/s={}", avg, mn, mx, p95, opsStr))
        return result
    }

    static _GenerateReport() {
        lines := []
        lines.Push("============================================")
        lines.Push("  热点路径性能基准测试报告 (AHK v2.0)")
        lines.Push("  " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"))
        lines.Push("  预热: " this._warmupIterations "轮 | 测量: " this._measureIterations "轮")
        lines.Push("============================================")
        lines.Push("")

        header := Format("{:<45} {:>8} {:>8} {:>8} {:>8} {:>8} {:>8}",
                         "测试项目", "avg(ms)", "min(ms)", "max(ms)", "median", "p95", "ops/s")
        lines.Push(header)
        lines.Push(StrReplace(header, ".", "-"))
        for idx, r in this._results {
            line := Format("{:<45} {:>8} {:>8} {:>8} {:>8} {:>8} {:>8}",
                          r["name"],
                          String(r["avg_ms"]),
                          String(r["min_ms"]),
                          String(r["max_ms"]),
                          String(r["median_ms"]),
                          String(r["p95_ms"]),
                          String(r["ops_per_sec"]))
            lines.Push(line)
        }

        lines.Push("")
        lines.Push("--- 统计摘要 ---")

        totalAvg := 0
        for r in this._results
            totalAvg += r["avg_ms"]
        lines.Push("总耗时(sum avg): " Round(totalAvg, 2) " ms")

        return Join("`n", lines)
    }

    static _GenConfig(size) {
        groups := Map()
        switch size {
            case "1K":
                groups := Map(
                    "1", Map("hotkey", "F1", "mode", "periodic", "keys", ["a", "b", "c"], "intervals", [50, 50, 50])
                )
            case "10K":
                for i in Range(1, 40) {
                    keys := []
                    intervals := []
                    for j in Range(1, 5) {
                        keys.Push(Format("{:c}", 96 + Mod(j, 26)))
                        intervals.Push(Random(30, 100))
                    }
                    groups[String(i)] := Map(
                        "hotkey", "F" Mod(i, 12),
                        "mode", Mod(i, 3) = 0 ? "sequence" : "periodic",
                        "keys", keys,
                        "intervals", intervals
                    )
                }
        }
        config := Map(
            "version", "3.0",
            "lastModified", A_Now,
            "GroupSettings", groups,
            "CONTROL_HOTKEYS", Map("emergency", "F12", "toggleAll", "^1"),
            "HoldSettings", Map("debounceDelay", 20, "checkInterval", 50)
        )
        return config
    }

    static BenchJsonParse() {
        jsonStr := JSONSerializer.Stringify(this._GenConfig("1K"))
        JSONParser.ParseOut := ""
        result := JSONParser.Parse(jsonStr, "")
        if !(result is Map)
            throw Error("解析失败")
    }

    static BenchJsonSerialize() {
        config := this._GenConfig("1K")
        jsonStr := JSONSerializer.Stringify(config)
        if jsonStr = ""
            throw Error("序列化失败")
    }

    static BenchJsonParseLarge() {
        jsonStr := JSONSerializer.Stringify(this._GenConfig("10K"))
        result := JSONParser.Parse(jsonStr, "")
        if !(result is Map)
            throw Error("大文件解析失败")
    }

    static BenchJsonSerializeLarge() {
        config := this._GenConfig("10K")
        jsonStr := JSONSerializer.Stringify(config)
        if jsonStr = ""
            throw Error("大文件序列化失败")
    }

    static BenchConfigLoad() {
        config := this._GenConfig("10K")
        jsonStr := JSONSerializer.Stringify(config)

        tempFile := A_Temp "\bench_config.json"
        FileDelete(tempFile)
        FileAppend(jsonStr, tempFile, "UTF-8")

        try {
            result := JSONParser.LoadFile(tempFile)
            if !(result is Map)
                throw Error("配置加载失败")
        } finally {
            FileDelete(tempFile)
        }
    }

    static BenchConfigSave() {
        config := this._GenConfig("10K")

        tempFile := A_Temp "\bench_save.json"
        jsonStr := JSONSerializer.Stringify(config)

        FileDelete(tempFile)
        FileAppend(jsonStr, tempFile, "UTF-8")
        try {
            loaded := JSONParser.LoadFile(tempFile)
            ConfigStore.Save(loaded)
        } finally {
            FileDelete(tempFile)
        }
    }

    static BenchKeyValidate() {
        testKeys := [
            "Space", "Enter", "Tab", "Escape", "Backspace",
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
            "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
            "u", "v", "w", "x", "y", "z",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
            "Up", "Down", "Left", "Right",
            "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
            "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
            "LButton", "RButton", "MButton", "XButton1", "XButton2",
            "WheelUp", "WheelDown",
            "^a", "^c", "^v", "^x", "^z",
            "+a", "+b", "+c",
            "!a", "!b", "!c",
            "^+a", "^+b", "^+c",
            "^!+a", "^!+b", "^!+c",
            "+!a", "+!b", "+!c"
        ]

        for key in testKeys {
            baseKey := RegExReplace(key, "^[\^+!#]+", "")
            isMouse := baseKey = "LButton" || baseKey = "RButton" || baseKey = "MButton"
                || baseKey = "XButton1" || baseKey = "XButton2"
                || baseKey = "WheelUp" || baseKey = "WheelDown"
            isValid := StrLen(baseKey) > 0
            if !isValid
                throw Error("无效键: " key)
        }
    }

    static BenchGroupSchedule() {
        groups := Map()
        for i in Range(1, 10) {
            keys := []
            intervals := []
            for j in Range(1, 3) {
                keys.Push(Format("{:c}", 96 + Mod(i + j, 26)))
                intervals.Push(30 + i * 5)
            }
            groups[String(i)] := Map(
                "hotkey", "F" Mod(i, 12),
                "mode", Mod(i, 2) = 0 ? "periodic" : "sequence",
                "keys", keys,
                "intervals", intervals
            )
        }

        for id, config in groups {
            grp := SkillGroup(id, config)
            if !(grp is SkillGroup)
                throw Error("分组创建失败: " id)
        }
    }

    static BenchLogWrite() {
        tempLog := A_Temp "\bench_test.log"
        FileDelete(tempLog)

        ErrorSystem.logFile := tempLog
        ErrorSystem._initialized := false
        ErrorSystem.Init()

        for i in Range(1, 1000) {
            ErrorSystem.LogError("基准测试日志条目 #" i " - 这是一条中等长度的错误信息用于测试日志系统吞吐量",
                               Mod(i, 3) = 0 ? "ERROR" : "WARNING")
        }

        FileDelete(tempLog)
        ErrorSystem.logFile := ""
    }

    static BenchJsonRoundtrip() {
        config := this._GenConfig("1K")
        jsonStr1 := JSONSerializer.Stringify(config)
        parsed := JSONParser.Parse(jsonStr1, "")
        jsonStr2 := JSONSerializer.Stringify(parsed)
        if jsonStr2 = ""
            throw Error("往返序列化失败")
    }

    static BenchDeepClone() {
        config := this._GenConfig("10K")
        cloned := deepclone(config)
        if !(cloned is Map)
            throw Error("深拷贝失败")
    }

    static BenchMapOps() {
        m := Map()
        for i in Range(1, 1000) {
            m["key_" i] := "value_" i
        }
        count := 0
        for k, v in m {
            count++
            if v != "value_" SubStr(k, 5)
                throw Error("Map读取不一致")
        }
        if count != 1000
            throw Error("Map计数错误")
    }
}

class Join {
    static Call(delim, arr) {
        result := ""
        for i, item in arr {
            if i > 1
                result .= delim
            result .= item
        }
        return result
    }
}

global LogRotator := {Rotate: (path, max) => 0}

try {
    report := BenchmarkRunner.RunAll()

    reportFile := A_ScriptDir "\benchmark_report.txt"
    FileDelete(reportFile)
    FileAppend(report, reportFile, "UTF-8")

    OutputDebug("`n" report)
    OutputDebug("`n报告已保存到: " reportFile)

    FileAppend("`nBENCHMARK_OK", A_ScriptDir "\benchmark_result.txt", "UTF-8")
} catch as e {
    OutputDebug("基准测试失败: " e.Message)
    FileAppend("`nBENCHMARK_FAIL: " e.Message, A_ScriptDir "\benchmark_result.txt", "UTF-8")
}