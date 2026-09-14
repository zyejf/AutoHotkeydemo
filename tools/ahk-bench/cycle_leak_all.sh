#!/usr/bin/env bash
# =================================================================
# cycle_leak_all.sh —— 逐个用例独立进程跑完循环引用泄漏基准
#
# 为什么必须独立跑：同一进程内连续跑多个用例时，AHK 自身的分配会让基线
# 持续漂移（实测 3216→4696KB），残留量甚至算出负值。故每个用例一个进程，
# 用追加写拼到同一份 CSV。
#
# 用法：
#   bash tools/ahk-bench/cycle_leak_all.sh
# =================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${TEMP:-/tmp}/ahkbench"
# ⚠️ 必须转成 POSIX 路径：`rm` / `[ -e ]` 作用在 `C:\...` 这种混用分隔符的字符串上
# 行为不可靠（实测 rm 不报错但文件仍在）。统一用 cygpath -u 之后再操作。
OUTDIR_U="$(cygpath -u "$OUTDIR" 2>/dev/null || echo "$OUTDIR")"
CSV="$OUTDIR_U/cycle_leak.csv"

# 清空上一轮：先删，删不掉就截断，仍失败则直接退出。
# 不清空的后果很隐蔽 —— 两轮数据会追加在同一份 CSV 里，
# 报告第 3 章（取首个匹配）和第 4 章（取末个匹配）会给出两组对不上的数字。
rm -f "$CSV" 2>/dev/null
if [ -e "$CSV" ]; then : > "$CSV" 2>/dev/null; fi
if [ -e "$CSV" ]; then
    echo "无法清空 $CSV —— 退出，避免两轮数据混在一起"
    exit 1
fi

for c in ctrl_cycle ctrl_plain obj_cycle obj_plain closure_cycle closure_plain; do
    printf '  %-16s ' "$c"
    BENCH_CASE="$c" bash "$HERE/run.sh" cycle_leak 300 >/dev/null 2>&1
    if grep -q "N=50000.*retained_kb" "$CSV" 2>/dev/null; then
        tail -1 "$CSV"
    else
        echo "FAILED（看 $CSV 末尾有无 FATAL 行）"
    fi
done

n=$(grep -c '^cycle,' "$CSV" 2>/dev/null || echo 0)
echo "完成：$CSV（$n 行用例数据，应为 6）"
