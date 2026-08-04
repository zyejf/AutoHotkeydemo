; =================================================================
; 领域层 - KeyRecorder 按键录制器
; 版本: 1.0
; 说明: 使用 InputHook + Hotkey 捕获键盘/鼠标事件
;       记录时间戳，可导出为分组配置
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "../infrastructure/error_system.ahk"

class KeyRecorder {
    static _recording := false
    static _events := []
    static _startTime := 0
    static _onEvent := ""
    static _hook := 0
    static _mouseHotkeys := false
    static MAX_EVENTS := 10000
    static _paused := false

    static IsRecording() => this._recording

    static IsPaused() => this._paused

    static Pause() {
        if !this._recording || this._paused
            return
        this._paused := true
        try this._hook.Stop()
        this._RemoveMouseHooks()
    }

    static Resume() {
        if !this._recording || !this._paused
            return
        try {
            this._hook := InputHook("V L0")
            this._hook.KeyDown := (keyName, *) => this.OnKey(keyName, "down")
            this._hook.KeyUp := (keyName, *) => this.OnKey(keyName, "up")
            this._hook.KeyOpt("{All}", "N")
            this._hook.Start()
            this._InstallMouseHooks()
            this._paused := false
        } catch as e {
            try this._hook.Stop()
            this._hook := 0
            this._RemoveMouseHooks()
            this._paused := true
            ErrorSystem.LogError("KeyRecorder Resume failed: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static GetEventCount() => this._events.Length

    static Start(onEvent) {
        if this._recording
            return
        this._recording := true
        this._paused := false
        this._events := []
        this._startTime := A_TickCount
        this._onEvent := onEvent
        try {
            this._hook := InputHook("V L0")
            this._hook.KeyDown := (keyName, *) => this.OnKey(keyName, "down")
            this._hook.KeyUp := (keyName, *) => this.OnKey(keyName, "up")
            this._hook.KeyOpt("{All}", "N")
            this._hook.Start()
            this._InstallMouseHooks()
        } catch as e {
            this._recording := false
            if this._hook {
                try this._hook.Stop()
                this._hook := 0
            }
            this._RemoveMouseHooks()
            throw e
        }
    }

    static Stop() {
        if !this._recording
            return Map()
        this._recording := false
        this._paused := false
        if this._hook {
            try this._hook.Stop()
            this._hook := 0
        }
        this._RemoveMouseHooks()
        duration := A_TickCount - this._startTime
        this._onEvent := ""
        return Map("events", this._events.Clone(), "duration", duration)
    }

    static OnKey(key, event, timestamp := "") {
        if !this._recording
            return
        if this._events.Length >= this.MAX_EVENTS {
            this.Stop()
            return
        }
        if timestamp = ""
            timestamp := A_TickCount - this._startTime
        evt := Map(
            "key", key,
            "event", event,
            "timestamp", timestamp,
            "device", "keyboard"
        )
        this._events.Push(evt)
        if this._onEvent {
            try
                this._onEvent.Call(evt)
            catch as e
                ErrorSystem.LogError("KeyRecorder onEvent callback error: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }

    static OnMouse(button, event, timestamp := "") {
        if !this._recording
            return
        if this._events.Length >= this.MAX_EVENTS {
            this.Stop()
            return
        }
        if timestamp = ""
            timestamp := A_TickCount - this._startTime
        evt := Map(
            "key", button,
            "event", event,
            "timestamp", timestamp,
            "device", "mouse"
        )
        this._events.Push(evt)
        if this._onEvent {
            try
                this._onEvent.Call(evt)
            catch as e
                ErrorSystem.LogError("KeyRecorder onEvent callback error: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }

    static ExportAsGroupConfig(mode, keyPressDuration := 15) {
        if this._events.Length = 0
            return Map()

        downEvents := []
        for evt in this._events {
            if evt["event"] = "down" || evt["event"] = "click"
                downEvents.Push(evt)
        }
        if downEvents.Length = 0
            return Map()

        keys := []
        for evt in downEvents
            keys.Push(evt["key"])

        if mode = "periodic" {
            intervals := []
            if downEvents.Length > 1 {
                Loop downEvents.Length - 1 {
                    i := A_Index + 1
                    interval := downEvents[i]["timestamp"] - downEvents[i - 1]["timestamp"]
                    if interval < 10
                        interval := 10
                    intervals.Push(interval)
                }
            }
            if intervals.Length = 0
                intervals.Push(50)
            return Map(
                "mode", "periodic",
                "keys", keys,
                "intervals", intervals,
                "keyPressDuration", keyPressDuration
            )
        }

        if mode = "sequence" {
            delays := []
            if downEvents.Length > 1 {
                Loop downEvents.Length - 1 {
                    i := A_Index + 1
                    delay := downEvents[i]["timestamp"] - downEvents[i - 1]["timestamp"]
                    if delay < 10
                        delay := 10
                    delays.Push(delay)
                }
            }
            if delays.Length = 0
                delays.Push(100)
            return Map(
                "mode", "sequence",
                "keys", keys,
                "delays", delays,
                "keyPressDuration", keyPressDuration
            )
        }

        if mode = "hold" {
            holdKeys := []
            for evt in downEvents
                holdKeys.Push(evt["key"])
            return Map(
                "mode", "hold",
                "holdKeys", holdKeys,
                "holdDuration", 0,
                "autoRepeat", false,
                "repeatInterval", 1000,
                "keyPressDuration", keyPressDuration
            )
        }

        if mode = "enhanced_periodic" {
            pressKeys := []
            for evt in downEvents
                pressKeys.Push(evt["key"])
            intervals := []
            if downEvents.Length > 1 {
                Loop downEvents.Length - 1 {
                    i := A_Index + 1
                    interval := downEvents[i]["timestamp"] - downEvents[i - 1]["timestamp"]
                    if interval < 10
                        interval := 10
                    intervals.Push(interval)
                }
            }
            if intervals.Length = 0
                intervals.Push(50)
            return Map(
                "mode", "enhanced_periodic",
                "pressKeys", pressKeys,
                "intervals", intervals,
                "keyPressDuration", keyPressDuration
            )
        }

        if mode = "enhanced_sequence" {
            pressKeys := []
            for evt in downEvents
                pressKeys.Push(evt["key"])
            delays := []
            if downEvents.Length > 1 {
                Loop downEvents.Length - 1 {
                    i := A_Index + 1
                    delay := downEvents[i]["timestamp"] - downEvents[i - 1]["timestamp"]
                    if delay < 10
                        delay := 10
                    delays.Push(delay)
                }
            }
            if delays.Length = 0
                delays.Push(100)
            return Map(
                "mode", "enhanced_sequence",
                "pressKeys", pressKeys,
                "pressDelays", delays,
                "keyPressDuration", keyPressDuration
            )
        }

        return Map()
    }

    static _InstallMouseHooks() {
        mouseButtons := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
        for btn in mouseButtons {
            try {
                Hotkey("~*" btn " Down", this._MakeMouseEventHandler(btn, "down"), "On")
            } catch as e {
                ; best-effort: 鼠标钩子热键注册失败不影响核心功能
                OutputDebug("ASD [WARN] KeyRecorder._InstallMouseHooks: " e.Message " at line " e.Line)
            }
            try {
                Hotkey("~*" btn " Up", this._MakeMouseEventHandler(btn, "up"), "On")
            } catch as e {
                ; best-effort: 鼠标钩子热键注册失败不影响核心功能
                OutputDebug("ASD [WARN] KeyRecorder._InstallMouseHooks: " e.Message " at line " e.Line)
            }
        }
        try {
            Hotkey("~WheelUp", this._MakeWheelHotkeyHandler("WheelUp"), "On")
        } catch as e {
            ; best-effort: 滚轮热键注册失败不影响核心功能
            OutputDebug("ASD [WARN] KeyRecorder._InstallMouseHooks: " e.Message " at line " e.Line)
        }
        try {
            Hotkey("~WheelDown", this._MakeWheelHotkeyHandler("WheelDown"), "On")
        } catch as e {
            ; best-effort: 滚轮热键注册失败不影响核心功能
            OutputDebug("ASD [WARN] KeyRecorder._InstallMouseHooks: " e.Message " at line " e.Line)
        }
        this._mouseHotkeys := true
    }

    static _MakeMouseEventHandler(btn, event) {
        return () => (this._recording && !this._paused ? this.OnMouse(btn, event) : 0)
    }

    static _MakeWheelHotkeyHandler(direction) {
        return () => (this._recording && !this._paused ? this.OnMouse(direction, "click") : 0)
    }

    static _RemoveMouseHooks() {
        if !this._mouseHotkeys
            return
        mouseButtons := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
        for btn in mouseButtons {
            try Hotkey("~*" btn " Down", "Off")
            try Hotkey("~*" btn " Up", "Off")
        }
        try Hotkey("~WheelUp", "Off")
        try Hotkey("~WheelDown", "Off")
        this._mouseHotkeys := false
    }
}
