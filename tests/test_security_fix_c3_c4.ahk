; =================================================================
; test_security_fix_c3_c4 - C3+C4 安全漏洞修复测试
; C3: WebView2 远程调试端口条件化（生产/编译环境不开启）
; C4: 路径遍历防护（拒绝式 InStr 检查替代删除式 RegExReplace 过滤）
; TDD RED 阶段：修复前预期 C3 测试 1-3 失败、C4 测试 4-5 失败
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

; 依赖引入（参考 test_webview2_bridge.ahk 的依赖链）
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"
#Include "../presentation/ui_manager.ahk"
#Include "../presentation/webview2_manager.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 初始化依赖（确保 JSONParser/JSONSerializer 等模块就绪）
; =================================================================
JSONLogger.Init()
DebugLogger.Init()
ConfigStore.InitDefaults()
ConfigService.ConfigStore := ConfigStore
ConfigService.SkillManager := SkillManager
ConfigService.Notifier := UIManager
GroupService.ConfigStore := ConfigStore
GroupService.SkillManager := SkillManager
SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := UIManager
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
SkillManager.Logger := JSONLogger
SkillManager.Notifier := UIManager
SkillManager.ConfigStore := ConfigStore
ErrorSystem.Init()
ModeRegistry._Init()

; =================================================================
; 测试固件
; =================================================================

; 读取 webview2_manager.ahk 源码用于 C3 源码检查
GetWv2Source() {
    return FileRead(A_ScriptDir "\..\presentation\webview2_manager.ahk", "UTF-8")
}

; 读取 backup_core.ahk 源码用于 C4 源码检查
GetBackupCoreSource() {
    return FileRead(A_ScriptDir "\..\infrastructure\backup_core.ahk", "UTF-8")
}

; 创建临时测试文件用于 C4 行为测试
; 文件放在 A_ScriptDir\backups\ 下（与 _BridgeCompareConfigs 的 backupDir 一致）
; 内容为有效 JSON，含 GroupSettings 字段
CreateTestFile() {
    testDir := A_ScriptDir "\backups"
    if !InStr(FileExist(testDir), "D")
        DirCreate(testDir)
    testFile := testDir "\test_c4_traversal.json"
    try FileDelete(testFile)
    FileAppend('{"GroupSettings":{}}', testFile, "UTF-8")
    return testFile
}

; 清理临时测试文件
CleanupTestFile(testFile) {
    try FileDelete(testFile)
}

; =================================================================
; C3 测试 - WebView2 远程调试端口条件化
; 修复目标：EnvSet 仅在 (!A_IsCompiled && EnvGet("ASD_DEBUG_WEBVIEW2")="1") 时执行
; =================================================================

Test_C3_CompiledModeNoDebugPort() {
    ; 验证源码包含 A_IsCompiled 检查（编译模式强制不开启调试端口）
    source := GetWv2Source()
    if InStr(source, "A_IsCompiled") {
        FileAppend("PASS: Test_C3_CompiledModeNoDebugPort - 存在 A_IsCompiled 条件检查`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_C3_CompiledModeNoDebugPort - 缺少 A_IsCompiled 条件检查，编译模式仍会开启调试端口`n", "*")
        return false
    }
}

Test_C3_NonCompiledNoFlagNoDebugPort() {
    ; 验证源码包含 ASD_DEBUG_WEBVIEW2 环境变量检查
    ; 非编译模式且无此标志时不应设置调试端口
    source := GetWv2Source()
    if InStr(source, "ASD_DEBUG_WEBVIEW2") {
        FileAppend("PASS: Test_C3_NonCompiledNoFlagNoDebugPort - 存在 ASD_DEBUG_WEBVIEW2 检查`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_C3_NonCompiledNoFlagNoDebugPort - 缺少 ASD_DEBUG_WEBVIEW2 环境变量检查`n", "*")
        return false
    }
}

Test_C3_NonCompiledWithFlagDebugPort() {
    ; 验证源码通过 EnvGet 读取 ASD_DEBUG_WEBVIEW2 标志
    ; 仅当标志为 "1" 时才设置调试端口
    source := GetWv2Source()
    if InStr(source, 'EnvGet("ASD_DEBUG_WEBVIEW2")') {
        FileAppend("PASS: Test_C3_NonCompiledWithFlagDebugPort - 存在 EnvGet 标志读取`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_C3_NonCompiledWithFlagDebugPort - 缺少 EnvGet 标志读取逻辑`n", "*")
        return false
    }
}

; =================================================================
; C4 测试 - 路径遍历防护（_BridgeCompareConfigs 行为测试）
; 修复目标：用 InStr 拒绝式检查替代 RegExReplace 删除式过滤
; =================================================================

