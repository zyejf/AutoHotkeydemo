; =================================================================
; 表现层 - 调试信息面板
; 版本: 3.0
; 说明: 实时显示技能管理器的运行状态和调试信息
;       支持性能数据展示
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../application/config_service.ahk"

class DebugPanel {
    static gui := ""
    static controls := Map()
    static _updateTimer := 0
    static visible := false

    static Toggle() {
        try {
            if DebugPanel.visible {
                DebugPanel.Hide()
            } else {
                DebugPanel.Show()
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static Show() {
        try {
            if DebugPanel.gui {
                DebugPanel.gui.Show()
                DebugPanel.visible := true
                DebugPanel._StartAutoUpdate()
                return
            }

            DebugPanel.gui := Gui("+Resize +MinSize500x300", "调试面板")
            DebugPanel.gui.SetFont("s10", "Consolas")

            DebugPanel.controls["Status"] := DebugPanel.gui.Add("Edit", "x10 y10 w480 h250 ReadOnly vEditStatus", "")
            DebugPanel.gui.OnEvent("Close", (*) => DebugPanel.Hide())
            DebugPanel.gui.OnEvent("Escape", (*) => DebugPanel.Hide())

            DebugPanel.visible := true
            DebugPanel._StartAutoUpdate()
            DebugPanel._UpdateDisplay()
            DebugPanel.gui.Show()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static Hide() {
        try {
            DebugPanel.visible := false
            if DebugPanel._updateTimer {
                SetTimer(DebugPanel._updateTimer, 0)
                DebugPanel._updateTimer := 0
            }
            if DebugPanel.gui {
                try
                    DebugPanel.gui.Hide()
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _StartAutoUpdate() {
        try {
            if DebugPanel._updateTimer
                return
            DebugPanel._updateTimer := () => DebugPanel._UpdateDisplay()
            SetTimer(DebugPanel._updateTimer, 1000)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _UpdateDisplay() {
        try {
            if !DebugPanel.visible || !DebugPanel.gui {
                if DebugPanel._updateTimer {
                    SetTimer(DebugPanel._updateTimer, 0)
                    DebugPanel._updateTimer := 0
                }
                return
            }

            info := "═══════════════════════════════════════════`r`n"
            info .= "     技能管理器调试面板`r`n"
            info .= "═══════════════════════════════════════════`r`n`r`n"

            info .= "系统状态:`r`n"
            info .= "  紧急模式: " (SkillManager.EmergencyMode ? " 是" : " 否") "`r`n"
            info .= "  活动分组: " SkillManager.GetActiveCount() " / " SkillManager.Groups.Count "`r`n"
            info .= "  长按启用: " (SkillManager.HoldModeEnabled ? " 是" : " 否") "`r`n"
            info .= "  长按注册: " SkillManager.HoldKeyRegistry.Count " 个键`r`n"
            info .= "  活跃定时器: " SkillManager.GetTimerCount() "`r`n`r`n"

            info .= "分组详情:`r`n"
            groupIds := []
            for id in SkillManager.Groups
                groupIds.Push(id)
            for id in groupIds {
                if !SkillManager.Groups.Has(id)
                    continue
                group := SkillManager.Groups[id]
                status := group.GetRuntimeStatus()
                activeStr := status["active"] ? "[活动]" : "[停止]"
                duration := status["runTime"] > 0 ? Format("{:.1f}s", status["runTime"] / 1000) : "0s"
                info .= "  分组" id ": " activeStr " 执行" status["executionCount"] "次 运行" duration
                if status["currentStep"] > 0
                    info .= " 步骤" status["currentStep"]
                info .= "`r`n"
            }

            ; BUG-6: 配置校验 WARNING 的展示出口。
            ; 校验器产出的可疑值告警此前只进日志、面板上看不到，补了告警也等于没补。
            ; 单独 try —— 渲染失败不应拖垮整个面板刷新。
            try {
                warnCount := ConfigService.LastValidationWarnings.Length
                info .= "`r`n配置告警: " (warnCount > 0 ? warnCount " 条" : "无") "`r`n"
                shown := 0
                for w in ConfigService.LastValidationWarnings {
                    shown++
                    if shown > 8 {
                        info .= "  … 另有 " (warnCount - 8) " 条`r`n"
                        break
                    }
                    msg := "（未知告警）"
                    if w is Map && w.Has("message")
                        msg := w["message"]
                    else if IsObject(w) && HasProp(w, "message")
                        msg := w.message
                    info .= "  - " msg "`r`n"
                }
            } catch as e {
                ErrorSystem.LogError("配置告警渲染失败: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
            }

            try
                DebugPanel.controls["Status"].Value := info
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}
