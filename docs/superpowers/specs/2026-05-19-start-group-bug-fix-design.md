# 启动分组功能 BUG 全面修复设计

日期: 2026-05-19
状态: 已批准
方案: C - 全面重构

## 已确认 BUG 清单

| 编号 | 严重程度 | 描述 | 根因 |
|------|---------|------|------|
| BUG-1 | 严重 | enhanced_hybrid 空子组 pressKeys 导致定时器空转 | ConfigValidator 不验证空数组 |
| BUG-4 | 严重 | 未注册模式导致 Execute 静默失败 | ModeRegistry.GetExecutor 返回空字符串 |
| BUG-5 | 中等 | 定时器竞态：外部删除 _timers 后闭包仍执行 | executor 闭包缺乏原子性检查 |
| BUG-6 | 中等 | hold 模式 holdDuration 到期后 active 状态不同步 | HoldExecutor 返回 0 但不更新 active |
| BUG-10 | 中等 | _lastSend 在分组停用后未清空 | Toggle/Dispose 不清理 _lastSend |
| BUG-3 | 轻微 | config.json 与 InitDefaults 配置不一致 | 缺少配置同步机制 |
| BUG-8 | 轻微 | enhanced_periodic/sequence 空数组通过验证 | 同 BUG-1 |

## 模块 1：配置验证体系重构

### 1.1 ModeRegistry Schema 增强

在 ModeRegistry._Init() 的 meta 参数中增加 requiresNonEmpty 字段：

```
ModeRegistry.Register("enhanced_periodic", EnhancedPeriodicExecutor(), Map(
    "name", "增强周期",
    "description", "周期性按键 + 可选长按功能",
    "requires", ["pressKeys", "intervals"],
    "requiresNonEmpty", ["pressKeys"]    ; 新增：这些字段必须非空数组
))
```

各模式的 requiresNonEmpty 定义：
- periodic: ["keys"]
- sequence: ["keys"]
- hybrid: ["groups"]
- enhanced_periodic: ["pressKeys"]
- enhanced_sequence: ["pressKeys"]
- enhanced_hybrid: ["groups"]
- hold: ["holdKeys"]

### 1.2 ConfigValidator 增强

在 _ValidateModeFields 中增加：
1. 空数组检查：对 requiresNonEmpty 中的字段，检查存在性 AND 非空
2. 子组结构验证：对 hybrid/enhanced_hybrid 的 groups，验证每个子组的 pressKeys 非空
3. 字段值范围检查：keyPressDuration 5-100, holdDuration >= 0

### 1.3 SkillGroup 构造函数防御

在 _SetupMode 末尾增加 _ValidateConfig 方法调用：
- 检查当前模式的关键按键数组是否非空
- 非空时正常创建，空时记录 WARNING 日志但允许创建（不抛异常，避免破坏现有功能）
- 在 Execute 中增加短路返回：如果按键数组为空，直接返回 0（停止定时器）

## 模块 2：ModeRegistry 防御性增强

### 2.1 GetExecutor 改为抛异常

```autohotkey
static GetExecutor(modeName) {
    if !this._executors.Has(modeName)
        throw ValueError("未注册的执行模式: " modeName)
    return this._executors[modeName]
}
```

### 2.2 SkillGroup 构造函数验证模式

在 __New 中 _SetupMode 之前：
```autohotkey
if !ModeRegistry.HasMode(this.mode)
    throw ValueError("无效的执行模式: " this.mode)
```

### 2.3 Execute 方法保留 try-catch

捕获 ValueError 和其他异常，返回 0（停止定时器）而非 10（继续重试）。

## 模块 3：执行状态同步修复

### 3.1 _StartGroupExecution 闭包增强

增加 _executionId 机制：
```autohotkey
static _StartGroupExecution(id) {
    this._StopGroupExecution(id)
    if !this.Groups.Has(id)
        return

    executionId := A_TickCount . id  ; 唯一执行 ID
    this._executionIds[id] := executionId

    executor(gId, execId) {
        ; 检查执行 ID 是否匹配（防止旧闭包继续执行）
        if SkillManager._executionIds[gId] != execId {
            return
        }
        if !SkillManager.Groups.Has(gId) || !SkillManager._timers.Has(gId) {
            SkillManager._StopGroupExecution(gId)
            return
        }
        grp := SkillManager.Groups[gId]
        if SkillManager.EmergencyMode || !grp.active {
            SkillManager._StopGroupExecution(gId)
            return
        }
        delay := grp.Execute()
        if delay > 0 && SkillManager._timers.Has(gId) && SkillManager._executionIds[gId] = execId {
            timerRef := SetTimer(executor.Bind(gId, execId), -delay)
            if IsObject(timerRef)
                SkillManager._timers[gId] := timerRef
        } else if delay <= 0 {
            SkillManager._StopGroupExecution(gId)
        }
    }

    timerRef := SetTimer(executor.Bind(id, executionId), -10)
    if IsObject(timerRef)
        this._timers[id] := timerRef
}
```

### 3.2 HoldExecutor 状态同步

返回 0 时同步设置 active := false：
```autohotkey
if (A_TickCount - group._holdStartTime > group.holdDuration) {
    if group.autoRepeat {
        ; ... autoRepeat 逻辑不变
    } else {
        group.active := false
        return 0
    }
}
```

### 3.3 Toggle/Dispose 清理 _lastSend

在 Toggle() 的关闭分支和 Dispose() 中增加：
```autohotkey
this._lastSend.Clear()
```

## 模块 4：配置一致性修复

### 4.1 ConfigStore.Load 增强

加载 config.json 后对每个分组运行验证：
```autohotkey
static Load() {
    ; ... 现有加载逻辑
    if configFromFile is Map && configFromFile.Has("GroupSettings") {
        for id, groupConfig in configFromFile["GroupSettings"] {
            errors := ConfigValidator.ValidateGroupOnly(id, groupConfig)
            if errors.Length > 0 {
                ; 用 InitDefaults 的值补充缺失字段
                defaultConfig := this._GetDefaultGroupConfig(id)
                if defaultConfig is Map
                    groupConfig := this._MergeWithDefaults(groupConfig, defaultConfig)
            }
        }
    }
}
```

### 4.2 配置合并策略

_MergeWithDefaults 方法：
- 遍历 defaultConfig 的所有键
- 如果 groupConfig 中缺少该键或值为空数组，用 defaultConfig 的值补充
- 保留 groupConfig 中已有的有效值

### 4.3 配置差异日志

加载时检测并记录差异到 JSONLogger。

## 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| domain/mode_registry.ahk | GetExecutor 抛异常；_Init 增加 requiresNonEmpty |
| domain/skill_group.ahk | 构造函数验证模式；Execute 短路返回；Toggle/Dispose 清理 _lastSend |
| domain/skill_manager.ahk | _StartGroupExecution 增加 executionId；_StopGroupExecution 清理 executionId |
| infrastructure/config_validator.ahk | 增加空数组检查、子组验证、值范围检查 |
| infrastructure/config_store.ahk | Load 增加验证和合并逻辑 |
| tests/test_bug_reproduction.ahk | 更新断言以匹配修复后的行为 |

## 测试策略

每个模块修复后：
1. 运行 test_bug_reproduction.ahk 验证 BUG 已修复
2. 运行对应层的完整测试套件确保无回归
3. 运行集成测试确保跨层交互正常
