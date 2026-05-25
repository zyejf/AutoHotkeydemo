#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
Persistent

; 引入模块
#Include "json.ahk"
#Include "gui.ahk"

; =================================================================
; 调试日志系统
; =================================================================
class DebugLogger {
	static logFile := "logs/debug.log"
	static enabled := true
	static maxSize := 5 * 1024 * 1024  ; 5MB
	static initialized := false

	static Init() {
		if this.initialized
			return
		this.initialized := true
		if !InStr(FileExist("logs"), "D")
			DirCreate("logs")
		; 写入会话分隔符
		try {
			FileAppend("`n========== " A_Now " ==========`n", this.logFile, "UTF-8")
		}
	}

	static Log(message) {
		if !this.enabled
			return
		try {
			this.Init()
			timestamp := FormatTime(, "HH:mm:ss")
			logLine := "[" timestamp "] " message "`n"
			FileAppend(logLine, this.logFile, "UTF-8")
			OutputDebug(message)
		} catch as e {
			OutputDebug("DebugLogger ERROR: " e.Message)
		}
	}

	static LogSeparator(title := "") {
		this.Log("---------- " title " ----------")
	}

	static LogVar(name, value) {
		this.Log(name " = '" value "' (type: " Type(value) ")")
	}

static LogMap(name, m) {
		if !(m is Map) {
			this.Log(name " is not a Map, type=" Type(m))
			return
		}
		this.Log(name " (Map, count=" m.Count ")")
		for k, v in m {
			if (A_Index > 10) {
				this.Log(" ... and " (m.Count - 10) " more items")
				break
			}
			this.Log(" [" k "] = '" (IsObject(v) ? Type(v) : v) "'")
		}
	}
}

; =================================================================
; 第一部分: 增强版用户配置区 (支持长按功能)
; =================================================================
; 第一部分: 增强版用户配置区 (支持长按功能)
; =================================================================

global GroupSettings := Map(
    ; 模式1: 序列连招 + 全程长按Shift
    1, { 
        hotkey: "F1", 
        mode: "enhanced_sequence", 
        ; 快速按下的按键序列 (按下即释放)
        pressKeys: ["Space", "4", "RButton"], 
        pressDelays: [50, 50, 50],
        ; 长按的按键 (激活时按下，关闭时释放)
         ;holdKeys: ["RButton"],
        ; 长按模式: 
        ;   "continuous" - 全程长按 (默认)
        ;   "sequence" - 在序列步骤中长按
         ;holdMode: "continuous",
        ; 当holdMode为"sequence"时，指定哪些步骤触发长按
        ;   [1, 0, 0, 1] 表示第1和第4步长按，第2和第3步正常按
         ;holdTriggers: []
    },
    
    ; 模式2: 基础序列连招 (无长按，保持原样)
    2, { 
        hotkey: "F2", 
        mode: "sequence", 
        keys: ["1", "2", "3", "q"], 
        delays: [100, 100, 100, 100] 
    },
    
    ; 模式3: 周期性按键 + 全程长按Ctrl
    3, { 
        hotkey: "F3", 
        mode: "enhanced_periodic", 
        ; 周期性按下的按键 (每隔指定时间按一次)
        pressKeys: ["space","1", "2", "3", "RButton", "space"], 
        intervals: [50, 50, 50, 50, 50, 50],
        ; 全程长按的按键
        holdKeys: ["Shift"],
        ; 长按模式:
        ;   "continuous" - 全程长按 (默认)
        ;   "periodic" - 周期性长按 (按住/释放交替)
        holdMode: "continuous",
        ; 当holdMode为"periodic"时，指定长按模式
        ;   [500, 500] 表示按住500ms，释放500ms，循环
        holdPattern: []
    },
    
    ; 模式4: 混合模式增强版 (周期性+序列)
    4, { 
        hotkey: "F4", 
        mode: "enhanced_hybrid", 
        ; 周期性部分
        periodic: { 
            pressKeys: ["Space"], 
            intervals: [100] 
        },
        ; 序列部分
        sequence: { 
            pressKeys: ["1", "2", "3", "4", "q"], 
            delays: [100, 100, 100, 100, 100] 
        },
        seqInterval: 100,
        ; 长按的按键
        holdKeys: ["Shift", "Ctrl"],
        ; 长按模式: 
        ;   "continuous" - 全程长按 (默认)
        ;   "sequence" - 在序列步骤中长按
        ;   "periodic" - 在周期性部分长按
        holdMode: "continuous"
    },
      5, { 
        hotkey: "F5", 
        mode: "enhanced_periodic", 
        ; 周期性按下的按键 (每隔指定时间按一次)
        pressKeys: [ "5"], 
        intervals: [ 50],
        ; 全程长按的按键
        holdKeys: ["Shift"],
        ; 长按模式:
        ;   "continuous" - 全程长按 (默认)
        ;   "periodic" - 周期性长按 (按住/释放交替)
        holdMode: "continuous",
        ; 当holdMode为"periodic"时，指定长按模式
        ;   [500, 500] 表示按住500ms，释放500ms，循环
        holdPattern: []
    },
    ; 模式5: 纯长按模式
    6, { 
        hotkey: "F6", 
        mode: "hold", 
        ; 长按的按键
        holdKeys: ["RButton"],
        ; 长按时长 (毫秒)
        ;   0: 按住不放直到手动关闭
        ;   >0: 按住指定时间后自动释放
        holdDuration: 700,
        ; 是否自动重复长按
        autoRepeat: false,
        ; 重复间隔 (autoRepeat为true时生效)
        repeatInterval: 1000
    }
)

global CONTROL_HOTKEYS := Map(
    "emergency", "f12",      ; Ctrl+2: 紧急停止
    "toggleAll", "^1",      ; Ctrl+1: 切换所有分组
    "showStatus", "^0",     ; Ctrl+0: 显示状态
    "toggleHoldMode", "^h", ; Ctrl+H: 切换长按模式
    "releaseAllHolds", "^r" ; Ctrl+R: 释放所有长按键
)

; 长按功能的全局设置
global HoldSettings := {
    debounceDelay: 20,      ; 按键防抖延迟(毫秒)
    checkInterval: 50,      ; 长按键状态检查频率
    allowOverlap: false,    ; 是否允许多分组同时长按同一键
    pressSpeed: 80,         ; 按键速度 (1-100)
    releaseOnEmergency: true ; 紧急停止时释放长按键
}

; =================================================================
; 第二部分: 用户界面管理器
; =================================================================

class UIManager {
    static _lastToastTime := 0
    static _toastDuration := 1500
    
