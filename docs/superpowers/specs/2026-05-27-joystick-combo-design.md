# 手柄按键连招 — 设计文档

> 版本: 1.0 | 日期: 2026-05-27 | 状态: 设计完成

---

## 需求摘要

| 维度 | 决策 |
|------|------|
| 手柄角色 | A(触发) + B(发送) 双方向 |
| 使用场景 | 动作RPG辅助 |
| 手柄类型 | Xbox/XInput + vJoy虚拟手柄 |
| 输入粒度 | 按钮 + 十字键 + 摇杆 + 扳机（全支持） |
| 发送方式 | vJoy + 直接Joy发送，auto自动降级 |
| 集成深度 | 深度集成到现有DDD四层架构 |

---

## 1. 架构总览

采用**对称架构**方案：新增手柄子系统作为键盘系统的平行模块，通过 `ModeRegistry` 插件机制接入，不修改现有7种键盘模式。

```
                        ┌──────────────────────┐
                        │   main.ahk           │
                        │  (启动/初始化)        │
                        └──────┬───────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ joy_hotkey_     │  │  config_service │  │  webview2_      │
│ manager.ahk     │  │  (配置管理)      │  │  manager.ahk    │
│ [infrastructure]│  └────────┬────────┘  │  (UI通信)        │
│ 手柄热键注册/    │          │           └────────┬────────┘
│ 摇杆轮询         │          │                    │
└────────┬────────┘          │                    │
         │                   │                    │ Bridge事件
         ▼                   ▼                    ▼
┌─────────────────────────────────────────────────────┐
│                  领域层 domain/                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │ skill_group  │  │ joystick_    │  │ joystick_  │ │
│  │ (不变)       │  │ executor.ahk │  │ input.ahk  │ │
│  │              │  │ ⭐新增       │  │ ⭐新增      │ │
│  │ 键盘/鼠标组  │  │ 手柄周期/序列│  │ 手柄录制    │ │
│  └──────────────┘  └──────┬───────┘  └───────────┘ │
│                           │                         │
└───────────────────────────┼─────────────────────────┘
                            │ Send
                            ▼
              ┌─────────────────────────┐
              │ joy_sender.ahk          │
              │ [infrastructure] ⭐新增  │
              │ ┌─────────┐┌──────────┐ │
              │ │ vJoy API││直接Send  │ │
              │ └─────────┘└──────────┘ │
              └─────────────────────────┘
```

---

## 2. A方向 — 手柄触发

### 2.1 手柄热键注册 (`joy_hotkey_manager.ahk`)

| 输入类型 | 检测方式 | 原因 |
|---------|---------|------|
| Joy1~Joy32 按钮 | `Hotkey("Joy1", handler, "On")` 原生注册 | 精确、低开销、支持down/up |
| JoyPOV 十字键 | `SetTimer` 50ms轮询 `GetKeyState("JoyPOV")` | AHK不支持POV热键语法 |
| JoyX/Y/Z/R/U/V 轴/扳机 | `SetTimer` 50ms轮询 + 阈值检测 | 连续值需转为离散事件 |

### 2.2 摇杆/扳机阈值触发

```
deadzone  = 20    ← 中心死区，<20 视为"释放"
threshold = 80    ← 大于80触发"按下"
hysteresis = 10   ← 回滞，防抖动
```

例如 `JoyX > 80` 触发"右"，回到 `< 70` 触发"释放"。

### 2.3 热键标识规则

| 类型 | 格式 | 示例 |
|------|------|------|
| 按钮 | `Joy1` ~ `Joy32` | `Joy1`, `Joy6` |
| POV方向 | `JoyPOV_UP/DOWN/LEFT/RIGHT` | `JoyPOV_UP` |
| 左摇杆 | `JoyX_LEFT/RIGHT`, `JoyY_UP/DOWN` | `JoyX_RIGHT` |
| 右摇杆 | `JoyR_LEFT/RIGHT`, `JoyU_UP/DOWN` | `JoyR_LEFT` |
| 扳机 | `JoyZ_DOWN`, `JoyV_DOWN` | `JoyZ_DOWN` |

