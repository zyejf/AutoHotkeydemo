; =================================================================
; 表现层 - GUI 管理器 + 全局设置编辑器 + 系统托盘
; 版本: 3.0
; 说明: 技能管理器主界面、全局设置编辑、系统托盘管理
;       依赖 GroupEditor / DebugPanel / BackupUI
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/skill_manager.ahk"
#Include "../lib/ahk2_lib/deepclone.ahk"
#Include "../application/config_service.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../application/backup_service.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "group_editor.ahk"
#Include "debug_panel.ahk"
#Include "backup_ui.ahk"

class GUIManager {
    static modeNames := Map(
        "periodic", "周期性",
        "sequence", "序列",
        "hybrid", "混合",
        "hold", "长按",
        "enhanced_periodic", "增强周期",
        "enhanced_sequence", "增强序列",
        "enhanced_hybrid", "增强混合",
        "joystick_periodic", "手柄周期",
        "joystick_sequence", "手柄序列",
        "joystick_hold", "手柄长按"
    )
    static gui := ""
    static controls := Map()
    static tray := ""
    static visible := false
    static _updateTimer := 0
    static _rowIndex := Map()

    static Show() {
        _DebugLog("GUIManager.Show START gui=" Type(GUIManager.gui))
        try {
            if GUIManager.gui {
                _DebugLog("GUIManager.Show: reusing existing gui")
                GUIManager.gui.Show("w600 h500")
                GUIManager.visible := true
                GUIManager._StartAutoUpdate()
                return
            }

            _DebugLog("GUIManager.Show: calling _BuildMainGUI")
            GUIManager._BuildMainGUI()
            GUIManager.visible := true
            GUIManager._StartAutoUpdate()
            GUIManager._RefreshGroupList()
            _DebugLog("GUIManager.Show: showing gui")
            GUIManager.gui.Show("w600 h500")
            _DebugLog("GUIManager.Show: DONE")
          } catch as e {
              _DebugLog("GUIManager.Show ERROR: " e.Message)
              MsgBox("显示主界面失败: " e.Message, "错误", "Icon!")
          }
    }

    static _BuildMainGUI() {
        GUIManager.gui := Gui("+Resize +MinSize550x450", "技能管理器 v3.0")
        GUIManager.gui.SetFont("s10", "Segoe UI")

        GUIManager.gui.Add("Text", "x15 y15 w200 h25", "分组列表:")
        GUIManager.controls["GroupLV"] := GUIManager.gui.Add("ListView", "x15 y45 w570 h300",
            ["ID", "热键", "模式", "状态"])

        GUIManager.controls["GroupLV"].OnEvent("DoubleClick", (*) => GUIManager._EditSelected())
        ; I5: OnEvent 静态方法引用必须用闭包包装，不能直接传递
        GUIManager.controls["GroupLV"].OnEvent("ContextMenu", (LV, item, isRightClick, *) => GUIManager._ShowContextMenu(LV, item, isRightClick))

        btnAdd := GUIManager.gui.Add("Button", "x15 y355 w100 h35", "添加分组")
        btnAdd.OnEvent("Click", (*) => (_DebugLog("btnAdd clicked"), GroupEditor.Open("", true)))

        btnEdit := GUIManager.gui.Add("Button", "x125 y355 w100 h35", "编辑")
        btnEdit.OnEvent("Click", (*) => (_DebugLog("btnEdit clicked"), GUIManager._EditSelected()))

        btnDelete := GUIManager.gui.Add("Button", "x235 y355 w100 h35", "删除")
        btnDelete.OnEvent("Click", (*) => GUIManager._DeleteSelected())

        btnToggle := GUIManager.gui.Add("Button", "x345 y355 w100 h35", "开关")
        btnToggle.OnEvent("Click", (*) => GUIManager._ToggleSelected())

        btnExport := GUIManager.gui.Add("Button", "x15 y400 w100 h35", "导出配置")
        btnExport.OnEvent("Click", (*) => GUIManager._ExportConfig())

        btnImport := GUIManager.gui.Add("Button", "x125 y400 w100 h35", "导入配置")
        btnImport.OnEvent("Click", (*) => GUIManager._ImportConfig())

        btnReload := GUIManager.gui.Add("Button", "x235 y400 w100 h35", "热重载")
        btnReload.OnEvent("Click", (*) => ConfigService.HotReload())

        btnGlobal := GUIManager.gui.Add("Button", "x345 y400 w100 h35", "全局设置")
        btnGlobal.OnEvent("Click", (*) => GlobalSettingsEditor.Open())

        btnBackup := GUIManager.gui.Add("Button", "x455 y355 w130 h35", "备份管理")
        btnBackup.OnEvent("Click", (*) => BackupUI.Show())

        btnDebug := GUIManager.gui.Add("Button", "x455 y400 w130 h35", "调试面板")
        btnDebug.OnEvent("Click", (*) => DebugPanel.Toggle())

        GUIManager.gui.OnEvent("Close", (*) => GUIManager._OnClose())
        GUIManager.gui.OnEvent("Escape", (*) => GUIManager._OnClose())

        GUIManager.controls["GroupLV"].ModifyCol(1, "40")
        GUIManager.controls["GroupLV"].ModifyCol(2, "80")
        GUIManager.controls["GroupLV"].ModifyCol(3, "120")
        GUIManager.controls["GroupLV"].ModifyCol(4, "200")
    }

