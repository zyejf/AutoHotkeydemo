# V5 分组编辑器现代化重构 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 V5 HTML 原型设计翻译为功能完整的 AutoHotkey v2 GUI 代码，替换现有 `group_editor.ahk`，实现现代化、用户友好的分组编辑界面。

**Architecture:** 保持 DDD 四层架构不变，仅修改表现层 `presentation/group_editor.ahk`。新增 `KeyPicker` 类（按键选择器弹窗）和 `ExecutionPreview` 类（执行预览组件）在同一文件内实现。所有 GUI 控件遵循 AHK v2 规范（位置参数双引号、Button 用 `.Text`、DropDownList 用 Array）。

**Tech Stack:** AutoHotkey v2.0, DDD 分层架构, 现有基础设施层（ConfigStore, ErrorSystem, DebugLogger）

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `presentation/group_editor.ahk` | 重写 | 主编辑器面板 + 模式切换 + 表单 + 验证 + 保存 |
| `presentation/gui_manager.ahk` | 微调 | 适配新编辑器接口（调用方式不变） |
| `infrastructure/utils.ahk` | 不变 | 使用现有 `_GetProp`, `StrJoin` 等工具函数 |

---

### Task 1: 创建 KeyPicker 按键选择器弹窗

**Files:**
- Modify: `presentation/group_editor.ahk` (在文件末尾 HotkeyEditor 类之后添加)

- [ ] **Step 1: 编写 KeyPicker 类骨架**

在 `group_editor.ahk` 文件末尾（`HotkeyEditor` 类之后）添加 `KeyPicker` 类：

```autohotkey
class KeyPicker {
    static gui := ""
    static callback := ""
    static searchEdit := ""
    static gridContainer := ""
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

        KeyPicker.gui := Gui("+ToolWindow +AlwaysOnTop +Owner" GroupEditor.gui.Hwnd, "选择按键")
        KeyPicker.gui.SetFont("s9", "Segoe UI")
        KeyPicker.gui.OnEvent("Close", (*) => KeyPicker._Close())

        KeyPicker.searchEdit := KeyPicker.gui.Add("Edit", "x10 y10 w340 h24", "")
        KeyPicker.searchEdit.OnEvent("Change", (*) => KeyPicker._FilterKeys())

        KeyPicker.gridContainer := KeyPicker.gui.Add("Text", "x10 y40 w340 h260", "")

        KeyPicker._BuildGrid()

        KeyPicker.gui.Show("w360 h310")
    }

    static _BuildGrid() {
        for btn in KeyPicker.allButtons {
            try
                btn.Destroy()
        }
        KeyPicker.allButtons := []

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

            secLabel := KeyPicker.gui.Add("Text", "x" x " y" y " w340 h14", section.section)
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
                btn := KeyPicker.gui.Add("Button", "x" btnX " y" y " w" btnW " h" btnH, key)
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
```

- [ ] **Step 2: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出（脚本正常启动）

- [ ] **Step 3: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: add KeyPicker class for key selection dialog"
```

---

### Task 2: 重构 GroupEditor 主面板 - 基本信息区

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 重写 GroupEditor 类的静态属性和 Open 方法**

替换 `GroupEditor` 类的静态属性和 `Open` 方法，实现 V5 风格的面板：

```autohotkey
class GroupEditor {
    static gui := ""
    static controls := Map()
    static currentId := ""
    static isNew := false
    static currentMode := "enhanced_periodic"
    static modeControls := Map()
    static subGroups := []
    static activeSubIdx := 1
    static validationErrors := Map()

    static MODE_LIST := [
        {key: "periodic", display: "周期性"},
        {key: "sequence", display: "序列"},
        {key: "enhanced_periodic", display: "增强周期"},
        {key: "enhanced_sequence", display: "增强序列"},
        {key: "hybrid", display: "混合"},
        {key: "enhanced_hybrid", display: "增强混合"},
        {key: "hold", display: "长按"}
    ]

    static MODE_KEY_TO_DISPLAY := Map(
        "periodic", "周期性", "sequence", "序列", "enhanced_periodic", "增强周期",
        "enhanced_sequence", "增强序列", "hybrid", "混合", "enhanced_hybrid", "增强混合", "hold", "长按"
    )

    static MODE_DISPLAY_TO_KEY := Map(
        "周期性", "periodic", "序列", "sequence", "增强周期", "enhanced_periodic",
        "增强序列", "enhanced_sequence", "混合", "hybrid", "增强混合", "enhanced_hybrid", "长按", "hold"
    )

