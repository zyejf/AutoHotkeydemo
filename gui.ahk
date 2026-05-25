; =================================================================
; GUI 模块 - 技能管理器图形界面
; 版本: 1.0
; 说明: 提供完整的图形界面，支持配置编辑、状态监控、备份管理
; =================================================================

#Requires AutoHotkey v2.0

global GUIModuleLoaded := true
global Menu, Gui

; =================================================================
; 第一部分: GUI状态管理
; =================================================================

class GUIState {
    static mainWindowX := 100
    static mainWindowY := 100
    static mainWindowW := 750
    static mainWindowH := 650
    static collapsedPanels := []
    static lastBackupTime := ""
    static selectedGroup := 1
    
    static stateFile := "gui_state.json"
    
    static Load() {
        if !FileExist(this.stateFile)
            return false
        
        try {
            state := JSONParser.LoadFile(this.stateFile)
            
            if (state.Has("mainWindow")) {
                win := state["mainWindow"]
                this.mainWindowX := win["x"]
                this.mainWindowY := win["y"]
                this.mainWindowW := win["width"]
                this.mainWindowH := win["height"]
            }
            
            if (state.Has("collapsedPanels"))
                this.collapsedPanels := state["collapsedPanels"]
            
            if (state.Has("lastBackupTime"))
                this.lastBackupTime := state["lastBackupTime"]
            
            if (state.Has("selectedGroup"))
                this.selectedGroup := state["selectedGroup"]
            
            return true
        } catch {
            return false
        }
    }
    
    static Save() {
        try {
            state := Map()
            state["mainWindow"] := Map(
                "x", this.mainWindowX,
                "y", this.mainWindowY,
                "width", this.mainWindowW,
                "height", this.mainWindowH
            )
            state["collapsedPanels"] := this.collapsedPanels
            state["lastBackupTime"] := this.lastBackupTime
            state["selectedGroup"] := this.selectedGroup
            state["savedAt"] := A_Now
            
            jsonStr := JSONSerializer.Stringify(state, 2)
            FileDelete(this.stateFile)
            FileAppend(jsonStr, this.stateFile, "UTF-8")
            return true
        } catch {
            return false
        }
    }
}

; =================================================================
; 第二部分: 备份管理器
; =================================================================

class BackupManager {
    static backupDir := "config_backup"
    static maxBackups := 10
    
    static Init() {
        if !InStr(FileExist(this.backupDir), "D")
            DirCreate(this.backupDir)
    }
    
    static CreateBackup(note := "") {
        this.Init()
        
        timestamp := StrReplace(StrReplace(A_Now, ":", ""), " ", "_")
        backupFile := this.backupDir "\config_" timestamp ".json"
        
        if FileExist("config.json") {
            try {
                FileCopy("config.json", backupFile)
                
                if (note != "") {
                    noteFile := backupFile ".note"
                    FileAppend(note, noteFile, "UTF-8")
                }
                
                GUIState.lastBackupTime := A_Now
                GUIState.Save()
                
                JSONLogger.Log(JSONError(
                    JSONErrorType.INFO_BACKUP_CREATED,
                    "配置已备份: " backupFile,
                    0, "", backupFile
                ))
                
                this._CleanupOldBackups()
                return backupFile
            } catch as e {
                UIManager.ShowStatus("备份失败: " e.Message, "error")
                return ""
            }
        }
        return ""
    }
    
    static ListBackups() {
        this.Init()
        backups := []
        
        try {
            Loop Files, this.backupDir "\config_*.json"
            {
                info := Map()
                info["file"] := A_LoopFileFullPath
                info["time"] := A_LoopFileTimeModified
                info["name"] := A_LoopFileName
                
                noteFile := A_LoopFileFullPath ".note"
                if FileExist(noteFile) {
                    try {
                        info["note"] := FileRead(noteFile, "UTF-8")
                    }
                }
                
                backups.Push(info)
            }
        }
        
        ; 按时间排序（最新的在前）
        for i in range(1, backups.Length - 1) {
            for j in range(i + 1, backups.Length) {
                if (backups[i]["time"] < backups[j]["time"]) {
                    temp := backups[i]
                    backups[i] := backups[j]
                    backups[j] := temp
                }
            }
        }
        
        return backups
    }
    
    static Restore(backupFile) {
        if !FileExist(backupFile) {
            UIManager.ShowStatus("备份文件不存在", "error")
            return false
        }
        
        try {
            ; 先备份当前配置
            this.CreateBackup("自动备份-恢复前")
            
            ; 恢复备份
            FileCopy(backupFile, "config.json", 1)
            
            ; 热重载
            result := ImportConfigFromJson("config.json")
            
            if (result) {
                UIManager.ShowStatus("配置已恢复", "success")
                return true
            }
            return false
        } catch as e {
            UIManager.ShowStatus("恢复失败: " e.Message, "error")
            return false
        }
    }
    
    static _CleanupOldBackups() {
        backups := this.ListBackups()
        
        while (backups.Length > this.maxBackups) {
            oldest := backups[backups.Length]
            try {
                FileDelete(oldest["file"])
                noteFile := oldest["file"] ".note"
                if FileExist(noteFile)
                    FileDelete(noteFile)
            }
            backups.Pop()
        }
    }
}

range(start, end) {
    arr := []
    for i in [start]
        arr.Push(i)
    loop end - start
        arr.Push(start + A_Index)
    return arr
}

; =================================================================
; 第三部分: 主窗口管理器
; =================================================================

class GUIManager {
    static gui := ""
    static controls := Map()
    static updateTimer := 0
    static isCreated := false
    
    static Show() {
        GUIState.Load()
        
        if !this.isCreated
            this._CreateWindow()
        
        this.gui.Show("x" GUIState.mainWindowX " y" GUIState.mainWindowY " w" GUIState.mainWindowW " h" GUIState.mainWindowH)
        this._RefreshAll()
        this._StartUpdateTimer()
    }
    
    static Hide() {
        if (this.gui)
            this.gui.Hide()
        this._StopUpdateTimer()
    }
    
    static _CreateWindow() {
        this.gui := Gui("+Resize", "🎮 技能管理器 v2.0")
        this.gui.SetFont("s10", "Microsoft YaHei UI")
        this.gui.BackColor := "F5F5F5"
        
        ; 菜单栏
        this._CreateMenuBar()
        
        ; 状态栏
        this._CreateStatusBar()
        
        ; 分组列表
        this._CreateGroupList()
        
        ; 详情面板
        this._CreateDetailPanel()
        
        ; 控制面板
        this._CreateControlPanel()
        
        ; 事件绑定
        this.gui.OnEvent("Close", (*) => this._OnClose())
        this.gui.OnEvent("Size", (g, m, w, h) => this._OnResize(w, h))
        
        this.isCreated := true
    }
    
