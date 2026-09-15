#Requires -Version 5.1
<#
.SYNOPSIS
    DoD 四闸门本地一键校验（Windows / PowerShell）。

.DESCRIPTION
    闸门① 图谱基线：无新增环、无白名单外依赖违规
    闸门② fmt + clippy：零告警
    闸门③ 测试：cargo test / AHK 套件 / JS 单测，且 test-map.md 已登记
    闸门④ 文档同步：输出人工核对清单（无法完全自动化）

.EXAMPLE
    .\scripts\check-gates.ps1            # 全量
    .\scripts\check-gates.ps1 -Quick     # 只跑 ①②（秒级，适合改代码时频繁跑）
    .\scripts\check-gates.ps1 -SkipAhk   # 跳过 AHK 套件
#>
[CmdletBinding()]
param(
    [switch]$Quick,
    [switch]$SkipGraph,
    [switch]$SkipCargo,
    [switch]$SkipAhk,
    [switch]$SkipJs,
    [string]$AhkExe = 'D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tauriDir = Join-Path $repoRoot 'asd-tauri'
$results = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------- 预检
# 本会话常缺 cargo / python（终端 PATH 被重置时很常见），与其让每个闸门抛出
# “无法将 xxx 项识别为 cmdlet...” 的晦涩异常，不如一次说清并提前退出。
$script:Py = $null
foreach ($candidate in @('python', 'python3', 'py')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $script:Py = $candidate; break }
}
$missing = @()
if (-not $script:Py) { $missing += 'python' }
foreach ($tool in @('cargo', 'node', 'git')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $missing += $tool }
}
if ($missing.Count -gt 0) {
    Write-Output ('=' * 62)
    Write-Output '  预检失败：以下工具不在当前 PATH'
    Write-Output ('=' * 62)
    foreach ($m in $missing) { Write-Output "  - $m" }
    Write-Output ''
    Write-Output '  提示：会话 PATH 可能与系统终端不同。请在可见上述工具的终端中运行，'
    Write-Output '        或先把工具目录加入 PATH 再执行本脚本。'
    exit 2
}

function Invoke-Gate {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$WorkDir = $repoRoot
    )
    Write-Output ''
    Write-Output ('=' * 62)
    Write-Output "  $Id  $Name"
    Write-Output ('=' * 62)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $prev = Get-Location
    try {
        Set-Location $WorkDir
        $code = & $Action
    }
    catch {
        Write-Output "  EXCEPTION: $($_.Exception.Message)"
        $code = 1
    }
    finally {
        Set-Location $prev
    }
    $sw.Stop()
    if ($null -eq $code) { $code = 0 }
    $status = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
    $color = if ($code -eq 0) { 'Green' } else { 'Red' }
    Write-Output "  -> $status ($([int]$sw.Elapsed.TotalSeconds)s)"
    [void]$results.Add([pscustomobject]@{
            Gate   = $Id
            Name   = $Name
            Status = $status
            Secs   = [int]$sw.Elapsed.TotalSeconds
        })
    # 结果已记入 $results；此处刻意不 return，避免调用方用赋值/管道吞掉诊断输出
}

# ---------------------------------------------------------------- 闸门①
if (-not $SkipGraph) {
    Invoke-Gate -Id 'G1' -Name '图谱基线（无新增环 / 无白名单外违规）' -Action {
        & $script:Py (Join-Path $repoRoot 'scripts/check-graph-baseline.py')
        $LASTEXITCODE
    }
}

# ---------------------------------------------------------------- 闸门②
if (-not $SkipCargo) {
    Invoke-Gate -Id 'G2a' -Name 'cargo fmt --all --check' -WorkDir $tauriDir -Action {
        cargo fmt --all --check
        $LASTEXITCODE
    }

    Invoke-Gate -Id 'G2b' -Name 'cargo clippy --workspace --all-targets -- -D warnings' -WorkDir $tauriDir -Action {
        cargo clippy --workspace --all-targets -- -D warnings
        $LASTEXITCODE
    }
}

