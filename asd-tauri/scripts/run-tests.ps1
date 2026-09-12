#requires -Version 5.1
<#
    .SYNOPSIS
        ASD-Tauri 测试运行器，支持快速/完整模式、覆盖率、JUnit XML 报告与结果分析。

    .PARAMETER Quick
        快速模式：跳过 #[ignore] 标记的测试（watchdog 集成测试）。

    .PARAMETER Verbose
        显示完整测试输出（默认仅显示最后 20 行）。

    .PARAMETER Coverage
        测试完成后运行 cargo llvm-cov 生成 lcov.info + HTML 报告到 coverage/ 目录。

    .PARAMETER Analyze
        测试完成后调用 ./scripts/analyze-tests.ps1 分析测试结果（需配合 -JUnit 使用以解析 XML）。

    .PARAMETER JUnit
        使用 cargo +nightly --format junit 生成 JUnit XML 到 test-results/ 目录（每个 crate 一个文件）。
        若 nightly 不可用，回退到 cargo-junit-report。

    .EXAMPLE
        .\scripts\run-tests.ps1 -Quick
        .\scripts\run-tests.ps1 -Quick -JUnit -Analyze
        .\scripts\run-tests.ps1 -Coverage
#>
param(
    [switch]$Quick,
    [switch]$Verbose,
    [switch]$Coverage,
    [switch]$Analyze,
    [switch]$JUnit
)

$ErrorActionPreference = "Continue"
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $rootDir

$script:results = @()

# ----------------------------------------------------------------------
# 辅助函数
# ----------------------------------------------------------------------
function Test-NightlyJunitAvailable {
    <#
        检查 nightly 工具链是否可用（用于 --format junit）。
        一旦失败则缓存结果，避免重复探测。
    #>
    if ($script:nightlyJunitFailed) { return $false }
    if ($script:nightlyJunitChecked) { return $script:nightlyJunitAvailable }

    $script:nightlyJunitChecked = $true
    & rustup run nightly rustc --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $script:nightlyJunitAvailable = $false
        return $false
    }
    $script:nightlyJunitAvailable = $true
    return $true
}

function Test-Cargo2junitAvailable {
    $list = & cargo --list 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($list | Select-String -Pattern "cargo2junit" -Quiet)
}

function Install-Cargo2junit {
    Write-Host "正在安装 cargo2junit..." -ForegroundColor Cyan
    $output = & cargo install cargo2junit 2>&1
    $exitCode = $LASTEXITCODE
    if ($Verbose) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -ne 0) {
        Write-Host "安装 cargo2junit 失败 (exit code: $exitCode)。" -ForegroundColor Red
        return $false
    }
    # 退出码不可靠（cargo install 某些情况下返回 0 但实际未安装成功），
    # 通过验证命令是否可用双重确认
    if (-not (Test-Cargo2junitAvailable)) {
        Write-Host "安装 cargo2junit 后命令仍不可用。" -ForegroundColor Red
        return $false
    }
    return $true
}

