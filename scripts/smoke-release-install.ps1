#Requires -Version 5.1
<#
.SYNOPSIS
    发布产物冒烟测试：静默安装 NSIS 包 → 启动主程序 → 用「日志文件 + 进程表」判定它到底能不能跑起来。

.DESCRIPTION
    判据全部取自**日志文件和进程表**，不做任何 GUI 截图 / 像素判断。
    每一条判据的字符串都实证自源码，出处见下方「判据出处」表；拿不到的判据一律
    如实报 UNVERIFIED，绝不静默变绿。

    ⚠️ 反假守卫（本项目踩过的坑：CI 里跑 `cargo test -- --ignored`，仓库零条
    #[ignore]，每次 "running 0 tests" 永远绿）。本脚本因此内置**双向对照**：
        -SelfCheck  不安装任何东西，只把每个判据函数喂「坏输入」，断言它必须变红；
                    同时喂「好输入」，断言它必须变绿。
                    任何一条本该红却变绿（或本该绿却变红）→ 该判据是假守卫 → 退出码 2。
    CI 里请先跑 -SelfCheck 再跑实装，守卫坏了要在装之前暴露，而不是发布之后。

.PARAMETER InstallerPath
    NSIS 安装包（*.exe）路径，必填。

.PARAMETER InstallDir
    安装目标目录。默认 $env:TEMP\asd-smoke-install（无空格，避免 NSIS /D 的引号坑）。

.PARAMETER MainExeName
    主程序文件名。实测为 `asd-tauri.exe`（来自 Cargo.toml [[bin]] name，
    **不是** productName「ASD - 技能管理器」）。

.PARAMETER StartupTimeoutSec
    等待「进程起来 + IPC 认证完成」的超时秒数。

.PARAMETER StrictConfig
    把 C3（配置落盘）的 UNVERIFIED 升级为硬失败。默认不开，原因见 C3 说明。

.PARAMETER KeepInstalled
    跳过清理（不卸载、不杀进程），便于事后人工看现场。

.EXAMPLE
    .\scripts\smoke-release-install.ps1 -SelfCheck
    .\scripts\smoke-release-install.ps1 -InstallerPath '.\ASD - 技能管理器_0.1.0_x64-setup.exe'

.NOTES
    退出码：0 全通过 / 1 有判据失败 / 2 守卫自检失败（假守卫）/ 3 参数或环境错误。
#>

# ═════════════════════════════════════════════════════════════════════════════
# ⚠️⚠️ 验证状态 —— 接手前必读，**不要**把它当成已验证 ⚠️⚠️
# ═════════════════════════════════════════════════════════════════════════════
#   · 判据的「判别性」（即：故意破坏时会不会真的变红）由两件事保证：
#       ① `-SelfCheck` 双向对照：坏输入必须变红、好输入必须变绿，任一条不符即退出码 2；
#       ② 真实日志的正 / 负样本复核（正：asd.2026-09-19.log 命中；负：更早的样本不命中）。
#   · **C1–C5 的运行时路径（安装 → 启动 → 拉起 AHK → IPC 认证）从未跑过一次完整闭环。**
#     下文出现的「实测」字样，来源是**人工一次性观测**（安装目录布局、主 exe 名、
#     日志串出现次数），**不等于**本脚本已端到端跑绿 —— 这两件事不要混为一谈。
#   · 首次发布（workflow_dispatch + build_release）之前**必须人工观察本 step 的输出**。
#     在那之前，不要把「CI 能出包」或「冒烟已通过」当成既有事实。
# ═════════════════════════════════════════════════════════════════════════════