    static _CreateMenuBar() {
        m := MenuBar()
        
        ; 文件菜单
        fileMenu := Menu()
        fileMenu.Add("打开配置文件", (*) => this._OpenConfigFile())
        fileMenu.Add("保存配置", (*) => this._SaveConfig())
        fileMenu.Add("另存为...", (*) => this._SaveConfigAs())
        fileMenu.Add()
        fileMenu.Add("创建备份", (*) => this._CreateBackup())
        fileMenu.Add("恢复备份...", (*) => BackupManager.ShowRestoreDialog())
        fileMenu.Add()
        fileMenu.Add("导出配置...", (*) => this._ExportConfig())
        fileMenu.Add("导入配置...", (*) => this._ImportConfig())
        fileMenu.Add()
        fileMenu.Add("重置为默认", (*) => this._ResetConfig())
        fileMenu.Add()
        fileMenu.Add("退出", (*) => this._OnClose())
        m.Add("文件(&F)", fileMenu)
        
        ; 编辑菜单
        editMenu := Menu()
        editMenu.Add("编辑分组1", (*) => GroupEditor.Edit(1))
        editMenu.Add("编辑分组2", (*) => GroupEditor.Edit(2))
        editMenu.Add("编辑分组3", (*) => GroupEditor.Edit(3))
        editMenu.Add("编辑分组4", (*) => GroupEditor.Edit(4))
        editMenu.Add("编辑分组5", (*) => GroupEditor.Edit(5))
        editMenu.Add("编辑分组6", (*) => GroupEditor.Edit(6))
        editMenu.Add()
        editMenu.Add("编辑热键设置", (*) => HotkeyEditor.Show())
        editMenu.Add("编辑全局设置", (*) => GlobalSettingsEditor.Show())
        m.Add("编辑(&E)", editMenu)
        
        ; 查看菜单
        viewMenu := Menu()
        viewMenu.Add("刷新状态", (*) => this._RefreshAll())
        viewMenu.Add("显示调试信息", (*) => this._ShowDebug())
        viewMenu.Add("查看错误日志", (*) => this._ShowErrorLog())
        m.Add("查看(&V)", viewMenu)
        
        ; 帮助菜单
        helpMenu := Menu()
        helpMenu.Add("使用帮助", (*) => this._ShowHelp())
        helpMenu.Add("关于", (*) => this._ShowAbout())
        m.Add("帮助(&H)", helpMenu)
        
        this.gui.MenuBar := m
    }
    
    static _CreateStatusBar() {
        this.controls["statusBar"] := this.gui.Add("Text", "x10 y10 w730 h30 +0x200 BackgroundFFFFFF", "状态: 加载中...")
    }
    
    static _CreateGroupList() {
        ; 分组列表标题
        this.gui.Add("GroupBox", "x10 y50 w350 h300", "📋 分组列表")
        
        ; ListView控件
        this.controls["groupList"] := this.gui.Add("ListView", "x20 y70 w330 h220 -Multi -Hdr", ["ID", "热键", "模式", "状态", "长按键"])
        
        ; 操作按钮
        this.controls["btnToggle"] := this.gui.Add("Button", "x20 y300 w100 h30", "启动/停止")
        this.controls["btnEdit"] := this.gui.Add("Button", "x130 y300 w100 h30", "编辑配置")
        this.controls["btnAdd"] := this.gui.Add("Button", "x240 y300 w100 h30", "添加新分组")
        
        ; 绑定事件
        this.controls["groupList"].OnEvent("ItemFocus", (ctrl, item) => this._OnGroupSelect(item))
        this.controls["btnToggle"].OnEvent("Click", (*) => this._ToggleSelectedGroup())
        this.controls["btnEdit"].OnEvent("Click", (*) => this._EditSelectedGroup())
        this.controls["btnAdd"].OnEvent("Click", (*) => this._AddNewGroup())
    }
    
    static _CreateDetailPanel() {
        ; 详情面板标题
        this.controls["detailBox"] := this.gui.Add("GroupBox", "x10 y360 w730 h130", "🔍 选中分组详情")
        
        ; 详情文本
        this.controls["detailText"] := this.gui.Add("Text", "x20 y380 w710 h100 BackgroundFFFFFF", "请选择一个分组查看详情")
    }
    
    static _CreateControlPanel() {
        ; 控制面板
        this.gui.Add("GroupBox", "x370 y50 w370 h300", "⚙️ 全局控制")
        
        ; 第一行按钮
        this.controls["btnStartAll"] := this.gui.Add("Button", "x380 y70 w110 h40", "全部启动")
        this.controls["btnStopAll"] := this.gui.Add("Button", "x500 y70 w110 h40", "全部停止")
        this.controls["btnEmergency"] := this.gui.Add("Button", "x620 y70 w110 h40", "紧急停止")
        
        ; 第二行按钮
        this.controls["btnReleaseHold"] := this.gui.Add("Button", "x380 y120 w110 h40", "释放长按键")
        this.controls["btnToggleHold"] := this.gui.Add("Button", "x500 y120 w110 h40", "切换长按")
        this.controls["btnShowStatus"] := this.gui.Add("Button", "x620 y120 w110 h40", "显示状态")
        
        ; 第三行 - 快捷操作
        this.gui.Add("Text", "x380 y180 w350", "──────────────────────────────────")
        this.gui.Add("Text", "x380 y200 w350", "快捷操作:")
        
        this.controls["btnSaveConfig"] := this.gui.Add("Button", "x380 y230 w170 h35", "💾 保存配置")
        this.controls["btnBackup"] := this.gui.Add("Button", "x560 y230 w170 h35", "📦 创建备份")
        
        ; 状态指示器
        this.gui.Add("Text", "x380 y280 w350 h50", "")
        this.controls["statusIndicator"] := this.gui.Add("Text", "x380 y280 w350 h50 +0x200 BackgroundFFFFFF", "")
        
        ; 绑定事件
        this.controls["btnStartAll"].OnEvent("Click", (*) => this._StartAllGroups())
        this.controls["btnStopAll"].OnEvent("Click", (*) => this._StopAllGroups())
        this.controls["btnEmergency"].OnEvent("Click", (*) => this._EmergencyStop())
        this.controls["btnReleaseHold"].OnEvent("Click", (*) => SkillManager.releaseAllHolds())
        this.controls["btnToggleHold"].OnEvent("Click", (*) => SkillManager.toggleHoldMode())
        this.controls["btnShowStatus"].OnEvent("Click", (*) => SkillManager.showStatus())
        this.controls["btnSaveConfig"].OnEvent("Click", (*) => this._SaveConfig())
        this.controls["btnBackup"].OnEvent("Click", (*) => this._CreateBackup())
    }
    
    static _RefreshAll() {
        this._UpdateStatusBar()
        this._UpdateGroupList()
        this._UpdateStatusIndicator()
        this._UpdateDetailPanel()
    }
    
    static _UpdateStatusBar() {
        if !SkillManager.EmergencyMode {
            status := "🟢 系统"
            if (SkillManager.ActiveCount > 0)
                status .= "运行中 (" SkillManager.ActiveCount "个分组)"
            else
                status .= "待机"
            
            status .= " | 长按: " (SkillManager.HoldModeEnabled ? "✅启用" : "⚪禁用")
        } else {
            status := "🔴 紧急停止模式"
        }
        
        this.controls["statusBar"].Value := status
    }
    
    static _UpdateGroupList() {
        LV := this.controls["groupList"]
        LV.Delete()
        
        modeNames := Map(
            "periodic", "周期",
            "sequence", "序列",
            "hybrid", "混合",
            "hold", "长按",
            "enhanced_periodic", "增强周期",
            "enhanced_sequence", "增强序列",
            "enhanced_hybrid", "增强混合"
        )
        
        for id, group in SkillManager.Groups {
            modeText := modeNames.Has(group.mode) ? modeNames[group.mode] : group.mode
            statusText := group.active ? "🟢运行" : "⚪停止"
            holdText := group.holdKeys.Length > 0 ? Join(group.holdKeys, ",") : "-"
            
            LV.Add("", id, group.hotkey, modeText, statusText, holdText)
        }
        
        LV.ModifyCol(1, 40)
        LV.ModifyCol(2, 60)
        LV.ModifyCol(3, 80)
        LV.ModifyCol(4, 70)
        LV.ModifyCol(5, 80)
        
        if (SkillManager.Groups.Count >= GUIState.selectedGroup)
            LV.Modify(GUIState.selectedGroup, "Focus Select")
    }
    
