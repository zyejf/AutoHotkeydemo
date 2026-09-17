# ASD-Tauri 测试地图

本文件按 crate × 类型 × 文件 × 测试数 × 覆盖范围列出所有测试资源，用于测试资产盘点与新增测试登记。

> **唯一权威来源**：本文档是测试统计的**单一权威来源**。AGENTS.md 为架构/执行模式/依赖的唯一权威；TESTING.md、developer-guide.md、migration-guide.md 仅引用本文档、不自行复制测试数字。

统计口径（截至 2026-09-13，实测）：
- Rust：**`cargo test -p <crate> --all-targets -- --list` 运行时注册数**（唯一权威）
  > ⚠️ **2026-09-13 修正（BUG-3）**：此前以「`#[test]` + `#[tokio::test]` 属性数」为口径，
  > 用正则静态统计。实测证明**任何正则计数都不可靠**，已废弃，改用运行时注册数。
  > 详见文末「统计命令」章节的原因说明。
- AHK 执行器：`Test_` 方法数（`tests/test_ahk_executor/*.ahk` 中以 `Test_` 开头的方法定义数）
- 运行用例：AHK v2 完整套件（`tests/run_all_tests.ahk` 汇总）与 E2E（WebDriverIO 用例数）

> **口径差异提示**：同一文件可能因计数方式不同而得出不同数字，两者均有效、不得互相「纠正」。
> - `watchdog_integration_tests.rs`：`#[test]` 属性数 = **14**（本文档口径）；`fn` 定义数 = **17**（`TESTING.md` 口径）。
> - 套件数：`test_executor.ahk` 的 `Test_` 方法分布在不同 `class ... extends AutoHotUnitSuite` 中，套件数按类计。
> - AHK 完整套件汇总：runner 除 `Test_` 方法外还执行 `Setup`/`Teardown` 生命周期钩子，故实跑总数（**722**）略高于静态 `Test_` 计数（**720**；静态计数不含 `tests/run_tests.ahk` 的 24 个，那是另一个 runner）。

自洽关系：**小计 = 明细之和 = 汇总 = 各 crate 总计相加**。

---

## asd-domain

纯逻辑 crate — 领域模型、配置验证、trait 定义。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-domain | 单元 | crates/asd-domain/src/config.rs | 35 | Config / GroupConfig / ModeData / ControlHotkeys 序列化与默认值 |
| asd-domain | 单元 | crates/asd-domain/src/validator.rs | 62 | ConfigValidator 配置验证规则（按键、间隔、模式、热键）+ BUG-6 可疑值 warning（长度不匹配／超长间隔／超长热键）+ **TD-023 新增 7 条 `mode_data_msg_*` 模式校验文案特征测试**（类型不匹配／空按键与时间／零值／子组／空子组列表／`joystick_hold` 告警而非错误／未知模式只报 `mode` 字段） |
| asd-domain | 单元 | crates/asd-domain/src/models.rs | 3 | SkillGroup 领域模型构造与字段访问 |
| asd-domain | 单元 | crates/asd-domain/src/traits.rs | 11 | IpcSender / EventEmitter / ProcessWatcher 三 trait：**默认方法体必须「明确拒绝」而非 panic**（send_and_wait / send_message / reset）、默认体可被覆写、序列号单调递增、对象安全性与 `Send + Sync` 超trait 约束（编译期钉子） |
| asd-domain | 集成 | crates/asd-domain/tests/integration_tests.rs | 43 | 跨模块配置解析与验证集成 |
| **小计** | — | — | **154** | — |

## asd-ipc-protocol

纯逻辑 crate — IPC 协议（命令、消息、错误、热键合并）。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/command.rs | 4 | IpcCommand 枚举序列化（13 variants） |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/message.rs | 24 | IpcMessage 构造器、序列化、字段访问 |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/error.rs | 5 | IpcError 错误类型与 Display 实现 |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/hotkey_merger.rs | 6 | HotkeyMerger 热键去重与合并 |
| asd-ipc-protocol | 集成 | crates/asd-ipc-protocol/tests/integration_tests.rs | 33 | IPC 协议端到端序列化/反序列化 |
| **小计** | — | — | **72** | — |

## asd-application

应用逻辑 crate — 调度器、状态、配置仓库、服务层。

