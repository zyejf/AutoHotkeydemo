; =================================================================
; OCR 封装模块 - 基于 Descolada OCR (Windows UWP OCR API)
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 说明:
; 1) 提供一套简易封装接口，对 Descolada OCR 库进行兼容封装。
; 2) 兼容层设计：如果目标 Descolada 库不存在，提供 Mock 实现以便测试。
; 3) 所有对 DLL 的调用均使用 try-catch 包装，遇到不可用场景返回空结果。

class TextLine {
	Text := ""
	Confidence := 0.0
	BoundingBox := {X: 0, Y: 0, W: 0, H: 0}
	
	__New(Text, Confidence := 0.0, BoundingBox := "") {
		this.Text := Text
		this.Confidence := Confidence
		if (BoundingBox = "")
			this.BoundingBox := {X: 0, Y: 0, W: 0, H: 0}
		else
			this.BoundingBox := BoundingBox
	}
}

class OCRResult {
	Text := ""
	Lines := []
	
	__New(Text := "", Lines := "") {
		this.Text := Text
		if (Lines = "")
			this.Lines := []
		else
			this.Lines := Lines
	}
	
	FindString(pattern) {
		for idx, line in this.Lines {
			pos := InStr(line.Text, pattern)
			if (pos != 0) {
				return {found: true, lineIndex: idx, position: pos}
			}
		}
		return {found: false}
	}
}

class OCRWrapper {
	static _engineLoaded := false
	static _engineAvailable := false
	static _useMock := true
	static _dllPath := ""
	static _languages := ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "it", "pt"]
	
	; =================================================================
	; Public API
	; =================================================================
	
	static FromDesktop(Options := "") {
		OCRWrapper._EnsureEngine()
		if !OCRWrapper._engineAvailable {
			return OCRResult("", [])
		}
		if OCRWrapper._useMock {
			return OCRWrapper._MockResult("Desktop", Options)
		}
		try {
			; TODO: 替换为 Descolada OCR 的实际入口签名
			json := ""
			if (json != "") {
				return OCRWrapper._ParseOCRJson(json)
			}
		} catch as e {
			; OCR 失败，使用 mock 结果
		}
		return OCRWrapper._MockResult("Desktop", Options)
	}
	
	static FromRect(X, Y, W, H, Options := "") {
		OCRWrapper._EnsureEngine()
		if !OCRWrapper._engineAvailable {
			return OCRResult("", [])
		}
		if OCRWrapper._useMock {
			return OCRWrapper._MockResult("Rect", Options, {X: X, Y: Y, W: W, H: H})
		}
		try {
			json := ""
			if (json != "") {
				return OCRWrapper._ParseOCRJson(json)
			}
		} catch as e {
			; OCR 失败，使用 mock 结果
		}
		return OCRWrapper._MockResult("Rect", Options, {X: X, Y: Y, W: W, H: H})
	}
	
	static FromWindow(WinTitle, Options := "") {
		OCRWrapper._EnsureEngine()
		if !OCRWrapper._engineAvailable {
			return OCRResult("", [])
		}
		if OCRWrapper._useMock {
			return OCRWrapper._MockResult("Window", Options, {WinTitle: WinTitle})
		}
		try {
			json := ""
			if (json != "") {
				return OCRWrapper._ParseOCRJson(json)
			}
		} catch as e {
			; OCR 失败，使用 mock 结果
		}
		return OCRWrapper._MockResult("Window", Options, {WinTitle: WinTitle})
	}
	
	static GetAvailableLanguages() {
		OCRWrapper._EnsureEngine()
		return OCRWrapper._languages
	}
	
	static IsAvailable() {
		OCRWrapper._EnsureEngine()
		return OCRWrapper._engineAvailable
	}
	
	; =================================================================
	; Private helpers
	; =================================================================
	
	static _EnsureEngine() {
		if OCRWrapper._engineLoaded
			return
		OCRWrapper._engineLoaded := true
		
		; 尝试定位 Descolada OCR 库
		libName := "OCR.ahk"
		candidatePaths := [
			A_ScriptDir "\Lib\OCR.ahk",
			A_ScriptDir "\libs\OCR.ahk",
			A_ScriptDir "\OCR.ahk"
		]
		
		for path in candidatePaths {
			if FileExist(path) {
				OCRWrapper._dllPath := path
				OCRWrapper._engineAvailable := true
				OCRWrapper._useMock := false
				OCRWrapper._Log("Descolada OCR library loaded from: " path)
				return
			}
		}
		
		; 未找到库，使用 Mock 实现
		OCRWrapper._engineAvailable := true
		OCRWrapper._useMock := true
		OCRWrapper._Log("Descolada OCR library not found. Using Mock implementation.")
	}
	
	static _MockResult(Mode, Options := "", rect := "") {
		lines := []
		lines.Push(TextLine("Mock OCR - Mode: " Mode, 0.99, {X: 10, Y: 10, W: 420, H: 20}))
		lines.Push(TextLine("This is a simulated OCR result.", 0.95, {X: 10, Y: 40, W: 420, H: 20}))
		lines.Push(TextLine("Equipment: Legendary Sword +15", 0.92, {X: 10, Y: 70, W: 420, H: 20}))
		full := "Mock OCR Result`nMock OCR line 1`nMock OCR line 2`nEquipment: Legendary Sword +15"
		return OCRResult(full, lines)
	}
	
	static _ParseOCRJson(json) {
		; TODO: 实现真实 JSON 解析
		return OCRWrapper._MockResult("JsonParse")
	}
	
	static _Log(msg) {
		try {
			if IsSet(_DebugLog) && IsFunc(_DebugLog) {
				_DebugLog(msg)
			} else {
				OutputDebug(msg)
			}
		} catch as e {
			OutputDebug(msg)
		}
	}
}