    static _UpdateStatusIndicator() {
        indicator := ""
        
        if (SkillManager.EmergencyMode) {
            indicator := '🔴 紧急停止已激活`n按F12或点击"全部启动"恢复'
        } else if (SkillManager.ActiveCount > 0) {
            indicator := "🟢 运行中: " SkillManager.ActiveCount " 个分组`n"
            
            if (SkillManager.HoldKeyRegistry.Count > 0) {
                heldKeys := []
                for key, groupId in SkillManager.HoldKeyRegistry
                    heldKeys.Push(key "(分组" groupId ")")
                indicator .= "长按: " Join(heldKeys, ", ")
            } else {
                indicator .= "无长按键激活"
            }
        } else {
            indicator := "⚪ 系统待机`n按F1-F6启动分组，或Ctrl+1启动全部"
        }
        
        this.controls["statusIndicator"].Value := indicator
    }
    
    static _UpdateDetailPanel() {
        if (GUIState.selectedGroup > SkillManager.Groups.Count) {
            this.controls["detailText"].Value := "请选择一个分组查看详情"
            return
        }
        
        group := SkillManager.Groups[GUIState.selectedGroup]
        status := group.GetRuntimeStatus()
        
        ; 构建详情文本
        detail := "分组" GUIState.selectedGroup " - [" group.hotkey "] - " this._GetModeDisplayName(group.mode) "`n`n"
        
        ; 运行状态
        if (status.active) {
            detail .= "状态: 🟢 运行中`n"
            detail .= "已执行: " status.executionCount " 次`n"
            detail .= "运行时间: " Round(status.runTime / 1000, 1) " 秒`n"
            if (status.currentStep > 0)
                detail .= "当前步骤: " status.currentStep "`n"
            if (status.heldKeys > 0)
                detail .= "长按键数: " status.heldKeys "`n"
            detail .= "`n"
        } else {
            detail .= "状态: ⚪ 待机`n"
            detail .= "总执行: " status.executionCount " 次`n`n"
        }
        
        ; 配置详情
        detail .= "─────────────────────────────────`n"
        detail .= "配置详情:`n"
        
        switch group.mode {
            case "periodic":
                detail .= "按键: " Join(group.keys, " → ") "`n"
                detail .= "间隔: " Join(group.intervals, ", ") " ms"
            case "sequence":
                detail .= "序列: " Join(group.keys, " → ") "`n"
                detail .= "延迟: " Join(group.delays, ", ") " ms"
            case "enhanced_periodic":
                detail .= "按键: " Join(group.pressKeys, " → ") "`n"
                detail .= "间隔: " Join(group.intervals, ", ") " ms`n"
                if (group.holdKeys.Length > 0)
                    detail .= "长按: " Join(group.holdKeys, ", ") " (" group.holdMode ")"
            case "enhanced_sequence":
                detail .= "序列: " Join(group.pressKeys, " → ") "`n"
                detail .= "延迟: " Join(group.pressDelays, ", ") " ms`n"
                if (group.holdKeys.Length > 0)
                    detail .= "长按: " Join(group.holdKeys, ", ") " (" group.holdMode ")"
            case "enhanced_hybrid":
                detail .= "周期: " Join(group.periodicPressKeys, " → ") "`n"
                detail .= "序列: " Join(group.seqPressKeys, " → ") "`n"
                if (group.holdKeys.Length > 0)
                    detail .= "长按: " Join(group.holdKeys, ", ")
            case "hold":
                detail .= "长按: " Join(group.holdKeys, ", ") "`n"
                detail .= "时长: " (group.holdDuration = 0 ? "无限" : group.holdDuration "ms") "`n"
                detail .= "重复: " (group.autoRepeat ? "是 (" group.repeatInterval "ms)" : "否")
            case "hybrid":
                detail .= "周期: " Join(group.periodicKeys, " → ") "`n"
                detail .= "序列: " Join(group.seqKeys, " → ")
        }
        
        this.controls["detailText"].Value := detail
    }
    
    static _GetModeDisplayName(mode) {
        modeNames := Map(
            "periodic", "周期性",
            "sequence", "序列",
            "hybrid", "混合",
            "hold", "长按",
            "enhanced_periodic", "增强周期",
            "enhanced_sequence", "增强序列",
            "enhanced_hybrid", "增强混合"
        )
        return modeNames.Has(mode) ? modeNames[mode] : mode
    }
    
    static _StartUpdateTimer() {
        this._StopUpdateTimer()
        this.updateTimer := SetTimer(() => this._RefreshAll(), 500)
    }
    
    static _StopUpdateTimer() {
        if (this.updateTimer) {
            SetTimer(this.updateTimer, 0)
            this.updateTimer := 0
        }
    }
    
    static _OnClose() {
        this._StopUpdateTimer()
        
        this.gui.GetPos(&x, &y, &w, &h)
        GUIState.mainWindowX := x
        GUIState.mainWindowY := y
        GUIState.mainWindowW := w
        GUIState.mainWindowH := h
        GUIState.Save()
        
        this.gui.Hide()
    }
    
    static _OnResize(w, h) {
    }
    
    static _OnGroupSelect(item) {
        if (item > 0) {
            GUIState.selectedGroup := item
            this._UpdateDetailPanel()
        }
    }
    
    static _ToggleSelectedGroup() {
        if (GUIState.selectedGroup > 0 && GUIState.selectedGroup <= SkillManager.Groups.Count)
            SkillManager.ToggleGroup(GUIState.selectedGroup)
    }
    
    static _EditSelectedGroup() {
        if (GUIState.selectedGroup > 0 && GUIState.selectedGroup <= SkillManager.Groups.Count)
            GroupEditor.Edit(GUIState.selectedGroup)
    }
    
static _AddNewGroup() {
		; 1. 生成新分组 ID
		newId := this._GenerateNewGroupId()

		; 2. 创建默认配置
		defaultConfig := this._CreateDefaultGroupConfig(newId)

		; 3. 临时保存到 GroupSettings
		GroupSettings[newId] := defaultConfig

		; 4. 创建 SkillGroup 实例
		SkillManager.Groups[newId] := SkillGroup(newId, defaultConfig)

		; 5. 标记为新建模式并打开编辑器
		GroupEditor.isNewGroup := true
		GroupEditor.Edit(newId)
	}

	static _GenerateNewGroupId() {
		maxId := 0
		for id, group in SkillManager.Groups {
			if (id > maxId)
				maxId := id
		}
		return maxId + 1
	}

	static _CreateDefaultGroupConfig(id) {
		; 尝试分配 F1-F12，寻找可用热键
		usedHotkeys := []
		for gid, group in SkillManager.Groups {
			usedHotkeys.Push(group.hotkey)
		}

		defaultHotkey := "F" id
		for i in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
			hk := "F" i
			if !this._ArrayContains(usedHotkeys, hk) {
				defaultHotkey := hk
				break
			}
		}

