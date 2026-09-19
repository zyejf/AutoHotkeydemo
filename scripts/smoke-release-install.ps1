#Requires -Version 5.1
<#
.SYNOPSIS
    发布产物冒烟测试：刚构建出来的 NSIS 安装包，装完之后到底能不能跑起来。

.DESCRIPTION
    全部判据取自「日志文件 + 注册表 + 进程表」三类**磁盘/系统证据**，
    不做 GUI 截图、不做像素判断、不做交互式点击。

    判据清单（任一条失败 => 非零退出）：
      C1 静默安装（NSIS /S）成功，且安装目录里出现主程序 exe
      C2 启动主程序后，进程表里能查到它，且 StartupWaitSec 内没有秒退
      C3a %APPDATA%\<identifier>\ 出现、生成了 asd.<YYYY-MM-DD>.log，
          且本次新增日志里有 logging.rs 的初始化成功串
      C3b 配置路径可达（首次启动被识别 / config.json 已存在）
      C4a 日志出现 AHK 子进程 spawn 记录
      C4b spawn 出来的 AHK 路径落在**本次安装目录**内（打包资源布局正确）
      C4c 进程表出现本次启动拉起的 AHK 子进程（核对父子关系）
      C5a/C5b IPC 认证成功 + 已接受 AHK 连接（已认证）
      C5c 负面对证：日志不含认证失败 / 认证超时 / AHK 路径解析失败

    另有一个**离线回放模式**（-ReplayLog）：不安装、不启动，直接把一份真实日志
    喂给同一套判据求值代码。用途是验证「断言机器本身会不会红」—— 配合
    -NegativeControl 即可在**没有 NSIS 产物**的机器上证明断言不是恒真守卫。

.NOTES
    ⚠️ 判据串全部来自源码实读，出处写在下面的 $script:Evidence 里。
       脚本启动时会做一次**源码漂移守卫**：若串在源码里找不到了，直接红
       （避免「断言早已失效但脚本还绿」这种假守卫）。
       确需绕过时用 -SkipSourceGuard，但要在 PR 里说明理由。

.PARAMETER InstallerPath
    NSIS 安装包（.exe）的路径。非回放模式下必填。

.PARAMETER StartupWaitSec
    启动后等待多少秒再判定「没秒退 + 日志已落盘」。默认 30s。

.PARAMETER ReplayLog
    离线回放模式：直接读取这份日志作为「本次新增日志」，跳过安装与启动。
    只求值日志类判据；进程表判据（C4c）会显式标注为「未评估」。

.PARAMETER ReplayInstallDir
    离线回放模式下用于 C4b 的「安装目录」。不给则 C4b 标注为「未评估」。

.PARAMETER NegativeControl
    反向对照：故意把 C5b 的判据串换成一个不存在的串，用来证明
    「这条断言在证据缺失时确实会红」。若打坏后 C5b 仍然 PASS，
    说明断言机器本身坏了，脚本红。CI 不使用该开关。

.EXAMPLE
    pwsh -File scripts/smoke-release-install.ps1 -InstallerPath 'C:\tmp\ASD-setup.exe'

.EXAMPLE
    # 反向对照（不需要安装包）：预期 C5b 变红，脚本整体退出码 0
    pwsh -File scripts/smoke-release-install.ps1 -NegativeControl `
        -ReplayLog "$env:APPDATA\com.asd.tauri\asd.2026-09-19.log" `
        -ReplayInstallDir 'C:\Users\me\AppData\Local\Temp\asd-smoke'
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InstallerPath,

    [string]$RepoRoot,
    [int]$StartupWaitSec = 30,
    [int]$InstallTimeoutSec = 420,
    [string]$LogCopyDir,
    [string]$ReplayLog,
    [string]$ReplayInstallDir,
    [switch]$SkipUninstall,
    [switch]$SkipSourceGuard,
    [switch]$NegativeControl
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# =================================================================
# 判据串（Evidence）—— 全部来自源码实读
# Text = 日志里**逐字**出现的子串；File/Line = 出处，供人工复核
# ⚠️ 不要凭印象改这里的任何字符串。要改，先改源码，再同步改这里。
# ⚠️ 行号只作人工复核线索，**不是**契约：实测同一条串在旧构建的真实日志里
#    出现在 ipc.rs:211 / watchdog.rs:276，在当前 main 里是 ipc.rs:275 / watchdog.rs:288。
#    契约是**字符串**，所以源码漂移守卫只比对字符串。
# =================================================================
$script:Evidence = [ordered]@{
    LogInit     = @{ Text = 'ASD Tauri 日志系统初始化完成';            File = 'asd-tauri/src-tauri/src/infrastructure/logging.rs'; Line = '58' }
    ConfigFirst = @{ Text = '配置文件不存在（首次启动），使用默认配置'; File = 'asd-tauri/src-tauri/src/lib.rs';                   Line = '726' }
    AhkCompiled = @{ Text = '使用编译模式 AHK 子进程';                  File = 'asd-tauri/src-tauri/src/lib.rs';                   Line = '640' }
    AhkPortable = @{ Text = '使用便携模式 AHK 子进程';                  File = 'asd-tauri/src-tauri/src/lib.rs';                   Line = '653' }
    AhkSpawn    = @{ Text = 'Watchdog: 启动 AHK 子进程:';               File = 'asd-tauri/src-tauri/src/infrastructure/watchdog.rs'; Line = '288' }
    IpcAuthOk   = @{ Text = 'IPC AHK 认证成功';                         File = 'asd-tauri/src-tauri/src/infrastructure/ipc.rs';    Line = '275' }
    IpcAccepted = @{ Text = 'IPC 已接受 AHK 连接（已认证）';            File = 'asd-tauri/src-tauri/src/infrastructure/ipc.rs';    Line = '300' }
    IpcAuthFail = @{ Text = 'IPC AHK 认证失败';                         File = 'asd-tauri/src-tauri/src/infrastructure/ipc.rs';    Line = '272 / 279 / 290' }
    IpcAuthTmo  = @{ Text = 'IPC AHK 认证超时';                         File = 'asd-tauri/src-tauri/src/infrastructure/ipc.rs';    Line = '295' }
    ResolveFail = @{ Text = '无法解析 AutoHotkey64.exe 路径';           File = 'asd-tauri/src-tauri/src/lib.rs';                   Line = '657' }
}