    ; 显示状态提示消息
    static ShowStatus(message, type := "info") {
        if (A_TickCount - this._lastToastTime < 500)
            return
        
        this._lastToastTime := A_TickCount
        
        toast := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound")
        
        colors := Map(
            "success", "00AA00",
            "error", "FF4444",
            "warning", "FF9900",
            "info", "3366CC"
        )
        
        bgColor := colors.Has(type) ? colors[type] : "3366CC"
        toast.BackColor := bgColor
        toast.SetFont("cFFFFFF s11 Bold", "Microsoft YaHei UI")
        toast.MarginX := 20
        toast.MarginY := 8
        
        textControl := toast.Add("Text", "Center", message)
        toast.Show("NoActivate")
        
        toast.GetPos(, , &width, &height)
        xPos := (A_ScreenWidth - width) // 2
        yPos := A_ScreenHeight - 100
        
        toast.Show("x" xPos " y" yPos " NoActivate")
        WinSetTransparent(240, toast.Hwnd)
        
        SetTimer(() => toast.Destroy(), -this._toastDuration)
    }
    
    ; 显示简要信息
    static ShowBriefInfo(activeCount, emergencyMode) {
        if emergencyMode {
            this.ShowStatus("🔴 紧急停止已激活", "error")
        } else if activeCount > 0 {
            this.ShowStatus("🟢 运行中 (" activeCount "个分组)", "success")
        } else {
            this.ShowStatus("⚪ 系统待机", "info")
        }
    }
}

; =================================================================
; 第三部分: 增强版技能组系统 (支持长按功能)
; =================================================================

class SkillGroup {
	__New(id, config) {
		DebugLogger.Log("SkillGroup.__New: id=" id)
		DebugLogger.Log("  config.type=" Type(config))
		DebugLogger.Log("  config.mode type=" Type(config.mode) " value='" config.mode "'")
		DebugLogger.Log("  config.hotkey type=" Type(config.hotkey) " value='" config.hotkey "'")
		
		this.id := id
		this.active := false
		this.mode := config.mode
		this.hotkey := config.hotkey

		; 运行时状态跟踪
		this._executionCount := 0
		this._startTime := 0
		this._lastUpdateTime := 0

		; 长按相关属性 - 修复：使用 HasProp() 而不是 .Has()
		this.holdKeys := HasProp(config, "holdKeys") ? config.holdKeys : []
		this.holdMode := HasProp(config, "holdMode") ? config.holdMode : "continuous"
		this._heldKeys := Map() ; 记录当前长按的键
		
		DebugLogger.Log("  Calling _SetupMode...")
		this._SetupMode(config)
		DebugLogger.Log("SkillGroup.__New: complete for id=" id)
	}
    
; 根据模式初始化配置
	_SetupMode(config) {
		DebugLogger.Log("_SetupMode: mode='" this.mode "'")
		switch this.mode {
			case "periodic":
				DebugLogger.Log("  Setting up periodic mode")
				this.keys := config.keys
				this.intervals := config.intervals
				this._isMouse := this._CheckMouseKeys(this.keys)

			case "sequence":
				DebugLogger.Log("  Setting up sequence mode")
				this.keys := config.keys
				this.delays := config.delays
				this._currentStep := 1
				this._isMouse := this._CheckMouseKeys(this.keys)

			case "hybrid":
				DebugLogger.Log("  Setting up hybrid mode")
				this.periodicKeys := config.periodic.keys
				this.periodicIntervals := config.periodic.intervals
				this._periodicMouse := this._CheckMouseKeys(this.periodicKeys)

				this.seqKeys := config.sequence.keys
				this.seqDelays := config.sequence.delays
				this._seqMouse := this._CheckMouseKeys(this.seqKeys)

				this.seqInterval := config.seqInterval
				this._seqStep := 1
				this._lastSeqRun := 0

			case "hold":
				DebugLogger.Log("  Setting up hold mode")
				DebugLogger.Log("    config.holdDuration type=" Type(config.holdDuration) " value=" config.holdDuration)
				this.holdDuration := config.holdDuration
				DebugLogger.Log("    holdDuration assigned OK")
				this.autoRepeat := HasProp(config, "autoRepeat") ? config.autoRepeat : false
				this.repeatInterval := HasProp(config, "repeatInterval") ? config.repeatInterval : 1000
				this._holdStartTime := 0
				this._isHoldMouse := this._CheckMouseKeys(this.holdKeys)

			case "enhanced_periodic":
				DebugLogger.Log("  Setting up enhanced_periodic mode")
				this.pressKeys := config.pressKeys
				this.intervals := config.intervals
				this._pressMouse := this._CheckMouseKeys(this.pressKeys)

				this.holdPattern := HasProp(config, "holdPattern") ? config.holdPattern : []
				if (this.holdMode = "periodic" && this.holdPattern.Length > 0) {
					this._holdPatternIndex := 1
					this._holdPatternStart := 0
				}

			case "enhanced_sequence":
				DebugLogger.Log("  Setting up enhanced_sequence mode")
				this.pressKeys := config.pressKeys
				this.pressDelays := config.pressDelays
				this._pressMouse := this._CheckMouseKeys(this.pressKeys)
				this._currentStep := 1

				this.holdTriggers := HasProp(config, "holdTriggers") ? config.holdTriggers : []
				this._activeHolds := Map() ; 当前激活的长按

			case "enhanced_hybrid":
				DebugLogger.Log("  Setting up enhanced_hybrid mode")
				this.periodicPressKeys := config.periodic.pressKeys
				this.periodicIntervals := config.periodic.intervals
				this._periodicMouse := this._CheckMouseKeys(this.periodicPressKeys)

				this.seqPressKeys := config.sequence.pressKeys
				this.seqDelays := config.sequence.delays
				this._seqMouse := this._CheckMouseKeys(this.seqPressKeys)

				this.seqInterval := config.seqInterval
				this._seqStep := 1
				this._lastSeqRun := 0
}
		DebugLogger.Log("_SetupMode: complete")
	}

	; 检查是否为鼠标按键
    _CheckMouseKeys(keys) {
        result := []
        for key in keys {
            result.Push(InStr(key, "Button") ? true : false)
        }
        return result
    }
    
