#!/usr/bin/env bash
# DoD 四闸门本地一键校验（Git Bash / Linux）。与 check-gates.ps1 等价。
#
#   ./scripts/check-gates.sh            # 全量
#   ./scripts/check-gates.sh --quick    # 只跑 ①②
#   ./scripts/check-gates.sh --skip-ahk
#
# 环境变量：
#   AHK_EXE  AutoHotkey v2 可执行文件路径（默认 /d/Program Files/AutoHotkey/v2/AutoHotkey64.exe）
#   PY       python 可执行文件名（默认 python）

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAURI_DIR="$REPO_ROOT/asd-tauri"

# Git Bash 下 $REPO_ROOT 是 MSYS 路径（/d/...），原生 Windows 程序（python.exe 等）
# 不认，会被拼成 D:\d\... 而报 No such file。故另备一份原生路径用于传参。
REPO_ROOT_NATIVE="$REPO_ROOT"
if command -v cygpath >/dev/null 2>&1; then
  REPO_ROOT_NATIVE="$(cygpath -w "$REPO_ROOT")"
fi
AHK_EXE="${AHK_EXE:-/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe}"
PY="${PY:-python}"

QUICK=0; SKIP_GRAPH=0; SKIP_CARGO=0; SKIP_AHK=0; SKIP_JS=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --skip-graph) SKIP_GRAPH=1 ;;
    --skip-cargo) SKIP_CARGO=1 ;;
    --skip-ahk) SKIP_AHK=1 ;;
    --skip-js) SKIP_JS=1 ;;
    *) echo "未知参数: $arg"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- 预检
# 与其让每个闸门抛出 "command not found"，不如一次说清并提前退出。
MISSING=""
for tool in cargo node git; do
  command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"
done
if ! command -v "$PY" >/dev/null 2>&1; then
  MISSING="$MISSING python(可用 PY 环境变量指定)"
fi
if [ -n "$MISSING" ]; then
  echo "=============================================================="
  echo "  预检失败：以下工具不在当前 PATH:"
  echo "   $MISSING"
  echo "  提示：请先安装，或用 PY / AHK_EXE 等环境变量指定路径。"
  echo "=============================================================="
  exit 2
fi

FAILED=()
run_gate() {
  local id="$1" name="$2" workdir="$3"; shift 3
  echo
  echo "=============================================================="
  echo "  $id  $name"
  echo "=============================================================="
  local start=$(date +%s)
  ( cd "$workdir" && "$@" )
  local code=$?
  local end=$(date +%s)
  if [ $code -eq 0 ]; then
    echo "  -> PASS ($((end - start))s)"
  else
    echo "  -> FAIL ($((end - start))s)"
    FAILED+=("$id")
  fi
}

# ---------------------------------------------------------------- 闸门①
if [ "$SKIP_GRAPH" -eq 0 ]; then
  run_gate "G1" "图谱基线（无新增环 / 无白名单外违规）" "$REPO_ROOT" \
    "$PY" "$REPO_ROOT_NATIVE/scripts/check-graph-baseline.py"
fi

# ---------------------------------------------------------------- 闸门②
if [ "$SKIP_CARGO" -eq 0 ]; then
  run_gate "G2a" "cargo fmt --all --check" "$TAURI_DIR" cargo fmt --all --check
  # ⚠️ CARGO_INCREMENTAL=0 是必需的：增量编译缓存会让 clippy 在本机稳定 ICE
  #    （rustc 1.95.0，退出码 101，与代码无关）。用 env 前缀而不是 export，
  #    以免污染后续闸门。
  run_gate "G2b" "cargo clippy --workspace --all-targets -- -D warnings" "$TAURI_DIR" \
    env CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets -- -D warnings
fi

