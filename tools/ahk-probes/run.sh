#!/usr/bin/env bash
# ============================================================================
# 探针运行器
#   用法：bash tools/ahk-probes/run.sh <probe-id> [timeout-sec]
#   例：  bash tools/ahk-probes/run.sh p0_version 120
#
# 为什么需要它：AutoHotkey64.exe 是 **GUI 子系统** 程序 ——
#   - cmd.exe 的 `start` / PowerShell 的 `&` 启动它 **不会等待** 进程结束；
#   - stdout 在部分父进程下会被吞掉。
# 因此探针一律把结果写到 %TEMP%\ahkprobe\<id>.csv，结束前写 <id>.done 哨兵，
# 本脚本靠哨兵判断结束（stdout 只作排错辅助，不参与取结果）。
#
# 注意：Git Bash 直接调用 exe 是会等待的（CreateProcess + WaitForSingleObject），
# 所以这里不需要 `cmd //c start /wait`；而且 Bash 里调用 cmd 会被安全策略拦截。
# ============================================================================
set -u

AHK="${AHK:-/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe}"
PROBE_ID="${1:-}"
TIMEOUT="${2:-300}"

if [ -z "$PROBE_ID" ]; then
  echo "用法: bash tools/ahk-probes/run.sh <probe-id> [timeout-sec]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/tools/ahk-probes/$PROBE_ID.ahk"

# AHK 侧写 %TEMP%\ahkprobe，这里换算到 POSIX 路径
WIN_TEMP="${TEMP:-}"
[ -n "$WIN_TEMP" ] || WIN_TEMP="${LOCALAPPDATA}\\Temp"
[ -n "$WIN_TEMP" ] || WIN_TEMP='C:\Windows\Temp'
OUTDIR="$(cygpath -u "$WIN_TEMP")/ahkprobe"
# 探针脚本必须传 Windows 路径：Git Bash 的 /d/xxx 会被 AHK 解析成 D:\d\xxx
SCRIPT_WIN="$(cygpath -w "$SCRIPT")"
CSV="$OUTDIR/$PROBE_ID.csv"
DONE="$OUTDIR/$PROBE_ID.done"

if [ ! -f "$SCRIPT" ]; then
  echo "找不到探针脚本: $SCRIPT" >&2
  exit 2
fi

rm -f "$CSV" "$DONE"
mkdir -p "$OUTDIR"

"$AHK" /ErrorStdOut=UTF-8 "$SCRIPT_WIN" &
RUNNER_PID=$!

i=0
while [ "$i" -lt "$TIMEOUT" ]; do
  if [ -f "$DONE" ]; then break; fi
  if ! kill -0 "$RUNNER_PID" 2>/dev/null; then
    sleep 2   # runner 已退出但没写 done —— 给写盘 2 秒宽限
    break
  fi
  sleep 1
  i=$((i + 1))
done

if [ -f "$DONE" ]; then
  echo "=== $PROBE_ID OK (wall=$(cat "$DONE")ms) ==="
else
  echo "=== $PROBE_ID TIMEOUT/NO-DONE after ${TIMEOUT}s ===" >&2
  kill "$RUNNER_PID" 2>/dev/null
fi

if [ -f "$CSV" ]; then
  cat "$CSV"
else
  echo "(无 CSV 输出: $CSV)" >&2
  exit 1
fi
