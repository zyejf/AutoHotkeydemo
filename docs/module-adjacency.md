# 模块邻接表

> **定位**：`docs/graph-driven-workflow.md` §2 的**数据附录**——提供逐文件粒度的入边/出边清单。
> **数据来源**：由 `.review-analysis/build_graph.py` 从源码的 `#Include` / `use` 语句**自动提取**，非人工维护。
> **重新生成**：见 `docs/graph-driven-workflow.md` 附录 A。本文件在框图变化后需重跑脚本刷新。
> **权威关系**：本表是**依赖关系的权威数据**；分层规则与妥协登记查 `AGENTS.md`；流程方法查 `docs/graph-driven-workflow.md`。

---

## 使用说明

| 符号 | 含义 |
|------|------|
| **OUT** | 出边——本模块 `#Include` 的其它模块（本模块依赖谁） |
| **IN** | 入边——`#Include` 本模块的其它模块（谁依赖本模块） |
| ⚠️ | 该边为**分层反向边**（内层依赖外层），必须登记在 `AGENTS.md` 妥协表 |
| 🔴 | 高频变更 / 高影响面模块（改动前必查 `docs/graph-driven-workflow.md` §4.4） |

**模块总数**：32 个生产模块（`domain` 8 + `infrastructure` 15 + `application` 3 + `presentation` 6）。

> **口径提示**：此处「32 个生产模块」只统计四层生产代码；`graph-driven-workflow.md` §2.1 的「72 个活跃文件」是图谱文件节点口径（含 `entry`/`tests`/`executor`）。两者口径不同、不可互相换算。

> **说明**：本表只列**四层生产模块**之间的边。来自 `main.ahk`（`entry` 层）、`tests/`（`tests` 层）、`_diag.ahk`/`_rt.ahk`（临时脚本）的入边以「外部引用者」形式统计，但不逐个展开，以避免表格被测试文件淹没。

---

## 1. 领域层（`domain/`，depth 1）

### 1.1 `domain/interfaces.ahk`

抽象接口定义——**依赖倒置的锚点**，被依赖次数最多的领域模块。

| 方向 | 内容 |
|------|------|
| **OUT** | *（无——叶子节点）* |
| **IN** | 领域内 6：`joystick_executor`、`key_recorder`、`key_validator`、`mode_registry`、`skill_group`、`skill_manager`<br/>基础设施 1 ⚠️：`joy_sender`（依赖倒置）<br/>表现层 2：`ui_manager`、`webview2_manager`<br/>外部：`main.ahk`、`tests/*`（5 处） |

> **约束**：`infrastructure/joy_sender.ahk` 对本文件的引用是**白名单反向边 #3**，仅用于类型继承（`JoySender` 实现 `IJoySender`），无副作用无状态。

---

### 1.2 `domain/joystick_input.ahk`

摇杆输入解析——**纯工具类，无副作用无状态**。被基础设施层反向引用。

| 方向 | 内容 |
|------|------|
| **OUT** | *（无——叶子节点）* |
| **IN** | 领域内 1：`joystick_executor`<br/>基础设施 2 ⚠️：`config_validator`、`joy_hotkey_manager`<br/>外部：`main.ahk`、`tests/test_joystick.ahk` |

> **约束**：两条来自基础设施的入边是**白名单反向边 #1、#2**，边界为「仅引用 `JoystickInput` 纯工具函数」。因该文件无状态无副作用，反向引用不产生初始化顺序风险。

---

### 1.3 `domain/skill_manager.ahk` 🔴

技能调度核心——**领域层被依赖最多的模块**，跨层影响面最广。

| 方向 | 内容 |
|------|------|
| **OUT** | 4：`interfaces`、`mode_registry`、`skill_group`、`infrastructure/error_system` |
| **IN** | 应用层 2：`config_service`、`group_service`<br/>表现层 2：`debug_panel`、`gui_manager`<br/>外部：`main.ahk`、`tests/*`（5 处） |

> **变更影响面**：改动本文件会影响应用层全部 3 个服务中的 2 个、表现层 2 个面板。改动前请查 `docs/graph-driven-workflow.md` §4.4。

---

