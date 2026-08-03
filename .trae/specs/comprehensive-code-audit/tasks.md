# Tasks

## Phase 1: 并行审查（8 个独立子代理，可全部并行执行）

- [x] Task 1: AHK v2 架构合规性审查（产出: `docs/review/phase1/task-1-findings.md`，6 个发现：Critical 1 / Important 3 / Minor 2）
  - 审查 `domain/` → `infrastructure/` 依赖（仅允许 error_system.ahk 的 LogError 方法）
  - 审查 4 项已知架构妥协的约束边界是否被遵守：
    1. DDD 层依赖违规（domain/mode_registry.ahk → infrastructure/error_system.ahk）
    2. `_Notify` 签名差异（interfaces.ahk vs webview2_manager.ahk）
    3. `BackupCore` 隐式依赖（config_service.ahk → backup_core.ahk）
    4. 领域层依赖 IPC 协议层（traits.rs → asd-ipc-protocol）
  - 审查模块间 `#Include` 关系是否合理，是否存在循环依赖
  - 审查是否有 I/O 泄漏到领域层
  - 审查工具函数迁移是否完成（_GetProp/_GetField 在 infrastructure/utils.ahk）
  - 产出: 架构合规性发现清单（含位置、描述、严重级别、修复建议）

- [x] Task 2: AHK v2 代码质量与可维护性审查（产出: `docs/review/phase1/task-2-findings.md`，23 个发现：Critical 1 / Important 9 / Minor 13）
  - 审查命名规范（PascalCase 类名/camelCase 静态属性/下划线私有方法/全大写常量）
  - 审查错误处理（OnError 回调、try-catch、JSONLogger.LogError）
  - 审查强制规则在所有 .ahk 文件的遵守：`#ErrorStdOut "UTF-8"` + `#Warn VarUnset, OutputDebug` + `#Warn Unreachable, OutputDebug` + `#Warn LocalSameAsGlobal, Off` + `OnError`
  - 审查箭头函数陷阱（`=>` 块体语法错误）、字符串拼接花括号陷阱
  - 审查重复代码、圈复杂度过高的函数、注释完整度
  - 审查 GUI 控件规范（位置参数双引号、Button.Text、OnEvent 闭包包装）
  - 审查定时器管理规范（_timers Map 存储引用）、周期性触发时间规范（独立触发时间而非 Mod()）
  - 审查热路径日志限速（Execute* 方法每秒最多一次）
  - 产出: 代码质量发现清单

- [x] Task 3: AHK v2 安全性与健壮性审查（产出: `docs/review/phase1/task-3-findings.md`，17 个发现：Critical 2 / Important 9 / Minor 6）
  - 审查输入验证（配置、热键、用户输入）
  - 审查配置校验逻辑（ConfigValidator）
  - 审查 Map/Object 访问安全（Has/HasProp 检查、Map.Delete 前置 Has 检查、数组越界检查）
  - 审查定时器引用管理（_timers Map 正确停止）
  - 审查热路径日志限速是否有效
  - 审查 WebView2 通信安全：
    - postMessage 模式（禁止 ExecuteScriptAsync 等待 Promise）
    - 禁止 AddHostObjectToScript sync 代理
    - WebMessage 双向通信正确性
  - 审查文件 I/O 错误处理（try-catch + JSONLogger）
  - 审查全局变量作用域声明（global 关键字）
  - 产出: 安全性发现清单

- [x] Task 4: AHK v2 测试覆盖与质量审查（产出: `docs/review/phase1/task-4-findings.md`，12 个发现：Critical 3 / Important 5 / Minor 4）
  - 审查测试套件完整性（test_domain/test_infrastructure/test_application/test_presentation/test_webview2_bridge/test_boundary/test_error_system/test_integration_error_system/test_result_reporter/run_all_tests/run_tests）
  - 审查测试隔离性（全局状态污染、测试间依赖）
  - 审查 fixture 管理
  - 审查测试前置检查流程遵守（语法检查 stderr 重定向/接管指令验证/运行时验证）
  - 审查 AHK 执行器测试（57 套件/467 测试：test_executor/test_ipc_client/test_hotkey_hook/test_sender/test_joystick）
  - 审查测试文件标准模板遵守（#ErrorStdOut/#Warn/OnError FileAppend）
  - 识别覆盖率盲区（哪些模块/分支未被测试覆盖）
  - 产出: 测试覆盖发现清单

- [x] Task 5: Rust 纯逻辑 crate 架构+质量审查（产出: `docs/review/phase1/task-5-findings.md`，12 个发现：Critical 0 / Important 5 / Minor 7）
  - 审查 4-crate workspace 依赖关系图正确性
  - 审查纯逻辑 crate 无禁用依赖（tokio/tauri/interprocess/windows；std::fs 仅限 asd-application 的 ConfigRepository）
  - 审查 trait 抽象解耦（IpcSender/EventEmitter/ProcessWatcher 在 asd-domain 定义，src-tauri/bridge.rs 实现）
  - 审查 I/O 泄漏修复（Config 的 I/O 方法在 ConfigRepository，非 domain 层）
  - 审查 Miri 兼容性（无 unsafe 代码）
  - 审查 thiserror 错误类型定义、? 操作符传播
  - 审查命名规范（Crate snake_case/结构体 PascalCase/函数 snake_case/Trait PascalCase）
  - 审查 ConfigValidator（213 tests）覆盖度
  - 审查 IpcCommand 13 variants 与 AHK 执行器同步性
  - 产出: 纯逻辑 crate 发现清单

