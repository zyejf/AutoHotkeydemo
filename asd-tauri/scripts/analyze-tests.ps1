#requires -Version 5.1
<#
    .SYNOPSIS
        分析 JUnit XML 测试结果，输出通过率、失败清单、耗时 Top10、按 crate 分组统计。

    .DESCRIPTION
        解析 test-results/ 目录下的 JUnit XML 文件，支持多文件合并统计。
        若目录不存在或为空，输出友好提示并退出。

    .PARAMETER ResultsDir
        测试结果目录路径，默认为脚本所在目录上级的 test-results/。

    .EXAMPLE
        .\scripts\analyze-tests.ps1
        .\scripts\analyze-tests.ps1 -ResultsDir D:\path\to\results

    .NOTES
        退出码：
          0 = 全部通过
          1 = 有失败
          2 = 无测试结果
#>
param(
    [string]$ResultsDir
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

if (-not $ResultsDir) {
    $ResultsDir = Join-Path $rootDir "test-results"
}

# ----------------------------------------------------------------------
# 检查结果目录
# ----------------------------------------------------------------------
if (-not (Test-Path $ResultsDir -PathType Container)) {
    Write-Host "测试结果目录不存在: $ResultsDir" -ForegroundColor Yellow
    Write-Host "请先运行: .\scripts\run-tests.ps1 -JUnit" -ForegroundColor Yellow
    exit 2
}

$xmlFiles = @(Get-ChildItem -Path $ResultsDir -Filter "*.xml" -File -ErrorAction SilentlyContinue)
if ($xmlFiles.Count -eq 0) {
    Write-Host "测试结果目录中没有 JUnit XML 文件: $ResultsDir" -ForegroundColor Yellow
    Write-Host "请先运行: .\scripts\run-tests.ps1 -JUnit" -ForegroundColor Yellow
    exit 2
}

# ----------------------------------------------------------------------
# 解析所有 XML 文件
# ----------------------------------------------------------------------
$allTestCases = New-Object System.Collections.ArrayList
$parseErrors = 0

foreach ($xmlFile in $xmlFiles) {
    $crateName = [System.IO.Path]::GetFileNameWithoutExtension($xmlFile.Name)

    try {
        $rawContent = Get-Content -Path $xmlFile.FullName -Raw -Encoding UTF8
        [xml]$doc = $rawContent
    } catch {
        Write-Warning "无法解析 XML 文件: $($xmlFile.Name) - $($_.Exception.Message)"
        $parseErrors++
        continue
    }

    # 兼容 <testsuites> 和 <testsuite> 根节点
    $suites = @()
    if ($null -ne $doc.testsuites) {
        $suites = @($doc.testsuites.testsuite)
    } elseif ($null -ne $doc.testsuite) {
        $suites = @($doc.testsuite)
    }

    foreach ($suite in $suites) {
        $suiteName = $suite.name
        if (-not $suiteName) { $suiteName = $crateName }

        $cases = @($suite.testcase)
        foreach ($case in $cases) {
            $timeVal = 0.0
            $timeStr = $case.time
            if ($timeStr) {
                try {
                    $timeVal = [double]::Parse($timeStr, [System.Globalization.CultureInfo]::InvariantCulture)
                } catch {
                    $timeVal = 0.0
                }
            }

            $status = "passed"
            $failureMsg = $null

            if ($case.failure) {
                $status = "failed"
                $failureMsg = $case.failure.message
                if (-not $failureMsg) { $failureMsg = $case.failure.InnerText }
            } elseif ($case.error) {
                $status = "failed"
                $failureMsg = $case.error.message
                if (-not $failureMsg) { $failureMsg = $case.error.InnerText }
            }

            if ($case.skipped) {
                $status = "ignored"
            }

            # 截断过长的失败信息并清理换行
            if ($failureMsg) {
                $failureMsg = $failureMsg.Trim()
                $failureMsg = $failureMsg -replace "`r`n", " " -replace "`n", " " -replace "`r", " "
                if ($failureMsg.Length -gt 200) {
                    $failureMsg = $failureMsg.Substring(0, 200) + "..."
                }
            }

            [void]$allTestCases.Add([PSCustomObject]@{
                Crate     = $crateName
                Suite     = $suiteName
                ClassName = $case.classname
                Name      = $case.name
                Time      = $timeVal
                Status    = $status
                Failure   = $failureMsg
            })
        }
    }
}

if ($allTestCases.Count -eq 0) {
    Write-Host "未解析到任何测试用例。" -ForegroundColor Yellow
    if ($parseErrors -gt 0) {
        Write-Host "有 $parseErrors 个 XML 文件解析失败。" -ForegroundColor Yellow
    }
    exit 2
}

# ----------------------------------------------------------------------
# 统计
# ----------------------------------------------------------------------
$total = $allTestCases.Count
$passed = @($allTestCases | Where-Object { $_.Status -eq "passed" }).Count
$failed = @($allTestCases | Where-Object { $_.Status -eq "failed" }).Count
$ignored = @($allTestCases | Where-Object { $_.Status -eq "ignored" }).Count

if ($total -gt 0) {
    $passRate = [math]::Round(($passed / $total) * 100, 2)
} else {
    $passRate = 0.0
}

# ----------------------------------------------------------------------
# 1. 总通过率
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "========== 测试结果汇总 ==========" -ForegroundColor Cyan
$summaryColor = if ($failed -eq 0) { "Green" } else { "Red" }
Write-Host ("总计: {0} | 通过: {1} | 失败: {2} | 忽略: {3}" -f $total, $passed, $failed, $ignored) -ForegroundColor $summaryColor
Write-Host ("通过率: {0}%" -f $passRate) -ForegroundColor $summaryColor

# ----------------------------------------------------------------------
# 2. 失败清单
# ----------------------------------------------------------------------
if ($failed -gt 0) {
    Write-Host ""
    Write-Host "========== 失败清单 ==========" -ForegroundColor Red
    $failedCases = @($allTestCases | Where-Object { $_.Status -eq "failed" })
    foreach ($fc in $failedCases) {
        Write-Host ("[{0}] {1} :: {2}" -f $fc.Crate, $fc.ClassName, $fc.Name) -ForegroundColor Red
        if ($fc.Failure) {
            Write-Host ("  原因: {0}" -f $fc.Failure) -ForegroundColor DarkRed
        }
    }
}

# ----------------------------------------------------------------------
# 3. 耗时 Top10
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "========== 耗时 Top 10 ==========" -ForegroundColor Cyan
$top10 = @($allTestCases | Sort-Object -Property Time -Descending | Select-Object -First 10)
$top10Rows = foreach ($t in $top10) {
    [PSCustomObject]@{
        Crate    = $t.Crate
        TestName = ("{0}::{1}" -f $t.ClassName, $t.Name)
        Time_Sec = [math]::Round($t.Time, 4)
    }
}
$top10Rows | Format-Table -AutoSize

# ----------------------------------------------------------------------
# 4. 按 crate 分组统计
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "========== 按 Crate 分组统计 ==========" -ForegroundColor Cyan
$groupedRows = $allTestCases | Group-Object -Property Crate | ForEach-Object {
    $groupTotal = $_.Count
    $groupPassed = @($_.Group | Where-Object { $_.Status -eq "passed" }).Count
    $groupFailed = @($_.Group | Where-Object { $_.Status -eq "failed" }).Count
    $groupIgnored = @($_.Group | Where-Object { $_.Status -eq "ignored" }).Count
    $groupDuration = [math]::Round(($_.Group | Measure-Object -Property Time -Sum).Sum, 4)

    [PSCustomObject]@{
        Crate      = $_.Name
        Total      = $groupTotal
        Passed     = $groupPassed
        Failed     = $groupFailed
        Ignored    = $groupIgnored
        Duration_S = $groupDuration
    }
}
$groupedRows | Format-Table -AutoSize

# ----------------------------------------------------------------------
# 退出码
# ----------------------------------------------------------------------
if ($parseErrors -gt 0) {
    Write-Host ""
    Write-Host "警告: 有 $parseErrors 个 XML 文件解析失败。" -ForegroundColor Yellow
}

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "有 $failed 个测试失败。" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "所有测试通过。" -ForegroundColor Green
    exit 0
}
