# Tasks

- [x] Task 1: 测试数据目录化与命名规范修正
  - [ ] SubTask 1.1: 新建 `asd-tauri/tests/fixtures/configs/` 目录
  - [ ] SubTask 1.2: 迁移 `asd-tauri/src-tauri/tests_config.json` → `asd-tauri/tests/fixtures/configs/tests_config.json`（保留原文件为符号链接或删除）
  - [ ] SubTask 1.3: 更新 `asd-tauri/src-tauri/src/tests/config_compat_tests.rs` 中 `include_str!("../../tests_config.json")` → `include_str!("../../../tests/fixtures/configs/tests_config.json")`
  - [ ] SubTask 1.4: 重命名 `asd-tauri/src-tauri/tests/manifest_helper.rs` 中 `manifest_helper_smoke_test` → `test_manifest_helper_smoke`
  - [ ] SubTask 1.5: 在 `asd-tauri/TESTING.md`（Task 4 创建）中记录命名规范：函数 `test_*` 前缀、文件 `{scope}_{type}_tests.rs` 后缀
  - [ ] SubTask 1.6: 验证 `cargo test -p asd-tauri --lib --features test-manifest` 通过

- [x] Task 2: 补齐 Tauri Command 层测试缺口
  - [ ] SubTask 2.1: 在 `asd-tauri/src-tauri/src/commands/hotkey_cmd.rs` 添加 `#[cfg(test)] mod tests`，覆盖 register_hotkey / unregister_hotkey / list_hotkeys 命令（至少 6 个测试：正常路径 × 3 + 错误路径 × 3）
  - [ ] SubTask 2.2: 在 `asd-tauri/src-tauri/src/commands/system_cmd.rs` 添加 `#[cfg(test)] mod tests`，覆盖 get_system_status / emergency_release / toggle_hold_mode 命令（至少 6 个测试）
  - [ ] SubTask 2.3: 使用 `asd_test_harness::make_test_state` 构造测试状态，验证命令返回值和状态变更
  - [ ] SubTask 2.4: 验证 `cargo test -p asd-tauri --lib --features test-manifest commands::` 通过

- [x] Task 3: 消除 MockEventBridge 重复与跨平台 gating
  - [ ] SubTask 3.1: 将 `asd-tauri/src-tauri/src/tests/bridge_tests.rs` 行 319-349 的 `MockEventBridge` 合并到 `asd-tauri/crates/asd-test-harness/src/lib.rs`（如已有 `MockEventEmitter` 则验证功能等价，删除 bridge_tests.rs 中的重复定义）
  - [ ] SubTask 3.2: 更新 `bridge_tests.rs` 中 `test_event_emitter_trait_contract` 改用 `asd_test_harness::MockEventEmitter`
  - [ ] SubTask 3.3: 在 `asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs` 文件顶部添加 `#![cfg(windows)]` 或对每个测试添加 `#[cfg(windows)]`，解决 Ubuntu CI 编译失败
  - [ ] SubTask 3.4: 验证 `cargo test -p asd-tauri --lib --features test-manifest` 通过

- [x] Task 4: 测试文档体系建立
  - [ ] SubTask 4.1: 新建 `asd-tauri/TESTING.md`，包含：测试分类标准（单元/集成/端到端/基准/模糊/AHK 六类）、命名规范、运行命令矩阵、覆盖率生成方法、CI 流程说明、测试数据管理规范
  - [ ] SubTask 4.2: 新建 `asd-tauri/docs/test-map.md`，按 crate × 类型 × 文件 × 测试数 × 覆盖范围列测试地图表格（基于调研报告数据）
  - [ ] SubTask 4.3: 更新 `AGENTS.md`（项目根目录）的 "Testing Requirements" 节：测试统计 389 → 506+、覆盖率命令 `cargo tarpaulin` → `cargo llvm-cov`、新增 "AHK 执行器测试" 小节、新增 "测试结果分析" 小节、新增 "测试数据管理" 小节
  - [ ] SubTask 4.4: 在 `AGENTS.md` 的 "关键设计决策" 节更新测试统计数字（389 → 506+，标注 2026-06-27）

- [x] Task 5: 覆盖率配置统一
  - [ ] SubTask 5.1: 新建 `asd-tauri/.codecov.yml`，配置：coverage target 80%、threshold 0.1% 递减、ignore tests/ benches/ fuzz/ 目录、split by crate
  - [ ] SubTask 5.2: 在 `TESTING.md` 中记录 `cargo llvm-cov --workspace --html` 本地生成命令
  - [ ] SubTask 5.3: 在 `AGENTS.md` 中将所有 `cargo tarpaulin` 命令替换为 `cargo llvm-cov` 等效命令

- [x] Task 6: 测试脚本增强
  - [x] SubTask 6.1: 增强 `asd-tauri/scripts/run-tests.ps1`：新增 `-Coverage` 参数（运行 cargo llvm-cov 生成 lcov.info + HTML）、新增 `-Analyze` 参数（运行后调用 analyze-tests.ps1）
  - [x] SubTask 6.2: 新建 `asd-tauri/scripts/analyze-tests.ps1`：解析 `test-results/` 下的 JUnit XML，输出通过率、失败清单、耗时 Top10、按 crate 分组统计表格
  - [x] SubTask 6.3: 在 `run-tests.ps1` 中添加 `cargo test -- --format junit -Z unstable-options` 选项生成 JUnit XML 到 `test-results/` 目录（需 Rust nightly，回退到 `cargo-junit-report`）
  - [x] SubTask 6.4: 验证 `./scripts/run-tests.ps1 -Quick -Analyze` 本地执行通过

