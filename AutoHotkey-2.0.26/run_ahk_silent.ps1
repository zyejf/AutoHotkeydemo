# AutoHotkey 无弹窗启动器 (PowerShell 版本)
# 用于捕获所有错误（包括加载时错误）并输出到日志

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath
)

$AHK_EXE = "d:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe"
$LogFile = Join-Path (Split-Path $ScriptPath -Parent) "error_output.log"

if (-not (Test-Path $ScriptPath)) {
    Write-Host "Error: Script file not found"
    exit 1
}

# 运行脚本，捕获所有输出
$process = Start-Process -FilePath $AHK_EXE -ArgumentList "/ErrorStdOut", $ScriptPath -RedirectStandardError $LogFile -RedirectStandardOutput (Join-Path (Split-Path $ScriptPath -Parent) "output.log") -Wait -NoNewWindow -PassThru

# 检查是否有错误输出
if (Test-Path $LogFile) {
    $errorContent = Get-Content $LogFile -Raw
    if ($errorContent.Trim() -ne "") {
        Write-Host "Error detected and logged to: $LogFile"
        Write-Host "`nError Details:"
        Write-Host $errorContent
    } else {
        Write-Host "Script executed successfully (no errors)"
        Remove-Item $LogFile
    }
} else {
    Write-Host "Script executed successfully"
}

exit $process.ExitCode