function Merge-JUnitXmlDocuments {
    <#
        nightly --format junit 对每个测试二进制输出一个独立 XML 文档，
        当一个 crate 含 lib + 集成测试时会产出多个文档。
        本函数将多个 <testsuite> 合并到单个 <testsuites> 根节点下。
    #>
    param([string]$Content)

    if (-not $Content) { return $Content }

    $xmlDeclCount = ([regex]::Matches($Content, '<\?xml')).Count
    if ($xmlDeclCount -le 1) {
        return $Content
    }

    $suiteMatches = [regex]::Matches(
        $Content,
        '<testsuite\b[^>]*>.*?</testsuite>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($suiteMatches.Count -eq 0) {
        return $Content
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<?xml version=""1.0"" encoding=""UTF-8""?>`n<testsuites>`n")
    foreach ($m in $suiteMatches) {
        [void]$sb.Append($m.Value)
        [void]$sb.Append("`n")
    }
    [void]$sb.Append("</testsuites>")
    return $sb.ToString()
}

function Convert-CargoOutputToJUnitXml {
    <#
        将 cargo test 的标准文本输出解析为 JUnit XML。
        作为 nightly --format junit 和 cargo2junit 都不可用时的最终回退方案。
        解析格式：test <name> ... ok | FAILED | ignored
        注意：此方式无法获取单测耗时，time 统一为 0。
    #>
    param(
        [string]$Crate,
        [string[]]$Output
    )

    $testcases = New-Object System.Collections.ArrayList
    $passedCount = 0
    $failedCount = 0
    $ignoredCount = 0

    foreach ($line in $Output) {
        $lineText = if ($line -is [string]) { $line } else { $line.ToString() }
        # 匹配：test test_name ... ok / FAILED / ignored
        if ($lineText -match '^test\s+(\S+)\s+\.\.\.\s+(ok|FAILED|ignored)') {
            $testName = $matches[1]
            $status = $matches[2]

            # XML 转义测试名
            $escapedName = $testName -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'

            if ($status -eq "ignored") {
                $ignoredCount++
                [void]$testcases.Add("<testcase classname=""$Crate"" name=""$escapedName""><skipped/></testcase>")
            } elseif ($status -eq "FAILED") {
                $failedCount++
                [void]$testcases.Add("<testcase classname=""$Crate"" name=""$escapedName""><failure>test failed</failure></testcase>")
            } else {
                $passedCount++
                [void]$testcases.Add("<testcase classname=""$Crate"" name=""$escapedName"" />")
            }
        }
    }

    $totalCount = $testcases.Count

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<?xml version=""1.0"" encoding=""UTF-8""?>`n")
    [void]$sb.Append("<testsuites>`n")
    [void]$sb.Append("<testsuite name=""$Crate"" tests=""$totalCount"" failures=""$failedCount"" errors=""0"" skipped=""$ignoredCount"" time=""0"">`n")
    foreach ($case in $testcases) {
        [void]$sb.Append($case)
        [void]$sb.Append("`n")
    }
    [void]$sb.Append("</testsuite>`n")
    [void]$sb.Append("</testsuites>")
    return $sb.ToString()
}

function Invoke-TestSuite {
    param(
        [string]$Name,
        [string[]]$CargoArgs,
        [string[]]$HarnessArgs
    )

    Write-Host "`n========== Running $Name ==========" -ForegroundColor Cyan

    $allArgs = @($CargoArgs)
    if ($HarnessArgs.Count -gt 0) {
        $allArgs += @("--") + $HarnessArgs
    }

    $output = & cargo test @allArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($Verbose) {
        $output | ForEach-Object { Write-Host $_ }
    } else {
        $output | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
    }

    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($exitCode -eq 0) { "Green" } else { "Red" }

    Write-Host "[$status] $Name" -ForegroundColor $color

    $script:results += [PSCustomObject]@{
        Suite    = $Name
        Status   = $status
        ExitCode = $exitCode
    }

    return $exitCode -eq 0
}

function Invoke-TestSuiteWithJUnit {
    param(
        [string]$Name,
        [string[]]$CargoArgs,
        [string[]]$HarnessArgs,
        [string]$OutputFile
    )

    Write-Host "`n========== Running $Name (JUnit) ==========" -ForegroundColor Cyan

    $generated = $false

    # 路径 1：nightly + --format junit
    # 命令格式：cargo +nightly test {CargoArgs} -- --format junit -Z unstable-options -Z format-options {HarnessArgs}
    if (Test-NightlyJunitAvailable) {
        $junitHarnessArgs = @("--format", "junit", "-Z", "unstable-options", "-Z", "format-options") + $HarnessArgs
        $junitArgs = @("+nightly", "test") + $CargoArgs + @("--") + $junitHarnessArgs

        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()

        & cargo @junitArgs > $stdoutFile 2> $stderrFile
        $exitCode = $LASTEXITCODE

        # 显示 stderr（编译/测试进度信息）
        if ($Verbose) {
            Get-Content $stderrFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        } else {
            Get-Content $stderrFile -ErrorAction SilentlyContinue | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
        }

        $content = ""
        if (Test-Path $stdoutFile) {
            $content = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
        }
        Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

        if ($content -and ($content -match '<\?xml' -or $content -match '<testsuite')) {
            $mergedXml = Merge-JUnitXmlDocuments -Content $content
            try {
                [System.IO.File]::WriteAllText($OutputFile, $mergedXml, [System.Text.UTF8Encoding]::new($false))
                $generated = $true
                Write-Host "  JUnit XML 已生成: $OutputFile" -ForegroundColor DarkGray
            } catch {
                Write-Host "  写入 JUnit XML 失败: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  nightly junit 格式输出无效，回退到 cargo2junit..." -ForegroundColor Yellow
            $script:nightlyJunitFailed = $true
        }

        if ($generated) {
            $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
            $color = if ($exitCode -eq 0) { "Green" } else { "Red" }
            Write-Host "[$status] $Name" -ForegroundColor $color
            $script:results += [PSCustomObject]@{
                Suite    = $Name
                Status   = $status
                ExitCode = $exitCode
            }
            return $exitCode -eq 0
        }
    }

    # 路径 2：cargo2junit 回退（通过管道转换 cargo test 的 JSON 输出）
    $cargo2junitReady = $false
    if (Test-Cargo2junitAvailable) {
        $cargo2junitReady = $true
    } elseif (-not $script:cargo2junitInstallFailed) {
        Write-Host "  cargo2junit 未安装，尝试安装..." -ForegroundColor DarkGray
        $cargo2junitReady = Install-Cargo2junit
        if (-not $cargo2junitReady) {
            $script:cargo2junitInstallFailed = $true
        }
    }

    if ($cargo2junitReady) {
        # cargo2junit 工作方式：RUSTC_BOOTSTRAP=1 cargo test --format json | cargo2junit > results.xml
        # RUSTC_BOOTSTRAP=1 允许 stable 工具链使用 -Z unstable-options
        $jsonHarnessArgs = @("-Z", "unstable-options", "--format", "json", "--report-time") + $HarnessArgs
        $jsonArgs = @("test") + $CargoArgs + @("--") + $jsonHarnessArgs

        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()

        $prevBootstrap = $env:RUSTC_BOOTSTRAP
        $env:RUSTC_BOOTSTRAP = "1"
        try {
            & cargo @jsonArgs > $stdoutFile 2> $stderrFile
            $exitCode = $LASTEXITCODE
        } finally {
            if ($null -eq $prevBootstrap) {
                Remove-Item Env:RUSTC_BOOTSTRAP -ErrorAction SilentlyContinue
            } else {
                $env:RUSTC_BOOTSTRAP = $prevBootstrap
            }
        }

        # 显示 stderr（编译/测试进度信息）
        if ($Verbose) {
            Get-Content $stderrFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        } else {
            Get-Content $stderrFile -ErrorAction SilentlyContinue | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
        }

        # 通过 cargo2junit 转换 JSON 到 JUnit XML
        $jsonContent = ""
        if (Test-Path $stdoutFile) {
            $jsonContent = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
        }
        Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

        $converted = $false
        if ($jsonContent) {
            try {
                $jsonContent | & cargo2junit > $OutputFile 2>$null
                if ((Test-Path $OutputFile) -and (Get-Item $OutputFile).Length -gt 0) {
                    $converted = $true
                }
            } catch {
                Write-Host "  cargo2junit 转换失败: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if ($converted) {
            $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
            $color = if ($exitCode -eq 0) { "Green" } else { "Red" }
            Write-Host "[$status] $Name (cargo2junit)" -ForegroundColor $color
            Write-Host "  JUnit XML 已生成: $OutputFile" -ForegroundColor DarkGray
            $script:results += [PSCustomObject]@{
                Suite    = $Name
                Status   = $status
                ExitCode = $exitCode
            }
            return $exitCode -eq 0
        }

        Write-Host "  cargo2junit 转换未产出有效 XML，回退到 PowerShell 原生解析..." -ForegroundColor Yellow
    } else {
        Write-Host "  cargo2junit 不可用，使用 PowerShell 原生解析生成 JUnit XML..." -ForegroundColor Yellow
    }

    # 路径 3：PowerShell 原生解析（最终回退，不依赖外部工具）
    # 运行普通 cargo test，捕获文本输出，解析生成 JUnit XML
    $allArgs = @($CargoArgs)
    if ($HarnessArgs.Count -gt 0) {
        $allArgs += @("--") + $HarnessArgs
    }

    $testOutput = & cargo test @allArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($Verbose) {
        $testOutput | ForEach-Object { Write-Host $_ }
    } else {
        $testOutput | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
    }

    # 解析文本输出生成 JUnit XML
    $xmlContent = Convert-CargoOutputToJUnitXml -Crate $Name -Output $testOutput
    try {
        [System.IO.File]::WriteAllText($OutputFile, $xmlContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  JUnit XML 已生成 (PowerShell 原生解析): $OutputFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "  写入 JUnit XML 失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($exitCode -eq 0) { "Green" } else { "Red" }
    Write-Host "[$status] $Name (native parser)" -ForegroundColor $color

    $script:results += [PSCustomObject]@{
        Suite    = $Name
        Status   = $status
        ExitCode = $exitCode
    }
    return $exitCode -eq 0
}

function Invoke-CoverageReport {
    Write-Host "`n========== 生成覆盖率报告 ==========" -ForegroundColor Cyan

    $coverageDir = Join-Path $rootDir "coverage"
    if (-not (Test-Path $coverageDir)) {
        New-Item -Path $coverageDir -ItemType Directory -Force | Out-Null
    }

    $covArgs = @("llvm-cov", "--workspace", "--html", "--output-dir", $coverageDir)

    & cargo @covArgs 2>&1 | ForEach-Object {
        if ($Verbose) { Write-Host $_ }
    }
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $indexHtml = Join-Path $coverageDir "index.html"
        $lcovFile = Join-Path $coverageDir "lcov.info"
        Write-Host "覆盖率报告已生成: $coverageDir" -ForegroundColor Green
        if (Test-Path $lcovFile) {
            Write-Host "lcov.info: $lcovFile" -ForegroundColor Green
        }
        if (Test-Path $indexHtml) {
            Write-Host "HTML 报告: $indexHtml" -ForegroundColor Green
            try {
                Start-Process $indexHtml
            } catch {
                Write-Host "无法自动打开浏览器，请手动打开: $indexHtml" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "覆盖率报告生成失败 (exit code: $exitCode)。" -ForegroundColor Red
        Write-Host "请确保已安装 cargo-llvm-cov: cargo install cargo-llvm-cov" -ForegroundColor Yellow
    }

    return $exitCode -eq 0
}

function Invoke-AnalyzeTests {
    $analyzeScript = Join-Path $scriptDir "analyze-tests.ps1"
    if (-not (Test-Path $analyzeScript)) {
        Write-Host "analyze-tests.ps1 不存在: $analyzeScript" -ForegroundColor Yellow
        return
    }

    Write-Host "`n========== 运行测试结果分析 ==========" -ForegroundColor Cyan
    & $analyzeScript
    # 分析脚本的退出码不影响主流程退出码
}

# ----------------------------------------------------------------------
# 模式提示
# ----------------------------------------------------------------------
if (-not $Quick) {
    Write-Host "WARNING: Running in Full mode. This may take several minutes as it includes watchdog integration tests (#[ignore] tests)." -ForegroundColor Yellow
} else {
    Write-Host "Running in Quick mode. Skipping ignored tests (watchdog integration tests)." -ForegroundColor Green
}

Write-Host "Project root: $rootDir" -ForegroundColor DarkGray
if ($JUnit) {
    Write-Host "JUnit XML 报告: 已启用 (输出到 test-results/)" -ForegroundColor DarkGray
}
if ($Coverage) {
    Write-Host "覆盖率报告: 已启用 (输出到 coverage/)" -ForegroundColor DarkGray
}
if ($Analyze) {
    Write-Host "结果分析: 已启用 (测试后调用 analyze-tests.ps1)" -ForegroundColor DarkGray
}

# ----------------------------------------------------------------------
# 准备 test-results 目录
# ----------------------------------------------------------------------
$resultsDir = Join-Path $rootDir "test-results"
if ($JUnit) {
    if (Test-Path $resultsDir) {
        Remove-Item -Path $resultsDir -Recurse -Force
    }
    New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
}

# ----------------------------------------------------------------------
# 构建测试参数
# ----------------------------------------------------------------------
# Cargo 参数（cargo test 子命令参数，不含 --）
$domainCargo = @("-p", "asd-domain")
$ipcCargo    = @("-p", "asd-ipc-protocol")
$appCargo    = @("-p", "asd-application")
$tauriCargo  = @("-p", "asd-tauri", "--lib")

# 测试 harness 参数（-- 之后传给测试二进制）
# Full 模式包含 --include-ignored 以运行 #[ignore] 标记的 watchdog 集成测试
$harnessArgs = if (-not $Quick) { @("--include-ignored") } else { @() }

# ----------------------------------------------------------------------
# 运行测试套件（所有套件都执行，不因单个失败而短路）
# ----------------------------------------------------------------------
if ($JUnit) {
    $domainPass = Invoke-TestSuiteWithJUnit -Name "asd-domain"       -CargoArgs $domainCargo -HarnessArgs $harnessArgs -OutputFile (Join-Path $resultsDir "asd-domain.xml")
    $ipcPass    = Invoke-TestSuiteWithJUnit -Name "asd-ipc-protocol" -CargoArgs $ipcCargo    -HarnessArgs $harnessArgs -OutputFile (Join-Path $resultsDir "asd-ipc-protocol.xml")
    $appPass    = Invoke-TestSuiteWithJUnit -Name "asd-application"  -CargoArgs $appCargo    -HarnessArgs $harnessArgs -OutputFile (Join-Path $resultsDir "asd-application.xml")
    $tauriPass  = Invoke-TestSuiteWithJUnit -Name "asd-tauri"        -CargoArgs $tauriCargo  -HarnessArgs $harnessArgs -OutputFile (Join-Path $resultsDir "asd-tauri.xml")
} else {
    $domainPass = Invoke-TestSuite -Name "asd-domain"       -CargoArgs $domainCargo -HarnessArgs $harnessArgs
    $ipcPass    = Invoke-TestSuite -Name "asd-ipc-protocol" -CargoArgs $ipcCargo    -HarnessArgs $harnessArgs
    $appPass    = Invoke-TestSuite -Name "asd-application"  -CargoArgs $appCargo    -HarnessArgs $harnessArgs
    $tauriPass  = Invoke-TestSuite -Name "asd-tauri"        -CargoArgs $tauriCargo  -HarnessArgs $harnessArgs
}

$allPassed = $domainPass -and $ipcPass -and $appPass -and $tauriPass

# ----------------------------------------------------------------------
# 测试摘要
# ----------------------------------------------------------------------
Write-Host "`n========== Test Summary ==========" -ForegroundColor Cyan
$script:results | Format-Table -AutoSize

$totalPass = ($script:results | Where-Object { $_.Status -eq "PASS" }).Count
$totalFail = ($script:results | Where-Object { $_.Status -eq "FAIL" }).Count
$summaryColor = if ($totalFail -eq 0) { "Green" } else { "Red" }
Write-Host ""
Write-Host "Total: $($script:results.Count) | PASS: $totalPass | FAIL: $totalFail" -ForegroundColor $summaryColor

# ----------------------------------------------------------------------
# 覆盖率报告
# ----------------------------------------------------------------------
if ($Coverage) {
    Invoke-CoverageReport | Out-Null
}

# ----------------------------------------------------------------------
# 结果分析
# ----------------------------------------------------------------------
if ($Analyze) {
    Invoke-AnalyzeTests
}

# ----------------------------------------------------------------------
# 退出
# ----------------------------------------------------------------------
if ($allPassed) {
    Write-Host "`nAll test suites passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome test suites failed. See output above for details." -ForegroundColor Red
    exit 1
}