		return {hotkey: defaultHotkey, mode: "periodic", keys: ["Space"], intervals: [50]}
	}

	static _ArrayContains(arr, value) {
		for item in arr {
			if (item = value)
				return true
		}
		return false
	}

	static _StartAllGroups() {
        SkillManager.toggleAll()
    }
    
    static _StopAllGroups() {
        for id, group in SkillManager.Groups {
            if (group.active) {
                group.active := false
                group._ReleaseAllKeys()
            }
        }
        SkillManager.ActiveCount := 0
        UIManager.ShowBriefInfo(0, false)
    }
    
    static _EmergencyStop() {
        SkillManager.emergency()
    }
    
    static _SaveConfig() {
        ExportConfigToJson("config.json")
        BackupManager.CreateBackup("手动保存")
    }
    
    static _SaveConfigAs() {
        MsgBox("另存为功能开发中...", "提示", "Iconi")
    }
    
    static _ExportConfig() {
        path := FileSelect("S", "config.json", "导出配置文件", "JSON文件 (*.json)")
        if (path != "")
            ExportConfigToJson(path)
    }
    
    static _ImportConfig() {
        path := FileSelect(1, "config.json", "导入配置文件", "JSON文件 (*.json)")
        if (path != "")
            ImportConfigFromJson(path)
    }
    
    static _ResetConfig() {
        result := MsgBox("确定要重置为默认配置吗？`n当前配置将备份。", "确认重置", "YesNo Icon?")
        if (result = "Yes") {
            BackupManager.CreateBackup("重置前备份")
            ResetToDefaultConfig()
            ExportConfigToJson("config.json")
        }
    }
    
    static _OpenConfigFile() {
        if FileExist("config.json")
            Run("notepad.exe config.json")
        else
            MsgBox("配置文件不存在，请先保存配置", "提示", "Iconi")
    }
    
    static _CreateBackup() {
        note := InputBox("请输入备份备注（可选）", "创建备份", "w400 h150").Value
        result := BackupManager.CreateBackup(note)
        if (result)
            UIManager.ShowStatus("备份已创建: " result, "success")
    }
    
    static _ShowDebug() {
        Send("^+d")
    }
    
    static _ShowErrorLog() {
        logFile := JSONLogger.logFile
        if FileExist(logFile)
            Run("notepad.exe " logFile)
        else
            MsgBox("日志文件不存在", "提示", "Iconi")
    }
    
    static _ShowHelp() {
        Send("^+h")
    }
    
    static _ShowAbout() {
        MsgBox(
            "🎮 技能管理器 v2.0`n`n" .
            "功能: 多模式技能连招管理`n`n" .
            "特性:`n" .
            "• 支持周期、序列、混合等7种模式`n" .
            "• 支持长按功能`n" .
            "• 图形界面配置管理`n" .
            "• 配置备份与恢复`n`n" .
            "热键:`n" .
            "• F1-F6: 切换分组`n" .
            "• Ctrl+G: 打开GUI`n" .
            "• Ctrl+1: 全部开关`n" .
            "• F12: 紧急停止",
            "关于",
            "Iconi"
        )
    }
}

; =================================================================
; 第四部分: 分组配置编辑器 (重构版)
; =================================================================

class GroupEditor {
    ; 窗口和控件
    static gui := ""
static controls := Map()
	static editingGroup := 0
	static config := {}
	static isNewGroup := false ; 新建模式标记

	; Tab 控件相关
	static groups := [] ; 按键组数据数组
	static currentGroupIndex := 1 ; 当前选中的组索引
	static keyListBox := "" ; 当前组的按键列表
	static holdListBox := "" ; 长按按键列表

	; 常量
	static rowHeight := 30
	static noLimit := 999999 ; 无上限标记

	; 模式状态映射
	static modeStates := Map(
		"periodic", {groupType: "periodic", showHold: false, multiGroup: false, valueLabel: "间隔(ms)"},
		"sequence", {groupType: "sequence", showHold: false, multiGroup: false, valueLabel: "延迟(ms)"},
		"hybrid", {groupType: "hybrid", showHold: false, multiGroup: true, valueLabel: "值(ms)"},
		"enhanced_periodic", {groupType: "periodic", showHold: true, multiGroup: false, valueLabel: "间隔(ms)"},
		"enhanced_sequence", {groupType: "sequence", showHold: true, multiGroup: false, valueLabel: "延迟(ms)"},
		"enhanced_hybrid", {groupType: "hybrid", showHold: true, multiGroup: true, valueLabel: "值(ms)"},
		"hold", {groupType: "hold", showHold: false, multiGroup: false, valueLabel: ""}
	)
    
static Edit(groupId) {
		this.editingGroup := groupId
		this.groups := []
		this.controls := Map()
		this.currentGroupIndex := 1

		JSONLogger.LogDebug("GroupEditor", JSONErrorType.DEBUG_EDITOR_OPEN, "打开编辑器: groupId=" groupId)

		if !SkillManager.Groups.Has(groupId) {
			MsgBox("分组" groupId "不存在", "错误", "Iconx")
			return
		}

		this._LoadGroupConfig(groupId)
		this._CreateEditor()
		this._PopulateFields()
		
		; 根据是否为新建模式调整窗口标题
		if (this.isNewGroup)
			this.gui.Title := "新建分组配置"
		else
			this.gui.Title := "编辑分组" groupId "配置"
		
		this.gui.Show()
	}
    
    static _LoadGroupConfig(id) {
        group := GroupSettings[id]
        this.config := {}
        this.config.hotkey := group.hotkey
        this.config.mode := group.mode
        this.config.groups := []
        
        switch group.mode {
            case "periodic":
                this.config.groups := [{
                    type: "periodic",
                    keys: this._ZipKeysValues(group.keys, group.intervals),
                    seqInterval: 0
                }]
            case "sequence":
                this.config.groups := [{
                    type: "sequence",
                    keys: this._ZipKeysValues(group.keys, group.delays),
                    seqInterval: 100
                }]
            case "hybrid":
                this.config.groups := [
                    {type: "periodic", keys: this._ZipKeysValues(group.periodic.keys, group.periodic.intervals), seqInterval: 0},
                    {type: "sequence", keys: this._ZipKeysValues(group.sequence.keys, group.sequence.delays), seqInterval: group.seqInterval}
                ]
            case "enhanced_periodic":
                this.config.groups := [{
                    type: "periodic",
                    keys: this._ZipKeysValues(group.pressKeys, group.intervals),
                    seqInterval: 0
                }]
            case "enhanced_sequence":
                this.config.groups := [{
                    type: "sequence",
                    keys: this._ZipKeysValues(group.pressKeys, group.pressDelays),
                    seqInterval: 100
                }]
            case "enhanced_hybrid":
                this.config.groups := [
                    {type: "periodic", keys: this._ZipKeysValues(group.periodicPressKeys, group.periodicIntervals), seqInterval: 0},
                    {type: "sequence", keys: this._ZipKeysValues(group.seqPressKeys, group.seqDelays), seqInterval: group.seqInterval}
                ]
case "hold":
			this.config.groups := [{
				type: "hold",
				keys: this._MapArray(group.holdKeys, k => {key: k, value: 0}),
				seqInterval: 0
			}]
		}

		; 加载长按配置
		this.config.hold := {
			enabled: HasProp(group, "holdKeys") && group.holdKeys.Length > 0,
			mode: HasProp(group, "holdMode") ? group.holdMode : "continuous",
			keys: HasProp(group, "holdKeys") ? this._MapArray(group.holdKeys, k => {key: k, value: 0}) : [],
			duration: HasProp(group, "holdDuration") ? group.holdDuration : 0,
			autoRepeat: HasProp(group, "autoRepeat") ? group.autoRepeat : false,
			repeatInterval: HasProp(group, "repeatInterval") ? group.repeatInterval : 1000
		}
	}
    