### 1.4 `domain/skill_group.ahk`

技能组领域模型。

| 方向 | 内容 |
|------|------|
| **OUT** | 5：`interfaces`、`joystick_executor`、`key_validator`、`mode_registry`、`infrastructure/error_system` |
| **IN** | 领域内 1：`skill_manager`<br/>外部：`main.ahk`、`tests/*`（5 处） |

---

### 1.5 `domain/mode_registry.ahk`

执行模式注册表。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`interfaces`、`joystick_executor`、`infrastructure/error_system` |
| **IN** | 领域内 2：`skill_group`、`skill_manager`<br/>外部：`main.ahk`、`tests/*`（5 处） |

> **变更影响面**：新增执行模式必须同步 `ModeData`（Rust）与 `executor.ahk`（AHK 执行器），见 `docs/graph-driven-workflow.md` §3.4。

---

### 1.6 `domain/key_recorder.ahk`

按键录制。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：`interfaces`、`infrastructure/error_system` |
| **IN** | 表现层 1：`webview2_manager`<br/>外部：`main.ahk`、`tests/*`（2 处） |

---

### 1.7 `domain/key_validator.ahk`

按键校验。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：`interfaces`、`infrastructure/error_system` |
| **IN** | 领域内 1：`skill_group`<br/>表现层 1：`webview2_manager`<br/>外部：`main.ahk`、`tests/*`（2 处） |

---

### 1.8 `domain/joystick_executor.ahk`

摇杆执行。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`interfaces`、`joystick_input`、`infrastructure/error_system` |
| **IN** | 领域内 2：`mode_registry`、`skill_group`<br/>外部：`main.ahk`、`tests/test_joystick.ahk` |

---

### 领域层小结

| 观察 | 说明 |
|------|------|
| 叶子节点 | `interfaces.ahk`、`joystick_input.ahk`（无出边，纯定义/纯工具） |
| 统一出边 | 6 个模块均引用 `infrastructure/error_system.ahk`——这是 `AGENTS.md` 妥协 #1 的**主条款**（方向正确，属 domain → infra 的正向边） |
| 反向入边 | 2 个模块被基础设施层反向引用（白名单 #1/#2） |

---

## 2. 基础设施层（`infrastructure/`，depth 0）

> **注意**：本层除 `joy_sender` / `config_validator` / `joy_hotkey_manager` 外均**不依赖领域层**，是依赖图的「地基」。

### 2.1 `infrastructure/error_system.ahk` 🔴

错误系统——**全项目被依赖次数最多的模块**（27 条入边），是事实上的核心枢纽。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：`json_serializer`、`utils` |
| **IN** | **27 处**，覆盖全部四层：<br/>领域层 6：`joystick_executor`、`key_recorder`、`key_validator`、`mode_registry`、`skill_group`、`skill_manager`<br/>基础设施 2：`error_handler`、`joy_hotkey_manager`、`joy_sender`<br/>应用层 2：`config_service`、`group_service`<br/>表现层 5：`backup_ui`、`debug_panel`、`group_editor`、`gui_manager`、`ui_manager`<br/>外部：`main.ahk`、`_diag.ahk`、`tests/*`（7 处） |

> **⚠️ 最高影响面模块**：修改本文件的**任何公开方法签名**都会波及 27 处引用点。
> **强约束**：领域层对本文件的引用**仅允许** `ErrorSystem.LogError`（`AGENTS.md` 妥协 #1 边界条款）。

---

### 2.2 `infrastructure/utils.ahk`

跨层共享工具入口（`_GetProp` / `_GetField`）。

| 方向 | 内容 |
|------|------|
| **OUT** | *（无——叶子节点）* |
| **IN** | 基础设施 4：`debug_logger`、`error_handler`、`error_system`、`json_logger`<br/>应用层 1：`group_service`<br/>外部：`main.ahk`、`_diag.ahk`、`tests/run_all_tests.ahk` |

> `_GetProp` / `_GetField` 于 v3.1+ 迁入本文件，作为跨层共享的统一入口。

---

### 2.3 `infrastructure/json_serializer.ahk`

JSON 序列化。

