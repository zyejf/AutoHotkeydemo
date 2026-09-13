#Requires -Version 5.1
<#
.SYNOPSIS
    将 scripts/hooks/ 安装为 git 钩子目录（core.hooksPath）。

.DESCRIPTION
    为什么需要：.git/hooks 不进版本库，换机器/新克隆后钩子全部失效。

.EXAMPLE
    .\scripts\install-hooks.ps1
    .\scripts\install-hooks.ps1 -Remove   # 取消，恢复使用 .git/hooks
#>
[CmdletBinding()]
param([switch]$Remove)

$repoRoot = Split-Path -Parent $PSScriptRoot
$hooksDir = Join-Path $repoRoot 'scripts/hooks'

if ($Remove) {
    git -C $repoRoot config --unset core.hooksPath 2>$null
    Write-Output '已取消 core.hooksPath，恢复使用 .git/hooks'
    exit 0
}

# 必须用绝对路径：相对 core.hooksPath 由 git 按「当前工作目录」解析，
# 在子目录里执行 git commit 会找不到钩子。
git -C $repoRoot config core.hooksPath $hooksDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output '已安装 git 钩子:'
Write-Output "  core.hooksPath = $(git -C $repoRoot config core.hooksPath)"
Get-ChildItem $hooksDir -File | ForEach-Object { Write-Output "  - $($_.Name)" }
Write-Output ''
Write-Output '提示: 设置环境变量 ASD_FULL_GATES=1 可让 pre-commit 额外跑快速闸门（较慢）。'
