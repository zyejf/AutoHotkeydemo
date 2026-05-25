; =================================================================
; 表现层 - 分组编辑器 V5.1 + 按键选择器 + 热键编辑器
; 版本: 5.1
; 说明: 现代化分组编辑界面，支持7种模式、按键选择器、
;       输入验证、执行预览、快捷操作
;       依赖领域层 SkillManager 和应用层 GroupService
;       所有 GUI 控件位置参数使用双引号包围
; 修复: Choose索引、JSON引用、回填数据、删除重渲染、布局重叠
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../application/group_service.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/error_system.ahk"

class GroupEditor {
    static gui := ""
    static controls := Map()
    static currentId := ""
    static isNew := false
    static currentMode := "enhanced_periodic"
    static modeControls := Map()
    static subGroups := []
    static activeSubIdx := 1
    static savedConfig := ""

    static MODE_DISPLAY_TO_KEY := Map(
        "周期性", "periodic", "序列", "sequence", "增强周期", "enhanced_periodic",
        "增强序列", "enhanced_sequence", "混合", "hybrid", "增强混合", "enhanced_hybrid", "长按", "hold"
    )

    static MODE_KEY_TO_DISPLAY := Map(
        "periodic", "周期性", "sequence", "序列", "enhanced_periodic", "增强周期",
        "enhanced_sequence", "增强序列", "hybrid", "混合", "enhanced_hybrid", "增强混合", "hold", "长按"
    )

    static MODE_DDL_ITEMS := ["周期性", "序列", "增强周期", "增强序列", "混合", "增强混合", "长按"]

    static Open(id := "", isNew := false) {
        try {
            GroupEditor.isNew := isNew
            GroupEditor.currentId := id
            GroupEditor.savedConfig := ""

            if GroupEditor.gui {
                try
                    GroupEditor.gui.Destroy()
            }

            title := isNew ? "添加新分组" : "编辑分组 " (id != "" ? id : "")
            GroupEditor.gui := Gui("+Resize +MinSize540x700", title)
            GroupEditor.gui.SetFont("s9", "Segoe UI")
            GroupEditor.gui.OnEvent("Close", (*) => GroupEditor._Close())
            GroupEditor.gui.OnEvent("Escape", (*) => GroupEditor._Close())

            GroupEditor._BuildUI(id, isNew)

            if !isNew && id != "" {
                config := GroupService.ConfigStore.GetGroupConfig(id)
                if config {
                    GroupEditor.savedConfig := config
                    GroupEditor._PopulateForm(config)
                }
            }

            GroupEditor.gui.Show("w560 h720")
        } catch as e {
            MsgBox("打开编辑器失败: " e.Message, "错误", "Icon!")
        }
    }

    static _Close() {
        try
            GroupEditor.gui.Destroy()
        GroupEditor.gui := ""
        GroupEditor.controls := Map()
        GroupEditor.modeControls := Map()
        GroupEditor.subGroups := []
        GroupEditor.savedConfig := ""
    }

    static _BuildUI(id, isNew) {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 12

        g.Add("GroupBox", "x10 y" y " w540 h130", "基本信息")
        y += 20

        g.Add("Text", "x20 y" y " w60 h22", "ID:")
        c["IdEdit"] := g.Add("Edit", "x80 y" y " w70 h22", id != "" ? id : "")
        if !isNew
            c["IdEdit"].Enabled := false
        y += 28

        g.Add("Text", "x20 y" y " w60 h22", "热键:")
        c["HotkeyBtn"] := g.Add("Button", "x80 y" y " w120 h26", "点击设置热键")
        c["HotkeyBtn"].OnEvent("Click", (*) => GroupEditor._OpenHotkeyEditor())
        c["HotkeyHint"] := g.Add("Text", "x210 y" y+3 " w200 h20", "点击后按键设置")
        y += 32

        g.Add("Text", "x20 y" y " w60 h22", "模式:")
        c["ModeDDL"] := g.Add("DropDownList", "x80 y" y " w150 h200 Choose3",
            GroupEditor.MODE_DDL_ITEMS)
        c["ModeDDL"].OnEvent("Change", (*) => GroupEditor._OnModeChange())

        c["modeGroupBox"] := g.Add("GroupBox", "x10 y150 w540 h350", "按键配置")
        GroupEditor._RenderModeContent()

        GroupEditor._BuildPreviewSection()
        GroupEditor._BuildFooter()
    }

    ; =================================================================
    ; 模式切换
    ; =================================================================
    static _OnModeChange() {
        modeName := GroupEditor.controls["ModeDDL"].Text
        mode := GroupEditor.MODE_DISPLAY_TO_KEY.Has(modeName) ? GroupEditor.MODE_DISPLAY_TO_KEY[modeName] : "enhanced_periodic"
        GroupEditor.currentMode := mode
        GroupEditor.savedConfig := ""
        GroupEditor._ClearModeControls()
        GroupEditor._RenderModeContent()
        GroupEditor._UpdatePreview()
    }

    static _ClearModeControls() {
        for name, ctrl in GroupEditor.modeControls {
            try
                ctrl.Destroy()
        }
        GroupEditor.modeControls := Map()
    }

    static _RenderModeContent(config := "") {
        mode := GroupEditor.currentMode

        switch mode {
            case "periodic": GroupEditor._RenderSimpleMode("间隔", false, config)
            case "sequence": GroupEditor._RenderSimpleMode("延迟", false, config)
            case "enhanced_periodic": GroupEditor._RenderSimpleMode("间隔", true, config)
            case "enhanced_sequence": GroupEditor._RenderSimpleMode("延迟", true, config)
            case "hybrid": GroupEditor._RenderHybridMode(false, config)
            case "enhanced_hybrid": GroupEditor._RenderHybridMode(true, config)
            case "hold": GroupEditor._RenderHoldMode(config)
        }
    }

