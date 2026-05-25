@echo off
set AHK_EXE=d:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe
set SCRIPT_FILE=%1
set LOG_FILE=%~dp1error_output.log

if "%SCRIPT_FILE%"=="" (
    echo Usage: run_ahk_silent.bat "script.ahk"
    exit /b 1
)

"%AHK_EXE%" /ErrorStdOut="%LOG_FILE%" "%SCRIPT_FILE%" 2>&1

if exist "%LOG_FILE%" (
    echo Error logged to: %LOG_FILE%
    type "%LOG_FILE%"
) else (
    echo Script executed successfully
)

exit /b 0