### 单元测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-application | 单元 | crates/asd-application/src/state.rs | 36 | AppState 状态管理与 trait object 装配 |
| asd-application | 单元 | crates/asd-application/src/config_repository.rs | 28 | ConfigRepository 文件 I/O 与序列化 + **TD-027 新增 2 条**：文件存在但读不出来（非 UTF-8 / 路径是目录）必须报 `IoError` 且消息里**不得**出现「不存在」+ **TD-043 新增 1 条**：目标文件被短暂独占（Windows `share_mode(0)`）时 `atomic_write` 必须靠退避重试成功，而不是直接掉进 copy 回退（后者同样写不进被占用的目标）+ **再 1 条**直接测 `fallback_copy` 本身（这条分支真实环境很难触发，抽成独立函数才能测到，否则整段是未覆盖行拖低覆盖率） |
| asd-application | 单元 | crates/asd-application/src/time_format.rs | 4 | 时间格式化工具 |
| asd-application | 单元 | crates/asd-application/src/error.rs | 6 | AppError 错误类型 |
| **单元小计** | — | — | **74** | — |

### 集成测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-application | 集成 | crates/asd-application/tests/integration_tests.rs | 28 | 跨服务集成（AppState + ConfigRepo） |
| asd-application | 集成 | crates/asd-application/tests/backup_service_tests.rs | 17 | BackupService 备份创建与恢复 |
| asd-application | 集成 | crates/asd-application/tests/group_service_tests.rs | 19 | GroupService 分组增删改查 + **TD-023 新增 3 条 `register_hotkey` IPC 失败回滚特征测试**（注销旧键失败 / 注册新键失败 / 无旧热键时注册失败），用「选择性失败的 IPC 发送器」把此前零覆盖的三条回滚路径逼出来 |
| asd-application | 集成 | crates/asd-application/tests/cross_crate_tests.rs | 13 | 跨 crate 边界（domain → application → ipc-protocol） |
| asd-application | 集成 | crates/asd-application/tests/recording_service_tests.rs | 11 | RecordingService 按键录制 |
| asd-application | 端到端 | crates/asd-application/tests/e2e_dataflow_tests.rs | 4 | 端到端数据流（Command → Bridge → AppState） |
| asd-application | 集成 | crates/asd-application/tests/concurrency_tests.rs | 4 | AppState 并发安全（Arc<Mutex> 验证） |
| asd-application | 集成 | crates/asd-application/tests/backtick_cjk_contract_tests.rs | 3 | **TD-050 新增**：反引号跨中文守护 —— 判据回归测试锁死 A 类（真损坏）与 B 类（刻意保留）形态，B 类不得靠加豁免过关 |
| **集成小计** | — | — | **99** | — |
| **总计** | — | — | **173** | — |

## asd-test-harness

测试工具 crate — Mock 实现与工厂函数（dev-dependency，含少量自测）。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-test-harness | 单元 | crates/asd-test-harness/src/lib.rs | 3 | MockIpcSender / MockEventEmitter / MockProcessWatcher / make_test_state 等工厂函数 |
| **小计** | — | — | **3** | — |

## asd-tauri（src-tauri）

Tauri 主 crate — 表现层 + 基础设施（IPC、Watchdog、Bridge、Commands）。

### 单元测试 + 内联集成测试（`--lib`）

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 单元 | src-tauri/src/infrastructure/ipc.rs | 52 | IpcManager named pipe 通信 |
| asd-tauri | 单元 | src-tauri/src/infrastructure/watchdog.rs | 32 | ProcessWatchdog + WatchdogRunner 进程管理 |
| asd-tauri | 集成 | src-tauri/src/tests/ipc_tests.rs | 26 | IPC 边界条件与错误处理 |
| asd-tauri | 集成 | src-tauri/src/tests/bridge_tests.rs | 12 | IpcBridge / WatchdogBridge trait 实现 + build_hotkey_event_payload 纯函数（原 13 个，2026-09-13 删除必然 panic 的死测试 `test_tauri_event_bridge_emit`，见 BUG-4） |
| asd-tauri | 集成 | src-tauri/src/tests/watchdog_integration_tests.rs | 17 | ProcessWatchdog 跨平台集成（`#![cfg(windows)]` gating，15 个 `#[ignore]` 需 `--ignored` 手动运行；本行为运行时注册数，与 `TESTING.md` 的 `fn` 口径 17 一致；旧口径按 `#[test]` 属性数记为 14，见文首口径差异提示） |
| asd-tauri | 集成 | src-tauri/src/tests/config_compat_tests.rs | 11 | Rust Config 与 AHK config.json 格式兼容性 |
| asd-tauri | 集成 | src-tauri/src/tests/command_contract_tests.rs | 5 | Tauri 命令契约守护（命令名/签名与前端 api.js 调用一致性）+ **TD-045 新增 `tauri_command_args_stay_owned`**：静态扫描，命令参数除 `state` 外不得是借用类型 + **TD-045 批次 8 新增 `no_blanket_missing_errors_doc_allow`**：禁止用文件头 blanket allow 关掉文档契约 lint |
| asd-tauri | 单元 | src-tauri/src/commands/config_cmd.rs | 29 | config_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/system_cmd.rs | 6 | get_system_status / emergency_release / toggle_hold_mode 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/hotkey_cmd.rs | 6 | register_hotkey / unregister_hotkey / list_hotkeys 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/group_cmd.rs | 20 | group_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/recording_cmd.rs | 21 | recording_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/lib.rs | 6 | IPC_PIPE_NAME 常量验证 + try_acquire_shutdown_guard 关机锁纯函数 |
| asd-tauri | 单元 | src-tauri/src/infrastructure/logging.rs | 3 | **TD-054 新增**：`env_filter_from` 契约 —— 默认 `info`、显式 spec 生效、非法 spec 回落到 `info`（`init()` 依赖真实 `tauri::App` 不可测，故抽纯函数） |
| asd-tauri | 集成 | src-tauri/src/tests/doc_markdown_contract_tests.rs | 2 | **TD-045 批次 9 新增**：禁止 blanket allow 关掉 `doc_markdown`（源码层 `#![allow(` + `Cargo.toml` 的 `[lints.clippy]` 层，各带防永真式锚点） |
| **小计** | — | — | **248** | — |

