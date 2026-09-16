#!/usr/bin/env bash
# 运行 tests/ 下的独立 AHK 测试脚本（tests/test_*.ahk），逐个收集退出码并汇总。
#
# 为什么需要它（TD-031 / C2）：
#   这些脚本各自跑一套断言，但**从未被任何 runner 执行过** —— 它们不在
#   tests/run_all_tests.ahk 的套件注册里。结果就是里面的一堆陈旧断言与生产缺陷
#   长期没人发现（2026-09-16 一接上执行就连挖出三个生产 BUG，见 TD-034/035/036）。
#   本脚本把它们串起来，让 check-gates.sh 的 G3f 能守住。
#
# 前置条件：
#   每个脚本必须以 `TestReporter.Finish()` 或 `ExitApp(failed > 0 ? 1 : 0)` 结尾 ——
#   AHK 的裸 `ExitApp()` 退出码恒为 0，失败会被静默吞掉。
#
# 环境变量：
#   AHK_EXE  AutoHotkey v2 可执行文件路径
#
# 用法：bash scripts/run-standalone-ahk-tests.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT_NATIVE="$REPO_ROOT"
if command -v cygpath >/dev/null 2>&1; then
  REPO_ROOT_NATIVE="$(cygpath -w "$REPO_ROOT")"
fi
AHK_EXE="${AHK_EXE:-/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe}"

if [ ! -f "$AHK_EXE" ]; then
  echo "未找到 AutoHotkey v2：$AHK_EXE"
  echo "请用 AHK_EXE 环境变量指定路径"
  exit 1
fi

SCRIPTS=(
  test_error_system
  test_integration_error_system
  test_joy_hotkey_manager
  test_key_recorder
  test_key_test_integration
  test_key_validator
  test_webview2_bridge
)

passed=0
failed=0
failed_names=""

for name in "${SCRIPTS[@]}"; do
  script="$REPO_ROOT/tests/$name.ahk"
  if [ ! -f "$script" ]; then
    echo "  [缺失] $name.ahk 不存在"
    failed=$((failed + 1))
    failed_names="$failed_names $name(缺失)"
    continue
  fi

  log="$(mktemp)"
  # 在仓库根下运行：这些脚本用 A_ScriptDir 定位配置与报告目录，换 cwd 会改变解析结果
  ( cd "$REPO_ROOT" && "$AHK_EXE" "$REPO_ROOT_NATIVE\\tests\\$name.ahk" ) >"$log" 2>&1
  rc=$?
  rm -f "$log" 2>/dev/null || true

  if [ "$rc" -eq 0 ]; then
    echo "  ✓ $name"
    passed=$((passed + 1))
  else
    echo "  ✗ $name（exit=$rc）"
    failed=$((failed + 1))
    failed_names="$failed_names $name"
  fi
done

# 与 G3b 保持同样的行格式，便于统一解析
echo "独立脚本总计: $((passed + failed)) 个"
echo "独立脚本通过: $passed 个"
echo "独立脚本失败: $failed 个"
if [ "$failed" -gt 0 ]; then
  echo "失败清单:$failed_names"
fi

[ "$failed" -eq 0 ] || exit 1
exit 0