    ; 切换技能组状态
    Toggle() {
        this.active := !this.active
        
        if !this.active {
            this._ReleaseAllKeys()
            UIManager.ShowStatus("分组 " this.id " 已关闭", "info")
            return false
        }
        
        ; 重置运行时状态
        this._executionCount := 0
        this._startTime := A_TickCount
        this._lastUpdateTime := A_TickCount
        
        ; 根据模式重置状态
        switch this.mode {
            case "sequence", "enhanced_sequence":
                this._currentStep := 1
            case "hybrid", "enhanced_hybrid":
                this._seqStep := 1
                this._lastSeqRun := 0
            case "hold":
                this._holdStartTime := A_TickCount
                ; 对于纯长按模式，立即按下长按键
                if (this.holdKeys.Length > 0) {
                    this._PressHoldKeys()
                }
            case "enhanced_periodic":
                if (this.holdMode = "periodic") {
                    this._holdPatternIndex := 1
                    this._holdPatternStart := A_TickCount
                }
        }
        
        ; 激活时按下长按键（对于非纯长按模式）
        if (this.holdKeys.Length > 0 && this.holdMode = "continuous" && this.mode != "hold") {
            this._PressHoldKeys()
        }
        
        UIManager.ShowStatus("分组 " this.id " 已激活", "success")
        return true
    }
    
    ; 按下长按键（真正的长按，不自动释放）
    _PressHoldKeys() {
        for i, key in this.holdKeys {
            if !SkillManager.IsKeyAllowed(key, this.id) {
                continue
            }
            
            isMouse := InStr(key, "Button") ? true : false
            ; 对于长按键，只按下，不释放
            this._SendHoldKey(key, isMouse, true)
            this._heldKeys[key] := A_TickCount
            SkillManager.RegisterHoldKey(key, this.id)
        }
    }
    
    ; 释放所有长按键
    _ReleaseHoldKeys() {
        for key in this._heldKeys {
            isMouse := InStr(key, "Button") ? true : false
            this._SendHoldKey(key, isMouse, false)  ; 释放长按键
            SkillManager.UnregisterHoldKey(key, this.id)
        }
        this._heldKeys.Clear()
    }
    
    ; 发送长按键（true=按下，false=释放）
    _SendHoldKey(key, isMouse, press := true) {
        try {
            if press {
                ; 按下长按键
                if isMouse {
                    SendEvent("{Blind}{" key " Down}")
                } else {
                    SendEvent("{Blind}{" key " Down}")
                }
            } else {
                ; 释放长按键
                if isMouse {
                    SendEvent("{Blind}{" key " Up}")
                } else {
                    SendEvent("{Blind}{" key " Up}")
                }
            }
        }
    }
    
    ; 释放所有按键
    _ReleaseAllKeys() {
        ; 释放普通按键
        switch this.mode {
            case "periodic":
                for i, key in this.keys {
                    this._ReleaseKey(key, this._isMouse[i])
                }
            case "sequence":
                for i, key in this.keys {
                    this._ReleaseKey(key, this._isMouse[i])
                }
            case "hybrid":
                for i, key in this.periodicKeys {
                    this._ReleaseKey(key, this._periodicMouse[i])
                }
                for i, key in this.seqKeys {
                    this._ReleaseKey(key, this._seqMouse[i])
                }
            case "enhanced_periodic":
                for i, key in this.pressKeys {
                    this._ReleaseKey(key, this._pressMouse[i])
                }
            case "enhanced_sequence":
                for i, key in this.pressKeys {
                    this._ReleaseKey(key, this._pressMouse[i])
                }
            case "enhanced_hybrid":
                for i, key in this.periodicPressKeys {
                    this._ReleaseKey(key, this._periodicMouse[i])
                }
                for i, key in this.seqPressKeys {
                    this._ReleaseKey(key, this._seqMouse[i])
                }
        }
        
        ; 释放长按键
        this._ReleaseHoldKeys()
    }
    
    ; 释放单个普通按键
    _ReleaseKey(key, isMouse) {
        try {
            if isMouse {
                SendEvent("{Blind}{" key " Up}")
            } else {
                SendEvent("{Blind}{" key " Up}")
            }
        }
    }
    
    ; 执行技能组
    Execute() {
        if !this.active
            return 0
        
        ; 更新执行计数
        this._executionCount++
        this._lastUpdateTime := A_TickCount
        
        switch this.mode {
            case "periodic":
                return this._ExecutePeriodic()
            case "sequence":
                return this._ExecuteSequence()
            case "hybrid":
                return this._ExecuteHybrid()
            case "hold":
                return this._ExecuteHold()
            case "enhanced_periodic":
                return this._ExecuteEnhancedPeriodic()
            case "enhanced_sequence":
                return this._ExecuteEnhancedSequence()
            case "enhanced_hybrid":
                return this._ExecuteEnhancedHybrid()
        }
        
        return 10
    }
    
    ; 基础周期性执行
    _ExecutePeriodic() {
        for i, key in this.keys {
            if (Mod(A_TickCount, this.intervals[i]) < 50) {
                this._SendKey(key, this._isMouse[i])
            }
        }
        return 10
    }
    
    ; 基础序列执行
    _ExecuteSequence() {
        key := this.keys[this._currentStep]
        isMouse := this._isMouse[this._currentStep]
        delay := this.delays[this._currentStep]
        
        this._SendKey(key, isMouse)
        this._currentStep := Mod(this._currentStep, this.keys.Length) + 1
        
        return delay
    }
    
    ; 基础混合执行
    _ExecuteHybrid() {
        for i, key in this.periodicKeys {
            if (Mod(A_TickCount, this.periodicIntervals[i]) < 50) {
                this._SendKey(key, this._periodicMouse[i])
            }
        }
        
        if (A_TickCount - this._lastSeqRun >= this.seqInterval) {
            key := this.seqKeys[this._seqStep]
            isMouse := this._seqMouse[this._seqStep]
            
            this._SendKey(key, isMouse)
            this._seqStep := Mod(this._seqStep, this.seqKeys.Length) + 1
            this._lastSeqRun := A_TickCount
        }
        
        return 10
    }
    
    ; 长按模式执行
    _ExecuteHold() {
        ; 检查是否需要自动释放
        if (this.holdDuration > 0 && A_TickCount - this._holdStartTime > this.holdDuration) {
            if (this.autoRepeat) {
                ; 自动重复：先释放再按下
                this._ReleaseHoldKeys()
                Sleep(50)
                this._PressHoldKeys()
                this._holdStartTime := A_TickCount
                return this.repeatInterval
            } else {
                ; 单次长按：关闭分组
                SkillManager.ToggleGroup(this.id)
            }
        }
        
        return 50
    }
    