| 方向 | 内容 |
|------|------|
| **OUT** | *（无——叶子节点）* |
| **IN** | 基础设施 5：`backup_core`、`config_io`、`error_system`、`ipc_channel`、`json_logger`<br/>应用层 1：`config_service`<br/>外部：`main.ahk`、`_diag.ahk`、`tests/*`（5 处） |

---

### 2.4 `infrastructure/json_parser.ahk`

JSON 解析。

| 方向 | 内容 |
|------|------|
| **OUT** | 1：`json_logger` |
| **IN** | 基础设施 3：`backup_core`、`config_io`、`ipc_channel`<br/>应用层 1：`config_service`<br/>外部：`main.ahk`、`_diag.ahk`、`tests/*`（5 处） |

---

### 2.5 `infrastructure/json_logger.ahk`

JSON 日志。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：`json_serializer`、`utils` |
| **IN** | 基础设施 7：`backup_core`、`config_io`、`config_store`、`config_validator`、`error_handler`、`ipc_channel`、`json_parser`<br/>应用层 1：`config_service`<br/>外部：`main.ahk`、`_diag.ahk`、`tests/*`（5 处） |

---

### 2.6 `infrastructure/config_store.ahk`

配置存储。

| 方向 | 内容 |
|------|------|
| **OUT** | 1：`json_logger` |
| **IN** | 应用层 2：`config_service`、`group_service`<br/>表现层 1：`gui_manager`<br/>外部：`main.ahk`、`tests/*`（4 处） |

> **变更影响面**：本文件与 Rust `ConfigRepository` 共同操作 `config.json`，**字段契约必须一致**，由 `config_compat_tests.rs` 守护。详见主规范 §3.6。

---

### 2.7 `infrastructure/config_validator.ahk` ⚠️

配置校验。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：**⚠️ `domain/joystick_input`（白名单反向边 #1）**、`json_logger` |
| **IN** | 应用层 2：`config_service`、`group_service`<br/>外部：`main.ahk`、`_diag.ahk`、`_rt.ahk`、`tests/*`（2 处） |

> **约束**：对 `domain/joystick_input.ahk` 的引用仅限纯工具函数（无副作用无状态）。

---

### 2.8 `infrastructure/error_handler.ahk`

错误处理器。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`error_system`、`json_logger`、`utils` |
| **IN** | 基础设施 1：`config_io`<br/>应用层 2：`config_service`、`group_service`<br/>表现层 2：`group_editor`、`gui_manager`<br/>外部：`main.ahk`、`tests/run_all_tests.ahk`、`tests/test_webview2_bridge.ahk` |

---

### 2.9 `infrastructure/backup_core.ahk` 🔴

备份核心。

| 方向 | 内容 |
|------|------|
| **OUT** | 4：`config_io`、`json_logger`、`json_parser`、`json_serializer` |
| **IN** | 应用层 3：`backup_service`、`config_service`、`group_service`（**应用层全部**）<br/>外部：`main.ahk`、`tests/*`（2 处） |

> **已知妥协 #2**：`application/config_service.ahk` 通过全局 `BackupCore` 类名**隐式引用**本文件（无显式 `#Include` 依赖声明），仅在内部调用 `BackupCore.CreateBackup()` 静态方法。详见 `AGENTS.md` AHK 妥协表 #2。

---

### 2.10 `infrastructure/config_io.ahk`

配置文件读写。

| 方向 | 内容 |
|------|------|
| **OUT** | 4：`error_handler`、`json_logger`、`json_parser`、`json_serializer` |
| **IN** | 基础设施 1：`backup_core`<br/>外部：`main.ahk`、`tests/run_all_tests.ahk` |

---

### 2.11 `infrastructure/debug_logger.ahk`

调试日志。

| 方向 | 内容 |
|------|------|
| **OUT** | 1：`utils` |
| **IN** | 外部：`main.ahk`、`tests/*`（5 处） |

---

### 2.12 `infrastructure/migration_logger.ahk`

迁移日志。

| 方向 | 内容 |
|------|------|
| **OUT** | *（无——叶子节点）* |
| **IN** | 应用层 1：`config_service`<br/>外部：`main.ahk`、`tests/run_all_tests.ahk` |