    ; =================================================================
    ; 分组列表操作
    ; =================================================================
    static _RefreshGroupList() {
        LV := GUIManager.controls["GroupLV"]
        LV.Delete()
        GUIManager._rowIndex := Map()

        for id, group in SkillManager.Groups {
            modeDisplay := GUIManager.modeNames.Has(group.mode) ? GUIManager.modeNames[group.mode] : group.mode
            status := group.active ? "运行中" : "停止"
            idStr := String(id)

            LV.Add(, idStr, group.hotkey, modeDisplay, status)
            GUIManager._rowIndex[idStr] := LV.GetCount()
        }
    }

    static _EditSelected() {
        LV := GUIManager.controls["GroupLV"]
        selected := LV.GetNext()
        if selected = 0 {
            MsgBox("请先在列表中选择要编辑的分组", "提示", "Icon!")
            return
        }
        id := LV.GetText(selected, 1)
        GroupEditor.Open(id, false)
    }

    static _DeleteSelected() {
        try {
            LV := GUIManager.controls["GroupLV"]
            selected := LV.GetNext()
            if selected = 0 {
                MsgBox("请先在列表中选择要删除的分组", "提示", "Icon!")
                return
            }

            id := LV.GetText(selected, 1)
            result := MsgBox("确定要删除分组 " id " 吗？此操作不可撤销。", "确认删除", "YesNo Icon?")

            if result = "Yes" {
                GroupService.DeleteGroup(id)
                GUIManager._RefreshGroupList()
                SkillManager._Notify("分组 " id " 已删除", "warning")
            }
        } catch as e {
            MsgBox("删除失败: " e.Message, "错误", "Icon!")
        }
    }

    static _ToggleSelected() {
        try {
            LV := GUIManager.controls["GroupLV"]
            selected := LV.GetNext()
            if selected = 0 {
                MsgBox("请先在列表中选择要操作的分组", "提示", "Icon!")
                return
            }
            id := LV.GetText(selected, 1)
            SkillManager.ToggleGroup(id)
            Sleep(100)
            GUIManager._RefreshGroupList()
        } catch as e {
            MsgBox("操作失败: " e.Message, "错误", "Icon!")
        }
    }

    static _ShowContextMenu(LV, item, isRightClick, *) {
        if !isRightClick
            return

        selected := LV.GetNext()
        if selected = 0
            return

        menu := Menu()
        id := LV.GetText(selected, 1)
        menu.Add("编辑", (*) => GroupEditor.Open(id, false))
        menu.Add("复制", (*) => GUIManager._CopyGroup(id))
        menu.Add("删除", (*) => GUIManager._DeleteSelected())
        menu.Add("备份此分组", (*) => GUIManager._BackupGroup(id))
        menu.Show()
    }