Test_C4_PathTraversal_DoubleDot_Rejected() {
    ; 输入 backups\..\test_c4_traversal.json 应被拒绝
    ; 漏洞存在时：RegExReplace 删除 .. 后路径变为 backups\test_c4_traversal.json（存在），
    ;             前缀检查通过，返回成功（无 error）—— 路径遍历防护被绕过
    ; 修复后：InStr 检测到 .. 直接拒绝，返回 error
    data := Map("basePath", "backups\..\test_c4_traversal.json", "targetPath", "backups\..\test_c4_traversal.json")
    result := WebView2Manager._BridgeCompareConfigs(data)
    if InStr(result, "error") {
        FileAppend("PASS: Test_C4_PathTraversal_DoubleDot_Rejected - 路径遍历被拒绝`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_C4_PathTraversal_DoubleDot_Rejected - 路径遍历未被拒绝: " result "`n", "*")
        return false
    }
}

Test_C4_PathTraversal_FourDots_Rejected() {
    ; 输入 backups\....\test_c4_traversal.json 应被拒绝
    ; 漏洞存在时：RegExReplace 删除所有 .. 后路径变为 backups\test_c4_traversal.json（存在），
    ;             前缀检查通过，返回成功（无 error）—— 四点绕过攻击成功
    ; 修复后：InStr 检测到 .. （.... 包含 .. 子串）直接拒绝
    data := Map("basePath", "backups\....\test_c4_traversal.json", "targetPath", "backups\....\test_c4_traversal.json")
    result := WebView2Manager._BridgeCompareConfigs(data)
    ; 修复后应返回路径拒绝（"路径不在备份目录内"），而非走到文件存在检查
    if InStr(result, "路径不在备份目录") {
        FileAppend("PASS: Test_C4_PathTraversal_FourDots_Rejected - 四点绕过已修复`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_C4_PathTraversal_FourDots_Rejected - .... 绕过未修复: " result "`n", "*")
        return false
    }
}

Test_C4_NormalPath_Accepted() {
    ; 正常路径 backups\test_c4_traversal.json 应通过路径检查（不被路径遍历防护误拒）
    ; 这是回归测试，确保修复不破坏正常路径处理
    data := Map("basePath", "backups\test_c4_traversal.json", "targetPath", "backups\test_c4_traversal.json")
    result := WebView2Manager._BridgeCompareConfigs(data)
    ; 正常路径应通过路径检查，不应返回"路径不在备份目录内"
    if InStr(result, "路径不在备份目录") {
        FileAppend("FAIL: Test_C4_NormalPath_Accepted - 正常路径被误拒: " result "`n", "*")
        return false
    } else {
        FileAppend("PASS: Test_C4_NormalPath_Accepted - 正常路径通过检查`n", "*")
        return true
    }
}

Test_C4_BackupCore_UsesInStrNotRegExReplace() {
    ; 验证 backup_core.ahk 的 DeleteBackup 方法不再使用 RegExReplace 删除式过滤
    ; 而是使用 InStr 拒绝式检查（参考 _BridgeRestoreBackup 的正确实现）
    source := GetBackupCoreSource()
    ; 检查是否仍存在正则删除式过滤模式 "\.\."（修复前第 112-113 行）
    if InStr(source, '"\.\."') {
        FileAppend("FAIL: Test_C4_BackupCore_UsesInStrNotRegExReplace - 仍使用 RegExReplace 删除式过滤`n", "*")
        return false
    }
    ; 检查是否使用 InStr 拒绝式检查 ".."
    if InStr(source, '".."') {
        FileAppend("PASS: Test_C4_BackupCore_UsesInStrNotRegExReplace - 已改用 InStr 拒绝式检查`n", "*")
        return true
    } else {
        FileAppend("FAIL: Test_C4_BackupCore_UsesInStrNotRegExReplace - 缺少 InStr 拒绝式检查`n", "*")
        return false
    }
}

; =================================================================
; 执行测试
; =================================================================

FileAppend("=== C3+C4 Security Fix Tests Start ===`n", "*")

; 创建临时测试文件（C4 行为测试依赖）
testFile := CreateTestFile()

passCount := 0
failCount := 0
totalTests := 7

; C3 测试（源码检查）
if Test_C3_CompiledModeNoDebugPort()
    passCount++
else
    failCount++

if Test_C3_NonCompiledNoFlagNoDebugPort()
    passCount++
else
    failCount++

if Test_C3_NonCompiledWithFlagDebugPort()
    passCount++
else
    failCount++

; C4 测试（行为测试 + 源码检查）
if Test_C4_PathTraversal_DoubleDot_Rejected()
    passCount++
else
    failCount++

if Test_C4_PathTraversal_FourDots_Rejected()
    passCount++
else
    failCount++

if Test_C4_NormalPath_Accepted()
    passCount++
else
    failCount++

if Test_C4_BackupCore_UsesInStrNotRegExReplace()
    passCount++
else
    failCount++

; 清理临时测试文件
CleanupTestFile(testFile)

FileAppend("`n=== Summary ===`n", "*")
FileAppend("PASS: " passCount " / FAIL: " failCount " / TOTAL: " totalTests "`n", "*")
FileAppend("=== C3+C4 Security Fix Tests End ===`n", "*")

if failCount > 0
    ExitApp(1)
ExitApp(0)
