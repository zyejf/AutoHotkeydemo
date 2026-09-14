; ----------------------------------------------------------------------------
; P6：长路径（MAX_PATH = 260 边界）
;   逐层加目录，在 200 / 260 / 1000 / 5000 / 30000 字符处各测一遍：
;     DirCreate / FileAppend / FileExist / FileRead / FileGetSize / FileDelete
;   并做 `\\?\` 前缀对照。
;   全部落在 %TEMP%\ahkprobe\lp，不碰生产目录。
;   注意：超过 ~30k 的路径 DirDelete 可能删不掉，属已知现象，会记录。
; ----------------------------------------------------------------------------
#Include _harness.ahk

Main() {
    ProbeInit("p6_longpath")
    ProbeNote("P6 长路径：MAX_PATH=260 边界 + \\\\?\\ 前缀对照")
    ProbeWrite("len,DirCreate,FileAppend,FileExist,FileRead,FileGetSize,FileDelete,len_with_prefix,DirCreate_ext,FileAppend_ext")

    base := EnvGet("TEMP") . "\ahkprobe\lp"
    try DirDelete(base, true)
    DirCreate(base)

    path := base
    seg := "0123456789abcdefghijklmnopqrstuvwxyz"
    milestones := [200, 260, 1000, 5000, 30000]
    mi := 1
    guard := 0
    while (mi <= milestones.Length) && (guard < 5000) {
        guard += 1
        if StrLen(path) >= milestones[mi] {
            TestAt(path, milestones[mi])
            mi += 1
        }
        path .= "\" . seg
        try
            DirCreate(path)
        catch as e
            break
    }
    ; 收尾：尽力清理
    try DirDelete(base, true)
    catch as e
        ProbeWrite("cleanup,FAILED(长路径残留属已知现象)")
    ProbeDone()
}

TestAt(dir, wantLen) {
    ; 先把路径长度凑到目标附近（用文件名补足）
    pad := wantLen - StrLen(dir) - 8
    if pad < 1
        pad := 20
    name := ""
    Loop floor(pad / 10)
        name .= "0123456789"
    f := dir . "\" . name . ".txt"
    L := StrLen(f)

    dc := Try_(("DirCreate"), () => (DirCreate(dir), "ok"))
    fa := Try_("FileAppend", () => (FileAppend("hello", f, "UTF-8-RAW"), "ok"))
    fe := Try_("FileExist", () => (FileExist(f) ? "ok" : "MISSING"))
    fr := Try_("FileRead", () => (StrLen(FileRead(f, "UTF-8-RAW")) . "chars"))
    fs := Try_("FileGetSize", () => FileGetSize(f))
    fd := Try_("FileDelete", () => (FileDelete(f), "ok"))

    ; \\?\ 前缀对照
    ext := "\\?\" . f
    dcx := Try_("DirCreate_ext", () => (DirCreate("\\?\" . dir), "ok"))
    fax := Try_("FileAppend_ext", () => (FileAppend("hello", ext, "UTF-8-RAW"), "ok"))
    try FileDelete(ext)

    ProbeWrite(L . "," . dc . "," . fa . "," . fe . "," . fr . "," . fs . "," . fd
        . "," . StrLen(ext) . "," . dcx . "," . fax)
}

Try_(tag, fn) {
    try {
        v := fn()
        return (v = "") ? "ok" : v
    } catch as e {
        return "ERR:" . StrReplace(e.Message, ",", ";") . "(" . e.Extra . ")"
    }
}

Main()
ExitApp
