; =================================================================
; 手柄测试工具 v1.0
; 说明: 实时检测手柄按钮、摇杆状态，支持多手柄和按键历史记录
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json.ahk"
#Include "equipment_recognizer.ahk"

; =================================================================
; 调试日志辅助函数（兼容层）
; =================================================================
_DebugLog(msg) {
	try {
		if IsSet(DebugLogger) && HasMethod(DebugLogger, "Log") {
			SkillMgrDebugLogger.Log(msg)
		} else {
			OutputDebug(msg)
		}
	} catch as e {
		OutputDebug(msg)
	}
}

; =================================================================
; JoystickTester - 主类
; =================================================================

class JoystickTester {
    static gui := ""
    static controls := Map()
    static selectedController := 1
    static buttonStates := Map()
    static history := []
    static buttonCount := 32
    static maxHistory := 50
    static pollInterval := 20
    static timers := Map()
    static isRunning := false
    static isPolling := false
    static stickPositions := Map("LX", 50, "LY", 50, "RX", 50, "RY", 50)
    static configFile := "joystick_config.json"
    static lastDetectedCount := 0
    static detectInterval := 2000
    static maxButtons := 128
    static allDetectedButtons := []
    static scanningMode := false

    ; 初始化应用
    static Init() {
        this._LoadConfig()
        this._CreateGUI()
        this._DetectControllers()
        this._StartPolling()
        this._StartControllerDetection()
        this.isRunning := true
    }

    ; 创建主窗口
    static _CreateGUI() {
        this.gui := Gui("+Resize", "手柄测试工具 v1.0")
        this.gui.SetFont("s9", "Microsoft YaHei")
        this.gui.Opt("+MinSize1000x620")

        ; 手柄选择器
        this._CreateControllerSelector()

        ; 按钮状态面板
        this._CreateButtonPanel()

        ; 按键历史面板
        this._CreateHistoryPanel()

        ; 摇杆可视化面板
        this._CreateJoystickPanel()

        ; 触发器和POV面板
        this._CreateTriggerPOVPanel()

        ; 创建OCR面板
        this._CreateOCRPanel()

        ; 绑定窗口事件
        this.gui.OnEvent("Close", (*) => this._OnClose())

        this.gui.Show("w1000 h620")

        ; 恢复窗口位置
        if (HasProp(this, "_savedX") && HasProp(this, "_savedY")) {
            this.gui.Move(this._savedX, this._savedY)
        }
    }

    ; 创建手柄选择器
    static _CreateControllerSelector() {
        this.controls["txtController"] := this.gui.Add("Text", "x10 y10 w80", "手柄编号:")

        controllerList := []
        loop 16 {
            controllerList.Push("手柄 " . A_Index)
        }

        this.controls["ddlController"] := this.gui.Add("DropDownList", "x90 y10 w100", controllerList)
        this.controls["ddlController"].Choose(this.selectedController)
        this.controls["ddlController"].OnEvent("Change", (*) => this._OnControllerChange())

        this.controls["txtControllerInfo"] := this.gui.Add("Text", "x200 y10 w400 h20", "未检测到手柄")
    }

    ; 创建按钮状态面板
    static _CreateButtonPanel() {
        this.controls["grpButtons"] := this.gui.Add("GroupBox", "x10 y40 w400 h220", "按钮状态")

        buttonW := 42
        buttonH := 42
        cols := 8
        startX := 20
        startY := 60
        gapX := 5
        gapY := 5

        loop 32 {
            idx := A_Index
            row := (idx - 1) // cols
            col := Mod(idx - 1, cols)
            x := startX + col * (buttonW + gapX)
            y := startY + row * (buttonH + gapY)

            btnKey := "btn" . idx
            this.controls[btnKey] := this.gui.Add("Text",
                Format("x{} y{} w{} h{} Center 0x200 BackgroundDefault", x, y, buttonW, buttonH),
                idx)
            this.controls[btnKey].SetFont("s10")

            this.buttonStates[idx] := false
        }
    }