    static _ZipKeysValues(keys, values) {
        result := []
        for i, key in keys {
            value := (i <= values.Length) ? values[i] : 50
            result.Push({key: key, value: value})
        }
        return result
    }
    
static _CreateEditor() {
        if (this.gui)
            this.gui.Destroy()
        this.controls := Map()
        
        this.gui := Gui("+Owner" GUIManager.gui.Hwnd, "编辑分组" this.editingGroup "配置")
        this.gui.SetFont("s10", "Microsoft YaHei UI")
        
        ; 基本设置区
        this.gui.Add("GroupBox", "x10 y10 w560 h90", "基本设置")
        this.gui.Add("Text", "x20 y30 w80", "激活热键:")
        this.controls["hotkey"] := this.gui.Add("Edit", "x110 y28 w100", this.config.hotkey)
        this.controls["btnRecordHotkey"] := this.gui.Add("Button", "x220 y28 w60", "录制")
        this.gui.Add("Text", "x20 y58 w80", "执行模式:")
        this.controls["mode"] := this.gui.Add("DropDownList", "x110 y56 w200", [
            "周期性",
            "序列",
            "混合",
            "增强周期",
            "增强序列",
            "增强混合",
            "纯长按"
        ])
        
        ; 按键配置区
        this.gui.Add("GroupBox", "x10 y110 w560 h370", "按键配置")
        this.controls["keyListBox"] := this.gui.Add("ListBox", "x20 y135 w530 h280", [])
        this.controls["keyListBox"].OnEvent("DoubleClick", (ctrl, item) => this._OnEditKey(item))
        
        ; 操作按钮
        this.controls["btnAddKey"] := this.gui.Add("Button", "x20 y420 w60", "添加")
        this.controls["btnEditKey"] := this.gui.Add("Button", "x90 y420 w60", "编辑")
        this.controls["btnDelKey"] := this.gui.Add("Button", "x160 y420 w60", "删除")
        this.controls["btnMoveUp"] := this.gui.Add("Button", "x230 y420 w60", "上移")
        this.controls["btnMoveDown"] := this.gui.Add("Button", "x300 y420 w60", "下移")
        this.controls["btnClearKeys"] := this.gui.Add("Button", "x370 y420 w60", "清空")
        
        ; 长按配置区
        this.gui.Add("GroupBox", "x10 y490 w560 h120", "长按配置")
        this.controls["holdEnabled"] := this.gui.Add("CheckBox", "x20 y510 w80", "启用长按")
        this.gui.Add("Text", "x110 y512 w60", "模式:")
        this.controls["holdMode"] := this.gui.Add("DropDownList", "x160 y510 w100", ["全程长按", "周期性", "序列式"])
        this.gui.Add("Text", "x270 y512 w60", "时长:")
        this.controls["holdDuration"] := this.gui.Add("Edit", "x320 y508 w60", "0")
        this.gui.Add("Text", "x385 y510 w50", "(0=无限)")
        this.controls["autoRepeat"] := this.gui.Add("CheckBox", "x20 y540 w80", "自动重复")
        this.gui.Add("Text", "x110 y542 w60", "间隔:")
        this.controls["repeatInterval"] := this.gui.Add("Edit", "x160 y538 w60", "1000")
        
        ; 底部按钮
        this.controls["btnOK"] := this.gui.Add("Button", "x180 y620 w100 h35", "确定")
        this.controls["btnCancel"] := this.gui.Add("Button", "x290 y620 w100 h35", "取消")
        this.controls["btnApply"] := this.gui.Add("Button", "x400 y620 w100 h35", "应用")
        
; 事件绑定
		this.controls["mode"].OnEvent("Change", (*) => this._OnModeChange())
		this.controls["btnRecordHotkey"].OnEvent("Click", (*) => this._RecordHotkey())
		this.controls["holdEnabled"].OnEvent("Click", (*) => this._OnHoldEnableChange())
		this.controls["holdMode"].OnEvent("Change", (*) => this._OnHoldModeChange())
		this.controls["autoRepeat"].OnEvent("Click", (*) => this._OnAutoRepeatChange())
		this.controls["btnAddKey"].OnEvent("Click", (*) => this._OnAddKey())
		this.controls["btnEditKey"].OnEvent("Click", (*) => this._OnEditKey(0))
		this.controls["btnDelKey"].OnEvent("Click", (*) => this._OnDeleteKey())
		this.controls["btnMoveUp"].OnEvent("Click", (*) => this._OnMoveUp())
		this.controls["btnMoveDown"].OnEvent("Click", (*) => this._OnMoveDown())
		this.controls["btnClearKeys"].OnEvent("Click", (*) => this._OnClearKeys())
		this.controls["btnOK"].OnEvent("Click", (*) => this._ApplyAndClose())
		this.controls["btnCancel"].OnEvent("Click", (*) => this._OnCancel())
		this.controls["btnApply"].OnEvent("Click", (*) => this._ApplyChanges())
		this.gui.OnEvent("Close", (*) => this._OnEditorClose())
	}
    
static _PopulateFields() {
        ; 设置模式下拉框
        modeMap := Map(
            "periodic", 1,
            "sequence", 2,
            "hybrid", 3,
            "enhanced_periodic", 4,
            "enhanced_sequence", 5,
            "enhanced_hybrid", 6,
            "hold", 7
        )
        if (modeMap.Has(this.config.mode))
            this.controls["mode"].Choose(modeMap[this.config.mode])
        
        ; 设置长按配置
        this.controls["holdEnabled"].Value := this.config.hold.enabled
        holdModeMap := Map("continuous", 1, "periodic", 2, "sequence", 3)
        if (holdModeMap.Has(this.config.hold.mode))
            this.controls["holdMode"].Choose(holdModeMap[this.config.hold.mode])
        this.controls["holdDuration"].Value := this.config.hold.duration
        this.controls["autoRepeat"].Value := this.config.hold.autoRepeat
        this.controls["repeatInterval"].Value := this.config.hold.repeatInterval
        
        ; 刷新按键列表
        this._RefreshKeyList()
        this._UpdateHoldControlsState()
    }
    
    static _RefreshKeyList() {
        this.controls["keyListBox"].Delete()
        if (this.config.groups.Length = 0)
            return
        
        group := this.config.groups[1]
        items := []
        for i, keyData in group.keys {
            displayText := keyData.key . " (" . keyData.value . "ms)"
            items.Push(displayText)
        }
        this.controls["keyListBox"].Add(items)
    }
    
static _OnAddKey() {
		DebugLogger.Log("_OnAddKey: START, groups.Length=" this.config.groups.Length)
		JSONLogger.LogDebug("GroupEditor", JSONErrorType.DEBUG_KEY_ADD, "添加按键")
		if (this.config.groups.Length = 0) {
			this.config.groups.Push({type: "periodic", keys: [], seqInterval: 0})
			DebugLogger.Log("_OnAddKey: created default group")
		}
		DebugLogger.Log("_OnAddKey: calling KeyEditDialog.Show with callback")
		KeyEditDialog.Show((key, value) => this._ApplyKeyEdit(0, key, value), "", 50, this._GetKeyList())
		DebugLogger.Log("_OnAddKey: KeyEditDialog.Show returned")
	}
    
static _OnEditKey(item) {
		DebugLogger.Log("_OnEditKey: START, item param=" item)
		if (this.config.groups.Length = 0) {
			DebugLogger.Log("_OnEditKey: no groups, returning")
			return
		}

		selectedIndex := this.controls["keyListBox"].Value
		DebugLogger.Log("_OnEditKey: selectedIndex=" selectedIndex)
		if (selectedIndex = 0) {
			DebugLogger.Log("_OnEditKey: no selection, returning")
			return
		}

		JSONLogger.LogDebug("GroupEditor", JSONErrorType.DEBUG_KEY_EDIT, "编辑按键: index=" selectedIndex)

		group := this.config.groups[1]
		DebugLogger.Log("_OnEditKey: group.keys.Length=" group.keys.Length)
		if (selectedIndex > group.keys.Length) {
			DebugLogger.Log("_OnEditKey: index out of range, returning")
			return
		}

		currentKey := group.keys[selectedIndex].key
		currentValue := group.keys[selectedIndex].value
		DebugLogger.Log("_OnEditKey: currentKey='" currentKey "' currentValue=" currentValue)
		DebugLogger.Log("_OnEditKey: calling KeyEditDialog.Show")
		KeyEditDialog.Show((key, value) => this._ApplyKeyEdit(selectedIndex, key, value), currentKey, currentValue, this._GetKeyList())
		DebugLogger.Log("_OnEditKey: KeyEditDialog.Show returned")
	}
    