    static Open(id := "", isNew := false) {
        try {
            GroupEditor.isNew := isNew
            GroupEditor.currentId := id
            GroupEditor.validationErrors := Map()

            if GroupEditor.gui {
                try
                    GroupEditor.gui.Destroy()
            }

            title := isNew ? "添加新分组" : "编辑分组 " (id != "" ? id : "")
            GroupEditor.gui := Gui("+Resize +MinSize520x620", title)
            GroupEditor.gui.SetFont("s9", "Segoe UI")
            GroupEditor.gui.OnEvent("Close", (*) => GroupEditor._Close())
            GroupEditor.gui.OnEvent("Escape", (*) => GroupEditor._Close())

            GroupEditor._BuildUI(id, isNew)

            if !isNew && id != "" {
                config := GroupService.ConfigStore.GetGroupConfig(id)
                if config
                    GroupEditor._PopulateForm(config)
            }

            GroupEditor.gui.Show("w540 h640")
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
    }
```

- [ ] **Step 2: 实现 _BuildUI 方法（基本信息区 + 模式选择）**

```autohotkey
    static _BuildUI(id, isNew) {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 12

        g.Add("GroupBox", "x10 y" y " w520 h130", "基本信息")
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
            ["周期性", "序列", "增强周期", "增强序列", "混合", "增强混合", "长按"])
        c["ModeDDL"].OnEvent("Change", (*) => GroupEditor._OnModeChange())

        c["modeGroupBox"] := g.Add("GroupBox", "x10 y150 w520 h340", "按键配置")
        GroupEditor._RenderModeContent()

        GroupEditor._BuildAdvancedSection()
        GroupEditor._BuildPreviewSection()
        GroupEditor._BuildFooter()
    }
```

- [ ] **Step 3: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 4: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: refactor GroupEditor main panel with V5 layout"
```

---

### Task 3: 实现模式切换和简单模式（周期性/序列/增强周期/增强序列）编辑界面

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 实现 _OnModeChange 和 _RenderModeContent**

```autohotkey
    static _OnModeChange() {
        modeName := GroupEditor.controls["ModeDDL"].Text
        mode := GroupEditor.MODE_DISPLAY_TO_KEY.Has(modeName) ? GroupEditor.MODE_DISPLAY_TO_KEY[modeName] : "enhanced_periodic"
        GroupEditor.currentMode := mode
        GroupEditor._ClearModeControls()
        GroupEditor._RenderModeContent()
    }

    static _ClearModeControls() {
        for name, ctrl in GroupEditor.modeControls {
            try
                ctrl.Destroy()
        }
        GroupEditor.modeControls := Map()
    }

    static _RenderModeContent() {
        mode := GroupEditor.currentMode

        switch mode {
            case "periodic": GroupEditor._RenderSimpleMode("间隔", false)
            case "sequence": GroupEditor._RenderSimpleMode("延迟", false)
            case "enhanced_periodic": GroupEditor._RenderSimpleMode("间隔", true)
            case "enhanced_sequence": GroupEditor._RenderSimpleMode("延迟", true)
            case "hybrid": GroupEditor._RenderHybridMode(false)
            case "enhanced_hybrid": GroupEditor._RenderHybridMode(true)
            case "hold": GroupEditor._RenderHoldMode()
        }
    }
```

- [ ] **Step 2: 实现 _RenderSimpleMode（周期性/序列/增强周期/增强序列共用）**

```autohotkey
    static _RenderSimpleMode(timeLabel, hasHold) {
        g := GroupEditor.gui
        c := GroupEditor.modeControls
        y := 172

        c["keyTableHeader"] := g.Add("Text", "x20 y" y " w60 h18", "按键")
        c["timeTableHeader"] := g.Add("Text", "x120 y" y " w80 h18", timeLabel " (ms)")
        y += 22

        c["keyRows"] := []
        defaultKeys := ["Space", "1", "2"]
        defaultTimes := [50, 100, 100]

        for i, key in defaultKeys {
            GroupEditor._AddSimpleKeyRow(c, y, key, defaultTimes[i], timeLabel)
            y += 28
        }

        c["addKeyBtn"] := g.Add("Button", "x20 y" y " w120 h24", "+ 添加按键")
        c["addKeyBtn"].OnEvent("Click", (*) => GroupEditor._AddSimpleKeyRowAction(timeLabel))

        if hasHold {
            y += 34
            c["holdKeysLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按键:")
            c["holdKeysEdit"] := g.Add("Edit", "x80 y" y " w200 h22", "")
            y += 26
            c["holdModeLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按模式:")
            c["holdModeDDL"] := g.Add("DropDownList", "x80 y" y " w120 h200 Choose1", ["持续按住", "周期按压"])
        }
    }

    static _AddSimpleKeyRow(c, y, key, interval, timeLabel) {
        rowIdx := c["keyRows"].Length + 1
        rowPrefix := "kr" rowIdx "_"

        c[rowPrefix "keyBtn"] := g.Add("Button", "x20 y" y " w90 h24", key)
        c[rowPrefix "keyBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._OpenKeyPicker(ri))(rowIdx))

        c[rowPrefix "intervalEdit"] := g.Add("Edit", "x120 y" y " w70 h22", String(interval))
        g.Add("Text", "x195 y" y+3 " w30 h18", "ms")

        c[rowPrefix "delBtn"] := g.Add("Button", "x230 y" y " w24 h24", "X")
        c[rowPrefix "delBtn"].OnEvent("Click", ((ri) => (*) => GroupEditor._DeleteSimpleKeyRow(ri))(rowIdx))

        c["keyRows"].Push({idx: rowIdx, key: key, interval: interval})
    }

    static _AddSimpleKeyRowAction(timeLabel) {
        c := GroupEditor.modeControls
        rows := c["keyRows"]
        y := 194 + rows.Length * 28
        GroupEditor._AddSimpleKeyRow(c, y, "", 50, timeLabel)
    }

    static _DeleteSimpleKeyRow(rowIdx) {
        c := GroupEditor.modeControls
        rows := c["keyRows"]
        newRowIdx := 0
        for i, row in rows {
            if row.idx != rowIdx {
                newRowIdx++
                prefix := "kr" newRowIdx "_"
                oldPrefix := "kr" row.idx "_"
                if c.Has(oldPrefix "keyBtn") {
                    c[prefix "keyBtn"] := c[oldPrefix "keyBtn"]
                    c[prefix "intervalEdit"] := c[oldPrefix "intervalEdit"]
                    c[prefix "delBtn"] := c[oldPrefix "delBtn"]
                }
            }
        }
        for i := rows.Length, 1, -1 {
            if rows[i].idx = rowIdx {
                rows.RemoveAt(i)
                break
            }
        }
    }

    static _OpenKeyPicker(rowIdx) {
        GroupEditor.gui.Opt("+Disabled")
        KeyPicker.Open((key) => GroupEditor._OnKeyPicked(rowIdx, key))
    }

    static _OnKeyPicked(rowIdx, key) {
        c := GroupEditor.modeControls
        prefix := "kr" rowIdx "_"
        if c.Has(prefix "keyBtn") {
            c[prefix "keyBtn"].Text := key
        }
        GroupEditor.gui.Opt("-Disabled")
        GroupEditor._UpdatePreview()
    }
```

- [ ] **Step 3: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 4: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: implement simple mode editors (periodic/sequence/enhanced)"
```

---

### Task 4: 实现混合模式（hybrid/enhanced_hybrid）编辑界面

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 实现 _RenderHybridMode（子组标签页 + 子组内容）**

```autohotkey
    static _RenderHybridMode(isEnhanced) {
        g := GroupEditor.gui
        c := GroupEditor.modeControls
        y := 172

        GroupEditor.subGroups := [
            {type: "periodic", keys: ["m", "a"], intervals: [50, 50]},
            {type: "sequence", keys: ["1", "2", "3", "4"], delays: [200, 220, 240, 2500], seqInterval: 100}
        ]
        GroupEditor.activeSubIdx := 1

        c["subTabArea"] := g.Add("Text", "x20 y" y " w500 h28", "")
        y += 32

        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()

        if isEnhanced {
            y := 440
            c["ehyHoldKeysLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按键:")
            c["ehyHoldKeysEdit"] := g.Add("Edit", "x80 y" y " w200 h22", "")
        }
    }