    static _ExportConfig() {
        filePath := FileSelect("S16", "config_export.json", "导出配置文件", "JSON (*.json)")
        if filePath = ""
            return

        config := ConfigService.ConfigStore.Load()
        ExportConfigToFile(filePath, config)
        SkillManager._Notify("配置已导出到: " filePath, "success", 3000)
    }

    static _ImportConfig() {
        try {
            filePath := FileSelect(1, "", "导入配置文件", "JSON (*.json)")
            if filePath = ""
                return

            try {
                GroupService.ImportGroups(filePath)
                Sleep(100)
                GUIManager._RefreshGroupList()
                SkillManager._Notify("配置导入成功", "success", 3000)
            } catch as e {
                ErrorSystem.LogError("导入失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _BackupGroup(id) {
        config := ConfigService.ConfigStore.Load()
        groupConfig := ConfigService.ConfigStore.GetGroupConfig(id)
        backupLabel := "group_" id
        result := BackupService.CreateBackup(config, backupLabel)
    }

    static _CopyGroup(id) {
        config := ConfigService.ConfigStore.GetGroupConfig(id)
        if !config
            return

        clonedConfig := deepclone(config)

        maxId := 0
        for existingId in SkillManager.Groups {
            try {
                idNum := Integer(String(existingId))
                if idNum > maxId
                    maxId := idNum
            } catch {
                continue
            }
        }
        newId := String(maxId + 1)

        GroupService.CreateGroup(newId, clonedConfig)
        GUIManager._RefreshGroupList()
        SkillManager._Notify("分组 " id " 已复制为 " newId, "info")
    }

    static _StartAutoUpdate() {
        if GUIManager._updateTimer
            return
        GUIManager._updateTimer := () => GUIManager._AutoRefresh()
        SetTimer(GUIManager._updateTimer, 2000)
    }

    static _StopAutoUpdate() {
        if GUIManager._updateTimer {
            SetTimer(GUIManager._updateTimer, 0)
            GUIManager._updateTimer := 0
        }
    }

    static _OnClose() {
        GUIManager.visible := false
        GUIManager._StopAutoUpdate()
        GUIManager.gui.Hide()
    }

    static _AutoRefresh() {
        if !GUIManager.visible {
            GUIManager._StopAutoUpdate()
            return
        }
        LV := GUIManager.controls["GroupLV"]
        selected := LV.GetNext()

        needsRebuild := false
        for id, group in SkillManager.Groups {
            idStr := String(id)
            if GUIManager._rowIndex.Has(idStr) {
                rowIdx := GUIManager._rowIndex[idStr]
                if rowIdx > LV.GetCount() || LV.GetText(rowIdx, 1) != idStr {
                    needsRebuild := true
                    break
                }
            } else {
                needsRebuild := true
                break
            }
        }

        if needsRebuild {
            LV.Delete()
            GUIManager._rowIndex := Map()
            for id, group in SkillManager.Groups {
                modeDisplay := GUIManager.modeNames.Has(group.mode) ? GUIManager.modeNames[group.mode] : group.mode
                status := group.active ? "运行中" : "停止"
                idStr := String(id)
                LV.Add(, idStr, group.hotkey, modeDisplay, status)
                GUIManager._rowIndex[idStr] := LV.GetCount()
            }
        } else {
            for id, group in SkillManager.Groups {
                modeDisplay := GUIManager.modeNames.Has(group.mode) ? GUIManager.modeNames[group.mode] : group.mode
                status := group.active ? "运行中" : "停止"
                idStr := String(id)
                rowIdx := GUIManager._rowIndex[idStr]
                LV.Modify(rowIdx, , idStr, group.hotkey, modeDisplay, status)
            }
        }

        if selected > 0 && selected <= LV.GetCount()
            LV.Modify(selected, "Select")
    }
}

; =================================================================
; 全局设置编辑器
; =================================================================
class GlobalSettingsEditor {
    static gui := ""
    static controls := Map()

    static Open() {
        if GlobalSettingsEditor.gui {
            try
                GlobalSettingsEditor.gui.Destroy()
        }

        GlobalSettingsEditor.gui := Gui("+Resize +MinSize400x400", "全局设置")
        GlobalSettingsEditor.gui.SetFont("s10", "Segoe UI")

        ctrlHotkeys := ConfigService.ConfigStore.Get("CONTROL_HOTKEYS")
        holdSettings := ConfigService.ConfigStore.Get("HoldSettings")

        y := 15
        GlobalSettingsEditor.gui.Add("Text", "x15 y" y " w150 h25", "控制热键:")

        y += 30
        keyActions := ["emergency", "toggleAll", "showStatus", "toggleHoldMode", "releaseAllHolds"]
        labels := ["紧急停止:", "全局开关:", "显示状态:", "长按开关:", "释放长按:"]

        for i, action in keyActions {
            currentHotkey := ""
            if ctrlHotkeys is Map && ctrlHotkeys.Has(action)
                currentHotkey := ctrlHotkeys[action]

            gY := y + (i - 1) * 35
            GlobalSettingsEditor.gui.Add("Text", "x20 y" gY " w80 h25", labels[i])
            GlobalSettingsEditor.controls["hk_" action] := GlobalSettingsEditor.gui.Add("Edit", "x100 y" gY " w100 h25", currentHotkey)
        }

        y += 200
        GlobalSettingsEditor.gui.Add("Text", "x15 y" y " w150 h25", "长按设置:")

        y += 30
        GlobalSettingsEditor.gui.Add("Text", "x20 y" y " w100 h25", "防抖延迟:")
        debounceText := (holdSettings is Map || IsObject(holdSettings)) ? String(_GetProp(holdSettings, "debounceDelay", 20)) : "20"
        GlobalSettingsEditor.controls["hs_debounceDelay"] := GlobalSettingsEditor.gui.Add("Edit", "x130 y" y " w80 h25", debounceText)

        y += 35
        GlobalSettingsEditor.gui.Add("Text", "x20 y" y " w100 h25", "检查间隔:")
        checkText := (holdSettings is Map || IsObject(holdSettings)) ? String(_GetProp(holdSettings, "checkInterval", 50)) : "50"
        GlobalSettingsEditor.controls["hs_checkInterval"] := GlobalSettingsEditor.gui.Add("Edit", "x130 y" y " w80 h25", checkText)

        y += 35
        GlobalSettingsEditor.gui.Add("Text", "x20 y" y " w100 h25", "按键速率:")
        speedText := (holdSettings is Map || IsObject(holdSettings)) ? String(_GetProp(holdSettings, "pressSpeed", 80)) : "80"
        GlobalSettingsEditor.controls["hs_pressSpeed"] := GlobalSettingsEditor.gui.Add("Edit", "x130 y" y " w80 h25", speedText)

        y += 35
        allowOverlap := (holdSettings is Map || IsObject(holdSettings)) ? _GetProp(holdSettings, "allowOverlap", false) : false
        GlobalSettingsEditor.controls["hs_allowOverlap"] := GlobalSettingsEditor.gui.Add("CheckBox", "x20 y" y " w200 h25 Checked" (allowOverlap ? 1 : 0), "允许多组共享长按键")

        y += 35
        releaseOnEmergency := (holdSettings is Map || IsObject(holdSettings)) ? _GetProp(holdSettings, "releaseOnEmergency", true) : true
        GlobalSettingsEditor.controls["hs_releaseOnEmergency"] := GlobalSettingsEditor.gui.Add("CheckBox", "x20 y" y " w200 h25 Checked" (releaseOnEmergency ? 1 : 0), "紧急时释放长按")

        y += 45
        btnSave := GlobalSettingsEditor.gui.Add("Button", "x15 y" y " w100 h35", "保存")
        btnSave.OnEvent("Click", (*) => GlobalSettingsEditor._Save())

        btnCancel := GlobalSettingsEditor.gui.Add("Button", "x125 y" y " w100 h35", "取消")
        btnCancel.OnEvent("Click", (*) => GlobalSettingsEditor.gui.Destroy())
        GlobalSettingsEditor.gui.OnEvent("Close", (*) => GlobalSettingsEditor.gui.Destroy())
        GlobalSettingsEditor.gui.OnEvent("Escape", (*) => GlobalSettingsEditor.gui.Destroy())

        GlobalSettingsEditor.gui.Show("w400 h480")
    }

    static _Save() {
        try {
            controlHotkeys := ConfigService.ConfigStore.Get("CONTROL_HOTKEYS")
            if !(controlHotkeys is Map)
                controlHotkeys := Map()

            keyActions := ["emergency", "toggleAll", "showStatus", "toggleHoldMode", "releaseAllHolds"]
            for action in keyActions {
                editKey := "hk_" action
                if GlobalSettingsEditor.controls.Has(editKey)
                    controlHotkeys[action] := GlobalSettingsEditor.controls[editKey].Text
            }

            holdSettings := Map(
                "debounceDelay", Integer(GlobalSettingsEditor.controls["hs_debounceDelay"].Text),
                "checkInterval", Integer(GlobalSettingsEditor.controls["hs_checkInterval"].Text),
                "pressSpeed", Integer(GlobalSettingsEditor.controls["hs_pressSpeed"].Text),
                "allowOverlap", GlobalSettingsEditor.controls["hs_allowOverlap"].Value ? true : false,
                "releaseOnEmergency", GlobalSettingsEditor.controls["hs_releaseOnEmergency"].Value ? true : false
            )

            ConfigService.ConfigStore.Set("CONTROL_HOTKEYS", controlHotkeys)
            ConfigService.ConfigStore.Set("HoldSettings", holdSettings)

            ConfigService.SaveConfig()
            MsgBox("全局设置已保存", "成功", "Iconi")
            GlobalSettingsEditor.gui.Destroy()
        } catch as e {
            ErrorSystem.LogError("保存失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}

; =================================================================
; 系统托盘
; =================================================================
class TrayManager {
    static Init() {
        A_TrayMenu.Delete()

        A_TrayMenu.Add("打开主界面", (*) => GUIManager.Show())
        A_TrayMenu.Add("添加分组", (*) => GroupEditor.Open("", true))
        A_TrayMenu.Add("调试面板", (*) => DebugPanel.Toggle())
        A_TrayMenu.Add("备份管理", (*) => BackupUI.Show())

        A_TrayMenu.Add()
        ctrlHotkeys := ConfigService.ConfigStore.Get("CONTROL_HOTKEYS")

        A_TrayMenu.Add("全局开关", (*) => SkillManager.ToggleAll())
        A_TrayMenu.Add("紧急停止", (*) => SkillManager.Emergency())
        A_TrayMenu.Add("释放所有长按", (*) => SkillManager.ReleaseAllHolds())

        A_TrayMenu.Add()
        A_TrayMenu.Add("热重载配置", (*) => ConfigService.HotReload())
        A_TrayMenu.Add("查看运行状态", (*) => SkillManager.ShowStatus())

        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => ExitApp(0))

        A_IconTip := "技能管理器 v3.0 [DDD]"
    }
}

_DebugLog(msg) {
    try {
        FileAppend(A_Now " " msg "`n", "logs/debug.log", "UTF-8")
    } catch as e {
        ; best-effort: 调试日志写入失败不影响主流程
        OutputDebug("ASD [WARN] _DebugLog: " e.Message " at line " e.Line)
    }
    OutputDebug(A_Now " " msg)
}