### 集成测试（`tests/` 目录）

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 集成 | src-tauri/tests/test_manifest_feature_removed.rs | 1 | 验证已废弃的 feature 已从 Cargo.toml 移除 |
| **asd-tauri 总计** | — | — | **249** | — |

> 注：`--lib` 明细之和 248 与 `cargo test -p asd-tauri --lib -- --list` 运行时注册数一致；
> benches 使用 criterion（`harness = false`），在 `--all-targets -- --list` 下**不注册**为测试，
> 故 `--all-targets` = 248（lib）+ 1（tests/test_manifest_feature_removed.rs）= **249**，
> 与基准测试的 7 个 criterion 微基准**互不计入**（口径隔离，避免重复计数）。

## 基准测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 基准 | src-tauri/benches/benchmarks.rs | 7 | criterion 微基准（热路径性能回归检测） |

## 模糊测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_config_deserialize.rs | 1 target | Config 反序列化随机输入 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_ipc_command.rs | 1 target | IpcCommand 反序列化随机输入 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_ipc_json.rs | 1 target | IPC JSON 协议随机输入 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_ipc_message_parse.rs | 1 target | IpcMessage 解析后字段访问与方法调用 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_hotkey_merger.rs | 1 target | HotkeyMerger push/flush 逻辑 |

## 覆盖率（纯逻辑 crate，行覆盖率）

> 2026-09-16 起由 `scripts/check-coverage.py`（CI 的 **G3f**）做**棘轮门禁**：
> 基线取实测值，**只阻下降不阻上升**，整体容差 0.5pp、单文件 2.0pp。
> 基线文件 `.review-analysis/coverage-baseline.json`（本表是其可读镜像，
> **数字冲突时以该 JSON 为准**）。

**整体 89.05%**（命中 5336 / 总行 5992，15 个文件）

> ⚠️ **口径：分母含 `#[cfg(test)]` 测试代码，跨文件百分比不可比。**
> cargo-llvm-cov 测的是测试二进制，`src/*.rs` 的内联测试一并进分母。实测测试代码占比
> `time_format.rs` 83.9% / `traits.rs` 77.9% / `validator.rs` 60.9% / `config.rs` 58.0%，
> 而 `group_service.rs`、`recording_service.rs`、`backup_service.rs` 是 0%。
> 所以下表**只能看同一个文件的纵向趋势，不能当横向排名** —— `time_format.rs` 的 100%
> 里有六成在测测试自己，`group_service.rs` 的 63.22% 反倒是纯生产代码。
> 已登记为 **TD-026（豁免不修）**：两条修法实测都堵死（`#[coverage(off)]` 在 rustc 1.95
> 仍是实验特性；`LF` 与逐行 `DA` 有 10/15 文件不一致，无法按行剔除），详见技术债台账。

> ⚠️ **2026-09-16 重取基线：81.64% → 88.65% 不是覆盖率提升，是量程变了。**
> 同一份代码换用 CI 那条 `llvm-cov` 命令后，`validator.rs` 的统计行数从 2367 变成 1856
> （命中数几乎没变，掉的是**未覆盖行**）—— 旧基线的生成命令已无从查证，口径不可复现。
> 已按 CI 命令重取，并在 `check-coverage.py` 增加**口径漂移检测**：基线现在存每个文件的行数，
> 任一文件统计行数变化 >10% 且 ≥20 行即判 FAIL，避免再拿两个不可比的数字互相比。
> **重取基线必须用同一条命令**（见 developer-guide §4.6.1.2）。