[CmdletBinding()]
param(
    # 不用 [Parameter(Mandatory)]：-SelfCheck 只验证判据函数、不装任何东西，
    # 强制参数会让守卫自检根本跑不起来（实测 -File ... -SelfCheck 直接报
    # 「强制参数丢失: InstallerPath」）。改为在下面手工校验，报错信息也更清楚。
    [string]$InstallerPath,

    # 默认目录**每次运行都不同**：本机上多人/多脚本并发跑冒烟时，若共用一个固定目录，
    # 会撞车 —— 实测撞到过：清目录时 asd-tauri.exe 被别人的进程锁住，Remove-Item 直接
    # 拒访问把脚本打断。唯一目录 + finally 里自清理，互不影响。要固定目录请显式传本参数。
    [string]$InstallDir = (Join-Path $env:TEMP ('asd-smoke-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))),

    [string]$MainExeName = 'asd-tauri.exe',

    [string]$AppIdentifier = 'com.asd.tauri',

    [int]$StartupTimeoutSec = 60,

    [switch]$StrictConfig,

    [switch]$KeepInstalled,

    [switch]$SelfCheck
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────────────────────
# 判据出处（每一条都是读源码 + 实跑核实过的，不是凭印象写的）
# ─────────────────────────────────────────────────────────────────────────────
#
#  C1 静默安装后主 exe 存在
#      安装器：`ASD - 技能管理器_<ver>_x64-setup.exe`，NSIS `/S` 静默、`/D=<dir>`
#              指定目录（实测 /D 被 NSIS 采纳，安装到 C:\Users\fei\AppData\Local\Temp\asd-smoke）。
#      主 exe：`asd-tauri.exe` —— Cargo.toml:11-13 `[[bin]] name = "asd-tauri"`。
#              实测安装目录只有三项：asd-tauri.exe / ahk_executor/ / uninstall.exe。
#              ⚠️ 不是 productName（tauri.conf.json:3 `"productName": "ASD - 技能管理器"`）。
#
#  C2 进程表里有主程序
#      进程名 `asd-tauri`。要求 StartTime >= 本次运行起点，避免拿残留进程蒙混过关。
#
#  C3 配置落盘  ⚠️ 本条**拿不到稳定判据**，默认只报 UNVERIFIED
#      实测：删掉 %APPDATA%\com.asd.tauri\config.json 后冷启动 30s，文件依然不存在。
#      源码：启动只**读**不写 —— src/lib.rs:722 `ConfigRepository::load_from_file_checked(&config_path)`；
#            唯一写入点是被前端命令触发的 src/commands/config_cmd.rs:58 `save_config_impl`
#            （asd-tauri/src/main.js:592/628/686/711 调 invoke('save_config')）。
#      退化判据：日志里出现「使用默认配置」= 配置子系统确实跑到了、路径解析正确。
#            该子串在**当前源码与已观测历史构建**中均出现，是唯一跨版本稳定的部分：
#              · src/lib.rs:726  `配置文件不存在（首次启动），使用默认配置`  (INFO)
#              · src/lib.rs:731  `配置文件加载失败[{}]: {} —— 使用默认配置，…` (ERROR)
#              · 历史构建实测输出 `配置文件加载失败: 配置文件不存在: …使用默认配置`
#            ⚠️ 注意：整句文案在版本间 churn 过（二进制打出的行号 689 对不上当前源码 726/731），
#               所以只匹配稳定子串 `使用默认配置`，不匹配整句。
#      ⇒ 结论：CI 干净机上会走「首次启动」分支而命中；本机若已有 config.json 则
#        既不落盘也不打日志 → UNVERIFIED。加 -StrictConfig 才会让它变红。
#
#  C4 拉起 AHK 子进程
#      进程名 `asd_executor.exe` 或 `AutoHotkey64.exe`。
#      ⚠️ 实测**装出来的版本走便携模式**：bundle.resources（tauri.conf.json）只列了
#         asd_executor.bat + AutoHotkey64.exe，没列 asd_executor.exe，所以进程是
#         `AutoHotkey64.exe`。实测日志佐证：lib.rs:617 `asd_executor.exe 不存在，尝试便携模式`。
#      配套日志：src/infrastructure/watchdog.rs:288 `Watchdog: 启动 AHK 子进程: {exe_path}`
#
#  C5 IPC 已完成认证 ★最关键
#      字符串：`IPC AHK 认证成功`
#      源码：src/infrastructure/ipc.rs:275  `tracing::info!("IPC AHK 认证成功");`
#            （紧邻 ipc.rs:270 的 constant_time_eq token 校验，校验不过走 :272 的
#             `IPC AHK 认证失败: token 不匹配`，所以这一条能真正区分「认证过没过」）
#      落盘核实：该串在真实日志里出现 —— asd.2026-09-13.log 55 次、09-16 17 次、
#            09-17 32 次、09-19 本次实跑 2 次。确实进了文件，不是只进 stdout。
#      ⚠️ 反面：AHK 侧的连接成功只走 `OutputDebug`
#            （ahk_executor/ipc_client.ahk:588 `OutputDebug("IpcClient: 已连接到 " …)`），
#            **不落日志文件，不能当判据**。
#      ⚠️ 另一个陷阱：`AHK-CONNECT-OK` 全仓只出现在
#            deliverables/engineering-assurance/td071-ipc-dacl-2026-09-19.md:256 描述的
#            **测试夹具**里（FileAppend 到 stdout），生产代码没有 → 不能用。
#
#  日志文件路径（实测，不靠猜）
#      src/infrastructure/logging.rs:28-34：RollingFileAppender，DAILY 轮转，
#      filename_prefix="asd"、suffix="log"、目录 = `app.path().app_data_dir()`
#      —— ⚠️ **不是** app_data_dir\logs 子目录，就在 app_data_dir 根下。
#      实测磁盘：%APPDATA%\com.asd.tauri\asd.2026-09-19.log（identifier 见
#      tauri.conf.json:5 `"identifier": "com.asd.tauri"`）。
#      轮转按 UTC 日期命名，因此脚本**按 LastWriteTime >= 运行起点筛选文件**，
#      不按文件名里的日期，避免 UTC/本地跨日时漏掉。
# ─────────────────────────────────────────────────────────────────────────────

$script:IPC_AUTH_OK   = 'IPC AHK 认证成功'   # ipc.rs:275
$script:CFG_FALLBACK  = '使用默认配置'        # 见 C3 说明，跨版本稳定子串

# ═════════════════════════════════════════════════════════════════════════════
# 判据函数（纯函数式：同样喂进 -SelfCheck 做双向对照，保证它们真的会变红）
# ═════════════════════════════════════════════════════════════════════════════

function Test-FileFresh {
    param([string]$Path, [datetime]$Since)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path
    # 长度 > 0：空文件不算「成功落盘」，否则 0 字节也算过 —— 那正是假守卫的温床。
    return ($item.LastWriteTime -ge $Since -and $item.Length -gt 0)
}

function Get-FreshLogFiles {
    param([string]$LogDir, [datetime]$Since)
    if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $LogDir -Filter 'asd.*.log' -File |
             Where-Object { $_.LastWriteTime -ge $Since })
}

function Test-LogContains {
    param([string]$LogDir, [string]$Pattern, [datetime]$Since)

    # @() 包裹是必须的：函数 return 空数组会被 PowerShell 展开成 $null，
    # 后面 $files.Count 在 Set-StrictMode 下会直接抛「找不到属性 Count」（实测踩到）。
    $files = @(Get-FreshLogFiles -LogDir $LogDir -Since $Since)
    $bytes = 0
    $hit = $false
    $hitLine = $null
    foreach ($f in $files) {
        $bytes += $f.Length
        # 显式 UTF8 读，避免 PS 5.1 默认编码把中文匹配成永远不命中（那也是一种假守卫）。
        $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
        foreach ($line in $lines) {
            if ($line.Contains($Pattern)) { $hit = $true; $hitLine = $line; break }
        }
        if ($hit) { break }
    }
    return [pscustomobject]@{
        Found     = $hit
        FileCount = $files.Count
        Bytes     = $bytes
        Line      = $hitLine
    }
}

function Test-ProcessSince {
    param([string[]]$Names, [datetime]$Since)
    $matched = @()
    foreach ($name in $Names) {
        $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        foreach ($p in $procs) {
            $started = $null
            try { $started = $p.StartTime } catch { $started = $null }
            # StartTime 取不到（权限/系统进程）一律视为「不是本次启动的」，宁可漏判也不误判。
            if ($null -ne $started -and $started -ge $Since) {
                $matched += [pscustomobject]@{ Name = $name; Id = $p.Id; StartTime = $started }
            }
        }
    }
    return [pscustomobject]@{ Found = ($matched.Count -gt 0); Matched = $matched }
}

# ═════════════════════════════════════════════════════════════════════════════
# 守卫自检（反向对照）：不安装、不启动，只验证判据函数真的会红 / 真的会绿
# ═════════════════════════════════════════════════════════════════════════════

function Invoke-GuardSelfCheck {
    $broken = @()
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('asd-smoke-guard-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $since = (Get-Date).AddMinutes(-5)

    try {
        # ── 负向：坏输入必须返回 RED ────────────────────────────────────────
        # N1 日志里只有「认证失败」，绝不能命中「认证成功」
        $badLog = Join-Path $tmp 'asd.2026-01-01.log'
        [System.IO.File]::WriteAllText($badLog,
            "2026-01-01T00:00:00Z  WARN x: IPC AHK 认证失败: token 不匹配`n",
            (New-Object System.Text.UTF8Encoding($false)))
        $r = Test-LogContains -LogDir $tmp -Pattern $script:IPC_AUTH_OK -Since $since
        if ($r.Found) { $broken += 'N1 负向失效：日志只有「认证失败」，判据却说认证成功' }

        # N2 陈旧文件（mtime 早于运行起点）不能算「本次落盘」
        $stale = Join-Path $tmp 'stale.json'
        [System.IO.File]::WriteAllText($stale, '{}', (New-Object System.Text.UTF8Encoding($false)))
        (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddDays(-3)
        if (Test-FileFresh -Path $stale -Since $since) { $broken += 'N2 负向失效：陈旧文件被当成新落盘' }

        # N3 不存在的路径不能算通过
        if (Test-FileFresh -Path (Join-Path $tmp 'nope.json') -Since $since) { $broken += 'N3 负向失效：不存在的文件被判为存在' }

        # N4 不存在的进程名不能算通过
        $fake = 'asd-no-such-proc-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if ((Test-ProcessSince -Names @($fake) -Since $since).Found) { $broken += 'N4 负向失效：不存在的进程被判为在跑' }

        # N5 日志目录为空（0 字节）时，判据必须报「未找到」而不是「通过」
        $emptyDir = Join-Path $tmp 'emptylogs'
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $r = Test-LogContains -LogDir $emptyDir -Pattern $script:IPC_AUTH_OK -Since $since
        if ($r.Found -or $r.Bytes -ne 0) { $broken += 'N5 负向失效：空日志目录被判为命中' }

        # ── 正向：好输入必须返回 GREEN ──────────────────────────────────────
        # P1 真有「认证成功」时必须命中
        $goodLog = Join-Path $tmp 'asd.2026-01-02.log'
        [System.IO.File]::WriteAllText($goodLog,
            "2026-01-02T00:00:00Z  INFO ThreadId(14) asd_tauri_lib::infrastructure::ipc: src-tauri\src\infrastructure\ipc.rs:275: IPC AHK 认证成功`n",
            (New-Object System.Text.UTF8Encoding($false)))
        $r = Test-LogContains -LogDir $tmp -Pattern $script:IPC_AUTH_OK -Since $since
        if (-not $r.Found) { $broken += 'P1 正向失效：日志真有「IPC AHK 认证成功」却没命中（永远红的守卫同样没用）' }
        if ($r.Bytes -le 0) { $broken += 'P1 正向失效：命中了但扫描字节数为 0' }

        # P2 真正刚写的文件必须算落盘
        $fresh = Join-Path $tmp 'fresh.json'
        [System.IO.File]::WriteAllText($fresh, '{"a":1}', (New-Object System.Text.UTF8Encoding($false)))
        if (-not (Test-FileFresh -Path $fresh -Since $since)) { $broken += 'P2 正向失效：刚写的文件没被判为落盘' }

        # P3 当前 PowerShell 宿主本身必须在进程表里能被找到（证明 StartTime 取得到）
        if (-not (Test-ProcessSince -Names @('powershell', 'pwsh') -Since $since).Found) {
            $broken += 'P3 正向失效：连当前宿主进程都找不到，StartTime 过滤逻辑坏了'
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($broken.Count -gt 0) {
        Write-Host ''
        Write-Host '✗ 守卫自检失败 —— 以下判据是假守卫（不会失败 = 等于没有检查）：' -ForegroundColor Red
        foreach ($b in $broken) { Write-Host "   - $b" -ForegroundColor Red }
        return 2
    }

    Write-Host '✓ 守卫自检通过：5 条负向断言全部如期变红，3 条正向断言全部如期变绿。' -ForegroundColor Green
    Write-Host '  （含义：这些判据在「故意破坏」时会真的失败，不是永远绿的摆设）' -ForegroundColor DarkGray
    return 0
}

if ($SelfCheck) { exit (Invoke-GuardSelfCheck) }

# ═════════════════════════════════════════════════════════════════════════════
# 实跑
# ═════════════════════════════════════════════════════════════════════════════

$script:InstalledByUs  = $false
$script:ChildProcesses = @()
$script:MainProcess    = $null
$runStart              = Get-Date

if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    Write-Host '✗ 参数错误：-InstallerPath 必填（指向 NSIS *.exe）。只想验证判据是否可靠请加 -SelfCheck。' -ForegroundColor Red
    exit 3
}
$installerFull = (Resolve-Path -LiteralPath $InstallerPath -ErrorAction SilentlyContinue).Path
if (-not $installerFull) {
    Write-Host "✗ 环境错误：找不到安装包 '$InstallerPath'" -ForegroundColor Red
    exit 3
}

$appDataDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) $AppIdentifier
$logDir     = $appDataDir            # logging.rs:28-34 → 就在 app_data_dir 根下，无 logs 子目录
$configPath = Join-Path $appDataDir 'config.json'
$exePath    = Join-Path $InstallDir $MainExeName
$mainProcName = [System.IO.Path]::GetFileNameWithoutExtension($MainExeName)

Write-Host '══════ ASD 发布产物冒烟测试 ══════' -ForegroundColor Cyan
Write-Host "安装包     : $installerFull"
Write-Host "安装目录   : $InstallDir"
Write-Host "应用数据   : $appDataDir"
Write-Host "判据       : 日志文件 + 进程表（不做 GUI 截图/像素判断）"
Write-Host ''

$results = New-Object System.Collections.ArrayList

function Add-Criterion {
    param([string]$Id, [string]$Name, [string]$State, [string]$Detail)
    # State: PASS / FAIL / UNVERIFIED
    $null = $results.Add([pscustomobject]@{ Id = $Id; Name = $Name; State = $State; Detail = $Detail })
    $color = switch ($State) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    $mark  = switch ($State) { 'PASS' { '✓' }     'FAIL' { '✗' } default { '?' } }
    Write-Host "[$mark] $Id $Name — $State" -ForegroundColor $color
    Write-Host "      $Detail" -ForegroundColor DarkGray
}

try {
    # ── C1 静默安装 ─────────────────────────────────────────────────────────
    # 清目录失败**不能**打断脚本：它可能只是残留目录被别的进程锁着（并发跑冒烟时撞过），
    # 而 NSIS 会覆盖安装，清不掉不等于装不上。装不上由下面的 C1 判定，别在这里提前判死。
    if (Test-Path -LiteralPath $InstallDir) {
        try { Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop }
        catch { Write-Host "⚠ 清理旧安装目录失败（不致命，继续安装）：$($_.Exception.Message)" -ForegroundColor Yellow }
    }
    if ($InstallDir -match '\s') {
        Write-Host "⚠ 安装目录含空格，NSIS /D 对引号敏感，可能装到别处： $InstallDir" -ForegroundColor Yellow
    }

    # /S = 静默；/D= 必须放最后且不加引号（NSIS 约定）
    $installerArgs = @('/S', "/D=$InstallDir")
    $inst = Start-Process -FilePath $installerFull -ArgumentList $installerArgs -Wait -PassThru
    if ($inst.ExitCode -ne 0) {
        Add-Criterion 'C1' '静默安装' 'FAIL' "安装器退出码 $($inst.ExitCode)（期望 0）"
    }
    elseif (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        Add-Criterion 'C1' '静默安装' 'FAIL' "安装器退出 0，但 $exePath 不存在 —— /D 未被采纳或包内资源缺失"
    }
    else {
        $script:InstalledByUs = $true
        $size = (Get-Item -LiteralPath $exePath).Length
        Add-Criterion 'C1' '静默安装' 'PASS' "$exePath 已就位（$size 字节），退出码 0"
    }

    if (-not $script:InstalledByUs) {
        Write-Host ''
        Write-Host '✗ C1 未通过，后续判据无从谈起，终止。' -ForegroundColor Red
        exit 1
    }

    # ── 启动主程序 ──────────────────────────────────────────────────────────
    $script:MainProcess = Start-Process -FilePath $exePath -PassThru
    Write-Host "已启动主程序 PID=$($script:MainProcess.Id)，等待就绪（超时 ${StartupTimeoutSec}s）..."

    $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
    $c2 = $null; $c4 = $null; $c5 = $null
    do {
        Start-Sleep -Seconds 2
        $c2 = Test-ProcessSince -Names @($mainProcName) -Since $runStart
        # 便携模式打出来的是 AutoHotkey64.exe（asd_executor.exe 未打包），两个都收。
        $c4 = Test-ProcessSince -Names @('asd_executor', 'AutoHotkey64') -Since $runStart
        $c5 = Test-LogContains -LogDir $logDir -Pattern $script:IPC_AUTH_OK -Since $runStart
        if ($script:MainProcess.HasExited) { break }
    } while (-not ($c2.Found -and $c4.Found -and $c5.Found) -and ((Get-Date) -lt $deadline))

    if ($c4.Found) { $script:ChildProcesses = $c4.Matched }

    # ── C2 主程序在进程表 ──────────────────────────────────────────────────
    if ($c2.Found) {
        $p = $c2.Matched[0]
        Add-Criterion 'C2' '主程序在进程表' 'PASS' "$($p.Name) PID=$($p.Id)，启动于 $($p.StartTime)"
    }
    elseif ($script:MainProcess.HasExited) {
        Add-Criterion 'C2' '主程序在进程表' 'FAIL' "主程序已启动但随后退出（退出码 $($script:MainProcess.ExitCode)）—— 装完跑不起来"
    }
    else {
        Add-Criterion 'C2' '主程序在进程表' 'FAIL' "超时 ${StartupTimeoutSec}s 内未在进程表找到 $mainProcName（StartTime >= $runStart）"
    }

    # ── C3 配置落盘 ────────────────────────────────────────────────────────
    $c3State  = 'UNVERIFIED'
    $c3Detail = ''
    if (Test-FileFresh -Path $configPath -Since $runStart) {
        $c3State  = 'PASS'
        $c3Detail = "$configPath 本次运行内已写入（$( (Get-Item -LiteralPath $configPath).Length ) 字节）"
    }
    else {
        $cfgLog = Test-LogContains -LogDir $logDir -Pattern $script:CFG_FALLBACK -Since $runStart
        if ($cfgLog.Found) {
            $c3State  = 'PASS'
            $c3Detail = "配置未落盘（启动不写盘，见 lib.rs:722 / config_cmd.rs:58），但日志显示配置子系统已到达并解析了路径：`"$($cfgLog.Line.Trim())`""
        }
        else {
            $c3Detail = "判定不了：启动阶段不写 config.json（lib.rs:722 只读；唯一写入点 config_cmd.rs:58 由前端 save_config 触发）。"
            $c3Detail += " 实测删掉 config.json 冷启动 30s 仍未重建。日志里也没有「$($script:CFG_FALLBACK)」。"
            $c3Detail += ' 加 -StrictConfig 才会让本条变红。'
        }
    }
    if ($c3State -eq 'UNVERIFIED' -and $StrictConfig) { $c3State = 'FAIL' }
    Add-Criterion 'C3' '配置落盘' $c3State $c3Detail

    # ── C4 AHK 子进程 ─────────────────────────────────────────────────────
    if ($c4.Found) {
        $names = ($c4.Matched | ForEach-Object { "$($_.Name)#$($_.Id)" }) -join ', '
        Add-Criterion 'C4' '拉起 AHK 子进程' 'PASS' "进程表命中：$names（watchdog.rs:288 会打「启动 AHK 子进程」）"
    }
    else {
        Add-Criterion 'C4' '拉起 AHK 子进程' 'FAIL' "超时内未出现 asd_executor.exe / AutoHotkey64.exe（StartTime >= $runStart）"
    }

    # ── C5 IPC 已完成认证 ★ ───────────────────────────────────────────────
    if ($c5.Found) {
        Add-Criterion 'C5' 'IPC 认证完成' 'PASS' "日志命中 ipc.rs:275 的「$($script:IPC_AUTH_OK)」：`"$($c5.Line.Trim())`""
    }
    elseif ($c5.FileCount -eq 0 -or $c5.Bytes -eq 0) {
        Add-Criterion 'C5' 'IPC 认证完成' 'FAIL' "$logDir 下找不到本次运行写过（>$runStart）的 asd.*.log —— 日志系统没起来，判定不了 IPC（按失败处理，不当通过）"
    }
    else {
        Add-Criterion 'C5' 'IPC 认证完成' 'FAIL' "扫过 $($c5.FileCount) 个日志/$($c5.Bytes) 字节，未出现「$($script:IPC_AUTH_OK)」（检查是不是走了 ipc.rs:272 的 token 不匹配 / :295 认证超时）"
    }
}
finally {
    # 清理：先杀主程序（watchdog 会带子进程、也会重启子进程，先杀父才不会被它重新拉起），
    # 再杀本次记录到的子进程。**绝不扫注册表、绝不用 '*ASD*' 之类的模糊匹配决定卸载谁**
    # —— 本机卸载项里含中文与空格，模糊匹配会误伤既有安装（本项目已发生过一次）。
    if (-not $KeepInstalled) {
        if ($null -ne $script:MainProcess -and -not $script:MainProcess.HasExited) {
            Stop-Process -Id $script:MainProcess.Id -Force -ErrorAction SilentlyContinue
        }
        foreach ($p in $script:ChildProcesses) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
        if ($script:InstalledByUs) {
            $uninst = Join-Path $InstallDir 'uninstall.exe'
            if (Test-Path -LiteralPath $uninst) {
                Start-Process -FilePath $uninst -ArgumentList '/S' -Wait -ErrorAction SilentlyContinue | Out-Null
            }
            Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "（-KeepInstalled：保留 $InstallDir 与进程，便于人工看现场）" -ForegroundColor DarkGray
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# 汇总
# ═════════════════════════════════════════════════════════════════════════════
$failed     = @($results | Where-Object { $_.State -eq 'FAIL' }).Count
$unverified = @($results | Where-Object { $_.State -eq 'UNVERIFIED' }).Count

Write-Host ''
Write-Host '══════ 汇总 ══════' -ForegroundColor Cyan
foreach ($r in $results) { Write-Host ("{0,-4} {1,-20} {2,-11} {3}" -f $r.Id, $r.Name, $r.State, $r.Detail) }

if ($env:GITHUB_STEP_SUMMARY) {
    $md = @('### 发布产物冒烟测试', '', '| 判据 | 结果 | 说明 |', '| --- | --- | --- |')
    foreach ($r in $results) { $md += "| $($r.Id) $($r.Name) | $($r.State) | $($r.Detail) |" }
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($md -join "`n")
}

if ($failed -gt 0) {
    Write-Host ''
    Write-Host "✗ 冒烟失败：$failed 条判据未通过（另有 $unverified 条判定不了）。" -ForegroundColor Red
    Write-Host '  这不是「包可能没问题」—— 是「装完跑不起来」，不要发布。' -ForegroundColor Red
    exit 1
}

Write-Host ''
if ($unverified -gt 0) {
    Write-Host "⚠ 冒烟通过，但有 $unverified 条判据拿不到（见上），不能当成已验证。" -ForegroundColor Yellow
}
else {
    Write-Host '✓ 冒烟通过：安装 → 启动 → 拉起 AHK → IPC 认证，全部命中。' -ForegroundColor Green
}
exit 0