    ; 增强周期性执行（支持长按）
    _ExecuteEnhancedPeriodic() {
        ; 执行周期性按键
        for i, key in this.pressKeys {
            if (Mod(A_TickCount, this.intervals[i]) < 50) {
                this._SendKey(key, this._pressMouse[i])
            }
        }
        
        ; 处理长按模式
        if (this.holdKeys.Length > 0) {
            switch this.holdMode {
                case "continuous":
                    ; 已在Toggle中处理，保持按住状态
                    ; 确保长按键仍然被按住
                    for key in this.holdKeys {
                        if !this._heldKeys.Has(key) {
                            ; 如果长按键意外释放了，重新按下
                            isMouse := InStr(key, "Button") ? true : false
                            this._SendHoldKey(key, isMouse, true)
                            this._heldKeys[key] := A_TickCount
                            SkillManager.RegisterHoldKey(key, this.id)
                        }
                    }
                    
                case "periodic":
                    if (this.holdPattern.Length >= 2) {
                        patternIndex := this._holdPatternIndex
                        cycleTime := this.holdPattern[1] + this.holdPattern[2]
                        elapsed := Mod(A_TickCount - this._holdPatternStart, cycleTime)
                        
                        if (elapsed < this.holdPattern[1]) {
                            ; 应该按住
                            if (!this._heldKeys.Has(this.holdKeys[1])) {
                                this._PressHoldKeys()
                            }
                        } else {
                            ; 应该释放
                            if (this._heldKeys.Has(this.holdKeys[1])) {
                                this._ReleaseHoldKeys()
                            }
                        }
                    }
            }
        }
        
        return 10
    }
    
    ; 增强序列执行（支持长按）
    _ExecuteEnhancedSequence() {
        ; 处理当前步骤的长按状态
        if (this.holdKeys.Length > 0 && this.holdMode = "sequence" && this.holdTriggers.Length > 0) {
            shouldHold := this.holdTriggers[this._currentStep]
            
            if shouldHold && !this._heldKeys.Has(this.holdKeys[1]) {
                ; 开始长按
                this._PressHoldKeys()
            } else if !shouldHold && this._heldKeys.Has(this.holdKeys[1]) {
                ; 释放长按
                this._ReleaseHoldKeys()
            }
        }
        
        ; 执行序列按键
        key := this.pressKeys[this._currentStep]
        isMouse := this._pressMouse[this._currentStep]
        delay := this.pressDelays[this._currentStep]
        
        this._SendKey(key, isMouse)
        this._currentStep := Mod(this._currentStep, this.pressKeys.Length) + 1
        
        return delay
    }
    
    ; 增强混合执行（支持长按）
    _ExecuteEnhancedHybrid() {
        ; 执行周期性按键
        for i, key in this.periodicPressKeys {
            if (Mod(A_TickCount, this.periodicIntervals[i]) < 50) {
                this._SendKey(key, this._periodicMouse[i])
            }
        }
        
        ; 执行序列按键
        if (A_TickCount - this._lastSeqRun >= this.seqInterval) {
            key := this.seqPressKeys[this._seqStep]
            isMouse := this._seqMouse[this._seqStep]
            
            this._SendKey(key, isMouse)
            this._seqStep := Mod(this._seqStep, this.seqPressKeys.Length) + 1
            this._lastSeqRun := A_TickCount
        }
        
        ; 处理长按模式
        if (this.holdKeys.Length > 0) {
            switch this.holdMode {
                case "continuous":
                    ; 已在Toggle中处理，保持按住状态
                    ; 确保长按键仍然被按住
                    for key in this.holdKeys {
                        if !this._heldKeys.Has(key) {
                            ; 如果长按键意外释放了，重新按下
                            isMouse := InStr(key, "Button") ? true : false
                            this._SendHoldKey(key, isMouse, true)
                            this._heldKeys[key] := A_TickCount
                            SkillManager.RegisterHoldKey(key, this.id)
                        }
                    }
                    
                case "sequence":
                    ; 在序列步骤中处理长按
                    if (this._lastSeqRun = A_TickCount - this.seqInterval) {
                        ; 序列刚执行，可以在这里添加序列触发的长按逻辑
                    }
                    
                case "periodic":
                    ; 周期性长按
                    if (Mod(A_TickCount, 1000) < 500) {
                        if (!this._heldKeys.Has(this.holdKeys[1])) {
                            this._PressHoldKeys()
                        }
                    } else {
                        if (this._heldKeys.Has(this.holdKeys[1])) {
                            this._ReleaseHoldKeys()
                        }
                    }
            }
        }
        
        return 10
    }
    
    ; 发送普通按键（按下即释放）
    _SendKey(key, isMouse) {
        ; 防抖检查
        static lastSend := Map()
        if lastSend.Has(key) && (A_TickCount - lastSend[key] < 50)
            return
        
        try {
            ; 普通按键：按下后立即释放
            if isMouse {
                SendEvent("{Blind}{" key " DownR}")
                Sleep(15)
                SendEvent("{Blind}{" key " Up}")
            } else {
                SendEvent("{Blind}{" key " DownR}")
                Sleep(15)
                SendEvent("{Blind}{" key " Up}")
            }
            lastSend[key] := A_TickCount
        }
    }
    
    ; 获取运行时状态
    GetRuntimeStatus() {
        currentStep := 0
        if (this.mode = "sequence" || this.mode = "enhanced_sequence")
            currentStep := this._currentStep
        else if (this.mode = "hybrid" || this.mode = "enhanced_hybrid")
            currentStep := this._seqStep
        
        return {
            active: this.active,
            executionCount: this._executionCount,
            runTime: this.active ? A_TickCount - this._startTime : 0,
            currentStep: currentStep,
            lastUpdate: this._lastUpdateTime,
            heldKeys: this._heldKeys.Count
        }
    }
}

; =================================================================
; 第四部分: 系统管理器（增强版，支持长按管理）
; =================================================================

class SkillManager {
    static Groups := Map()
    static ActiveCount := 0
    static EmergencyMode := false
    static HoldKeyRegistry := Map()  ; 记录哪些键被哪些分组长按
    static HoldModeEnabled := true   ; 是否启用长按功能
    
    ; 初始化系统
    static Init() {
        for id, config in GroupSettings {
            this.Groups[id] := SkillGroup(id, config)
        }
        
        this._BindHotkeys()
        UIManager.ShowStatus("🎮 技能管理器已启动 (长按功能已启用)", "success")
    }
    
    ; 绑定热键
    static _BindHotkeys() {
        ; 为每个技能组绑定热键
        for id, group in this.Groups {
            Hotkey(group.hotkey, ((id) => (*) => this.ToggleGroup(id))(id))
        }
        
        ; 为控制热键绑定功能
        for action, hk in CONTROL_HOTKEYS {
            Hotkey(hk, ((action) => (*) => this.%action%())(action))
        }
    }
    