if (-not $Quick) {
    # ------------------------------------------------------------ 闸门③
    if (-not $SkipCargo) {
        Invoke-Gate -Id 'G3a' -Name 'cargo test --workspace' -WorkDir $tauriDir -Action {
            cargo test --workspace
            $LASTEXITCODE
        }
    }

    if (-not $SkipAhk) {
        Invoke-Gate -Id 'G3b' -Name 'AHK 完整测试套件 (tests/run_all_tests.ahk)' -Action {
            if (-not (Test-Path $AhkExe)) {
                Write-Output "  未找到 AutoHotkey v2：$AhkExe"
                Write-Output '  请用 -AhkExe 指定路径，或 choco install autohotkey'
                return 1
            }
            $log = Join-Path $env:TEMP "asd_ahk_gate_$PID.log"
            & $AhkExe (Join-Path $repoRoot 'tests/run_all_tests.ahk') *> $log
            $text = if (Test-Path $log) { Get-Content $log -Raw -Encoding UTF8 } else { '' }
            # 汇总既可能在 stdout，也可能只写进 tests/test_results.log（runner 行为），两边都兜。
            $resultLog = Join-Path $repoRoot 'tests/test_results.log'
            if ($text -notmatch '总计:' -and (Test-Path $resultLog)) {
                $text = Get-Content $resultLog -Raw -Encoding UTF8
            }
            $m = [regex]::Match($text, '总计:\s*(\d+).*?通过:\s*(\d+).*?失败:\s*(\d+)', 'Singleline')
            if (-not $m.Success) {
                Write-Output '  无法解析 AHK 结果汇总（未找到 总计/通过/失败）'
                Get-Content $log -Tail 20 -ErrorAction SilentlyContinue
                return 1
            }
            $total = [int]$m.Groups[1].Value
            $pass = [int]$m.Groups[2].Value
            $fail = [int]$m.Groups[3].Value
            Write-Output "  AHK: 总计 $total / 通过 $pass / 失败 $fail"
            Remove-Item $log -Force -ErrorAction SilentlyContinue
            if ($fail -gt 0) { return 1 }
            return 0
        }
    }

    if (-not $SkipJs) {
        Invoke-Gate -Id 'G3c' -Name 'JS 单元测试 (node --test)' -WorkDir (Join-Path $repoRoot 'asd-tauri/e2e/helpers/__tests__') -Action {
            # 不能写 `node --test <目录>`：会被 node 当成 CJS 模块去 require，
            # 报 Cannot find module。改为传具体文件名。
            $files = @(Get-ChildItem -Filter *.test.js | Select-Object -ExpandProperty Name)
            if ($files.Count -eq 0) {
                Write-Output '  未找到任何 *.test.js'
                return 1
            }
            node --test @files
            $LASTEXITCODE
        }
    }

    Invoke-Gate -Id 'G3d' -Name 'test-map.md 登记自洽（--no-cargo 快速档）' -Action {
        & $script:Py (Join-Path $repoRoot 'scripts/check-test-map.py') --no-cargo
        $LASTEXITCODE
    }

    # 静态检查，约 2.5s。C1a/C1b/C1c/C2/C3b 走棘轮（只阻新增），C3 恒 0 硬阻断。
    Invoke-Gate -Id 'G3e' -Name '技术债度量（C1 孤儿 / C2 未接入 / C3 文档漂移 / C3b 硬写数字）' -Action {
        & $script:Py (Join-Path $repoRoot 'scripts/check-tech-debt.py')
        $LASTEXITCODE
    }
}

# ---------------------------------------------------------------- 闸门④
Write-Output ''
Write-Output ('=' * 62)
Write-Output '  G4  文档同步（人工核对清单）'
Write-Output ('=' * 62)
Write-Output '  [ ] AGENTS.md 架构/分层/妥协白名单是否同步'
Write-Output '  [ ] asd-tauri/docs/test-map.md 测试数是否更新（G3d 已校验数字自洽）'
Write-Output '  [ ] docs/developer-guide.md 命令与排障是否同步'
Write-Output '  [ ] docs/graph-driven-workflow.md 流程是否同步'
Write-Output '  [ ] 新增 crate / 跨 crate 依赖是否同步 ALLOWED_CRATE_DEPS'
Write-Output '  [ ] 清理了技术债后是否 --update-baseline 收紧水位（基线 diff 须出现在本 CR）'
Write-Output '  -> 提示：G4 无法完全自动化，请人工确认后打勾'
[void]$results.Add([pscustomobject]@{ Gate = 'G4'; Name = '文档同步'; Status = 'MANUAL'; Secs = 0 })

# ---------------------------------------------------------------- 汇总
Write-Output ''
Write-Output ('=' * 62)
Write-Output '  四闸门汇总'
Write-Output ('=' * 62)
Write-Output ($results | Format-Table -AutoSize | Out-String)

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
if ($failed.Count -eq 0) {
    Write-Output 'ALL GATES PASSED (G4 需人工确认)'
    exit 0
}
Write-Output "FAILED GATES: $($failed.Gate -join ', ')"
exit 1
