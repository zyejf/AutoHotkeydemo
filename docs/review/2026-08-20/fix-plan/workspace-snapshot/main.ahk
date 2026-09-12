; =================================================================
; 技能管理器 v3.0 - 主入口文件
; 版本: 3.0
; 架构: 严格 DDD 四层（domain / infrastructure / application / presentation）
; 说明: 精简的启动入口，负责依赖注入和初始化协调
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

Persistent(true)
InstallKeybdHook()
InstallMouseHook()

; =================================================================
; 第 1 步: 加载基础设施层（无外部依赖）
; =================================================================
#Include "infrastructure\json_serializer.ahk"
#Include "infrastructure\json_logger.ahk"
#Include "infrastructure\json_parser.ahk"
#Include "infrastructure\debug_logger.ahk"
#Include "infrastructure\utils.ahk"
#Include "infrastructure\config_validator.ahk"
#Include "infrastructure\config_store.ahk"
#Include "infrastructure\error_handler.ahk"
#Include "infrastructure\error_system.ahk"
#Include "infrastructure\backup_core.ahk"
#Include "infrastructure\migration_logger.ahk"
#Include "infrastructure\joy_sender.ahk"
#Include "infrastructure\joy_hotkey_manager.ahk"

; =================================================================
; 第 2 步: 加载领域层
; =================================================================
#Include "domain\interfaces.ahk"
#Include "domain\mode_registry.ahk"
#Include "domain\joystick_executor.ahk"
#Include "domain\joystick_input.ahk"
#Include "domain\skill_group.ahk"
#Include "domain\skill_manager.ahk"
#Include "domain\key_recorder.ahk"
#Include "domain\key_validator.ahk"

; =================================================================
; 第 3 步: 加载应用层
; =================================================================
#Include "application\group_service.ahk"
#Include "application\config_service.ahk"

; =================================================================
; 第 4 步: 加载表现层
; =================================================================
#Include "presentation\ui_manager.ahk"
#Include "presentation\gui_manager.ahk"
#Include "presentation\webview2_manager.ahk"

; =================================================================
; 第 5 步: 依赖注入 - 初始化领域层抽象依赖
; =================================================================

InitDependencies() {
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
    SkillManager.OnExitCallback := () => WebView2Manager._StopAutoUpdate()
    SkillManager.RegisterEventHook(WebView2Manager)

    ; 注入手柄发送器实现（依赖倒置：领域层通过 IJoySender 抽象使用）
    JoystickExecutor.SetJoySender(JoySender())

    JoyHotkeyManager.Init(1)
}

; =================================================================
; 第 6 步: 启动
; =================================================================

; 注册运行时错误处理（必须在任何可能出错的代码之前）
OnError(ErrorSystem_HandleError, -1)

try {
    InitDependencies()

    ErrorSystem.Init()

    ModeRegistry._Init()

    UIManager.Init()
    TrayManager.Init()

    ConfigService.LoadConfig()

    OnExit((*) => SkillManager.OnExit())

    WebView2Manager.Show()

    UIManager.Notify("技能管理器 v3.0 [DDD架构] 已启动", "success", 2000)

} catch as e {
    ErrorSystem.LogError("启动失败: " e.Message, "CRITICAL", A_ThisFunc, A_LineNumber)

    try {
        if ModeRegistry.GetRegisteredModes().Length = 0
            ModeRegistry._Init()

        ConfigStore.InitDefaults()
        SkillManager.Init(ConfigStore.Get("GroupSettings"))
        OnExit((*) => SkillManager.OnExit())

        try {
            UIManager.Init()
            TrayManager.Init()
            ConfigService.SaveConfig()
            WebView2Manager.Show()
            UIManager.Notify("启动异常，已加载默认配置", "warning", 5000)
        } catch {
            TrayTip("技能管理器", "启动异常，已加载默认配置", 0x10)
        }
    } catch as fallbackErr {
        ErrorSystem.LogError("降级启动也失败: " fallbackErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
        ExitApp(1)
    }
}
