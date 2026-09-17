#!/usr/bin/env bash
# 运行「不在 run_all_tests.ahk 套件注册里」的独立 AHK 测试脚本，逐个收集退出码并汇总。
#
# 为什么需要它（TD-031 / C2）：
#   这些脚本各自跑一套断言，但**从未被任何 runner 执行过**。结果就是里面的一堆陈旧
#   断言与生产缺陷长期没人发现 —— 2026-09-16 一接上执行就连挖出五个生产 BUG
#   （TD-034/035/036/037）。本脚本把它们串起来，让 check-gates.sh 的 **G3g** 能守住。
#   覆盖：tests/ 下 7 个（147 条断言）+ tools/ahk-bench/lib/seqgen_test.ahk（53 条）。
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

# CI（windows-latest）传进来的是 Windows 原生路径（C:\...），Git Bash 的 `-f` 认不了
# 反斜杠 —— 会被当成转义符。先归一化成 POSIX 路径。
if [ ! -f "$AHK_EXE" ] && command -v cygpath >/dev/null 2>&1; then
  _converted="$(cygpath -u "$AHK_EXE" 2>/dev/null || true)"
  [ -n "$_converted" ] && AHK_EXE="$_converted"
fi

if [ ! -f "$AHK_EXE" ]; then
  echo "未找到 AutoHotkey v2：$AHK_EXE"
  echo "请用 AHK_EXE 环境变量指定路径"
  exit 1
fi

# 相对仓库根的路径。用路径而不是裸名字，是因为最后一个不在 tests/ 下
# （tools/ahk-bench/lib/seqgen_test.ahk，2026-09-16 接入）。
SCRIPTS=(
  tests/test_error_system.ahk
  tests/test_integration_error_system.ahk
  tests/test_joy_hotkey_manager.ahk
  tests/test_key_recorder.ahk
  tests/test_key_test_integration.ahk
  tests/test_key_validator.ahk
  tests/test_webview2_bridge.ahk
  tools/ahk-bench/lib/seqgen_test.ahk
  tests/archive/test_all_tests_have_onerror_c6.ahk
  tests/archive/test_config_c8.ahk
  tests/archive/test_migration_logger_c2.ahk
)

# 只跑指定的几个（相对仓库根的路径）—— 单脚本调试与阳性对照用，省掉 4 分钟全量。
# 例：bash scripts/run-standalone-ahk-tests.sh tests/test_webview2_bridge.ahk
if [ "$#" -gt 0 ]; then
  SCRIPTS=("$@")
fi

passed=0
failed=0
failed_names=""

for rel in "${SCRIPTS[@]}"; do
  script="$REPO_ROOT/$rel"
  if [ ! -f "$script" ]; then
    echo "  [缺失] $rel 不存在"
    failed=$((failed + 1))
    failed_names="$failed_names $rel(缺失)"
    continue
  fi

  # AHK 是原生 Windows 程序，要的是反斜杠路径
  native_rel="$(echo "$rel" | tr '/' '\\')"
  log="$(mktemp)"
  # 起始时刻锚点：用它判断「报告是不是本次运行产出的」，避免旧报告冒充
  marker="$(mktemp)"

  # 在仓库根下运行：这些脚本用 A_ScriptDir 定位配置与报告目录，换 cwd 会改变解析结果
  ( cd "$REPO_ROOT" && "$AHK_EXE" "$REPO_ROOT_NATIVE\\$native_rel" ) >"$log" 2>&1
  rc=$?

  # ---- 假绿防护（2026-09-17 实测事故）----
  # 退出码 0 **不足以**证明脚本跑到了结尾。AHK v2 里「OnError 回调返回 true（已处理）」
  # 会把运行时错误吞掉、主线程静默终止、退出码仍是 0 —— 于是「一条断言都没跑」在门禁里
  # 显示为 ✓。实测触发方式：`FileDelete` 对**不存在**的文件会抛错（对照组：目标存在时正常
  # 返回），配合吞错写法就让 test_webview2_bridge.ahk 静默空转了很久，38 条断言从未执行。
  # 所以退出码为 0 时，还必须证明脚本真的走到了结尾：
  #   · 用 TestReporter 的脚本 → 必须新产出一份 standalone 报告（Finish() 才会写）
  #   · 其它脚本              → stdout 必须有内容
  # 判定「跑到了结尾」的通用办法：本次运行必须留下**新鲜产物**（比 marker 新）。
  # 三种产物形态都在实际脚本里出现过，所以并集判断，不能只认一种：
  #   · stdout                                   （test_error_system / joy_hotkey_manager / c6 / c8 / c2）
  #   · tests/reports/standalone/*.json          （TestReporter；Finish() 写固定名，
  #                                               ExportReport() 写时间戳名 —— 两种都要认）
  #   · 脚本同目录的 *.log                        （seqgen_test 写 seqgen_test_result.log）
  ran_to_end=0
  reason=""
  if [ -s "$log" ]; then
    ran_to_end=1
  else
    script_dir="$(dirname "$script")"
    if [ -n "$(find "$script_dir" "$REPO_ROOT/tests/reports/standalone" -maxdepth 1 \
                \( -name '*.json' -o -name '*.log' \) -newer "$marker" -print -quit 2>/dev/null)" ]; then
      ran_to_end=1
    else
      reason="既无 stdout 也无新鲜产物"
    fi
  fi

  rm -f "$log" "$marker" 2>/dev/null || true

  if [ "$rc" -eq 0 ] && [ "$ran_to_end" -eq 1 ]; then
    echo "  ✓ $rel"
    passed=$((passed + 1))
  else
    if [ "$rc" -ne 0 ]; then
      echo "  ✗ $rel（exit=$rc）"
      failed_names="$failed_names $rel"
    else
      echo "  ✗ $rel（假绿：exit=0 但${reason}——脚本很可能中途静默终止，一条断言都没跑）"
      failed_names="$failed_names $rel(假绿)"
    fi
    failed=$((failed + 1))
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
