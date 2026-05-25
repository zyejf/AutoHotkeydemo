; =================================================================
; 领域层 - 抽象接口定义（依赖倒置基础）
; 版本: 3.0
; 说明: 定义领域层所需的全部抽象基类
;       遵循严格依赖倒置原则（Dependency Inversion Principle）
;       domain 层不依赖任何具体实现，所有依赖通过抽象接口表达
;       AHK v2 无 interface 关键字，使用抽象基类 + 文档约定模拟
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; =================================================================
; 日志接口 - ILogger
; 契约:
;   Log(level, message, context) - 记录一条日志
;   level: "ERROR" | "WARNING" | "DEBUG"
;   message: 日志消息
;   context: Map 对象，包含 traceId / module / spanId 等上下文
; =================================================================
class ILogger {
    Log(level, message, context := "") {
        throw Error("ILogger.Log: 抽象方法，子类必须实现")
    }

    Error(message, context := "") {
        this.Log("ERROR", message, context)
    }

    Warning(message, context := "") {
        this.Log("WARNING", message, context)
    }

    Debug(message, context := "") {
        this.Log("DEBUG", message, context)
    }
}

; =================================================================
; 通知接口 - INotifier
; 契约:
;   Notify(message, type, duration) - 向用户发送通知
;   type: "success" | "error" | "warning" | "info"
;   duration: 显示时长（毫秒），0 或省略表示默认值
; =================================================================
class INotifier {
    ; 显示状态通知（抽象方法 - 子类必须实现）
    Notify(message, type := "info", duration := 0) {
        throw Error("INotifier.Notify: 抽象方法，子类必须实现")
    }

    ; 显示简要信息
    ShowBriefInfo(activeCount, emergencyMode) {
        throw Error("INotifier.ShowBriefInfo: 抽象方法，子类必须实现")
    }
}

; =================================================================
; 配置存储接口 - IConfigStore
; 契约:
;   Load()  - 加载配置，返回配置对象
;   Save(config) - 保存配置，返回成功/失败
;   Get(key, default) - 读取单个配置项
;   Set(key, value) - 写入单个配置项
; =================================================================
class IConfigStore {
    Load() {
        throw Error("IConfigStore.Load: 抽象方法，子类必须实现")
    }

    Save(config) {
        throw Error("IConfigStore.Save: 抽象方法，子类必须实现")
    }

    Get(key, default := "") {
        throw Error("IConfigStore.Get: 抽象方法，子类必须实现")
    }

    Set(key, value) {
        throw Error("IConfigStore.Set: 抽象方法，子类必须实现")
    }

    Has(key) {
        throw Error("IConfigStore.Has: 抽象方法，子类必须实现")
    }
}

; =================================================================
; 执行器接口 - IExecutor
; 契约:
;   Execute(group) - 执行一个技能组的按键操作
;   group: SkillGroup 实例
;   返回: 下次执行的延迟时间（毫秒），0 表示不需要继续执行
; =================================================================
class IExecutor {
    Execute(group) {
        throw Error("IExecutor.Execute: 抽象方法，子类必须实现")
    }

    GetModeName() {
        throw Error("IExecutor.GetModeName: 抽象方法，子类必须实现")
    }
}

; =================================================================
; 健康检查接口 - IHealthChecker
; 契约:
;   Check() - 执行健康检查，返回 {healthy: bool, issues: Array}
; =================================================================
class IHealthChecker {
    Check() {
        throw Error("IHealthChecker.Check: 抽象方法，子类必须实现")
    }
}

; =================================================================
; 事件钩子接口 - IEventHook
; 契约:
;   OnEvent(event, data) - 事件触发时的回调
;   event: "onActivate" | "onDeactivate" | "onError" | "onConfigChange" 等
;   data: 事件相关数据
; =================================================================
class IEventHook {
    OnEvent(event, data) {
        throw Error("IEventHook.OnEvent: 抽象方法，子类必须实现")
    }
}