### 2.4 配置存储扩展

```json
{
  "hotkey": "Joy1",
  "hotkey": "JoyPOV_UP",
  "hotkey": "JoyX_RIGHT",
  "hotkey": "JoyZ_DOWN"
}
```

---

## 3. B方向 — 手柄发送

### 3.1 三种手柄执行模式

注册到 `ModeRegistry` 的3个新模式：

| 模式 | 功能 | 对标键盘模式 |
|------|------|------------|
| `joystick_periodic` | 周期性发送手柄按键 | periodic |
| `joystick_sequence` | 序列发送手柄按键 | sequence |
| `joystick_hold` | 长按手柄按键 | hold |

### 3.2 配置结构

```json
{
  "mode": "joystick_periodic",
  "joyKeys": ["Joy1", "Joy4", "JoyPOV_UP"],
  "joyIntervals": [500, 1000, 300],
  "joyKeyDuration": 50,
  "sendMethod": "vjoy"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `joyKeys` | Array | 手柄按键标识列表 |
| `joyIntervals` | Array | 各按键间隔(ms) |
| `joyKeyDuration` | Int | 按下持续时间(ms)，默认50 |
| `sendMethod` | String | `"vjoy"` / `"direct"` / `"auto"` |

### 3.3 双发送通道 (`joy_sender.ahk`)

```
请求发送 Joy1
       │
  ┌────┴────┐
  ▼         ▼
vJoy API   直接Send
SetAxis()  Send("{Joy1 down}")
SetBtn()   兼容性有限
游戏完美识别
```

**auto 降级策略**：

```
启动 → 检测vJoy
  ├─ vJoy可用 → auto使用vJoy
  │   中途失败 → 降级直接Send + 日志警告
  └─ vJoy不可用 → auto降级直接Send
      强制vJoy → 启动失败，提示安装vJoy驱动
```

### 3.4 JoySender 接口

```autohotkey
class JoySender {
    static SendBtn(btnNum, state, method := "vjoy")  ; Joy1~Joy32 按下/释放
    static SendPov(direction, method := "vjoy")       ; UP/DOWN/LEFT/RIGHT/CENTER
    static SendAxis(axis, value, method := "vjoy")    ; JoyX/Y/Z/R/U/V 0~100
    static IsVJoyAvailable()                          ; 检测vJoy驱动
}
```

---

## 4. UI集成

### 4.1 模式下拉新增3项

在现有7种模式后追加：
- `joystick_periodic` — 手柄周期
- `joystick_sequence` — 手柄序列
- `joystick_hold` — 手柄长按

选择手柄模式后，按键编辑区自动切换为手柄按键选择器。

### 4.2 热键捕获升级

点击"设置热键"进入监听模式，**同时监听键盘和手柄**：

| 操作 | 显示 | 存储 |
|------|------|------|
| 按下 Joy1 | 🎮 按钮1 (A) | `Joy1` |
| 推左摇杆→ | 🎮 左摇杆→ | `JoyX_RIGHT` |
| 按十字键↑ | 🎮 十字键↑ | `JoyPOV_UP` |
| 扣LT扳机 | 🎮 左扳机 | `JoyZ_DOWN` |

### 4.3 手柄按键选择器

```
┌─ 手柄按键配置 ─────────────────────────┐
│                                        │
│  按键1: [🎮 Joy1(A) ▼]    间隔: [500]ms│
│  按键2: [🎮 Joy2(B) ▼]    间隔: [300]ms│
│  按键3: [🎮 POV→    ▼]    间隔: [200]ms│
│                                        │
│  [+ 添加按键]  [🎙 手柄录制]            │
│                                        │
│  发送方式:  [vJoy ▼]                   │
│  按键时长:  [50]ms                      │
└────────────────────────────────────────┘
```

下拉选项分组：
```
─ 按钮 ──────────
  Joy1 (A) / Joy2 (B) / Joy3 (X) / Joy4 (Y)
  Joy5 (LB) / Joy6 (RB) / Joy7 (Back) / Joy8 (Start)
  Joy9 (LS) / Joy10 (RS)