# AHK 子进程可能的名字：编译模式 asd_executor.exe / 便携模式 AutoHotkey64.exe
$script:AhkProcessNames = @('asd_executor', 'AutoHotkey64')

# =================================================================
# 工具函数
# =================================================================
$script:Results = New-Object System.Collections.Generic.List[object]
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:NegativeControlOk = $false

function Write-Head([string]$text) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkGray
    Write-Host $text -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkGray
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Desc,
        [Parameter(Mandatory = $true)][bool]$Pass,
        [string]$Evidence = '',
        [string]$Hint = ''
    )
    $script:Results.Add([pscustomobject]@{ Id = $Id; Desc = $Desc; Pass = $Pass })
    if (-not $Pass) { $script:Failures.Add("$Id $Desc") }
    $color = 'Green'; $tag = 'PASS'
    if (-not $Pass) { $color = 'Red'; $tag = 'FAIL' }
    Write-Host ("[{0}] {1}  {2}" -f $tag, $Id, $Desc) -ForegroundColor $color
    if ($Evidence) { Write-Host ("        证据: {0}" -f $Evidence) -ForegroundColor DarkGray }
    if ((-not $Pass) -and $Hint) { Write-Host ("        说明: {0}" -f $Hint) -ForegroundColor Yellow }
}

function Add-Skipped([string]$Id, [string]$Desc, [string]$Why) {
    Write-Host ("[SKIP] {0}  {1}" -f $Id, $Desc) -ForegroundColor DarkYellow
    Write-Host ("        原因: {0} —— 该条**未评估**，不得当成通过" -f $Why) -ForegroundColor DarkYellow
}

# 门控失败：后续判据已无法评估，直接中止（不是「跳过」，是「中止」）
function Stop-Smoke([string]$Id, [string]$Msg, [string]$Hint = '') {
    Add-Result -Id $Id -Desc $Msg -Pass $false -Hint $Hint
    throw "SMOKE-ABORT@$Id"
}

# 安全取属性：注册表项常常缺字段，StrictMode 下直接访问会抛异常
function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $pr = $obj.PSObject.Properties[$name]
    if ($pr) { return $pr.Value }
    return $null
}

function Read-TextFile([string]$path) {
    # 显式 UTF-8：tracing 的文件层是 with_ansi(false) 的纯文本 UTF-8。
    # 不用 Get-Content -Encoding utf8，避免 PS 5.1 下 BOM/代码页差异带来的静默截断。
    return [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-LogFiles([string]$dir) {
    if (-not $dir) { return @() }
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'asd.*.log' } |
        Sort-Object LastWriteTime -Descending)
}

function Get-AhkProcesses {
    $found = @()
    foreach ($n in $script:AhkProcessNames) {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($p) { $found += @($p) }
    }
    return $found
}