if [ "$QUICK" -eq 0 ]; then
  # -------------------------------------------------------------- 闸门③
  if [ "$SKIP_CARGO" -eq 0 ]; then
    run_gate "G3a" "cargo test --workspace" "$TAURI_DIR" \
      env CARGO_INCREMENTAL=0 cargo test --workspace
  fi

  if [ "$SKIP_AHK" -eq 0 ]; then
    echo
    echo "=============================================================="
    echo "  G3b  AHK 完整测试套件 (tests/run_all_tests.ahk)"
    echo "=============================================================="
    if [ ! -f "$AHK_EXE" ]; then
      echo "  未找到 AutoHotkey v2：$AHK_EXE"
      echo "  请用 AHK_EXE 环境变量指定路径"
      FAILED+=("G3b")
    else
      AHK_LOG="$(mktemp)"
      ( cd "$REPO_ROOT" && "$AHK_EXE" "$REPO_ROOT_NATIVE/tests/run_all_tests.ahk" ) >"$AHK_LOG" 2>&1
      # 汇总既可能在 stdout，也可能只写进 tests/test_results.log（runner 行为），两边都兜。
      RESULT_LOG="$REPO_ROOT/tests/test_results.log"
      SRC="$AHK_LOG"
      if [ -f "$RESULT_LOG" ] && grep -q '总计:' "$RESULT_LOG"; then
        SRC="$RESULT_LOG"
      fi
      summary=$(grep -E '^(总计|通过|失败):' "$SRC" | tr '\n' ' ')
      fail=$(grep -E '^失败:' "$SRC" | grep -oE '[0-9]+' | head -1)
      if [ -z "$fail" ]; then
        echo "  无法解析 AHK 结果汇总（未找到 总计/通过/失败）"
        tail -20 "$SRC"
        FAILED+=("G3b")
      else
        echo "  AHK: $summary"
        [ "${fail:-0}" -eq 0 ] || FAILED+=("G3b")
      fi
      rm -f "$AHK_LOG" 2>/dev/null || true
    fi
  fi

  if [ "$SKIP_JS" -eq 0 ]; then
    # 不能写 `node --test <目录>`：该形式会被 node 当成 CJS 模块去 require，
    # 报 Cannot find module。改为进目录后传通配文件名（shell 在 cd 之后才展开）。
    run_gate "G3c" "JS 单元测试 (node --test)" \
      "$REPO_ROOT/asd-tauri/e2e/helpers/__tests__" \
      node --test *.test.js
  fi

  run_gate "G3d" "test-map.md 登记自洽（--no-cargo 快速档）" "$REPO_ROOT" \
    "$PY" "$REPO_ROOT_NATIVE/scripts/check-test-map.py" --no-cargo

  # 静态检查，约 2.5s。C1a/C1b/C1c/C2/C3b 走棘轮（只阻新增），C3 恒 0 硬阻断。
  run_gate "G3e" "技术债度量（C1 孤儿 / C2 未接入 / C3 文档漂移 / C3b 硬写数字）" "$REPO_ROOT" \
    "$PY" "$REPO_ROOT_NATIVE/scripts/check-tech-debt.py"

  # tests/ 下的独立脚本（不在 run_all_tests.ahk 的套件注册里）。2026-09-16 首次
  # 接入执行即连挖三个生产 BUG（TD-034/035/036）—— 这些断言以前是一次都没跑过的。
  # 编号取 G3g 而不是 G3f —— G3f 已经是覆盖率棘轮（跑在 CI 的 coverage job，见 developer-guide §4.6.1）
  run_gate "G3g" "AHK 独立脚本（不在 run_all_tests 注册里的 8 个，逐个按退出码汇总）" "$REPO_ROOT" \
    bash "$REPO_ROOT_NATIVE/scripts/run-standalone-ahk-tests.sh"
fi

# ---------------------------------------------------------------- 闸门④
echo
echo "=============================================================="
echo "  G4  文档同步（人工核对清单）"
echo "=============================================================="
cat <<'CHECKLIST'
  [ ] AGENTS.md 架构/分层/妥协白名单是否同步
  [ ] asd-tauri/docs/test-map.md 测试数是否更新（G3d 已校验数字自洽）
  [ ] docs/developer-guide.md 命令与排障是否同步
  [ ] docs/graph-driven-workflow.md 流程是否同步
  [ ] 新增 crate / 跨 crate 依赖是否同步 ALLOWED_CRATE_DEPS
  [ ] 清理了技术债后是否 --update-baseline 收紧水位（基线 diff 须出现在本 CR）
  -> 提示：G4 无法完全自动化，请人工确认后打勾
CHECKLIST

# ---------------------------------------------------------------- 汇总
echo
echo "=============================================================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "ALL GATES PASSED (G4 需人工确认)"
  exit 0
fi
echo "FAILED GATES: ${FAILED[*]}"
exit 1