    ; 切换技能组状态
    static ToggleGroup(id) {
        if this.EmergencyMode
            return
        
        group := this.Groups[id]
        
        if group.Toggle() {
            this.ActiveCount++
            this._StartGroupExecution(id)
        } else {
            this.ActiveCount--
            this._StopGroupExecution(id)
        }
        
        UIManager.ShowBriefInfo(this.ActiveCount, this.EmergencyMode)
    }
    
    ; 开始执行技能组
    static _StartGroupExecution(id) {
        group := this.Groups[id]
        this._StopGroupExecution(id)
        
        executor(*) {
            if this.EmergencyMode || !group.active {
                this._StopGroupExecution(id)
                return
            }
            
            delay := group.Execute()
            if delay > 0 {
                SetTimer(executor, -delay)
            }
        }
        
        boundExecutor := executor.Bind(this)
        SetTimer(boundExecutor, -10)
    }
    
    ; 停止执行技能组
    static _StopGroupExecution(id) {
        this.Groups[id]._ReleaseAllKeys()
    }
    
    ; 注册长按键（防止冲突）
    static RegisterHoldKey(key, groupId) {
        ; 修复：直接访问全局变量 HoldSettings，而不是通过 global.HoldSettings
        if !HoldSettings.allowOverlap && this.HoldKeyRegistry.Has(key) {
            ; 键已被其他分组占用
            existingGroup := this.HoldKeyRegistry[key]
            if existingGroup != groupId {
                UIManager.ShowStatus("警告: " key " 键已被分组" existingGroup "占用", "warning")
                return false
            }
        }
        
        this.HoldKeyRegistry[key] := groupId
        return true
    }
    
    ; 注销长按键
    static UnregisterHoldKey(key, groupId) {
        if this.HoldKeyRegistry.Has(key) && this.HoldKeyRegistry[key] = groupId {
            this.HoldKeyRegistry.Delete(key)
        }
    }
    
    ; 检查按键是否允许被长按
    static IsKeyAllowed(key, groupId) {
        if !this.HoldKeyRegistry.Has(key) {
            return true
        }
        ; 修复：直接访问全局变量 HoldSettings
        return HoldSettings.allowOverlap || this.HoldKeyRegistry[key] = groupId
    }
    
    ; 紧急停止
    static emergency() {
        this.EmergencyMode := true
        
        for id, group in this.Groups {
            group.active := false
            this._StopGroupExecution(id)
        }
        
        this.ActiveCount := 0
        
        ; 清理长按键注册表
        ; 修复：直接访问全局变量 HoldSettings
        if HoldSettings.releaseOnEmergency {
            this.HoldKeyRegistry.Clear()
        }
        
        UIManager.ShowBriefInfo(this.ActiveCount, this.EmergencyMode)
        SetTimer(() => this.ResetEmergency(), -3000)
    }
    
    ; 重置紧急停止
    static ResetEmergency() {
        this.EmergencyMode := false
        UIManager.ShowBriefInfo(this.ActiveCount, this.EmergencyMode)
    }
    
    ; 切换所有分组
    static toggleAll() {
        if this.EmergencyMode
            return
        
        if this.ActiveCount > 0 {
            for id, group in this.Groups {
                if group.active {
                    group.active := false
                    this._StopGroupExecution(id)
                }
            }
            this.ActiveCount := 0
            UIManager.ShowStatus("所有分组已关闭", "info")
        } else {
            for id, group in this.Groups {
                if !group.active {
                    group.active := true
                    this._StartGroupExecution(id)
                }
            }
            this.ActiveCount := this.Groups.Count
            UIManager.ShowStatus("所有分组已激活", "success")
        }
        
        UIManager.ShowBriefInfo(this.ActiveCount, this.EmergencyMode)
    }
    
    ; 显示状态
    static showStatus() {
        if this.EmergencyMode {
            UIManager.ShowStatus("🔴 紧急停止模式 | 按F1-F5重新开始", "error")
        } else if this.ActiveCount > 0 {
            holdKeys := []
            for key, groupId in this.HoldKeyRegistry {
                holdKeys.Push(key " (分组" groupId ")")
            }
            
            if holdKeys.Length > 0 {
                ; 使用 Join 函数连接字符串
                UIManager.ShowStatus("🟢 运行中 | " this.ActiveCount "个分组 | 长按: " this._Join(holdKeys, ", "), "success")
            } else {
                UIManager.ShowStatus("🟢 运行中 | " this.ActiveCount "个分组", "success")
            }
        } else {
            UIManager.ShowStatus("⚪ 待机 | 按F1-F5开始技能分组 | Ctrl+1全部开关", "info")
        }
    }
    
    ; 辅助函数：连接字符串数组
    static _Join(arr, delimiter) {
        result := ""
        for i, item in arr {
            if i > 1
                result .= delimiter
            result .= item
        }
        return result
    }
    
    ; 切换长按模式
    static toggleHoldMode() {
        this.HoldModeEnabled := !this.HoldModeEnabled
        
        if !this.HoldModeEnabled {
            ; 禁用长按模式，释放所有长按键
            for id, group in this.Groups {
                if group.active && group.holdKeys.Length > 0 {
                    group._ReleaseHoldKeys()
                }
            }
            this.HoldKeyRegistry.Clear()
        }
        
        UIManager.ShowStatus("长按功能: " (this.HoldModeEnabled ? "已启用" : "已禁用"), 
                            this.HoldModeEnabled ? "success" : "warning")
    }
    
    ; 释放所有长按键
    static releaseAllHolds() {
        for id, group in this.Groups {
            if group.active {
                group._ReleaseHoldKeys()
            }
        }
        this.HoldKeyRegistry.Clear()
        UIManager.ShowStatus("所有长按键已释放", "info")
    }
    
    ; 系统退出时的清理
    static OnExit(*) {
        for id, group in SkillManager.Groups {
            group._ReleaseAllKeys()
        }
        UIManager.ShowStatus("系统已关闭", "info")
    }
}

; =================================================================
; 第五部分: 辅助函数
; =================================================================

; 连接字符串数组
Join(arr, delimiter) {
    result := ""
    for i, item in arr {
        if i > 1
            result .= delimiter
        result .= item
    }
    return result
}

; =================================================================
; 第六部分: 系统初始化
; =================================================================

OnExit(SkillManager.OnExit)
SkillManager.Init()

; =================================================================
; 第七部分: 调试和帮助功能
; =================================================================