    ; 创建历史记录面板
    static _CreateHistoryPanel() {
        this.controls["grpHistory"] := this.gui.Add("GroupBox", "x10 y270 w190 h200", "按键历史")

        this.controls["lstHistory"] := this.gui.Add("ListBox", "x20 y290 w170 h150", [])

        this.controls["btnClearHistory"] := this.gui.Add("Button", "x20 y450 w170 h30", "清空历史")
        this.controls["btnClearHistory"].OnEvent("Click", (*) => this._ClearHistory())
    }

    ; 创建摇杆可视化面板
    static _CreateJoystickPanel() {
        ; 左摇杆
        this.controls["grpLeftStick"] := this.gui.Add("GroupBox", "x210 y270 w180 h150", "左摇杆")
        this.controls["txtLeftStickX"] := this.gui.Add("Text", "x220 y295 w80", "X: 50")
        this.controls["txtLeftStickY"] := this.gui.Add("Text", "x300 y295 w80", "Y: 50")

        ; 左摇杆位置指示器（使用Text控件模拟圆点）
        this.controls["picLeftStick"] := this.gui.Add("Progress", "x220 y320 w140 h80 BackgroundSilver -Smooth", 0)
        this.controls["dotLeftStick"] := this.gui.Add("Text", "x285 y355 w10 h10 Center BackgroundLime", "")

        ; 右摇杆
        this.controls["grpRightStick"] := this.gui.Add("GroupBox", "x400 y270 w180 h150", "右摇杆")
        this.controls["txtRightStickR"] := this.gui.Add("Text", "x410 y295 w80", "R: 50")
        this.controls["txtRightStickU"] := this.gui.Add("Text", "x490 y295 w80", "U: 50")

        this.controls["picRightStick"] := this.gui.Add("Progress", "x410 y320 w140 h80 BackgroundSilver -Smooth", 0)
        this.controls["dotRightStick"] := this.gui.Add("Text", "x475 y355 w10 h10 Center BackgroundLime", "")
    }

