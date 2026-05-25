# 按键测试页面设计规格

日期: 2026-05-21
状态: 已批准

## 1. 概述

在现有 WebView2 仪表盘中集成"按键测试"页面，提供两个独立功能：

1. **录制模式**：捕获用户真实按键的时间间隔和顺序，可导出为分组配置
2. **验证模式**：监控分组启动后按键的实际发送时序，生成验证报告

## 2. 架构

### 2.1 方案选择

方案 A：WebView2 桥接 — 前端 UI + AHK InputHook 桥接，实时推送事件

### 2.2 新增文件

| 文件 | 层级 | 职责 |
|------|------|------|
| `domain/key_recorder.ahk` | 领域层 | 按键录制器，使用 InputHook 捕获键盘/鼠标事件 |
| `domain/key_validator.ahk` | 领域层 | 执行验证器，在 _SendKey/_SendHoldKey 中埋点收集时序 |
| `presentation/app_ui.html` | 表现层 | 新增"按键测试"页面（导航栏第6项） |

### 2.3 数据流

**录制模式**：
用户点击"开始录制" → KeyRecorder.Start() → InputHook 启动 → 每次按键事件通过 Bridge 推送到前端 → 前端记录时间戳并绘制时序图 → 停止录制后可导出配置

**验证模式**：
用户选择分组 + 点击"开始验证" → KeyValidator.Start(groupId) → _SendKey/_SendHoldKey 埋点触发 → 每次发送通过 Bridge 推送 → 前端实时绘制执行时序 → 停止后生成验证报告

## 3. KeyRecorder 录制器

### 3.1 类设计

```ahk
class KeyRecorder {
    static _hook := 0
    static _recording := false
    static _events := []
    static _startTime := 0
    static _onEvent := ""
    
    static Start(onEvent)
    static Stop() => Map("events", this._events, "duration", A_TickCount - this._startTime)
    static IsRecording() => this._recording
    static OnKey(key, event, timestamp)
    static OnMouse(button, event, timestamp)
    static ExportAsGroupConfig(mode, keyPressDuration) => Map
}
```

### 3.2 事件格式

```json
{
    "key": "A",
    "event": "down",
    "timestamp": 1234,
    "device": "keyboard"
}
```

event 取值: "down" | "up" | "click" | "wheel"
device 取值: "keyboard" | "mouse"

### 3.3 InputHook 配置

- InputHook Notify 回调捕获所有按键
- 鼠标事件通过 OnMessage 捕获（0x200/0x201/0x202/0x204/0x205/0x206/0x20A）
- 修饰键单独处理，记录组合键

### 3.4 导出为分组配置

录制停止后，前端计算相邻同键 down 事件的时间间隔：
- 周期性模式: keys + intervals
- 序列模式: keys + delays
- 用户可在导出前选择模式和调整参数

## 4. KeyValidator 验证器

### 4.1 类设计

```ahk
class KeyValidator {
    static _active := false
    static _groupId := ""
    static _expectedSeq := []
    static _actualSeq := []
    static _startTime := 0
    static _onEvent := ""
    
    static Start(groupId, onEvent)
    static Stop() => Map (验证报告)
    static IsActive() => this._active
    static OnSend(groupId, key, event, timestamp)
    static _BuildReport() => Map
}
```

### 4.2 埋点机制

在 SkillGroup._SendKey 和 _SendHoldKey 中添加：

```ahk
if KeyValidator._active
    KeyValidator.OnSend(this.id, key, "press", A_TickCount - KeyValidator._startTime)
```

仅在 KeyValidator 激活时执行，不影响正常性能。

### 4.3 验证报告指标

| 指标 | 计算方式 | 通过标准 |
|------|----------|----------|
| 顺序正确性 | 实际发送顺序 vs 配置顺序 | 100% 匹配 |
| 间隔偏差 | 实际间隔 vs 配置间隔 | ±20% 良好, ±50% 可接受 |
| 发送成功率 | 成功发送次数 / 应发送次数 | >= 95% |
| 长按时序 | 按下/释放时间差 vs holdDuration | ±30% 以内 |

### 4.4 报告格式

```json
{
    "groupId": "1",
    "duration": 5000,
    "totalExpected": 50,
    "totalActual": 48,
    "orderCorrect": true,
    "avgIntervalDeviation": 3.2,
    "maxIntervalDeviation": 8.5,
    "sendSuccessRate": 0.96,
    "holdTimingCorrect": true,
    "details": [
        {"key": "A", "expectedInterval": 50, "actualInterval": 52, "deviation": 4.0, "status": "good"},
        {"key": "B", "expectedInterval": 50, "actualInterval": 75, "deviation": 50.0, "status": "poor"}
    ]
}
```

## 5. 前端 UI

### 5.1 页面布局

新增导航项"按键测试"，页面分为两个独立 Tab：录制和验证。

### 5.2 录制 Tab

- 开始/停止录制按钮
- 录制计时器
- Canvas 时序图（绿色条=按下时长，圆点=点击）
- 事件列表（序号、键名、事件类型、时间戳）
- 导出选项（模式选择、按键时长、导出按钮）

### 5.3 验证 Tab

- 分组选择下拉框
- 开始/停止验证按钮
- Canvas 时序图（绿色=实际，蓝色虚线=期望，红色=偏差过大）
- 验证报告（顺序正确性、间隔偏差、发送成功率、长按时序）

### 5.4 Bridge 新增消息

| Action | 方向 | 说明 |
|--------|------|------|
| StartRecording | 前端→后端 | 开始录制 |
| StopRecording | 前端→后端 | 停止录制 |
| StartValidation | 前端→后端 | 开始验证（含 groupId） |
| StopValidation | 前端→后端 | 停止验证 |
| ExportRecording | 前端→后端 | 导出录制为分组配置 |
| onKeyEvent | 后端→前端 | 录制事件推送 |
| onSendEvent | 后端→前端 | 验证事件推送 |

## 6. 约束与延后

- 游戏手柄支持延后实现，通过 ModeRegistry 插件式扩展
- 录制和验证完全独立，可分别使用
- 埋点仅在 KeyValidator 激活时执行，不影响正常性能
