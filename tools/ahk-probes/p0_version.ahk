; ----------------------------------------------------------------------------
; P0：环境一致性指纹
;   确认「探针跑的引擎」== 「本项目打包用的引擎」== 「仓库内源码版本」。
;   三者不一致的话，后面所有实测结论都对本项目失真。
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    ProbeInit("p0_version")
    ProbeNote("P0 环境指纹")
    ProbeWrite("key,value")

    ProbeWrite("A_AhkVersion," . A_AhkVersion)
    ProbeWrite("A_IsCompiled," . A_IsCompiled)
    ProbeWrite("A_Is64bitOS," . A_Is64bitOS)
    ProbeWrite("A_OSVersion," . A_OSVersion)
    ProbeWrite("A_PtrSize," . A_PtrSize)
    ProbeWrite("A_ScriptFullPath," . A_ScriptFullPath)
    ProbeWrite("A_AhkPath," . A_AhkPath)
    ProbeWrite("A_LineFile," . A_LineFile)
    ProbeWrite("A_WorkingDir," . A_WorkingDir)
    ProbeWrite("A_ScriptName," . A_ScriptName)

    ; 项目内打包的那份 exe（若存在则取大小，用于与 A_AhkPath 对照）
    projExe := "D:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\AutoHotkey64.exe"
    ProbeWrite("project_exe_size," . (FileExist(projExe) ? FileGetSize(projExe) : "NA"))
    ProbeWrite("ahkpath_exe_size," . (FileExist(A_AhkPath) ? FileGetSize(A_AhkPath) : "NA"))

    ; 定时器分辨率相关：系统时钟粒度
    ProbeWrite("A_TickCount_step_probe_note,see P2")

    ProbeDone()
}

Main()
ExitApp
