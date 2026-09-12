; =================================================================
; AHK IPC 执行器 - 主入口
; 版本: 1.0
; 说明: AHK 子进程主入口，连接 Rust 主进程的 Named Pipe
;       接收 IPC 指令执行按键/热键/手柄操作
;       由 Rust 侧 ProcessWatchdog 管理生命周期
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 设置 SendLevel 让 asd_executor 发送的按键能触发 key_receiver 的热键钩子
; 默认 SendLevel=0 的 SendInput 不触发热键钩子
SendLevel(10)

; =================================================================
; 模块引入
; =================================================================

#Include "ipc_client.ahk"
#Include "hotkey_hook.ahk"
#Include "sender.ahk"
#Include "joystick.ahk"

; =================================================================
; 全局错误接管
; 直接运行、编译为 exe 时注册；被 #Include（如测试）时由包含者负责错误接管
; 注意：编译后 A_LineFile 为源文件名（executor.ahk），A_ScriptFullPath 为 exe 路径，
; 两者不相等，因此需要额外检查 A_IsCompiled，否则编译模式下 OnError 不注册，
; 运行时错误会弹出 AHK 默认错误对话框导致 E2E 测试卡住
; =================================================================

if (A_IsCompiled || A_LineFile = A_ScriptFullPath)
    OnError((e, mode) => (OutputDebug("RUNTIME_ERROR: " e.Message " at line " e.Line), true))

; =================================================================
; IPC 命令分发器
; =================================================================

class CommandDispatcher {
    ; 技能组配置缓存: groupId => config Map
    static _groupConfigs := Map()

    ; 录制状态
    static _recordState := "idle"
    static _recordedKeys := []
    static _recordMode := "periodic"
    static _recordGroupId := ""

    ; =================================================================
    ; 分发 IPC 命令
    ; =================================================================

    static Dispatch(action, data, seq) {
        OutputDebug("CommandDispatcher: 分发 action=" action " seq=" seq)

        switch action {
            case "toggle_group":
                CommandDispatcher._HandleToggleGroup(data, seq)
            case "register_hotkey":
                CommandDispatcher._HandleRegisterHotkey(data, seq)
            case "unregister_hotkey":
                CommandDispatcher._HandleUnregisterHotkey(data, seq)
            case "emergency_release":
                CommandDispatcher._HandleEmergencyRelease(seq)
            case "hold_mode_toggle":
                CommandDispatcher._HandleHoldModeToggle(data, seq)
            case "start_recording":
                CommandDispatcher._HandleStartRecording(data, seq)
            case "stop_recording":
                CommandDispatcher._HandleStopRecording(seq)
            case "pause_recording":
                CommandDispatcher._HandlePauseRecording(seq)
            case "resume_recording":
                CommandDispatcher._HandleResumeRecording(data, seq)
            case "start_validation":
                CommandDispatcher._HandleStartValidation(data, seq)
            case "stop_validation":
                CommandDispatcher._HandleStopValidation(seq)
            default:
                OutputDebug("CommandDispatcher: 未知命令 action=" action)
                IpcClient.SendResult(seq, Map("status", "error", "message", "未知命令: " action))
        }
    }

    ; =================================================================
    ; 命令处理
    ; =================================================================