---

### 2.13 `infrastructure/ipc_channel.ahk`

IPC 通道（**v3.0 内部通信**）。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`json_logger`、`json_parser`、`json_serializer` |
| **IN** | 仅 `tests/run_all_tests.ahk` |

> **⚠️ v4.0 说明**：本模块属 **v3.0 独立模式**的内部通信通道。v4.0 的跨进程通信由 Rust `IpcManager` + AHK `ahk_executor/ipc_client.ahk` 承担，**不经过本文件**。
> **观察**：本模块除测试外无生产入边，是 v4.0 迁移后的**潜在归档候选**。

---

### 2.14 `infrastructure/joy_hotkey_manager.ahk` ⚠️

摇杆热键管理。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：**⚠️ `domain/joystick_input`（白名单反向边 #2）**、`error_system` |
| **IN** | 外部：`main.ahk`、`tests/test_joy_hotkey_manager.ahk`、`tests/test_joy_hotkey_manager_ahu.ahk` |

> **约束**：对 `domain/joystick_input.ahk` 的引用用于消除重复实现（A1 修复：删除冗余的 `joystick_input_utils.ahk`，该文件曾为规避反向依赖而复刻 `JoystickInput` 全部方法）。仅限纯工具函数。

---

### 2.15 `infrastructure/joy_sender.ahk` ⚠️

摇杆发送器——实现 `IJoySender` 抽象接口（依赖倒置）。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：**⚠️ `domain/interfaces`（白名单反向边 #3）**、`error_system` |
| **IN** | 外部：`main.ahk`、`tests/test_joystick.ahk` |

> **约束**：对 `domain/interfaces.ahk` 的引用**仅用于类型继承**（`JoySender` 实现 `IJoySender`），无副作用无状态。边界为「domain 定义接口 / joy_sender 实现接口」。

---

### 基础设施层小结

| 观察 | 说明 |
|------|------|
| 枢纽模块 | `error_system`（27 入边）——改动需极高谨慎 |
| 叶子节点 | `utils`、`json_serializer`、`migration_logger` |
| 反向边 | 3 条（`config_validator`、`joy_hotkey_manager`、`joy_sender`）——**全部为白名单内** |
| 潜在归档 | `ipc_channel.ahk`（v3.0 遗留，无生产入边） |

---

## 3. 应用层（`application/`，depth 2）

### 3.1 `application/group_service.ahk` 🔴

分组增删改查编排。

| 方向 | 内容 |
|------|------|
| **OUT** | 8：`application/config_service`、`domain/skill_manager`、`infrastructure/backup_core`、`infrastructure/config_store`、`infrastructure/config_validator`、`infrastructure/error_handler`、`infrastructure/error_system`、`infrastructure/utils` |
| **IN** | 表现层 1：`group_editor`<br/>外部：`main.ahk`、`tests/*`（3 处） |

> **应用层内部依赖**：`group_service` → `config_service`（同层调用）。
> **变更影响面**：Rust 侧 `group_service.rs` 的 `build_toggle_command` 与本模块的 `ToggleGroup` 语义必须一致，详见主规范 §3.4.1。

---

### 3.2 `application/config_service.ahk` 🔴

配置读写编排——**应用层中出边最多的模块**。

| 方向 | 内容 |
|------|------|
| **OUT** | 10：`domain/skill_manager`、`infrastructure/backup_core`、`config_store`、`config_validator`、`error_handler`、`error_system`、`json_logger`、`json_parser`、`json_serializer`、`migration_logger` |
| **IN** | 应用层 1：`group_service`<br/>表现层 2：`backup_ui`、`gui_manager`<br/>外部：`main.ahk`、`tests/*`（3 处） |

> **已知妥协 #2**：通过全局 `BackupCore` 类名隐式引用 `infrastructure/backup_core.ahk`（无显式 `#Include`）。

---

### 3.3 `application/backup_service.ahk`

备份/恢复编排。

| 方向 | 内容 |
|------|------|
| **OUT** | 1：`infrastructure/backup_core` |
| **IN** | 表现层 2：`backup_ui`、`gui_manager`<br/>外部：`main.ahk`、`tests/run_all_tests.ahk` |