─ 十字键 ────────
  JoyPOV_UP / JoyPOV_DOWN / JoyPOV_LEFT / JoyPOV_RIGHT
─ 摇杆 ──────────
  JoyX_LEFT / JoyX_RIGHT / JoyY_UP / JoyY_DOWN
  JoyR_LEFT / JoyR_RIGHT / JoyU_UP / JoyU_DOWN
─ 扳机 ──────────
  JoyZ_DOWN / JoyV_DOWN
```

### 4.4 仪表盘适配

分组卡片热键显示适配：
- 键盘: `F1` → `F1`
- 手柄: `Joy1` → `🎮 A`

### 4.5 按键测试页新增手柄测试区

```
┌─ 🎮 手柄测试 ───────────────────────────┐
│  已连接: Xbox Controller ✓               │
│  按钮状态: 实时显示Joy1~Joy32按下状态     │
│  左摇杆: X=50 Y=50                       │
│  右摇杆: X=50 Y=50                       │
│  十字键: ───                             │
│  扳机: LT=0 RT=0                         │
│  [开始录制] [停止录制]                    │
└──────────────────────────────────────────┘
```

---

## 5. 错误处理

| 场景 | 检测方式 | 处理策略 |
|------|---------|---------|
| 无手柄连接 | `GetKeyState("Joy1")` 检测 | toast提示，手柄功能降级但系统正常运行 |
| vJoy驱动未安装 | `DllCall` 加载失败 | auto→direct降级，日志记录；强制vJoy则启动失败 |
| 多手柄冲突 | 枚举获取设备列表 | 默认1号手柄，配置中可选 `joystickId` |
| 手柄热插拔 | 30s定时检测 `JoyButtons` | 丢失→暂停手柄分组；恢复→提示重连 |
| 摇杆轮询泄漏 | 分组停止时清理Timer | 复用 `executionId` 机制 |
| 热键冲突 | 注册前检查 | 与键盘同逻辑，toast提示 |

---

## 6. 测试策略

| 层 | 测试文件 | 覆盖内容 |
|----|---------|---------|
| 单元 | `test_joystick.ahk` | JoySender发送、输入标识解析、按钮/轴/POV |
| 单元 | `test_joystick.ahk` | JoystickExecutor三模式周期/序列/长按时序 |
| 集成 | `test_joystick.ahk` | joy_hotkey_manager注册/轮询/冲突检测 |
| 集成 | 现有测试 | config.json手柄字段序列化 |
| E2E | agent-browser | app_ui.html手柄UI交互 |

---

## 7. 文件变更清单

| 操作 | 文件 | 行数估计 | 说明 |
|------|------|---------|------|
| ⭐新增 | `domain/joystick_executor.ahk` | ~180行 | 手柄三模式执行器(实现IExecutor) |
| ⭐新增 | `domain/joystick_input.ahk` | ~120行 | 手柄输入录制(对应KeyRecorder) |
| ⭐新增 | `infrastructure/joy_sender.ahk` | ~150行 | vJoy API + 直接Send双通道 |
| ⭐新增 | `infrastructure/joy_hotkey_manager.ahk` | ~100行 | 热键注册/轴轮询/热插拔检测 |
| ✏️修改 | `domain/mode_registry.ahk` | +15行 | 注册3种新模式 |
| ✏️修改 | `main.ahk` | +10行 | 引入新文件 + 初始化 |
| ✏️修改 | `presentation/app_ui.html` | ~200行 | 手柄UI(模式/选择器/测试区) |
| ✏️修改 | `config.json` | +10行 | 扩展schema注释 |
| ⭐新增 | `tests/test_joystick.ahk` | ~100行 | 手柄单元测试 |

**总计：约885行新增代码，4新增+4修改共8个文件。**