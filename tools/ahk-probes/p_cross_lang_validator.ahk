; =================================================================
; 探针：跨语言校验对拍 —— AHK 侧的半边
; 版本: 1.0（TD-067）
;
; 作用：读 tests/fixtures/configs/cross_lang_validator_cases.json，把每个用例的
;       config 交给 infrastructure/ConfigValidator.Validate()，逐例输出
;       `id<TAB>errors<TAB>warnings`（errors>0 即「AHK 侧判定非法」）。
;
; 为什么要有这一半：Rust 侧的对拍测试（crates/asd-domain/tests/
; cross_lang_validator_parity.rs）里 AHK 的结论是**抄进夹具的快照**。若没有本脚本，
; 快照只能靠人肉跑一次之后就再也无法复核 —— AHK 侧改了校验规则而无人重跑，夹具里的
; ahk_has_error 会一直「绿」下去，所谓对拍就退化成单向断言。本脚本让那一列
; **可重新生成**，任何人改了 AHK 侧校验都能一条命令看出分歧面是否变了。
;
; 用法（PowerShell / bash）：
;   asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe tools/ahk-probes/p_cross_lang_validator.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug

; 注意：_GetProp 定义在 utils.ahk，config_validator.ahk 自己并不 include 它
; （生产靠 main.ahk 同时 include 两者才成立），本脚本必须自己带上。
; 用相对路径而非 %A_ScriptDir%：图谱工具（.review-analysis/build_graph.py）
; 只解析字面相对路径，内置变量会让它记成「未解析 #Include」而触发 G1 硬失败。
#Include "../../infrastructure/utils.ahk"
#Include "../../infrastructure/json_parser.ahk"
#Include "../../infrastructure/config_validator.ahk"

casesPath := A_ScriptDir "\..\..\tests\fixtures\configs\cross_lang_validator_cases.json"
if !FileExist(casesPath) {
    FileAppend("FATAL: 找不到夹具 " casesPath "`n", "*")
    ExitApp(2)
}

doc := JSONParser.Parse(FileRead(casesPath, "UTF-8"))
cases := _GetProp(doc, "cases")
if !(cases is Array) || cases.Length = 0 {
    FileAppend("FATAL: 夹具里没有 cases 数组（解析器是否静默失效？）`n", "*")
    ExitApp(2)
}

out := ""
for c in cases {
    id := _GetProp(c, "id", "<no-id>")
    cfg := _GetProp(c, "config")
    if !IsObject(cfg) {
        FileAppend("FATAL: 用例 " id " 缺少 config`n", "*")
        ExitApp(2)
    }
    errs := ConfigValidator.Validate(cfg)
    nErr := 0
    nWarn := 0
    for e in errs {
        if _GetProp(e, "type", "") = "ERROR"
            nErr++
        else
            nWarn++
    }
    out .= id "`t" nErr "`t" nWarn "`n"
}
FileAppend(out, "*")
ExitApp(0)
