; =================================================================
; EquipmentAttributeRecognizer - 装备属性识别器
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "ocr.ahk"

; 说明:
; 1) 解析 OCR 结果，提取装备属性信息
; 2) 支持常见的属性格式：名称-值对、带单位的数值等
; 3) 提供置信度筛选和结果验证

class EquipmentAttributeRecognizer {
	static _attributePatterns := []
	static _initialized := false
	
	; =================================================================
	; 初始化
	; =================================================================
	
	static _Init() {
		if EquipmentAttributeRecognizer._initialized
			return
		EquipmentAttributeRecognizer._initialized := true
		
		; 定义常见的属性模式（正则表达式）
		EquipmentAttributeRecognizer._attributePatterns := [
			{name: "attack", pattern: "i)(攻击力|Attack|ATK)[:\s]*(\d+(?:\.\d+)?)"},
			{name: "defense", pattern: "i)(防御力|Defense|DEF)[:\s]*(\d+(?:\.\d+)?)"},
			{name: "hp", pattern: "i)(生命值|Health|HP)[:\s]*(\d+(?:\.\d+)?)"},
			{name: "mp", pattern: "i)(魔法值|Mana|MP)[:\s]*(\d+(?:\.\d+)?)"},
			{name: "level", pattern: "i)(等级|Level|Lv\.?)[:\s]*(\d+)"},
			{name: "enhance", pattern: "i)(\+\d+)"},
			{name: "quality", pattern: "i)(普通|优秀|精良|史诗|传说|Common|Rare|Epic|Legendary)"},
			{name: "durability", pattern: "i)(耐久度|Durability)[:\s]*(\d+)\s*/\s*(\d+)"}
		]
	}
	
	; =================================================================
	; Public API
	; =================================================================
	
	; 从 OCR 结果识别装备属性
	static Recognize(ocrResult) {
		EquipmentAttributeRecognizer._Init()
		
		if !IsObject(ocrResult) || !HasProp(ocrResult, "Text") {
			return EquipmentAttributeRecognizer._EmptyResult()
		}
		
		result := {
			name: "",
			attributes: Map(),
			rawText: ocrResult.Text,
			confidence: 0.0,
			lines: []
		}
		
		; 解析所有行
		if HasProp(ocrResult, "Lines") && IsObject(ocrResult.Lines) {
			totalConf := 0.0
			lineCount := 0
			
			for lineObj in ocrResult.Lines {
				parsedLine := EquipmentAttributeRecognizer._ParseLine(lineObj)
				if parsedLine.found {
					result.lines.Push(parsedLine)
					totalConf += lineObj.Confidence
					lineCount++
				}
			}
			
			; 计算平均置信度
			if (lineCount > 0) {
				result.confidence := totalConf / lineCount
			}
		}
		
		; 尝试提取装备名称（通常是第一行）
		if HasProp(ocrResult, "Lines") && ocrResult.Lines.Length > 0 {
			firstLine := ocrResult.Lines[1].Text
			; 名称通常不包含数字和特殊符号
			if !RegExMatch(firstLine, "[0-9+\-*/%]")
				result.name := StrReplace(firstLine, "`n", "")
		}
		
		; 从全文提取属性值
		EquipmentAttributeRecognizer._ExtractAttributes(ocrResult.Text, result.attributes)
		
		return result
	}
	
	; 从屏幕区域识别装备属性
	static RecognizeFromRect(X, Y, W, H, Options := "") {
		ocrResult := OCRWrapper.FromRect(X, Y, W, H, Options)
		return EquipmentAttributeRecognizer.Recognize(ocrResult)
	}
	
	; 从窗口识别装备属性
	static RecognizeFromWindow(WinTitle, Options := "") {
		ocrResult := OCRWrapper.FromWindow(WinTitle, Options)
		return EquipmentAttributeRecognizer.Recognize(ocrResult)
	}
	
	; 获取属性值
	static GetAttribute(recognizeResult, attrName) {
		if !IsObject(recognizeResult) || !HasProp(recognizeResult, "attributes") {
			return ""
		}
		
		if recognizeResult.attributes.Has(attrName) {
			return recognizeResult.attributes[attrName]
		}
		return ""
	}
	
	; 检查是否有有效属性
	static HasAttributes(recognizeResult) {
		if !IsObject(recognizeResult) || !HasProp(recognizeResult, "attributes") {
			return false
		}
		return recognizeResult.attributes.Count > 0
	}
	
	; =================================================================
	; Private helpers
	; =================================================================
	
	static _ParseLine(lineObj) {
		result := {found: false, text: "", confidence: 0.0, attributes: Map()}
		
		if !IsObject(lineObj) || !HasProp(lineObj, "Text") {
			return result
		}
		
		text := lineObj.Text
		if (text = "") {
			return result
		}
		
		result.found := true
		result.text := text
		result.confidence := HasProp(lineObj, "Confidence") ? lineObj.Confidence : 0.5
		
		; 提取行内属性
		EquipmentAttributeRecognizer._ExtractAttributes(text, result.attributes)
		
		return result
	}
	
	static _ExtractAttributes(text, attrMap) {
		for patternObj in EquipmentAttributeRecognizer._attributePatterns {
			attrName := patternObj.name
			pattern := patternObj.pattern
			
			; 尝试匹配
			if RegExMatch(text, pattern, &match) {
				if (match.Count >= 1) {
					; 如果有捕获组，取最后一个捕获组作为值
					value := match[match.Count]
					if (value = "") {
						value := match[0]
					}
					attrMap[attrName] := value
				} else {
					attrMap[attrName] := match[0]
				}
			}
		}
		
		; 特殊处理：检测强化等级（如 +15）
		if RegExMatch(text, "\+(\d+)", &enhanceMatch) {
			attrMap["enhanceLevel"] := enhanceMatch[1]
		}
		
		; 特殊处理：检测数值范围（如 耐久度 50/100）
		if RegExMatch(text, "(\d+)\s*/\s*(\d+)", &rangeMatch) {
			attrMap["current"] := rangeMatch[1]
			attrMap["max"] := rangeMatch[2]
		}
	}
	
	static _EmptyResult() {
		return {
			name: "",
			attributes: Map(),
			rawText: "",
			confidence: 0.0,
			lines: []
		}
	}
	
	; =================================================================
	; 工具方法
	; =================================================================
	
	; 将识别结果转换为可读字符串
	static ToString(recognizeResult) {
		if !IsObject(recognizeResult) {
			return "[Invalid Result]"
		}
		
		str := "=== Equipment Info ===`n"
		
		if (recognizeResult.name != "") {
			str .= "Name: " recognizeResult.name "`n"
		}
		
		if recognizeResult.attributes.Count > 0 {
			str .= "`n--- Attributes ---`n"
			for name, value in recognizeResult.attributes {
				str .= name ": " value "`n"
			}
		}
		
		str .= "`nConfidence: " recognizeResult.confidence
		
		return str
	}
	
	; 将识别结果导出为 Map（用于 JSON 序列化）
	static ToMap(recognizeResult) {
		result := Map()
		result["name"] := recognizeResult.name
		result["confidence"] := recognizeResult.confidence
		
		attrs := Map()
		if HasProp(recognizeResult, "attributes") && recognizeResult.attributes.Count > 0 {
			for name, value in recognizeResult.attributes {
				attrs[name] := value
			}
		}
		result["attributes"] := attrs
		
		return result
	}
}
