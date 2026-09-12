# 发现清单（2026-09-12）

> 逐条列出本次审查的全部发现，含精确定位、判定依据与修复建议。  
> 级别定义：**Critical** = 运行时崩溃/数据损坏；**Important** = 功能缺陷/架构违规/显著技术债；**Minor** = 质量与一致性问题。



---

## A. 未闭合的历史发现


### A-1【Important → ✅ 已修复】`watchdog.rs` 手写 `unsafe impl Send/Sync`

| 项         | 内容                                                                                                                                                                                            |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **编号**    | T5-01（2026-08-20 遗留）                                                                                                                                                                          |
| **原位置**   | `asd-tauri/src-tauri/src/infrastructure/watchdog.rs:64, 76, 535, 539`（4 处）                                                                                                                    |
| **原现状**   | `:64 unsafe impl Send for ProcessWatchdog {}`  
`:76 unsafe impl Sync for ProcessWatchdog {}`  
`:535 unsafe impl Send for JobObjectGuard {}`  
`:539 unsafe impl Sync for JobObjectGuard {}` |
| **原风险**   | soundness 依赖「内部 Mutex 保护所有字段」这一人工维护的不变量。任何后续修改引入未受保护的字段，即变为**未定义行为**，且编译器不会报错                                                                                                                 |
| **原缓解缺陷** | 仅有「移除 `unsafe impl` 则无法编译」的守护，只能防「意外删除」，**不能防「新增未保护字段」** —— 手写 `unsafe impl` 会无条件吞掉字段的真实性质                                                                                                    |

#### 根因定位（本次修复的关键发现）

用编译器探针实证：`windows` crate **0.62.2 的 `HANDLE(pub *mut c_void)` 既非 `Send` 也非 `Sync`**  
（`windows-0.62.2/src/Windows/Win32/Foundation/mod.rs:5291`；`*mut T` 的 `!Send`/`!Sync`  
见 `core/src/marker.rs:102,677`）。