| 文件 | 行覆盖率 | 备注 |
|------|---------|------|
| asd-application/src/group_service.rs | 63.22% | 覆盖最低（该文件无内联测试，分母是纯生产代码） |
| asd-application/src/recording_service.rs | 67.28% | |
| asd-application/src/backup_service.rs | 78.31% | |
| asd-domain/src/models.rs | 86.62% | |
| asd-application/src/state.rs | 87.73% | |
| asd-application/src/config_repository.rs | 93.51% | |
| asd-domain/src/validator.rs | 93.75% | 最大文件（1856 行），116 行未覆盖 |
| asd-domain/src/config.rs | 95.74% | |
| asd-domain/src/traits.rs | 95.89% | 2026-09-16 由 **0.00%** 补到 95.89%（TD-007，新增 11 个用例）。0% 的根因是 trait 默认方法体**只为实例化的具体类型生成代码**，此前没有任何类型实现这三个 trait，llvm 根本没生成代码。按行核对**生产代码 15/15 = 100%**；分母里其余 131 行是本次新增的测试代码 |
| asd-ipc-protocol/src/error.rs | 96.08% | |
| asd-ipc-protocol/src/message.rs | 96.88% | |
| asd-ipc-protocol/src/command.rs | 97.70% | |
| asd-ipc-protocol/src/hotkey_merger.rs | 98.73% | |
| asd-application/src/error.rs | 100.00% | |
| asd-application/src/time_format.rs | 100.00% | 分母 83.9% 是测试代码（口径见上） |

覆盖范围：仅 `asd-domain` / `asd-ipc-protocol` / `asd-application` 三个纯逻辑 crate。
`src-tauri` 依赖 windows / tauri 系列 crate，在 Linux 上无法编译，不纳入。

⚠️ 已实测的一个认知偏差：删掉 `asd-ipc-protocol/tests/integration_tests.rs`（463 行）
后覆盖率**纹丝不动** —— 该文件的用例所覆盖的行已被单元测试覆盖，
**它的价值不在覆盖率，在跨模块契约**。别用「删了覆盖率没变」来判定测试冗余。

## AHK 执行器测试

使用项目根目录 `tests/AutoHotUnit.ahk` 框架，测试 `src-tauri/ahk_executor/` 下 5 个 AHK 脚本的纯逻辑方法。

| Crate | 类型 | 文件路径 | 套件数 / Test_ 方法数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| AHK | 单元 | tests/test_ahk_executor/test_executor.ahk | 10 / 46 | executor.ahk CommandDispatcher._GetStr/_GetInt/_GetBool/_GetArr/_GetMap、MergeModeConfig、Dispatch unknown、RecordKey、Validation、ReportFlag |
| AHK | 单元 | tests/test_ahk_executor/test_ipc_client.ahk | 12 / 64 | ipc_client.ahk IPCConst、MiniJson 解析/序列化/往返/布尔标记、IpcClient 初始状态/序列号/断连接收/认证 token/去重 |
| AHK | 单元 | tests/test_ahk_executor/test_hotkey_hook.ahk | 7 / 28 | hotkey_hook.ahk Normalize、RegistrationState、Register/Unregister error、UnregisterAll、Init、Callback |
| AHK | 单元 | tests/test_ahk_executor/test_sender.ahk | 13 / 57 | sender.ahk AllowedKeys、ValidateKey、ToggleGroup、StartPeriodic/Sequence/Enhanced/Hold、HoldModeToggle、EmergencyRelease、Shutdown、Init、ReportKeyEvents、**QPC 精确定刻（时钟分辨率／SleepUntil 误差／保持时长对齐 kpd／端到端 P95 ≤ 20ms／零漏发／非整数间隔 1:3 不拆桶／间隔取整后比例不破）**、**T6 合并遍历等价性（periodic／hybrid 与旧版逐项一致、lastNextDue 等于推进后基准的最小值）**、**T6 开关默认开启且分派确实走合并版（lastNextDue 只有合并版会写，双向阳性对照）** |
| AHK | 单元 | tests/test_ahk_executor/test_joystick.ahk | 19 / 84 | joystick.ahk AllowedKeys、ValidateKey、IsButton/IsPov/IsAxis、GetButtonNum/GetPovDirection/GetAxisInfo、AxisToVJoyId、PovDirectionToValue、ResolveMethod、IsVJoyAvailable、StopGroup、EmergencyRelease、Init、StartPeriodic/Sequence/Hold、**QPC 整数微秒调度（间隔/延时取整、唤醒周期 Ceil 而非 Round、发送钩子拦截 down/up、序列按计划时刻而非当前时刻推进基准、滞后保相位并计 droppedTriggers、周期非追帧路径按计划时刻推进、不允许提前触发、空按键表不除零）** |
| **总计** | — | — | **61 套件 / 279 个 Test_ 方法** | — |

