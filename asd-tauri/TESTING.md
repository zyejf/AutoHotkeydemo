# ASD-Tauri 测试指南

本文件是 ASD-Tauri 项目测试体系的统一入口，覆盖测试分类、命名规范、运行命令、覆盖率生成、CI 流程、测试数据管理与结果分析。

测试规模（截至 2026-09-13，以 [`docs/test-map.md`](./docs/test-map.md) 为唯一权威来源，本文档不复制数字）：
- Rust 测试函数：`#[test]` + `#[tokio::test]` 属性数（详见 test-map.md「汇总」）
- AHK 执行器测试：套件数与 `Test_` 方法数（详见 test-map.md「汇总」）
- AHK v2 完整测试套件：`tests/run_all_tests.ahk` 汇总（详见 test-map.md「汇总」；口径为 `Test_` 方法 + runner 执行的 `Setup`/`Teardown` 钩子）
- 基准测试：7 个 criterion bench
- 模糊测试：5 个 fuzz target

详细的按文件测试分布见 [`docs/test-map.md`](./docs/test-map.md)。

---

## 1. 测试分类标准

ASD-Tauri 项目将测试划分为六类，每类有独立的目录约定、运行命令与适用场景。

### 1.1 单元测试

- **定义**：位于 `src/` 目录下、`#[cfg(test)] mod tests` 内的测试，验证单个模块/函数的内部行为，不跨 crate 边界。
- **运行命令**：`cargo test -p <crate> --lib`
- **目录约定**：与被测代码同文件，置于 `#[cfg(test)] mod tests { ... }` 块中。
- **典型示例**：`crates/asd-domain/src/validator.rs` 中的 `#[cfg(test)] mod tests`。

### 1.2 集成测试

- **定义**：位于 `tests/` 目录或 crate 根 `tests/` 子目录的独立测试文件，跨模块/跨 crate 验证公共 API 行为。
- **运行命令**：`cargo test -p <crate> --test <file>` 或 `cargo test -p <crate>`
- **目录约定**：
  - crate 内集成测试：`crates/<crate>/tests/<scope>_<type>_tests.rs`
  - 主 crate 集成测试：`src-tauri/src/tests/<scope>_<type>_tests.rs`（通过 `mod.rs` 聚合，由 `--lib` 一起运行）
  - 主 crate manifest 集成测试：`src-tauri/tests/test_manifest_feature_removed.rs`
- **典型示例**：`crates/asd-application/tests/concurrency_tests.rs`、`src-tauri/src/tests/ipc_tests.rs`。

### 1.3 端到端测试

- **定义**：模拟真实用户场景，验证从 Tauri Command 到 IPC Bridge、AppState、Scheduler 的完整数据流。
- **运行命令**：`cargo test -p asd-application --test e2e_dataflow_tests`
- **目录约定**：`crates/asd-application/tests/e2e_dataflow_tests.rs`。
- **典型示例**：`crates/asd-application/tests/e2e_dataflow_tests.rs` 中的 4 个端到端数据流测试。

### 1.4 基准测试

- **定义**：使用 criterion 框架的微基准测试，追踪热路径性能回归。
- **运行命令**：`cd src-tauri && cargo bench`
- **目录约定**：`src-tauri/benches/benchmarks.rs`。
- **基线对比**：与 `src-tauri/benches/baseline.json`（Task 8 生成）对比，性能退化 >10% 时发出警告（不阻塞）。
- **典型示例**：`src-tauri/benches/benchmarks.rs` 中的 7 个 criterion bench。

### 1.5 模糊测试

- **定义**：使用 `cargo-fuzz` + `libFuzzer` 对反序列化/解析逻辑进行随机输入测试。
- **运行命令**：
  ```bash
  cd src-tauri/fuzz
  cargo +nightly fuzz run fuzz_config_deserialize -- -max_total_time=600
  cargo +nightly fuzz run fuzz_hotkey_merger -- -max_total_time=600
  cargo +nightly fuzz run fuzz_ipc_command -- -max_total_time=600
  cargo +nightly fuzz run fuzz_ipc_json -- -max_total_time=600
  cargo +nightly fuzz run fuzz_ipc_message_parse -- -max_total_time=600
  ```
