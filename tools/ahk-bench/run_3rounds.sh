#!/usr/bin/env bash
# =================================================================
# run_3rounds.sh —— 三轮可复现基准（L1 纯生成 + L3 端到端）
#
# ⚠️ 踩过的坑：不要用 `rm` 清哨兵文件。本环境的 safe-delete 钩子会拦截 rm
#    （genie-trash 无法处理 /d/... 与 C:\... 混写的路径），导致 .done 没被删掉，
#    轮询立刻返回 0 秒，跑出来的是上一轮的陈旧 CSV —— r1/r3 全是假数据。
#    解决：**每轮用独立输出目录**，AHK 的 BenchInit 自己会 FileDelete，
#    从根上不存在陈旧哨兵。
# =================================================================
set -u

AHK="${AHK_EXE:-/d/Program Files/AutoHotkey/v2/AutoHotkey64.exe}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_OUT="$(cygpath -u "${TEMP:-/tmp}")/ahkbench"
ROUNDS="${1:-3}"

wait_done() {   # $1=dir  $2=id  $3=timeout_s
    local d="$1" id="$2" to="$3" w=0
    while [ ! -f "$d/${id}.done" ]; do
        sleep 1
        w=$((w + 1))
        if [ $w -ge "$to" ]; then
            echo "  [TIMEOUT ${to}s] ${id}"
            return 1
        fi
    done
    return 0
}

run_round() {   # $1=round
    local r="$1"
    local out="$BASE_OUT/r$r"
    mkdir -p "$out"
    export AHK_BENCH_OUT="$(cygpath -w "$out")"

    echo "--- round $r : L1 纯生成 ---"
    "$AHK" /ErrorStdOut=UTF-8 "$(cygpath -w "$HERE/bench_seqgen.ahk")" >/dev/null 2>&1 &
    if wait_done "$out" "seqgen" 600; then
        cp "$out/seqgen.csv" "$HERE/results/seqgen-r$r-2026-09-14.csv"
        echo "  seqgen OK"
    fi

    echo "--- round $r : L3 端到端 ---"
    "$AHK" /ErrorStdOut=UTF-8 "$(cygpath -w "$HERE/bench_schedule_e2e.ahk")" >/dev/null 2>&1 &
    if wait_done "$out" "schedule_e2e" 900; then
        cp "$out/schedule_e2e.csv" "$HERE/results/schedule_e2e-r$r-2026-09-14.csv"
        echo "  e2e OK"
    fi
}

i=1
while [ $i -le "$ROUNDS" ]; do
    run_round "$i"
    i=$((i + 1))
done
echo "ALLDONE"
