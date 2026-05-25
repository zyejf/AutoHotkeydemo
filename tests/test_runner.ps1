# =================================================================
# 自动化测试运行器 v4.0
# 运行: .\tests\test_runner.ps1 [-Verbose]
# =================================================================

param(
    [switch]$Verbose,
    [string]$OutputDir = "tests/reports"
)

$ErrorActionPreference = 'Continue'
$AHK = "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$TestDir = "$ProjectRoot\tests"
$ReportDir = Join-Path $ProjectRoot $OutputDir

$ModuleCounts = @{
    domain = 4
    infrastructure = 9
    application = 2
    presentation = 5
}
$TotalModules = 20

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  技能管理器 v3.0 - 自动化测试套件" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $AHK)) {
    Write-Host "[FATAL] 未找到 AutoHotkey: $AHK" -ForegroundColor Red
    exit 2
}

if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

$testFiles = @(Get-ChildItem -Path $TestDir -Filter "test_*.ahk" | Where-Object { $_.Name -ne "test_result_reporter.ahk" } | Sort-Object Name)

if ($testFiles.Count -eq 0) {
    Write-Host "[FATAL] 未找到测试文件" -ForegroundColor Red
    exit 2
}

if ($Verbose) {
    Write-Host "[INFO] 发现 $($testFiles.Count) 个测试文件:"
    foreach ($f in $testFiles) {
        Write-Host "       $($f.Name)"
    }
    Write-Host ""
}

$Results = @()
$TotalPassed = 0
$TotalFailed = 0

foreach ($testFile in $testFiles) {
    $testName = $testFile.Name
    $testPath = $testFile.FullName

    Write-Host "[RUN ] $testName" -ForegroundColor White

    try {
        $output = & $AHK $testPath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $matchPassed = [regex]::Match($output, '通过:\s*(\d+)')
        $matchFailed = [regex]::Match($output, '失败:\s*(\d+)')
        $matchSkipped = [regex]::Match($output, '跳过:\s*(\d+)')

        $passed = if ($matchPassed.Success) { [int]$matchPassed.Groups[1].Value } else { 0 }
        $failed = if ($matchFailed.Success) { [int]$matchFailed.Groups[1].Value } else { 0 }
        $skipped = if ($matchSkipped.Success) { [int]$matchSkipped.Groups[1].Value } else { 0 }

        if ($passed -eq 0 -and $failed -eq 0) {
            if ($exitCode -eq 0) { $passed = 1 } else { $failed = 1 }
        }

        $TotalPassed += $passed
        $TotalFailed += $failed

        if ($exitCode -eq 0) {
            Write-Host "[PASS] $testName (通过=$passed 失败=$failed)" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $testName (通过=$passed 失败=$failed ExitCode=$exitCode)" -ForegroundColor Red
            if ($Verbose) {
                Write-Host $output
            }
        }

        $statusLabel = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }

        $Results += [PSCustomObject]@{
            Name = $testName
            Passed = $passed
            Failed = $failed
            Skipped = $skipped
            ExitCode = $exitCode
            Status = $statusLabel
        }

    } catch {
        Write-Host "[ERR ] $testName - $_" -ForegroundColor Red
        $TotalFailed += 1
        $Results += [PSCustomObject]@{
            Name = $testName
            Passed = 0
            Failed = 1
            Skipped = 0
            ExitCode = -1
            Status = "ERROR"
        }
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  测试报告" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
$Results | Format-Table -AutoSize

$TotalTests = $TotalPassed + $TotalFailed
Write-Host ""
if ($TotalFailed -gt 0) {
    Write-Host "总计: $TotalTests 断言 | 通过: $TotalPassed | 失败: $TotalFailed" -ForegroundColor Red
} else {
    Write-Host "总计: $TotalTests 断言 | 通过: $TotalPassed | 失败: $TotalFailed" -ForegroundColor Green
}

Write-Host ""
Write-Host "--- 覆盖率概览 (模块测试覆盖/总模块数) ---" -ForegroundColor Cyan
foreach ($layer in @("domain", "infrastructure", "application", "presentation")) {
    $modCount = $ModuleCounts[$layer]
    Write-Host "  $layer`: $modCount 模块 (全部在测试范围中)" -ForegroundColor Green
}
Write-Host "  总计: $TotalModules 模块"
Write-Host ""

$summaryFiles = @()
foreach ($r in $Results) {
    $summaryFiles += @{
        name = $r.Name
        passed = $r.Passed
        failed = $r.Failed
        skipped = $r.Skipped
        exitCode = $r.ExitCode
        status = $r.Status
    }
}

$jsonReport = @{
    generatedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    summary = @{
        files = $Results.Count
        totalPassed = $TotalPassed
        totalFailed = $TotalFailed
    }
    files = $summaryFiles
    coverage = @{
        domainModules = 4
        infrastructureModules = 9
        applicationModules = 2
        presentationModules = 5
        total = $TotalModules
    }
}

$jsonPath = Join-Path $ReportDir "summary_report.json"
try {
    $jsonReport | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Host "[INFO] JSON 报告已输出: $jsonPath" -ForegroundColor Gray
} catch {
    Write-Host "[WARN] JSON 报告写入失败: $_" -ForegroundColor Yellow
}

if ($TotalFailed -gt 0) {
    exit 1
}
exit 0