- **目录约定**：`src-tauri/fuzz/fuzz_targets/<name>.rs`。
- **CI 调度**：每周日 00:00 UTC cron 运行各 target 10 分钟，崩溃时上传 artifact。
- **典型示例**：`src-tauri/fuzz/fuzz_targets/fuzz_config_deserialize.rs`。

### 1.6 AHK 执行器测试

- **定义**：使用项目根目录 `tests/AutoHotUnit.ahk` 框架（`AutoHotUnitSuite` 基类）测试 `src-tauri/ahk_executor/` 下 5 个 AHK 脚本的纯逻辑方法，不依赖真实按键发送或 named pipe。
- **运行命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- **目录约定**：`tests/test_ahk_executor/test_<module>.ahk`（位于项目根目录的 `tests/` 下，非 `asd-tauri/tests/`）。
- **测试文件**：
  - `test_executor.ahk`（9 套件）：`CommandDispatcher._GetStr/_GetInt/_GetBool/_GetArr/_GetMap`、`MergeModeConfig`、`Dispatch unknown`、`RecordKey`、`Validation`
  - `test_ipc_client.ahk`（12 套件）：`IPCConst`、`MiniJson` 解析/序列化/往返/布尔标记、`IpcClient` 初始状态/序列号/断连接收/认证 token/去重
  - `test_hotkey_hook.ahk`（7 套件）：`Normalize`、`RegistrationState`、`Register/Unregister error`、`UnregisterAll`、`Init`、`Callback`
  - `test_sender.ahk`（11 套件）：`AllowedKeys`、`ValidateKey`、`ToggleGroup`、`StartPeriodic/Sequence/Enhanced/Hold`、`HoldModeToggle`、`EmergencyRelease`、`Shutdown`、`Init`
  - `test_joystick.ahk`（18 套件）：`AllowedKeys`、`ValidateKey`、`IsButton/IsPov/IsAxis`、`GetButtonNum/GetPovDirection/GetAxisInfo`、`AxisToVJoyId`、`PovDirectionToValue`、`ResolveMethod`、`IsVJoyAvailable`、`StopGroup`、`EmergencyRelease`、`Init`、`StartPeriodic/Sequence/Hold`
- **总计**：57 套件，255 个 `Test_` 方法（口径为 `tests/test_ahk_executor/*.ahk` 中以 `Test_` 开头的方法定义数）。
- **强制规范**：所有 AHK 测试文件必须包含 `#ErrorStdOut "UTF-8"` + `#Warn VarUnset, OutputDebug` + `#Warn Unreachable, OutputDebug` + `OnError` 回调，详见 [AGENTS.md](../AGENTS.md) 的「错误与警告接管机制」节。

---

## 2. 命名规范

### 2.1 测试函数命名

所有 Rust 测试函数必须以 `test_` 前缀开头，使用 snake_case，描述测试意图（场景 + 期望）。

- 正确：`test_register_hotkey_success`
- 正确：`test_recovering_recent_heartbeat_no_child_returns_restart_needed`
- 正确：`test_manifest_helper_smoke`
- 错误：`manifest_helper_smoke_test`（缺少 `test_` 前缀，已在 Task 1 重命名为 `test_manifest_helper_smoke`）
- 错误：`it_works`（描述过于模糊）

AHK 测试方法使用 `Test_<SuiteName>_<Scenario>` 形式（AutoHotUnit 约定），如 `Test_GetStr_MapType_ExistingKey`。

### 2.2 测试文件命名

Rust 集成测试文件遵循 `{scope}_{type}_tests.rs` 约定：

| 命名模式 | 含义 | 示例 |
|---------|------|------|
| `{scope}_tests.rs` | 按服务/模块分组的集成测试 | `backup_service_tests.rs`、`group_service_tests.rs`、`recording_service_tests.rs` |
| `{scope}_{type}_tests.rs` | 按场景类型分组的集成测试 | `concurrency_tests.rs`、`e2e_dataflow_tests.rs`、`cross_crate_tests.rs` |
| `{scope}_integration_tests.rs` | crate 级集成测试 | `integration_tests.rs` |
| `{scope}_boundary_tests.rs` | 边界条件测试 | `ipc_tests.rs`、`bridge_tests.rs` |
| `{scope}_compat_tests.rs` | 兼容性测试 | `config_compat_tests.rs` |
| `test_manifest_feature_removed.rs` | 主 crate manifest 集成测试（位于 `src-tauri/tests/`，由 cargo 自动发现，验证废弃 feature 已从 Cargo.toml 移除） | — |