注：AHK 测试文件位于项目根目录的 `tests/test_ahk_executor/`，非 `asd-tauri/tests/`。被测脚本位于 `asd-tauri/src-tauri/ahk_executor/`。

**JSON 转义快路径（`tests/suites/core_suites.ahk` 的 `JSONSerializerEscapeTests`，7 个用例）**：守护 `infrastructure/json_serializer.ahk` 的 `_EscapeString` T1 快路径 —— 快路径三判定（不含引号／不含反斜杠／不含 0x00-0x1F）必须恰好覆盖需转义字符集、反斜杠必须先于引号替换、`\uXXXX` 兜底集合不能漏字符，并做 0..127 逐字符与逐字符版 `_EscapeStringCharByChar` 的等价性扫描。已做 7 项变异阳性对照（替换顺序颠倒／三处快路径判定各漏一项／兜底集合漏 `\x0B` 与 `\x00-\x07`／漏 `\t` 短写法），全部变红。

**JSON 标量类型分派（`tests/suites/core_suites.ahk` 的 `JSONSerializerScalarTypeTests`，10 个用例）**：守护 `JSONSerializer` 的布尔／数字分派（TD-030）。AHK v2 没有布尔类型（`Type(true)` 是 `"Integer"`），序列化器只能靠 `BoolKeys` 键名白名单判定 JSON 布尔 —— 白名单外的 1/0 必须按数字输出（否则 `holdDuration=0` 之类的 u64 字段被写成 `false`，Rust 侧 serde 直接 invalid type）。用例双侧钉住：数字侧（标量 1/0/1.0/-1、`[1,0,2]`、配置契约 `holdDuration`）与布尔侧（`allowOverlap`/`releaseOnEmergency`/`success`/`error`/嵌套 `autoRepeat`）。已做 5 项变异阳性对照（恢复按值判布尔／白名单删一项／白名单清空／布尔分支失效／去掉 `IsObject` 保护），全部变红。