^+d:: {  ; Ctrl+Shift+D: 调试信息
    info := "🎮 技能管理器 - 调试信息`n"
    info .= "══════════════════════`n`n"
    
    info .= "📊 系统状态:`n"
    info .= "   活动分组: " SkillManager.ActiveCount "/" SkillManager.Groups.Count "`n"
    info .= "   紧急模式: " (SkillManager.EmergencyMode ? "是" : "否") "`n"
    info .= "   长按功能: " (SkillManager.HoldModeEnabled ? "启用" : "禁用") "`n`n"
    
    info .= "📋 长按键状态:`n"
    if SkillManager.HoldKeyRegistry.Count > 0 {
        for key, groupId in SkillManager.HoldKeyRegistry {
            info .= "   " key " -> 分组" groupId "`n"
        }
    } else {
        info .= "   无长按键激活`n"
    }
    
    info .= "`n📋 分组状态:`n"
    for id, group in SkillManager.Groups {
        modeText := ""
        switch group.mode {
            case "periodic": modeText := "周期"
            case "sequence": modeText := "序列"
            case "hybrid": modeText := "混合"
            case "hold": modeText := "长按"
            case "enhanced_periodic": modeText := "增强周期"
            case "enhanced_sequence": modeText := "增强序列"
            case "enhanced_hybrid": modeText := "增强混合"
        }
        
        status := group.active ? "🟢" : "⚪"
        holdInfo := group.holdKeys.Length > 0 ? " (长按: " Join(group.holdKeys, ", ") ")" : ""
        heldInfo := ""
        if group._heldKeys.Count > 0 {
            heldKeysList := []
            for key in group._heldKeys {
                heldKeysList.Push(key)
            }
            heldInfo := " [已按住: " Join(heldKeysList, ", ") "]"
        }
        info .= "   " status " 分组" id ": " modeText holdInfo heldInfo "`n"
    }
    
    info .= "`n══════════════════════`n"
    info .= "按确定继续..."
    
    MsgBox(info, "调试信息", "Iconi")
}

^+h:: {  ; Ctrl+Shift+H: 帮助信息
    helpText := 
    "
    (
    🎮 技能管理器 - 增强版 (支持长按功能)
    
    【基本操作】
    • F1-F5: 切换对应的技能分组
    • Ctrl+1: 一键开启/关闭所有分组
    • Ctrl+2: 紧急停止（卡键时使用）
    • Ctrl+0: 显示当前状态信息
    
    【新增功能】
    • Ctrl+H: 切换长按功能启用/禁用
    • Ctrl+R: 强制释放所有长按键
    
    【模式说明】
    1. 基础模式:
       - 周期性: 定时重复按键
       - 序列连招: 按顺序按键
       - 混合模式: 同时支持两种
    
    2. 增强模式 (支持长按):
       - 增强周期: 周期性按键 + 可选长按
       - 增强序列: 序列连招 + 可选长按
       - 增强混合: 混合模式 + 可选长按
       - 纯长按: 按住指定按键不放
    
    【长按配置说明】
    • holdKeys: 需要长按的按键列表
    • holdMode: 长按模式 (continuous/sequence/periodic)
    • holdDuration: 长按时长 (0=无限)
    • autoRepeat: 是否自动重复长按
    
    【修改配置】
    打开脚本文件，在顶部用户配置区修改:
    • pressKeys: 快速按下的按键
    • holdKeys: 长按的按键
    • delays/intervals: 时间间隔
    • hotkey: 激活热键
    
    【注意事项】
    1. 默认不允许多个分组同时长按同一键
    2. 紧急停止会自动释放所有长按键
    3. 长按键冲突时会显示警告
    
    按确定关闭帮助
    )"
    
    MsgBox(helpText, "快速帮助", "Iconi")
}

; =================================================================
; 第八部分: 配置导入导出功能
; =================================================================

; 导出当前配置到JSON文件
ExportConfigToJson(filePath := "config.json") {
    try {
        config := Map()
        
        ; 导出分组设置
groupSettings := Map()
	for id, group in GroupSettings {
		groupConfig := Map()
		groupConfig["hotkey"] := _GetProp(group, "hotkey", "")
		groupConfig["mode"] := _GetProp(group, "mode", "periodic")

		switch _GetProp(group, "mode", "") {
		case "periodic":
			groupConfig["keys"] := _GetProp(group, "keys", [])
			groupConfig["intervals"] := _GetProp(group, "intervals", [])
		case "sequence":
			groupConfig["keys"] := _GetProp(group, "keys", [])
			groupConfig["delays"] := _GetProp(group, "delays", [])
		case "hybrid":
			groupConfig["periodic"] := _GetProp(group, "periodic", {})
			groupConfig["sequence"] := _GetProp(group, "sequence", {})
			groupConfig["seqInterval"] := _GetProp(group, "seqInterval", 100)
		case "enhanced_periodic":
			groupConfig["pressKeys"] := _GetProp(group, "pressKeys", [])
			groupConfig["intervals"] := _GetProp(group, "intervals", [])
			holdKeys := _GetProp(group, "holdKeys", [])
			if (holdKeys.Length > 0)
				groupConfig["holdKeys"] := holdKeys
			if (_GetProp(group, "holdMode", "continuous") != "continuous")
				groupConfig["holdMode"] := _GetProp(group, "holdMode")
			holdPattern := _GetProp(group, "holdPattern", [])
			if (holdPattern.Length > 0)
				groupConfig["holdPattern"] := holdPattern
		case "enhanced_sequence":
				groupConfig["pressKeys"] := _GetProp(group, "pressKeys", [])
				groupConfig["pressDelays"] := _GetProp(group, "pressDelays", [])
				holdKeys := _GetProp(group, "holdKeys", [])
				if (holdKeys.Length > 0)
					groupConfig["holdKeys"] := holdKeys
				if (_GetProp(group, "holdMode", "continuous") != "continuous")
					groupConfig["holdMode"] := _GetProp(group, "holdMode")
			case "enhanced_hybrid":
				groupConfig["periodic"] := Map("pressKeys", _GetProp(group, "periodicPressKeys", []), "intervals", _GetProp(group, "periodicIntervals", []))
				groupConfig["sequence"] := Map("pressKeys", _GetProp(group, "seqPressKeys", []), "delays", _GetProp(group, "seqDelays", []))
				groupConfig["seqInterval"] := _GetProp(group, "seqInterval", 100)
				holdKeys := _GetProp(group, "holdKeys", [])
				if (holdKeys.Length > 0)
					groupConfig["holdKeys"] := holdKeys
				if (_GetProp(group, "holdMode", "continuous") != "continuous")
					groupConfig["holdMode"] := _GetProp(group, "holdMode")
			case "hold":
				groupConfig["holdKeys"] := _GetProp(group, "holdKeys", [])
				groupConfig["holdDuration"] := _GetProp(group, "holdDuration", 500)
				groupConfig["autoRepeat"] := _GetProp(group, "autoRepeat", false)
				groupConfig["repeatInterval"] := _GetProp(group, "repeatInterval", 1000)
			}
            
            groupSettings[String(id)] := groupConfig
        }
        config["GroupSettings"] := groupSettings
        
        ; 导出控制热键
        controlHotkeys := Map()
        for action, hk in CONTROL_HOTKEYS {
            controlHotkeys[action] := hk
        }
        config["CONTROL_HOTKEYS"] := controlHotkeys
        
; 导出全局设置
		holdSettings := Map()
		holdSettings["debounceDelay"] := _GetProp(HoldSettings, "debounceDelay", 20)
		holdSettings["checkInterval"] := _GetProp(HoldSettings, "checkInterval", 50)
		holdSettings["allowOverlap"] := _GetProp(HoldSettings, "allowOverlap", false)
		holdSettings["pressSpeed"] := _GetProp(HoldSettings, "pressSpeed", 80)
		holdSettings["releaseOnEmergency"] := _GetProp(HoldSettings, "releaseOnEmergency", true)
		config["HoldSettings"] := holdSettings
        
        ; 添加元数据
        config["version"] := "2.0"
        config["lastModified"] := A_Now
        
; 写入文件
		jsonStr := JSONSerializer.Stringify(config, 2)
		if FileExist(filePath)
			FileDelete(filePath)
		FileAppend(jsonStr, filePath, "UTF-8")
        
        UIManager.ShowStatus("配置已导出到 " filePath, "success")
        return true
    } catch as e {
        UIManager.ShowStatus("导出失败: " e.Message, "error")
        return false
    }
}