> **本模块出边最少（1 条）**——职责单一，是应用层中最内聚的模块。

---

### 应用层小结

| 观察 | 说明 |
|------|------|
| 层内依赖 | `group_service` → `config_service`（唯一一条应用层内部边） |
| 共同内层 | 3 个模块均依赖 `infrastructure/backup_core.ahk` |
| 对领域层依赖 | 仅 `config_service` / `group_service` 依赖 `domain/skill_manager`；`backup_service` 不依赖领域层 |
| `main.ahk` 依赖 | 3 个模块**全部**被 `main.ahk` 引用（依赖注入需要） |

---

## 4. 表现层（`presentation/`，depth 3）

### 4.1 `presentation/gui_manager.ahk` 🔴

主 GUI 管理——**表现层中出边最多的模块**。

| 方向 | 内容 |
|------|------|
| **OUT** | 9：`application/backup_service`、`application/config_service`、`domain/skill_manager`、`infrastructure/config_store`、`infrastructure/error_handler`、`infrastructure/error_system`、`presentation/backup_ui`、`presentation/debug_panel`、`presentation/group_editor` |
| **IN** | 外部：`main.ahk`、`tests/run_all_tests.ahk` |

> **表现层内部依赖**：本模块是表现层的**聚合入口**，引用同层 3 个面板（`backup_ui` / `debug_panel` / `group_editor`）。

---

### 4.2 `presentation/webview2_manager.ahk` 🔴

WebView2 宿主 + AHK-JS Bridge。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`domain/interfaces`、`domain/key_recorder`、`domain/key_validator` |
| **IN** | 外部：`main.ahk`、`tests/run_all_tests.ahk`、`tests/test_webview2_bridge.ahk` |

> **⚠️ 红线**：AHK-JS 通信**禁止使用 sync 代理**（`hostObjects.sync.ahk.Method()` 会在消息循环中死锁），必须用 `postMessage`。详见主规范 §3.7。
> **v4.0 说明**：v3.0 的 GUI 通道。v4.0 GUI 是 Tauri 前端，不走本模块。

---

### 4.3 `presentation/ui_manager.ahk`

UI 通用管理。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：`domain/interfaces`、`infrastructure/error_system` |
| **IN** | 外部：`main.ahk`、`tests/*`（3 处） |

> ~~**⚠️ 重名警告**：根目录存在同名的 `ui_manager.ahk`（孤点，无任何依赖关系）。**切勿混淆**——根目录那个是待清理的遗留副本。~~
>
> **✅ 已于 2026-09-16 清理**（TD-003）：根 `ui_manager.ahk` 已删除。它与
> `presentation/ui_manager.ahk` **定义了同名的 `class UIManager`**（根副本 v1.0 / 89 行，
> 真身 v3.0 / 100 行 `extends INotifier`），是迁移遗留，且无任何 `#Include` 指向它。
> 现在 `UIManager` 全局唯一，重名歧义消除。恢复命令：`git checkout HEAD~1 -- ui_manager.ahk`。

---

### 4.4 `presentation/group_editor.ahk`

分组编辑器面板。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`application/group_service`、`infrastructure/error_handler`、`infrastructure/error_system` |
| **IN** | 表现层 1：`gui_manager`<br/>外部：`tests/run_all_tests.ahk`、`tests/test_integration_error_system.ahk` |

---

### 4.5 `presentation/backup_ui.ahk`

备份面板。

| 方向 | 内容 |
|------|------|
| **OUT** | 3：`application/backup_service`、`application/config_service`、`infrastructure/error_system` |
| **IN** | 表现层 1：`gui_manager`<br/>外部：`tests/test_integration_error_system.ahk` |

---

### 4.6 `presentation/debug_panel.ahk`

调试面板。

| 方向 | 内容 |
|------|------|
| **OUT** | 2：`domain/skill_manager`、`infrastructure/error_system` |
| **IN** | 表现层 1：`gui_manager`<br/>外部：`tests/run_all_tests.ahk` |

---

### 表现层小结

