; =================================================================
; AutoHotUnit 测试运行器 - 完整测试套件（v4.1 模块化：套件定义拆分至 suites/ 目录）
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "AutoHotUnit.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/config_io.ahk"
#Include "../infrastructure/ipc_channel.ahk"
#Include "../application/config_service.ahk"
#Include "../application/group_service.ahk"
#Include "../application/backup_service.ahk"
#Include "../presentation/ui_manager.ahk"
#Include "../presentation/group_editor.ahk"
#Include "../presentation/gui_manager.ahk"
#Include "../presentation/debug_panel.ahk"
#Include "../presentation/webview2_manager.ahk"

; ============================================================
; AHK 执行器测试（asd-tauri/src-tauri/ahk_executor/）
; ============================================================
#Include "test_ahk_executor/test_executor.ahk"
#Include "test_ahk_executor/test_ipc_client.ahk"
#Include "test_ahk_executor/test_hotkey_hook.ahk"
#Include "test_ahk_executor/test_sender.ahk"
#Include "test_ahk_executor/test_joystick.ahk"

; ============================================================
; joy_hotkey_manager 测试（infrastructure/）
; ============================================================
#Include "test_joy_hotkey_manager_ahu.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; ============================================================
; 测试套件定义（v4.1 按模块拆分至 suites/ 目录）
; ============================================================
#Include "suites/core_suites.ahk"
#Include "suites/base_suites.ahk"
#Include "suites/fix_round_suites.ahk"
#Include "suites/layering_security_suites.ahk"

; 创建静默报告器
reporter := SilentReporter(A_ScriptDir "\test_results.log")

; 创建测试管理器
testManager := AutoHotUnitManager(reporter)

; 初始化 ModeRegistry（注册所有内置模式）
ModeRegistry._Init()

; 全局注入 MockJoySender，确保所有测试套件中 JoystickExecutor 可正常工作
; 避免摇杆分组停用/执行时抛出 "JoySender 未注入" 异常
JoystickExecutor.SetJoySender(MockJoySender())

; 注册所有测试套件
testManager.RegisterSuite(
    InterfaceContractTests, 
    ModeRegistryTests, 
    ModeRegistryExecutorTests, 
    SkillGroupTests,
    SkillManagerTests,
    JSONParserTests,
    JSONSerializerTests,
    ConfigStoreTests,
    ConfigValidatorTests,
    ErrorSystemTests,
    DebugLoggerTests,
    JSONLoggerTests,
    BackupCoreTests,
    LogRotatorTests,
    JSONSerializerCircularTests,
    JSONParserLoopProtectionTests,
    SkillGroupKeyValidationTests,
    SkillGroupHoldStartTests,
    SkillManagerDeleteGroupTests,
    JSONParserResetStateTests,
    ConfigStoreMapTypeTests,
    ErrorHandlerHealthCheckTests,
    GroupEditorModeMappingTests,
    GetPropUtilTests,
    SkillGroupMapAccessTests,
    IDTypeConsistencyTests,
    MapIterationSafetyTests,
    ConfigSaveTests,
    LogRotationTests,
    HoldPatternTriggerTests,
    ModeRegistryMapTests,
    ILoggerNoInfoTests,
    ConfigValidatorMapFormatTests,
    GUIManagerModeNamesTests,
    HealthCheckEncapsulationTests,
    BackupCoreThrottleTests,
    JSONParseContextIsolationTests,
    ToggleAllUsesToggleGroupTests,
    SkillGroupToggleExceptionTests,
    ConfigValidatorAllMapFormatTests,
    ValidateGroupOnlyNoDoubleWrapTests,
    JSONLoggerMaxErrorsTests,
    GetRuntimeStatusMapTests,
    HealthCheckTimestampTests,
    BackupCoreSortTests,
    HotkeyEditorNormalizeTests,
    MathTests,
    StringTests,
    ArrayTests,
    MapTests,
    SequenceHoldTriggersMultiKeyTests,
    SaveConfigNoDoubleSerializeTests,
    RestoreBackupAtomicTests,
    JSONErrorModulePropertyTests,
    DebugLoggerEnforceSizeTests,
    GroupServiceRollbackSafetyTests,
    ToggleAllAccurateNotifyTests,
    JSONSerializerSpacesCacheTests,
    HealthCheckMaxActiveGroupsTests,
    IPCPollMessagesOrderTests,
    ConfigStoreSetUnknownKeyTests,
    ExecutorTimerGuardTests,
    HotReloadEmergencyResetTests,
    ToggleDebounceReturnTests,
    CopyGroupIdGenerationTests,
    BackupSortAlgorithmTests,
    BackupServiceLayeringTests,
    ConfigIOLayeringTests,
    JSONLoggerModuleDefaultTests,
    DebounceCacheTests,
    HealthCheckTimestampFormatTests,
    CreateGroupFailureConsistencyTests,
    ActiveCountComputedPropertyTests,
    CleanupOrphanTimersSelectiveTests,
    KeyPressDurationMaxLimitTests,
    RestoreBackupSafetyFileTests,
    ConfigStoreSetReturnTests,
    ParseIntArrayErrorReportTests,
    IPCChannelFallbackReadTests,
    IsValidKeyNameExpandedTests,
    AutoRefreshIncrementalTests,
    OnExitUITimerCleanupTests,
    HealthCheckGetActiveCountCacheTests,
    ConfigImportSecurityTests,
    GuiAndTimerSpecTests,
    IPCChannelInitSafetyTests,
    ConfigServiceFileCopyCatchTests,
    ConfigValidatorNumericLimitTests,
    WebView2TempFileNamingTests,
    WebView2PushStateNoRedundantParseTests,
    FixtureUsageTests,
    JoystickExecutorInjectionTimerTests,
    LogRateLimitTests
)

