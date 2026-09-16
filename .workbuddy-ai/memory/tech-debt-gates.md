# 技术债度量闸门 与 覆盖率棘轮

## `scripts/check-tech-debt.py`（**G3e**，2026-09-16 起在四闸门内）

六信号：C1a 孤儿文件 / C1b 同名重复 / C1c 代码误放 `docs` 等 / C2 `tests/` 未接入执行 /
C3 文档-代码一致性 / **C3b 文档硬写的 AHK 基线数字**。
**C1a/C1b/C1c/C2/C3b 走棘轮**（存量只登记，新增才 FAIL），**C3 不棘轮、恒 0 硬阻断**。
基线 `.review-analysis/tech-debt-baseline.json`，清理后 `--update-baseline` 收紧（diff 必须进 CR）。约 2.5s。
接入点：`check-gates.sh`/`.ps1` 的 G3e（**不随 `--quick`**）；
⚠️ `.github/workflows/ci.yml` 是**独立实现**，加闸门要改两处。只扫 AHK；JS/TS 孤儿未覆盖（已知盲区）。

- ⚠️ **C3b 写法约定**：文档里**不要复写 AHK 用例总数**，写「见 test-map.md」指针。
  带日期历史报告里的数字是当日快照，**改它等于篡改历史**，登记豁免即可。
  **举例写在反引号里**（匹配前剔除反引号片段），裸数字才拦。
- ⚠️ **「在 tests/ 目录下」≠「是测试」**：判测试看有无 `Test_` 函数与 runner 入边
  （`tests/legacy/json.ahk` 1469 行、0 个 `Test_`，伪装了很久）。
- ⚠️ **「数字在文档里出现过」不是一致性证据**：`format(2.0,'g')=="2"` 会命中「AutoHotkey v2.0」。
  判 K 值漂移必须**数字与 bench 名同行**、只认小数形态、排除 `v2.0` 版本号上下文。
- ⚠️ 全仓 `Path.rglob` **必须先剪枝** `target/node_modules/.git/AutoHotkey-2.0.26/archive`
  （否则光枚举 23s；剪后 2.5s）。

## `scripts/check-coverage.py`（**G3f**）

只测 3 个纯逻辑 crate。取数命令须与 CI 一致（`--package` ×3，不能 `--workspace`）。
基线 `.review-analysis/coverage-baseline.json`。

- ⚠️ **分母含 `#[cfg(test)]` 测试代码**（cargo-llvm-cov 测测试二进制），占比 0%~84% 不等
  → **跨文件百分比不可比**，「最低的 5 个文件」只能看同文件纵向趋势。登记 TD-026 豁免不修：
  `#[coverage(off)]` 在 rustc 1.95 仍实验；`LF` 与逐行 `DA` 有 10/15 文件不一致，无法按行剔除。
  **别再重复调查这两条路。**
- ⚠️ **trait 默认方法体恒 0% 常属正常**：只为**实例化的具体类型**生成代码，无实现者 → 0%，不是漏测。
- ⚠️ 漂移判据是**命中数是否与行数同向变化**（`|Δhits/Δlines| ≥ 0.5` 判真实改动）。
  只判行数会把「补测试」误报成换尺子 → 训练出无脑 `--update-baseline`，棘轮失效。
  `--baseline <path>` 可用副本做阳性对照。
- ⚠️ **G3f 只跑在 CI（ubuntu），不在 `check-gates.sh`**。本机 Windows 必然报「统计口径漂移」FAIL
  （`cfg(windows)` 让行数变多、命中不动）。**别在本机 `--update-baseline`**。

## 文档 lint 收紧（TD-021，2026-09-16 收官）

- **推进机制**：`missing_errors_doc`/`missing_panics_doc` 在 `asd-tauri/Cargo.toml`
  `[workspace.lints]` 由 allow 改 **warn**。**不放 crate 级豁免**，未补齐的文件各自在
  **文件头** `#![allow(...)]`，补完一个删一行。⚠️ `src-tauri/Cargo.toml` **没有 `[lints]` 段**，
  不吃 workspace lints。
- **写 `# Errors` 的方法**：必须**逐个读函数体**得出失败条件，凭签名猜的是误导性文档。
  每个文件补完做阳性对照（加一个未写契约的 `pub fn` → clippy 红，还原 → 绿）。
- ⚠️ `clippy::doc_lazy_continuation` **两个触发点**：① `-` 列表后的段落**必须空一行**；
  ② **多行列表项续行必须缩进**（`///   `）。`cargo fmt` 不补缩进。
- 补文档是**挖真信号**的过程：本轮挖出「一批返回 `Result` 但恒定 `Ok` 的接口」
  （`clippy::unnecessary_wraps` 默认**不检查导出函数**）、`register_hotkey` 的 `Ok(Some(x))`
  表示**没注册成功**、回滚**不是无条件的**。够格的另立 TD 项。