**JSON 缩进分派（`tests/suites/core_suites.ahk` 的 `JSONSerializerIndentTests`，6 个用例）**：钉住 `indent <= 0` 必须输出**单行紧凑** JSON（TD-034）。旧实现无条件换行，`indent=0` 只让缩进变成 0 个空格，于是 `Stringify(x, 0)` 仍是多行 —— 而 `ErrorSystem._ToJsonLine` 与 `JSONLogger._ToJsonLine` 都按「一条记录一行」落盘（函数名就叫 `_ToJsonLine`），`IPCChannel` 也是按行分帧，逐行解析全军覆没。用例覆盖：对象/嵌套容器无换行、拼上换行后按 `` `n `` 切分只剩一行、`JSONParser` 往返、以及**默认 `indent=2` 仍必须是 pretty**（防「修成永远紧凑」）。阳性对照两组：改回无条件换行 → 3 条红；改成永远紧凑 → 1 条红。

**手柄字段校验（`tests/suites/core_suites.ahk` 的 `ConfigValidatorJoystickFieldTests`，5 个用例）**：钉住手柄模式的间隔/延迟字段是 `joyIntervals` / `joyDelays`（TD-035）。运行时（`domain/joystick_executor.ahk`、v4 的 `ahk_executor/joystick.ahk`）读的就是这两个名字，校验器却曾查 `intervals` / `delays`。危害被放大是因为 `ConfigService.SaveConfig()` 遇到 **ERROR 级**校验问题会拒绝保存**整份**配置 —— 一个手柄分组就能让用户连普通分组都存不下。最强的一条用例是「出厂默认配置必须能过自家校验器」（默认分组 7 正是 `joystick_periodic`）。阳性对照两组，分别红 2 条 / 1 条。

**分组 ID 生成（`tests/suites/base_suites.ahk`，1 个用例）**：`CreateGroup` 用 `ConfigStore.HasGroup()` 判重，`_GenerateGroupId()` 原先只看 `SkillManager.Groups` —— 两个真值源不同步时会生成已存在的 ID，随即抛「分组已存在」（TD-036）。用例构造的正是事故现场：SkillManager 已清空而 `ConfigStore.InitDefaults()` 里有默认分组 1..7。

---

## 测试固件

| 文件路径 | 用途 | 引用方 |
|---------|------|-------|
| asd-tauri/tests/fixtures/configs/tests_config.json | 主测试配置样本（Task 1 迁移自 src-tauri/tests_config.json） | src-tauri/src/tests/config_compat_tests.rs |
| asd-tauri/src-tauri/config.json | 主运行时配置样本（`MAIN_CONFIG_JSON`，经 `include_str!("../../config.json")` 引用，用于 Config roundtrip 序列化兼容性验证） | src-tauri/src/tests/config_compat_tests.rs |

---

## 汇总

| 类别 | 统计 |
|------|------|
| Rust 测试（运行时注册数，`--all-targets -- --list`） | 651（asd-domain 154 + asd-ipc-protocol 72 + asd-application 173 + asd-test-harness 3 + asd-tauri 249；其中 `#[ignore]` 15 个）。2026-09-18 +8：本轮新增 `backtick_cjk_contract_tests` 3 条（TD-050）、`doc_markdown_contract_tests` 2 条（TD-045 批次 9）、`infrastructure::logging` 3 条（TD-054）；另含 TD-045 批次 8 的 `no_blanket_missing_errors_doc_allow` 1 条此前未登记 |
| AHK 执行器测试（`Test_` 方法数） | 61 套件 / 279 个 `Test_` 方法（`tests/test_ahk_executor/` 5 文件；不含 `test_joy_hotkey_manager_ahu.ahk` 的 7 套件） |
| AHK v2 完整测试套件（`tests/run_all_tests.ahk` 汇总） | 722 个用例 / 182 个套件。**本机**（`scripts/check-gates.sh`，默认）：通过 722 / 失败 0 / 跳过 0。**CI**（G3b，`ASD_HOST_TIMING=0`）：通过 715 / 失败 0 / **跳过 7** —— 跳过的是 `SenderPreciseTimingTests` 里 7 条绝对墙钟时延断言，原因见下。2026-09-16 三次增长：① +33 用例 / +13 套件，原 `tests/test_joystick.ahk`（独立脚本，断言从未执行）改名并转为 `tests/test_joystick_input.ahk` 接入套件（TD-002）；② +10 用例 / +1 套件，`JSONSerializerScalarTypeTests` 钉住 JSON 标量的布尔/数字分派（TD-030，AHK v2 无布尔类型导致的 1/0 串味）；③ +12 用例 / +2 套件，`JSONSerializerIndentTests`（+6，TD-034：`Stringify(x, 0)` 必须是单行紧凑）与 `ConfigValidatorJoystickFieldTests`（+5，TD-035：手柄模式的间隔/延迟字段是 `joyIntervals`/`joyDelays`），另在 `base_suites.ahk` 的 `ConfigStoreGroupTests` 补 1 条 `_GenerateGroupId` 配置侧碰撞用例（TD-036）。接入 `tests/` 下从未执行的独立脚本时一并修好了一批陈旧断言。2026-09-17 再 +3 用例 / +1 套件：`ConfigValidatorFallbackConfigTests` 钉住「配置读取失败时的降级默认值必须能通过自家校验器」（TD-047，详见下） |
| 基准测试 | 7 个 criterion bench |
| AHK 生产基准（CI 门禁，T11） | 2 个基准脚本 / 8 个 metric：`bench_prod_escape.ahk` 5 个（直接测 `JSONSerializer._EscapeString`，T1，**K=1.5**，warn 1.25）+ `bench_prod_tick.ahk` 3 个（直接测 `Sender._ExecutePeriodic`，T6，**K=1.4**，warn 1.2）；两个 bench 的 p50 **都是归一化值**（÷ 同进程紧邻测得的参考负载），判据「p50 中位数 ≤ 基线 ×K」，两个都进 CI 的 `ahk-bench` job 并阻断合并。K 不同是按信噪比定的（T1 信号 41~49×，T6 仅 ~1.7×），详见 `docs/developer-guide.md` §4.6.4 |
| 模糊测试 | 5 个 fuzz target |
| E2E 测试 | 9 suite / 53 用例 |

自洽校验：各 crate「小计 = 明细之和」，上表 Rust 总数 = asd-domain + asd-ipc-protocol + asd-application + asd-test-harness + asd-tauri = 154 + 72 + 173 + 3 + 249 = 651。

> **备注（T8-07† 处置）**：`docs/review/2026-08-20/task-8-tests.md` 分报告《总结》自报「发现总数 7（Important 3 + Minor 4）」，但正文仅列 T8-01~T8-06 共 6 条（其中 Minor 3 条：T8-04/T8-05/T8-06）。已核实第 4 条 Minor 无正文，属该报告自报计数笔误（正文实际为 Important 3 + Minor 3 = 6 条），无遗漏问题，占位 `T8-07†` 予以关闭。

