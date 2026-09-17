"""自查（本批次最大风险点）：**新增的反引号里不许含 CJK**。

与 `check_backticks_cjk.py` 的区别：那条规则会把「反引号包一个中文字符串字面量」
这类**正确**写法也报出来（`asd-application` 里有 16 处是这种正确写法，例如
`` `"无效的文件路径"` ``）。所以这里换成精确判据：

    只比对 HEAD 与工作区，只看**本次新加出来的**反引号对；
    新加的反引号对内部若含 CJK，就是 clippy 不认词边界造成的损坏。

用法: python tools/check_added_backticks_cjk.py [repo_root]
"""
import re
import subprocess
import sys
from pathlib import Path

CJK = re.compile(
    r"[\u2e80-\u303f\u3040-\u33ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\ufe30-\ufe4f\uff00-\uffef]"
)
PAIR = re.compile(r"`([^`\n]*)`")


def regions(line: str):
    return [(m.start(), m.end(), m.group(1)) for m in PAIR.finditer(line)]


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    diff = subprocess.run(
        ["git", "diff", "--name-only", "--", "*.rs"],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()

    hits = []
    changed_lines = 0
    new_regions = 0
    for rel in diff:
        old = subprocess.run(
            ["git", "show", f"HEAD:{rel}"], cwd=root, capture_output=True, text=True
        ).stdout.split("\n")
        new = (root / rel).read_text(encoding="utf-8").split("\n")
        if len(old) != len(new):
            # 行数变了就退回逐行配对（本批次只加反引号，行数不该变）
            print(f"  ⚠️ {rel}: 行数从 {len(old)} 变成 {len(new)}，请人工核对")
        for i, (o, n) in enumerate(zip(old, new), start=1):
            if o == n:
                continue
            changed_lines += 1
            old_set = {r[2] for r in regions(o)}
            for start, end, inner in regions(n):
                if inner in old_set:
                    continue
                new_regions += 1
                if CJK.search(inner):
                    hits.append((rel, i, n.strip()))

    print(f"改动文件 {len(diff)} 个 / 改动行 {changed_lines} 行 / 新增反引号对 {new_regions} 个")
    if hits:
        print(f"\n❌ {len(hits)} 处新增反引号里含 CJK（正是台账记的损坏模式）：")
        for rel, line, text in hits:
            print(f"  {rel}:{line}")
            print(f"      | {text}")
        return 1
    print("\n✅ 新增反引号对全部只含 ASCII，没有把中文包进去")
    return 0


if __name__ == "__main__":
    sys.exit(main())
