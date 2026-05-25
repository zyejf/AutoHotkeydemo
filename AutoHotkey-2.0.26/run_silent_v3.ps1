param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath
)

$AHKPath = "d:\1demo\AutoHotkeydemo\AutoHotkey-2.0.26\AutoHotkey.exe"

if (-not (Test-Path $ScriptPath)) {
    Write-Host "Error: Script file not found" -ForegroundColor Red
    exit 1
}

$ScriptDir = Split-Path $ScriptPath -Parent
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
$ErrorLogFile = Join-Path $ScriptDir "logs\$ScriptName`_error.log"

$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Host "Running: $ScriptPath" -ForegroundColor Cyan

$process = Start-Process -FilePath $AHKPath -ArgumentList "/ErrorStdOut", $ScriptPath -RedirectStandardError $ErrorLogFile -Wait -NoNewWindow -PassThru

if (Test-Path $ErrorLogFile) {
    $errorContent = Get-Content $ErrorLogFile -Raw
    if ($errorContent -and $errorContent.Trim() -ne "") {
        Write-Host "`nError detected:" -ForegroundColor Red
        Write-Host $errorContent -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Script executed successfully" -ForegroundColor Green
exit 0
