# AutoHotkey 无弹窗启动器
# 用于捕获所有错误（包括加载时和运行时错误）

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [string]$AHKPath = "d:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe"
)

$ErrorActionPreference = "Stop"

# 检查脚本文件是否存在
if (-not (Test-Path $ScriptPath)) {
    Write-Host "Error: Script file not found: $ScriptPath" -ForegroundColor Red
    exit 1
}

# 检查 AutoHotkey 是否存在
if (-not (Test-Path $AHKPath)) {
    Write-Host "Error: AutoHotkey not found: $AHKPath" -ForegroundColor Red
    exit 1
}

# 设置日志文件路径
$ScriptDir = Split-Path $ScriptPath -Parent
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
$LoadTimeErrorLog = Join-Path $ScriptDir "logs\$ScriptName`_loadtime_error.log"
$RuntimeErrorLog = Join-Path $ScriptDir "logs\$ScriptName`_runtime_error.log"

# 确保日志目录存在
$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Host "Running script: $ScriptPath" -ForegroundColor Cyan
Write-Host "Error logs will be saved to: $LogDir" -ForegroundColor Gray

# 运行脚本，捕获加载时错误
try {
    $process = Start-Process -FilePath $AHKPath `
        -ArgumentList "/ErrorStdOut", $ScriptPath `
        -RedirectStandardError $LoadTimeErrorLog `
        -RedirectStandardOutput (Join-Path $LogDir "$ScriptName`_output.log") `
        -Wait -NoNewWindow -PassThru
    
    # 检查加载时错误
    if (Test-Path $LoadTimeErrorLog) {
        $loadError = Get-Content $LoadTimeErrorLog -Raw
        if ($loadError -and $loadError.Trim() -ne "") {
            Write-Host "`n========================================" -ForegroundColor Red
            Write-Host "Load-time Error Detected!" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host $loadError -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "Error logged to: $LoadTimeErrorLog" -ForegroundColor Gray
            exit 1
        } else {
            Remove-Item $LoadTimeErrorLog -Force
        }
    }
    
    # 检查运行时错误日志
    if (Test-Path $RuntimeErrorLog) {
        $runtimeError = Get-Content $RuntimeErrorLog -Raw
        if ($runtimeError -and $runtimeError.Trim() -ne "") {
            Write-Host "`n========================================" -ForegroundColor Yellow
            Write-Host "Runtime Errors Detected!" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "Error logged to: $RuntimeErrorLog" -ForegroundColor Gray
        }
    }
    
    # 检查退出代码
    if ($process.ExitCode -eq 0) {
        Write-Host "`nScript executed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nScript exited with code: $($process.ExitCode)" -ForegroundColor Yellow
    }
    
    exit $process.ExitCode
    
} catch {
    Write-Host "Error running script: $_" -ForegroundColor Red
    exit 1
}