| 观察 | 说明 |
|------|------|
| 聚合入口 | `gui_manager.ahk` 引用同层全部 3 个面板 |
| 依赖倒置 | `ui_manager` / `webview2_manager` 依赖 `domain/interfaces`（正向边，符合分层） |
| HTML 资源 | `app_ui.html` / `editor_ui.html` / `editor_ui_v2.html` 为 WebView2 加载资源，**不参与 `#Include` 图** |

---

## 5. AHK 执行器（`src-tauri/ahk_executor/`，depth 5）

**跨进程边界，独立子树**——属 `LAYER_EXEMPT`，不参与四层分层约束。

| 文件 | 职责 | 测试 |
|------|------|------|
| `executor.ahk` | `CommandDispatcher.Dispatch` 命令分发 | `tests/test_ahk_executor/test_executor.ahk` |
| `ipc_client.ahk` | Named pipe 客户端 + `MiniJson` | `tests/test_ahk_executor/test_ipc_client.ahk` |
| `hotkey_hook.ahk` | 热键钩子（**热路径**） | `tests/test_ahk_executor/test_hotkey_hook.ahk` |
| `sender.ahk` | 按键发送 | `tests/test_ahk_executor/test_sender.ahk` |
| `joystick.ahk` | 摇杆输入 | `tests/test_ahk_executor/test_joystick.ahk` |

> **测试关系**：5 个测试文件各自 `#Include` 对应的被测脚本（5 条 `tests → executor` 边）。
> **状态**：执行器**无生产 `#Include` 入边**（由 Rust `spawn_child` 以进程方式启动，非文件引用）。

---

## 6. Rust Crate 邻接表

| Crate | 出边（生产） | 出边（dev） | 入边 |
|-------|-------------|-----------|------|
| `asd-ipc-protocol` | *（无——最底层）* | *（无）* | `asd-domain`、`asd-application`、`src-tauri` |
| `asd-domain` | `asd-ipc-protocol` | *（无）* | `asd-application`、`src-tauri` |
| `asd-application` | `asd-domain`、`asd-ipc-protocol` | `asd-test-harness` | `src-tauri` |
| `asd-test-harness` | ⚠️ `asd-application`、`asd-domain`、`asd-ipc-protocol` | *（无）* | `src-tauri`（dev） |
| `src-tauri` | `asd-application`、`asd-domain`、`asd-ipc-protocol` | `asd-test-harness` | *（无——顶层）* |

> **`asd-test-harness` 的 3 条出边（2026-09-16 更正，TD-009）**：原先被判为「违规」，实为 `ALLOWED_CRATE_DEPS` **漏填空集**所致 —— 属于**夹具的设计意图**（必须同时 mock 三个层的类型）。现已补入允许矩阵，**违规数 3 → 0**。
> ⚠️ 注意 `asd-application` 的 dev-dependencies 里有 `asd-test-harness`，与生产边构成 **dev 依赖环**（cargo 允许；环检测只用生产边）。这条边**必须保持 dev-only**。详见主规范 §2.3。
> **生产依赖无环**：环检测（Tarjan）仅使用生产边，结果为 0 环。

---

## 7. 维护指引

| 何时更新本表 | 操作 |
|-------------|------|
| 增删 AHK 文件 / 修改 `#Include` | 重跑 `python .review-analysis/build_graph.py`，按新数据刷新对应章节 |
| 增删 crate / crate 依赖 | 更新 §6，并同步 `build_graph.py` 的 `ALLOWED_CRATE_DEPS` |
| 新增架构妥协 | 更新对应模块的「约束」注记，并同步 `AGENTS.md` 妥协表 |

```bash
# 刷新本表所需的数据
python .review-analysis/build_graph.py
# 然后读取 .review-analysis/graph-raw.json 的 ahk.edges / rust.crate_edges
```

> **注意**：本表是**自动提取数据的呈现**，不是手工维护的「第二真相」。若与 `build_graph.py` 的输出冲突，**以脚本输出为准**并刷新本表。

---

**相关文档**：`docs/graph-driven-workflow.md`（主规范）· `AGENTS.md`（架构权威）· `docs/graph-sync-checklist.md`（同步清单）