    ; 创建触发器和POV面板
    static _CreateTriggerPOVPanel() {
        ; 触发器
        this.controls["grpTrigger"] := this.gui.Add("GroupBox", "x210 y430 w180 h80", "触发器 (Z)")
        this.controls["prgTrigger"] := this.gui.Add("Progress", "x220 y455 w160 h20 Range0-100 -Smooth", 0)
        this.controls["txtTriggerVal"] := this.gui.Add("Text", "x220 y480 w160", "Z: 0")

        ; POV十字键
        this.controls["grpPOV"] := this.gui.Add("GroupBox", "x400 y430 w180 h80", "十字键 (POV)")
        this.controls["txtPOVDir"] := this.gui.Add("Text", "x410 y455 w160 h40 Center", "无")

        ; 映射测试面板
        this.controls["grpMapping"] := this.gui.Add("GroupBox", "x590 y270 w200 h240", "映射测试")
        this.controls["txtMappingBtn"] := this.gui.Add("Text", "x600 y295 w80", "手柄按钮:")
        this.controls["ddlMappingBtn"] := this.gui.Add("DropDownList", "x680 y295 w100", this._GetButtonList())
        this.controls["txtMappingKey"] := this.gui.Add("Text", "x600 y330 w80", "映射到:")
        this.controls["edtMappingKey"] := this.gui.Add("Edit", "x680 y330 w100", "")
        this.controls["btnMappingTest"] := this.gui.Add("Button", "x600 y365 w180 h30", "开始测试")
        this.controls["btnMappingTest"].OnEvent("Click", (*) => this._StartMappingTest())
        this.controls["txtMappingStatus"] := this.gui.Add("Text", "x600 y405 w180 h60", "状态: 等待测试...")

        ; 扫描面板
        this._CreateScanPanel()

    ; 检测结果面板
    static _CreateDetectedButtonsPanel() {
        this.controls["grpDetected"] := this.gui.Add("GroupBox", "x800 y170 w190 h250", Format("已检测按键 ({})", this.allDetectedButtons.Length))
        this.controls["lstDetectedBtns"] := this.gui.Add("ListBox", "x810 y190 w170 h190", [])
        this.controls["btnExportDetected"] := this.gui.Add("Button", "x810 y390 w170 h25", "导出检测结果")
        this.controls["btnExportDetected"].OnEvent("Click", (*) => this._ExportDetectedButtons())
    }

    ; 创建OCR面板
    static _CreateOCRPanel() {
        this.controls["grpOCR"] := this.gui.Add("GroupBox", "x800 y430 w190 h160", "装备属性识别")
        
        ; 区域输入
        this.controls["txtOCRX"] := this.gui.Add("Text", "x810 y450 w30", "X:")
        this.controls["edtOCRX"] := this.gui.Add("Edit", "x840 y450 w50", "0")
        
        this.controls["txtOCRY"] := this.gui.Add("Text", "x900 y450 w30", "Y:")
        this.controls["edtOCRY"] := this.gui.Add("Edit", "x930 y450 w50", "0")
        
        this.controls["txtOCRW"] := this.gui.Add("Text", "x810 y480 w30", "W:")
        this.controls["edtOCRW"] := this.gui.Add("Edit", "x840 y480 w50", "200")
        
        this.controls["txtOCRH"] := this.gui.Add("Text", "x900 y480 w30", "H:")
        this.controls["edtOCRH"] := this.gui.Add("Edit", "x930 y480 w50", "100")
        
        ; 触发按钮
        this.controls["btnOCRTrigger"] := this.gui.Add("Button", "x810 y510 w170 h30", "开始识别")
        this.controls["btnOCRTrigger"].OnEvent("Click", (*) => this._OnOCRTrigger())
        
        ; 结果显示
        this.controls["lstOCRResult"] := this.gui.Add("ListView", "x810 y550 w170 h80", "属性|值|置信度")
        this.controls["lstOCRResult"].SetColumnWidth(1, 80)
        this.controls["lstOCRResult"].SetColumnWidth(2, 80)
        this.controls["lstOCRResult"].SetColumnWidth(3, 60)
    }

    ; OCR触发事件处理器
    static _OnOCRTrigger() {
        try {
            ; 获取区域参数
            x := this.controls["edtOCRX"].Value
            y := this.controls["edtOCRY"].Value
            w := this.controls["edtOCRW"].Value
            h := this.controls["edtOCRH"].Value
            
            ; 验证输入
            if (!x || !y || !w || !h) {
                this.controls["lstOCRResult"].Delete(1, this.controls["lstOCRResult"].GetCount)
                this.controls["lstOCRResult"].Add("错误||请填写完整的区域参数||")
                return
            }
            
            ; 转换为数字
            x := x + 0
            y := y + 0
            w := w + 0
            h := h + 0
            
            if (w <= 0 || h <= 0) {
                this.controls["lstOCRResult"].Delete(1, this.controls["lstOCRResult"].GetCount)
                this.controls["lstOCRResult"].Add("错误||宽度和高度必须大于0||")
                return
            }
            
            ; 清空结果列表
            this.controls["lstOCRResult"].Delete(1, this.controls["lstOCRResult"].GetCount)
            
            ; 执行OCR识别
            _DebugLog("JoystickTester._OnOCRTrigger: Starting OCR from rect (" x "," y "," w "," h ")")
            ocrResult := OCRWrapper.FromRect(x, y, w, h)
            
            ; 检查OCR是否可用
            if (!OCRWrapper.IsAvailable()) {
                this.controls["lstOCRResult"].Add("错误||OCR库不可用||")
                return
            }
            
            ; 识别装备属性
            equipResult := EquipmentAttributeRecognizer.Recognize(ocrResult)
            
            ; 显示结果
            if (equipResult.name != "") {
                this.controls["lstOCRResult"].Add("名称||" equipResult.name "||")
            }
            
            if (equipResult.attributes.Count > 0) {
                for name, value in equipResult.attributes {
                    this.controls["lstOCRResult"].Add(name "||" value "||" Format("{:P2}", equipResult.confidence))
                }
            } else {
                this.controls["lstOCRResult"].Add("未识别到属性||OCR文本: " SubStr(ocrResult.Text, 1, 50) "||")
            }
            
            ; 显示原始OCR文本（调试用）
            _DebugLog("JoystickTester._OnOCRTrigger: OCR Result - Text: '" ocrResult.Text "', Confidence: " equipResult.confidence)
            
        } catch as e {
            this.controls["lstOCRResult"].Delete(1, this.controls["lstOCRResult"].GetCount)
            this.controls["lstOCRResult"].Add("错误||" e.Message "||")
            _DebugLog("JoystickTester._OnOCRTrigger error: " e.Message)
        }
    }

    ; 获取按钮列表
    static _GetButtonList() {
        list := []
        loop this.maxButtons {
            list.Push("Joy" . A_Index)
        }
        return list
    }

    ; 创建扫描面板
    static _CreateScanPanel() {
        this.controls["grpScan"] := this.gui.Add("GroupBox", "x800 y40 w190 h120", "按键扫描")
        this.controls["txtScanHint"] := this.gui.Add("Text", "x810 y60 w170 h30", "扫描标准按键（Joy1-Joy32）")
        this.controls["btnScan"] := this.gui.Add("Button", "x810 y95 w170 h30", "开始扫描")
        this.controls["btnScan"].OnEvent("Click", (*) => this._OnScanClick())
        this.controls["txtScanResult"] := this.gui.Add("Text", "x810 y130 w170 h25", "未扫描")
    }

    ; 创建检测结果面板
    static _CreateDetectedButtonsPanel() {
        this.controls["grpDetected"] := this.gui.Add("GroupBox", "x800 y170 w190 h250", Format("已检测按键 ({})", this.allDetectedButtons.Length))
        this.controls["lstDetectedBtns"] := this.gui.Add("ListBox", "x810 y190 w170 h190", [])
        this.controls["btnExportDetected"] := this.gui.Add("Button", "x810 y390 w170 h25", "导出检测结果")
        this.controls["btnExportDetected"].OnEvent("Click", (*) => this._ExportDetectedButtons())
    }

    ; 获取按钮列表
    static _GetButtonList() {
        list := []
        loop this.maxButtons {
            list.Push("Joy" . A_Index)
        }
        return list
    }

    ; 扫描所有可能的按钮
    static _ScanAllButtons() {
        detected := []
        prefix := this.selectedController . "joy"

loop Min(this.maxButtons, 32) {
		btnName := prefix . A_Index
		try {
			state := GetKeyState(btnName)
			if (state != "" && state != " ") {
				detected.Push(A_Index)
			}
		} catch as e {
			_DebugLog("JoystickTester._ScanAllButtons: GetKeyState(" btnName ") 失败: " e.Message)
			break
		}
	}

        this.allDetectedButtons := detected
        return detected
    }

    ; 扫描按钮点击事件
    static _OnScanClick() {
        this.controls["txtScanResult"].Value := "扫描中..."

        detected := this._ScanAllButtons()

        this.controls["txtScanResult"].Value := Format("发现 {} 个按键", detected.Length)

        lst := this.controls["lstDetectedBtns"]
        lst.Delete(1, lst.GetCount)

        for i, btnIdx in detected {
            lst.Add(Format("Joy{}", btnIdx))
        }

        this.controls["grpDetected"].Text := Format("已检测按键 ({})", detected.Length)

        if (detected.Length > 0) {
            this.buttonCount := detected[detected.Length]
            this._MarkExistingButtons(detected)
        }
    }

    ; 标记存在的按钮
    static _MarkExistingButtons(detected) {
        for i, btnIdx in detected {
            if (btnIdx <= 32 && this.controls.Has("btn" . btnIdx)) {
                btn := this.controls["btn" . btnIdx]
                btn.Opt("+Border cGreen")
            }
        }
    }

    ; 导出检测结果
    static _ExportDetectedButtons() {
        if (this.allDetectedButtons.Length = 0) {
            MsgBox("没有检测结果可导出`n请先点击'开始扫描'按钮", "提示", "Icon!")
            return
        }

        result := "手柄按键检测结果`n"
        result .= "================`n"
        result .= Format("手柄编号: {}`n", this.selectedController)
        result .= Format("检测时间: {}`n`n", A_Now)
        result .= "检测到的按键:`n"

        for i, btnIdx in this.allDetectedButtons {
            result .= Format("Joy{}`n", btnIdx)
        }

        fileName := Format("detected_buttons_{}.txt", StrReplace(A_Now, ":", ""))
        try {
            FileAppend(result, fileName, "UTF-8")
            MsgBox("结果已导出到: " . fileName, "导出成功")
        } catch as e {
            MsgBox("导出失败: " . e.Message, "错误", "Icon!")
        }
    }

    ; 开始映射测试
    static _StartMappingTest() {
        btnIdx := this.controls["ddlMappingBtn"].Value
        if (btnIdx = 0) {
            MsgBox("请选择手柄按钮", "提示", "Icon!")
            return
        }

        targetKey := this.controls["edtMappingKey"].Value
        if (targetKey = "") {
            MsgBox("请输入目标按键", "提示", "Icon!")
            return
        }

        joyBtn := this.selectedController . "joy" . btnIdx
        this.controls["txtMappingStatus"].Value := "状态: 测试中..."

        try {
            this._testMappingBtn := btnIdx
            this._testMappingKey := targetKey
            this._testMappingPrev := false
            this.controls["txtMappingStatus"].Value := Format("状态: 按下 Joy{} 发送 {}", btnIdx, targetKey)
        } catch as e {
            this.controls["txtMappingStatus"].Value := "状态: 失败 - " . e.Message
        }
    }

    ; 检测可用的手柄
    static _DetectControllers() {
        detected := []
        firstInfo := ""

        loop 16 {
            prefix := A_Index . "joy"
            name := GetKeyState(prefix . "Name")

            if (name != "") {
                buttons := GetKeyState(prefix . "Buttons")
                axes := GetKeyState(prefix . "Axes")
                info := Format("{} - 按钮: {}, 轴: {}", name, buttons, axes)
                detected.Push({id: A_Index, name: name, info: info, buttons: buttons})

                if (A_Index = 1) {
                    firstInfo := info
                    if (buttons > 0 && buttons <= 32)
                        this.buttonCount := buttons
                }
            }
        }

        ; 检测到手柄数量变化时更新显示
        if (detected.Length != this.lastDetectedCount) {
            this.lastDetectedCount := detected.Length

            if (detected.Length > 0) {
                ; 找到第一个检测到的手柄
                first := detected[1]
                this.controls["txtControllerInfo"].Value := first.info
                this.selectedController := first.id
                this.controls["ddlController"].Choose(first.id)
            } else {
                this.controls["txtControllerInfo"].Value := "未检测到手柄"
            }
        }
    }

    ; 开始手柄自动检测
    static _StartControllerDetection() {
        this.timers["detect"] := () => this._DetectControllers()
        SetTimer(this.timers["detect"], this.detectInterval)
    }

    ; 停止手柄自动检测
    static _StopControllerDetection() {
        if this.timers.Has("detect") {
            SetTimer(this.timers["detect"], 0)
            this.timers.Delete("detect")
        }
    }

    ; 手柄切换事件
    static _OnControllerChange() {
        this.selectedController := this.controls["ddlController"].Value

        prefix := this.selectedController . "joy"
        name := GetKeyState(prefix . "Name")
        buttons := GetKeyState(prefix . "Buttons")
        axes := GetKeyState(prefix . "Axes")

        if (name != "") {
            this.controls["txtControllerInfo"].Value := Format("{} - 按钮: {}, 轴: {}", name, buttons, axes)
            if (buttons > 0 && buttons <= 32)
                this.buttonCount := buttons
        } else {
            this.controls["txtControllerInfo"].Value := Format("手柄 {} 未连接", this.selectedController)
        }

        loop 32 {
            this._UpdateButtonState(A_Index, false)
        }
    }

    ; 开始轮询
    static _StartPolling() {
        if this.isPolling
            return

        this.isPolling := true
        this.timers["poll"] := () => this._PollController()
        SetTimer(this.timers["poll"], this.pollInterval)
    }

    ; 停止轮询
    static _StopPolling() {
        if !this.isPolling
            return

        if this.timers.Has("poll") {
            SetTimer(this.timers["poll"], 0)
            this.timers.Delete("poll")
        }
        this.isPolling := false
    }

    ; 轮询控制器状态
    static _PollController() {
        try {
            this._PollButtons()
            this._PollAxes()
            this._PollPOV()
            this._CheckMappingTest()
        } catch as e {
            OutputDebug("JoystickTester._PollController error: " e.Message)
        }
    }

    ; 轮询摇杆轴
    static _PollAxes() {
        prefix := this.selectedController . "joy"

        joyX := GetKeyState(prefix . "X")
        joyY := GetKeyState(prefix . "Y")
        joyR := GetKeyState(prefix . "R")
        joyU := GetKeyState(prefix . "U")
        joyZ := GetKeyState(prefix . "Z")

        ; 更新左摇杆
        if (joyX != "" && joyY != "") {
            this.controls["txtLeftStickX"].Value := Format("X: {:.0f}", joyX)
            this.controls["txtLeftStickY"].Value := Format("Y: {:.0f}", joyY)
            this._UpdateStickDot("Left", joyX, joyY)
        }

        ; 更新右摇杆
        if (joyR != "" && joyU != "") {
            this.controls["txtRightStickR"].Value := Format("R: {:.0f}", joyR)
            this.controls["txtRightStickU"].Value := Format("U: {:.0f}", joyU)
            this._UpdateStickDot("Right", joyR, joyU)
        }

        ; 更新触发器
        if (joyZ != "") {
            this.controls["prgTrigger"].Value := joyZ
            this.controls["txtTriggerVal"].Value := Format("Z: {:.0f}", joyZ)
        }
    }

    ; 更新摇杆圆点位置
    static _UpdateStickDot(side, x, y) {
        dotKey := "dot" . side . "Stick"
        if !this.controls.Has(dotKey)
            return

        ; 计算圆点位置（画布中心为70,40）
        centerX := 70
        centerY := 40
        dotX := centerX + (x - 50) * 1.3 - 5
        dotY := centerY + (y - 50) * 0.7 - 5

        ; 限制范围
        dotX := Max(0, Min(130, dotX))
        dotY := Max(0, Min(70, dotY))

        ; 更新位置（需要加上画布偏移）
        baseX := (side = "Left") ? 220 : 410
        baseY := 320
        this.controls[dotKey].Move(baseX + dotX, baseY + dotY)
    }

    ; 轮询POV
    static _PollPOV() {
        prefix := this.selectedController . "joy"
        pov := GetKeyState(prefix . "POV")

        if (pov = "")
            return

        direction := this._GetPOVDirection(pov)
        this.controls["txtPOVDir"].Value := direction
    }

    ; 获取POV方向
    static _GetPOVDirection(pov) {
        if (pov = -1)
            return "无"

        ; 标准化到8方向
        if (pov >= 33750 || pov < 2250)
            return "↑"
        else if (pov >= 2250 && pov < 6750)
            return "↗"
        else if (pov >= 6750 && pov < 11250)
            return "→"
        else if (pov >= 11250 && pov < 15750)
            return "↘"
        else if (pov >= 15750 && pov < 20250)
            return "↓"
        else if (pov >= 20250 && pov < 24750)
            return "↙"
        else if (pov >= 24750 && pov < 29250)
            return "←"
        else if (pov >= 29250 && pov < 33750)
            return "↖"
        else
            return Format("{:.0f}°", pov / 100)
    }

    ; 检查映射测试
    static _CheckMappingTest() {
        if !HasProp(this, "_testMappingBtn")
            return

        btnIdx := this._testMappingBtn
        prefix := this.selectedController . "joy"
        isPressed := GetKeyState(prefix . btnIdx)

        if (isPressed && !this._testMappingPrev) {
            Send("{" . this._testMappingKey . "}")
            this.controls["txtMappingStatus"].Value := Format("状态: 已发送 {}", this._testMappingKey)
        }
        this._testMappingPrev := isPressed
    }

    ; 轮询按钮状态
    static _PollButtons() {
        prefix := this.selectedController . "joy"

        loop this.buttonCount {
            btnName := prefix . A_Index
            currentState := GetKeyState(btnName)

            if (currentState = "")
                continue

            prevState := this.buttonStates[A_Index]

            if (currentState && !prevState) {
                this._UpdateButtonState(A_Index, true)
                this._AddHistory("Joy" . A_Index, "按下")
            } else if (!currentState && prevState) {
                this._UpdateButtonState(A_Index, false)
                this._AddHistory("Joy" . A_Index, "释放")
            }

            this.buttonStates[A_Index] := currentState
        }
    }

    ; 更新按钮显示
    static _UpdateButtonState(btnIndex, isPressed) {
        btnKey := "btn" . btnIndex

        if !this.controls.Has(btnKey)
            return

        btn := this.controls[btnKey]

        if (isPressed) {
            btn.Opt("+BackgroundLime")
            btn.SetFont("s10 cWhite Bold")
        } else {
            btn.Opt("+BackgroundDefault")
            btn.SetFont("s10 cDefault Norm")
        }
    }

    ; 添加历史记录
    static _AddHistory(button, event) {
        timestamp := FormatTime(, "HH:mm:ss")
        entry := Format("{} {} {}", timestamp, button, event)

        this.history.Push({timestamp: timestamp, button: button, event: event})

        lst := this.controls["lstHistory"]

        if (this.history.Length > this.maxHistory) {
            this.history.RemoveAt(1)
            lst.Delete(1)
        }

        lst.Add(entry)

        count := lst.GetCount
        if (count > 0)
            lst.Choose(count)
    }

    ; 清空历史记录
    static _ClearHistory() {
        this.history := []
        lst := this.controls["lstHistory"]
        count := lst.GetCount
        if (count > 0)
            lst.Delete(1, count)
    }

    ; 窗口关闭事件
    static _OnClose() {
        this._StopPolling()
        this._StopControllerDetection()
        this._SaveConfig()
        this.isRunning := false
    }

    ; 加载配置
    static _LoadConfig() {
        if !FileExist(this.configFile)
            return

        try {
            config := JSONParser.LoadFile(this.configFile)

            if (config.Has("selectedController"))
                this.selectedController := config["selectedController"]

if (config.Has("windowX") && config.Has("windowY"))
            this._savedX := config["windowX"], this._savedY := config["windowY"]
        } catch as e {
            OutputDebug("JoystickTester._LoadConfig error: " e.Message)
        }
    }

    ; 保存配置
    static _SaveConfig() {
        try {
            this.gui.GetPos(&x, &y)

            config := Map(
                "selectedController", this.selectedController,
                "windowX", x,
                "windowY", y,
                "savedAt", A_Now
            )

jsonStr := JSONSerializer.Stringify(config, 2)
        FileDelete(this.configFile)
        FileAppend(jsonStr, this.configFile, "UTF-8")
        } catch as e {
            OutputDebug("JoystickTester._SaveConfig error: " e.Message)
        }
    }
}

; =================================================================
; 启动
; =================================================================

JoystickTester.Init()

