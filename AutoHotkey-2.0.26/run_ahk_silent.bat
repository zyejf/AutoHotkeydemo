@echo off
REM =================================================================
REM AutoHotkey 无弹窗启动器
REM 用于捕获所有错误（包括加载时错误）并输出到日志
REM =================================================================

setlocal enabledelayedexpansion

set AHK_EXE=d:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe
set SCRIPT_FILE=%1
set LOG_FILE=%~dp1error_output.log

if "%SCRIPT_FILE%"=="" (
    echo 用法: run_ahk_silent.bat "脚本路径.ahk"
    exit /b 1
)

if not exist "%SCRIPT_FILE%" (
    echo 错误: 脚本文件不存在
    exit /b 1
)

REM 运行脚本，将所有错误输出到日志文件
"%AHK_EXE%" /ErrorStdOut="%LOG_FILE%" "%SCRIPT_FILE%" 2>&1

REM 检查是否有错误输出
if exist "%LOG_FILE%" (
    echo 错误已记录到: %LOG_FILE%
    type "%LOG_FILE%"
) else (
    echo 脚本执行完成，无错误
)

exit /b 0