    static _OnDeleteKey() {
        if (this.config.groups.Length = 0)
            return
        
        selectedIndex := this.controls["keyListBox"].Value
        if (selectedIndex = 0)
            return
        
        JSONLogger.LogDebug("GroupEditor", JSONErrorType.DEBUG_KEY_DELETE, "删除按键: index=" selectedIndex)
        
        group := this.config.groups[1]
        if (selectedIndex <= group.keys.Length) {
            group.keys.RemoveAt(selectedIndex)
            this._RefreshKeyList()
        }
    }
    
    static _OnMoveUp() {
        if (this.config.groups.Length = 0)
            return
        
        selectedIndex := this.controls["keyListBox"].Value
        if (selectedIndex <= 1)
            return
        
        group := this.config.groups[1]
        temp := group.keys[selectedIndex - 1]
        group.keys[selectedIndex - 1] := group.keys[selectedIndex]
        group.keys[selectedIndex] := temp
        this._RefreshKeyList()
        this.controls["keyListBox"].Choose(selectedIndex - 1)
    }
    
    static _OnMoveDown() {
        if (this.config.groups.Length = 0)
            return
        
        selectedIndex := this.controls["keyListBox"].Value
        group := this.config.groups[1]
        if (selectedIndex = 0 || selectedIndex >= group.keys.Length)
            return
        
        temp := group.keys[selectedIndex + 1]
        group.keys[selectedIndex + 1] := group.keys[selectedIndex]
        group.keys[selectedIndex] := temp
        this._RefreshKeyList()
        this.controls["keyListBox"].Choose(selectedIndex + 1)
    }
    
    static _OnClearKeys() {
        if (this.config.groups.Length > 0) {
            result := MsgBox("确定要清空所有按键吗？", "确认", "YesNo Icon?")
            if (result = "Yes") {
                this.config.groups[1].keys := []
                this._RefreshKeyList()
            }
        }
    }
    
static _ApplyKeyEdit(index, key, value) {
		DebugLogger.Log("_ApplyKeyEdit: START index=" index " key='" key "' value=" value)
		DebugLogger.Log("_ApplyKeyEdit: this.config type=" Type(this.config))
		DebugLogger.Log("_ApplyKeyEdit: this.config.groups type=" Type(this.config.groups))
		DebugLogger.Log("_ApplyKeyEdit: this.config.groups.Length=" this.config.groups.Length)
		
		if (this.config.groups.Length = 0) {
			this.config.groups.Push({type: "periodic", keys: [], seqInterval: 0})
			DebugLogger.Log("_ApplyKeyEdit: created default group")
		}

		group := this.config.groups[1]
		DebugLogger.Log("_ApplyKeyEdit: group type=" Type(group))
		DebugLogger.Log("_ApplyKeyEdit: group.keys type=" Type(group.keys))
		DebugLogger.Log("_ApplyKeyEdit: group.keys.Length=" group.keys.Length)
		
		if (index = 0) {
			group.keys.Push({key: key, value: value})
			DebugLogger.Log("_ApplyKeyEdit: pushed new key, total=" group.keys.Length)
		} else {
			group.keys[index].key := key
			group.keys[index].value := value
			DebugLogger.Log("_ApplyKeyEdit: updated key at index " index)
		}
		this._RefreshKeyList()
		DebugLogger.Log("_ApplyKeyEdit: DONE")
	}

static _OnModeChange(*) {
		oldMode := this.config.mode
		this.config.mode := this._GetModeValue()
		JSONLogger.LogDebug("GroupEditor", JSONErrorType.DEBUG_MODE_CHANGE, "切换模式: " oldMode " -> " this.config.mode)
		this._RebuildGroupsForMode()
		this._UpdateHoldControlsState()
		this._RefreshKeyList()
	}

	static _RebuildGroupsForMode() {
		currentKeys := []
		if (this.config.groups.Length > 0 && HasProp(this.config.groups[1], "keys")) {
			if (IsObject(this.config.groups[1].keys) && this.config.groups[1].keys is Array) {
				currentKeys := this.config.groups[1].keys.Clone()
			}
		}
		this.config.groups := [{
			type: this.config.mode,
			keys: currentKeys,
			seqInterval: 100
		}]
	}

static _GetModeValue() {
		idx := this.controls["mode"].Value
		modes := ["periodic", "sequence", "hybrid", "enhanced_periodic", "enhanced_sequence", "enhanced_hybrid", "hold"]
		return idx > 0 ? modes[idx] : "periodic"
	}

	static _MapArray(arr, mapper) {
		result := []
		if !IsObject(arr)
			return result
		for item in arr
			result.Push(mapper(item))
		return result
	}

	static _ExtractProperty(arr, propName) {
		result := []
		if !IsObject(arr)
			return result
		for item in arr
			if HasProp(item, propName)
				result.Push(item.%propName%)
		return result
	}

	static _UpdateHoldControlsState() {
        modeIdx := this.controls["mode"].Value
        if (modeIdx < 1)
            return
        
        modes := ["periodic", "sequence", "hybrid", "enhanced_periodic", "enhanced_sequence", "enhanced_hybrid", "hold"]
        currentMode := modes[modeIdx]
        
        isHoldMode := (currentMode = "hold")
        isEnhancedMode := InStr(currentMode, "enhanced_")
        
        this.controls["holdEnabled"].Enabled := !isHoldMode
        this.controls["holdEnabled"].Value := isHoldMode ? true : this.controls["holdEnabled"].Value
        
        if (isHoldMode) {
            this.controls["holdMode"].Enabled := false
            this.controls["holdDuration"].Enabled := true
            this.controls["autoRepeat"].Enabled := true
            this.controls["repeatInterval"].Enabled := this.controls["autoRepeat"].Value
        } else if (isEnhancedMode) {
            holdEnabled := this.controls["holdEnabled"].Value
            this.controls["holdMode"].Enabled := holdEnabled
            this.controls["holdDuration"].Enabled := false
            this.controls["autoRepeat"].Enabled := false
            this.controls["repeatInterval"].Enabled := false
        } else {
            this.controls["holdEnabled"].Enabled := false
            this.controls["holdMode"].Enabled := false
            this.controls["holdDuration"].Enabled := false
            this.controls["autoRepeat"].Enabled := false
            this.controls["repeatInterval"].Enabled := false
        }
    }
    
    static _OnHoldEnableChange(*) {
        this._UpdateHoldControlsState()
    }
    