主 crate 内联集成测试位于 `src-tauri/src/tests/`，通过 `mod.rs` 聚合：
- `ipc_tests.rs`（26 测试）：IPC 边界条件
- `bridge_tests.rs`：IpcBridge / TauriEventBridge / WatchdogBridge trait 实现
- `watchdog_integration_tests.rs`（17 个 `fn`，`#![cfg(windows)]` gating，含 15 个 `#[ignore]`）：ProcessWatchdog 跨平台。**口径提示**：本行按 `fn` 数计；`test-map.md` 按 `#[test]` 属性数计为 14，两者均有效。
- `config_compat_tests.rs`（11 测试）：Rust Config 与 AHK config.json 格式兼容性

AHK 测试文件命名：`test_<module>.ahk`，对应被测的 `ahk_executor/<module>.ahk`。

### 2.3 测试套件命名（AHK）

AHK 测试套件类名使用 PascalCase + `Tests` 后缀，描述被测对象：

- 正确：`CommandDispatcherGetStrTests extends AutoHotUnitSuite`
- 正确：`IpcClientParseAuthTokenTests extends AutoHotUnitSuite`
- 错误：`Tests1`（无描述性）

---

## 3. 运行命令矩阵

下表列出各 crate 的测试运行命令。测试数量统一以 [`docs/test-map.md`](./docs/test-map.md) 为唯一权威来源，本表不复制数字以免漂移。

| Crate | 类型 | 命令 | 预期结果 |
|-------|------|------|-----------|
| asd-domain | 单元 + 集成 | `cargo test -p asd-domain` | 见 test-map.md |
| asd-ipc-protocol | 单元 + 集成 | `cargo test -p asd-ipc-protocol` | 见 test-map.md |
| asd-application | 全部 | `cargo test -p asd-application` | 见 test-map.md |
| asd-test-harness | 单元 | `cargo test -p asd-test-harness` | 见 test-map.md |
| asd-tauri | 全部 | `cargo test -p asd-tauri` | 见 test-map.md |
| 全 workspace | 全部 | `cargo test --workspace` | 见 test-map.md |
| asd-tauri | 基准 | `cd src-tauri && cargo bench` | 7 个 bench |
| asd-tauri | 模糊 | `cd src-tauri/fuzz && cargo +nightly fuzz run <target>` | 5 个 target |
| asd-domain | Miri | `cargo +nightly miri test -p asd-domain` | 0 UB |
| asd-ipc-protocol | Miri | `cargo +nightly miri test -p asd-ipc-protocol` | 0 UB |
| asd-application | Miri | `cargo +nightly miri test -p asd-application -- --skip config_repository --skip save_config --skip load_from` | 0 UB |
| AHK 执行器 | 单元 | `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk` | 57 套件 / 255 个 Test_ 方法 |

**关键提示**：
- 测试数量统计以 [`docs/test-map.md`](./docs/test-map.md) 为唯一权威来源，本文档仅引用、不自行复制数字。
- Miri 验证需跳过 `config_repository`、`save_config`、`load_from`（涉及文件 I/O，Miri 不支持）。

---

## 4. 覆盖率生成方法

ASD-Tauri 项目统一使用 `cargo-llvm-cov` 作为覆盖率工具（自 Task 5 起，取代 `cargo-tarpaulin`）。

### 4.1 安装

```bash
cargo install cargo-llvm-cov
rustup component add llvm-tools-preview
```

### 4.2 本地生成

```bash
# 生成 HTML 报告（自动打开浏览器）
cd asd-tauri && cargo llvm-cov --workspace --html --output-dir coverage/

# 生成 lcov.info（用于 CI 上传 Codecov）
cd asd-tauri && cargo llvm-cov --workspace --lcov --output-path lcov.info

# 仅运行覆盖率不生成报告（快速验证）
cd asd-tauri && cargo llvm-cov --workspace --summary-only
```

### 4.3 覆盖率目标

覆盖率目标在 [`.codecov.yml`](./.codecov.yml) 中按 crate 配置：

| Crate | 覆盖率目标 | 说明 |
|-------|-----------|------|
| asd-domain | 95% | 纯逻辑 crate，高标准 |
| asd-ipc-protocol | 95% | 纯逻辑 crate，高标准 |
| asd-application | 90% | 应用逻辑 crate |
| asd-tauri（src-tauri） | 75% | 主 crate 含 IO/平台代码，标准放宽 |
| 总体 | 80% | patch 阈值 0.1% 递减 |

