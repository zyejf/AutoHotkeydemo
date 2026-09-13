#!/usr/bin/env bash
# 将 scripts/hooks/ 安装为 git 钩子目录（core.hooksPath）。
#
#   ./scripts/install-hooks.sh          # 安装
#   ./scripts/install-hooks.sh --remove # 取消（恢复使用 .git/hooks）
#
# 为什么需要：.git/hooks 不进版本库，换机器/新克隆后钩子全部失效。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/scripts/hooks"

# 注意：不要用 `git -C "$REPO_ROOT"`。在 Git Bash 下 $REPO_ROOT 是 MSYS 路径
# （/d/...），原生 git 不认；改为先 cd 再执行 git。
cd "$REPO_ROOT"

if [ "${1:-}" = "--remove" ]; then
  git config --unset core.hooksPath || true
  echo "已取消 core.hooksPath，恢复使用 .git/hooks"
  exit 0
fi

chmod +x "$HOOKS_DIR"/* 2>/dev/null || true

# core.hooksPath 必须是 git 能识别的绝对路径（Windows 下为 D:/... 形式）。
# git 原生程序不认 MSYS 的 /d/... 路径，故用 git rev-parse 转换。
HOOKS_DIR_NATIVE="$HOOKS_DIR"
if command -v cygpath >/dev/null 2>&1; then
  HOOKS_DIR_NATIVE="$(cygpath -w "$HOOKS_DIR" | sed 's|\\|/|g')"
fi

git config core.hooksPath "$HOOKS_DIR_NATIVE"

echo "已安装 git 钩子:"
echo "  core.hooksPath = $(git config core.hooksPath)"
for h in "$HOOKS_DIR"/*; do
  echo "  - $(basename "$h")"
done
echo
echo "提示: 设置 ASD_FULL_GATES=1 可让 pre-commit 额外跑快速闸门（较慢）。"
