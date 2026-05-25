; =================================================================
; 基础设施层 - 统一错误处理与自愈系统
; 版本: 3.0
; 说明: 统一异常分类与处理，支持自动恢复策略
;       包括: 重试、降级、回滚、资源保护
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_logger.ahk"
#Include "utils.ahk"
#Include "error_system.ahk"

class ErrorHandler {
    ; =================================================================
    ; 异常分类
    ; =================================================================
    static CATEGORY_BUSINESS := "BUSINESS"
    static CATEGORY_SYSTEM := "SYSTEM"
    static CATEGORY_VALIDATION := "VALIDATION"
    static CATEGORY_IO := "IO"
    static CATEGORY_NETWORK := "NETWORK"

    ; =================================================================
    ; 重试策略
    ; =================================================================
    static RetryWithPolicy(action, maxRetries := 3, delayMs := 100, category := "SYSTEM") {
        lastError := ""

        loop maxRetries {
            try {
                return action()
            } catch as e {
                lastError := e.Message
                JSONLogger.Log("WARNING", "重试 " A_Index "/" maxRetries " 失败: " e.Message,
                              Map("module", "ErrorHandler", "code", "W_RETRY"))

                if A_Index < maxRetries
                    Sleep(Min(delayMs * A_Index, 500))
            }
        }

        JSONLogger.Log("ERROR", "重试 " maxRetries " 次后仍失败: " lastError,
                      Map("module", "ErrorHandler", "code", "E_RETRY_EXHAUSTED"))
        throw Error("操作失败 (已重试 " maxRetries " 次): " lastError)
    }

    ; =================================================================
    ; 降级策略
    ; =================================================================
    static SafeExecute(action, fallback := "", category := "SYSTEM") {
        try {
            return action()
        } catch as e {
            JSONLogger.Log("ERROR", "执行失败，使用降级策略: " e.Message,
                          Map("module", "ErrorHandler", "category", category))

            if IsObject(fallback)
                return fallback()
            return fallback
        }
    }

    ; =================================================================
    ; 资源保护 - 定时器泄漏检测
    ; =================================================================
    static maxTimers := 100
    static maxActiveGroups := 10

    static CheckTimerLeak(timerMap) {
        if timerMap is Map && timerMap.Count > ErrorHandler.maxTimers {
            JSONLogger.Log("WARNING", "定时器数量超过阈值: " timerMap.Count " > " ErrorHandler.maxTimers,
                          Map("module", "ErrorHandler", "code", "W_TIMER_LEAK"))

            count := 0
            for id, timerRef in timerMap {
                try {
                    SetTimer(timerRef, 0)
                    count++
                }
            }
            timerMap.Clear()
            JSONLogger.Log("DEBUG", "已清理 " count " 个孤立定时器",
                          Map("module", "ErrorHandler"))
            return true
        }
        return false
    }

    ; =================================================================
    ; 卡键自动释放
    ; =================================================================
    static maxHoldDuration := 60000

    static CheckStuckKeys(heldKeys) {
        if !(heldKeys is Map)
            return false

        released := false
        keysToRelease := []

        for k, startTime in heldKeys {
            if A_TickCount - startTime > ErrorHandler.maxHoldDuration {
                keysToRelease.Push(k)
            }
        }

        if keysToRelease.Length > 0 {
            JSONLogger.Log("ERROR", "检测到 " keysToRelease.Length " 个卡住的键，自动释放",
                          Map("module", "ErrorHandler", "code", "E_STUCK_KEY"))

            for k in keysToRelease {
                try {
                    baseKey := RegExReplace(k, "^[\^+!#]+", "")
                    SendInput("{Blind}{" baseKey " Up}")
                }
                heldKeys.Delete(k)
            }
            return true
        }
        return false
    }

    ; =================================================================
    ; 日志文件膨胀保护
    ; =================================================================
    static maxLogFileSize := 10 * 1024 * 1024

    static CheckLogFileSize(filePath) {
        if !FileExist(filePath)
            return false

        try {
            size := FileGetSize(filePath)
            if size > ErrorHandler.maxLogFileSize {
                JSONLogger.Log("WARNING", "日志文件超过大小限制: " Round(size / 1024 / 1024, 1) "MB，执行轮转",
                              Map("module", "ErrorHandler"))
                LogRotator.Rotate(filePath, 5)
                return true
            }
        }
        return false
    }

    ; =================================================================
    ; 健康检查
    ; =================================================================
    static HealthCheck(skillManager) {
        issues := []
        activeCount := skillManager.GetActiveCount()

        if skillManager.EmergencyMode
            issues.Push(Map("type", "CRITICAL", "message", "紧急模式已激活"))

        if activeCount > ErrorHandler.maxActiveGroups
            issues.Push(Map("type", "WARNING", "message", "活动分组过多: " activeCount))

        timerCount := skillManager.GetTimerCount()
        if timerCount > activeCount * 2
            issues.Push(Map("type", "WARNING", "message", "检测到定时器泄漏: " timerCount "个定时器 vs " activeCount "个活动分组"))

        return Map(
            "healthy", issues.Length = 0,
            "issues", issues,
            "timestamp", ErrorSystem._FormatISO8601(A_Now),
            "activeCount", activeCount,
            "holdKeyCount", skillManager.HoldKeyRegistry.Count
        )
    }
}