### 4.4 忽略目录

以下目录不计入覆盖率统计（见 `.codecov.yml` 的 `ignore` 节）：
- `crates/asd-test-harness/**`（测试工具 crate）
- `src-tauri/tests/**`、`**/tests/**`、`**/*_tests.rs`（集成测试目录）
- `src-tauri/benches/**`（基准测试）
- `src-tauri/fuzz/**`（模糊测试）
- `tests/**`（顶层测试目录）

### 4.5 一键流程

通过 `scripts/run-tests.ps1 -Coverage` 一键运行测试并生成覆盖率报告：

```powershell
./scripts/run-tests.ps1 -Coverage -Analyze
```

详见第 7 节。

---

## 5. CI 流程说明

CI 配置位于**仓库根目录** [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)。

> ⚠️ 2026-09-13 迁移：配置曾位于 `asd-tauri/.github/workflows/ci.yml`，但
> **GitHub Actions 只读取仓库根目录的 `.github/workflows`**，子目录那份从未被执行过。
> 现已迁移并修复（补 `working-directory`、修正 `cargo fmt --all -- --check` 写法）。
> 四闸门 job 为 `gates`（windows-latest，阻塞合并）；coverage/miri/fuzz/bench 为
> 辅助 job，均 `continue-on-error` 不阻塞；e2e 仅 `workflow_dispatch` 手动触发。
> 本地等价入口：`scripts/check-gates.sh` / `scripts/check-gates.ps1`。

### 5.1 test job

- **触发**：push 到 main/master、所有 PR
- **矩阵**：`windows-latest` + `ubuntu-latest`
- **步骤**：
  1. checkout 仓库
  2. 安装 Rust stable + clippy + rustfmt
  3. 缓存 cargo（Swatinem/rust-cache@v2）
  4. 安装 Linux 依赖（webkit2gtk、gtk3 等）
  5. `cargo fmt --all -- --check`（格式检查）
  6. `cargo clippy --workspace --all-targets -- -D warnings`（lint 检查）
  7. `cargo test -p asd-domain`
  8. `cargo test -p asd-ipc-protocol`
  9. `cargo test -p asd-application`
  10. `cargo test -p asd-tauri --lib`

### 5.2 coverage job

- **触发**：push 事件（非 PR）
- **运行环境**：`ubuntu-latest`
- **步骤**：安装 `cargo-llvm-cov` → `cargo llvm-cov --workspace --html --output-path coverage.html` → 上传为 artifact（保留 90 天）

### 5.3 miri job（Task 8 新增）

- **触发**：PR 事件
- **运行环境**：`ubuntu-latest`，`nightly` toolchain + `miri` component
- **范围**：asd-domain、asd-ipc-protocol、asd-application
- **策略**：允许失败（渐进式修复 UB）

### 5.4 fuzz job（Task 8 新增）

- **触发**：cron `0 0 * * 0`（每周日 00:00 UTC）
- **运行环境**：`ubuntu-latest`，`nightly` toolchain
- **范围**：5 个 fuzz target 各运行 10 分钟（`-max_total_time=600`）
- **失败处理**：崩溃时上传 artifact，创建 issue

### 5.5 bench job（Task 8 新增）

- **触发**：push 到 main
- **运行环境**：`ubuntu-latest`
- **步骤**：运行 `cargo bench` → 与 `benches/baseline.json` 比对 → 性能退化 >10% 时输出警告（不阻塞）

### 5.6 ahk-test job（Task 10 新增）

- **触发**：push 到 main/master、所有 PR
- **运行环境**：`windows-latest`
- **步骤**：通过 chocolatey 安装 AutoHotkey v2（`choco install autohotkey`）→ checkout → 运行 `AutoHotkey.exe tests\run_all_tests.ahk` → 解析输出判断通过/失败 → 上传 AHK 测试日志为 artifact

---

## 6. 测试数据管理规范

### 6.1 统一存放目录

所有测试固件（fixture）存放于 `asd-tauri/tests/fixtures/`，按类型分子目录：

```
asd-tauri/tests/fixtures/
├── configs/           # JSON 配置样本
│   └── tests_config.json   # 主测试配置（Task 1 迁移自 src-tauri/tests_config.json）
└── (未来扩展：inputs/, outputs/, mocks/)
```

