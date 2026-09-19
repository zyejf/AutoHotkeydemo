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
#   · C1–C5 的运行时路径：⚠️ **2026-09-20 01:00 订正 —— 上面「从未跑过一次完整闭环」这句已被证伪**，
#     保留痕迹如下：本机用真实 NSIS 包（target/debug/bundle/nsis/ASD - 技能管理器_0.1.0_x64-setup.exe）
#     连跑 2 次，均 exit 0，C1/C2/C4/C5 = PASS（C3 仍 UNVERIFIED —— 跑通不会让它自动变绿）。
#     **但这不能读成「发布链路已验证」**，三条限制照旧成立：
#       ① 曾用 2026-09-18 22:00 构建的**旧包**跑过 2 次（物证：日志打 `ipc.rs:211`，
#          而当前源码该串在 `ipc.rs:275`）。⚠️ **2026-09-20 01:49 已重跑并覆盖该结论**：
#          用 **HEAD 新构建**的包（4,632,300 字节 / mtime 01:47:04）重跑，**exit 0**，
#          C5 日志命中 **`ipc.rs:275`** —— 绿灯现在属于 HEAD，不再只是旧包。
#          「换包后必须重跑」这条规矩不变：**行号就是可机读的取证锚点**，
#          拿旧包日志给新包背书等同于伪造证据；
#       ② 只跑过 debug 包，**release 包从未产出过**；
#       ③ 判据取自日志与进程表，**不覆盖 GUI 可操作性**（TD-083 那一类仍需人工点）。
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

    # ── C1 静默安装后主 exe 存在 + AHK 资源齐全 ─────────────────────────────
    $exitCode   = [int](Get-Ev $Evidence 'InstallExitCode' -1)
    $mainExe    = [string](Get-Ev $Evidence 'MainExePath' '')
    $mainExists = [bool](Get-Ev $Evidence 'MainExeExists' $false)
    $mainSize   = [long](Get-Ev $Evidence 'MainExeSize' 0)
    $ahkRes     = [string](Get-Ev $Evidence 'AhkResourcePath' '')
    $ahkResOk   = [bool](Get-Ev $Evidence 'AhkResourceExists' $false)
    if ($exitCode -ne 0) {
        $c1State = 'FAIL'; $c1Detail = "安装器退出码 $exitCode（期望 0）"
    }
    elseif (-not $mainExists) {
        $c1State = 'FAIL'; $c1Detail = "安装器退出 0，但 $mainExe 不存在 —— /D 未被采纳或包内资源缺失"
    }
    elseif (-not $ahkResOk) {
        # ⚠️ 这一条是**打包/安装层**的判据，不是运行时的。少了它，安装目录只落了主 exe
        #    时 C1 照样 PASS，脚本会继续启动，然后在 C4/C5 报「拉不起 AHK / IPC 没认证」
        #    —— 真正的原因（资源没打进包）被伪装成运行时缺陷，排障被引偏。
        # ⚠️ **失败归因必须跟着 Verdict 走**（2026-09-20 补，team-lead 批）。
        #    只读 $ahkResOk 的话，「资源曾就位、之后被删」（Vanished）也会被写成
        #    「打包/安装层缺陷」—— 那是同一种引偏，只是引到了另一侧。
        #    Verdict 由 Get-AhkResourceStability 从采样序列算出。
        #    ⚠️ **判据本身（PASS/FAIL）不看 Verdict**：这里只改「失败时说什么」，
        #       C1 的 PASS/FAIL 语义与加 Verdict 之前逐字相同（由 MC1r 钉住）。
        $ahkVerdict = [string](Get-Ev $Evidence 'AhkResourceVerdict' 'Missing')
        $ahkDirOk   = [bool](Get-Ev $Evidence 'AhkResourceDirExists' $false)
        $ahkTrace   = [string](Get-Ev $Evidence 'AhkResourceTrace' '')
        $ahkPaths   = [string](Get-Ev $Evidence 'AhkResourcePathTrace' '')
        $c1State = 'FAIL'
        $c1Detail = "安装器退出 0、$mainExe 已就位，但 $ahkRes 在采样窗口内没有做到「次次都在」（5 次 × 8ms，观测窗口 ≈32ms；轨迹 $ahkTrace）。"
        if ($ahkVerdict -eq 'Vanished') {
            $c1Detail += ' 归因：**资源曾就位、之后消失** —— 有东西在删安装目录（清理器 / 竞态），'
            $c1Detail += '**不是**「资源没打进包」。先查谁在删，别去改 tauri.conf.json 的资源清单。'
        }
        elseif ($ahkVerdict -eq 'Late') {
            $c1Detail += ' 归因：**首样不在、之后出现** —— 安装器已退出但资源尚未落盘 / 可见性延迟，'
            $c1Detail += '既不是打包缺失也不是被删。慢盘上会假红，属**已知取舍**（见 TD-089）。'
        }
        elseif ($ahkDirOk) {
            $c1Detail += ' 归因：**ahk_executor 目录在、但这个文件不在** —— 该文件没落盘，或落盘后被移走；'
            $c1Detail += '若这是干净安装（期间无外部动作），则指向打包清单少列了它（资源清单见 tauri.conf.json:37-48），属打包/安装层缺陷。'
            $c1Detail += " 目录/文件逐次存在性：$ahkPaths"
        }
        else {
            $c1Detail += ' 归因：**连 ahk_executor 目录都不在** —— 资源整块没落盘 / 装到了别处，'
            $c1Detail += '不是「清单漏列一个文件」。'
            $c1Detail += " 目录/文件逐次存在性：$ahkPaths"
        }
        if ($ahkVerdict -ne 'Vanished' -and $ahkVerdict -ne 'Late') {
            $c1Detail += ' 这是打包/安装层缺陷，不是运行时故障；继续启动只会得到「拉起 AHK 失败」，把原因引偏到 IPC 认证上。'
        }
    }
    else {
        $c1State = 'PASS'; $c1Detail = "$mainExe 已就位（$mainSize 字节）+ AHK 资源齐全，退出码 0"
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

# ── 残留提示（纯函数）────────────────────────────────────────────────────
# ⚠️ 为什么必须做成纯函数而不是内联 Write-Host：残留提示是「静默失败」的唯一出口，
#    而静默失败恰恰是最容易悄悄退化的一类 —— 内联写死后**没有任何自检能覆盖它**，
#    哪天被人顺手删掉、或把 -ErrorAction 改回 SilentlyContinue，谁都不会知道
#    （本脚本的判据层就吃过这个亏：判据谓词写死时，变异后自检照样 exit 0）。
#    做成纯函数后进入 -SelfCheck 的双向对照：返回值改成空串 ⇒ 自检必须变红（MR1/MR2）。
#    固定前缀 `SMOKE_RESIDUE:` 是给 CI 输出 grep 用的**契约**，
#    不要为了「更好读」改成中文自由文本 —— 改了就等于把 grep 的钩子拆了。
function Get-ResidueNotice {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('KeptForDiagnosis', 'CleanupFailed')][string]$Kind,
        [AllowEmptyString()][string]$Reason = ''
    )
    # 空路径 ⇒ 空串：调用方统一 `if ($notice) { Write-Host ... }`，
    # 这样「没有残留」就不会刷出一行空提示（噪声同样会让人忽略真正的告警）。
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $tail = if ($Reason) { " —— $Reason" } else { '' }
    switch ($Kind) {
        'KeptForDiagnosis' { return "SMOKE_RESIDUE: 保留安装目录用于诊断（未清理）：$Path$tail" }
        'CleanupFailed'    { return "SMOKE_RESIDUE: 清理失败，残留：$Path$tail" }
    }
    return ''
}

