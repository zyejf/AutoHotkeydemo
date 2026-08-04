# =================================================================
# Integration Test Verification Script
# Purpose: Verify test file structure and dependencies without AutoHotkey
# =================================================================

param(
    [string]$TestFile = "tests\test_integration_error_system.ahk"
)

$ErrorActionPreference = 'Continue'
$ProjectRoot = $PSScriptRoot | Split-Path -Parent
$TestPath = Join-Path $ProjectRoot $TestFile

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Integration Test Verification" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Verify test file exists
Write-Host "[CHECK] Test file existence" -ForegroundColor Yellow
if (Test-Path $TestPath) {
    Write-Host "  PASS Test file exists: $TestPath" -ForegroundColor Green
} else {
    Write-Host "  FAIL Test file not found: $TestPath" -ForegroundColor Red
    exit 1
}

# Verify test file content
Write-Host ""
Write-Host "[CHECK] Test file structure" -ForegroundColor Yellow
$content = Get-Content $TestPath -Raw -Encoding UTF8

$checks = @{
    "#Requires AutoHotkey v2.0" = "AutoHotkey v2.0 declaration"
    "TestReporter.BeginTest" = "Test framework initialization"
    "TestReporter.Scenario" = "Test scenario definition"
    "TestReporter.Assert" = "Assertion method call"
    "TestReporter.AssertThrows" = "Exception assertion call"
    "TestReporter.AssertNoThrow" = "No-exception assertion call"
    "TestReporter.Summarize" = "Test summary"
    "TestReporter.ExportReport" = "Report export"
    "ErrorSystem" = "Error system integration"
    "OnError" = "Error callback registration"
}

$passedChecks = 0
$failedChecks = 0

foreach ($check in $checks.GetEnumerator()) {
    if ($content -match [regex]::Escape($check.Key)) {
        Write-Host "  PASS $($check.Value)" -ForegroundColor Green
        $passedChecks++
    } else {
        Write-Host "  FAIL $($check.Value)" -ForegroundColor Red
        $failedChecks++
    }
}

# Count test scenarios
Write-Host ""
Write-Host "[CHECK] Test scenario count" -ForegroundColor Yellow
$scenarioMatches = [regex]::Matches($content, 'TestReporter\.Scenario\(')
$scenarioCount = $scenarioMatches.Count
Write-Host "  PASS Found $scenarioCount test scenarios" -ForegroundColor Green

# Count assertions
Write-Host ""
Write-Host "[CHECK] Assertion count" -ForegroundColor Yellow
$assertMatches = [regex]::Matches($content, 'TestReporter\.Assert')
$assertCount = $assertMatches.Count
Write-Host "  PASS Found $assertCount assertions" -ForegroundColor Green

# Verify dependency files
Write-Host ""
Write-Host "[CHECK] Dependency file existence" -ForegroundColor Yellow
$dependencies = @(
    "tests\test_result_reporter.ahk",
    "infrastructure\error_system.ahk",
    "domain\interfaces.ahk",
    "domain\mode_registry.ahk",
    "domain\skill_group.ahk",
    "domain\skill_manager.ahk",
    "application\group_service.ahk",
    "application\config_service.ahk",
    "presentation\ui_manager.ahk",
    "presentation\backup_ui.ahk",
    "presentation\group_editor.ahk"
)

$depExists = 0
$depMissing = 0

foreach ($dep in $dependencies) {
    $depPath = Join-Path $ProjectRoot $dep
    if (Test-Path $depPath) {
        Write-Host "  PASS $dep" -ForegroundColor Green
        $depExists++
    } else {
        Write-Host "  FAIL $dep" -ForegroundColor Red
        $depMissing++
    }
}

# Verify error system module
Write-Host ""
Write-Host "[CHECK] Error system module functionality" -ForegroundColor Yellow
$errorSystemPath = Join-Path $ProjectRoot "infrastructure\error_system.ahk"
if (Test-Path $errorSystemPath) {
    $errorSystemContent = Get-Content $errorSystemPath -Raw -Encoding UTF8

    $errorSystemChecks = @{
        "class ErrorSystem" = "ErrorSystem class definition"
        "HandleError" = "HandleError method"
        "LogError" = "LogError method"
        "LogWarning" = "LogWarning method"
        "LogInfo" = "LogInfo method"
        "GetErrorCount" = "GetErrorCount method"
        "_WriteLog" = "_WriteLog internal method"
        "_BuildErrorRecord" = "_BuildErrorRecord internal method"
    }

    foreach ($check in $errorSystemChecks.GetEnumerator()) {
        if ($errorSystemContent -match [regex]::Escape($check.Key)) {
            Write-Host "  PASS $($check.Value)" -ForegroundColor Green
        } else {
            Write-Host "  FAIL $($check.Value)" -ForegroundColor Red
        }
    }
}

# Generate verification report
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Verification Report" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test file: $TestFile" -ForegroundColor White
Write-Host "Structure checks: $passedChecks / $($checks.Count) passed" -ForegroundColor $(if ($passedChecks -eq $checks.Count) { "Green" } else { "Yellow" })
Write-Host "Test scenarios: $scenarioCount" -ForegroundColor Cyan
Write-Host "Assertions: $assertCount" -ForegroundColor Cyan
Write-Host "Dependency files: $depExists / $($dependencies.Count) exist" -ForegroundColor $(if ($depExists -eq $dependencies.Count) { "Green" } else { "Yellow" })
Write-Host ""

if ($failedChecks -eq 0 -and $depMissing -eq 0) {
    Write-Host "Status: PASS Test file verification successful" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Install AutoHotkey v2.0 (https://www.autohotkey.com/)" -ForegroundColor White
    Write-Host "  2. Run test: AutoHotkey.exe tests\test_integration_error_system.ahk" -ForegroundColor White
    Write-Host "  3. View report: tests\reports\test_report_*.json" -ForegroundColor White
    exit 0
} else {
    Write-Host "Status: FAIL Test file verification failed" -ForegroundColor Red
    Write-Host "  Structure check failures: $failedChecks" -ForegroundColor Yellow
    Write-Host "  Missing dependency files: $depMissing" -ForegroundColor Yellow
    exit 1
}
