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
    Copy-Item $ahkBin $portableExe -Force
    $size = (Get-Item $portableExe).Length / 1MB
    Write-Host "Portable mode ready: AutoHotkey64.exe ($([math]::Round($size, 2)) MB)" -ForegroundColor Green

    # Create a launcher batch that Rust can call
    $launcherPath = Join-Path $projectDir "ahk_executor\asd_executor.bat"
    Set-Content -Path $launcherPath -Value "@echo off`n`"%~dp0AutoHotkey64.exe`" `"%~dp0executor.ahk`" %*" -Encoding ASCII
    Write-Host "Created launcher: asd_executor.bat" -ForegroundColor Green
}

Write-Host "=== AHK Subprocess Build Complete ===" -ForegroundColor Cyan