# ── 残留提示的**决策层**（纯函数）────────────────────────────────────────
# ⚠️ 为什么在格式化函数之外还要单独一层：MR1/MR2 只能证明「Get-ResidueNotice 会拼出
#    正确的话」，**证明不了「该说话的场合真的会说话」**。而泰莎发现的正是后者 ——
#    C1 失败那条分支压根没调用它。这类缺陷属于「守卫存在但从未接入」（TD-058 的 B 类），
#    是本项目踩过最多次的一类，所以决策必须单独成函数、单独被变异覆盖（MR3）。
function Get-ResiduePlan {
    param(
        [bool]$C1Passed,
        [bool]$KeepInstalled,
        [bool]$CleanupOk,
        [AllowEmptyString()][string]$Reason = ''
    )
    # C1 没过 ⇒ 目录是唯一物证，**保留**且必须说出来。
    if (-not $C1Passed) {
        return [pscustomobject]@{ Emit = $true;  Kind = 'KeptForDiagnosis'; Reason = 'C1 未通过，保留现场用于诊断' }
    }
    # -KeepInstalled 是用户显式要求留现场，已有自己的提示行，不再重复刷残留告警。
    if ($KeepInstalled) {
        return [pscustomobject]@{ Emit = $false; Kind = '';               Reason = '' }
    }
    if (-not $CleanupOk) {
        return [pscustomobject]@{ Emit = $true;  Kind = 'CleanupFailed';    Reason = $Reason }
    }
    return [pscustomobject]@{ Emit = $false; Kind = ''; Reason = '' }
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

function Get-AhkResourceStability {
    <#
    .SYNOPSIS
        AHK 资源「安装后是否**稳定**存在」的判定：纯函数 —— 只读采样序列，不碰磁盘 / 进程 / 时钟。

    .DESCRIPTION
        为什么非抽不可（与 Get-CriterionStates 同一条理由）：判定住在主流程里，-SelfCheck 就够不着，
        把它改成恒真也没人拦得住（变异不生效 = 等于没验）。

        为什么 C1 要「多次采样」而不是一次 Test-Path：
          单次快照把两个**处置相反**的问题混成一个 FAIL ——
            ① 资源从未落盘  ⇒ 打包 / 安装层缺陷（查 tauri.conf.json 的资源清单）；
            ② 资源落过盘、随后被删 ⇒ 有东西在删安装目录（查「谁在删」）。
          更糟的是：单次采样的**时刻**本身可能与「删除」竞态（安装器退出 → 启动 app 之间），
          于是它删之前采到就报绿、删之后采到就报红，**判别力是有偏的**。
          ⇒ 改为多次采样，并把「首样」与「后续」分开看。

    .PARAMETER Samples
        按时间顺序的布尔采样序列，如 @($true, $true, $false)。

    .OUTPUTS
        Verdict         : Stable | Vanished | Missing | Late | Unknown
        Stable          : 是否「全部采样都为 True」——**只有它为真**才允许 C1 认为资源齐全
        Trace           : 可读序列，如 'T,T,F'（进证据包，供事后排障）
        FirstFalseIndex : 第一个 False 的 1 基下标（全 True 时为 0）
    #>
    param([bool[]]$Samples)

    if ($null -eq $Samples) { $Samples = @() }
    $n = $Samples.Count

    $traceParts = @()
    foreach ($s in $Samples) { $traceParts += $(if ($s) { 'T' } else { 'F' }) }
    $trace = ($traceParts -join ',')

    if ($n -eq 0) {
        # 空采样**不许**当通过 —— 那是「不会失败的检查」。
        return [pscustomobject]@{ Verdict = 'Unknown'; Stable = $false; Trace = $trace; FirstFalseIndex = 0 }
    }

    $firstFalse = 0
    for ($i = 0; $i -lt $n; $i++) {
        if (-not $Samples[$i]) { $firstFalse = $i + 1; break }
    }

    if ($firstFalse -eq 0) {
        return [pscustomobject]@{ Verdict = 'Stable';   Stable = $true;  Trace = $trace; FirstFalseIndex = 0 }
    }
    if ($firstFalse -eq 1) {
        # 首样不在时**必须再看后面有没有出现过** —— 这两种情形的处置相反，
        # 合并成一个 Missing 会把「采样太早」误报成「打包缺失」（本函数第一版的缺陷，
        # 由科迪复核指出：F,T,T 与 F,F,F 在旧版里同判 Missing，而前者的注释还写着
        # 「采样窗口内从未出现」—— 那句话对 F,T,T 是**错的**）。
        $anyLaterTrue = $false
        for ($i = 1; $i -lt $n; $i++) {
            if ($Samples[$i]) { $anyLaterTrue = $true; break }
        }
        if ($anyLaterTrue) {
            # 迟到出现 ⇒ 安装器已退出、但资源尚未落盘 / 可见性延迟。**不是**打包缺失。
            return [pscustomobject]@{ Verdict = 'Late';    Stable = $false; Trace = $trace; FirstFalseIndex = 1 }
        }
        # 窗口内全程不在 ⇒ 打包 / 安装层。
        return [pscustomobject]@{ Verdict = 'Missing'; Stable = $false; Trace = $trace; FirstFalseIndex = 1 }
    }
    # 首样在、之后消失 ⇒ 出现过又被删。
    return [pscustomobject]@{ Verdict = 'Vanished'; Stable = $false; Trace = $trace; FirstFalseIndex = $firstFalse }
}

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

        # ── 残留提示：格式化层（MR1/MR2）+ 决策层（MR3）─────────────────────────
        # ⚠️ 为什么分两层断言：只测格式化函数会漏掉「该说话的场合没说话」—— 那正是
        #    泰莎 ⑥ 发现的缺陷形态（C1 失败 ⇒ 既不清理也不提示），属于「守卫写好了
        #    但从未接入」。格式化层测「话说得对不对」，决策层测「该不该说」。
        # MR1 正向：真有残留时必须拼出带契约前缀的话（前缀是给 CI grep 用的钩子）
        $nKeep = Get-ResidueNotice -Path 'C:\Temp\asd-smoke-install-1' -Kind 'KeptForDiagnosis' -Reason 'C1 未通过'
        if (-not $nKeep -or $nKeep -notmatch '^SMOKE_RESIDUE: ') {
            $broken += 'MR1 正向失效：有残留却不产出 SMOKE_RESIDUE 提示（或丢了契约前缀）—— 静默失败会复发'
        }
        # MR2 正向：清理失败同样要说话
        $nFail = Get-ResidueNotice -Path 'C:\Temp\asd-smoke-install-2' -Kind 'CleanupFailed' -Reason '拒绝访问'
        if (-not $nFail -or $nFail -notmatch '^SMOKE_RESIDUE: ') {
            $broken += 'MR2 正向失效：清理失败不产出 SMOKE_RESIDUE 提示 —— 「删不掉」会再次静默'
        }
        # MR2 反向：空路径不许刷噪声（告警刷多了等于没有告警）
        if ((Get-ResidueNotice -Path '' -Kind 'CleanupFailed' -Reason 'x') -ne '') {
            $broken += 'MR2 噪声：空路径仍产出提示 —— 假告警会淹没真告警'
        }
        # MR3 决策层负向：C1 未通过 ⇒ 必须发 KeptForDiagnosis
        #    （变异点：把这条 `if (-not $C1Passed)` 分支删掉，本条必须立刻变红）
        $pC1Fail = Get-ResiduePlan -C1Passed $false -KeepInstalled $false -CleanupOk $true
        if (-not $pC1Fail.Emit -or $pC1Fail.Kind -ne 'KeptForDiagnosis') {
            $broken += 'MR3 负向失效：C1 未通过时应产出 KeptForDiagnosis，实际没有 —— 「装失败后静默留下目录」会复发'
        }
        # MR3 决策层正向：一切正常时**不要**刷残留告警
        $pOk = Get-ResiduePlan -C1Passed $true -KeepInstalled $false -CleanupOk $true
        if ($pOk.Emit) {
            $broken += 'MR3 正向失效：清理成功却仍报残留 —— 假告警会淹没真告警'
        }

        # ── MR4 接线层（文本级）────────────────────────────────────────────────
        # （不署提出者：本仓提交信息与源码注释都不写作者归属 —— 多人同名前缀易串，
        #   且署名一旦写错就会把错误归因固化下来，比不写更糟。理由记在这里就够了。）
        # ⚠️ 上面 MR1–MR3 都只断言**纯函数的返回值**，证明不了「它真的被调用了」。
        #    这是会真实发生的失效：本轮就出现过 `Get-ResidueNotice` 定义就位、
        #    **零调用点**的状态 —— 那时 MR1–MR3 会全部变绿，而它要守的静默失败
        #    **一点没被守住**。「抽了纯函数却没接线」属于「守卫存在但从未接入」。
        #    -SelfCheck 在 `if ($SelfCheck) { exit }` 处就返回、结构上够不着主流程的
        #    调用点，所以只能做文本级断言。
        # ⚠️ **本条能覆盖什么、不能覆盖什么（措辞经校准，我先前写的 slogan 是错的）**：
        #    能覆盖 —— 「重排 / 重构时**忘了**重接」；
        #    覆盖不了 —— 「**按新写法重接**」。后者更危险：MR4 报红之后，只要改一行
        #       正则去匹配新写法就变绿，CI 绿 ⇒ 合入 ⇒ **那次红色没有任何人看到**。
        #    ⇒ 我曾写「误报会逼人看一眼，漏报不会」—— **在合入门禁的语义下这句是错的**：
        #      误报同样会被悄悄抹平，区别只是多改一行正则。别拿它当安全网。
        #    要保证「主流程真的会打印」，只有**端到端**一条路：实跑一次 C1 失败、
        #    断言输出里确有 `SMOKE_RESIDUE` 行。**已固化进 CI**（release job 的
        #    「端到端：C1 失败必须打印残留告警」step，排在真实冒烟**之前** —— 真实冒烟
        #    首次执行很可能红，放后面就永远轮不到它跑）。本机亦已人工跑通一次。
        # ⚠️ 【历史沿革，**不是**当前理由】下面 ①–③ 是**文本匹配那一代**锚点的设计理由，
        #    现已被下方的 **AST 解析**整体取代，保留仅作沿革，别再照它改当前实现：
        #    ① 只匹配函数名会把**注释里的同名文字**算成调用点 ⇒ 断言恒绿。**已实测到**：
        #       本条自己的说明文字一度含锚点原文，于是「删掉一处真调用 + 留一段注释」
        #       仍被算成 2 处（泰莎独立复现确认）⇒ 说明文字里**禁止**写锚点原文；
        #    ② 自检自身也调用该函数（喂的是字面量路径），只有主流程两处传 `$InstallDir`；
        #    ③ 必须是 `$x = <函数名> ...` 的**赋值形态**：否则把调用用**行中** `#` 注释掉
        #       （`$notice = # <函数名> ...`，`#` 不在行首，行首过滤拦不住）照样能伪造通过。
        #       —— 这也是「行首过滤」不够、必须叠加形态锚定的原因。
        $selfPath = $PSCommandPath
        if ($selfPath -and (Test-Path -LiteralPath $selfPath)) {
            # ⚠️ **改用 AST 解析，不再用文本匹配**。文本匹配这条路已被连续三轮找到
            #    伪造向量，每补一层正则就有人从下一层缝漏进来（打地鼠），故整体换掉：
            #      ① 行首 `#` 注释里写同样一句话 → 加「跳过 # 行」堵住；
            #      ② 行中 `#`（`$x = # <fn> ...`）→ `#` 不在行首，①拦不住 → 加赋值形态锚点堵住；
            #      ③ **块注释 `<# ... #>` 的内部行不以 `#` 开头** → ①②都拦不住，实测伪造后仍绿。
            #    AST 直接从语法树取**真实命令调用**：行注释、块注释、字符串都不是 CommandAst，
            #    一次性堵住这一整类。**别再往正则上堆层** —— 那是同一层的重复投入。
            #    ⚠️ 剩余边界（无法自动覆盖）：AST 只能证明「**代码里有这个调用**」，
            #    证明不了「**这次运行会执行到它**」（例如被前置 `return` 挡住）。
            #    后者没有自动机制能覆盖，只能靠上面的端到端 step + 首次人工观察兜底。
            $astErr = $null
            $astTok = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($selfPath, [ref]$astTok, [ref]$astErr)
            if ($null -eq $ast -or ($astErr -and $astErr.Count -gt 0)) {
                # 解析不了就**报错**，绝不默认通过 —— 默认通过正是「不会失败的检查」。
                $broken += 'MR4 无法自检：脚本自身 AST 解析失败 —— 接线断言**未执行**，不要当成通过'
            }
            else {
                $cmds = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
                $wired = @($cmds | Where-Object {
                    $hit = $false
                    if ($_.GetCommandName() -eq 'Get-ResidueNotice') {
                        $els = @($_.CommandElements)
                        for ($k = 0; $k -lt $els.Count - 1; $k++) {
                            $e = $els[$k]
                            if ($e -is [System.Management.Automation.Language.CommandParameterAst] -and $e.ParameterName -eq 'Path') {
                                $nx = $els[$k + 1]
                                if ($nx -is [System.Management.Automation.Language.VariableExpressionAst] -and $nx.VariablePath.UserPath -eq 'InstallDir') {
                                    $hit = $true
                                    break
                                }
                            }
                        }
                    }
                    $hit
                })
                if ($wired.Count -lt 2) {
                    $broken += "MR4 接线失效：主流程里 Get-ResidueNotice -Path `$InstallDir 的调用点只有 $($wired.Count) 处（期望 >=2：C1 失败 + 清理失败）—— 函数还在但没人调用 => 残留提示永远不会打印，静默失败照旧"
                }
            }
        }
        else {
            # 拿不到自身路径时**不许**默认通过 —— 那正是「不会失败的检查」。
            $broken += 'MR4 无法自检：拿不到脚本自身路径（$PSCommandPath 为空或文件不在），接线断言**未执行**，不要当成通过'
        }

        # ⚠️ MR5 组合层**不在这里**，已下移到「C1–C5 判据组装」之后（见后半段）。
        #    原因（实测，不是推测）：它需要从 `$badPack` 取 C1 的判定结果，而 `$badPack`
        #    定义在**本位置之后**；在 `Set-StrictMode` 下引用未定义变量会**直接抛出**，
        #    于是 :679 之后的所有断言（含 MC1r、MD1–MD4）**一条都不会执行**，
        #    而退出码仍是 1 —— 会被误读成「判据是假守卫」。**位置本身就是断言的一部分**。

        # ── C1–C5 的判据组装：坏证据包必须变红 / 好证据包必须变绿 ────────────────
        # ⚠️ 这一段补的是**覆盖缺口**：在此之前 -SelfCheck 只喂上面 3 个辅助函数，
        #    主流程的判据组装完全没被覆盖 —— 实测把 `if ($c5.Found)` 改成 `if ($true)`，
        #    自检照样 exit 0。现在判定住在 Get-CriterionStates 里，同一个变异拦得住。
        $badPack = @{
            InstallExitCode = 1
            MainExePath     = 'X:\nope\asd-tauri.exe'
            MainExeExists   = $false
            MainExeSize     = 0
            AhkResourcePath   = 'X:\nope\ahk_executor\AutoHotkey64.exe'
            AhkResourceExists = $false
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
            AhkResourcePath   = 'C:\Temp\asd-smoke\ahk_executor\AutoHotkey64.exe'
            AhkResourceExists = $true
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

        # ── C1 的 AHK 资源维度必须**单独隔离**测 ────────────────────────────
        # ⚠️ 为什么不能只靠上面那个「全坏包」：全坏包里 InstallExitCode=1、MainExeExists=$false，
        #    C1 在第一个分支就已经 FAIL —— 于是「AHK 资源检查」这一条无论怎么写都改变不了 C1
        #    的结果，把它改成 `-or $true` 也照样绿（**变异不生效 = 等于没验**）。
        #    必须构造「其余全好、只缺 AHK 资源」的包，才能把这一条单独顶到台前。
        $packAhkMissing = @{}
        foreach ($k in $goodPack.Keys) { $packAhkMissing[$k] = $goodPack[$k] }
        $packAhkMissing['AhkResourceExists'] = $false
        $c1Ahk = Get-StateOf @(Get-CriterionStates -Evidence $packAhkMissing) 'C1'
        if ($null -eq $c1Ahk) {
            $broken += 'MC1r 缺失：只缺 AHK 资源的证据包没返回 C1'
        }
        elseif ($c1Ahk.State -ne 'FAIL') {
            $broken += "MC1r 负向失效：主 exe 在、AHK 资源缺失时 C1 应为 FAIL，实际 $($c1Ahk.State) —— 打包层缺陷被放行到运行时，会伪装成 IPC 认证失败"
        }

        # ── AHK 资源「稳定性」判定的双向对照（MC1s）─────────────────────────
        # ⚠️ **判定规则写在这里，与 Get-AhkResourceStability 的注释必须逐字一致**：
        #    全 T ⇒ Stable（**唯一**允许 C1 认为资源齐全的情形）；
        #    首样 F 且之后出现 ⇒ Late；全程 F ⇒ Missing；首样 T 之后 F ⇒ Vanished。
        #    为什么必须把「首样」与「后续」分开看：这四者的**处置相反**
        #    （Late 查「装完为什么还没落盘」/ Missing 查打包清单 / Vanished 查谁在删安装目录），
        #    合并成一句「资源不存在」就把判别器抹掉了 —— 旧版正是把 F,T,T 与 F,F,F 同判 Missing。
        $sStable = Get-AhkResourceStability -Samples @($true, $true, $true)
        $sVan    = Get-AhkResourceStability -Samples @($true, $false, $true)
        $sLate   = Get-AhkResourceStability -Samples @($false, $true, $true)
        $sMiss   = Get-AhkResourceStability -Samples @($false, $false, $false)
        $sEmpty  = Get-AhkResourceStability -Samples @()
        if ($sStable.Verdict -ne 'Stable' -or -not $sStable.Stable) {
            $broken += "MC1s 正向失效：全 T 的采样应判 Stable，实际 $($sStable.Verdict) / Stable=$($sStable.Stable) —— 恒红，装成功了也会被判成资源不全"
        }
        if ($sVan.Verdict -ne 'Vanished' -or $sVan.Stable) {
            $broken += "MC1s 负向失效：出现过又被删（T,F,T）应判 Vanished 且**不算齐全**，实际 $($sVan.Verdict) / Stable=$($sVan.Stable) —— 删除竞态会被记成打包缺陷，归因引偏"
        }
        if ($sLate.Verdict -ne 'Late' -or $sLate.Stable) {
            $broken += "MC1s 负向失效：首样不在、之后出现（F,T,T）应判 Late（采样太早 / 落盘延迟）且不算齐全，实际 $($sLate.Verdict) / Stable=$($sLate.Stable) —— 会被误报成「资源没打进包」，把排障引向 tauri.conf.json 的资源清单"
        }
        if ($sMiss.Verdict -ne 'Missing' -or $sMiss.Stable) {
            $broken += "MC1s 负向失效：全程不在（F,F,F）应判 Missing 且不算齐全，实际 $($sMiss.Verdict) / Stable=$($sMiss.Stable)"
        }
        if ($sEmpty.Stable) {
            $broken += 'MC1s 负向失效：空采样被判齐全 —— 「一次都没采到」被当成通过，正是不会失败的检查'
        }

        # ── C1 的失败归因必须跟着 Verdict 走（MC1v）─────────────────────────
        # ⚠️ 本组钉的是「**失败时说的是哪种失败**」，**不是** PASS/FAIL（那是 MC1r 的活）。
        #    为什么必须钉：归因文案若写死成「打包/安装层缺陷」，Vanished（资源被删）
        #    也会被这么报 —— 把排障引向 tauri.conf.json 的资源清单，是同一种引偏的另一侧。
        #    验收方式：把 AhkResourceVerdict 的读取改成恒定值 ⇒ 四句归因塌成同一句 ⇒ 本组变红。
        #    ⇒ 所以这里既查「每句说到点上」，也查「四句两两不同」——后者才是防塌陷的那一条。
        $attBase = @{}
        foreach ($k in $goodPack.Keys) { $attBase[$k] = $goodPack[$k] }
        $attBase['AhkResourceExists']  = $false   # 逼 C1 落进 AHK 分支
        $attBase['AhkResourceTrace']   = 'T,F,T'
        $attBase['AhkResourcePathTrace'] = 'root=TTTTT dir=TTTTT exec=FFFFF'
        $mkAtt = {
            param([string]$Verdict, [bool]$DirExists)
            $p = @{}
            foreach ($k in $attBase.Keys) { $p[$k] = $attBase[$k] }
            $p['AhkResourceVerdict']   = $Verdict
            $p['AhkResourceDirExists'] = $DirExists
            $p
        }
        $dVan    = [string](Get-StateOf @(Get-CriterionStates -Evidence (& $mkAtt 'Vanished' $true))  'C1').Detail
        $dLate   = [string](Get-StateOf @(Get-CriterionStates -Evidence (& $mkAtt 'Late' $true))      'C1').Detail
        $dMissD  = [string](Get-StateOf @(Get-CriterionStates -Evidence (& $mkAtt 'Missing' $true))   'C1').Detail
        $dMissNo = [string](Get-StateOf @(Get-CriterionStates -Evidence (& $mkAtt 'Missing' $false))  'C1').Detail
        if ($dVan -notmatch '之后消失') {
            $broken += "MC1v 归因失效：Verdict=Vanished 时文案没点明「之后消失」—— 资源被删会被当成打包缺失。实际：$dVan"
        }
        if ($dLate -notmatch '之后出现') {
            $broken += "MC1v 归因失效：Verdict=Late 时文案没点明「之后出现」—— 慢盘假红会被当成打包缺失。实际：$dLate"
        }
        if ($dMissD -notmatch '少列了它') {
            $broken += "MC1v 归因失效：Verdict=Missing 且目录在时，文案没点明「打包清单少列了它」。实际：$dMissD"
        }
        if ($dMissNo -notmatch '目录都不在') {
            $broken += "MC1v 归因失效：Verdict=Missing 且目录不在时，文案没点明「目录都不在」。实际：$dMissNo"
        }
        $attUnique = @(@($dVan, $dLate, $dMissD, $dMissNo) | Select-Object -Unique).Count
        if ($attUnique -lt 4) {
            $broken += "MC1v 归因失效：四种归因的文案没有两两不同（去重后只剩 $attUnique 种）—— 归因被写死成同一句，判别器等于不存在"
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

        # ── MR5 组合层：从**证据包**一路走到底 —— C1 失败 ⇒ 最终串含 SMOKE_RESIDUE ─
        # ⚠️ 位置说明：必须放在 `$badPack` 定义**之后**（故不放在 MR1–MR4 那一段）。
        # ⚠️ 为什么这一层必须**从证据包取 C1 的判定结果**，而不是写死 `-C1Passed $false`：
        #    写死输入的话只覆盖「决策 + 格式化」两层的组合，**覆盖不到「C1 的判定结果
        #    有没有真的传到决策层」**。一旦 C1 谓词被改成恒真，写死版照样绿，而真实行为
        #    变成「装失败了也不提示」—— 正是要防的那件事。从证据包取 ⇒ 恒真变异会
        #    让 $mr5C1.State 变 PASS ⇒ 不发提示 ⇒ MR5 红。**已实测**：把
        #    `State = $c1State` 改成 `State = 'PASS'`，自检 exit 2 并点名 MR5。
        #    ⚠️ 边界：仍只证明「给定失败证据 ⇒ 产出正确的话」，**不证明主流程真会执行到
        #    那两处调用** —— 后者由 CI 的端到端 step 守（且只覆盖 C1 失败这一条分支）。
        $mr5Bad = @{}
        foreach ($k in $badPack.Keys) { $mr5Bad[$k] = $badPack[$k] }
        $mr5C1 = Get-StateOf @(Get-CriterionStates -Evidence $mr5Bad) 'C1'
        if ($null -eq $mr5C1) {
            $broken += 'MR5 组合失效：坏证据包没返回 C1 —— 组合断言无从判定，**不要**当成通过'
        }
        else {
            $mr5Plan = Get-ResiduePlan -C1Passed ($mr5C1.State -eq 'PASS') -KeepInstalled $false -CleanupOk $true
            if (-not $mr5Plan.Emit) {
                # ⚠️ 必须先判 Emit 再去格式化：**不要**在 Emit=false 时调 Get-ResidueNotice。
                #    那时 Kind 是空串，而 Kind 带 [ValidateSet]，传空会**抛参数验证异常**
                #    ⇒ 自检崩溃（实测：变异把 C1 改成恒 PASS 后，本条直接崩、退出码还被
                #    记成 0 —— 比变红更糟，看起来像「没问题」）。先判 Emit 才能让它
                #    **正当地报红**，这也是「守卫崩了 ≠ 守卫生效」的一个具体样例。
                $broken += "MR5 组合失效：C1 判定为 $($mr5C1.State) 时决策层应发提示，实际 Emit=false —— 判据结果没有传到决策层"
            }
            else {
                $mr5Str = Get-ResidueNotice -Path 'C:\Temp\asd-smoke-install-mr5' -Kind $mr5Plan.Kind -Reason $mr5Plan.Reason
                if (-not $mr5Str -or $mr5Str -notmatch '^SMOKE_RESIDUE: ' -or $mr5Str -notmatch '未清理') {
                    $broken += "MR5 组合失效：C1 判定为 $($mr5C1.State) 时应产出「SMOKE_RESIDUE … 未清理」，实际产出「$mr5Str」—— 决策 → 格式化这条链断了"
                }
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
        # ⚠️ 本条**单独不可能红**，这是预期的，不要当成「假守卫」删掉：
        #    `ExitCode` 与 `Failed` 是从**同一个 `$failed`** 派生的（`Get-SmokeVerdict`
        #    里 `elseif ($failed -gt 0) { $code = 1 }`），所以只要全 PASS 包的 `Failed`
        #    被算错成非 0，就必然 `failed > 0` ⇒ 出口码非 0 ⇒ 下面那条 MD1 同时红。
        #    ⇒ 它是**冗余信号**（信息量不超过下一条），不是**不会失败的检查**。
        #    ⚠️ 该结论只有一轮突变的证据（把 `$failed` 改成算总数，两条一起红），
        #       **未经独立复验**；若要删它，请先自己补一轮能让它单独红的突变再决定。
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

    # ── 横幅里的断言数**由断言集合自动推导**，不再手写 ──────────────────────────
    # 为什么改：原先写死「三层都过」。后来陆续加了 MR1–MR5 / MC1r / MC3s / MD1–MD4，
    #   加断言的人改了断言、没改这句 ⇒ 横幅与实际断言集合漂移。**写死的计数迟早会
    #   漂移**，所以改成从本函数自身的 AST 里数：一条 `$broken +=` 就是一条断言，
    #   消息前缀去重后就是一个断言组。删掉/新增任一断言块，数字自动跟着变 ——
    #   验收靠**突变**（删掉 MR5 整块，数字必须变小），不靠人眼看代码。
    # 为什么用 AST 而不是文本匹配：与上面 MR4 同一条理由 —— 行注释、块注释、字符串
    #   里出现同样文字都会被文本匹配算进去（MR4 已被连续三轮找到伪造向量）。
    # ⚠️ 它能证明什么、不能证明什么（与 MR4 同一边界，别夸大）：
    #   能证明 —— 函数体里**存在**这些断言语句；
    #   证明不了 —— 某条分支**这次是否被走到**（例如被前置 return 挡住）。
    #   ⇒ 所以措辞用「断言 / 断言组」而不是「层」，且**不**宣称每条都执行过。
    # ⚠️ 拿不到计数时**不许**默认报 0：「0 条断言都过」是假绿，比不报更糟。
    $gN = -1
    $gGroups = New-Object System.Collections.Generic.List[string]
    $gPath = $PSCommandPath
    if ($gPath -and (Test-Path -LiteralPath $gPath)) {
        $gErr = $null
        $gTok = $null
        $gAst = [System.Management.Automation.Language.Parser]::ParseFile($gPath, [ref]$gTok, [ref]$gErr)
        if (($null -ne $gAst) -and -not ($gErr -and $gErr.Count -gt 0)) {
            $gFns = @($gAst.FindAll({
                param($x)
                ($x -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
                ($x.Name -eq 'Invoke-GuardSelfCheck')
            }, $true))
            if ($gFns.Count -ge 1) {
                $gAdds = @($gFns[0].FindAll({
                    param($x)
                    ($x -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
                    ($x.Operator -eq [System.Management.Automation.Language.TokenKind]::PlusEquals) -and
                    ($x.Left -is [System.Management.Automation.Language.VariableExpressionAst]) -and
                    ($x.Left.VariablePath.UserPath -eq 'broken')
                }, $true))
                $gN = $gAdds.Count
                foreach ($gAdd in $gAdds) {
                    $gRaw = $gAdd.Right.Extent.Text.Trim().Trim('"').Trim("'")
                    $gIds = @()
                    if ($gRaw -match '^([A-Za-z]+[0-9]+[a-z]*)') {
                        $gIds = @($Matches[1])
                    }
                    elseif ($gRaw -match '^([A-Za-z]+)\$([A-Za-z_][A-Za-z0-9_]*)') {
                        # 形如 "M$id 缺失：..."（C1/C2/C4/C5 循环里那几条）：前缀是常量、
                        # 后面紧跟迭代变量，必须把外层 foreach 的字面量取值展开，
                        # 否则这 4 个断言组会被并成 1 个，删掉其中一条也看不出来。
                        $gPfx     = $Matches[1]
                        $gVarName = $Matches[2]
                        $gNode    = $gAdd.Parent
                        while ($null -ne $gNode) {
                            if (($gNode -is [System.Management.Automation.Language.ForEachStatementAst]) -and
                                ($null -ne $gNode.Variable) -and
                                ($gNode.Variable.VariablePath.UserPath -eq $gVarName)) {
                                $gVals = @()
                                foreach ($gS in @($gNode.Condition.FindAll({
                                    param($y) $y -is [System.Management.Automation.Language.StringConstantExpressionAst]
                                }, $true))) {
                                    $gVals += ($gPfx + $gS.Value)
                                }
                                $gIds = $gVals
                                break
                            }
                            $gNode = $gNode.Parent
                        }
                        if ($gIds.Count -eq 0) { $gIds = @($gPfx + '$' + $gVarName) }
                    }
                    else { $gIds = @('(未命名)') }
                    foreach ($gId in $gIds) {
                        if (-not $gGroups.Contains($gId)) { $gGroups.Add($gId) }
                    }
                }
            }
        }
    }

    if ($gN -lt 1) {
        # 数不出来就说数不出来 —— 宁可黄着，也不要印一个「0 条断言都过」的假绿。
        Write-Host '✓ 守卫自检通过（⚠ 断言条数未能自动统计 —— 横幅计数失效，请修本函数的 AST 统计；' -ForegroundColor Yellow
        Write-Host '   本行**不是**「0 条断言都过」，别当绿灯读）' -ForegroundColor Yellow
    }
    else {
        Write-Host "✓ 守卫自检通过（$gN 条断言 / $($gGroups.Count) 个断言组都过）：" -ForegroundColor Green
        Write-Host "  · 断言组：$($gGroups -join '、')" -ForegroundColor DarkGray
    }
    Write-Host '  （含义：判据在「故意破坏」时会真的失败，且失败会真的反映到退出码上 ——' -ForegroundColor DarkGray
    Write-Host '    「判据会红」和「红了算不算数」是两件事，都验了）' -ForegroundColor DarkGray
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
# AHK 可执行资源：打包态**唯一**的一个（tauri.conf.json:44）。
# ⚠️ 与 C4 的进程名判定有意不对称：C4 同时接受 asd_executor.exe / AutoHotkey64.exe（进程表里
#    出现哪个都算拉起成功），而 C1 只认打包清单里真正存在的那一个 —— C1 问的是「包落全了吗」，
#    不是「进程起来了吗」。将来打包清单变了（例如把 asd_executor.exe 也打进去），这里要跟着改。
$ahkResPath = Join-Path (Join-Path $InstallDir 'ahk_executor') 'AutoHotkey64.exe'

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
    AhkResourcePath     = $ahkResPath
    AhkResourceExists   = $false
    # 稳定性采样的默认值必须是「不齐全 / 未测定」：主流程若因任何原因没跑到采样，
    # 缺省值不能替它说「资源齐全」。
    AhkResourceVerdict  = 'Missing'
    AhkResourceTrace    = ''
    AhkResourceSampleMs = 0
    # 目录位缺省 $false = 按「最严重口径」说（连目录都不在）；主流程采样后覆盖它。
    # 这是**诊断字段**，不参与 C1 的 PASS/FAIL（判定只由 AhkResourceExists 决定）。
    AhkResourceDirExists = $false
    AhkResourcePathTrace = ''
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
    # AHK 资源必须和主 exe 一起验：只查主 exe 的话，「装完资源不全」会在 C1 假绿，
    # 一路带到 C4/C5 才炸，把打包缺陷报成运行时故障。
    # ⚠️ **判定规则**（改这里必须同步改 Get-AhkResourceStability 的注释与 MC1s / MC1v 断言）：
    #     全部采样 True            ⇒ Stable   ⇒ AhkResourceExists=$true（C1 才可能 PASS）
    #     首样 False 且之后出现过  ⇒ Late     ⇒ 安装尚未落盘 / 可见性延迟，**不是**打包缺失
    #     全程 False               ⇒ Missing  ⇒ 打包 / 安装层
    #     首样 True 之后 False     ⇒ Vanished ⇒ 出现过又被删 ⇒ 有东西在删安装目录
    #    **任一次 False 都不算齐全**：单次快照会在「删之前 / 删之后」之间随机落点，
    #    既可能假绿也可能假红 —— 用它当「资源齐全」的判据，判别力是有偏的。
    #    ⚠️ Late 也判不齐全（C1 FAIL）是**刻意的取舍**：宁可吵闹 —— 「安装器已退出、
    #       资源却还没落盘」本身就值得看一眼；代价是慢盘机器上可能假红，基率未知
    #       （首次真跑之前不要假定它罕见）。**下一个看到慢盘假红的人：那不是 bug，
    #       不要把它「修」成不吵闹** —— 判据一旦不吵就等于哑了。同款记录见
    #       docs/tech-debt-register.md 的 TD-089（只写在对话里的取舍等于没有取舍）。
    # ⚠️ **Stable 仍只由 `AutoHotkey64.exe` 这一条路径决定 —— 语义一字未改。**
    #    另外三条路径（安装目录 / ahk_executor / asd_executor.exe）只做**诊断记录**，
    #    **不参与判定**，理由各有不同：
    #      · `asd_executor.exe`：健康安装里**本来就不存在**（未列进 tauri.conf.json:37-48
    #        的 resources，应用走便携模式）。把它算进「全部 True」会让每一次正常安装都 FAIL。
    #      · `ahk_executor` 目录位：文件在 ⇒ 目录必然在，加进判定是冗余、不改行为。
    #        它的唯一用途是**把「目录整块不在」与「只缺这个文件」分开**（Cody 的 ①/② 对照）。
    #      · 安装根目录：同目录位，只作记录。
    # ⚠️ 已知覆盖边界：5 次 × 8ms 间隔 ⇒ 只覆盖「安装器退出后 ~32ms」。若删除发生在
    #    「启动 app」那一段（实测 16:03Z 那次 init→spawn 相隔 970ms），本处仍会报
    #    Stable —— 要覆盖它需要第二个采样点（放在 finally 清理之前），本处不越界。
    $ahkSampleCount = 5
    $ahkSampleMs    = 8
    $ahkSamples     = @()
    $ahkRootSamples = @()
    $ahkDirSamples  = @()
    $ahkExecSamples = @()
    $ahkProbeDir    = Join-Path $InstallDir 'ahk_executor'
    $ahkProbeExec   = Join-Path $ahkProbeDir 'asd_executor.exe'
    for ($i = 0; $i -lt $ahkSampleCount; $i++) {
        if ($i -gt 0) { Start-Sleep -Milliseconds $ahkSampleMs }
        $ahkRootSamples += [bool](Test-Path -LiteralPath $InstallDir   -PathType Container)
        $ahkDirSamples  += [bool](Test-Path -LiteralPath $ahkProbeDir  -PathType Container)
        $ahkExecSamples += [bool](Test-Path -LiteralPath $ahkProbeExec -PathType Leaf)
        $ahkSamples     += [bool](Test-Path -LiteralPath $ahkResPath   -PathType Leaf)
    }
    $ahkStab = Get-AhkResourceStability -Samples $ahkSamples
    $rootT = ''; foreach ($v in $ahkRootSamples) { $rootT += $(if ($v) { 'T' } else { 'F' }) }
    $dirT  = ''; foreach ($v in $ahkDirSamples)  { $dirT  += $(if ($v) { 'T' } else { 'F' }) }
    $execT = ''; foreach ($v in $ahkExecSamples) { $execT += $(if ($v) { 'T' } else { 'F' }) }
    $ev['AhkResourceExists']   = [bool]$ahkStab.Stable
    $ev['AhkResourceVerdict']  = [string]$ahkStab.Verdict
    $ev['AhkResourceTrace']    = [string]$ahkStab.Trace
    $ev['AhkResourceSampleMs'] = [int]$ahkSampleMs
    $ev['AhkResourceDirExists'] = [bool]($ahkDirSamples[-1])
    $ev['AhkResourcePathTrace'] = "root=$rootT dir=$dirT exec=$execT"

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
        # ⚠️ 刻意**不清理** $InstallDir：装失败的目录是唯一能看出「为什么失败」的物证
        #    （ahk_executor 在不在、uninstall.exe 在不在、装到哪一步停的）。自动删掉它
        #    等于销毁取证材料。但**必须说出来** —— 静默留下目录与静默删除是同一种病：
        #    前者让你下次撞上「目录被占」却毫无线索（泰莎 ⑥ 发现的就是这条：C1 失败
        #    ⇒ finally 整个不清理 ⇒ 目录留在 %TEMP% 而输出里一个字都没有）。
        $plan = Get-ResiduePlan -C1Passed $false -KeepInstalled $KeepInstalled -CleanupOk $true
        if ($plan.Emit) {
            $notice = Get-ResidueNotice -Path $InstallDir -Kind $plan.Kind -Reason $plan.Reason
            if ($notice) { Write-Host $notice -ForegroundColor Yellow }
        }
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
                # ⚠️ `_?=$InstallDir` 不能省。NSIS 卸载器默认会把自身复制到
                #    %TEMP%\~nsu1.tmp\Un.exe 再执行，**原进程立即退出** —— 于是
                #    Start-Process -Wait 提前返回，紧接着的 Remove-Item -Recurse 会撞上
                #    仍在删文件的卸载器（实测留下 ~nsu1.tmp\Un.exe 与删不干净的安装目录，
                #    也就是下面 :792 那条「清理旧安装目录失败」告警的来源）。
                #    `_?=<dir>` 让它就地卸载、不自我复制，-Wait 才真的是「等它做完」。
                #    对照：安装器内部的覆盖安装路径也是这么调的
                #    （asd-tauri/target/debug/nsis/x64/installer.nsi:350 `_?=$4`）——
                #    只有本脚本自己调卸载器时漏了这个参数。
                Start-Process -FilePath $uninst -ArgumentList @('/S', "_?=$InstallDir") -Wait -ErrorAction SilentlyContinue | Out-Null
            }
            # ⚠️ 这里**不能**用 `-ErrorAction SilentlyContinue`：清理失败时脚本照样 exit 0，
            #    于是「目录没删掉」这件事**完全不留痕**（实测 %TEMP% 下确实留下过
            #    asd-smoke-install-* 残留目录，而没有任何输出提示过它）。
            #    清理失败**不改变判据结论**（它衡量的是打包质量，不是安装目录卫生），
            #    但必须显式说出来 —— 否则下次排查「为什么安装目录被占」时毫无线索。
            $cleanOk  = $false
            $cleanMsg = ''
            try {
                Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
                $cleanOk = $true
            }
            catch {
                $cleanOk  = $false
                $cleanMsg = $_.Exception.Message
            }
            $plan = Get-ResiduePlan -C1Passed $true -KeepInstalled $false -CleanupOk $cleanOk -Reason $cleanMsg
            if ($plan.Emit) {
                $notice = Get-ResidueNotice -Path $InstallDir -Kind $plan.Kind -Reason $plan.Reason
                if ($notice) { Write-Host $notice -ForegroundColor Yellow }
            }
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