- [x] Task 7: CI 测试完整性增强
  - [x] SubTask 7.1: 在 `asd-tauri/.github/workflows/ci.yml` 的 test job 中新增 `cargo test -p asd-test-harness` 步骤（放在 asd-application 之前）
  - [x] SubTask 7.2: 在 test job 中安装 `cargo-junit-report`，将各 crate 测试结果转换为 JUnit XML，上传为 artifact（保留 90 天）
  - [x] SubTask 7.3: 在 test job 中安装 cargo-llvm-cov，生成 lcov.info，使用 codecov-action@v4 上传到 Codecov（需 CODECOV_TOKEN secret）
  - [x] SubTask 7.4: 验证 CI 配置语法正确（`yamllint` 或 `actionlint`）

- [x] Task 8: CI 高级测试 job（Miri + Fuzz + Bench）
  - [x] SubTask 8.1: 新增 `miri` job：使用 `nightly` toolchain + `miri` component，对 asd-domain / asd-ipc-protocol / asd-application 运行 `cargo +nightly miri test`（仅 ubuntu，允许失败以渐进式修复）
  - [x] SubTask 8.2: 新增 `fuzz` job：`schedule: cron: '0 0 * * 0'`（每周日），运行 3 个 fuzz target 各 10 分钟（`cargo +nightly fuzz run fuzz_config_deserialize -- -max_total_time=600`），崩溃时上传 artifact
  - [x] SubTask 8.3: 新增 `bench` job：在 push 到 main 时运行 `cargo bench`，与 `benches/baseline.json` 比对，性能退化 >10% 时输出警告（使用 `critcmp` 或自写脚本），不阻塞
  - [x] SubTask 8.4: 生成初始 `asd-tauri/src-tauri/benches/baseline.json`（运行一次 bench 记录基线）

- [x] Task 9: AHK 执行器自动化测试
  - [ ] SubTask 9.1: 新建 `tests/test_ahk_executor/` 目录
  - [ ] SubTask 9.2: 编写 `tests/test_ahk_executor/test_executor.ahk`：测试 executor.ahk 的命令解析（StartGroup/StopGroup/UpdateConfig 等）、按键序列执行逻辑、错误处理（使用 AutoHotUnit 框架，遵循 AGENTS.md 的 AHK 测试规范：#ErrorStdOut + #Warn + OnError）
  - [ ] SubTask 9.3: 编写 `tests/test_ahk_executor/test_ipc_client.ahk`：测试 ipc_client.ahk 的 named pipe 连接、JSON 序列化/反序列化、心跳发送、auth token 处理
  - [ ] SubTask 9.4: 编写 `tests/test_ahk_executor/test_hotkey_hook.ahk`：测试 hotkey_hook.ahk 的热键注册/注销逻辑、热键事件回调
  - [ ] SubTask 9.5: 编写 `tests/test_ahk_executor/test_sender.ahk`：测试 sender.ahk 的按键发送、延时处理、增强模式按键序列
  - [ ] SubTask 9.6: 编写 `tests/test_ahk_executor/test_joystick.ahk`：测试 joystick.ahk 的摇杆输入读取、阈值判断
  - [ ] SubTask 9.7: 更新 `tests/run_all_tests.ahk` 包含 test_ahk_executor 目录下的所有测试
  - [ ] SubTask 9.8: 验证 `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk` 通过

- [x] Task 10: CI AHK 测试 job
  - [ ] SubTask 10.1: 在 `asd-tauri/.github/workflows/ci.yml` 新增 `ahk-test` job：仅 windows-latest，使用 chocolatey 安装 AutoHotkey v2（`choco install autohotkey`）
  - [ ] SubTask 10.2: 在 ahk-test job 中 checkout 仓库，运行 `AutoHotkey.exe tests\run_all_tests.ahk`，解析输出判断通过/失败
  - [ ] SubTask 10.3: 上传 AHK 测试日志为 artifact

- [x] Task 11: 最终验证与文档同步
  - [x] SubTask 11.1: 运行 `cargo test --workspace` 验证所有 Rust 测试通过
  - [x] SubTask 11.2: 运行 `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk` 验证 AHK 测试通过
  - [x] SubTask 11.3: 运行 `./scripts/run-tests.ps1 -Coverage -Analyze` 验证完整流程
  - [x] SubTask 11.4: 验证 `AGENTS.md` 中测试统计与实际 `#[test]` + `#[tokio::test]` 计数误差 ≤ 5%
  - [x] SubTask 11.5: 验证 `asd-tauri/docs/test-map.md` 中所有文件路径存在且测试数准确

# Task Dependencies

- [Task 2] 可与 [Task 1] 并行（无依赖）
- [Task 3] 可与 [Task 1, 2] 并行（无依赖）
- [Task 4] 依赖 [Task 1, 2, 3] 完成（文档需反映最终代码状态）
- [Task 5] 可与 [Task 1-3] 并行（独立配置文件）
- [Task 6] 依赖 [Task 5]（脚本引用覆盖率工具）
- [Task 7] 依赖 [Task 1, 3]（CI 需测试代码已修正）
- [Task 8] 依赖 [Task 7]（CI 基础设施就绪后扩展高级 job）
- [Task 9] 可与 [Task 1-8] 并行（AHK 测试独立于 Rust 测试）
- [Task 10] 依赖 [Task 9]（CI 需 AHK 测试代码已就绪）
- [Task 11] 依赖 [所有前置任务]（最终验证）
