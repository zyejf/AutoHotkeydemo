# build_ahk.ps1 - Build AHK subprocess for ASD-Tauri
# Compiles executor.ahk to standalone exe, or falls back to portable mode
#
# NOTE: Ahk2Exe v1.1.37+ has a known bug where /bin parameter paths containing
# spaces (e.g. "D:\Program Files\...") cause error 0x34 (Base file not found).
# Workaround: copy the base file to a temporary path without spaces before
# compilation, then clean up afterwards.
$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Use env var if set, otherwise use default path
$ahkCompiler = if ($env:AHK_COMPILER) { $env:AHK_COMPILER } else { "D:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" }
$ahkBin = if ($env:AHK_BIN) { $env:AHK_BIN } else { "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" }
$inputFile = Join-Path $projectDir "ahk_executor\executor.ahk"
$outputFile = Join-Path $projectDir "ahk_executor\asd_executor.exe"
$portableExe = Join-Path $projectDir "ahk_executor\AutoHotkey64.exe"
# Temporary base file path without spaces (workaround for Ahk2Exe bug)
$ahkBinTemp = Join-Path $projectDir "ahk_executor\_AutoHotkey64.exe"

Write-Host "=== Building AHK Subprocess ===" -ForegroundColor Cyan

# Auto-detect: if default path doesn't exist, try candidate paths
if (-not (Test-Path $ahkBin)) {
    $candidates = @(
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ahkBin = $c; break }
    }
}
if (-not (Test-Path $ahkCompiler)) {
    $candidates = @(
        "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe",
        "D:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ahkCompiler = $c; break }
    }
}

# Verify AHK runtime exists
if (-not (Test-Path $ahkBin)) {
    Write-Host "ERROR: AutoHotkey64.exe not found: $ahkBin" -ForegroundColor Red
    Write-Host "Hint: Set AHK_BIN environment variable to the correct path" -ForegroundColor Yellow
    exit 1
}

# Verify entry file exists
if (-not (Test-Path $inputFile)) {
    Write-Host "ERROR: executor.ahk not found: $inputFile" -ForegroundColor Red
    exit 1
}

# Syntax check
Write-Host "Syntax checking executor.ahk..." -ForegroundColor Yellow
$checkResult = & $ahkBin /ErrorStdOut $inputFile 2>&1
if ($LASTEXITCODE -eq 2) {
    Write-Host "ERROR: Syntax check failed:" -ForegroundColor Red
    Write-Host $checkResult
    exit 2
}
Write-Host "Syntax check passed" -ForegroundColor Green

# Check mpress.exe availability (/compress 1 requires mpress)
$mpressPath = Join-Path (Split-Path $ahkCompiler) "mpress.exe"
$compressLevel = "1"
if (-not (Test-Path $mpressPath)) {
    Write-Host "WARNING: mpress.exe not found at $mpressPath, using /compress 0" -ForegroundColor Yellow
    Write-Host "  (install mpress.exe to enable compression, or keep /compress 0)" -ForegroundColor Yellow
    $compressLevel = "0"
}

