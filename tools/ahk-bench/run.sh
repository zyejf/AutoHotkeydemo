#!/usr/bin/env bash
# =================================================================
# run.sh —— AHK 重构基准运行器
#
# 用法：
#   bash tools/ahk-bench/run.sh            # 跑全部（除 _harness.ahk）
#   bash tools/ahk-bench/run.sh json_escape
#   bash tools/ahk-bench/run.sh cycle_leak 300   # 自定义超时秒数
#
# 结果 CSV：%TEMP%\ahkbench\<id>.csv
#
# 两个 Windows 陷阱（踩过，别改回去）：
#   1) AutoHotkey64.exe 是 GUI 子系统进程，直接调用不会等待 —— 所以后台拉起，
#      轮询 <id>.done 哨兵文件，而不是依赖退出码。
#   2) 脚本路径必须转成 Windows 形式（cygpath -w）：Git Bash 的 /d/xxx
#      会被 AHK 解析成 D:\d\xxx。
# =================================================================
set -u

AHK="${AHK_EXE:-/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 输出目录：必须显式传给 AHK（Windows 路径），否则两边对 %TEMP% 的理解可能不同
OUTDIR="${TEMP:-/tmp}/ahkbench"
mkdir -p "$OUTDIR" 2>/dev/null
AHK_BENCH_OUT="$(cygpath -w "$OUTDIR")"
export AHK_BENCH_OUT

if [ ! -f "$AHK" ]; then
    echo "未找到 AutoHotkey v2：$AHK"
    echo "请用 AHK_EXE 环境变量指定路径"
    exit 1
fi

run_one() {
    local id="$1"
    local timeout="${2:-180}"
    local script="$HERE/bench_${id}.ahk"

    if [ ! -f "$script" ]; then
        echo "  [SKIP] 无此基准：$script"
        return 1
    fi

    local script_win
    script_win="$(cygpath -w "$script")"
    rm -f "$OUTDIR/${id}.done" 2>/dev/null

    printf '  %-16s ' "$id"
    "$AHK" /ErrorStdOut=UTF-8 "$script_win" >/dev/null 2>&1 &

    local waited=0
    while [ ! -f "$OUTDIR/${id}.done" ]; do
        sleep 0.5
        waited=$((waited + 1))
        if [ $((waited / 2)) -ge "$timeout" ]; then
            echo "TIMEOUT (${timeout}s) —— 可能弹了模态错误框，看 CSV 末尾有无 FATAL 行"
            return 1
        fi
    done
    echo "OK  -> $OUTDIR/${id}.csv"
}

target="${1:-all}"
timeout="${2:-180}"

if [ "$target" = "all" ]; then
    echo "运行全部基准（超时 ${timeout}s/个）……"
    for f in "$HERE"/*.ahk; do
        base="$(basename "$f" .ahk)"
        base="${base#bench_}"          # 文件名是 bench_<id>.ahk，run_one 会再加前缀
        [ "$base" = "_harness" ] && continue
        run_one "$base" "$timeout"
    done
else
    run_one "$target" "$timeout"
fi

echo "完成。CSV 目录：$OUTDIR"