### 6.2 引用方式

测试代码使用 `include_str!` 引用相对路径，禁止硬编码绝对路径：

```rust
// 正确：相对路径引用
const TEST_CONFIG: &str = include_str!("../../../tests/fixtures/configs/tests_config.json");

// 错误：硬编码绝对路径
const TEST_CONFIG: &str = include_str!("D:/1demo/AutoHotkeydemo/asd-tauri/tests/fixtures/configs/tests_config.json");
```

参考实现：`src-tauri/src/tests/config_compat_tests.rs` 第 1 行。

### 6.3 登记规范

新增测试固件必须同步更新 [`docs/test-map.md`](./docs/test-map.md) 的「测试固件」章节，记录：
- 文件路径
- 用途说明
- 引用该固件的测试文件列表

### 6.4 固件命名

- 配置样本：`<场景>_config.json`（如 `tests_config.json`、`minimal_config.json`、`invalid_config.json`）
- 输入数据：`<场景>_input.<ext>`
- 期望输出：`<场景>_expected.<ext>`

---

## 7. 测试结果分析

### 7.1 JUnit XML 生成

测试结果以 JUnit XML 格式集中收集，便于 CI 上传与本地分析。

**方式一：cargo nightly 原生支持**

```bash
cargo test --workspace -- --format junit -Z unstable-options > test-results/junit.xml
```

**方式二：cargo-junit-report（回退方案，stable 兼容）**

```bash
cargo install cargo-junit-report
cargo test --workspace -- -Z unstable-options --format json > test-results/raw.json
cargo junit-report --input test-results/raw.json --output test-results/junit.xml
```

输出目录：`asd-tauri/test-results/`（已在 `.gitignore` 中忽略）。

### 7.2 分析脚本

[`scripts/analyze-tests.ps1`](./scripts/analyze-tests.ps1)（Task 6 新增）解析 `test-results/` 下的 JUnit XML，输出：

- **总体通过率**：通过/失败/跳过数 + 百分比
- **失败清单**：失败测试的名称、文件、错误信息、堆栈
- **耗时 Top10**：按测试用例耗时降序排列的前 10 名
- **按 crate 分组统计**：每个 crate 的通过率、平均耗时、最慢测试

```powershell
./scripts/analyze-tests.ps1
# 或指定 JUnit XML 路径
./scripts/analyze-tests.ps1 -XmlPath test-results/junit.xml
```

### 7.3 一键流程

[`scripts/run-tests.ps1`](./scripts/run-tests.ps1)（Task 6 增强）支持 `-Coverage` 与 `-Analyze` 参数：

```powershell
# 快速运行所有测试
./scripts/run-tests.ps1 -Quick

# 运行测试 + 生成覆盖率
./scripts/run-tests.ps1 -Coverage

# 运行测试 + 生成覆盖率 + 分析结果（完整流程）
./scripts/run-tests.ps1 -Coverage -Analyze

# 仅运行特定 crate
./scripts/run-tests.ps1 -Crate asd-domain
```

`-Coverage -Analyze` 流程：
1. 运行 `cargo test --workspace` 生成 JUnit XML → `test-results/junit.xml`
2. 运行 `cargo llvm-cov --workspace --html --output-dir coverage/` 生成覆盖率
3. 调用 `scripts/analyze-tests.ps1` 解析 JUnit XML，输出通过率/失败清单/耗时 Top10/crate 分组统计
4. 自动打开 `coverage/index.html` 浏览器预览

### 7.4 CI artifact

CI 中 JUnit XML 上传为 artifact（保留 90 天），可在 GitHub Actions 运行页面下载。

---

## 参考

- [AGENTS.md](../AGENTS.md) — 项目根目录的 AI 代理规则，包含测试规范与错误接管机制
- [docs/test-map.md](./docs/test-map.md) — 测试地图（按 crate × 文件 × 测试数 × 覆盖范围）
- [.codecov.yml](./.codecov.yml) — Codecov 覆盖率配置
- [.github/workflows/ci.yml](./.github/workflows/ci.yml) — CI 工作流配置
- [scripts/run-tests.ps1](./scripts/run-tests.ps1) — 测试运行脚本
- [scripts/analyze-tests.ps1](./scripts/analyze-tests.ps1) — 测试结果分析脚本（Task 6 新增）