    static _HandleToggleGroup(data, seq) {
        groupId := CommandDispatcher._GetStr(data, "groupId", "")
        active := CommandDispatcher._GetBool(data, "active", false)

        if groupId = "" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "缺少 groupId"))
            return
        }

        if active {
            ; 从 IPC 数据合并模式配置，填充缓存后启动
            mergedConfig := CommandDispatcher._MergeModeConfig(data)
            CommandDispatcher._groupConfigs[groupId] := mergedConfig
            CommandDispatcher._StartGroupWithConfig(groupId, mergedConfig)
        } else {
            Sender.ToggleGroup(groupId, false)
            Joystick.StopGroup(groupId)
        }

        IpcClient.SendResult(seq, Map("status", "ok", "groupId", groupId, "active", active ? MiniJson.BOOL_TRUE : MiniJson.BOOL_FALSE))
    }

    static _HandleRegisterHotkey(data, seq) {
        hotkeyStr := CommandDispatcher._GetStr(data, "hotkey", "")
        groupId := CommandDispatcher._GetStr(data, "groupId", "")

        if hotkeyStr = "" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "缺少 hotkey"))
            return
        }

        ok := HotkeyHook.Register(hotkeyStr, groupId)
        IpcClient.SendResult(seq, Map("status", ok ? "ok" : "error", "hotkey", hotkeyStr, "groupId", groupId))
    }

    static _HandleUnregisterHotkey(data, seq) {
        hotkeyStr := CommandDispatcher._GetStr(data, "hotkey", "")

        if hotkeyStr = "" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "缺少 hotkey"))
            return
        }

        ok := HotkeyHook.Unregister(hotkeyStr)
        IpcClient.SendResult(seq, Map("status", ok ? "ok" : "error", "hotkey", hotkeyStr))
    }

    static _HandleEmergencyRelease(seq) {
        Sender.EmergencyRelease()
        Joystick.EmergencyRelease()
        IpcClient.SendResult(seq, Map("status", "ok"))
    }

    static _HandleHoldModeToggle(data, seq) {
        enabled := CommandDispatcher._GetBool(data, "enabled", true)
        Sender.HoldModeToggle(enabled)
        IpcClient.SendResult(seq, Map("status", "ok", "enabled", enabled ? MiniJson.BOOL_TRUE : MiniJson.BOOL_FALSE))
    }

    static _HandleStartRecording(data, seq) {
        groupId := CommandDispatcher._GetStr(data, "groupId", "")
        mode := CommandDispatcher._GetStr(data, "mode", "periodic")
        if CommandDispatcher._recordState = "recording" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "已在录制中"))
            return
        }
        if CommandDispatcher._recordState = "idle" {
            CommandDispatcher._recordedKeys := []
            CommandDispatcher._recordMode := mode
            CommandDispatcher._recordGroupId := groupId
        }
        CommandDispatcher._recordState := "recording"
        Sender._reportKeyEvents := true
        OutputDebug("CommandDispatcher: 录制开始 groupId=" groupId " mode=" mode)
        IpcClient.SendResult(seq, Map("status", "ok", "groupId", groupId, "mode", mode))
    }

    static _HandleStopRecording(seq) {
        if CommandDispatcher._recordState = "idle" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "未在录制中"))
            return
        }
        CommandDispatcher._recordState := "idle"
        Sender._reportKeyEvents := false
        recordedKeys := CommandDispatcher._recordedKeys
        mode := CommandDispatcher._recordMode

        ; 从带时间戳的录制数据中提取按键列表和间隔
        keys := []
        intervals := []
        delays := []

        for i, entry in recordedKeys {
            if entry is Map {
                if entry.Has("key")
                    keys.Push(entry["key"])
                if i > 1 && entry.Has("time") {
                    prevEntry := recordedKeys[i - 1]
                    if prevEntry is Map && prevEntry.Has("time") {
                        interval := entry["time"] - prevEntry["time"]
                        ; 间隔最小 10ms，避免零间隔或极小间隔
                        safeInterval := interval > 10 ? interval : 50
                        intervals.Push(safeInterval)
                        delays.Push(safeInterval)
                    }
                }
            }
        }

        ; 第一个键的默认间隔
        if keys.Length > 0 {
            intervals.InsertAt(1, 50)
            delays.InsertAt(1, 50)
        }

        OutputDebug("CommandDispatcher: 录制停止 keys=" keys.Length " intervals=" intervals.Length)
        IpcClient.SendResult(seq, Map(
            "status", "ok",
            "keys", keys,
            "mode", mode,
            "count", keys.Length,
            "intervals", intervals,
            "delays", delays
        ))
    }

    static _HandlePauseRecording(seq) {
        if CommandDispatcher._recordState != "recording" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "未在录制中"))
            return
        }
        CommandDispatcher._recordState := "paused"
        OutputDebug("CommandDispatcher: 录制已暂停")
        IpcClient.SendResult(seq, Map("status", "ok", "paused", true))
    }

    static _HandleResumeRecording(data, seq) {
        if CommandDispatcher._recordState != "paused" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "未在暂停中"))
            return
        }
        CommandDispatcher._recordState := "recording"
        OutputDebug("CommandDispatcher: 录制已恢复")
        IpcClient.SendResult(seq, Map("status", "ok", "resumed", true))
    }

    ; 验证状态
    static _validationGroupId := ""

    static _HandleStartValidation(data, seq) {
        groupId := CommandDispatcher._GetStr(data, "groupId", "")
        if groupId = "" {
            IpcClient.SendResult(seq, Map("status", "error", "message", "缺少 groupId"))
            return
        }
        CommandDispatcher._validationGroupId := groupId
        Sender._reportKeyEvents := true
        OutputDebug("CommandDispatcher: 验证模式启动 groupId=" groupId)
        IpcClient.SendResult(seq, Map("status", "ok", "validation", true, "groupId", groupId))
    }

    static _HandleStopValidation(seq) {
        groupId := CommandDispatcher._validationGroupId
        CommandDispatcher._validationGroupId := ""
        Sender._reportKeyEvents := false
        OutputDebug("CommandDispatcher: 验证模式停止 groupId=" groupId)
        IpcClient.SendResult(seq, Map("status", "ok", "validation", false, "groupId", groupId))
    }

    ; 录制按键回调 — 同时记录按键名称和时间戳
    static RecordKey(key) {
        if CommandDispatcher._recordState = "recording" {
            entry := Map(
                "key", key,
                "time", A_TickCount
            )
            CommandDispatcher._recordedKeys.Push(entry)
            IpcClient._SendMsg(Map(
                "type", "key_record_event",
                "seq", IpcClient._NextSeq(),
                "data", Map("key", key, "time", A_TickCount, "device", "keyboard")
            ))
        }
    }

    ; =================================================================
    ; 配置缓存与执行启动
    ; =================================================================

    ; 缓存技能组配置（由外部调用）
    static CacheGroupConfig(groupId, config) {
        CommandDispatcher._groupConfigs[groupId] := config
    }

    ; 根据配置启动技能组
    static _StartGroupWithConfig(groupId, config) {
        mode := CommandDispatcher._GetStr(config, "mode", "periodic")
        kpd := CommandDispatcher._GetInt(config, "keyPressDuration", 15)

        Sender.ToggleGroup(groupId, true)

        switch mode {
            case "periodic":
                keys := CommandDispatcher._GetArr(config, "keys")
                intervals := CommandDispatcher._GetArr(config, "intervals")
                Sender.StartPeriodic(groupId, keys, intervals, kpd)
            case "sequence":
                keys := CommandDispatcher._GetArr(config, "keys")
                delays := CommandDispatcher._GetArr(config, "delays")
                Sender.StartSequence(groupId, keys, delays, kpd)
            case "enhanced_periodic":
                keys := CommandDispatcher._GetArr(config, "pressKeys")
                intervals := CommandDispatcher._GetArr(config, "intervals")
                Sender.StartEnhancedPeriodic(groupId, keys, intervals, kpd)
            case "enhanced_sequence":
                keys := CommandDispatcher._GetArr(config, "pressKeys")
                delays := CommandDispatcher._GetArr(config, "pressDelays")
                Sender.StartEnhancedSequence(groupId, keys, delays, kpd)
            case "hold":
                holdKeys := CommandDispatcher._GetArr(config, "holdKeys")
                holdMode := CommandDispatcher._GetStr(config, "holdMode", "continuous")
                holdDuration := CommandDispatcher._GetInt(config, "holdDuration", 0)
                Sender.StartHold(groupId, holdKeys, holdMode, holdDuration)
            case "hybrid":
                groups := CommandDispatcher._GetArr(config, "groups")
                Sender.StartHybrid(groupId, groups, kpd)
            case "enhanced_hybrid":
                groups := CommandDispatcher._GetArr(config, "groups")
                Sender.StartEnhancedHybrid(groupId, groups, kpd)
            case "joystick_periodic":
                joyKeys := CommandDispatcher._GetArr(config, "joyKeys")
                joyIntervals := CommandDispatcher._GetArr(config, "joyIntervals")
                sendMethod := CommandDispatcher._GetStr(config, "joySendMethod", "auto")
                Joystick.StartPeriodic(groupId, joyKeys, joyIntervals, sendMethod, kpd)
            case "joystick_sequence":
                joyKeys := CommandDispatcher._GetArr(config, "joyKeys")
                joyDelays := CommandDispatcher._GetArr(config, "joyDelays")
                sendMethod := CommandDispatcher._GetStr(config, "joySendMethod", "auto")
                Joystick.StartSequence(groupId, joyKeys, joyDelays, sendMethod, kpd)
            case "joystick_hold":
                joyKeys := CommandDispatcher._GetArr(config, "joyKeys")
                sendMethod := CommandDispatcher._GetStr(config, "joySendMethod", "auto")
                Joystick.StartHold(groupId, joyKeys, sendMethod)
            default:
                OutputDebug("CommandDispatcher: 未知模式 mode=" mode)
        }
    }

    ; =================================================================
    ; 数据提取辅助
    ; =================================================================

    static _GetStr(data, key, default := "") {
        if data is Map {
            if data.Has(key) {
                val := data[key]
                if val is String
                    return val
                if val != ""
                    return String(val)
            }
        } else if IsObject(data) && HasProp(data, key)
            return String(data.%key%)
        return default
    }

    static _GetInt(data, key, default := 0) {
        str := CommandDispatcher._GetStr(data, key, "")
        if str = ""
            return default
        try
            return Integer(str)
        catch
            return default
    }

    static _GetBool(data, key, default := false) {
        if data is Map {
            if data.Has(key)
                return data[key] = true || data[key] = 1 || data[key] = "true"
        } else if IsObject(data) && HasProp(data, key)
            return data.%key% = true || data.%key% = 1 || data.%key% = "true"
        return default
    }

    static _GetArr(data, key) {
        if data is Map {
            if data.Has(key) {
                val := data[key]
                if val is Array
                    return val
            }
        } else if IsObject(data) && HasProp(data, key) {
            val := data.%key%
            if val is Array
                return val
        }
        return []
    }

    ; 将 IPC 数据合并为 _StartGroupWithConfig 期望的扁平配置
    ; 顶层字段（mode, keyPressDuration, holdKeys, holdMode）直接复制
    ; modeData 子对象的字段提升到顶层（keys, intervals, pressKeys 等）
    static _MergeModeConfig(data) {
        config := Map()
        if data is Map {
            for k, v in data {
                if k != "modeData" && k != "active" && k != "groupId"
                    config[k] := v
            }
            if data.Has("modeData") {
                modeData := data["modeData"]
                if modeData is Map {
                    for k, v in modeData
                        config[k] := v
                }
            }
        }
        return config
    }

    static _GetMap(data, key) {
        if data is Map {
            if data.Has(key) {
                val := data[key]
                if val is Map
                    return val
            }
        }
        return Map()
    }
}

