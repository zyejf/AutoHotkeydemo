# =================================================================
# AutoHotUnit Test Runner - PowerShell Wrapper
# Captures load-time and runtime errors
# =================================================================

param(
    [string]$TestFile = "run_all_tests.ahk",
    [string]$AHKPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
)

$ErrorActionPreference = "Continue"
$TestDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestFilePath = Join-Path $TestDir $TestFile
$ResultFile = Join-Path $TestDir "test_results.log"
$ErrorLogFile = Join-Path $TestDir "test_errors.log"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AutoHotUnit Test Runner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Clear error log
if (Test-Path $ErrorLogFile) {
    Remove-Item $ErrorLogFile -Force
}

# Run test and capture all output
Write-Host "Running tests..." -ForegroundColor Yellow
Write-Host "Test file: $TestFilePath" -ForegroundColor Gray
Write-Host ""

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $AHKPath
$processInfo.Arguments = "/ErrorStdOut `"$TestFilePath`""
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo
$process.Start() | Out-Null

# Capture output
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()

$exitCode = $process.ExitCode

# Check for errors
$hasErrors = $false
$errorMessages = @()

if ($stderr -ne "") {
    $hasErrors = $true
    $errorMessages += "STDERR: $stderr"
}

if ($stdout -ne "") {
    # Check if it's error output (AutoHotkey error format)
    if ($stdout -match "Error:|Exception:|This class declaration conflicts") {
        $hasErrors = $true
        $errorMessages += "STDOUT (Error): $stdout"
    }
}

if ($exitCode -ne 0) {
    $hasErrors = $true
    $errorMessages += "Exit Code: $exitCode (non-zero exit code)"
}

# Output result
if ($hasErrors) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Test execution failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "Error details:" -ForegroundColor Red
    foreach ($msg in $errorMessages) {
        Write-Host "  $msg" -ForegroundColor Red
    }
    
    # Write error log
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $errorContent = @"
========================================
Test Execution Error Report
Time: $timestamp
========================================

Error Type: Load-time Error / Runtime Error

Error Details:
$($errorMessages -join "`n")

Raw Output:
STDOUT:
$stdout

STDERR:
$stderr

Exit Code: $exitCode
"@
    
    $errorContent | Out-File -FilePath $ErrorLogFile -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "Error log saved to: $ErrorLogFile" -ForegroundColor Yellow
    
    exit 1
} else {
    # Check test result file
    if (Test-Path $ResultFile) {
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Test execution completed!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        # Display test results
        $results = Get-Content $ResultFile -Raw
        Write-Host $results
        
        # Check for failed tests
        if ($results -match "Failed: [1-9]") {
            Write-Host ""
            Write-Host "Some tests failed!" -ForegroundColor Yellow
            exit 1
        } else {
            Write-Host ""
            Write-Host "All tests passed!" -ForegroundColor Green
            exit 0
        }
    } else {
        Write-Host "Warning: Test result file not found" -ForegroundColor Yellow
        Write-Host "Exit Code: $exitCode" -ForegroundColor Gray
        exit 1
    }
}
