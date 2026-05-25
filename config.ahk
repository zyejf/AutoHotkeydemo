; =================================================================
; ⚠ 全局配置变量唯一定义点
; 以下 global 变量仅在此文件中声明，其他文件通过 global 引用访问
; =================================================================

; =================================================================
; 全局配置数据 - 技能分组默认配置定义
; 版本: 1.0
; 说明: 定义 GroupSettings 全局 Map，包含各技能分组的默认热键、模式、按键配置
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

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
        ; groups 数组 - 新格式，支持多子组
        groups: [
            {
                type: "periodic",
                pressKeys: ["Space"],
                intervals: [100]
            },
            {
                type: "sequence",
                pressKeys: ["1", "2", "3", "4", "q"],
                delays: [100, 100, 100, 100, 100],
                seqInterval: 100
            }
        ],
        seqInterval: 100,
        ; 长按的按键
        holdKeys: ["Shift", "Ctrl"],
        ; 长按模式: 
        ;   "continuous" - 全程长按 (默认)
        ;   "sequence" - 在序列步骤中长按
        ;   "periodic" - 在周期性部分长按
        holdMode: "continuous",
        ; 按键按下持续时间 (毫秒，所有模式通用)
        keyPressDuration: 15
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