    static _OnHoldModeChange(*) {
    }
    
    static _OnAutoRepeatChange(*) {
        this.controls["repeatInterval"].Enabled := this.controls["autoRepeat"].Value
    }
    
    static _RecordHotkey() {
        this.gui.Opt("+Disabled")
        UIManager.ShowStatus("请按下新的热键...", "info")
        SetTimer(() => this._DoRecordHotkey(), -100)
    }
    
    static _DoRecordHotkey() {
        try {
            InputHookObj := InputHook("V L1 T5", "{Esc}")
            InputHookObj.Start()
            InputHookObj.Wait()
            
            if (InputHookObj.EndReason = "Max" || InputHookObj.EndReason = "EndKey") {
                key := GetKeyName(InputHookObj.EndKey)
                if (key != "") {
                    this.controls["hotkey"].Value := key
                    UIManager.ShowStatus("已录制热键: " key, "success")
                }
            }
        } catch {
            UIManager.ShowStatus("录制失败，请手动输入", "warning")
        }
        this.gui.Opt("-Disabled")
    }
    
    static _ApplyChanges() {
try {
		this.config.hotkey := this.controls["hotkey"].Value
		this.config.mode := this._GetModeValue()

		; 收集长按配置
		this.config.hold.enabled := this.controls["holdEnabled"].Value
		holdModeMap := ["continuous", "periodic", "sequence"]
		this.config.hold.mode := holdModeMap[this.controls["holdMode"].Value]
		this.config.hold.duration := Integer(this.controls["holdDuration"].Value)
		this.config.hold.autoRepeat := this.controls["autoRepeat"].Value
		this.config.hold.repeatInterval := Integer(this.controls["repeatInterval"].Value)

		if !this._ValidateConfig() {
			JSONLogger.LogWarning("GroupEditor", "W001", "配置验证失败: groupId=" this.editingGroup)
			MsgBox("配置验证失败，请检查输入", "错误", "Iconx")
			return false
		}

		this._ApplyToGroupSettings()
		
		; 新建模式：绑定热键
		if (this.isNewGroup) {
			Hotkey(this.config.hotkey, ((id) => (*) => SkillManager.ToggleGroup(id))(this.editingGroup))
			this.isNewGroup := false
		}
		
		ExportConfigToJson()
		GUIManager._RefreshAll()
		JSONLogger.LogDebug("GroupEditor", JSONErrorType.DEBUG_CONFIG_SAVE, "保存配置成功: groupId=" this.editingGroup)
		UIManager.ShowStatus("分组" this.editingGroup "配置已保存", "success")
		return true
	} catch as e {
		MsgBox("应用失败: " e.Message, "错误", "Iconx")
		return false
	}
}

static _ValidateConfig() {
	if (this.config.hotkey = "") {
		MsgBox("请输入热键", "错误", "Icon!")
		return false
	}

	; 检测热键冲突
	for id, group in SkillManager.Groups {
		if (id != this.editingGroup && group.hotkey = this.config.hotkey) {
			result := MsgBox("热键 '" this.config.hotkey "' 已被分组 " id " 使用`n是否继续？", "热键冲突", "YesNo Icon?")
			if (result != "Yes")
				return false
			break
		}
	}

	hasKeys := false
	if (this.config.groups.Length > 0) {
		hasKeys := this.config.groups[1].keys.Length > 0
	}

	if !hasKeys && this.config.mode != "hold" {
		MsgBox("请至少添加一个按键", "错误", "Icon!")
		return false
	}

	return true
}
    
static _ApplyToGroupSettings() {
		newConfig := {}
		newConfig.hotkey := this.config.hotkey
		newConfig.mode := this.config.mode

		if (this.config.groups.Length > 0) {
			group := this.config.groups[1]
			keys := []
			values := []
			if (HasProp(group, "keys") && IsObject(group.keys) && group.keys is Array) {
				keys := this._ExtractProperty(group.keys, "key")
				values := this._ExtractProperty(group.keys, "value")
			}

			switch this.config.mode {
			case "periodic":
				newConfig.keys := keys
				newConfig.intervals := values
			case "sequence":
				newConfig.keys := keys
				newConfig.delays := values
			case "hybrid":
				newConfig.periodic := {keys: keys, intervals: values}
				newConfig.sequence := {keys: [], delays: []}
				newConfig.seqInterval := 100
			case "enhanced_periodic":
				newConfig.pressKeys := keys
				newConfig.intervals := values
			case "enhanced_sequence":
				newConfig.pressKeys := keys
				newConfig.pressDelays := values
			case "enhanced_hybrid":
				newConfig.periodicPressKeys := keys
				newConfig.periodicIntervals := values
				newConfig.seqPressKeys := []
				newConfig.seqDelays := []
				newConfig.seqInterval := 100
			case "hold":
				newConfig.holdKeys := keys
				newConfig.holdDuration := this.config.hold.duration
				newConfig.autoRepeat := this.config.hold.autoRepeat
				newConfig.repeatInterval := this.config.hold.repeatInterval
			}

; 长按配置（非 hold 模式）
		if (this.config.mode != "hold" && this.config.hold.enabled) {
			if (HasProp(this.config.hold, "keys") && IsObject(this.config.hold.keys) && this.config.hold.keys is Array) {
				newConfig.holdKeys := this._ExtractProperty(this.config.hold.keys, "key")
				newConfig.holdMode := this.config.hold.mode
			}
		}
	}

		GroupSettings[this.editingGroup] := newConfig
		SkillManager.Groups[this.editingGroup] := SkillGroup(this.editingGroup, newConfig)
	}
    
    static _GetKeyList() {
        return [
            "Space", "Enter", "Escape", "Tab", "Backspace",
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            "LButton", "RButton", "MButton", "XButton1", "XButton2",
            "LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt",
            "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn",
            "Insert", "Delete", "CapsLock", "NumLock", "ScrollLock"
        ]
    }
    
static _ApplyAndClose() {
		if (this._ApplyChanges()) {
			this.isNewGroup := false
			this.gui.Destroy()
		}
	}

	static _OnCancel() {
		this._OnEditorClose()
	}

	static _OnEditorClose() {
		if (this.isNewGroup) {
			try {
				if (GroupSettings.Has(this.editingGroup))
					GroupSettings.Delete(this.editingGroup)
				if (SkillManager.Groups.Has(this.editingGroup))
					SkillManager.Groups.Delete(this.editingGroup)
			} catch {
			}
			this.isNewGroup := false
			GUIManager._RefreshAll()
		}
		this.gui.Destroy()
	}
}

; =================================================================
; KeyEditDialog - 按键编辑对话框
; =================================================================

