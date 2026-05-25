#Requires AutoHotkey v2.0

; 此脚本包含故意触发的加载时错误
; 用于测试 /ErrorStdOut 参数

MsgBox("这行不会执行，因为下面有语法错误")

result := "abc" + 123  ; 加载时错误：类型不匹配
