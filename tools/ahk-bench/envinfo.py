#!/usr/bin/env python3
"""采集基准测试环境信息（OS / CPU / 内存 / QPC 频率 / AHK 版本）。

用法：
    python tools/ahk-bench/envinfo.py

存在的意义：基准报告必须能被人复核。「在一台什么机器上跑的」是最基本的
一项，而 AHK 侧没有 JVM 那种 `-version` 一把梭，QPC 频率还会影响所有
微秒级结论，所以单独落成脚本，避免每次手敲。

⚠️ 只依赖标准库 + ctypes，不需要 pip 安装任何东西。
"""
import ctypes
import ctypes.wintypes as wt
import os
import platform
import subprocess
import sys

AHK_EXE = r"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"


def cpu_name() -> str:
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"HARDWARE\DESCRIPTION\System\CentralProcessor\0",
        )
        return winreg.QueryValueEx(key, "ProcessorNameString")[0].strip()
    except Exception as exc:  # 非 Windows 或权限不足
        return "unknown (%s)" % exc


def cpu_cores() -> int:
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"HARDWARE\DESCRIPTION\System\CentralProcessor",
        )
        n = 0
        while True:
            try:
                winreg.EnumKey(key, n)
                n += 1
            except OSError:
                break
        return n
    except Exception:
        return os.cpu_count() or 0


class MEMORYSTATUSEX(ctypes.Structure):
    _fields_ = [
        ("dwLength", wt.DWORD),
        ("dwMemoryLoad", wt.DWORD),
        ("ullTotalPhys", ctypes.c_ulonglong),
        ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong),
        ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong),
        ("ullAvailVirtual", ctypes.c_ulonglong),
        ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


def ram_gb() -> float:
    st = MEMORYSTATUSEX()
    st.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(st))
    return st.ullTotalPhys / (1024 ** 3)


def qpc_freq() -> int:
    freq = ctypes.c_longlong()
    ctypes.windll.kernel32.QueryPerformanceFrequency(ctypes.byref(freq))
    return freq.value


def ahk_version() -> str:
    """AutoHotkey64.exe 没有 /version 开关（实测无输出），
    只能跑一个极小脚本把 A_AhkVersion 写进文件再读回来。

    ⚠️ GUI 子系统进程的 stdout 抓不到，所以必须落文件（本项目踩过：
       重定向到管道恒为 0 字节）。
    """
    import tempfile
    tmp = tempfile.gettempdir()
    script = os.path.join(tmp, "_ahkver_probe.ahk")
    out = os.path.join(tmp, "_ahkver_probe.txt")
    try:
        with open(script, "w", encoding="utf-8") as f:
            f.write('FileAppend(A_AhkVersion, "%s", "UTF-8")\n'
                    % out.replace("\\", "\\\\"))
        if os.path.exists(out):
            os.remove(out)
        subprocess.run([AHK_EXE, script], timeout=30,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(out, encoding="utf-8") as f:
            return f.read().strip()
    except Exception as exc:
        return "unknown (%s)" % exc
    finally:
        for p in (script, out):
            try:
                os.remove(p)
            except OSError:
                pass


def main() -> int:
    print("OS            :", platform.system(), platform.release(), platform.version())
    print("Build         :", platform.win32_ver())
    print("CPU           :", cpu_name())
    print("Logical cores :", cpu_cores())
    print("RAM (GB)      : %.1f" % ram_gb())
    print("QPC freq (Hz) :", qpc_freq())
    print("Python        :", platform.python_version())
    print("AHK           :", ahk_version())
    return 0


if __name__ == "__main__":
    sys.exit(main())
