@echo off
REM =================================================================
REM Test runner for DDD architecture v3.0
REM =================================================================
setlocal enabledelayedexpansion

set AHK=C:\Program Files\AutoHotkey\v2\AutoHotkey.exe
set TEST_DIR=%~dp0
set REPORT_DIR=%TEST_DIR%reports

if not exist "%AHK%" (
    echo [FATAL] AutoHotkey not found: %AHK%
    exit /b 2
)

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"

set PASS_COUNT=0
set FAIL_COUNT=0
set FILE_PASS=0
set FILE_FAIL=0

echo ============================================
echo   Skill Manager v3.0 - Test Suite
echo ============================================
echo.

set TEST_FILES=test_domain test_infrastructure test_application test_presentation test_boundary

for %%f in (%TEST_FILES%) do (
    echo [RUN ] %%f.ahk
    "%AHK%" "%TEST_DIR%%%f.ahk" > "%REPORT_DIR%\%%f_output.txt" 2>&1
    
    if !ERRORLEVEL! EQU 0 (
        echo [PASS] %%f.ahk
        set /a FILE_PASS+=1
        findstr /C:"PASS" "%REPORT_DIR%\%%f_output.txt" > nul
    ) else (
        echo [FAIL] %%f.ahk ^(ExitCode=!ERRORLEVEL!^)
        set /a FILE_FAIL+=1
    )
    echo.
)

echo ============================================
echo   Test Summary
echo ============================================
echo Passed: %FILE_PASS% files
echo Failed: %FILE_FAIL% files
echo.

if %FILE_FAIL% GTR 0 (
    echo [WARNING] Some tests failed. Check tests\reports\ for output.
    exit /b 1
)

echo [SUCCESS] All tests passed.
exit /b 0