# Try compilation if Ahk2Exe is available
$compiled = $false
if (Test-Path $ahkCompiler) {
    Write-Host "Compiling asd_executor.exe (compress=$compressLevel)..." -ForegroundColor Yellow
    try {
        # Remove old output to detect fresh compilation
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

        # Workaround: Ahk2Exe cannot handle /bin paths with spaces.
        # Use hardlink to a space-free path.
        # NOTE: Copy-Item triggers Ahk2Exe "Base file appears to be invalid" warning popup
        # (silent flag does not suppress it). Hardlink preserves original file bytes/signature.
        Remove-Item $ahkBinTemp -Force -ErrorAction SilentlyContinue
        New-Item -ItemType HardLink -Path $ahkBinTemp -Target $ahkBin | Out-Null

        # Ahk2Exe is a GUI app - use WaitForExit with timeout to prevent hang on error popup
        # /compress 1 requires mpress.exe; if missing, Ahk2Exe shows a MessageBox and hangs
        $proc = Start-Process -FilePath $ahkCompiler `
            -ArgumentList "/silent","/in","$inputFile","/out","$outputFile","/bin","$ahkBinTemp","/compress","$compressLevel" `
            -PassThru -NoNewWindow

        # Wait up to 30 seconds (prevent permanent hang on error popup)
        if (-not $proc.WaitForExit(30000)) {
            Write-Host "WARNING: Ahk2Exe hung (likely error popup), killing process" -ForegroundColor Yellow
            $proc | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }

        # Clean up temporary base file
        Remove-Item $ahkBinTemp -Force -ErrorAction SilentlyContinue

        Start-Sleep -Milliseconds 500

        if (Test-Path $outputFile) {
            $size = (Get-Item $outputFile).Length / 1MB
            Write-Host "Compilation success: asd_executor.exe ($([math]::Round($size, 2)) MB)" -ForegroundColor Green
            $compiled = $true
        } else {
            Write-Host "WARNING: Ahk2Exe did not produce output (exit code: $($proc.ExitCode))" -ForegroundColor Yellow
            Write-Host "Falling back to portable mode..." -ForegroundColor Yellow
        }
    } catch {
        # Clean up temporary base file on error
        Remove-Item $ahkBinTemp -Force -ErrorAction SilentlyContinue
        Write-Host "WARNING: Ahk2Exe compilation failed: $_" -ForegroundColor Yellow
        Write-Host "Falling back to portable mode..." -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: Ahk2Exe not found at $ahkCompiler" -ForegroundColor Yellow
    Write-Host "Falling back to portable mode..." -ForegroundColor Yellow
}

# Portable mode: copy AutoHotkey64.exe alongside .ahk files
# The Rust side will launch: AutoHotkey64.exe executor.ahk
if (-not $compiled) {
    Write-Host "Setting up portable mode..." -ForegroundColor Yellow

    # 关键：便携模式**必须**先清掉旧的编译产物（TD-046）。
    #
    # `resolve_ahk_executor_path`（src/lib.rs）优先用 `ahk_executor/asd_executor.exe`；
    # 只要它存在，Rust 就**永远不会**走这里刚准备好的便携模式。于是「编译失败 →
    # 退回便携模式」在残留旧 exe 时是一个**谎言**：构建脚本报告成功，运行时用的
    # 还是那份旧 exe。
    #
    # 2026-09-17 实测：本地那份 exe 编译于 2026-06-29，而 executor.ahk 等已改到
    # 9/11~9/15；E2E 因此跑出一个旧了 2.5 个月的执行器，产出 12 条假的 HIGH 已知问题。
    if (Test-Path $outputFile) {
        Write-Host "移除残留的旧编译产物: $outputFile" -ForegroundColor Yellow
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $outputFile) {
        Write-Host "ERROR: 无法移除旧的 $outputFile" -ForegroundColor Red
        Write-Host "Rust 侧会优先用它（resolve_ahk_executor_path），本次便携模式不会生效，" -ForegroundColor Red
        Write-Host "运行时仍会用旧执行器 —— 结果不可信。请手动删除该文件后重试。" -ForegroundColor Red
        exit 3
    }
    Copy-Item $ahkBin $portableExe -Force
    $size = (Get-Item $portableExe).Length / 1MB
    Write-Host "Portable mode ready: AutoHotkey64.exe ($([math]::Round($size, 2)) MB)" -ForegroundColor Green

    # Create a launcher batch that Rust can call
    $launcherPath = Join-Path $projectDir "ahk_executor\asd_executor.bat"
    Set-Content -Path $launcherPath -Value "@echo off`n`"%~dp0AutoHotkey64.exe`" `"%~dp0executor.ahk`" %*" -Encoding ASCII
    Write-Host "Created launcher: asd_executor.bat" -ForegroundColor Green
}

Write-Host "=== AHK Subprocess Build Complete ===" -ForegroundColor Cyan