> **备注（宿主时延类断言：CI 跳过 7 条）**：`SenderPreciseTimingTests` 里有 7 条断言是**绝对墙钟时延上限**（SleepUntil 误差、保持时长对齐 kpd、periodic/sequence/hybrid 端到端 P95 ≤ 20ms、步进不漂移）。定刻走 **QPC 忙等**，CPU 一被争用就不是「变慢一点」而是量级崩塌。本机 12 线程施加 N 个满载进程实测（SleepUntil 误差 p50 / periodic 端到端 p50）：
>
> | 争用 | SleepUntil p50 | periodic 端到端 p50 | SleepUntil p95 |
> |------|----------------|---------------------|----------------|
> | 空载 | 0.005 ms | 15.015 ms | 0.006 ms |
> | 11 进程 | 0.005 ms | 15.015 ms | 0.05 ~ 1.76 ms |
> | 14 进程 | **19.22 ms** | **28.45 ms** | **28.45 ms** |
>
> GitHub 共享 runner（2 vCPU）实测落在这条悬崖带上（run 34971335578：SleepUntil p95=**11.15** ms、periodic p95=**31.86** ms），按插值其中位数也已越线 —— 即 **CI 上中位数同样守不住**，不是放宽 P95 能解决的。更关键的是：本机注入「定刻退化成 AHK 网格 `Sleep`」缺陷后，periodic 端到端 P95 = **31.76** ms，与 CI 那个 31.86 几乎相同 —— **在共享 runner 上，「实现退化」与「宿主忙」在数值上无法区分**。故 CI 用 `ASD_HOST_TIMING=0` 显式跳过这 7 条（跳过数写进汇总且 CI 会校验「必须跳过 ≥1 条」，防止门控静默失效），真正的守护点是争用可控的本机四闸门（默认全跑，注入缺陷实测 4 条变红）。详见 `docs/developer-guide.md`。

---

## E2E 测试

使用 tauri-driver + WebDriverIO 框架，在真实 Windows 桌面环境下测试完整应用链路。

| Suite | 文件路径 | 用例数 | 覆盖范围 |
|-------|---------|-------|---------|
| E2E | asd-tauri/e2e/specs/smoke.spec.js | 1 | 应用启动与关闭冒烟测试 |
| E2E | asd-tauri/e2e/specs/config_cmd.spec.js | 12 | 11 个 config_cmd 命令 |
| E2E | asd-tauri/e2e/specs/group_cmd.spec.js | 8 | 8 个 group_cmd 命令 |
| E2E | asd-tauri/e2e/specs/hotkey_cmd.spec.js | 3 | 2 个 hotkey_cmd 命令 + 热键触发 |
| E2E | asd-tauri/e2e/specs/recording_cmd.spec.js | 5 | 4 个 recording_cmd 命令 + 状态机 |
| E2E | asd-tauri/e2e/specs/system_cmd.spec.js | 5 | 5 个 system_cmd 命令 |
| E2E | asd-tauri/e2e/specs/modes.spec.js | 7 | 7 种执行模式（系统共支持 10 种，`joystick_*` 三种未纳入 E2E） |
| E2E | asd-tauri/e2e/specs/ipc.spec.js | 7 | Rust↔AHK IPC 通信 |
| E2E | asd-tauri/e2e/specs/key_send.spec.js | 5 | AHK 执行器按键验证 |
| **总计** | — | **53** | — |

> **执行模式口径**：系统能力共 10 种执行模式（见 AGENTS.md「支持的执行模式」）；E2E 覆盖 7 种（`modes.spec.js`），`joystick_periodic` / `joystick_sequence` / `joystick_hold` 三种未纳入 E2E。两口径分别标注，不混用。

### E2E 测试固件