    static _RenderSubTabs() {
        c := GroupEditor.modeControls
        for name, ctrl in c {
            if InStr(name, "subTab_") = 1 {
                try
                    ctrl.Destroy()
                c.Delete(name)
            }
        }

        g := GroupEditor.gui
        x := 20
        for i, sub in GroupEditor.subGroups {
            tabName := "subTab_" i
            isActive := (i = GroupEditor.activeSubIdx)
            btnStyle := isActive ? "c0x667eea" : "c0x888888"
            c[tabName] := g.Add("Button", "x" x " y174 w70 h24 " btnStyle, "子组 " i)
            c[tabName].OnEvent("Click", ((idx) => (*) => GroupEditor._SwitchSub(idx))(i))
            x += 74
        }

        c["addSubBtn"] := g.Add("Button", "x" x " y174 w24 h24", "+")
        c["addSubBtn"].OnEvent("Click", (*) => GroupEditor._AddSubGroup())
    }

    static _SwitchSub(idx) {
        GroupEditor.activeSubIdx := idx
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }

    static _AddSubGroup() {
        GroupEditor.subGroups.Push({type: "periodic", keys: [], intervals: []})
        GroupEditor.activeSubIdx := GroupEditor.subGroups.Length
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }

    static _RemoveSubGroup(idx) {
        if GroupEditor.subGroups.Length <= 1 {
            MsgBox("至少保留一个子组", "提示", "Icon!")
            return
        }
        GroupEditor.subGroups.RemoveAt(idx)
        if GroupEditor.activeSubIdx > GroupEditor.subGroups.Length
            GroupEditor.activeSubIdx := GroupEditor.subGroups.Length
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }

    static _RenderSubContent() {
        c := GroupEditor.modeControls
        for name, ctrl in c {
            if InStr(name, "sub_") = 1 {
                try
                    ctrl.Destroy()
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
        y += 28

        timeLabel := sub.type = "sequence" ? "延迟" : "间隔"
        c["sub_keyHeader"] := g.Add("Text", "x20 y" y " w60 h18", "按键")
        c["sub_timeHeader"] := g.Add("Text", "x120 y" y " w80 h18", timeLabel " (ms)")
        y += 22

        prefix := "sub_"
        times := sub.type = "sequence" ? sub.delays : sub.intervals
        for i, key in sub.keys {
            interval := (i <= times.Length) ? times[i] : 50
            c[prefix "key_" i] := g.Add("Button", "x20 y" y " w90 h24", key)
            c[prefix "key_" i].OnEvent("Click", ((ri) => (*) => GroupEditor._OpenSubKeyPicker(ri))(i))
            c[prefix "time_" i] := g.Add("Edit", "x120 y" y " w70 h22", String(interval))
            g.Add("Text", "x195 y" y+3 " w30 h18", "ms")
            c[prefix "del_" i] := g.Add("Button", "x230 y" y " w24 h24", "X")
            c[prefix "del_" i].OnEvent("Click", ((ri) => (*) => GroupEditor._DeleteSubKeyRow(ri))(i))
            y += 28
        }

        c[prefix "addRowBtn"] := g.Add("Button", "x20 y" y " w120 h24", "+ 添加按键")
        c[prefix "addRowBtn"].OnEvent("Click", (*) => GroupEditor._AddSubKeyRow())

        if sub.type = "sequence" {
            y += 30
            c[prefix "seqIntervalLabel"] := g.Add("Text", "x20 y" y " w70 h20", "循环间隔:")
            c[prefix "seqIntervalEdit"] := g.Add("Edit", "x90 y" y " w70 h22", String(_GetProp(sub, "seqInterval", 100)))
            g.Add("Text", "x165 y" y+3 " w30 h18", "ms")
        }
    }

    static _OnSubTypeChange() {
        idx := GroupEditor.activeSubIdx
        if idx < 1 || idx > GroupEditor.subGroups.Length
            return
        typeName := GroupEditor.modeControls["sub_typeDDL"].Text
        GroupEditor.subGroups[idx].type := (typeName = "序列") ? "sequence" : "periodic"
        GroupEditor._RenderSubContent()
    }

    static _OpenSubKeyPicker(rowIdx) {
        GroupEditor.gui.Opt("+Disabled")
        KeyPicker.Open((key) => GroupEditor._OnSubKeyPicked(rowIdx, key))
    }

    static _OnSubKeyPicked(rowIdx, key) {
        prefix := "sub_key_" rowIdx
        if GroupEditor.modeControls.Has(prefix)
            GroupEditor.modeControls[prefix].Text := key
        GroupEditor.gui.Opt("-Disabled")
    }

    static _AddSubKeyRow() {
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
```

- [ ] **Step 2: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 3: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: implement hybrid mode editor with sub-group tabs"
```

---

### Task 5: 实现长按模式编辑界面

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 实现 _RenderHoldMode**

```autohotkey
    static _RenderHoldMode() {
        g := GroupEditor.gui
        c := GroupEditor.modeControls
        y := 172

        c["hHoldKeysLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按键:")
        c["hHoldKeysEdit"] := g.Add("Edit", "x80 y" y " w200 h22", "")
        g.Add("Text", "x290 y" y+3 " w180 h18", "如 Shift, Ctrl（逗号分隔）")
        y += 30

        c["hDurationLabel"] := g.Add("Text", "x20 y" y " w60 h20", "持续时长:")
        c["hDurationEdit"] := g.Add("Edit", "x80 y" y " w80 h22", "0")
        g.Add("Text", "x165 y" y+3 " w120 h18", "ms (0=无限)")
        y += 30

        c["hAutoRepeatLabel"] := g.Add("Text", "x20 y" y " w60 h20", "自动重复:")
        c["hAutoRepeatCB"] := g.Add("CheckBox", "x80 y" y " w60 h20", "启用")
        y += 26

        c["hRepeatIntervalLabel"] := g.Add("Text", "x20 y" y " w60 h20", "重复间隔:")
        c["hRepeatIntervalEdit"] := g.Add("Edit", "x80 y" y " w80 h22", "1000")
        g.Add("Text", "x165 y" y+3 " w30 h18", "ms")
    }
```

- [ ] **Step 2: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 3: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: implement hold mode editor"
```

---

### Task 6: 实现高级选项区 + 执行预览 + 底部操作栏

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 实现 _BuildAdvancedSection, _BuildPreviewSection, _BuildFooter**

```autohotkey
    static _BuildAdvancedSection() {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 500

        c["advGroupBox"] := g.Add("GroupBox", "x10 y" y " w520 h70", "高级选项")
        y += 18

        c["advHoldKeysLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按键:")
        c["advHoldKeysEdit"] := g.Add("Edit", "x80 y" y " w200 h22", "")
        g.Add("Text", "x290 y" y+3 " w180 h18", "如 Shift, Ctrl（逗号分隔）")
        y += 26

        c["advHoldModeLabel"] := g.Add("Text", "x20 y" y " w60 h20", "长按模式:")
        c["advHoldModeDDL"] := g.Add("DropDownList", "x80 y" y " w120 h200 Choose1", ["持续按住", "周期按压"])
    }

    static _BuildPreviewSection() {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 578

        c["previewGroupBox"] := g.Add("GroupBox", "x10 y" y " w520 h50", "执行预览")
        y += 18
        c["previewText"] := g.Add("Text", "x20 y" y " w500 h24", "按热键启动后: [尚未配置]")
    }

    static _BuildFooter() {
        g := GroupEditor.gui
        c := GroupEditor.controls
        y := 636

        c["importBtn"] := g.Add("Button", "x10 y" y " w70 h30", "导入")
        c["importBtn"].OnEvent("Click", (*) => GroupEditor._ImportConfig())

        c["exportBtn"] := g.Add("Button", "x85 y" y " w70 h30", "导出")
        c["exportBtn"].OnEvent("Click", (*) => GroupEditor._ExportConfig())

        c["resetBtn"] := g.Add("Button", "x160 y" y " w70 h30", "重置")
        c["resetBtn"].OnEvent("Click", (*) => GroupEditor._ResetForm())

        c["cancelBtn"] := g.Add("Button", "x340 y" y " w80 h30", "取消")
        c["cancelBtn"].OnEvent("Click", (*) => GroupEditor._Close())

        c["saveBtn"] := g.Add("Button", "x430 y" y " w100 h30", "保存")
        c["saveBtn"].OnEvent("Click", (*) => GroupEditor._ValidateAndSave())
    }
```

- [ ] **Step 2: 实现辅助方法**

```autohotkey
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
                            previewStr .= " → "
                        previewStr .= k
                    }
                    previewStr .= " ↻ 循环"
                } else
                    previewStr .= "[请添加按键]"
            case "sequence", "enhanced_sequence":
                keys := GroupEditor._CollectSimpleKeys()
                if keys.Length > 0 {
                    for i, k in keys {
                        if i > 1
                            previewStr .= " → "
                        previewStr .= k
                    }
                    previewStr .= " → 完成"
                } else
                    previewStr .= "[请添加按键]"
            case "hybrid", "enhanced_hybrid":
                for i, sub in GroupEditor.subGroups {
                    if i > 1
                        previewStr .= " | "
                    previewStr .= "子组" i ": "
                    for j, k in sub.keys {
                        if j > 1
                            previewStr .= "→"
                        previewStr .= k
                    }
                }
            case "hold":
                mc := GroupEditor.modeControls
                if mc.Has("hHoldKeysEdit")
                    previewStr .= "按住 " mc["hHoldKeysEdit"].Text
        }