    ; =================================================================
    ; 简单模式（周期性/序列/增强周期/增强序列）
    ; =================================================================
    static _RenderSimpleMode(timeLabel, hasHold, config := "") {
        g := GroupEditor.gui
        c := GroupEditor.modeControls
        y := 172

        c["keyTableHeader"] := g.Add("Text", "x20 y" y " w60 h18", "按键")
        c["timeTableHeader"] := g.Add("Text", "x120 y" y " w80 h18", timeLabel " (ms)")
        y += 22

        c["keyRows"] := []

        if config != "" {
            keys := GroupEditor._GetConfigKeys(config, GroupEditor.currentMode)
            times := GroupEditor._GetConfigTimes(config, GroupEditor.currentMode, timeLabel)
        } else {
            keys := ["Space", "1", "2"]
            times := [50, 100, 100]
        }

        for i, key in keys {
            interval := (i <= times.Length) ? times[i] : 50
            GroupEditor._AddSimpleKeyRow(y, key, interval)
            y += 28
        }

        c["addKeyBtn"] := g.Add("Button", "x20 y" y " w120 h24", "+ 添加按键")
        c["addKeyBtn"].OnEvent("Click", (*) => GroupEditor._AddSimpleKeyRowAction())

        if hasHold {
            y += 34
            c["holdKeysLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按键:")
            holdVal := ""
            if config != ""
                holdVal := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
            c["holdKeysEdit"] := g.Add("Edit", "x80 y" y " w200 h22", holdVal)
            g.Add("Text", "x290 y" y+3 " w180 h18", "如 Shift, Ctrl（逗号分隔）")
            y += 26
            c["holdModeLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按模式:")
            holdModeVal := 1
            if config != "" {
                hm := _GetProp(config, "holdMode", "continuous")
                holdModeVal := (hm = "continuous") ? 1 : 2
            }
            c["holdModeDDL"] := g.Add("DropDownList", "x80 y" y " w120 h200 Choose" holdModeVal, ["持续按住", "周期按压"])
        }
    }

    static _GetConfigKeys(config, mode) {
        switch mode {
            case "periodic", "sequence":
                return _GetProp(config, "keys", [])
            case "enhanced_periodic", "enhanced_sequence":
                return _GetProp(config, "pressKeys", [])
            default:
                return []
        }
    }

    static _GetConfigTimes(config, mode, timeLabel) {
        switch mode {
            case "periodic":
                return _GetProp(config, "intervals", [])
            case "sequence":
                return _GetProp(config, "delays", [])
            case "enhanced_periodic":
                return _GetProp(config, "intervals", [])
            case "enhanced_sequence":
                return _GetProp(config, "pressDelays", [])
            default:
                return []
        }
    }

