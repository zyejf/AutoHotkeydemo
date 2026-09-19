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
    安装目标目录。默认 $env:TEMP\asd-smoke-install-<随机 8 位>（无空格，避免 NSIS /D 的
    引号坑；每次运行唯一，避免并发跑冒烟时互相清目录）。
    ⚠️ **该目录会被无条件递归删除**：脚本开头清一次、结尾（finally）再删一次，
       判定条件只有「目录存在」，**不看它是不是本次自己建的**。
       因此它**必须位于 $env:TEMP 之下**，否则脚本直接报错退出（exit 3）。
       确有必要指定 TEMP 之外的路径时，必须显式加 -ForceInstallDir 才放行 ——
       这条护栏是为防「手滑把 -InstallDir 指到真实安装目录，一个参数删掉用户安装」
       （本项目已出过一次模糊匹配误卸既有安装的事故）。

.PARAMETER ForceInstallDir
    显式放行「-InstallDir 不在 $env:TEMP 之下」。默认关闭；加之前先确认你知道自己在删什么。

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

    # 见 .PARAMETER ForceInstallDir：放行「-InstallDir 不在 $env:TEMP 之下」。
    [switch]$ForceInstallDir,

    [string]$MainExeName = 'asd-tauri.exe',

    [string]$AppIdentifier = 'com.asd.tauri',

    [int]$StartupTimeoutSec = 60,

    # 主程序起来后至少静置这么久再停掉读日志。IPC 认证在 AHK 起来后 ~1s 内完成，
    # 25s 足够；太短会在认证还没发生时就掐掉进程，制造假红。
    [int]$SettleSec = 25,

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
#      轮转按 UTC 日期命名，所以文件名里的日期与本地日期可能差一天（本机 UTC+8 实测：
#      本地 00:04 启动，文件仍叫 asd.2026-09-19.log）。脚本因此**不按文件名判断**，
#      而是在启动前记下每个日志文件的字节长度做基线，只搜本次运行新增的那段字节。
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

function Get-LogBaseline {
    <#
    记录运行前每个日志文件已有的长度。之后只搜「本次运行新增的那段字节」。
    ⚠️ 这不是洁癖：最初的实现只按 LastWriteTime >= 运行起点筛文件，结果实测
    **误判过**——别人并发跑冒烟时往同一个 asd.*.log 追加内容，文件 mtime 变新，
    于是上一次运行的「…使用默认配置」被当成这次的证据，C3 直接假绿。
    按字节偏移切一刀才能做到「只认本次运行写进去的东西」。
    #>
    param([string]$LogDir)
    $baseline = @{}
    if (Test-Path -LiteralPath $LogDir -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -Filter 'asd.*.log' -File)) {
            $baseline[$f.FullName] = [int]$f.Length
        }
    }
    return $baseline
}

