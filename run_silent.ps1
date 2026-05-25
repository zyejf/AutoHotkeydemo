#Requires -Version 5.1
<#
.SYNOPSIS
    AutoHotkey v2 无弹窗启动器 - 捕获加载时错误
.DESCRIPTION
    使用 /ErrorStdOut 参数启动 AutoHotkey 脚本，捕获 stderr 输出并记录到日志文件
.PARAMETER ScriptPath
    要启动的 AutoHotkey 脚本路径（默认: asd.ahk）
.EXAMPLE
    .\run_silent.ps1
    启动默认脚本 asd.ahk
.EXAMPLE
    .\run_silent.ps1 -ScriptPath "test.ahk"
    启动指定脚本 test.ahk
#>

param(
    [string]$ScriptPath = "asd.ahk"
)

$ErrorActionPreference = "Stop"
$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$logDir = Join-Path $PSScriptRoot "logs"
$logFile = Join-Path $logDir "errors.log"

function Write-ColorMessage {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Initialize-LogDirectory {
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Write-ColorMessage "[INFO] 创建日志目录: $logDir" "Cyan"
        } catch {
            Write-ColorMessage "[ERROR] 无法创建日志目录: $_" "Red"
            exit 1
        }
    }
}

function Test-AutoHotkeyExists {
    if (-not (Test-Path $ahkPath)) {
        Write-ColorMessage "[ERROR] AutoHotkey v2 未找到: $ahkPath" "Red"
        Write-ColorMessage "[提示] 请从 https://www.autohotkey.com/ 下载安装 AutoHotkey v2" "Yellow"
        exit 1
    }
}

function Test-ScriptExists {
    param([string]$Path)
    
    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path $PSScriptRoot $Path
    }
    
    if (-not (Test-Path $fullPath)) {
        Write-ColorMessage "[ERROR] 脚本文件未找到: $fullPath" "Red"
        exit 1
    }
    
    return $fullPath
}

function Write-ErrorLog {
    param(
        [string]$Message,
        [string]$File = "",
        [int]$Line = 0
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"
    
    $logEntry = @{
        timestamp = $timestamp
        level = "ERROR"
        type = "LoadTimeError"
        message = $Message
        file = $File
        line = $Line
    } | ConvertTo-Json -Compress
    
    try {
        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
        Write-ColorMessage "[ERROR] 错误已记录到: $logFile" "Red"
    } catch {
        Write-ColorMessage "[ERROR] 无法写入日志文件: $_" "Red"
    }
}

function Start-AutoHotkeyScript {
    param([string]$ScriptFullPath)
    
    Write-ColorMessage "`n========================================" "Cyan"
    Write-ColorMessage "  AutoHotkey v2 无弹窗启动器" "Cyan"
    Write-ColorMessage "========================================`n" "Cyan"
    
    Write-ColorMessage "[INFO] 启动脚本: $ScriptFullPath" "White"
    Write-ColorMessage "[INFO] AutoHotkey: $ahkPath" "White"
    Write-ColorMessage "[INFO] 日志文件: $logFile`n" "White"
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ahkPath
    $psi.Arguments = "/ErrorStdOut `"$ScriptFullPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = $PSScriptRoot
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    
    $errorOutput = New-Object System.Text.StringBuilder
    $outputReceived = $false
    
    $outputAction = {
        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
            $outputReceived = $true
            $null = $errorOutput.AppendLine($EventArgs.Data)
        }
    }
    
    $stdOutAction = {
        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
            Write-Host $EventArgs.Data
        }
    }
    
    Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $outputAction | Out-Null
    Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $stdOutAction | Out-Null
    
    try {
        $null = $process.Start()
        $process.BeginErrorReadLine()
        $process.BeginOutputReadLine()
        $process.WaitForExit()
        
        Start-Sleep -Milliseconds 100
        
        $errorText = $errorOutput.ToString().Trim()
        
        if ($outputReceived -and $errorText.Length -gt 0) {
            Write-ColorMessage "`n[ERROR] 检测到加载时错误!" "Red"
            Write-ColorMessage "----------------------------------------" "Yellow"
            
            $errorLines = $errorText -split "`r`n|`n"
            $fileMatch = ""
            $lineMatch = 0
            
            foreach ($line in $errorLines) {
                if ($line -match "\.ahk") {
                    Write-ColorMessage "  $line" "Yellow"
                    
                    if ($line -match ":\d+:") {
                        $fileMatch = ($line -split ":")[0]
                        $lineMatch = [int]($line -split ":")[1]
                    }
                } else {
                    Write-ColorMessage "  $line" "Red"
                }
            }
            
            Write-ColorMessage "----------------------------------------`n" "Yellow"
            
            Write-ErrorLog -Message $errorText -File $fileMatch -Line $lineMatch
            
            Write-ColorMessage "`n[提示] 请修复上述错误后重新启动脚本" "Cyan"
            exit 1
        } else {
            Write-ColorMessage "[SUCCESS] 脚本启动成功，无加载时错误`n" "Green"
            exit 0
        }
        
    } catch {
        Write-ColorMessage "[ERROR] 启动失败: $_" "Red"
        Write-ErrorLog -Message $_.Exception.Message
        exit 1
    } finally {
        $process.Dispose()
    }
}

Initialize-LogDirectory
Test-AutoHotkeyExists
$scriptFullPath = Test-ScriptExists -Path $ScriptPath
Start-AutoHotkeyScript -ScriptFullPath $scriptFullPath