; 从JSON文件导入配置（热重载）
ImportConfigFromJson(filePath := "config.json") {
	DebugLogger.Log("=== ImportConfigFromJson START ===")
	DebugLogger.Log("File: " filePath)
	DebugLogger.Log("File exists: " FileExist(filePath))

	try {
		if !FileExist(filePath) {
			DebugLogger.Log("ERROR: File not found")
			UIManager.ShowStatus("配置文件不存在: " filePath, "warning")
			return false
		}

		; 解析JSON
		DebugLogger.Log("Calling JSONParser.LoadFile...")
		config := JSONParser.LoadFile(filePath)
		DebugLogger.Log("Parse complete. config type: " Type(config))
		if (config is Map)
			DebugLogger.LogMap("config", config)

		; 验证配置
		DebugLogger.Log("Validating config...")
		errors := ConfigValidator.Validate(config)
		DebugLogger.Log("Validation errors: " errors.Length)
		if (errors.Length > 0) {
			for err in errors {
				DebugLogger.Log("  Error: " err.level " - " err.message)
			}
			hasError := false
			for err in errors {
				if (err.level = "ERROR" || err.level = "CRITICAL")
					hasError := true
			}
			if (hasError) {
				DebugLogger.Log("Validation failed, aborting")
				UIManager.ShowStatus("配置验证失败，查看日志", "error")
				return false
			}
		}

		; 应用配置（热重载）
		DebugLogger.Log("Calling HotReloadConfig...")
		result := HotReloadConfig(config)
		DebugLogger.Log("HotReloadConfig result: " result)

		if (result) {
			UIManager.ShowStatus("配置已加载并生效", "success")
		}
		return result
	} catch as e {
		DebugLogger.Log("=== ImportConfigFromJson EXCEPTION ===")
		DebugLogger.Log("Message: " e.Message)
		DebugLogger.Log("File: " e.File)
		DebugLogger.Log("Line: " e.Line)
		DebugLogger.Log("Stack: " e.Stack)
		errorMsg := "导入失败: " e.Message
		try {
			errorMsg .= "`n位置: " e.File ":" e.Line
		}
		UIManager.ShowStatus(errorMsg, "error")
		return false
	}
}

; 热重载配置（立即生效）
HotReloadConfig(config) {
	try {
		DebugLogger.Log("=== HotReloadConfig START ===")
		DebugLogger.Log("config type: " Type(config))
		DebugLogger.Log("config.Has('GroupSettings'): " config.Has("GroupSettings"))

		; 停止所有正在运行的分组
		DebugLogger.Log("Stopping active groups...")
		for id, group in SkillManager.Groups {
			if (group.active) {
				group.active := false
				group._ReleaseAllKeys()
			}
		}

		; 更新分组设置
		if (config.Has("GroupSettings")) {
			newGroupSettings := config["GroupSettings"]
			DebugLogger.Log("newGroupSettings type: " Type(newGroupSettings))
			if (newGroupSettings is Map) {
				DebugLogger.Log("newGroupSettings.Count: " newGroupSettings.Count)
				DebugLogger.LogMap("newGroupSettings", newGroupSettings)
			}

			; 清除旧热键绑定
			for id, group in SkillManager.Groups {
				try {
					Hotkey(group.hotkey, "Off")
				}
			}

			; 清空并重建
			SkillManager.Groups := Map()

			for idStr, groupConfig in newGroupSettings {
				DebugLogger.Log("--- Processing group ---")
				DebugLogger.LogVar("idStr", idStr)
				DebugLogger.Log("idStr type: " Type(idStr))
				DebugLogger.Log("idStr len: " StrLen(idStr))
				DebugLogger.Log("RegExMatch: " RegExMatch(idStr, "^\d+$"))

				; 验证 idStr 是否为有效数字
				if !(idStr is String && RegExMatch(idStr, "^\d+$")) {
					DebugLogger.Log("SKIP: Invalid group ID")
					continue
				}

				DebugLogger.Log("Calling Integer(idStr)...")
				id := Integer(idStr)
				DebugLogger.LogVar("id", id)

				; 转换Map到Object（兼容原有结构）
				DebugLogger.Log("Calling _MapToObject...")
				configObj := _MapToObject(groupConfig)
				DebugLogger.Log("configObj type: " Type(configObj))

				; 创建新分组
				GroupSettings[id] := configObj
				SkillManager.Groups[id] := SkillGroup(id, configObj)
				DebugLogger.Log("Group " id " created successfully")
			}

			; 重新绑定热键
			DebugLogger.Log("Rebinding hotkeys...")
			for id, group in SkillManager.Groups {
				Hotkey(group.hotkey, ((id) => (*) => SkillManager.ToggleGroup(id))(id))
			}
		}
        
        ; 更新控制热键
        if (config.Has("CONTROL_HOTKEYS")) {
            ; 清除旧热键
            for action, hk in CONTROL_HOTKEYS {
                try {
                    Hotkey(hk, "Off")
                }
            }
            
            ; 更新并重新绑定
            newHotkeys := config["CONTROL_HOTKEYS"]
            for action, hk in newHotkeys {
                CONTROL_HOTKEYS[action] := hk
            }
            
            for action, hk in CONTROL_HOTKEYS {
                Hotkey(hk, ((action) => (*) => SkillManager.%action%())(action))
            }
        }
        
; 更新全局设置
	if (config.Has("HoldSettings")) {
		DebugLogger.Log("Processing HoldSettings...")
		newSettings := config["HoldSettings"]
		settingsObj := _MapToObject(newSettings)
		DebugLogger.Log("HoldSettings values with types:")
		DebugLogger.Log("  debounceDelay: type=" Type(settingsObj.debounceDelay) " value=" settingsObj.debounceDelay)
		DebugLogger.Log("  checkInterval: type=" Type(settingsObj.checkInterval) " value=" settingsObj.checkInterval)
		DebugLogger.Log("  allowOverlap: type=" Type(settingsObj.allowOverlap) " value=" settingsObj.allowOverlap)
		DebugLogger.Log("  pressSpeed: type=" Type(settingsObj.pressSpeed) " value=" settingsObj.pressSpeed)
		DebugLogger.Log("  releaseOnEmergency: type=" Type(settingsObj.releaseOnEmergency) " value=" settingsObj.releaseOnEmergency)
		DebugLogger.Log("Assigning to HoldSettings...")
		HoldSettings.debounceDelay := settingsObj.debounceDelay
		DebugLogger.Log("  debounceDelay assigned OK")
		HoldSettings.checkInterval := settingsObj.checkInterval
		DebugLogger.Log("  checkInterval assigned OK")
		HoldSettings.allowOverlap := settingsObj.allowOverlap
		DebugLogger.Log("  allowOverlap assigned OK")
		HoldSettings.pressSpeed := settingsObj.pressSpeed
		DebugLogger.Log("  pressSpeed assigned OK")
		HoldSettings.releaseOnEmergency := settingsObj.releaseOnEmergency
		DebugLogger.Log("  releaseOnEmergency assigned OK")
	}

		SkillManager.ActiveCount := 0
		DebugLogger.Log("=== HotReloadConfig SUCCESS ===")
		return true
	} catch as e {
		DebugLogger.Log("=== HotReloadConfig EXCEPTION ===")
		DebugLogger.Log("Message: " e.Message)
		DebugLogger.Log("File: " e.File)
		DebugLogger.Log("Line: " e.Line)
		DebugLogger.Log("Stack: " e.Stack)
		UIManager.ShowStatus("热重载失败: " e.Message, "error")
		return false
	}
}

