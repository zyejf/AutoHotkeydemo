"""TD-030 阳性对照：对 JSONSerializer 做变异，验证新增测试能抓住回归。

只做临时改写 + 还原，不提交。用法：python tools/_pc_scalar.py
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "infrastructure" / "json_serializer.ahk"
# AHK 解释器：优先用环境变量 AHK_EXE（与 scripts/check-gates.sh 同一套约定），
# 缺省回落到常见安装路径。找不到就直接报错，不要静默跳过 —— 那会让阳性对照「假绿」。
AHK = os.environ.get("AHK_EXE") or r"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
LOG = ROOT / "tests" / "test_results.log"

orig = P.read_text(encoding="utf-8")
bak = Path(tempfile.gettempdir()) / "json_serializer.bak"
shutil.copy(P, bak)

MUTS = {
    "M1 恢复按值判布尔（旧实现）": (
        "} else if value is String {\n"
        "            return '\"' this._EscapeString(value) '\"'\n"
        "        } else if value is Integer || value is Float {",
        "} else if value is String {\n"
        "            return '\"' this._EscapeString(value) '\"'\n"
        "        } else if value = true || value = false {\n"
        '            return value ? "true" : "false"\n'
        "        } else if value is Integer || value is Float {",
    ),
    "M2 白名单去掉 allowOverlap": ('"allowOverlap", true,\n', ""),
    "M3 白名单清空": (
        'static BoolKeys := Map(\n        "success", true,\n        "error", true,\n'
        '        "ok", true,\n        "valid", true,\n        "active", true,\n'
        '        "allowOverlap", true,\n        "releaseOnEmergency", true,\n'
        '        "autoRepeat", true\n    )',
        "static BoolKeys := Map()",
    ),
    "M4 布尔分支永不生效": (
        "if this.BoolKeys.Has(key) && !IsObject(value) && !(value is String)",
        "if false && this.BoolKeys.Has(key)",
    ),
    "M5 布尔键分支不看对象保护（Map 值误判为 true）": (
        "if this.BoolKeys.Has(key) && !IsObject(value) && !(value is String)",
        "if this.BoolKeys.Has(key)",
    ),
}

def _restore(*_a):
    """被中断时也必须还原，否则生产文件会残留变异。"""
    shutil.copy(bak, P)


signal.signal(signal.SIGTERM, _restore)
signal.signal(signal.SIGINT, _restore)

only = sys.argv[1] if len(sys.argv) > 1 else None

try:
    for name, (a, b) in MUTS.items():
        if only and only not in name:
            continue
        assert a in orig, f"锚点未命中: {name}"
        P.write_text(orig.replace(a, b, 1), encoding="utf-8", newline="")
        subprocess.run([AHK, str(ROOT / "tests" / "run_all_tests.ahk")],
                       capture_output=True, timeout=300)
        log = LOG.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"^总计: (\d+) 个测试\s*\n通过: (\d+) 个\s*\n失败: (\d+) 个", log, re.M)
        failed = re.findall(r"^  - (Test_\w+):", log, re.M)
        total, passed, nfail = m.groups() if m else ("?", "?", "?")
        print(f"{name}: 总计={total} 通过={passed} 失败={nfail}")
        for f in failed[:8]:
            print("      ", f)
finally:
    shutil.copy(bak, P)
    print("已还原生产文件")