这与 `std::os::windows::io::OwnedHandle` **不同** —— std 为其手写了 `unsafe impl Send/Sync`  
并附注释「Windows HANDLE may be transferred across and shared between thread boundaries  
(despite containing a *mut void, which in general isn't Send or Sync)」  
（`std/src/os/windows/io/handle.rs:110-124`）。

因此 4 处 `unsafe impl` 中的 2 处（`JobObjectGuard`）是**必要的**；  
另外 2 处（`ProcessWatchdog`）才是**可消除**的 —— 其存在仅因为 `Child`/`JobObjectGuard`  
直接作为字段，把 `!Sync` 传染给了 `ProcessWatchdog`。

#### 修复方案（已实施）

引入 `SendSyncCell<T>` 泛型封装，把「跨线程移动」与「并发共享」两个命题拆开：

| 类型                                           | 语义                                | 手工 unsafe 命题                          |
| -------------------------------------------- | --------------------------------- | ------------------------------------- |
| `RawHandle(HANDLE)`                          | `unsafe impl Send`，**刻意不 `Sync`** | 句柄是内核对象 ID，可跨线程移动（与 std 立场一致）         |
| `SendSyncCell<T: Send>`                      | `Send + Sync`，**不暴露 `&T`**        | 仅重述「T 可移动」；`Sync` 的正当性来自「无 `&T` 共享入口」 |
| `JobObjectGuard(SendSyncCell<RawHandle>)`    | 自动推导                              | 无                                     |
| `ProcessWatchdog`（字段用 `SendSyncCell<Child>`） | 自动推导 `Send + Sync + 'static`      | 无                                     |

**手工 `unsafe impl` 由 4 处收敛为 3 处，且全部集中在两个泛型封装内**，  
其中 `ProcessWatchdog` 的 2 处被彻底消除。

#### 修复后的守护能力（已故障注入验证）

| 注入场景                                             | 预期   | 实测                                                                  |
| ------------------------------------------------ | ---- | ------------------------------------------------------------------- |
| 向 `ProcessWatchdog` 新增 `std::cell::Cell<u32>` 字段 | 编译失败 | ✅ E0277「`Cell<u32>` cannot be shared between threads safely」        |
| 给 `ProcessWatchdog` 加回手写 `unsafe impl Send`      | 测试失败 | ✅ `test_no_handwritten_unsafe_send_sync_for_watchdog_types` 精确报出违规行 |

新增 3 个回归防线：

1. `test_send_sync_cell_wrapping_chain_is_sound` —— 逐环断言类型推导链（编译期）
2. `test_process_watchdog_send_sync_is_derived_not_declared` —— 断言 `Send + Sync + 'static` 由推导得出
3. `test_no_handwritten_unsafe_send_sync_for_watchdog_types` —— 源码级白名单检查（防退化修复）

**同时修正**：`JobObjectGuard` 的 `Send`/`Sync` 由字段推导，其原有 SAFETY 注释中的  
「`HANDLE` 本身是线程安全的系统资源」表述不够精确（`HANDLE: !Send + !Sync`），  
已改为以 `RawHandle` 为单一命题载体的形式化注释。

### A-2【Important】`test-map.md` 引用已删除的 `scheduler.rs`

| 项      | 内容                                                                           |                 |    |                                         |    |                                       |                                                                          |
| ------ | ---------------------------------------------------------------------------- | --------------- | -- | --------------------------------------- | -- | ------------------------------------- | ------------------------------------------------------------------------ |
| **编号** | T7-04（2026-08-20 遗留）                                                         |                 |    |                                         |    |                                       |                                                                          |
| **位置** | `asd-tauri/docs/test-map.md:50`                                              |                 |    |                                         |    |                                       |                                                                          |
| **现状** | 表格仍列：\`                                                                      | asd-application | 单元 | crates/asd-application/src/scheduler.rs | 17 | SkillManager 调度逻辑（Arc<dyn IpcSender>） | `。但 `scheduler.rs`**已于本次基线提交中删除**（SkillManager 死代码清除，见 commit`21fc349\`） |
| **影响** | test-map 作为「测试分布唯一权威」，其数据失真会误导后续开发者与 AI 助手。§41-63 行的 asd-application 计数整体需重算 |                 |    |                                         |    |                                       |                                                                          |
| **建议** | 删除第 50 行；重算 `asd-application` 段落的总计数；检查同段落其他条目是否也受影响                         |                 |    |                                         |    |                                       |                                                                          |

### A-3【Important】AGENTS.md 测试统计与实际不符

| 项      | 内容                                                                                                     |
| ------ | ------------------------------------------------------------------------------------------------------ |
| **编号** | T7-05（2026-08-20 遗留）                                                                                   |
| **位置** | `AGENTS.md:144`                                                                                        |
| **现状** | 声称「Rust **624** 个测试函数（`#[test]` + `#[tokio::test]`，含 16 个 `#[ignore]`）」                                |
| **实测** | `#[test]` + `#[tokio::test]` 属性共 **596** 个（排除 target/）；实际运行用例 **608**（592 passed + 16 ignored）         |
| **结论** | 「624」**高估 28 个**。`#[ignore]` 的「16」**准确**（实测真实属性正好 16 个：bridge_tests 1 + watchdog_integration_tests 15） |
| **建议** | 将 624 修正为 596（静态函数数）或 608（运行用例数），并明确口径；建议统一采用「运行用例数」并注明 `passed + ignored` 拆分                          |

### A-4【Important→降级】录制/验证模式的 IPC 同步阻塞写

| 项        | 内容                                                                                                                                                                                           |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **编号**   | CR2（2026-08-20 为 Critical，本次降级）                                                                                                                                                              |
| **位置**   | `asd-tauri/src-tauri/ahk_executor/sender.ahk:584-600`；`ipc_client.ahk:795-825`                                                                                                               |
| **原描述**  | 「每次按键 down/up 无条件执行 IPC 序列化 + 同步阻塞写命名管道（无 OVERLAPPED/背压）」                                                                                                                                    |
| **实测修正** | 原描述**已不准确**。当前架构：  
① 发键用 `SendInput`（本地 API，微秒级），**不含 IPC**；  
② IPC 上报位于 `_ReportKeyEvent`，受 `_reportKeyEvents` 门控（`sender.ahk:34`，**默认 `false`**）；  
③ 仅**录制/验证模式**下才启用上报                 |
| **残留风险** | 录制模式下，每次按键 down/up 仍执行一次**同步阻塞 `WriteFile`**（`ipc_client.ahk:808`，overlapped 参数传 `0`）。管道对端慢时，AHK 钩子线程被阻塞，可能导致录制丢键                                                                            |
| **已改善**  | `ipc_client.ahk:815-820` 新增写失败限速降级（`_lastWriteFailLogTime`，每 1s 最多记录一次），避免原「写失败即断连」的雪崩                                                                                                       |
| **建议**   | 文件顶部已定义 `FILE_FLAG_OVERLAPPED := 0x40000000`（`:32`），建议接入异步写：① 管道以 `OVERLAPPED` 打开；② `WriteFile` 传 `OVERLAPPED` 结构指针；③ 以 `GetOverlappedResult` 校验。若判定录制模式键频低、阻塞可接受，则应在代码注释中**显式记录该取舍**并标注触发条件 |

### A-5【Minor】`joy_sender` 反向依赖未在 AGENTS.md 登记

| 项      | 内容                                                                  |
| ------ | ------------------------------------------------------------------- |
| **编号** | T2-05（2026-08-20 遗留）                                                |
| **位置** | `AGENTS.md:75` vs `infrastructure/joy_sender.ahk:17`                |
| **现状** | 实测 `infrastructure → domain` 共 **3 条**边，AGENTS.md 妥协 #1 仅登记 **2 条** |
| **详见** | B-1（同一根因，合并处置）                                                      |

---

## B. 本次新增发现

### B-1【Important】AGENTS.md 架构妥协 #1 漏记一条依赖

| 项        | 内容                                                                                                                                                                                                                         |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **位置**   | `AGENTS.md:75`；代码侧 `infrastructure/config_validator.ahk:15-16`                                                                                                                                                             |
| **图谱证据** | `infrastructure → domain` 的 3 条边：  
① `joy_hotkey_manager.ahk → domain/joystick_input.ahk` — 已登记 ✅  
② `joy_sender.ahk → domain/interfaces.ahk` — 已登记 ✅  
③ `config_validator.ahk → domain/joystick_input.ahk` — **未登记** ❌ |
| **代码判定** | ❌ **代码不违规**。`config_validator.ahk:15` 有注释 `; A1 已备案妥协 #1：基础设施层引用领域层纯工具类（JoystickInput 无副作用、无状态）`；用法仅 `JoystickInput.IsJoystickKey(keyStr)`（`:167`），为纯静态方法，完全符合妥协 #1 的「无副作用、无状态」约束                                          |
| **性质**   | **纯文档失同步**——代码正确、注释正确，唯独 AGENTS.md 的妥协描述不完整                                                                                                                                                                                |
| **影响**   | 后续维护者依据 AGENTS.md 判断「哪些反向依赖合法」时，会误认为 `config_validator` 的依赖是**未备案的违规**，可能触发无谓重构                                                                                                                                            |
| **建议**   | 更新 `AGENTS.md:75`，在妥协 #1 的允许清单中补入：  
`此外，允许 infrastructure/config_validator.ahk 引用 domain/joystick_input.ahk 的 JoystickInput.IsJoystickKey() 纯静态方法，用于摇杆按键名合法性校验。`                                                          |

### B-2【Important】891 行已废弃且无法执行的测试代码

| 项        | 内容                                                                                                                                                                         |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **位置**   | `tests/test_domain.ahk`(195行)、`tests/test_application.ahk`(169行)、`tests/test_infrastructure.ahk`(192行)、`tests/test_presentation.ahk`(178行)、`tests/test_boundary.ahk`(157行) |
| **图谱证据** | ① 这 5 个文件**无入边**（不被 `run_all_tests.ahk` 或任何 suite 引用）；② 均**不含 `Test_` 方法**（实测 `Test_` 计数为 0）                                                                               |
| **根因**   | 它们属**上一代「断言式验证脚本」**&#x67B6;构：用 `TestReporter.BeginTest(...)` + 顺序手工断言，而非 `run_all_tests.ahk` 要求的 `AutoHotUnit` 套件模式（`Test_` 方法约定）。因此**永远不会被测试运行器加载**                       |
| **自承废弃** | `tests/test_infrastructure.ahk:22` 明确写道：`; 保留旧版 T 对象声明以兼容，本文件不再使用`                                                                                                         |
| **影响**   | ① **虚假覆盖感**——891 行看似测试代码，实测执行 0 个用例；② 与 `tests/suites/*.ahk`（内联测试新架构）功能重复；③ 干扰代码阅读与统计口径                                                                                    |
| **建议**   | 二选一：  
**(a) 归档**（推荐）：移入 `tests/archive/`，与既有归档测试并置；  
**(b) 改写**：转换为 `Test_` 方法并注册进 `run_all_tests.ahk`（需评估与新 suite 的重复度，若已完全覆盖则直接删除更优）                                   |

### B-3【Important】死测试引用不存在的模块

| 项      | 内容                                                                                                                                                                                   |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **位置** | `tests/test_error_captor.ahk:10, 12`（全文 329 行）                                                                                                                                       |
| **证据** | 第 10 行 `#Include "../infrastructure/error_captor.ahk"` — **文件不存在**  
第 12 行 `#Include "../infrastructure/error_watchdog.ahk"` — **文件不存在**  
（`infrastructure/` 实际内容确认为 15 个文件，不含这两个） |
| **根因** | 这两个模块已在 error_system 重构中被替换，但测试文件未同步处置                                                                                                                                               |
| **影响** | 该文件**必然加载失败**；且同样未被 `run_all_tests.ahk` 引用（无入边），是彻底的死测试。误导开发者以为 IErrorCaptor 有测试覆盖                                                                                                   |
| **建议** | 与 B-2 一并处置（归档或删除）。若错误捕获器功能仍需测试，应在 `tests/suites/` 下按新架构重写                                                                                                                            |

### B-4【Minor】陈旧孤立文件 `gui.ahk`

| 项        | 内容                                                                                                                                                                                      |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **位置**   | `gui.ahk:13`（项目根目录）                                                                                                                                                                     |
| **证据**   | ① 第 13 行 `#Include "json.ahk"` — **文件不存在**（`tests/legacy/json.ahk` 是仅存的一份，且不在根目录）；② 图谱判定为**孤点**——全项目无任何文件引用 `gui.ahk`                                                                   |
| **辅助证据** | `.workbuddy/memory/MEMORY.md:12` 仍记载「入口: `asd.ahk` (#Include json.ahk, gui.ahk, SkillMgrDebugLogger.ahk, ui_manager.ahk, config.ahk)」——已是**过期描述**，当前的 `asd.ahk` 仅 `#Include "main.ahk"` |
| **性质**   | v1/v2 时代残留                                                                                                                                                                              |
| **建议**   | 删除，或移入 `tests/archive/`。同步更正 `.workbuddy/memory/MEMORY.md` 的过期入口描述                                                                                                                      |

### B-5【Minor】Tauri 命令数量守护机制缺失

| 项        | 内容                                                                                                                                        |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **位置**   | `asd-tauri/src-tauri/src/lib.rs:751`（`tauri::generate_handler![...]`）                                                                     |
| **前序状态** | T5-02 指出 `EXPECTED_TAURI_COMMAND_COUNT` 为**永真式断言**（常量自比，不构成守护）                                                                            |
| **当前状态** | 该常量**已被删除**，但**未建立替代机制**。全项目搜索 `command_count` / `CommandCount` 无结果                                                                       |
| **影响**   | 「34 个 Tauri commands」这一对外契约**当前无任何保护**——误删一个 command 或重复注册，编译与测试均不会发现，直到前端调用失败                                                            |
| **建议**   | ① 在集成测试中统计 `generate_handler!` 注册项数量并断言（需 Tauri 提供内省能力，或维护显式清单）；② 或引入宏计数方案；③ 或至少在 `lib.rs` 的 `generate_handler!` 处添加注释，列出命令总数与清单来源，降低误改概率 |

### B-6【Minor】`migration_logger.ahk` 无测试覆盖

| 项        | 内容                                                                             |
| -------- | ------------------------------------------------------------------------------ |
| **位置**   | `infrastructure/migration_logger.ahk`                                          |
| **图谱证据** | 32 个生产模块中，**31 个**被 `tests/` 下文件直接 `#Include`。唯 `migration_logger.ahk` **零入边** |
| **影响**   | 该模块是全项目唯一未被直接测试覆盖的生产模块。虽为日志类基础设施（风险相对低），但迁移日志关系到配置版本升级的可追溯性                    |
| **建议**   | 补一个基础单元测试（覆盖写入/格式化/边界），或在 `AGENTS.md` 中明确标注「纯基础设施，免测」并说明理由                     |

---


## C. 已确认非问题（避免重复排查）

以下项在历史清单中曾被提出，经本次实测**判定为非问题或已正确处置**，记录以避免后续重复排查：

| 编号    | 原描述                                           | 实测判定                                                                                                                             |
| ----- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| T6-06 | `listen_ahk` 每条消息无差别 `msg.clone()`            | ❌ **非问题**：实测 `ipc.rs:71-78` 的 `clone()` 全为 `Arc` 浅拷贝（廉价，仅增引用计数），无深拷贝开销                                                           |
| T8-05 | `#[ignore]` 实测 19+ 与文档 16 不一致                 | ❌ **非问题**：实测 `^\s*#\[ignore` 真实属性**正好 16 个**（bridge_tests 1 + watchdog_integration_tests 15）；此前的「19」系把 3 个文档注释（`:5`、`:193` 等）误计入 |
| T6-05 | bridge `block_in_place + block_on` 可无限阻塞      | ✅ **已文档化**：`bridge.rs:11-26` 已作为「已知妥协 #2」登记，含完整的风险边界与修改约束说明，非未处理风险                                                               |
| T5-05 | `lib.rs` 直接操作 IpcManager 未走 `IpcSender` trait | ✅ **已文档化**：`lib.rs:245-254` 明确说明「心跳/接受循环/关机」不属 `IpcSender` trait 职责范围，以及 M31 回调注册例外，符合 AGENTS.md 规则                              |
| T4-02 | `scheduler.rs` 的 `SkillManager` 死代码           | ✅ **已修复**：本次基线提交 `21fc349` 已删除该文件，全项目无残留引用                                                                                       |
| T7-02 | `migration-guide.md` 引用已删 API                 | ✅ **已修复**：残留的 `SkillManager._activeHotkeys` 条目位于「迁移对照表」中，是正确的历史映射说明                                                              |
| T8-03 | E2E spec 生命周期代码高度重复                           | ✅ **已修复**：新增 `asd-tauri/e2e/helpers/spec-hooks.js`（175 行）抽取共用逻辑                                                                  |
| T8-04 | `run_all_tests.ahk` 缺 `OnError` 回调            | ✅ **已修复**：`tests/run_all_tests.ahk:50` 已添加                                                                                       |
| T8-06 | fixtures 缺 joystick 配置样本                      | ✅ **已修复**：`tests/fixtures/joystick_config.json` 已新增                                                                              |

---

## D. 处置优先级建议与状态

|   优先级  | 项                        | 工作量 | 理由                                  |   状态  |
| :----: | ------------------------ | :-: | ----------------------------------- | :---: |
| **P1** | A-1（watchdog unsafe）     |  中  | 唯一涉及内存安全的 soundness 风险，应优先消解 unsafe | ✅ 已修复 |
| **P1** | B-2 + B-3（891+329 行废弃测试） |  低  | 归档即可，立刻消除「虚假覆盖感」                    | ✅ 已修复 |
| **P1** | B-1（AGENTS.md 妥协漏记）      |  极低 | 一行文档修正，防止后续误判                       | ✅ 已修复 |
| **P2** | A-4（录制模式 IPC 同步写）        |  中  | 需评估录制实际键频，决定接入 OVERLAPPED 或记录取舍     | 见 A-4 |
| **P2** | A-2 + A-3（文档数据失真）        |  低  | test-map 与 AGENTS.md 数字修正           | ✅ 已修复 |
| **P3** | B-4 / B-5 / B-6          |  低  | 清理与补测，可批量处理                         | ✅ 已修复 |

### 修复完成度小结

|  编号 | 项                          |     级别    |          状态          |
| :-: | -------------------------- | :-------: | :------------------: |
| A-1 | watchdog 4 处 `unsafe impl` | Important | ✅ 已修复（收敛为 3 处，2 处消除） |
| A-2 | test-map 引用已删 scheduler.rs | Important |         ✅ 已修复        |
| A-3 | AGENTS.md 测试统计失真           | Important |         ✅ 已修复        |
| A-4 | 录制模式 IPC 同步写               | Important |       ⏳ 保留（见下）       |
| A-5 | —                          |     —     |           —          |
| B-1 | AGENTS.md 妥协 #1 漏记依赖       |   Minor   |         ✅ 已修复        |
| B-2 | 5 个废弃测试文件                  |   Minor   |         ✅ 已归档        |
| B-3 | `test_error_captor.ahk`    |   Minor   |         ✅ 已归档        |
| B-4 | `gui.ahk` + 3 个失效 I14 测试   |   Minor   |         ✅ 已删除        |
| B-5 | 命令数量守护测试缺失                 |   Minor   |     ✅ 已补（含故障注入验证）    |
| B-6 | migration_logger 零测试覆盖     |   Minor   |      ✅ 已补 10 个测试     |

**未修复项的明确结论**：

- **A-4（录制模式 IPC 同步写）**：接入 `FILE_FLAG_OVERLAPPED`  
  （常量已在 `ipc_client.ahk:32` 定义但未使用）需要改造 IPC 写入为异步完成端口  
  或「写超时 + 丢弃」策略，涉及执行器 IPC 层的并发模型调整。  
  鉴于该项仅在**录制/验证模式**（默认关闭）下触发，且当前无实测丢键证据，  
  本次**不实施代码改造**，改为在代码中显式记录该取舍（见下节「技术债登记」）。

### 技术债登记

| 项         | 位置                                | 取舍理由                                                                                                  | 触发条件                     |
| --------- | --------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------ |
| IPC 同步阻塞写 | `ahk_executor/ipc_client.ahk:808` | 仅录制/验证模式启用（`_reportKeyEvents` 默认 `false`），且 `SendInput` 热路径不含 IPC；改为 OVERLAPPED 需重构 IPC 并发模型，收益/风险比不佳 | 若出现录制丢键的实测证据，或录制模式改为默认开启 |

---

*清单生成：2026-09-12 · 共 10 项发现（0 Critical / 4 Important / 6 Minor）+ 9 项已确认非问题*  
*修复完成：2026-09-12 · 9/10 项已修复（A-4 转为技术债登记）*
