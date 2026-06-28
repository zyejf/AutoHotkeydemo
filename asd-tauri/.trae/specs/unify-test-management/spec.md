# 统一测试管理与整合 Spec

## Why

ASD-Tauri 项目测试资源丰富（506 个测试函数、19 个内联测试文件、11 个集成测试文件、7 个基准、3 个 fuzz target），但存在显著的管理缺口：
- **文档过时**：AGENTS.md 记录 389 个测试，实际 506 个；spec.md 记录 461 个
- **覆盖率工具不一致**：AGENTS.md 推荐 tarpaulin，CI 实际用 llvm-cov，无统一配置文件
- **测试数据无目录化**：tests_config.json 散落在 src-tauri/ 根，无 fixtures/ 目录
- **CI 不完整**：未运行 asd-test-harness 测试、未运行 Miri 验证、未运行 fuzz/bench、未上传覆盖率到第三方服务
- **AHK 执行器测试空白**：5 个 .ahk 脚本无任何自动化测试
- **测试结果无集中收集**：CI 仅输出日志，无 JUnit XML 报告，无趋势分析
- **命名/分类不统一**：manifest_helper_smoke_test 无 test_ 前缀；asd-application/tests/ 文件命名混杂（按服务 vs 按场景）

本次工作系统性整合所有测试资源，建立统一管理体系，制定标准化流程与规范，实现测试结果集中收集与分析，并建立持续集成的测试机制。

## What Changes

### 文档体系
- 新建 `asd-tauri/TESTING.md`：统一测试指南（运行命令、分类标准、命名规范、覆盖率、CI 流程）
- 更新 `AGENTS.md`：修正过时测试统计（389 → 506+）、统一覆盖率命令为 cargo-llvm-cov、补充 AHK 测试章节
- 新建 `asd-tauri/docs/test-map.md`：测试地图（crate × 类型 × 文件 × 测试数 × 覆盖范围）

### 规范层
- 制定测试命名约定：`test_*` 前缀强制、文件命名 `{scope}_{type}_tests.rs` 约定
- 制定测试分类标准：单元 / 集成 / 端到端 / 基准 / 模糊 / AHK 六类
- 重命名不一致的测试函数（如 `manifest_helper_smoke_test` → `test_manifest_helper_smoke`）

### 测试数据目录化
- 新建 `asd-tauri/tests/fixtures/` 目录作为统一测试数据存放点
- 迁移 `src-tauri/tests_config.json` → `tests/fixtures/configs/tests_config.json`
- 更新 `config_compat_tests.rs` 的 `include_str!` 路径
- 建立测试数据管理规范（fixtures/ 下按类型分子目录）

### 覆盖率统一
- **BREAKING** 移除 AGENTS.md 中的 cargo-tarpaulin 推荐，统一为 cargo-llvm-cov
- 新建 `asd-tauri/.codecov.yml`：覆盖率配置（目标 80%、阈值递减 0.1%）
- CI 中安装 cargo-llvm-cov 并生成 lcov.info，上传到 Codecov（需仓库 secrets）
- 本地脚本 `scripts/run-tests.ps1` 增加 `-Coverage` 参数生成覆盖率报告

### CI 增强
- 新增 asd-test-harness 测试步骤（之前遗漏）
- 新增 Miri 验证 job（纯逻辑 crate，nightly + miri）
- 新增 fuzz 定期运行 job（cron：每周日凌晨，仅 ubuntu）
- 新增 bench 回归检测 job（与 baseline 比对，性能退化 >10% 时警告）
- 配置 JUnit XML 测试报告生成（cargo-junit-report），上传为 artifact
- 跨平台一致性：watchdog_integration_tests.rs 添加 `#[cfg(windows)]` gating

### AHK 执行器测试
- 复用项目根目录 `tests/` 框架（AutoHotUnit）和 run_all_tests.ahk 入口
- 新建 `tests/test_ahk_executor/` 目录，为 5 个 AHK 脚本编写测试：
  - `test_executor.ahk`：executor.ahk 主流程测试
  - `test_ipc_client.ahk`：ipc_client.ahk IPC 协议测试
  - `test_hotkey_hook.ahk`：hotkey_hook.ahk 热键注册测试
  - `test_sender.ahk`：sender.ahk 按键发送测试
  - `test_joystick.ahk`：joystick.ahk 摇杆输入测试
- CI 新增 AHK 测试 job（仅 windows，依赖 AutoHotkey v2 安装）