    static _AddSimpleKeyRow(y, key, interval) {
        c := GroupEditor.modeControls
        rows := c["keyRows"]
        rowIdx := rows.Length + 1
        prefix := "kr" rowIdx "_"
        g := GroupEditor.gui

        c[prefix "keyBtn"] := g.Add("Button", "x20 y" y " w90 h24", key != "" ? key : "点击选择")
        c[prefix "keyBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._OpenKeyPickerForSimpleRow(ri))(rowIdx))

        c[prefix "intervalEdit"] := g.Add("Edit", "x120 y" y " w70 h22", String(interval))
        c[prefix "msLabel"] := g.Add("Text", "x195 y" y+3 " w30 h18", "ms")

        c[prefix "delBtn"] := g.Add("Button", "x230 y" y " w24 h24", "X")
        c[prefix "delBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._DeleteSimpleKeyRow(ri))(rowIdx))

        rows.Push({idx: rowIdx, key: key, interval: interval})
    }

    static _AddSimpleKeyRowAction() {
        GroupEditor._ReRenderSimpleRows()
        c := GroupEditor.modeControls
        rows := c["keyRows"]
        y := 194 + rows.Length * 28
        GroupEditor._AddSimpleKeyRow(y, "", 50)
        c["addKeyBtn"].Move(, 194 + rows.Length * 28)
        GroupEditor._UpdatePreview()
    }

    static _DeleteSimpleKeyRow(rowIdx) {
        c := GroupEditor.modeControls
        rows := c["keyRows"]

        i := rows.Length
        while i >= 1 {
            if rows[i].idx = rowIdx {
                rows.RemoveAt(i)
                break
            }
            i--
        }
        GroupEditor._ReRenderSimpleRows()
        GroupEditor._UpdatePreview()
    }

    static _ReRenderSimpleRows() {
        c := GroupEditor.modeControls
        if !c.Has("keyRows")
            return
        rows := c["keyRows"]

        for row in rows {
            prefix := "kr" row.idx "_"
            if c.Has(prefix "intervalEdit") {
                try
                    row.interval := Integer(c[prefix "intervalEdit"].Text)
                catch
                    row.interval := row.interval
            }
            if c.Has(prefix "keyBtn") {
                btnText := c[prefix "keyBtn"].Text
                if btnText != "" && btnText != "点击选择"
                    row.key := btnText
            }
        }

        for row in rows {
            prefix := "kr" row.idx "_"
            if c.Has(prefix "keyBtn")
                try c[prefix "keyBtn"].Destroy()
            if c.Has(prefix "intervalEdit")
                try c[prefix "intervalEdit"].Destroy()
            if c.Has(prefix "msLabel")
                try c[prefix "msLabel"].Destroy()
            if c.Has(prefix "delBtn")
                try c[prefix "delBtn"].Destroy()
            c.Delete(prefix "keyBtn")
            c.Delete(prefix "intervalEdit")
            c.Delete(prefix "msLabel")
            c.Delete(prefix "delBtn")
        }

        g := GroupEditor.gui
        y := 194
        newRows := []
        for i, row in rows {
            prefix := "kr" i "_"
            keyText := row.key != "" ? row.key : "点击选择"

            c[prefix "keyBtn"] := g.Add("Button", "x20 y" y " w90 h24", keyText)
            c[prefix "keyBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._OpenKeyPickerForSimpleRow(ri))(i))

            c[prefix "intervalEdit"] := g.Add("Edit", "x120 y" y " w70 h22", String(row.interval))
            c[prefix "msLabel"] := g.Add("Text", "x195 y" y+3 " w30 h18", "ms")

            c[prefix "delBtn"] := g.Add("Button", "x230 y" y " w24 h24", "X")
            c[prefix "delBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._DeleteSimpleKeyRow(ri))(i))

            newRows.Push({idx: i, key: row.key, interval: row.interval})
            y += 28
        }
        c["keyRows"] := newRows

        if c.Has("addKeyBtn")
            c["addKeyBtn"].Move(, y)

        holdY := y + 28
        if c.Has("holdKeysLabel") {
            c["holdKeysLabel"].Move(, holdY)
            c["holdKeysEdit"].Move(, holdY)
            if c.Has("holdKeysHint")
                c["holdKeysHint"].Move(, holdY + 3)
            holdY += 26
            c["holdModeLabel"].Move(, holdY)
            c["holdModeDDL"].Move(, holdY)
        }
    }

    static _OpenKeyPickerForSimpleRow(rowIdx) {
        GroupEditor.gui.Opt("+Disabled")
        KeyPicker.Open((key) => GroupEditor._OnKeyPickedForSimpleRow(rowIdx, key))
    }

    static _OnKeyPickedForSimpleRow(rowIdx, key) {
        c := GroupEditor.modeControls
        prefix := "kr" rowIdx "_"
        if c.Has(prefix "keyBtn") {
            c[prefix "keyBtn"].Text := key
            rows := c["keyRows"]
            for row in rows {
                if row.idx = rowIdx {
                    row.key := key
                    break
                }
            }
        }
        GroupEditor.gui.Opt("-Disabled")
        GroupEditor._UpdatePreview()
    }

    ; =================================================================
    ; 混合模式（hybrid / enhanced_hybrid）
    ; =================================================================
    static _RenderHybridMode(isEnhanced, config := "") {
        g := GroupEditor.gui
        c := GroupEditor.modeControls

        if config != "" {
            GroupEditor._LoadHybridFromConfig(config)
        } else if GroupEditor.subGroups.Length = 0 {
            GroupEditor.subGroups := [
                {type: "periodic", keys: ["m", "a"], intervals: [50, 50], delays: [], seqInterval: 100},
                {type: "sequence", keys: ["1", "2", "3", "4"], intervals: [], delays: [200, 220, 240, 2500], seqInterval: 100}
            ]
        }
        GroupEditor.activeSubIdx := 1

        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()

        if isEnhanced {
            holdY := c.Has("_subContentEndY") ? c["_subContentEndY"] + 10 : 460
            c["ehyHoldKeysLabel"] := g.Add("Text", "x20 y" holdY " w60 h20", "长按键:")
            holdVal := ""
            if config != ""
                holdVal := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
            c["ehyHoldKeysEdit"] := g.Add("Edit", "x80 y" holdY " w200 h22", holdVal)
            c["ehyHoldKeysHint"] := g.Add("Text", "x290 y" holdY+3 " w180 h18", "如 Shift, Ctrl（逗号分隔）")
        }
    }

    static _RepositionHybridHoldKeys() {
        c := GroupEditor.modeControls
        if !c.Has("ehyHoldKeysLabel")
            return
        holdY := c.Has("_subContentEndY") ? c["_subContentEndY"] + 10 : 460
        c["ehyHoldKeysLabel"].Move(, holdY)
        c["ehyHoldKeysEdit"].Move(, holdY)
        if c.Has("ehyHoldKeysHint")
            c["ehyHoldKeysHint"].Move(, holdY + 3)
    }

    static _LoadHybridFromConfig(config) {
        groups := _GetProp(config, "groups", [])
        if groups.Length = 0 {
            GroupEditor.subGroups := [
                {type: "periodic", keys: ["m", "a"], intervals: [50, 50], delays: [], seqInterval: 100},
                {type: "sequence", keys: ["1", "2", "3", "4"], intervals: [], delays: [200, 220, 240, 2500], seqInterval: 100}
            ]
            return
        }

        GroupEditor.subGroups := []
        for g in groups {
            subType := _GetProp(g, "type", "periodic")
            sub := {type: subType, keys: _GetProp(g, "pressKeys", []), intervals: [], delays: [], seqInterval: _GetProp(g, "seqInterval", 100)}
            if subType = "sequence"
                sub.delays := _GetProp(g, "delays", [])
            else
                sub.intervals := _GetProp(g, "intervals", [])
            GroupEditor.subGroups.Push(sub)
        }
    }

    static _RenderSubTabs() {
        c := GroupEditor.modeControls
        for name, ctrl in c {
            if InStr(name, "subTab_") = 1 {
                try ctrl.Destroy()
                c.Delete(name)
            }
        }
        if c.Has("addSubBtn") {
            try c["addSubBtn"].Destroy()
            c.Delete("addSubBtn")
        }

        g := GroupEditor.gui
        x := 20
        for i, sub in GroupEditor.subGroups {
            tabName := "subTab_" i
            c[tabName] := g.Add("Button", "x" x " y174 w70 h24", "子组 " i)
            c[tabName].OnEvent("Click", ((idx) => (*) => GroupEditor._SwitchSub(idx))(i))
            if i = GroupEditor.activeSubIdx
                c[tabName].SetFont("bold")
            x += 74
        }

        c["addSubBtn"] := g.Add("Button", "x" x " y174 w24 h24", "+")
        c["addSubBtn"].OnEvent("Click", (*) => GroupEditor._AddSubGroup())
    }

    static _SwitchSub(idx) {
        GroupEditor._SyncSubGroupData()
        GroupEditor.activeSubIdx := idx
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }

    static _AddSubGroup() {
        GroupEditor._SyncSubGroupData()
        GroupEditor.subGroups.Push({type: "periodic", keys: [], intervals: [], delays: [], seqInterval: 100})
        GroupEditor.activeSubIdx := GroupEditor.subGroups.Length
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }

    static _RemoveSubGroup(idx) {
        if GroupEditor.subGroups.Length <= 1 {
            MsgBox("至少保留一个子组", "提示", "Icon!")
            return
        }
        GroupEditor._SyncSubGroupData()
        GroupEditor.subGroups.RemoveAt(idx)
        if GroupEditor.activeSubIdx > GroupEditor.subGroups.Length
            GroupEditor.activeSubIdx := GroupEditor.subGroups.Length
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }

    static _SyncSubGroupData() {
        idx := GroupEditor.activeSubIdx
        if idx < 1 || idx > GroupEditor.subGroups.Length
            return
        c := GroupEditor.modeControls
        sub := GroupEditor.subGroups[idx]

        if c.Has("sub_typeDDL") {
            typeName := c["sub_typeDDL"].Text
            sub.type := (typeName = "序列") ? "sequence" : "periodic"
        }

        newKeys := []
        newTimes := []
        for i, key in sub.keys {
            prefix := "sub_row_" i "_"
            if c.Has(prefix "keyBtn") && c[prefix "keyBtn"].Text != "" && c[prefix "keyBtn"].Text != "点击选择"
                newKeys.Push(c[prefix "keyBtn"].Text)
            else if key != ""
                newKeys.Push(key)
            else
                newKeys.Push("")

            if c.Has(prefix "timeEdit") {
                try
                    newTimes.Push(Integer(c[prefix "timeEdit"].Text))
                catch
                    newTimes.Push(50)
            } else
                newTimes.Push(50)
        }

        sub.keys := newKeys
        if sub.type = "sequence"
            sub.delays := newTimes
        else
            sub.intervals := newTimes

        if c.Has("sub_seqIntervalEdit") {
            try
                sub.seqInterval := Integer(c["sub_seqIntervalEdit"].Text)
            catch
                sub.seqInterval := 100
        }
    }

    static _RenderSubContent() {
        c := GroupEditor.modeControls
        for name, ctrl in c {
            if InStr(name, "sub_") = 1 {
                try ctrl.Destroy()
                c.Delete(name)
            }
        }

        g := GroupEditor.gui
        idx := GroupEditor.activeSubIdx
        if idx < 1 || idx > GroupEditor.subGroups.Length
            return

        sub := GroupEditor.subGroups[idx]
        y := 206

        c["sub_typeLabel"] := g.Add("Text", "x20 y" y " w40 h20", "类型:")
        c["sub_typeDDL"] := g.Add("DropDownList", "x60 y" y " w90 h200 Choose" (sub.type = "sequence" ? 2 : 1), ["周期性", "序列"])
        c["sub_typeDDL"].OnEvent("Change", (*) => GroupEditor._OnSubTypeChange())

        c["sub_removeBtn"] := g.Add("Button", "x160 y" y " w60 h22", "删除子组")
        c["sub_removeBtn"].OnEvent("Click", (*) => GroupEditor._RemoveSubGroup(idx))
        y += 28

        timeLabel := sub.type = "sequence" ? "延迟" : "间隔"
        c["sub_keyHeader"] := g.Add("Text", "x20 y" y " w60 h18", "按键")
        c["sub_timeHeader"] := g.Add("Text", "x120 y" y " w80 h18", timeLabel " (ms)")
        y += 22

        times := sub.type = "sequence" ? sub.delays : sub.intervals
        for i, key in sub.keys {
            interval := (i <= times.Length) ? times[i] : 50
            prefix := "sub_row_" i "_"
            c[prefix "keyBtn"] := g.Add("Button", "x20 y" y " w90 h24", key != "" ? key : "点击选择")
            c[prefix "keyBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._OpenKeyPickerForSubRow(ri))(i))
            c[prefix "timeEdit"] := g.Add("Edit", "x120 y" y " w70 h22", String(interval))
            c[prefix "msLabel"] := g.Add("Text", "x195 y" y+3 " w30 h18", "ms")
            c[prefix "delBtn"] := g.Add("Button", "x230 y" y " w24 h24", "X")
            c[prefix "delBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._DeleteSubKeyRow(ri))(i))
            y += 28
        }

        c["sub_addRowBtn"] := g.Add("Button", "x20 y" y " w120 h24", "+ 添加按键")
        c["sub_addRowBtn"].OnEvent("Click", (*) => GroupEditor._AddSubKeyRow())

        if sub.type = "sequence" {
            y += 30
            c["sub_seqIntervalLabel"] := g.Add("Text", "x20 y" y " w70 h20", "循环间隔:")
            c["sub_seqIntervalEdit"] := g.Add("Edit", "x90 y" y " w70 h22", String(_GetProp(sub, "seqInterval", 100)))
            c["sub_seqMsLabel"] := g.Add("Text", "x165 y" y+3 " w30 h18", "ms")
            y += 30
        }

        c["_subContentEndY"] := y
        GroupEditor._RepositionHybridHoldKeys()
    }

    static _OnSubTypeChange() {
        idx := GroupEditor.activeSubIdx
        if idx < 1 || idx > GroupEditor.subGroups.Length
            return
        typeName := GroupEditor.modeControls["sub_typeDDL"].Text
        newType := (typeName = "序列") ? "sequence" : "periodic"
        if GroupEditor.subGroups[idx].type != newType {
            GroupEditor.subGroups[idx].type := newType
            if newType = "sequence" {
                GroupEditor.subGroups[idx].delays := GroupEditor.subGroups[idx].intervals.Clone()
                GroupEditor.subGroups[idx].intervals := []
            } else {
                GroupEditor.subGroups[idx].intervals := GroupEditor.subGroups[idx].delays.Clone()
                GroupEditor.subGroups[idx].delays := []
            }
        }
        GroupEditor._RenderSubContent()
    }

    static _OpenKeyPickerForSubRow(rowIdx) {
        GroupEditor.gui.Opt("+Disabled")
        KeyPicker.Open((key) => GroupEditor._OnKeyPickedForSubRow(rowIdx, key))
    }

    static _OnKeyPickedForSubRow(rowIdx, key) {
        prefix := "sub_row_" rowIdx "_keyBtn"
        if GroupEditor.modeControls.Has(prefix)
            GroupEditor.modeControls[prefix].Text := key
        idx := GroupEditor.activeSubIdx
        if idx >= 1 && idx <= GroupEditor.subGroups.Length && rowIdx >= 1 && rowIdx <= GroupEditor.subGroups[idx].keys.Length
            GroupEditor.subGroups[idx].keys[rowIdx] := key
        GroupEditor.gui.Opt("-Disabled")
    }

    static _AddSubKeyRow() {
        GroupEditor._SyncSubGroupData()
        idx := GroupEditor.activeSubIdx
        if idx < 1 || idx > GroupEditor.subGroups.Length
            return
        sub := GroupEditor.subGroups[idx]
        sub.keys.Push("")
        if sub.type = "sequence"
            sub.delays.Push(50)
        else
            sub.intervals.Push(50)
        GroupEditor._RenderSubContent()
    }

    static _DeleteSubKeyRow(rowIdx) {
        GroupEditor._SyncSubGroupData()
        idx := GroupEditor.activeSubIdx
        if idx < 1 || idx > GroupEditor.subGroups.Length
            return
        sub := GroupEditor.subGroups[idx]
        sub.keys.RemoveAt(rowIdx)
        if sub.type = "sequence" && rowIdx <= sub.delays.Length
            sub.delays.RemoveAt(rowIdx)
        else if rowIdx <= sub.intervals.Length
            sub.intervals.RemoveAt(rowIdx)
        GroupEditor._RenderSubContent()
    }

    ; =================================================================
    ; 长按模式
    ; =================================================================
    static _RenderHoldMode(config := "") {
        g := GroupEditor.gui
        c := GroupEditor.modeControls
        y := 172

        holdVal := ""
        durationVal := "0"
        autoRepeatVal := 0
        repeatIntervalVal := "1000"

        if config != "" {
            holdVal := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
            durationVal := String(_GetProp(config, "holdDuration", 0))
            autoRepeatVal := _GetProp(config, "autoRepeat", false) ? 1 : 0
            repeatIntervalVal := String(_GetProp(config, "repeatInterval", 1000))
        }

        c["hHoldKeysLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按键:")
        c["hHoldKeysEdit"] := g.Add("Edit", "x80 y" y " w200 h22", holdVal)
        g.Add("Text", "x290 y" y+3 " w180 h18", "如 Shift, Ctrl（逗号分隔）")
        y += 30

        c["hDurationLabel"] := g.Add("Text", "x20 y" y " w60 h20", "持续时长:")
        c["hDurationEdit"] := g.Add("Edit", "x80 y" y " w80 h22", durationVal)
        g.Add("Text", "x165 y" y+3 " w120 h18", "ms (0=无限)")
        y += 30

        c["hAutoRepeatLabel"] := g.Add("Text", "x20 y" y " w60 h20", "自动重复:")
        c["hAutoRepeatCB"] := g.Add("CheckBox", "x80 y" y " w60 h20" (autoRepeatVal ? " Checked" : ""), "启用")
        y += 26

        c["hRepeatIntervalLabel"] := g.Add("Text", "x20 y" y " w60 h20", "重复间隔:")
        c["hRepeatIntervalEdit"] := g.Add("Edit", "x80 y" y " w80 h22", repeatIntervalVal)
        g.Add("Text", "x165 y" y+3 " w30 h18", "ms")
    }

    ; =================================================================
    ; 执行预览
    ; =================================================================
    static _BuildPreviewSection() {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 508

        c["previewGroupBox"] := g.Add("GroupBox", "x10 y" y " w540 h50", "执行预览")
        y += 18
        c["previewText"] := g.Add("Text", "x20 y" y " w520 h24", "按热键启动后: [尚未配置]")
    }

    static _UpdatePreview() {
        c := GroupEditor.controls
        if !c.Has("previewText")
            return

        hotkey := c["HotkeyBtn"].Text
        if hotkey = "点击设置热键" {
            c["previewText"].Text := "按热键启动后: [请先设置热键]"
            return
        }

        mode := GroupEditor.currentMode
        previewStr := "按 " hotkey " 启动后: "

        switch mode {
            case "periodic", "enhanced_periodic":
                keys := GroupEditor._CollectSimpleKeys()
                if keys.Length > 0 {
                    for i, k in keys {
                        if i > 1
                            previewStr .= " -> "
                        previewStr .= k
                    }
                    previewStr .= " [循环]"
                } else
                    previewStr .= "[请添加按键]"
            case "sequence", "enhanced_sequence":
                keys := GroupEditor._CollectSimpleKeys()
                if keys.Length > 0 {
                    for i, k in keys {
                        if i > 1
                            previewStr .= " -> "
                        previewStr .= k
                    }
                    previewStr .= " [完成]"
                } else
                    previewStr .= "[请添加按键]"
            case "hybrid", "enhanced_hybrid":
                for i, sub in GroupEditor.subGroups {
                    if i > 1
                        previewStr .= " | "
                    previewStr .= "子组" i ": "
                    for j, k in sub.keys {
                        if j > 1
                            previewStr .= "->"
                        previewStr .= k
                    }
                }
            case "hold":
                mc := GroupEditor.modeControls
                if mc.Has("hHoldKeysEdit") && mc["hHoldKeysEdit"].Text != ""
                    previewStr .= "按住 " mc["hHoldKeysEdit"].Text
                else
                    previewStr .= "[请设置长按键]"
        }

        c["previewText"].Text := previewStr
    }

    ; =================================================================
    ; 底部操作栏
    ; =================================================================
    static _BuildFooter() {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 566

        c["importBtn"] := g.Add("Button", "x10 y" y " w70 h28", "导入")
        c["importBtn"].OnEvent("Click", (*) => GroupEditor._ImportConfig())

        c["exportBtn"] := g.Add("Button", "x85 y" y " w70 h28", "导出")
        c["exportBtn"].OnEvent("Click", (*) => GroupEditor._ExportConfig())

        c["resetBtn"] := g.Add("Button", "x160 y" y " w70 h28", "重置")
        c["resetBtn"].OnEvent("Click", (*) => GroupEditor._ResetForm())

        c["cancelBtn"] := g.Add("Button", "x350 y" y " w80 h28", "取消")
        c["cancelBtn"].OnEvent("Click", (*) => GroupEditor._Close())

        c["saveBtn"] := g.Add("Button", "x440 y" y " w110 h28", "保存")
        c["saveBtn"].OnEvent("Click", (*) => GroupEditor._ValidateAndSave())
    }

    ; =================================================================
    ; 快捷操作
    ; =================================================================
    static _ImportConfig() {
        filePath := FileSelect(1, "", "导入分组配置", "JSON (*.json)")
        if filePath = ""
            return
        try {
            content := FileRead(filePath, "UTF-8")
            config := JSONParser.Parse(content)
            GroupEditor._PopulateForm(config)
        } catch as e {
            MsgBox("导入失败: " e.Message, "错误", "Icon!")
        }
    }

    static _ExportConfig() {
        config := GroupEditor._CollectConfig()
        if !config {
            MsgBox("请先完善配置", "提示", "Icon!")
            return
        }
        filePath := FileSelect("S16", "group_config.json", "导出分组配置", "JSON (*.json)")
        if filePath = ""
            return
        try {
            jsonStr := JSONSerializer.Stringify(config)
            FileAppend(jsonStr, filePath, "UTF-8")
            MsgBox("已导出到: " filePath, "成功")
        } catch as e {
            MsgBox("导出失败: " e.Message, "错误", "Icon!")
        }
    }

    static _ResetForm() {
        result := MsgBox("确定要重置所有配置吗？", "确认", "YesNo Icon?")
        if result != "Yes"
            return
        GroupEditor.controls["HotkeyBtn"].Text := "点击设置热键"
        GroupEditor.controls["ModeDDL"].Choose(3)
        GroupEditor.currentMode := "enhanced_periodic"
        GroupEditor.subGroups := []
        GroupEditor.savedConfig := ""
        GroupEditor._ClearModeControls()
        GroupEditor._RenderModeContent()
        GroupEditor._UpdatePreview()
    }

    ; =================================================================
    ; 输入验证和保存
    ; =================================================================
    static _ValidateAndSave() {
        errors := []

        id := GroupEditor.controls["IdEdit"].Text
        if id = ""
            errors.Push("请输入分组 ID")

        hotkey := GroupEditor.controls["HotkeyBtn"].Text
        if hotkey = "点击设置热键"
            errors.Push("请设置热键")

        mode := GroupEditor.currentMode
        if mode != "hold" && mode != "hybrid" && mode != "enhanced_hybrid" {
            keys := GroupEditor._CollectSimpleKeys()
            if keys.Length = 0
                errors.Push("请至少添加一个按键")
        }

        if mode = "hybrid" || mode = "enhanced_hybrid" {
            GroupEditor._SyncSubGroupData()
            if GroupEditor.subGroups.Length = 0
                errors.Push("请至少添加一个子组")
            for i, sub in GroupEditor.subGroups {
                if sub.keys.Length = 0
                    errors.Push("子组 " i " 请至少添加一个按键")
            }
        }

        if mode = "hold" {
            mc := GroupEditor.modeControls
            if mc.Has("hHoldKeysEdit") && mc["hHoldKeysEdit"].Text = ""
                errors.Push("请输入长按键")
        }

        if errors.Length > 0 {
            MsgBox(errors[1], "验证错误", "Icon!")
            return
        }

        config := GroupEditor._CollectConfig()
        if !config {
            MsgBox("请完善分组配置", "验证错误", "Icon!")
            return
        }

        try {
            if GroupEditor.isNew {
                result := GroupService.CreateGroup(id, config)
                if result["success"] {
                    try GUIManager._RefreshGroupList()
                    GroupEditor._Close()
                } else
                    MsgBox("创建失败", "错误", "Icon!")
            } else {
                result := GroupService.UpdateGroup(GroupEditor.currentId, config)
                if result["success"] {
                    try GUIManager._RefreshGroupList()
                    GroupEditor._Close()
                } else
                    MsgBox("更新失败", "错误", "Icon!")
            }
        } catch as e {
            MsgBox("保存失败: " e.Message, "错误", "Icon!")
        }
    }

    ; =================================================================
    ; 配置收集
    ; =================================================================
    static _CollectSimpleKeys() {
        c := GroupEditor.modeControls
        keys := []
        if !c.Has("keyRows")
            return keys
        for row in c["keyRows"] {
            prefix := "kr" row.idx "_"
            if c.Has(prefix "keyBtn") && c[prefix "keyBtn"].Text != "" && c[prefix "keyBtn"].Text != "点击选择"
                keys.Push(c[prefix "keyBtn"].Text)
        }
        return keys
    }

    static _CollectSimpleIntervals() {
        c := GroupEditor.modeControls
        intervals := []
        if !c.Has("keyRows")
            return intervals
        for row in c["keyRows"] {
            prefix := "kr" row.idx "_"
            if c.Has(prefix "intervalEdit") {
                try
                    intervals.Push(Integer(c[prefix "intervalEdit"].Text))
                catch
                    intervals.Push(50)
            }
        }
        return intervals
    }

    static _CollectConfig() {
        try {
            hotkey := GroupEditor.controls["HotkeyBtn"].Text
            if hotkey = "点击设置热键"
                return ""

            mode := GroupEditor.currentMode
            config := Map("hotkey", hotkey, "mode", mode)

            switch mode {
                case "periodic":
                    config["keys"] := GroupEditor._CollectSimpleKeys()
                    config["intervals"] := GroupEditor._CollectSimpleIntervals()
                case "sequence":
                    config["keys"] := GroupEditor._CollectSimpleKeys()
                    config["delays"] := GroupEditor._CollectSimpleIntervals()
                case "enhanced_periodic":
                    config["pressKeys"] := GroupEditor._CollectSimpleKeys()
                    config["intervals"] := GroupEditor._CollectSimpleIntervals()
                    mc := GroupEditor.modeControls
                    if mc.Has("holdKeysEdit") && mc["holdKeysEdit"].Text != ""
                        config["holdKeys"] := GroupEditor._ParseArray(mc["holdKeysEdit"].Text)
                    if mc.Has("holdModeDDL")
                        config["holdMode"] := mc["holdModeDDL"].Text = "持续按住" ? "continuous" : "periodic"
                case "enhanced_sequence":
                    config["pressKeys"] := GroupEditor._CollectSimpleKeys()
                    config["pressDelays"] := GroupEditor._CollectSimpleIntervals()
                    mc := GroupEditor.modeControls
                    if mc.Has("holdKeysEdit") && mc["holdKeysEdit"].Text != ""
                        config["holdKeys"] := GroupEditor._ParseArray(mc["holdKeysEdit"].Text)
                    if mc.Has("holdModeDDL")
                        config["holdMode"] := mc["holdModeDDL"].Text = "持续按住" ? "continuous" : "periodic"
                case "hybrid", "enhanced_hybrid":
                    GroupEditor._SyncSubGroupData()
                    config["groups"] := GroupEditor._CollectSubGroups()
                    if mode = "enhanced_hybrid" {
                        mc := GroupEditor.modeControls
                        if mc.Has("ehyHoldKeysEdit") && mc["ehyHoldKeysEdit"].Text != ""
                            config["holdKeys"] := GroupEditor._ParseArray(mc["ehyHoldKeysEdit"].Text)
                        config["holdMode"] := "continuous"
                    }
                case "hold":
                    mc := GroupEditor.modeControls
                    if mc.Has("hHoldKeysEdit")
                        config["holdKeys"] := GroupEditor._ParseArray(mc["hHoldKeysEdit"].Text)
                    if mc.Has("hDurationEdit") {
                        try
                            config["holdDuration"] := Integer(mc["hDurationEdit"].Text)
                        catch
                            config["holdDuration"] := 0
                    }
                    if mc.Has("hAutoRepeatCB")
                        config["autoRepeat"] := mc["hAutoRepeatCB"].Value ? true : false
                    if mc.Has("hRepeatIntervalEdit") {
                        try
                            config["repeatInterval"] := Integer(mc["hRepeatIntervalEdit"].Text)
                        catch
                            config["repeatInterval"] := 1000
                    }
            }

            return config
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return ""
        }
    }

    static _CollectSubGroups() {
        groups := []
        for i, sub in GroupEditor.subGroups {
            subConfig := Map("type", sub.type)
            subConfig["pressKeys"] := sub.keys

            if sub.type = "periodic"
                subConfig["intervals"] := sub.intervals
            else {
                subConfig["delays"] := sub.delays
                subConfig["seqInterval"] := _GetProp(sub, "seqInterval", 100)
            }
            groups.Push(subConfig)
        }
        return groups
    }

    ; =================================================================
    ; 编辑时回填数据
    ; =================================================================
    static _PopulateForm(config) {
        mode := _GetProp(config, "mode", "enhanced_periodic")
        GroupEditor.currentMode := mode

        displayName := GroupEditor.MODE_KEY_TO_DISPLAY.Has(mode) ? GroupEditor.MODE_KEY_TO_DISPLAY[mode] : "增强周期"
        for i, item in GroupEditor.MODE_DDL_ITEMS {
            if item = displayName {
                GroupEditor.controls["ModeDDL"].Choose(i)
                break
            }
        }

        hotkey := _GetProp(config, "hotkey", "")
        if hotkey != ""
            GroupEditor.controls["HotkeyBtn"].Text := hotkey

        GroupEditor._ClearModeControls()
        GroupEditor._RenderModeContent(config)
        GroupEditor._UpdatePreview()
    }

    ; =================================================================
    ; 热键编辑器
    ; =================================================================
    static _OpenHotkeyEditor() {
        GroupEditor.gui.Opt("+Disabled")
        HotkeyEditor.Open((hotkey) => GroupEditor._OnHotkeySelected(hotkey))
    }

    static _OnHotkeySelected(hotkey) {
        GroupEditor.controls["HotkeyBtn"].Text := hotkey
        GroupEditor.gui.Opt("-Disabled")
        GroupEditor._UpdatePreview()
    }

    ; =================================================================
    ; 辅助方法
    ; =================================================================
    static _ParseArray(text) {
        result := []
        parts := StrSplit(text, ",")
        for part in parts {
            trimmed := Trim(part)
            if trimmed != ""
                result.Push(trimmed)
        }
        return result
    }

    static _ArrayToStr(arr) {
        if !(arr is Array)
            return ""
        str := ""
        for item in arr {
            if str != ""
                str .= ", "
            str .= item
        }
        return str
    }

    static _ParseIntArray(text) {
        result := []
        if text = ""
            return result
        parts := StrSplit(text, ",")
        for part in parts {
            trimmed := Trim(part)
            if trimmed != "" && IsInteger(trimmed)
                result.Push(Integer(trimmed))
        }
        return result
    }
}

; =================================================================
; 按键选择器弹窗
; =================================================================
class KeyPicker {
    static gui := ""
    static callback := ""
    static allButtons := []

    static ALL_KEYS := [
        {section: "功能键", keys: ["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"]},
        {section: "数字", keys: ["1","2","3","4","5","6","7","8","9","0"]},
        {section: "字母", keys: ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]},
        {section: "特殊", keys: ["Space","Enter","Tab","Esc","Backspace","Delete","Insert","Home","End","PgUp","PgDn"]},
        {section: "方向", keys: ["Up","Down","Left","Right"]},
        {section: "修饰", keys: ["Shift","Ctrl","Alt","Win"]},
        {section: "鼠标", keys: ["LButton","RButton","MButton","XButton1","XButton2"]},
        {section: "符号", keys: ["``","-","=","[","]","\",";","'",",",".","/"]}
    ]

    static Open(callback) {
        KeyPicker.callback := callback

        if KeyPicker.gui {
            try
                KeyPicker.gui.Destroy()
        }

        KeyPicker.gui := Gui("+ToolWindow +AlwaysOnTop", "选择按键")
        KeyPicker.gui.SetFont("s9", "Segoe UI")
        KeyPicker.gui.OnEvent("Close", (*) => KeyPicker._Close())

        KeyPicker.searchEdit := KeyPicker.gui.Add("Edit", "x10 y10 w340 h24", "")
        KeyPicker.searchEdit.OnEvent("Change", (*) => KeyPicker._FilterKeys())

        KeyPicker._BuildGrid()

        KeyPicker.gui.Show("w360 h400")
    }

    static _BuildGrid() {
        for btn in KeyPicker.allButtons {
            try
                btn.Destroy()
        }
        KeyPicker.allButtons := []

        g := KeyPicker.gui
        x := 10
        y := 42
        col := 0
        maxCols := 8
        btnW := 40
        btnH := 24
        gap := 2

        for idx, section in KeyPicker.ALL_KEYS {
            if col > 0 {
                y += btnH + gap + 14
                col := 0
            }

            secLabel := g.Add("Text", "x" x " y" y " w340 h14", section.section)
            secLabel.SetFont("s7 c0x888888")
            KeyPicker.allButtons.Push(secLabel)
            y += 16

            for keyIdx, key in section.keys {
                if col >= maxCols {
                    col := 0
                    y += btnH + gap
                }

                btnX := x + col * (btnW + gap)
                isSpecial := (section.section = "特殊" || section.section = "修饰" || section.section = "鼠标")
                btn := g.Add("Button", "x" btnX " y" y " w" btnW " h" btnH, key)
                btn.SetFont(isSpecial ? "s7" : "s8")
                btn.OnEvent("Click", ((k) => (*) => KeyPicker._PickKey(k))(key))
                KeyPicker.allButtons.Push(btn)
                col++
            }
            y += btnH + gap + 4
            col := 0
        }
    }

    static _FilterKeys() {
        query := StrLower(KeyPicker.searchEdit.Text)
        for btn in KeyPicker.allButtons {
            try {
                if btn.HasProp("Text") {
                    match := query = "" || InStr(StrLower(btn.Text), query)
                    btn.Visible := match
                }
            } catch {
                continue
            }
        }
    }

    static _PickKey(key) {
        if KeyPicker.callback
            KeyPicker.callback(key)
        KeyPicker._Close()
    }

    static _Close() {
        try
            KeyPicker.gui.Destroy()
        KeyPicker.gui := ""
        KeyPicker.allButtons := []
    }
}

; =================================================================
; 热键捕获对话框
; =================================================================
class HotkeyEditor {
    static gui := ""
    static callback := ""
    static _ih := ""
    static _pressedMods := ""
    static _pressedKey := ""
    static _keyDownTime := 0

    static Open(callback) {
        HotkeyEditor.callback := callback
        HotkeyEditor._pressedMods := ""
        HotkeyEditor._pressedKey := ""
        HotkeyEditor._keyDownTime := 0

        HotkeyEditor.gui := Gui("+ToolWindow +AlwaysOnTop", "设置热键")
        HotkeyEditor.gui.SetFont("s12", "Segoe UI")
        HotkeyEditor.gui.Add("Text", "w300 h50 Center", "请按下要设置的热键组合... (Esc取消)")
        HotkeyEditor.gui.OnEvent("Close", (*) => HotkeyEditor._Close())
        HotkeyEditor.gui.OnEvent("Escape", (*) => HotkeyEditor._Close())

        HotkeyEditor.gui.Show("w320 h100")

        HotkeyEditor._WaitForKey()
    }

    static _WaitForKey() {
        ih := InputHook("L0 M")
        ih.KeyOpt("{All}", "NS")
        ih.OnKeyDown := HotkeyEditor._OnKeyDown
        ih.OnEnd := HotkeyEditor._OnInputEnd
        ih.Start()
        HotkeyEditor._ih := ih
    }

    static _OnKeyDown(ih, key, sc) {
        if key = "Escape" {
            HotkeyEditor._Close()
            return
        }

        mods := ""
        if GetKeyState("Ctrl", "P")
            mods .= "^"
        if GetKeyState("Alt", "P")
            mods .= "!"
        if GetKeyState("Shift", "P")
            mods .= "+"
        if GetKeyState("Win", "P")
            mods .= "#"

        normalizedKey := HotkeyEditor._NormalizeKey(key)

        if HotkeyEditor._IsModifierOnly(normalizedKey) {
            HotkeyEditor._pressedMods := mods
            return
        }

        fullKey := mods normalizedKey
        if HotkeyEditor.callback && fullKey != ""
            HotkeyEditor.callback(fullKey)
        HotkeyEditor._Close()
    }

    static _OnInputEnd(ih) {
    }

    static _IsModifierOnly(key) {
        return key = "Shift" || key = "Ctrl" || key = "Alt" || key = "LShift" || key = "RShift" || key = "LCtrl" || key = "RCtrl" || key = "LAlt" || key = "RAlt" || key = "LWin" || key = "RWin"
    }

    static _NormalizeKey(key) {
        if key = ""
            return key
        specialKeys := Map(
            "Space", "Space", "Enter", "Enter", "Tab", "Tab",
            "Backspace", "Backspace", "Delete", "Delete", "Insert", "Insert",
            "Home", "Home", "End", "End", "PgUp", "PgUp", "PgDn", "PgDn",
            "Up", "Up", "Down", "Down", "Left", "Left", "Right", "Right"
        )
        if specialKeys.Has(key)
            return specialKeys[key]
        if RegExMatch(key, "^F\d+$")
            return key
        if StrLen(key) = 1
            return StrLower(key)
        return key
    }

    static _Close() {
        try
            HotkeyEditor.gui.Destroy()
        HotkeyEditor.gui := ""
    }
}