; =================================================================
; 初始化与启动
; =================================================================

Executor_Init() {
    OutputDebug("Executor: 初始化开始")

    ; 初始化各模块
    HotkeyHook.Init()
    Sender.Init()
    Joystick.Init()

    ; 设置 IPC 回调
    IpcClient.OnCommand := (action, data, seq) => CommandDispatcher.Dispatch(action, data, seq)
    IpcClient.OnShutdown := () => Executor_Shutdown()
    IpcClient.OnConnected := () => OutputDebug("Executor: IPC 已连接")
    IpcClient.OnDisconnected := () => OutputDebug("Executor: IPC 已断开")

    ; 绑定录制回调
    HotkeyHook.OnKeyRecorded := (key) => CommandDispatcher.RecordKey(key)

    ; 启动 IPC 连接
    IpcClient.Start()

    OutputDebug("Executor: 初始化完成，等待 IPC 连接")
}

Executor_Shutdown() {
    OutputDebug("Executor: 开始关机")

    ; 停止所有执行
    Sender.Shutdown()
    Joystick.EmergencyRelease()
    HotkeyHook.UnregisterAll()

    ; 停止 IPC
    IpcClient.Stop()

    OutputDebug("Executor: 关机完成")
}

; 退出时清理（仅直接运行或编译为 exe 时注册）
; 注意：编译后 A_LineFile 为源文件名（executor.ahk），A_ScriptFullPath 为 exe 路径，
; 两者不相等，因此需要额外检查 A_IsCompiled
if (A_IsCompiled || A_LineFile = A_ScriptFullPath)
    OnExit((exitCode, exitReason) => (Executor_Shutdown(), 0))

; =================================================================
; 启动
; 仅在直接运行 executor.ahk 或编译为 exe 时初始化；被 #Include（如测试）时跳过
; =================================================================

if (A_IsCompiled || A_LineFile = A_ScriptFullPath)
    Executor_Init()

; 编译模式下需要 Persistent 保持脚本运行（无热键/GUI 时脚本会自动退出）
if (A_IsCompiled)
    Persistent