### 测试结果集中收集
- CI 上传 JUnit XML 测试报告为 artifact（保留 90 天）
- `scripts/run-tests.ps1` 增强：输出 JUnit XML 到 `test-results/` 目录
- 新建 `scripts/analyze-tests.ps1`：分析测试报告，输出通过率、失败清单、耗时 Top10

### 关键缺口补齐
- 补充 `src-tauri/src/commands/hotkey_cmd.rs` 测试（当前 0 个）
- 补充 `src-tauri/src/commands/system_cmd.rs` 测试（当前 0 个）
- 合并 `src-tauri/src/tests/bridge_tests.rs` 中的 MockEventBridge 到 asd-test-harness（消除重复）

## Impact

- **Affected specs**: `integration-test-suite`（已完成的前置工作，本次在其基础上整合）
- **Affected code**:
  - `AGENTS.md`（项目根）：更新测试统计、覆盖率命令、新增 AHK 测试章节
  - `asd-tauri/TESTING.md`（新建）
  - `asd-tauri/docs/test-map.md`（新建）
  - `asd-tauri/.codecov.yml`（新建）
  - `asd-tauri/.github/workflows/ci.yml`（增强：新增 4 个 job）
  - `asd-tauri/scripts/run-tests.ps1`（增强：-Coverage、-Analyze 参数）
  - `asd-tauri/scripts/analyze-tests.ps1`（新建）
  - `asd-tauri/src-tauri/tests_config.json` → `asd-tauri/tests/fixtures/configs/tests_config.json`（迁移）
  - `asd-tauri/src-tauri/src/tests/config_compat_tests.rs`（更新 include_str! 路径）
  - `asd-tauri/src-tauri/src/tests/manifest_helper.rs`（重命名测试函数）
  - `asd-tauri/src-tauri/src/commands/hotkey_cmd.rs`（补充测试）
  - `asd-tauri/src-tauri/src/commands/system_cmd.rs`（补充测试）
  - `asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`（添加 #[cfg(windows)] gating）
  - `asd-tauri/crates/asd-test-harness/src/lib.rs`（合并 MockEventBridge）
  - `asd-tauri/src-tauri/src/tests/bridge_tests.rs`（改用 asd-test-harness 的 MockEventEmitter）
  - `tests/test_ahk_executor/`（新建目录，5 个 AHK 测试文件）
  - `tests/run_all_tests.ahk`（更新：包含 test_ahk_executor）

## ADDED Requirements

### Requirement: 统一测试文档体系

系统 SHALL 提供完整的测试文档体系，包括 TESTING.md 测试指南、test-map.md 测试地图，并保持 AGENTS.md 中的测试统计与实际一致。

#### Scenario: 新开发者查询测试方法
- **WHEN** 新开发者阅读 TESTING.md
- **THEN** 能找到所有测试运行命令、分类标准、命名规范、覆盖率生成方法、CI 流程

#### Scenario: 测试统计自动同步
- **WHEN** 新增测试函数后查询 AGENTS.md
- **THEN** 测试统计数字与实际 `#[test]` + `#[tokio::test]` 计数一致（误差 ≤ 5%）

### Requirement: 测试命名与分类规范

系统 SHALL 强制执行统一的测试命名约定和分类标准。

#### Scenario: 测试函数命名
- **WHEN** 编写新的测试函数
- **THEN** 函数名必须以 `test_` 开头，使用 snake_case，描述测试意图（如 `test_recovering_recent_heartbeat_no_child_returns_restart_needed`）

#### Scenario: 测试文件命名
- **WHEN** 创建新的集成测试文件
- **THEN** 文件名遵循 `{scope}_{type}_tests.rs` 约定（如 `ipc_boundary_tests.rs`、`state_concurrency_tests.rs`）

### Requirement: 测试数据目录化

系统 SHALL 将所有测试数据集中到 `tests/fixtures/` 目录下，按类型分子目录管理。

#### Scenario: 测试数据查找
- **WHEN** 开发者需要查找测试配置样本
- **THEN** 在 `tests/fixtures/configs/` 目录下找到所有 JSON 配置样本（tests_config.json、minimal_config.json 等）

#### Scenario: 测试数据引用
- **WHEN** 测试代码需要加载测试数据
- **THEN** 使用 `include_str!("../../../tests/fixtures/configs/xxx.json")` 相对路径引用，不使用绝对路径

### Requirement: 统一覆盖率工具

系统 SHALL 统一使用 cargo-llvm-cov 作为覆盖率工具，并配置 Codecov 上传。