| 文件路径 | 用途 |
|---------|------|
| asd-tauri/e2e/fixtures/test_config.json | 测试专用配置（7 模式分组） |
| asd-tauri/e2e/fixtures/key_receiver.ahk | AHK 按键接收窗口（捕获按键事件） |
| asd-tauri/e2e/helpers/tauri.js | Tauri 交互辅助（invoke/getConfig/saveConfig） |
| asd-tauri/e2e/helpers/config.js | 配置管理辅助（备份/恢复/加载测试配置） |
| asd-tauri/e2e/helpers/key_receiver.js | 按键接收器辅助（启停/读取/断言） |
| asd-tauri/e2e/helpers/report.js | 测试报告辅助（结果收集/Markdown 生成） |
| asd-tauri/e2e/helpers/ahk_path.js | AHK v2 可执行文件路径集中管理（`AHK_PATH` 环境变量覆盖默认路径，消除硬编码） |
| asd-tauri/e2e/helpers/error_utils.js | 错误消息提取（`extractErrorMessage`，兼容 AppError 结构化对象/Error 实例/字符串） |
| asd-tauri/e2e/helpers/spec-hooks.js | 共享 spec 生命周期钩子工厂（before/beforeEach/afterEach/after + `extractCaseId` + `DEFAULT_FAILURE_SEVERITY`） |
| asd-tauri/e2e/helpers/__tests__/ahk_path.test.js | ahk_path.js 单元测试（node:test） |
| asd-tauri/e2e/helpers/__tests__/error_utils.test.js | error_utils.js 单元测试（node:test） |
| asd-tauri/src/__tests__/api_contract.test.js | **前端 api.js ↔ Rust 命令的契约测试**（TD-005）：静态双向核对 —— JS 调用的命令集 == Rust 的 `#[tauri::command]` 命令集、JS 传的每个参数名能对上 Rust 的 snake_case 参数、Rust 的必填参数都被前端传了。7 个用例（含一条「解析器不许静默失效」的锚点）。首次运行即抓到 `export_recording` 漏传 `delays` |

### 运行方式

```bash
# 前置条件
cargo install tauri-driver --locked
cd asd-tauri && cargo build --release
cd asd-tauri/e2e && npm install

# 运行
cd asd-tauri/e2e && npm test
```

### E2E 测试文档

| 文档 | 路径 | 用途 |
|------|------|------|
| E2E 测试报告 | docs/e2e-test-report.md | 53 个用例的状态总览（PENDING/PASS/FAIL） |
| E2E 已知问题 | docs/e2e-known-issues.md | 10 个已知问题与修复建议 |

---

## 维护规范

1. **新增测试文件**：在本地图的对应 crate 小节追加一行，记录文件路径、测试数、覆盖范围。
2. **新增测试固件**：在「测试固件」章节登记路径、用途、引用方。
3. **测试数变更**：每次合并 PR 后更新本地图的测试数列，保持与**运行时注册数**一致，并同步校验「小计 = 明细之和 = 汇总」。
4. **统计命令**：
   ```bash
   # ✅ 权威：各 crate 运行时注册数（推荐，唯一可信）
   for c in asd-domain asd-ipc-protocol asd-application asd-test-harness asd-tauri; do
     n=$(cargo test -p $c --all-targets -- --list 2>/dev/null | grep -c ": test$")
     echo "$c = $n"
   done

   # 单个文件明细（如 bridge_tests）
   cargo test -p asd-tauri --all-targets -- --list 2>/dev/null | grep "bridge_tests" | wc -l
   ```
   ```powershell
   # PowerShell 等价写法
   foreach ($c in @('asd-domain','asd-ipc-protocol','asd-application','asd-test-harness','asd-tauri')) {
     $n = (cargo test -p $c --all-targets -- --list 2>$null | Select-String ": test$").Count
     "$c = $n"
   }
   # 全量运行（查看 test result）
   cargo test --workspace 2>&1 | Select-String "test result"
   # AHK 执行器 Test_ 方法数
   (Get-ChildItem .\tests\test_ahk_executor\*.ahk | ForEach-Object { (Select-String -Path $_.FullName -Pattern '^\s*Test_[A-Za-z0-9_]+').Count } )
   ```

> #### ⚠️ 为什么废弃正则计数（2026-09-13 BUG-3 根因记录）
>
> 曾用正则 `#\[test\]|#\[tokio::test` 或 `^\s*#\[(tokio::)?test\]` 静态统计属性数。实测证明
> **两者都不可靠**，且失败方向相反：
>
> | 正则 | `src-tauri/src` 计数 | 问题 |
> |------|:---:|------|
> | `^\s*#\[(tokio::)?test\]`（`MEMORY.md` 曾用） | **231** | 带 `\]` 与 `^` 锚点 → **漏计**带参属性 `#[tokio::test(flavor = "multi_thread")]` |
> | `#\[test\]\|#\[tokio::test`（本文件曾用） | **243** | 无 `\]` 故能匹配带参属性，但在 `asd-test-harness` 上**多计 1**（4 vs 实际 3） |
>
> `bridge_tests.rs` 最能说明问题：严格正则得 **4**（即旧登记值），宽松正则得 **13**，
> 运行时实际 **13** —— 差的 9 个全是 `#[tokio::test(flavor = "multi_thread")]`。
>
> **根因**：正则无法感知 `#[cfg]` 条件编译、宏展开、doc-test 等，
> 属**方法论缺陷**，不是「换个正则就能修好」。
> 因此改为以 **`cargo test -- --list` 运行时注册数**为唯一权威。