- [x] Task 6: Rust src-tauri 架构+质量审查（产出: `docs/review/phase1/task-6-findings.md`，8 个发现：Critical 0 / Important 3 / Minor 5）
  - 审查 19 个 Tauri commands 均使用 `#[tauri::command]` 宏标注
  - 审查 bridge.rs trait 实现（IpcBridge/TauriEventBridge/WatchdogBridge）
  - 审查 blocking_lock 使用（已知妥协 #2，死锁风险评估）
  - 审查 IpcManager（interprocess named pipe 通信）
  - 审查 ProcessWatchdog + WatchdogRunner（进程管理、心跳超时）
  - 审查 tracing 日志使用（而非 log）
  - 审查 src-tauri 内部 DDD 分层占位（domain/application 子模块仅 re-export）
  - 审查 IPC 通信通过 IpcSender trait（禁止直接调用 IpcManager）
  - 审查 commands/ 目录 5 个模块（config_cmd/group_cmd/hotkey_cmd/recording_cmd/system_cmd）
  - 产出: src-tauri 发现清单

- [x] Task 7: Rust 安全性与健壮性审查（产出: `docs/review/phase1/task-7-findings.md`，9 个发现：Critical 0 / Important 6 / Minor 3）
  - 审查 unsafe 代码（纯逻辑 crate 应无，src-tauri 检查 windows crate 使用）
  - 审查 unwrap/expect 使用（panic 风险点）
  - 审查 IPC 通信安全（named pipe 名称一致性、错误处理）
  - 审查进程管理（JobObjects、心跳超时与 AHK 端心跳间隔匹配）
  - 审查错误传播链完整性（AppError、IpcError）
  - 审查并发安全（Arc/Mutex/tokio::sync::Mutex、blocking_lock 死锁）
  - 审查配置序列化兼容性（Rust Config 与 AHK config.json 格式兼容）
  - 审查 AHK 子进程隔离（asd_executor.exe 作为子进程）
  - 审查 named pipe 路径一致性
  - 产出: 安全性发现清单

- [x] Task 8: Rust 测试覆盖与质量审查（产出: `docs/review/phase1/task-8-findings.md`，17 个发现：Critical 3 / Important 6 / Minor 8）
  - 审查 506+ 测试分布合理性（asd-domain 125/ipc-protocol 71/application 175/tauri 134）
  - 审查 test-manifest feature 覆盖（主 crate 测试需要 --features test-manifest）
  - 审查测试隔离性、fixture 管理（tests/fixtures/、include_str!、禁止硬编码绝对路径）
  - 审查 E2E 测试完整性（9 suite/53 用例：smoke/config_cmd/group_cmd/hotkey_cmd/recording_cmd/system_cmd/modes/ipc/key_send）
  - 审查 criterion bench（7 个）、cargo-fuzz（3 个 target）
  - 审查 config_compat_tests（Rust Config 与 AHK config.json 兼容性）
  - 审查 ipc_tests、测试固件登记（asd-tauri/docs/test-map.md）
  - 识别覆盖率盲区（纯逻辑 crate 96.57% 之外的 src-tauri 部分）
  - 产出: 测试覆盖发现清单

## Phase 2: 汇总整合（1 个子代理，依赖 Phase 1 全部完成）

- [x] Task 9: 汇总生成统一审查报告（产出: `docs/code-review-report-2026-08-03.md`，去重后 94 个发现：Critical 10 / Important 43 / Minor 41）
  - 收集 Task 1 ~ Task 8 共 8 个子代理的发现清单
  - 按严重程度分级（Critical/Important/Minor），统一分级标准：
    - Critical: 崩溃/数据损坏/安全漏洞/架构严重违规
    - Important: 影响可维护性/潜在风险/违反 AGENTS.md 强制规范
    - Minor: 代码风格/命名/注释等不影响功能
  - 按模块（AHK v2 各层 / Rust 各 crate）分组组织发现
  - 每条发现含：位置（file:line 或 file:line-range）、维度、严重级别、描述、根因、修复建议
  - 生成执行摘要（总体评估、关键风险、关键指标）
  - 生成统计汇总（各级别数量、按维度分布、按模块分布）
  - 输出到: `docs/code-review-report-2026-08-03.md`
  - 产出: 最终审查报告

# Task Dependencies

- [Task 1] ~ [Task 8] 相互独立，无共享状态，可全部并行执行
- [Task 9] 依赖 [Task 1] ~ [Task 8] 全部完成（需要汇总所有发现）
- [Task 10] 依赖 [Task 9] 完成及验证阶段发现的问题（checklist 验证未通过项）

## Phase 3: 修复验证未通过项（依赖验证阶段）

- [x] Task 10: 修复报告 - 为 Important/Minor 发现补充独立"根因"字段（已完成：补充 83 条根因字段，94 条发现现在全部包含根因分析，检查点通过）
  - 验证阶段发现：审查报告中仅 Critical 级别（C1-C10）和个别 Important 发现包含独立"根因"字段
  - 其余 Important（I1-I43 大部分）和全部 Minor（M1-M41）发现的根因信息隐含在"描述"中
  - checklist.md 检查点"每条发现包含根因分析"未通过
  - 修复方案：为报告中所有缺少独立"根因"字段的 Important 和 Minor 发现补充"根因"段落
  - 修复后需重新验证该检查点
  - 产出: 更新后的 `docs/code-review-report-2026-08-03.md`