        c["previewText"].Text := previewStr
    }

    static _ImportConfig() {
        filePath := FileSelect(1, "", "导入分组配置", "JSON (*.json)")
        if filePath = ""
            return
        try {
            content := FileRead(filePath, "UTF-8")
            config := JSON.Parse(content)
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
            FileAppend(JSON.Stringify(config), filePath, "UTF-8")
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
        GroupEditor._ClearModeControls()
        GroupEditor._RenderModeContent()
        GroupEditor._UpdatePreview()
    }
```

- [ ] **Step 3: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 4: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: add advanced section, preview, and footer actions"
```

---

### Task 7: 实现输入验证和保存逻辑

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 实现 _ValidateAndSave 和 _CollectConfig**

```autohotkey
    static _ValidateAndSave() {
        errors := []

        id := GroupEditor.controls["IdEdit"].Text
        if id = ""
            errors.Push("请输入分组 ID")

        hotkey := GroupEditor.controls["HotkeyBtn"].Text
        if hotkey = "点击设置热键"
            errors.Push("请设置热键")

        keys := GroupEditor._CollectSimpleKeys()
        if GroupEditor.currentMode != "hold" && GroupEditor.currentMode != "hybrid" && GroupEditor.currentMode != "enhanced_hybrid" {
            if keys.Length = 0
                errors.Push("请至少添加一个按键")
        }

        if GroupEditor.currentMode = "hybrid" || GroupEditor.currentMode = "enhanced_hybrid" {
            if GroupEditor.subGroups.Length = 0
                errors.Push("请至少添加一个子组")
            for i, sub in GroupEditor.subGroups {
                if sub.keys.Length = 0
                    errors.Push("子组 " i " 请至少添加一个按键")
            }
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
                    GUIManager._RefreshGroupList()
                    GroupEditor._Close()
                } else
                    MsgBox("创建失败", "错误", "Icon!")
            } else {
                result := GroupService.UpdateGroup(GroupEditor.currentId, config)
                if result["success"] {
                    GUIManager._RefreshGroupList()
                    GroupEditor._Close()
                } else
                    MsgBox("更新失败", "错误", "Icon!")
            }
        } catch as e {
            MsgBox("保存失败: " e.Message, "错误", "Icon!")
        }
    }

    static _CollectSimpleKeys() {
        c := GroupEditor.modeControls
        keys := []
        if !c.Has("keyRows")
            return keys
        for row in c["keyRows"] {
            prefix := "kr" row.idx "_"
            if c.Has(prefix "keyBtn") && c[prefix "keyBtn"].Text != ""
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
                    config["holdMode"] := "sequence"
                case "hybrid", "enhanced_hybrid":
                    config["groups"] := GroupEditor._CollectSubGroups()
                    mc := GroupEditor.modeControls
                    if mc.Has("hybridSeqInterval") {
                        try
                            config["seqInterval"] := Integer(mc["hybridSeqInterval"].Text)
                        catch
                            config["seqInterval"] := 100
                    }
                    if mode = "enhanced_hybrid" {
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

            advHoldKeys := GroupEditor.controls["advHoldKeysEdit"].Text
            if advHoldKeys != "" && !config.Has("holdKeys")
                config["holdKeys"] := GroupEditor._ParseArray(advHoldKeys)

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
            subKeys := []
            mc := GroupEditor.modeControls
            for j, k in sub.keys {
                prefix := "sub_key_" j
                if mc.Has(prefix) && mc[prefix].Text != ""
                    subKeys.Push(mc[prefix].Text)
                else if k != ""
                    subKeys.Push(k)
            }
            subConfig["pressKeys"] := subKeys

            times := []
            for j, k in sub.keys {
                prefix := "sub_time_" j
                if mc.Has(prefix) {
                    try
                        times.Push(Integer(mc[prefix].Text))
                    catch
                        times.Push(50)
                }
            }

            if sub.type = "periodic"
                subConfig["intervals"] := times
            else {
                subConfig["delays"] := times
                prefix := "sub_seqIntervalEdit"
                if mc.Has(prefix) {
                    try
                        subConfig["seqInterval"] := Integer(mc[prefix].Text)
                    catch
                        subConfig["seqInterval"] := 100
                }
            }
            groups.Push(subConfig)
        }
        return groups
    }
```

- [ ] **Step 2: 保留辅助方法**

```autohotkey
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

    static _ParseIntArray(text) {
        result := []
        parts := StrSplit(text, ",")
        for part in parts {
            trimmed := Trim(part)
            if trimmed != "" {
                try
                    result.Push(Integer(trimmed))
                catch
                    result.Push(50)
            }
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
```

- [ ] **Step 3: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 4: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: implement validation, save, and config collection"
```

---

### Task 8: 实现 _PopulateForm（编辑时回填数据）

**Files:**
- Modify: `presentation/group_editor.ahk` (GroupEditor 类)

- [ ] **Step 1: 实现 _PopulateForm 和 _PopulateModeFields**

```autohotkey
    static _PopulateForm(config) {
        mode := _GetProp(config, "mode", "enhanced_periodic")
        GroupEditor.currentMode := mode

        displayName := GroupEditor.MODE_KEY_TO_DISPLAY.Has(mode) ? GroupEditor.MODE_KEY_TO_DISPLAY[mode] : "增强周期"
        GroupEditor.controls["ModeDDL"].Choose(displayName)

        hotkey := _GetProp(config, "hotkey", "")
        if hotkey != ""
            GroupEditor.controls["HotkeyBtn"].Text := hotkey

        GroupEditor._ClearModeControls()
        GroupEditor._RenderModeContent()
        GroupEditor._PopulateModeFields(config)
        GroupEditor._UpdatePreview()
    }

    static _PopulateModeFields(config) {
        mode := GroupEditor.currentMode
        c := GroupEditor.modeControls

        switch mode {
            case "periodic":
                GroupEditor._FillSimpleRows(_GetProp(config, "keys", []), _GetProp(config, "intervals", []))
            case "sequence":
                GroupEditor._FillSimpleRows(_GetProp(config, "keys", []), _GetProp(config, "delays", []))
            case "enhanced_periodic":
                GroupEditor._FillSimpleRows(_GetProp(config, "pressKeys", []), _GetProp(config, "intervals", []))
                if c.Has("holdKeysEdit")
                    c["holdKeysEdit"].Text := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
                if c.Has("holdModeDDL")
                    c["holdModeDDL"].Choose(_GetProp(config, "holdMode", "continuous") = "continuous" ? "持续按住" : "周期按压")
            case "enhanced_sequence":
                GroupEditor._FillSimpleRows(_GetProp(config, "pressKeys", []), _GetProp(config, "pressDelays", []))
                if c.Has("holdKeysEdit")
                    c["holdKeysEdit"].Text := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
            case "hybrid", "enhanced_hybrid":
                GroupEditor._FillHybridFromConfig(config)
                if mode = "enhanced_hybrid" && c.Has("ehyHoldKeysEdit")
                    c["ehyHoldKeysEdit"].Text := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
            case "hold":
                if c.Has("hHoldKeysEdit")
                    c["hHoldKeysEdit"].Text := GroupEditor._ArrayToStr(_GetProp(config, "holdKeys", []))
                if c.Has("hDurationEdit")
                    c["hDurationEdit"].Text := String(_GetProp(config, "holdDuration", 0))
                if c.Has("hAutoRepeatCB")
                    c["hAutoRepeatCB"].Value := _GetProp(config, "autoRepeat", false) ? 1 : 0
                if c.Has("hRepeatIntervalEdit")
                    c["hRepeatIntervalEdit"].Text := String(_GetProp(config, "repeatInterval", 1000))
        }
    }

    static _FillSimpleRows(keys, intervals) {
        c := GroupEditor.modeControls
        if !c.Has("keyRows")
            return
        for i, key in keys {
            if i <= c["keyRows"].Length {
                prefix := "kr" c["keyRows"][i].idx "_"
                if c.Has(prefix "keyBtn")
                    c[prefix "keyBtn"].Text := key
                if c.Has(prefix "intervalEdit") && i <= intervals.Length
                    c[prefix "intervalEdit"].Text := String(intervals[i])
            }
        }
    }

    static _FillHybridFromConfig(config) {
        groups := _GetProp(config, "groups", [])
        if groups.Length = 0
            return

        GroupEditor.subGroups := []
        for g in groups {
            subType := _GetProp(g, "type", "periodic")
            sub := {type: subType, keys: _GetProp(g, "pressKeys", [])}
            if subType = "sequence" {
                sub.delays := _GetProp(g, "delays", [])
                sub.seqInterval := _GetProp(g, "seqInterval", 100)
            } else
                sub.intervals := _GetProp(g, "intervals", [])
            GroupEditor.subGroups.Push(sub)
        }

        GroupEditor.activeSubIdx := 1
        GroupEditor._RenderSubTabs()
        GroupEditor._RenderSubContent()
    }
```

- [ ] **Step 2: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 3: 提交**

```bash
git add presentation/group_editor.ahk
git commit -m "feat: implement PopulateForm for editing existing groups"
```

---

### Task 9: 适配 gui_manager.ahk 和清理旧代码

**Files:**
- Modify: `presentation/gui_manager.ahk` (确保调用接口兼容)
- Modify: `presentation/group_editor.ahk` (移除旧的 _ShowPeriodicFields 等方法)

- [ ] **Step 1: 验证 gui_manager.ahk 的调用接口**

检查 `gui_manager.ahk` 中对 `GroupEditor.Open(id, false)` 和 `GroupEditor.Open("", true)` 的调用是否仍然兼容。新实现的 `Open` 方法签名不变，无需修改。

- [ ] **Step 2: 移除旧的方法**

从 `group_editor.ahk` 中删除以下旧方法（已被新方法替代）：
- `_ShowPeriodicFields`
- `_ShowSequenceFields`
- `_ShowEnhancedPeriodicFields`
- `_ShowEnhancedSequenceFields`
- `_ShowHybridFields`
- `_ShowHoldFields`
- `_CreateModeSpecificFields`
- `_GroupsToStr`
- `_ArrayToQuotedStr`
- 旧的 `_PopulateForm`
- 旧的 `_PopulateModeFields`
- 旧的 `_CollectConfig`
- 旧的 `_Save`
- 旧的 `_ShowStatus`

- [ ] **Step 3: 保留 HotkeyEditor 类**

确认 `HotkeyEditor` 类保持不变，它被 `_OpenHotkeyEditor` 方法使用。

- [ ] **Step 4: 语法验证**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
Expected: 无错误输出

- [ ] **Step 5: 提交**

```bash
git add presentation/group_editor.ahk presentation/gui_manager.ahk
git commit -m "refactor: clean up old editor methods, verify interface compatibility"
```

---

### Task 10: 端到端功能测试

**Files:**
- Test: 手动测试所有编辑器功能

- [ ] **Step 1: 启动应用**

Run: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" asd.ahk`

- [ ] **Step 2: 测试添加新分组**

1. 点击"添加分组"按钮
2. 输入 ID
3. 点击热键按钮设置热键
4. 切换不同模式，验证界面切换
5. 使用按键选择器添加按键
6. 点击保存，验证分组创建成功

- [ ] **Step 3: 测试编辑现有分组**

1. 在列表中选择一个分组
2. 点击"编辑"
3. 验证数据回填正确
4. 修改配置并保存

- [ ] **Step 4: 测试混合模式**

1. 创建混合模式分组
2. 添加/删除子组
3. 切换子组类型
4. 验证保存和回填

- [ ] **Step 5: 测试验证**

1. 尝试不填 ID 保存 → 应提示错误
2. 尝试不设热键保存 → 应提示错误
3. 尝试不添加按键保存 → 应提示错误

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "test: verify V5 editor end-to-end functionality"
```

---

## 自检清单

1. **Spec 覆盖率**: 所有 V5 原型功能均已覆盖：7 种模式编辑界面、按键选择器、输入验证、快捷操作（导入/导出/重置）、执行预览。
2. **占位符扫描**: 无 TBD/TODO/待实现内容。
3. **类型一致性**: 所有方法签名和属性名在 Task 间保持一致：`_RenderSimpleMode`, `_RenderHybridMode`, `_RenderHoldMode`, `_CollectConfig`, `_ValidateAndSave` 等。