class KeyEditDialog {
    static gui := ""
    static keyCtrl := ""
    static valueCtrl := ""
    static callback := ""
    
static Show(callback, currentKey, currentValue, keyList) {
		DebugLogger.Log("KeyEditDialog.Show: START")
		DebugLogger.Log("KeyEditDialog.Show: callback type=" Type(callback))
		DebugLogger.Log("KeyEditDialog.Show: currentKey='" currentKey "' currentValue=" currentValue)
		DebugLogger.Log("KeyEditDialog.Show: keyList count=" keyList.Length)
		KeyEditDialog.callback := callback
		DebugLogger.Log("KeyEditDialog.Show: callback assigned, type now=" Type(KeyEditDialog.callback))

		if (KeyEditDialog.gui)
			KeyEditDialog.gui.Destroy()

		KeyEditDialog.gui := Gui("+Owner" GroupEditor.gui.Hwnd, "编辑按键")
		KeyEditDialog.gui.SetFont("s10", "Microsoft YaHei UI")

		KeyEditDialog.gui.Add("Text", "x20 y20 w60", "按键:")
		KeyEditDialog.keyCtrl := KeyEditDialog.gui.Add("ComboBox", "x80 y18 w150", keyList)

		KeyEditDialog.gui.Add("Text", "x20 y50 w60", "间隔:")
		KeyEditDialog.valueCtrl := KeyEditDialog.gui.Add("Edit", "x80 y48 w100", String(currentValue))
		KeyEditDialog.gui.Add("Text", "x185 y50 w30", "ms")

		KeyEditDialog.gui.Add("Button", "x50 y80 w80", "确定").OnEvent("Click", (*) => KeyEditDialog._OnOK())
		KeyEditDialog.gui.Add("Button", "x140 y80 w80", "取消").OnEvent("Click", (*) => KeyEditDialog.gui.Destroy())

		; 设置当前值
		if (currentKey != "") {
			for i, k in keyList {
				if (StrLower(k) = StrLower(currentKey)) {
					KeyEditDialog.keyCtrl.Choose(i)
					break
				}
			}
		}

		KeyEditDialog.gui.OnEvent("Close", (*) => KeyEditDialog.gui.Destroy())
		DebugLogger.Log("KeyEditDialog.Show: showing dialog")
		KeyEditDialog.gui.Show()
	}
    
static _OnOK() {
		key := KeyEditDialog.keyCtrl.Text
		value := 50
		try {
			value := Integer(KeyEditDialog.valueCtrl.Value)
		} catch {
		}

		DebugLogger.Log("KeyEditDialog._OnOK: key='" key "' value=" value)
		DebugLogger.Log("KeyEditDialog._OnOK: callback type=" Type(KeyEditDialog.callback))
		DebugLogger.Log("KeyEditDialog._OnOK: IsObject(callback)=" IsObject(KeyEditDialog.callback))

		if (key != "" && IsObject(KeyEditDialog.callback)) {
			DebugLogger.Log("KeyEditDialog._OnOK: about to call callback")
			try {
				KeyEditDialog.callback(key, value)
				DebugLogger.Log("KeyEditDialog._OnOK: callback returned successfully")
			} catch as e {
				DebugLogger.Log("KeyEditDialog._OnOK: callback threw error - " e.Message)
				DebugLogger.Log("KeyEditDialog._OnOK: error file=" e.File " line=" e.Line)
				MsgBox("回调错误: " e.Message, "错误", "Iconx")
			}
		}
		KeyEditDialog.gui.Destroy()
	}
}

; =================================================================
; 第五部分: 热键编辑器
; =================================================================

class HotkeyEditor {
    static gui := ""
    
    static Show() {
        if (this.gui)
            this.gui.Destroy()
        
        this.gui := Gui("+Owner" GUIManager.gui.Hwnd, "热键设置")
        this.gui.SetFont("s10", "Microsoft YaHei UI")
        
        this.gui.Add("GroupBox", "x10 y10 w300 h200", "控制热键")
        
        hotkeys := [
            ["紧急停止", "emergency", CONTROL_HOTKEYS["emergency"]],
            ["切换全部", "toggleAll", CONTROL_HOTKEYS["toggleAll"]],
            ["显示状态", "showStatus", CONTROL_HOTKEYS["showStatus"]],
            ["切换长按", "toggleHoldMode", CONTROL_HOTKEYS["toggleHoldMode"]],
            ["释放长按", "releaseAllHolds", CONTROL_HOTKEYS["releaseAllHolds"]]
        ]
        
        for i, hk in hotkeys {
            this.gui.Add("Text", "x20 y" 30 + (i-1) * 35, hk[1] ":")
            this.gui.Add("Edit", "x120 y" 28 + (i-1) * 35 " w100", hk[3])
        }
        
        this.gui.Add("Button", "x50 y220 w100", "确定")
        this.gui.Add("Button", "x160 y220 w100", "取消")
        
        this.gui.Show()
    }
}

; =================================================================
; 第六部分: 全局设置编辑器
; =================================================================

class GlobalSettingsEditor {
    static gui := ""
    
    static Show() {
        if (this.gui)
            this.gui.Destroy()
        
        this.gui := Gui("+Owner" GUIManager.gui.Hwnd, "全局设置")
        this.gui.SetFont("s10", "Microsoft YaHei UI")
        
        this.gui.Add("GroupBox", "x10 y10 w300 h200", "长按功能设置")
        
        this.gui.Add("Text", "x20 y30", "防抖延迟(ms):")
        this.gui.Add("Edit", "x150 y28 w80", HoldSettings.debounceDelay)
        
        this.gui.Add("Text", "x20 y60", "检查频率(ms):")
        this.gui.Add("Edit", "x150 y58 w80", HoldSettings.checkInterval)
        
        this.gui.Add("Text", "x20 y90", "按键速度(1-100):")
        this.gui.Add("Edit", "x150 y88 w80", HoldSettings.pressSpeed)
        
        this.gui.Add("CheckBox", "x20 y120 w280", "允许多分组长按同一键", HoldSettings.allowOverlap ? "Checked" : "")
        this.gui.Add("CheckBox", "x20 y150 w280", "紧急停止时释放长按键", HoldSettings.releaseOnEmergency ? "Checked" : "")
        
        this.gui.Add("Button", "x50 y220 w100", "确定")
        this.gui.Add("Button", "x160 y220 w100", "取消")
        
        this.gui.Show()
    }
}

; =================================================================
; 第七部分: 托盘管理器
; =================================================================

class TrayManager {
    static iconState := "normal"
    static groupMenu := false

    static Init() {
        A_TrayMenu.Delete()

        A_TrayMenu.Add("打开主窗口", (*) => GUIManager.Show())
        A_TrayMenu.Add()
        A_TrayMenu.Add("分组控制", (*) => this._ShowGroupMenu())
        A_TrayMenu.Add()
        A_TrayMenu.Add("全部启动", (*) => SkillManager.toggleAll())
        A_TrayMenu.Add("全部停止", (*) => GUIManager._StopAllGroups())
        A_TrayMenu.Add("紧急停止", (*) => SkillManager.emergency())
        A_TrayMenu.Add()
        A_TrayMenu.Add("创建备份", (*) => GUIManager._CreateBackup())
        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => ExitApp())

        A_TrayMenu.Default := "打开主窗口"

        SetTimer(() => this._UpdateTrayIcon(), 1000)
    }

    static _ShowGroupMenu(*) {
        if (!this.groupMenu) {
            this.groupMenu := Menu()
            this._PopulateGroupMenu()
        }
        this.groupMenu.Show()
    }

    static _PopulateGroupMenu() {
        for id, group in SkillManager.Groups {
            status := group.active ? "✓" : " "
            this.groupMenu.Add(status " 分组" id " [" group.hotkey "]", ((id) => (*) => SkillManager.ToggleGroup(id))(id))
        }
    }

    static _UpdateTrayIcon() {
        newState := "normal"

        if (SkillManager.EmergencyMode)
            newState := "error"
        else if (SkillManager.ActiveCount > 0)
            newState := "running"

        if (newState != this.iconState) {
            this.iconState := newState
        }
    }
}

; =================================================================
; 第八部分: 初始化
; =================================================================

TrayManager.Init()

JSONLogger.Log(JSONError(
    "I001",
    "GUI模块已加载",
    0, "", ""
))

; =================================================================
; 结束: GUI模块
; =================================================================