#### Scenario: 本地生成覆盖率
- **WHEN** 开发者运行 `./scripts/run-tests.ps1 -Coverage`
- **THEN** 生成 lcov.info 和 HTML 报告，HTML 自动打开浏览器预览

#### Scenario: CI 覆盖率上传
- **WHEN** CI 在 push 事件运行
- **THEN** 生成覆盖率报告并上传到 Codecov，README 中显示覆盖率徽章

### Requirement: CI 完整性

系统 SHALL 在 CI 中运行所有类型的测试，包括单元、集成、Miri、fuzz、bench、AHK 测试。

#### Scenario: Miri 验证
- **WHEN** CI 在 PR 事件运行
- **THEN** 对 asd-domain、asd-ipc-protocol、asd-application 运行 Miri 验证，0 UB 才通过

#### Scenario: Fuzz 定期运行
- **WHEN** 每周日凌晨触发 cron job
- **THEN** 运行 3 个 fuzz target 各 10 分钟，崩溃时创建 issue

#### Scenario: 基准回归检测
- **WHEN** CI 在 push 到 main 运行
- **THEN** 运行 criterion bench，与 baseline 比较，性能退化 >10% 时发出警告（不阻塞）

#### Scenario: AHK 测试
- **WHEN** CI 在 windows-latest 运行
- **THEN** 安装 AutoHotkey v2，运行 `tests/run_all_tests.ahk`，验证所有 AHK 测试通过

### Requirement: 测试结果集中收集

系统 SHALL 集中收集所有测试结果为 JUnit XML 格式，并提供分析工具。

#### Scenario: CI 测试报告
- **WHEN** CI 测试 job 完成
- **THEN** 生成 JUnit XML 报告上传为 artifact，保留 90 天

#### Scenario: 本地测试分析
- **WHEN** 开发者运行 `./scripts/analyze-tests.ps1`
- **THEN** 输出通过率、失败清单、耗时 Top10 测试、按 crate 分组统计

### Requirement: AHK 执行器自动化测试

系统 SHALL 为 ahk_executor/ 下的 5 个 AHK 脚本提供自动化测试，复用项目根目录的 AutoHotUnit 框架。

#### Scenario: executor.ahk 测试
- **WHEN** 运行 `tests/test_ahk_executor/test_executor.ahk`
- **THEN** 验证 executor.ahk 的命令解析、按键序列执行、错误处理逻辑

#### Scenario: ipc_client.ahk 测试
- **WHEN** 运行 `tests/test_ahk_executor/test_ipc_client.ahk`
- **THEN** 验证 ipc_client.ahk 的 named pipe 连接、JSON 收发、心跳机制

### Requirement: 关键测试缺口补齐

系统 SHALL 补齐 Tauri Command 层的测试缺口，消除零测试的 command 模块。

#### Scenario: hotkey_cmd 测试
- **WHEN** 运行 `cargo test -p asd-tauri --lib --features test-manifest commands::hotkey_cmd`
- **THEN** 验证 register_hotkey / unregister_hotkey / list_hotkeys 命令的正确性和错误处理

#### Scenario: system_cmd 测试
- **WHEN** 运行 `cargo test -p asd-tauri --lib --features test-manifest commands::system_cmd`
- **THEN** 验证 get_system_status / emergency_release / toggle_hold_mode 命令的正确性

## MODIFIED Requirements

### Requirement: AGENTS.md 测试规范

AGENTS.md 中的 "Testing Requirements" 节 SHALL 反映当前实际的测试规模和工具链。

**变更点**：
- 测试统计从 "389 个测试" 更新为 "506+ 个测试"（标注日期）
- 覆盖率命令从 `cargo tarpaulin` 改为 `cargo llvm-cov`
- 新增 "AHK 执行器测试" 小节，说明 `tests/test_ahk_executor/` 目录和运行命令
- 新增 "测试结果分析" 小节，说明 `scripts/analyze-tests.ps1` 用法
- 新增 "测试数据管理" 小节，说明 `tests/fixtures/` 目录规范

## REMOVED Requirements

### Requirement: cargo-tarpaulin 推荐

**Reason**: 覆盖率工具已统一为 cargo-llvm-cov，tarpaulin 在 Windows 下需 WSL 且与 CI 不一致
**Migration**: AGENTS.md 中所有 `cargo tarpaulin` 命令替换为 `cargo llvm-cov`；本地若已安装 tarpaulin 可继续使用，但文档不再推荐