function Test-LogContains {
    param([string]$LogDir, [string]$Pattern, [hashtable]$Baseline)

    $scannedFiles = 0
    $scannedBytes = 0
    $hit = $false
    $hitLine = $null

    if (Test-Path -LiteralPath $LogDir -PathType Container) {
        # @() 包裹是必须的：函数 return 空数组会被 PowerShell 展开成 $null，
        # 后面 .Count 在 Set-StrictMode 下会直接抛「找不到属性 Count」（实测踩到）。
        $files = @(Get-ChildItem -LiteralPath $LogDir -Filter 'asd.*.log' -File)
        foreach ($f in $files) {
            $base = 0
            if ($Baseline.ContainsKey($f.FullName)) { $base = [int]$Baseline[$f.FullName] }
            # ⚠️ 应用在运行时对日志文件持有独占句柄，直接读会抛
            #   「文件正由另一进程使用」（实测踩到过）。重试几次等它松手；
            #   始终读不到就跳过这个文件 —— 由调用方按「判定不了」处理，绝不当通过。
            $raw = $null
            for ($retry = 0; $retry -lt 6; $retry++) {
                try { $raw = [System.IO.File]::ReadAllBytes($f.FullName); break }
                catch { Start-Sleep -Milliseconds 500 }
            }
            if ($null -eq $raw) { continue }

            # 本次运行没往这个文件里追加任何字节 → 跳过（轮转后变短也算没追加）
            if ($raw.Length -le $base) { continue }

            $scannedFiles++
            $newLen = $raw.Length - $base
            $scannedBytes += $newLen
            # 显式 UTF8 解码，避免 PS 5.1 默认编码把中文匹配成永远不命中（那也是一种假守卫）。
            $text = [System.Text.Encoding]::UTF8.GetString($raw, $base, $newLen)
            foreach ($line in ($text -split "`n")) {
                if ($line.Contains($Pattern)) { $hit = $true; $hitLine = $line; break }
            }
            if ($hit) { break }
        }
    }

    return [pscustomobject]@{
        Found     = $hit
        FileCount = $scannedFiles
        Bytes     = $scannedBytes
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

# 取证据包字段：缺字段返回默认值。
# 用显式 ContainsKey 而不是 $Pack[$Key] —— Set-StrictMode 下要的是「缺了就是缺了」的
# 确定性行为，不能让一个笔误悄悄变成 $null 再被判定成 PASS。
function Get-Ev {
    param([hashtable]$Pack, [string]$Key, $Default = $null)
    if ($Pack.ContainsKey($Key)) { return $Pack[$Key] }
    return $Default
}

# 从判据结果里按 Id 取一条；取不到返回 $null（调用方必须显式处理，不许默认当成 PASS）。
function Get-StateOf {
    param($States, [string]$Id)
    $m = @($States | Where-Object { $_.Id -eq $Id })
    if ($m.Count -eq 0) { return $null }
    return $m[0]
}

function Get-CriterionStates {
    <#
    .SYNOPSIS
        C1–C5 的**状态计算**：纯函数 —— 只读证据包，不碰磁盘 / 进程 / 网络 / 时钟。

    .DESCRIPTION
        把判定从主流程里抽出来，唯一目的是**让它能被 -SelfCheck 双向对照**。

        为什么非抽不可：原先判定散在主流程的 if/else 里，-SelfCheck 够不着，于是
        「把 `if ($c5.Found)` 改成 `if ($true)`」这种变异能一路绿到底 —— 而 C5 恰恰是
        最关键的那条。抽成纯函数后，同一个变异会被自检点名拦下（见 Invoke-GuardSelfCheck）。

        入参 $Evidence 是 hashtable，字段见各处 Get-Ev 调用；缺字段取默认值。
        出参：5 个对象，每个含 Id / Name / State(PASS|FAIL|UNVERIFIED) / Detail。
    #>
    param([Parameter(Mandatory = $true)][hashtable]$Evidence)

    $out = New-Object System.Collections.ArrayList
    $runStartText = [string](Get-Ev $Evidence 'RunStartText' '')

    # ── C1 静默安装后主 exe 存在 ────────────────────────────────────────────
    $exitCode   = [int](Get-Ev $Evidence 'InstallExitCode' -1)
    $mainExe    = [string](Get-Ev $Evidence 'MainExePath' '')
    $mainExists = [bool](Get-Ev $Evidence 'MainExeExists' $false)
    $mainSize   = [long](Get-Ev $Evidence 'MainExeSize' 0)
    if ($exitCode -ne 0) {
        $c1State = 'FAIL'; $c1Detail = "安装器退出码 $exitCode（期望 0）"
    }
    elseif (-not $mainExists) {
        $c1State = 'FAIL'; $c1Detail = "安装器退出 0，但 $mainExe 不存在 —— /D 未被采纳或包内资源缺失"
    }
    else {
        $c1State = 'PASS'; $c1Detail = "$mainExe 已就位（$mainSize 字节），退出码 0"
    }
    $null = $out.Add([pscustomobject]@{ Id = 'C1'; Name = '静默安装'; State = $c1State; Detail = $c1Detail })

    # ── C2 主程序在进程表 ──────────────────────────────────────────────────
    $procFound  = [bool](Get-Ev $Evidence 'MainProcFound' $false)
    $procName   = [string](Get-Ev $Evidence 'MainProcName' '')
    $procId     = [int](Get-Ev $Evidence 'MainProcId' 0)
    $procStart  = [string](Get-Ev $Evidence 'MainProcStart' '')
    $mainExited = [bool](Get-Ev $Evidence 'MainExited' $false)
    $mainExitCd = [int](Get-Ev $Evidence 'MainExitCode' -1)
    $timeout    = [int](Get-Ev $Evidence 'StartupTimeoutSec' 0)
    if ($procFound) {
        $c2State = 'PASS'; $c2Detail = "$procName PID=$procId，启动于 $procStart"
    }
    elseif ($mainExited) {
        $c2State = 'FAIL'; $c2Detail = "主程序已启动但随后退出（退出码 $mainExitCd）—— 装完跑不起来"
    }
    else {
        $c2State = 'FAIL'; $c2Detail = "超时 ${timeout}s 内未在进程表找到 $procName（StartTime >= $runStartText）"
    }
    $null = $out.Add([pscustomobject]@{ Id = 'C2'; Name = '主程序在进程表'; State = $c2State; Detail = $c2Detail })

    # ── C3 配置落盘（默认只报 UNVERIFIED，见文件头 C3 说明）──────────────────
    $cfgFresh    = [bool](Get-Ev $Evidence 'ConfigFresh' $false)
    $cfgPath     = [string](Get-Ev $Evidence 'ConfigPath' '')
    $cfgSize     = [long](Get-Ev $Evidence 'ConfigSize' 0)
    $cfgFallback = [bool](Get-Ev $Evidence 'ConfigFallbackFound' $false)
    $cfgLine     = [string](Get-Ev $Evidence 'ConfigFallbackLine' '')
    $cfgPattern  = [string](Get-Ev $Evidence 'CfgFallbackPattern' '')
    $strictCfg   = [bool](Get-Ev $Evidence 'StrictConfig' $false)
    if ($cfgFresh) {
        $c3State = 'PASS'; $c3Detail = "$cfgPath 本次运行内已写入（$cfgSize 字节）"
    }
    elseif ($cfgFallback) {
        $c3State = 'PASS'
        $c3Detail = "配置未落盘（启动不写盘，见 lib.rs:722 / config_cmd.rs:58），但日志显示配置子系统已到达并解析了路径：`"$($cfgLine.Trim())`""
    }
    else {
        $c3State = 'UNVERIFIED'
        $c3Detail = "判定不了：启动阶段不写 config.json（lib.rs:722 只读；唯一写入点 config_cmd.rs:58 由前端 save_config 触发）。"
        $c3Detail += " 实测删掉 config.json 冷启动 30s 仍未重建。日志里也没有「$cfgPattern」。"
        $c3Detail += ' 加 -StrictConfig 才会让本条变红。'
    }
    if ($c3State -eq 'UNVERIFIED' -and $strictCfg) { $c3State = 'FAIL' }
    $null = $out.Add([pscustomobject]@{ Id = 'C3'; Name = '配置落盘'; State = $c3State; Detail = $c3Detail })

    # ── C4 AHK 子进程 ─────────────────────────────────────────────────────
    $ahkFound = [bool](Get-Ev $Evidence 'AhkFound' $false)
    $ahkNames = [string](Get-Ev $Evidence 'AhkNames' '')
    if ($ahkFound) {
        $c4State = 'PASS'; $c4Detail = "进程表命中：$ahkNames（watchdog.rs:288 会打「启动 AHK 子进程」）"
    }
    else {
        $c4State = 'FAIL'; $c4Detail = "超时内未出现 asd_executor.exe / AutoHotkey64.exe（StartTime >= $runStartText）"
    }
    $null = $out.Add([pscustomobject]@{ Id = 'C4'; Name = '拉起 AHK 子进程'; State = $c4State; Detail = $c4Detail })

    # ── C5 IPC 已完成认证 ★ ───────────────────────────────────────────────
    $authFound = [bool](Get-Ev $Evidence 'AuthFound' $false)
    $authLine  = [string](Get-Ev $Evidence 'AuthLine' '')
    $authFiles = [int](Get-Ev $Evidence 'AuthFileCount' 0)
    $authBytes = [long](Get-Ev $Evidence 'AuthBytes' 0)
    $authPat   = [string](Get-Ev $Evidence 'AuthPattern' '')
    $logDirTxt = [string](Get-Ev $Evidence 'LogDir' '')
    if ($authFound) {
        $c5State = 'PASS'; $c5Detail = "日志命中 ipc.rs:275 的「$authPat」：`"$($authLine.Trim())`""
    }
    elseif ($authFiles -eq 0 -or $authBytes -eq 0) {
        $c5State = 'FAIL'
        $c5Detail = "$logDirTxt 下没有任何 asd.*.log 在本次运行期间新增字节 —— 日志系统没起来，判定不了 IPC（按失败处理，不当通过）"
    }
    else {
        $c5State = 'FAIL'
        $c5Detail = "扫过 $authFiles 个日志/$authBytes 字节，未出现「$authPat」（检查是不是走了 ipc.rs:272 的 token 不匹配 / :295 认证超时）"
    }
    $null = $out.Add([pscustomobject]@{ Id = 'C5'; Name = 'IPC 认证完成'; State = $c5State; Detail = $c5Detail })

    return $out.ToArray()
}

function Get-SmokeVerdict {
    <#
    .SYNOPSIS
        汇总层判定：只读判据结果数组，算出计数与**退出码**。纯函数，不碰磁盘 / 进程 / 时钟。

    .DESCRIPTION
        为什么还要单独抽一层：Get-CriterionStates 守的是「判据会不会红」，这一层守的是
        **「红了算不算数」**。两者是不同的失败模式，后者更致命 ——

        最危险的场景不是判据不红，而是：所有判据都忠实地报 FAIL，汇总处一句
        `$failed = 0` 就让整个冒烟报成功。判据层怎么双向对照都拦不住它，因为它
        根本没发生在判据层。这和 G3h「CI 跑 `cargo test -- --ignored`、仓库零条
        #[ignore]、每次 0 tests 恒绿」是同一个病，只是换到了汇总层发作。

    .OUTPUTS
        PSCustomObject：Failed / Unverified / Passed / Total / ExitCode

        退出码契约：
            有 FAIL            → 1  （判据未通过，不许发布）
            无 FAIL            → 0  （含「只有 UNVERIFIED」：现状只警告不失败）
            一条判据都没有      → 2  （内部错误）
        ⚠️ 2 与「守卫自检失败」共用退出码，语义是一致的：**脚本自己坏了**，
           不是产品坏了。空的判据集绝不能算 0 —— 「什么都没跑」不是「跑过了」。
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$States)

    # @() 包裹：$States 为空集合时，管道结果会被 PowerShell 展开成 $null，
    # 后面 .Count 在 Set-StrictMode 下会抛（本文件 Test-LogContains 处踩过同一个坑）。
    $arr        = @($States)
    $failed     = @($arr | Where-Object { $_.State -eq 'FAIL' }).Count
    $unverified = @($arr | Where-Object { $_.State -eq 'UNVERIFIED' }).Count
    $passed     = @($arr | Where-Object { $_.State -eq 'PASS' }).Count

    if ($arr.Count -eq 0) { $code = 2 }
    elseif ($failed -gt 0) { $code = 1 }
    else { $code = 0 }

    return [pscustomobject]@{
        Failed     = $failed
        Unverified = $unverified
        Passed     = $passed
        Total      = $arr.Count
        ExitCode   = $code
    }
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
        $r = Test-LogContains -LogDir $tmp -Pattern $script:IPC_AUTH_OK -Baseline @{}
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
        $r = Test-LogContains -LogDir $emptyDir -Pattern $script:IPC_AUTH_OK -Baseline @{}
        if ($r.Found -or $r.Bytes -ne 0) { $broken += 'N5 负向失效：空日志目录被判为命中' }

        # ── 正向：好输入必须返回 GREEN ──────────────────────────────────────
        # P1 真有「认证成功」时必须命中
        $goodLog = Join-Path $tmp 'asd.2026-01-02.log'
        [System.IO.File]::WriteAllText($goodLog,
            "2026-01-02T00:00:00Z  INFO ThreadId(14) asd_tauri_lib::infrastructure::ipc: src-tauri\src\infrastructure\ipc.rs:275: IPC AHK 认证成功`n",
            (New-Object System.Text.UTF8Encoding($false)))
        $r = Test-LogContains -LogDir $tmp -Pattern $script:IPC_AUTH_OK -Baseline @{}
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

        # ── C1–C5 的判据组装：坏证据包必须变红 / 好证据包必须变绿 ────────────────
        # ⚠️ 这一段补的是**覆盖缺口**：在此之前 -SelfCheck 只喂上面 3 个辅助函数，
        #    主流程的判据组装完全没被覆盖 —— 实测把 `if ($c5.Found)` 改成 `if ($true)`，
        #    自检照样 exit 0。现在判定住在 Get-CriterionStates 里，同一个变异拦得住。
        $badPack = @{
            InstallExitCode = 1
            MainExePath     = 'X:\nope\asd-tauri.exe'
            MainExeExists   = $false
            MainExeSize     = 0
            MainProcFound   = $false
            MainProcName    = 'asd-tauri'
            MainProcId      = 0
            MainProcStart   = ''
            MainExited      = $true
            MainExitCode    = 1
            StartupTimeoutSec = 60
            RunStartText    = 'T0'
            ConfigFresh     = $false
            ConfigPath      = 'X:\nope\config.json'
            ConfigSize      = 0
            ConfigFallbackFound = $false
            ConfigFallbackLine  = ''
            CfgFallbackPattern  = $script:CFG_FALLBACK
            StrictConfig    = $false
            AhkFound        = $false
            AhkNames        = ''
            AuthFound       = $false
            AuthLine        = ''
            AuthFileCount   = 0
            AuthBytes       = 0
            AuthPattern     = $script:IPC_AUTH_OK
            LogDir          = 'X:\nope'
        }
        $goodPack = @{
            InstallExitCode = 0
            MainExePath     = 'C:\Temp\asd-smoke\asd-tauri.exe'
            MainExeExists   = $true
            MainExeSize     = 123456
            MainProcFound   = $true
            MainProcName    = 'asd-tauri'
            MainProcId      = 4242
            MainProcStart   = 'T0'
            MainExited      = $false
            MainExitCode    = 0
            StartupTimeoutSec = 60
            RunStartText    = 'T0'
            ConfigFresh     = $false
            ConfigPath      = 'C:\Temp\cfg\config.json'
            ConfigSize      = 0
            ConfigFallbackFound = $true
            ConfigFallbackLine  = '配置文件不存在（首次启动），使用默认配置'
            CfgFallbackPattern  = $script:CFG_FALLBACK
            StrictConfig    = $false
            AhkFound        = $true
            AhkNames        = 'AutoHotkey64#1234'
            AuthFound       = $true
            AuthLine        = 'INFO asd_tauri_lib::infrastructure::ipc: ipc.rs:275: IPC AHK 认证成功'
            AuthFileCount   = 1
            AuthBytes       = 2048
            AuthPattern     = $script:IPC_AUTH_OK
            LogDir          = 'C:\Temp\logs'
        }

        $badStates  = @(Get-CriterionStates -Evidence $badPack)
        $goodStates = @(Get-CriterionStates -Evidence $goodPack)

        # C1 / C2 / C4 / C5：坏包必须 FAIL，好包必须 PASS。
        foreach ($id in @('C1', 'C2', 'C4', 'C5')) {
            $b = Get-StateOf $badStates  $id
            $g = Get-StateOf $goodStates $id
            if ($null -eq $b -or $null -eq $g) {
                $broken += "M$id 缺失：Get-CriterionStates 根本没返回 $id 这条判据"
                continue
            }
            if ($b.State -ne 'FAIL') {
                $broken += "M$id 负向失效：喂坏证据包时 $id 应为 FAIL，实际 $($b.State) —— 该判据恒绿，是假守卫"
            }
            if ($g.State -ne 'PASS') {
                $broken += "M$id 正向失效：喂好证据包时 $id 应为 PASS，实际 $($g.State) —— 该判据恒红，同样没用"
            }
        }

        # C3 单独处理：它的坏包按**设计**是 UNVERIFIED（「拿不到稳定判据」是刻意的，
        # 见文件头 C3 说明），硬断言 FAIL 会与设计自相矛盾。三档：
        #   ① 坏包必须「不是 PASS」（恒绿会被抓住）
        #   ② 好包必须 PASS（恒红会被抓住）
        #   ③ 坏包 + StrictConfig 必须 FAIL（否则 -StrictConfig 这个开关是摆设）
        $c3Bad  = Get-StateOf $badStates  'C3'
        $c3Good = Get-StateOf $goodStates 'C3'
        if ($null -eq $c3Bad -or $null -eq $c3Good) {
            $broken += 'MC3 缺失：Get-CriterionStates 根本没返回 C3 这条判据'
        }
        else {
            if ($c3Bad.State -eq 'PASS') {
                $broken += 'MC3 负向失效：喂坏证据包时 C3 不该 PASS（按设计应为 UNVERIFIED），实际 PASS —— 恒绿假守卫'
            }
            if ($c3Good.State -ne 'PASS') {
                $broken += "MC3 正向失效：喂好证据包时 C3 应为 PASS，实际 $($c3Good.State) —— 恒红同样没用"
            }
            $strictPack = @{}
            foreach ($k in $badPack.Keys) { $strictPack[$k] = $badPack[$k] }
            $strictPack['StrictConfig'] = $true
            $c3Strict = Get-StateOf @(Get-CriterionStates -Evidence $strictPack) 'C3'
            if ($null -eq $c3Strict) {
                $broken += 'MC3s 缺失：StrictConfig 证据包没返回 C3'
            }
            elseif ($c3Strict.State -ne 'FAIL') {
                $broken += "MC3s 失效：坏证据包 + StrictConfig 时 C3 应为 FAIL，实际 $($c3Strict.State) —— -StrictConfig 开关是摆设"
            }
        }

        # ── 汇总层：判据红了，算不算数 ──────────────────────────────────────
        # ⚠️ 这一段守的**不是**「判据会不会红」（上面 MC1–MC3s 管），而是
        #    「红了算不算数」。变异 D（把 $failed 算成 0）此前能一路绿 ——
        #    所有判据都忠实报 FAIL，汇总一句 $failed = 0 就让冒烟报成功。
        #    这与 G3h「0 tests 恒绿」同病，只是发生在汇总层。
        $vPass = Get-SmokeVerdict -States @(
            [pscustomobject]@{ Id = 'C1'; State = 'PASS' }
            [pscustomobject]@{ Id = 'C2'; State = 'PASS' }
        )
        if ($vPass.Failed -ne 0) { $broken += "MD1 计数错：全 PASS 的包 Failed 应为 0，实际 $($vPass.Failed)" }
        if ($vPass.ExitCode -ne 0) { $broken += "MD1 正向失效：全 PASS 的包应 exit 0，实际 $($vPass.ExitCode)（永远红的汇总同样没用）" }

        $vFail = Get-SmokeVerdict -States @(
            [pscustomobject]@{ Id = 'C1'; State = 'PASS' }
            [pscustomobject]@{ Id = 'C5'; State = 'FAIL' }
        )
        if ($vFail.Failed -ne 1) {
            $broken += "MD2 计数错：含 1 条 FAIL 的包 Failed 应为 1，实际 $($vFail.Failed) —— 判据红了但没被数进去"
        }
        if ($vFail.ExitCode -eq 0) {
            $broken += 'MD2 负向失效：包里有 FAIL 却算出 exit 0 —— 汇总层恒绿，判据再忠实也白搭（G3h「0 tests 恒绿」的同类病）'
        }

        # 只有 UNVERIFIED（无 FAIL）：现状是「警告但仍 exit 0」，这条断言把这个契约钉住，
        # 免得哪天被顺手改成失败而没人注意（那会让 C3 的 UNVERIFIED 直接卡发布）。
        $vUnv = Get-SmokeVerdict -States @(
            [pscustomobject]@{ Id = 'C1'; State = 'PASS' }
            [pscustomobject]@{ Id = 'C3'; State = 'UNVERIFIED' }
        )
        if ($vUnv.ExitCode -ne 0) {
            $broken += "MD3 失效：只有 UNVERIFIED、没有 FAIL 时应 exit 0（现状仅警告），实际 $($vUnv.ExitCode)"
        }
        if ($vUnv.Unverified -ne 1) {
            $broken += "MD3 计数错：含 1 条 UNVERIFIED 的包 Unverified 应为 1，实际 $($vUnv.Unverified)"
        }

        # 空判据集绝不能算成功 —— 「什么都没跑」不是「跑过了」。
        $vEmpty = Get-SmokeVerdict -States @()
        if ($vEmpty.ExitCode -eq 0) {
            $broken += 'MD4 负向失效：一条判据都没有却算出 exit 0 —— 「什么都没跑」被当成通过'
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

    Write-Host '✓ 守卫自检通过（三层都过）：' -ForegroundColor Green
    Write-Host '  · 辅助函数层：5 条负向断言如期变红 + 3 条正向断言如期变绿（N1-N5 / P1-P3）' -ForegroundColor DarkGray
    Write-Host '  · 判据组装层：C1/C2/C4/C5 坏包必 FAIL、好包必 PASS；C3 坏包非 PASS、好包 PASS，' -ForegroundColor DarkGray
    Write-Host '                且坏包 + -StrictConfig 必 FAIL' -ForegroundColor DarkGray
    Write-Host '  · 汇总层：含 FAIL 的包必 exit 非 0、全 PASS 必 exit 0、空判据集必 exit 非 0' -ForegroundColor DarkGray
    Write-Host '  （含义：判据在「故意破坏」时会真的失败，且失败会真的反映到退出码上 ——' -ForegroundColor DarkGray
    Write-Host '    「判据会红」和「红了算不算数」是两件事，两层都验了）' -ForegroundColor DarkGray
    return 0
}

if ($SelfCheck) { exit (Invoke-GuardSelfCheck) }

# ═════════════════════════════════════════════════════════════════════════════
# 实跑
# ═════════════════════════════════════════════════════════════════════════════

$script:InstalledByUs  = $false
$script:LogBaseline    = @{}
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

# ── -InstallDir 安全护栏 ───────────────────────────────────────────────────
# 本脚本会在开头与结尾（finally）两次 `Remove-Item -Recurse -Force $InstallDir`，
# 且**只判目录是否存在，不判它是不是本次自己建的**。手滑把 -InstallDir 指到真实安装
# 目录 = 一个参数删掉用户安装（本项目已出过一次模糊匹配误卸既有安装的事故）。
# 因此默认只允许 TEMP 之下的路径；要 TEMP 之外的路径必须显式 -ForceInstallDir。
#
# ⚠️ 这条护栏**不完备**，已知边界（别把前缀检查当成完备的归属校验）：
#    判的是「归一化后的路径字符串是否落在 TEMP 之下」，**不解析重解析点**。
#    若 TEMP 之下存在目录联接 / 符号链接指向别处，字符串检查会放行，实际删除行为
#    取决于 Remove-Item -Recurse 对重解析点的处理（本脚本没有做链接解析，也没测过
#    这种布局）。这是「防止手滑」的护栏，不是安全边界。
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    Write-Host '✗ 参数错误：-InstallDir 不能为空。' -ForegroundColor Red
    exit 3
}
$tempRoot    = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$installFull = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
$underTemp   = $installFull.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
if (-not $underTemp) {
    if (-not $ForceInstallDir) {
        Write-Host '✗ 参数错误：-InstallDir 不在 TEMP 之下，拒绝执行（防止误删真实安装目录）。' -ForegroundColor Red
        Write-Host "    -InstallDir : $installFull" -ForegroundColor Red
        Write-Host "    允许的根    : $tempRoot" -ForegroundColor Red
        Write-Host '    原因：该目录会被**无条件递归删除**，判定条件只有「目录存在」。' -ForegroundColor Red
        Write-Host '    确需指定 TEMP 之外的路径时，显式加 -ForceInstallDir。' -ForegroundColor Red
        exit 3
    }
    Write-Host "⚠ -ForceInstallDir 已开启：稍后将无条件递归删除 $installFull" -ForegroundColor Yellow
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

# 证据包：判定所需的一切都装在这里；判定本身由纯函数 Get-CriterionStates 做。
# ⚠️ 主流程**只负责**「跑副作用 + 填证据包 + 打印」，不再自己 if/else 判 PASS/FAIL ——
#    判定一旦散落在主流程里，-SelfCheck 就够不着，变异能一路绿（见 Get-CriterionStates 注释）。
$ev = @{
    InstallExitCode     = -1
    MainExePath         = $exePath
    MainExeExists       = $false
    MainExeSize         = 0
    MainProcFound       = $false
    MainProcName        = $mainProcName
    MainProcId          = 0
    MainProcStart       = ''
    MainExited          = $false
    MainExitCode        = -1
    StartupTimeoutSec   = $StartupTimeoutSec
    RunStartText        = $runStart.ToString('HH:mm:ss')
    ConfigFresh         = $false
    ConfigPath          = $configPath
    ConfigSize          = 0
    ConfigFallbackFound = $false
    ConfigFallbackLine  = ''
    CfgFallbackPattern  = $script:CFG_FALLBACK
    StrictConfig        = [bool]$StrictConfig
    AhkFound            = $false
    AhkNames            = ''
    AuthFound           = $false
    AuthLine            = ''
    AuthFileCount       = 0
    AuthBytes           = 0
    AuthPattern         = $script:IPC_AUTH_OK
    LogDir              = $logDir
}

# 把纯函数判出的结果落到 $results 并打印。$Only 为空表示全打。
function Add-States {
    param($States, [string[]]$Only = @())
    foreach ($s in $States) {
        if ($Only.Count -gt 0 -and ($Only -notcontains $s.Id)) { continue }
        Add-Criterion -Id $s.Id -Name $s.Name -State $s.State -Detail $s.Detail
    }
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
    $ev['InstallExitCode'] = [int]$inst.ExitCode
    if (Test-Path -LiteralPath $exePath -PathType Leaf) {
        $ev['MainExeExists'] = $true
        $ev['MainExeSize']   = [long](Get-Item -LiteralPath $exePath).Length
    }

    # 运行时证据还没有，先只判 C1。⚠️ 判定仍走纯函数，不在这里写 if/else ——
    #    主流程里每多一个判定谓词，-SelfCheck 就少覆盖一处。
    $c1Obj = Get-StateOf @(Get-CriterionStates -Evidence $ev) 'C1'
    if ($null -ne $c1Obj) {
        Add-States @($c1Obj) -Only @('C1')
        if ($c1Obj.State -eq 'PASS') { $script:InstalledByUs = $true }
    }

    if (-not $script:InstalledByUs) {
        Write-Host ''
        Write-Host '✗ C1 未通过，后续判据无从谈起，终止。' -ForegroundColor Red
        exit 1
    }

    # ── 启动主程序 ──────────────────────────────────────────────────────────
    # 必须在启动**之前**记下日志基线，否则会把上一次运行的日志当成这次的证据。
    $script:LogBaseline = Get-LogBaseline -LogDir $logDir
    $script:MainProcess = Start-Process -FilePath $exePath -PassThru
    Write-Host "已启动主程序 PID=$($script:MainProcess.Id)，等待就绪（超时 ${StartupTimeoutSec}s）..."

    $deadline    = (Get-Date).AddSeconds($StartupTimeoutSec)
    $settleUntil = (Get-Date).AddSeconds($SettleSec)
    $c2 = $null; $c4 = $null
    # 区分「自己提前挂了」和「我们主动停的」—— 后面要亲手停它，不能拿 HasExited 判死活。
    $exitedEarly = $false
    do {
        Start-Sleep -Seconds 2
        $c2 = Test-ProcessSince -Names @($mainProcName) -Since $runStart
        # 便携模式打出来的是 AutoHotkey64.exe（asd_executor.exe 未打包），两个都收。
        $c4 = Test-ProcessSince -Names @('asd_executor', 'AutoHotkey64') -Since $runStart
        if ($script:MainProcess.HasExited) { $exitedEarly = $true; break }
    } while ((-not ($c2.Found -and $c4.Found) -or ((Get-Date) -lt $settleUntil)) -and ((Get-Date) -lt $deadline))

    if ($c4.Found) { $script:ChildProcesses = $c4.Matched }

    # ── 先停主程序，再读日志 ────────────────────────────────────────────────
    # ⚠️ 顺序不能反：应用对 asd.*.log 持有独占句柄，跑着的时候读必然抛
    #   「文件正由另一进程使用」（实测踩到）。停掉后句柄释放才能读。
    #   C2/C4 是进程判据，已在上面进程还活着时取到；C3/C5 是日志判据，放到这里读。
    if ($null -ne $script:MainProcess -and -not $script:MainProcess.HasExited) {
        Stop-Process -Id $script:MainProcess.Id -Force -ErrorAction SilentlyContinue
    }
    foreach ($p in $script:ChildProcesses) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2    # 等日志文件句柄真正释放
    $c5 = Test-LogContains -LogDir $logDir -Pattern $script:IPC_AUTH_OK -Baseline $script:LogBaseline

    # ── 把运行时证据填进证据包（判定交给纯函数，这里不做任何 PASS/FAIL 判断）──────
    # ⚠️ 「主程序是不是自己退出的」必须用 $exitedEarly，**不能**用 $script:MainProcess.HasExited：
    #    上面刚由**我们自己**把主程序停掉（为释放日志文件句柄），此刻 HasExited 恒为 true，
    #    拿它当证据会把「我们杀的」误判成「它自己崩的」——一个必然误报的假判据。
    if ($c2.Found) {
        $p = $c2.Matched[0]
        $ev['MainProcFound'] = $true
        $ev['MainProcId']    = [int]$p.Id
        $ev['MainProcStart'] = [string]$p.StartTime
    }
    $ev['MainExited'] = [bool]$exitedEarly
    if ($exitedEarly) { $ev['MainExitCode'] = [int]$script:MainProcess.ExitCode }

    if (Test-FileFresh -Path $configPath -Since $runStart) {
        $ev['ConfigFresh'] = $true
        $ev['ConfigSize']  = [long](Get-Item -LiteralPath $configPath).Length
    }
    else {
        $cfgLog = Test-LogContains -LogDir $logDir -Pattern $script:CFG_FALLBACK -Baseline $script:LogBaseline
        if ($cfgLog.Found) {
            $ev['ConfigFallbackFound'] = $true
            $ev['ConfigFallbackLine']  = [string]$cfgLog.Line
        }
    }

    if ($c4.Found) {
        $ev['AhkFound'] = $true
        $ev['AhkNames'] = (($c4.Matched | ForEach-Object { "$($_.Name)#$($_.Id)" }) -join ', ')
    }

    $ev['AuthFound']     = [bool]$c5.Found
    $ev['AuthLine']      = [string]$c5.Line
    $ev['AuthFileCount'] = [int]$c5.FileCount
    $ev['AuthBytes']     = [long]$c5.Bytes

    # ── C2–C5 一次性由纯函数判出（证据齐了，5 条一起算）────────────────────
    Add-States @(Get-CriterionStates -Evidence $ev) -Only @('C2', 'C3', 'C4', 'C5')
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
# ⚠️ 汇总与退出码一律走纯函数 Get-SmokeVerdict，**不在这里就地算** ——
#    这里每多写一个聚合表达式，-SelfCheck 就少覆盖一处。变异 D（把 $failed 算成 0）
#    正是从这个位置溜过去的：判据全对，汇总一句谎，冒烟报成功。
$verdict    = Get-SmokeVerdict -States $results
$failed     = $verdict.Failed
$unverified = $verdict.Unverified

if ($verdict.Total -eq 0) {
    Write-Host ''
    Write-Host '✗ 内部错误：一条判据都没算出来，绝不当成通过。' -ForegroundColor Red
    exit $verdict.ExitCode
}

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
    exit $verdict.ExitCode
}

Write-Host ''
if ($unverified -gt 0) {
    Write-Host "⚠ 冒烟通过，但有 $unverified 条判据拿不到（见上），不能当成已验证。" -ForegroundColor Yellow
}
else {
    Write-Host '✓ 冒烟通过：安装 → 启动 → 拉起 AHK → IPC 认证，全部命中。' -ForegroundColor Green
}
exit $verdict.ExitCode