; Map转Object辅助函数
_MapToObject(m) {
	obj := {}
	for key, value in m {
		if (value is Map) {
			obj.%key% := _MapToObject(value)
		} else if (value is Array) {
			obj.%key% := _ArrayToObject(value)
		} else {
			obj.%key% := value
		}
	}
	return obj
}

; Array中Map转Object辅助函数
_ArrayToObject(arr) {
	result := []
	for item in arr {
		if (item is Map) {
			result.Push(_MapToObject(item))
		} else if (item is Array) {
			result.Push(_ArrayToObject(item))
		} else {
			result.Push(item)
		}
	}
	return result
}

; 安全获取属性（兼容Map和Object）
_GetProp(obj, key, default := "") {
	if (obj is Map)
		return obj.Has(key) ? obj[key] : default
	else if (HasProp(obj, key))
		return obj.%key%
	return default
}

; 重置为默认配置
ResetToDefaultConfig() {
    global GroupSettings := Map(
        1, {
            hotkey: "F1",
            mode: "enhanced_sequence",
            pressKeys: ["Space", "4", "RButton"],
            pressDelays: [50, 50, 50]
        },
        2, {
            hotkey: "F2",
            mode: "sequence",
            keys: ["1", "2", "3", "q"],
            delays: [100, 100, 100, 100]
        },
        3, {
            hotkey: "F3",
            mode: "enhanced_periodic",
            pressKeys: ["space","1", "2", "3", "RButton", "space"],
            intervals: [50, 50, 50, 50, 50, 50],
            holdKeys: ["Shift"],
            holdMode: "continuous"
        },
        4, {
            hotkey: "F4",
            mode: "enhanced_hybrid",
            periodic: {
                pressKeys: ["Space"],
                intervals: [100]
            },
            sequence: {
                pressKeys: ["1", "2", "3", "4", "q"],
                delays: [100, 100, 100, 100, 100]
            },
            seqInterval: 100,
            holdKeys: ["Shift", "Ctrl"],
            holdMode: "continuous"
        },
        5, {
            hotkey: "F5",
            mode: "enhanced_periodic",
            pressKeys: ["5"],
            intervals: [50],
            holdKeys: ["Shift"],
            holdMode: "continuous"
        },
        6, {
            hotkey: "F6",
            mode: "hold",
            holdKeys: ["RButton"],
            holdDuration: 700,
            autoRepeat: false,
            repeatInterval: 1000
        }
    )
    
    global CONTROL_HOTKEYS := Map(
        "emergency", "f12",
        "toggleAll", "^1",
        "showStatus", "^0",
        "toggleHoldMode", "^h",
        "releaseAllHolds", "^r"
    )
    
    global HoldSettings := {
        debounceDelay: 20,
        checkInterval: 50,
        allowOverlap: false,
        pressSpeed: 80,
        releaseOnEmergency: true
    }
    
    UIManager.ShowStatus("已恢复默认配置", "info")
}

; =================================================================
; 第九部分: GUI入口
; =================================================================

^g:: {
    GUIManager.Show()
}

ShowMainWindow() {
    GUIManager.Show()
}

; =================================================================
; 第十部分: 启动提示
; =================================================================

; 自动加载配置（如果存在）
if FileExist("config.json") {
	try {
		ImportConfigFromJson("config.json")
	} catch as e {
		; 加载失败，使用默认配置并创建配置文件
		UIManager.ShowStatus("配置加载失败，使用默认配置", "warning")
		try {
			ExportConfigToJson("config.json")
		} catch {
			; 导出也失败，忽略
		}
	}
} else {
	; 配置文件不存在，创建默认配置文件
	try {
		ExportConfigToJson("config.json")
		UIManager.ShowStatus("已创建默认配置文件", "info")
	} catch as e {
		UIManager.ShowStatus("创建配置文件失败: " e.Message, "error")
	}
}

; 启动提示音
SoundBeep(500, 200)
Sleep(200)
SoundBeep(800, 150)

; 延迟显示欢迎消息
SetTimer(StartupToast, -800)

StartupToast() {
    UIManager.ShowStatus("系统就绪 | F1-F6切换分组 | Ctrl+G打开GUI", "success")
}

; =================================================================
; 结束: 增强版技能管理器代码
; =================================================================