; ============================================================
; 注册 AHK 执行器测试套件（asd-tauri/src-tauri/ahk_executor/）
; ============================================================
testManager.RegisterSuite(
    CommandDispatcherGetStrTests,
    CommandDispatcherGetIntTests,
    CommandDispatcherGetBoolTests,
    CommandDispatcherGetArrTests,
    CommandDispatcherGetMapTests,
    CommandDispatcherMergeModeConfigTests,
    CommandDispatcherDispatchUnknownTests,
    CommandDispatcherRecordKeyTests,
    CommandDispatcherValidationTests,
    CommandDispatcherReportFlagTests,
    IPCConstTests,
    MiniJsonParseObjectTests,
    MiniJsonParseArrayTests,
    MiniJsonParseScalarTests,
    MiniJsonStringifyTests,
    MiniJsonRoundTripTests,
    MiniJsonBoolMarkerTests,
    IpcClientInitialStateTests,
    IpcClientNextSeqTests,
    IpcClientSendDisconnectedTests,
    IpcClientParseAuthTokenTests,
    IpcClientDeduplicationTests,
    HotkeyHookNormalizeTests,
    HotkeyHookRegistrationStateTests,
    HotkeyHookRegisterErrorTests,
    HotkeyHookUnregisterErrorTests,
    HotkeyHookUnregisterAllTests,
    HotkeyHookInitTests,
    HotkeyHookCallbackTests,
    SenderAllowedKeysTests,
    SenderValidateKeyTests,
    SenderToggleGroupTests,
    SenderStartPeriodicTests,
    SenderStartSequenceTests,
    SenderStartEnhancedTests,
    SenderStartHoldTests,
    SenderHoldModeToggleTests,
    SenderEmergencyReleaseTests,
    SenderShutdownTests,
    SenderInitTests,
    SenderReportKeyEventsTests,
    JoystickAllowedKeysTests,
    JoystickValidateKeyTests,
    JoystickIsButtonTests,
    JoystickGetButtonNumTests,
    JoystickIsPovTests,
    JoystickGetPovDirectionTests,
    JoystickIsAxisTests,
    JoystickGetAxisInfoTests,
    JoystickAxisToVJoyIdTests,
    JoystickPovDirectionToValueTests,
    JoystickResolveMethodTests,
    JoystickIsVJoyAvailableTests,
    JoystickStopGroupTests,
    JoystickEmergencyReleaseTests,
    JoystickInitTests,
    JoystickStartPeriodicTests,
    JoystickStartSequenceTests,
    JoystickStartHoldTests
)

; ============================================================
; 注册 joy_hotkey_manager 测试套件
; ============================================================
testManager.RegisterSuite(
    JoyHotkeyRegisterTests,
    JoyHotkeyUnregisterTests,
    JoyHotkeyMultiJoystickTests,
    JoyHotkeyPollingLogicTests,
    JoyHotkeyPollingTimerTests,
    JoyHotkeyCallbackTests,
    JoyHotkeyReviewFixTests
)

; 运行测试
testManager.RunSuites()

; 退出程序
ExitApp(0)