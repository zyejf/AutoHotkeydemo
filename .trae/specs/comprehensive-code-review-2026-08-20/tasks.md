# Tasks

## Phase 1：基线核对（前置，1 个子代理）

- [x] Task 1：基线核对与变更盘点（产出：`docs/review/2026-08-20/phase1-baseline.md`）
  - 用 `git log` / `git diff 2026-08-03..HEAD --stat` 盘点 08-03 之后的所有变更文件
  - 对照 `docs/superpowers/plans/2026-08-04-important-review-findings.md` 与 08-03 报告，逐项核对 10 Critical + 43 Important 修复是否落地
  - 列出新增 / 修改 / 删除文件清单，标注哪些模块是本次审查的新增重点
  - 产出：变更文件清单 + 历史修复核对表（已修复 / 部分修复 / 未修复 / 引入回归）

## Phase 2：并行审查（矩阵，每次最多 4 个子代理）

- [x] Task 2：AHK v2 架构设计与可维护性审查（产出：`docs/review/2026-08-20/task-2-ahk-arch.md`）
  - 审查 DDD 四层依赖（domain → infrastructure 仅允许登记妥协项）
  - 审查 4 项已知架构妥协约束边界、`#Include` 循环依赖、I/O 与表现层泄漏
  - 审查命名规范、错误处理、强制接管指令、箭头函数/花括号陷阱
  - 审查重复代码、圈复杂度、空 catch 块、注释完整度
  - 审查 GUI / 定时器 / 周期性触发规范

- [x] Task 3：AHK v2 安全性与性能审查（产出：`docs/review/2026-08-20/task-3-ahk-secperf.md`）
  - 审查输入验证、ConfigValidator、Map/Object 安全访问、文件 I/O 与路径处理
  - 审查 WebView2 通信安全（postMessage / 禁止 sync 代理 / 禁止等 Promise）
  - 审查脚本自注入安全（拦截用户按键、release、紧急释放）
  - 审查热路径日志限速、周期性触发时间、定时器泄漏、循环内 JSON/deepclone 开销

- [x] Task 4：Rust 纯逻辑 crate（domain / ipc-protocol / application）审查（产出：`docs/review/2026-08-20/task-4-rust-core.md`）
  - 审查 5-crate 依赖图、纯逻辑 crate 禁用依赖、trait 解耦、I/O 泄漏
  - 审查新增 service 层（backup_service / group_service / recording_service / time_format）职责边界与 I/O
  - 审查 thiserror 错误类型、`?` 传播、命名、`unwrap`/`expect`、`unsafe`
  - 审查 scheduler 与 ConfigRepository 的职责边界

- [x] Task 5：Rust src-tauri 架构、安全与质量审查（产出：`docs/review/2026-08-20/task-5-src-tauri.md`）
  - 审查 34 个 Tauri commands 宏标注、bridge trait 实现
  - 审查 IpcManager（named pipe）、ProcessWatchdog、心跳超时、panic hook 补偿
  - 审查并发安全（Arc / Mutex / blocking_lock 死锁）、`shutdown.rs` 优雅关机
  - 审查配置序列化兼容性（Rust Config 与 AHK config.json）

- [x] Task 6：性能优化专项审查（跨栈，产出：`docs/review/2026-08-20/task-6-performance.md`）
  - 审查 Rust↔AHK IPC 吞吐、背压、序列化热点
  - 审查 AHK 热路径日志限速有效性、定时器生命周期
  - 审查循环内重复 JSON 解析 / deepclone / Map 查找开销
  - 审查阻塞调用与异步上下文冲突的潜在延迟

- [x] Task 7：文档完整性审查（产出：`docs/review/2026-08-20/task-7-docs.md`）
  - 核对 AGENTS.md 与实际代码的一致性（crate 数、commands 数、测试口径、执行模式表、IpcCommand 示例）
  - 审查 docs/ 各指南是否过时、test-map.md 测试分布、TESTING.md 覆盖新模块
  - 审查 config.json schema 文档与实现一致性

- [x] Task 8：测试覆盖与质量审查（产出：`docs/review/2026-08-20/task-8-tests.md`）
  - 审查新增 `*_service.rs` 模块的测试覆盖
  - 审查测试隔离性、fixture 管理、测试前置检查流程
  - 审查 AHK 执行器测试（57 套件 / 244 Test_ 口径）、E2E（9 suite / 53 用例）
  - 识别覆盖率盲区

## Phase 3：汇总（依赖 Phase 2 全部完成，1 个子代理）

- [x] Task 9：去重汇总生成最终报告（产出：`docs/code-review-report-2026-08-20.md`）
  - 收集 Task 1 ~ Task 8 的发现清单
  - 去重并按 Critical / Important / Minor 统一分级
  - 按维度 + 模块分组组织，每条含位置 / 维度 / 级别 / 描述 / 根因 / 修复方案
  - 生成执行摘要、历史修复核对表、统计汇总

# Task Dependencies

- [Task 1] 为前置任务，先于 Phase 2 完成（提供变更清单与修复核对表供各审查任务引用）
- [Task 2] ~ [Task 8] 相互独立，可并行；同一时刻最多并发 4 个（分两波执行）
- [Task 9] 依赖 [Task 1] ~ [Task 8] 全部完成