function Get-ChildProcessIds([int]$ParentPid) {
    # 用 CIM 拿父子关系。拿不到（CIM 不可用）时返回 $null，由调用方降级并如实标注。
    try {
        $kids = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$ParentPid" -ErrorAction Stop
        return @($kids | ForEach-Object { [int](Get-Prop $_ 'ProcessId') })
    } catch {
        Write-Host ("        [warn] CIM 不可用，无法核对父子关系: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
}

function Get-UninstallEntries {
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $out = @()
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        foreach ($k in (Get-ChildItem -Path $r -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $p) { continue }
            $out += [pscustomobject]@{
                Key             = $k.PSChildName
                DisplayName     = [string](Get-Prop $p 'DisplayName')
                # NSIS 有时把 InstallLocation 写成带引号的串，不去引号会让 Test-Path 永远为假
                InstallLocation = ([string](Get-Prop $p 'InstallLocation')).Trim('"')
                UninstallString = [string](Get-Prop $p 'UninstallString')
                Root            = $r
            }
        }
    }
    return $out
}

function Stop-All($appProc) {
    if ($appProc) {
        $exited = $true
        try { $exited = $appProc.HasExited } catch { $exited = $true }
        if (-not $exited) {
            Write-Host ("        清理: 结束主程序 pid={0}" -f $appProc.Id) -ForegroundColor DarkGray
            try { $appProc.Kill() } catch { Write-Host "        [warn] 主程序结束失败: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    foreach ($p in (Get-AhkProcesses)) {
        Write-Host ("        清理: 结束 AHK 子进程 {0} pid={1}" -f $p.ProcessName, $p.Id) -ForegroundColor DarkGray
        try { $p.Kill() } catch { Write-Host "        [warn] AHK 结束失败: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# =================================================================
# 判据求值：日志类（C3 / C4a / C4b / C5）+ 进程表类（C4c）
# 这段是唯一一处「把证据变成 PASS/FAIL」的地方 —— 正常流程与离线回放共用它，
# 所以离线回放对断言机器的验证是**有效的**（不是另写一份仿制品）。
# =================================================================
function Invoke-LogJudgements {
    param(
        [Parameter(Mandatory = $true)][string]$LogText,
        [string]$InstallDir = '',
        [switch]$SkipProcessChecks,
        $AppProc = $null,
        $AhkBefore = @()
    )

    Write-Head 'C3. app_data_dir（日志 / 配置路径）落盘'
    $eLogInit = $script:Evidence.LogInit
    $okLogInit = $LogText.Contains($eLogInit.Text)
    Add-Result -Id 'C3a' -Desc '日志系统初始化成功串出现在本次新增日志中' -Pass $okLogInit `
        -Evidence ("`"{0}`"  @ {1}:{2}" -f $eLogInit.Text, $eLogInit.File, $eLogInit.Line) `
        -Hint '该串不存在说明 logging::init 未走到最后一行，或 RUST_LOG 把它过滤掉了'

    # 配置路径可达：首次启动会打印「配置文件不存在」；复用安装（config.json 已存在）则看文件本身。
    # ⚠️ 实证：config.json **不在启动路径上写入**（lib.rs:710-738 只读；写入只发生在
    #    config_cmd.rs:234 的 save_config，需前端调用）。因此无头冒烟下不能断言「config.json 会落盘」。
    $configFirstSeen = $LogText.Contains($script:Evidence.ConfigFirst.Text)
    $configFileExists = $false
    if ($appDataDir) { $configFileExists = Test-Path -LiteralPath (Join-Path $appDataDir 'config.json') }
    $okConfig = ($configFirstSeen -or $configFileExists)
    $cfgEvidence = @()
    if ($configFirstSeen) { $cfgEvidence += ("日志含 `"{0}`"" -f $script:Evidence.ConfigFirst.Text) }
    if ($configFileExists) { $cfgEvidence += ("文件存在 " + (Join-Path $appDataDir 'config.json')) }
    if ($cfgEvidence.Count -eq 0) { $cfgEvidence += '两者皆无' }
    Add-Result -Id 'C3b' -Desc '配置路径可达（首次启动已识别 / config.json 已存在）' -Pass $okConfig `
        -Evidence ($cfgEvidence -join '; ') `
        -Hint 'config.json 只在 UI 触发 save_config 时写盘（config_cmd.rs:234），无头启动不会自动生成'

    Write-Head 'C4. 拉起 AHK 子进程'
    $eSpawn = $script:Evidence.AhkSpawn
    $spawnHit = $LogText.Contains($eSpawn.Text)

    # 从 spawn 行里抠出实际路径。真实日志样例（2026-09-19 一次成功启动）：
    #   Watchdog: 启动 AHK 子进程: \\?\C:\...\asd-smoke\ahk_executor\AutoHotkey64.exe
    $spawnPath = ''
    if ($spawnHit) {
        $m = [regex]::Match($LogText, [regex]::Escape($eSpawn.Text) + '\s*(?<p>.+?)(\r?\n|$)')
        if ($m.Success) { $spawnPath = $m.Groups['p'].Value.Trim() }
    }
    $spawnShown = '<未解析出>'
    if ($spawnPath) { $spawnShown = $spawnPath }
    Add-Result -Id 'C4a' -Desc '日志出现 AHK 子进程 spawn 记录' -Pass $spawnHit `
        -Evidence ("`"{0}`" @ {1}:{2}  → 路径={3}" -f $eSpawn.Text, $eSpawn.File, $eSpawn.Line, $spawnShown) `
        -Hint 'watchdog.rs 的 spawn 记录。真实日志实证：该串在成功启动的构建里必然出现'

    # C4b：spawn 出来的路径必须落在**本次安装目录**内 —— 这才是「打包资源布局正确」的证据，
    #      也是 dev 环境永远测不出来的一类故障。
    $normPath = $spawnPath -replace '^\\\\\?\\', ''
    if (-not $InstallDir) {
        Add-Skipped 'C4b' 'AHK 子进程路径落在本次安装目录内' '未提供安装目录（离线回放未给 -ReplayInstallDir）'
    } else {
        $okPath = $false
        if ($spawnPath) { $okPath = $normPath.ToLower().StartsWith($InstallDir.ToLower()) }
        Add-Result -Id 'C4b' -Desc 'AHK 子进程路径落在本次安装目录内（打包资源解析正确）' -Pass $okPath `
            -Evidence ("spawn路径={0}  安装目录={1}" -f $normPath, $InstallDir) `
            -Hint '路径不在安装目录内 => bundle.resources 未按预期打包，或跑到了开发目录的运行时'
    }

    # 补充信息（**不计判据**）：解析模式串。真实日志实证 —— 旧构建里该串缺失，
    # 所以不设为硬判据，只打印，避免把「文案差异」误判成「功能坏了」。
    $modeHit = @()
    foreach ($k in @('AhkCompiled', 'AhkPortable')) {
        $e = $script:Evidence[$k]
        if ($LogText.Contains($e.Text)) { $modeHit += $e.Text }
    }
    if ($modeHit.Count -gt 0) {
        Write-Host ("        [info] 解析模式串: {0}" -f ($modeHit -join ' | ')) -ForegroundColor DarkGray
    } else {
        Write-Host '        [info] 未出现「使用便携/编译模式 AHK 子进程」串（不计判据；实测旧构建的真实日志里该串缺失）' -ForegroundColor DarkGray
    }

    if ($SkipProcessChecks) {
        Add-Skipped 'C4c' '进程表出现本次启动拉起的 AHK 子进程' '离线回放模式不启动进程'
    } else {
        # 必须是本次启动的**新**子进程，且父进程是主程序（避免读到遗留进程假绿）
        $ahkNow = @(Get-AhkProcesses | Where-Object { $AhkBefore -notcontains $_.Id })
        $childIds = Get-ChildProcessIds -ParentPid $AppProc.Id
        $okChild = $false
        $childEvidence = ''
        $ahkList = ($ahkNow | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ','
        if ($ahkNow.Count -eq 0) {
            $childEvidence = '进程表中没有新增 AHK 进程'
        } elseif ($null -ne $childIds) {
            $matched = @($ahkNow | Where-Object { $childIds -contains $_.Id })
            $okChild = ($matched.Count -gt 0)
            $childEvidence = "新增AHK=[{0}] 主程序子进程=[{1}] 交集=[{2}]" -f $ahkList, ($childIds -join ','), (($matched | ForEach-Object { $_.Id }) -join ',')
        } else {
            # CIM 不可用：降级为「存在新增进程」，并如实标注降级
            $okChild = $true
            $childEvidence = "新增AHK=[{0}]（CIM 不可用，未核对父子关系，判据已降级）" -f $ahkList
        }
        Add-Result -Id 'C4c' -Desc '进程表出现本次启动拉起的 AHK 子进程' -Pass $okChild -Evidence $childEvidence `
            -Hint '进程名应为 asd_executor 或 AutoHotkey64；CIM 不可用时会退化为「仅看新增进程」'
    }

    Write-Head 'C5. IPC 认证'
    $eAuth = $script:Evidence.IpcAuthOk
    $eAccepted = $script:Evidence.IpcAccepted

    # 反向对照：故意用不存在的串，证明这条断言会红
    if ($NegativeControl) {
        Write-Host '[NEGATIVE-CONTROL] C5b 判据串已被替换为不存在的串，预期 C5b 变红' -ForegroundColor Magenta
        $eAccepted = @{ Text = $eAccepted.Text + '__NEGATIVE_CONTROL__'; File = $eAccepted.File; Line = $eAccepted.Line }
    }

    Add-Result -Id 'C5a' -Desc '日志出现 IPC 认证成功串' -Pass $LogText.Contains($eAuth.Text) `
        -Evidence ("`"{0}`"  @ {1}:{2}" -f $eAuth.Text, $eAuth.File, $eAuth.Line)
    Add-Result -Id 'C5b' -Desc '日志出现 IPC 已接受 AHK 连接（已认证）串' -Pass $LogText.Contains($eAccepted.Text) `
        -Evidence ("`"{0}`"  @ {1}:{2}" -f $eAccepted.Text, $eAccepted.File, $eAccepted.Line) `
        -Hint '该串在 ipc.rs:300，需「子进程 spawn 成功 + 管道名一致 + 子进程主动连上 + auth token 匹配」四件事同时成立'

    # 负面对证
    $bad = @($script:Evidence.IpcAuthFail, $script:Evidence.IpcAuthTmo, $script:Evidence.ResolveFail)
    $badHit = @($bad | Where-Object { $LogText.Contains($_.Text) })
    $okNeg = ($badHit.Count -eq 0)
    $negEvidence = '未命中任何负面对证串'
    if (-not $okNeg) { $negEvidence = '命中: ' + (($badHit | ForEach-Object { $_.Text }) -join ' | ') }
    Add-Result -Id 'C5c' -Desc '日志不含认证失败 / 认证超时 / AHK 路径解析失败' -Pass $okNeg -Evidence $negEvidence `
        -Hint '命中说明「看起来起来了，其实是坏的」'

    if ($NegativeControl) {
        # 反向对照成立的条件：唯一一条失败就是被我们故意打坏的那条 C5b
        $script:NegativeControlOk = (($script:Failures.Count -eq 1) -and ($script:Failures[0] -like 'C5b *'))
        if (-not $script:NegativeControlOk) {
            Add-Result -Id 'NC' -Desc '反向对照失败：打坏判据串后断言没有变红（断言机器本身坏了）' -Pass $false `
                -Evidence ("实际失败项: [{0}]" -f ($script:Failures -join ' ; '))
        }
    }
}

function Write-Summary {
    Write-Head '汇总'
    foreach ($r in $script:Results) {
        $c = 'Green'; $t = 'PASS'; if (-not $r.Pass) { $c = 'Red'; $t = 'FAIL' }
        Write-Host ("[{0}] {1}  {2}" -f $t, $r.Id, $r.Desc) -ForegroundColor $c
    }
    Write-Host ''
    if ($script:NegativeControlOk) {
        Write-Host '反向对照通过：证据缺失时 C5b 确实变红 —— 该断言不是恒真守卫' -ForegroundColor Magenta
        return 0
    }
    if ($script:Failures.Count -eq 0) {
        Write-Host '冒烟通过：安装 / 启动 / app_data_dir 落盘 / 拉起 AHK / IPC 已认证' -ForegroundColor Green
        return 0
    }
    Write-Host ("冒烟失败，共 {0} 条未通过：" -f $script:Failures.Count) -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    return 1
}

# =================================================================
# 主流程
# =================================================================
$appProc = $null
$installer = $null
$productName = $null
$appDataDir = $null
$replayMode = [bool]$ReplayLog
$exitCode = 1

# 清理段的安全阀：只卸载「本次运行确实装出来的那一个」卸载项。
# ⚠️ 这里刻意不用 `DisplayName -like '*ASD*'` 之类的模糊匹配 —— 实测踩过：
#    模糊匹配会命中本机既有的、与本次运行无关的安装，然后把它卸载掉。
$didInstall = $false
$installedEntry = $null

try {
    Write-Head '0. 预检'

    if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
    $confPath = Join-Path $RepoRoot 'asd-tauri/src-tauri/tauri.conf.json'
    if (-not (Test-Path $confPath)) { Stop-Smoke 'PRE' "找不到 tauri.conf.json: $confPath" '用 -RepoRoot 指定仓库根目录' }
    $conf = Get-Content -LiteralPath $confPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $productName = [string](Get-Prop $conf 'productName')
    $identifier = [string](Get-Prop $conf 'identifier')
    if (-not $productName -or -not $identifier) { Stop-Smoke 'PRE' 'tauri.conf.json 缺少 productName / identifier' }
    Write-Host ("productName={0}  identifier={1}" -f $productName, $identifier) -ForegroundColor Gray

    # ---- 源码漂移守卫：判据串必须仍存在于源码中 ----
    if ($SkipSourceGuard) {
        Write-Host '[warn] -SkipSourceGuard 已开启：跳过判据串源码守卫' -ForegroundColor Yellow
    } else {
        $drift = @()
        foreach ($name in $script:Evidence.Keys) {
            $e = $script:Evidence[$name]
            $f = Join-Path $RepoRoot $e.File
            if (-not (Test-Path $f)) { $drift += "$name : 源码文件缺失 $($e.File)"; continue }
            if (-not (Read-TextFile $f).Contains($e.Text)) {
                $drift += ("{0} : 串 [{1}] 已不在 {2}:{3}" -f $name, $e.Text, $e.File, $e.Line)
            }
        }
        if ($drift.Count -gt 0) {
            Write-Host '判据串漂移明细:' -ForegroundColor Red
            $drift | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            Stop-Smoke 'PRE' '判据串已从源码消失，冒烟脚本的断言已失效' '源码里的日志文案被改过 => 必须同步更新 $script:Evidence；确认无误后用 -SkipSourceGuard 绕过'
        }
        Write-Host ("判据串源码守卫: {0} 条全部命中源码" -f $script:Evidence.Count) -ForegroundColor Green
    }

    # 环境预检：C3 的两条判据都建立在 %APPDATA%\<identifier> 上。
    # 环境变量缺失时**不许把判据降级为「跳过」**，必须显式红。
    if (-not $env:APPDATA) {
        Stop-Smoke 'PRE' '$env:APPDATA 为空，无法定位 app_data_dir' '日志/配置判据都建立在 %APPDATA%\<identifier> 上；环境变量缺失不能当作「跳过」'
    }
    $appDataDir = Join-Path $env:APPDATA $identifier

    if ($replayMode) {
        # ---------------- 离线回放：不安装、不启动 ----------------
        Write-Head '离线回放模式'
        $rl = Resolve-Path -LiteralPath $ReplayLog -ErrorAction SilentlyContinue
        if (-not $rl) { Stop-Smoke 'PRE' "回放日志不存在: $ReplayLog" }
        $logText = Read-TextFile $rl.Path
        Write-Host ("回放日志: {0}（{1} 字符）" -f $rl.Path, $logText.Length) -ForegroundColor Gray
        if ($logText.Length -eq 0) { Stop-Smoke 'PRE' '回放日志为空' }
        Invoke-LogJudgements -LogText $logText -InstallDir $ReplayInstallDir -SkipProcessChecks
        $exitCode = Write-Summary
        return
    }

    if (-not $InstallerPath) { Stop-Smoke 'PRE' '非回放模式下必须提供 -InstallerPath' }

    $resolved = Resolve-Path -LiteralPath $InstallerPath -ErrorAction SilentlyContinue
    if (-not $resolved) { Stop-Smoke 'PRE' "安装包不存在: $InstallerPath" '检查 -InstallerPath 是否指向 NSIS 产物（*.exe）' }
    $installer = $resolved.Path
    if (-not $installer.ToLower().EndsWith('.exe')) { Stop-Smoke 'PRE' "安装包不是 .exe: $installer" }
    $installerSize = (Get-Item -LiteralPath $installer).Length
    if ($installerSize -le 0) { Stop-Smoke 'PRE' "安装包是空文件: $installer" }
    Write-Host ("安装包: {0}  ({1:N0} 字节)" -f $installer, $installerSize) -ForegroundColor Gray

    # ---- 记录基线：本次运行前已存在的日志长度、AHK 进程 ----
    $logFilesBefore = Get-LogFiles $appDataDir
    $logBeforePath = ''
    $logBeforeLen = 0
    if ($logFilesBefore.Count -gt 0) {
        $logBeforePath = $logFilesBefore[0].FullName
        $logBeforeLen = $logFilesBefore[0].Length
    }
    $beforeLabel = '<无>'
    if ($logBeforePath) { $beforeLabel = $logBeforePath }
    Write-Host ("基线日志: {0} (len={1})" -f $beforeLabel, $logBeforeLen) -ForegroundColor Gray

    $ahkBefore = @(Get-AhkProcesses | ForEach-Object { $_.Id })
    if ($ahkBefore.Count -gt 0) {
        Write-Host ("清理本次运行前的遗留 AHK 进程: {0}" -f ($ahkBefore -join ',')) -ForegroundColor Yellow
        foreach ($p in (Get-AhkProcesses)) { try { $p.Kill() } catch { } }
        Start-Sleep -Milliseconds 500
    }

    # =================================================================
    # C1. 静默安装 + 安装目录出现主 exe
    # =================================================================
    Write-Head 'C1. 静默安装（NSIS /S）'

    # 既有安装护栏：本机若已有**真实存在**的同名安装，拒绝覆盖。
    # 这既避免把本次产物装到既有环境上（结果不可信），也避免清理段误伤别人的安装。
    $preExisting = @(Get-UninstallEntries | Where-Object { $_.DisplayName -eq $productName })
    $livePre = @($preExisting | Where-Object { $_.InstallLocation -and (Test-Path -LiteralPath $_.InstallLocation) })
    if ($livePre.Count -gt 0) {
        $where = ($livePre | ForEach-Object { $_.InstallLocation }) -join ', '
        Stop-Smoke 'C1' "本机已存在同名安装（$productName），拒绝在既有环境上覆盖安装" "既有位置: $where —— 请先手动卸载，或在干净环境上跑"
    }
    $stalePre = @($preExisting | Where-Object { -not ($_.InstallLocation -and (Test-Path -LiteralPath $_.InstallLocation)) })
    if ($stalePre.Count -gt 0) {
        Write-Host ("[warn] 检测到 {0} 个**失效**的同名卸载项（指向不存在的目录），不阻断；清理段只会卸载本次装出来的那一个" -f $stalePre.Count) -ForegroundColor Yellow
        foreach ($s in $stalePre) { Write-Host ("        - {0} | InstallLocation={1}" -f $s.Key, $s.InstallLocation) -ForegroundColor DarkGray }
    }

    $inst = Start-Process -FilePath $installer -ArgumentList '/S' -PassThru
    if (-not $inst.WaitForExit($InstallTimeoutSec * 1000)) {
        try { $inst.Kill() } catch { }
        Stop-Smoke 'C1' "安装器 $InstallTimeoutSec s 内未退出（疑似弹窗卡住）" 'displayLanguageSelector=true 下 /S 是否真静默未经实测，首次执行需人工盯'
    }
    Write-Host ("安装器退出码: {0}" -f $inst.ExitCode) -ForegroundColor Gray
    if ($inst.ExitCode -ne 0) { Stop-Smoke 'C1' "静默安装失败，退出码 $($inst.ExitCode)" }
    $didInstall = $true

    # 定位安装目录：注册表优先（精确 DisplayName），候选路径兜底
    $installDir = ''
    $entries = Get-UninstallEntries
    $hit = @($entries | Where-Object { $_.DisplayName -eq $productName -and $_.InstallLocation })
    if ($hit.Count -eq 0) {
        $hit = @($entries | Where-Object { $_.DisplayName -like '*ASD*' -and $_.InstallLocation })
        if ($hit.Count -gt 0) {
            Write-Host ("[warn] 未找到 DisplayName 精确等于 `"{0}`" 的卸载项，退化为 `*ASD*` 模糊匹配" -f $productName) -ForegroundColor Yellow
        }
    }
    foreach ($h in $hit) {
        if (Test-Path -LiteralPath $h.InstallLocation) {
            $installDir = (Resolve-Path -LiteralPath $h.InstallLocation).Path
            Write-Host ("安装目录（注册表 {0}）：{1}" -f $h.Key, $installDir) -ForegroundColor Gray
            break
        }
    }
    if (-not $installDir) {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA $productName),
            (Join-Path (Join-Path $env:LOCALAPPDATA 'Programs') $productName),
            (Join-Path $env:ProgramFiles $productName)
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c) {
                $installDir = (Resolve-Path -LiteralPath $c).Path
                Write-Host "安装目录（候选路径）：$installDir" -ForegroundColor Gray
                break
            }
        }
    }
    if (-not $installDir) {
        Stop-Smoke 'C1' '安装后既未在注册表 Uninstall 项、也未在候选路径找到安装目录' '注册表键名与安装目录命名来自 tauri-bundler 的 NSIS 模板，未经本地实跑验证'
    }

    # 精确记录「本次装出来的卸载项」：DisplayName 精确等于 productName 且 InstallLocation 指向本次安装目录。
    # 拿不到就不记 —— 清理段宁可跳过卸载，也不做模糊匹配。
    foreach ($h in @(Get-UninstallEntries | Where-Object { $_.DisplayName -eq $productName -and $_.InstallLocation })) {
        if (-not (Test-Path -LiteralPath $h.InstallLocation)) { continue }
        if ((Resolve-Path -LiteralPath $h.InstallLocation).Path -eq $installDir) { $installedEntry = $h; break }
    }
    if ($installedEntry) {
        Write-Host ("本次安装对应的卸载项: {0}\{1}" -f $installedEntry.Root, $installedEntry.Key) -ForegroundColor DarkGray
    } else {
        Write-Host '[warn] 未能精确定位本次安装的卸载项，清理段将跳过卸载' -ForegroundColor Yellow
    }

    # 定位主 exe：候选名优先，兜底取唯一非辅助 exe
    $excludeExe = @('uninstall.exe', 'AutoHotkey64.exe', 'asd_executor.exe')
    $mainExe = ''
    foreach ($name in @("$productName.exe", 'asd-tauri.exe')) {
        $p = Join-Path $installDir $name
        if (Test-Path -LiteralPath $p) { $mainExe = $p; break }
    }
    if (-not $mainExe) {
        $rest = @(Get-ChildItem -LiteralPath $installDir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
            Where-Object { $excludeExe -notcontains $_.Name -and $_.Name -notlike '*uninst*' })
        if ($rest.Count -eq 1) {
            $mainExe = $rest[0].FullName
        } elseif ($rest.Count -gt 1) {
            $names = ($rest | ForEach-Object { $_.Name }) -join ', '
            Stop-Smoke 'C1' '安装目录里有多个候选主程序，无法判定哪个是主 exe' "候选: $names"
        }
    }
    if (-not $mainExe) { Stop-Smoke 'C1' "安装目录 $installDir 里找不到主程序 exe" }

    Add-Result -Id 'C1' -Desc '静默安装成功且安装目录出现主程序 exe' -Pass $true -Evidence "退出码=0, exe=$mainExe"

    # =================================================================
    # C2. 启动主程序，进程表可见且未秒退
    # =================================================================
    Write-Head 'C2. 启动主程序'
    $env:RUST_LOG = 'info'   # 与 logging.rs 的默认级别一致，显式声明避免环境漂移
    $appProc = Start-Process -FilePath $mainExe -PassThru
    Write-Host ("已启动 pid={0}，等待 {1}s ..." -f $appProc.Id, $StartupWaitSec) -ForegroundColor Gray
    Start-Sleep -Seconds $StartupWaitSec

    $alive = $false
    try { $alive = -not $appProc.HasExited } catch { $alive = $false }
    if (-not $alive) {
        $code = 'n/a'
        try { $code = $appProc.ExitCode } catch { }
        Stop-Smoke 'C2' "主程序启动后立即退出（exit=$code）" '典型原因：WebView2 运行时缺失 / 资源缺失导致 setup 失败'
    }
    Add-Result -Id 'C2' -Desc "主程序启动后 ${StartupWaitSec}s 未退出" -Pass $true -Evidence "pid=$($appProc.Id), name=$($appProc.ProcessName)"

    # ---- 取出「本次运行新增」的那一段日志，避免复用旧日志导致假绿 ----
    $logFilesAfter = Get-LogFiles $appDataDir
    if ($logFilesAfter.Count -eq 0) {
        Stop-Smoke 'C3a' "app_data_dir 存在但没有 asd.<YYYY-MM-DD>.log（目录: $appDataDir）" 'tracing_appender 的 DAILY 轮转产出 asd.<date>.log；不存在说明文件层未初始化'
    }
    $logFile = $logFilesAfter[0]
    $logText = ''
    if ($logFile.FullName -eq $logBeforePath) {
        if ($logFile.Length -gt $logBeforeLen) {
            $fs = [System.IO.File]::Open($logFile.FullName, 'Open', 'Read', 'ReadWrite')
            try {
                $fs.Seek($logBeforeLen, 'Begin') | Out-Null
                $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
                try { $logText = $sr.ReadToEnd() } finally { $sr.Dispose() }
            } finally { $fs.Dispose() }
        }
    } else {
        $logText = Read-TextFile $logFile.FullName
    }
    Write-Host ("本次新增日志: {0} 字节（文件: {1}）" -f $logText.Length, $logFile.FullName) -ForegroundColor Gray
    if ($logText.Length -eq 0) {
        Stop-Smoke 'C3a' '本次运行未向日志写入任何内容（日志文件存在但零新增）' '不能把旧日志内容当成本次启动的证据'
    }

    Invoke-LogJudgements -LogText $logText -InstallDir $installDir -AppProc $appProc -AhkBefore $ahkBefore
    $exitCode = Write-Summary
}
catch {
    if ($_.Exception.Message -notlike 'SMOKE-ABORT*') {
        Write-Host ''
        Write-Host "冒烟脚本异常: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        # ⚠️ 实测踩过：这里原先只打印不记失败，于是「未预期异常」会被汇总段判成
        #    「冒烟通过 / exit 0」—— 一个典型的恒绿守卫。非受控异常一律判失败。
        Add-Result -Id 'EXC' -Desc "脚本异常中止: $($_.Exception.Message)" -Pass $false `
            -Hint '非受控异常一律判失败，不允许「异常吞掉后报通过」'
    }
    if ($replayMode) {
        $exitCode = Write-Summary
    }
}
finally {
    if (-not $replayMode) {
        Write-Head '清理'
        Stop-All -appProc $appProc

        if (-not $SkipUninstall) {
            if (-not $didInstall) {
                Write-Host '本次运行未完成安装（C1 之前中止），跳过卸载：不触碰任何既有安装' -ForegroundColor DarkGray
            } elseif (-not $installedEntry) {
                Write-Host '未精确定位到本次安装对应的卸载项，跳过卸载（宁可留残留，也不误删既有安装）' -ForegroundColor Yellow
            } else {
                $unExe = $installedEntry.UninstallString.Trim('"')
                if ($unExe -match '^(.+?\.exe)') { $unExe = $Matches[1] }
                Write-Host ("卸载（{0}\{1}）: {2} /S" -f $installedEntry.Root, $installedEntry.Key, $unExe) -ForegroundColor DarkGray
                if (Test-Path -LiteralPath $unExe) {
                    $up = Start-Process -FilePath $unExe -ArgumentList '/S' -PassThru
                    if ($up.WaitForExit(180000)) {
                        # 卸载不属于本脚本的 5 条判据，退出码只如实打印，不参与判定
                        Write-Host ("卸载器退出码: {0}（非判据，仅记录）" -f $up.ExitCode) -ForegroundColor DarkGray
                    } else {
                        try { $up.Kill() } catch { }
                        Write-Host '卸载器 180s 未退出（非判据，仅记录）' -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "卸载器路径不存在: $unExe（非判据，仅记录）" -ForegroundColor Yellow
                }
            }
        }

        if ($LogCopyDir) {
            New-Item -ItemType Directory -Path $LogCopyDir -Force | Out-Null
            if ($appDataDir -and (Test-Path -LiteralPath $appDataDir)) {
                foreach ($f in (Get-LogFiles $appDataDir)) { Copy-Item $f.FullName $LogCopyDir -Force }
                Write-Host "日志已留档到: $LogCopyDir" -ForegroundColor DarkGray
            }
        }

        # 只有走到「安装完成」的路径才需要在这里收尾；其余（PRE/C1 中止）已在 catch 里出结论。
        if ($didInstall) { $exitCode = Write-Summary }
    }
}

exit $exitCode
