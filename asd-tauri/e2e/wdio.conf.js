// =================================================================
// WebDriverIO 配置 - Tauri E2E 测试
// =================================================================
// 通过 tauri-driver（监听 4444 端口）驱动 Tauri 应用窗口
// 所有 JS 使用 ESM 语法（package.json type=module）
// =================================================================
import { spawn, spawnSync, execSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import net from 'node:net';

const __dirname = dirname(fileURLToPath(import.meta.url));

// 检查指定端口是否在监听（用于诊断 Vite dev server / tauri-driver 是否运行）
function checkPort(host, port) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(1000);
    socket.on('connect', () => {
      socket.destroy();
      resolve(true);
    });
    socket.on('timeout', () => {
      socket.destroy();
      resolve(false);
    });
    socket.on('error', () => {
      resolve(false);
    });
    socket.connect(port, host);
  });
}

// 应用 binary 路径（绝对路径，避免工作目录歧义）
// e2e 目录位于 asd-tauri/e2e，binary 在 workspace 根 target/debug/
// 注意：使用 tauri build --debug --no-bundle 构建，前端已嵌入
const binaryAbsPath = resolve(__dirname, '../target/debug/asd-tauri.exe');
// 报告目录
const reportsDir = resolve(__dirname, 'reports');
// msedgedriver.exe 所在目录（tauri-driver 通过 --native-driver 参数显式指定）
const driversDir = resolve(__dirname, 'drivers');
const msedgedriverExePath = resolve(driversDir, 'msedgedriver.exe');

// WebView2 user data 目录（UDF）：必须指向 WebView2 真实使用的那个目录。
//
// ⚠️ **前一版推导是错的，已订正**（2026-09-18）。错误推导是「wry 传空串 ⇒ WebView2 走
//    默认 UDF ⇒ UDF = `<exe>.WebView2`」。它错在**只读了一层源码**：
//    wry-0.55.1/src/webview2/mod.rs:345 确实是 `data_directory.unwrap_or_default()`，
//    但 **Tauri 在它之上那层就把值填上了** —— tauri-2.11.2/src/manager/webview.rs:534-543：
//      #[cfg(any(target_os = "linux", target_os = "windows"))]
//      if pending.webview_attributes.data_directory.is_none() {
//          ... = Some(manager.path().resolve(&identifier, BaseDirectory::LocalData));
//      }
//    即 Windows 上 Tauri **强制**填 `Some(<LocalData>/<identifier>)`，wry 永远收不到 None，
//    `unwrap_or_default()` 那条空串分支根本不会被触发。
//    ⇒ 真实 UDF = `<LocalData>/<identifier>`；本仓 identifier = `com.asd.tauri`
//      （asd-tauri/src-tauri/tauri.conf.json:5，且未配置 dataDirectory），
//      Windows 上 `<LocalData>` = `%LOCALAPPDATA%`。
//    **教训：跨层行为必须追到「谁最后赋值」，不能只看声明处。** 这也是本轮第二次栽在同一个
//    形状上（第一次是误以为 additional_browser_args 只能改 Rust、其实它本来就是 conf 字段）。
//
// ⚠️ **仍刻意不用 mkdtempSync 新建临时目录**：那样 WebView2 写在一处、EdgeDriver 拿着
//    userDataFolder 去另一处找，正是上游报 `DevToolsActivePort file doesn't exist`
//    （run 34766587019 / job 103748526013）的成因。目录对齐比目录干净更重要。
//
// ⚠️ 端口只能用 `0`，不要改固定端口：固定端口唯一通路是 `ms:edgeOptions.debuggerAddress`，
//    但 tauri-driver 用 `always_match.extend(native)` **整体替换** `ms:edgeOptions`
//    （crates/tauri-driver/src/server.rs:150-152，native 里只有 binary/args/webviewOptions）
//    ⇒ 注入必被覆盖、完全不可达。
const webviewUserDataFolder = join(process.env.LOCALAPPDATA ?? '', 'com.asd.tauri');
// 对照候选：前一版（错误）推导得出的路径。不做 userDataFolder，仅供 [UDF 探测 B] 扫描对照，
// 以防本次推导又错一次时还要再跑一轮。
const webviewUserDataFolderLegacy = binaryAbsPath + '.WebView2';

// 全局引用：保存 tauri-driver 子进程，供 onComplete 关闭
let tauriDriverProcess = null;
// 全局引用：保存 tauri-driver 的 stdout/stderr。
// ⚠️ 必须是模块级而非 onPrepare 内的局部变量：onComplete 要无条件落盘它，
//    而「局部 const」在 onComplete 里根本不可见（这是第六道死因排查的硬要求）。
// ⚠️ 落盘不能只在 waitForPort 失败的分支做 —— 那等于「只有没启动时才记录它为什么
//    没启动」，而 run 35327797606 的实际失败形态是「启动了、已监听 4444，但
//    POST /session 永不返回」，正好被那个条件排除，driver 输出一行都没留下来。
const driverLog = [];
// 采样器输出（与 driverLog 分开存，避免被 onComplete 的 4000 字符尾部截断）
const samplerLines = [];
let samplerTimer = null;
// 采样目标状态：只记录**变化**，并额外每 30s 打心跳，见 samplerTick。
// ⚠️ 心跳必须存在：本轮已连续三次栽在「静默」上（driverLog 静默、diag 不进 stdout、
//    tauri-driver 零输出）。没有心跳，「一条变化都没有」既可能是真没变化，也可能是
//    采样器自己挂了 —— 同样的静默会再骗我们一次。
const samplerState = {
  startedAt: 0,
  beatAt: 0,
  targets: {
    app: { label: 'asd-tauri.exe', present: null, everSeen: false, firstSeen: null, lastSeen: null },
    native: { label: 'msedgedriver.exe', present: null, everSeen: false, firstSeen: null, lastSeen: null },
    vite: { label: '5173 (Vite)', present: null, everSeen: false, firstSeen: null, lastSeen: null },
    tauri: { label: 'tauri-driver PID', present: null, everSeen: false, firstSeen: null, lastSeen: null },
  },
};
// 全局引用：保存由本配置启动的 Vite dev server 子进程，供 onComplete 关闭。
// 复用外部已运行的实例时不持有句柄（不关闭别人的进程）。
let viteProcess = null;

const VITE_HOST = '127.0.0.1';
const VITE_PORT = 5173;
// 前端项目根（asd-tauri/），Vite 需以此为 cwd 才能读到 vite.config.js
const projectRoot = resolve(__dirname, '..');
// 直接以 node 执行 vite 的 JS 入口：跨平台、无需 shell、无 .cmd/.ps1 扩展名歧义
const viteBinPath = resolve(projectRoot, 'node_modules/vite/bin/vite.js');

// Vite 冷启动预热的目标模块。
// 真因（TD-016，2026-09-16 实测）：Vite dev server 的**首次**模块转换极慢 ——
// `/src/styles.css` 的 `vite:transform` 实测 **51166ms**，之后走内存缓存只要 0.68ms。
// 后果链：首屏 load 约 54s 才完成 → WebDriver 的 getTitle()/execute() 都会**阻塞到页面
// load 完成**（不是它们慢，实测页面就绪后均为 5ms）→ 首个命令吃掉 mocha 的 60s 预算 →
// 表现为「getTitle() 超时」，极易误判成「窗口没起来 / 页面加载失败」。
// 因此在**建立 WebDriver 会话之前**把这 50 秒付掉，让真正受限的 60s 只覆盖应用本身。
const WARMUP_PATHS = ['/', '/@vite/client', '/src/main.js', '/src/styles.css'];
// 单个预热请求的超时：必须显著大于实测的 51s，否则预热自己先超时、等于没预热
const WARMUP_TIMEOUT_MS = 120000;

// 顺序预热 Vite 模块，返回诊断行。
// 刻意**顺序**而非并发：并发会让多个冷转换互相争抢，总墙钟时间反而更长（实测并发时
// styles.css 52.7s / api.js 22.3s / env.mjs 20.7s 各自都慢）；顺序时除第一个外均 <3s。
async function warmupVite() {
  const started = Date.now();
  const lines = [];
  for (const p of WARMUP_PATHS) {
    const t = Date.now();
    try {
      const res = await fetch(`http://${VITE_HOST}:${VITE_PORT}${p}`, {
        signal: AbortSignal.timeout(WARMUP_TIMEOUT_MS),
      });
      await res.text();
      lines.push(`[OK] 预热 ${p} ${Date.now() - t}ms (HTTP ${res.status})`);
    } catch (e) {
      // 预热失败**不阻塞**：它只是加速手段，失败则退化成原来的慢首屏，由用例自己超时报错
      lines.push(`[WARN] 预热 ${p} 失败 ${Date.now() - t}ms: ${e.message}`);
    }
  }
  lines.push(`[INFO] Vite 预热总耗时 ${Date.now() - started}ms`);
  return lines;
}

// 无条件落盘 tauri-driver 的输出到 reports/tauri-driver.log。
// 调用点：onPrepare 的 exit 钩子（进程自己退出时）+ onComplete（收尾时）。
// 目的：让「tauri-driver 起来了但 /session 不返回」这种失败也能留下证据。
function dumpDriverLog() {
  try {
    if (!existsSync(reportsDir)) {
      mkdirSync(reportsDir, { recursive: true });
    }
    writeFileSync(
      resolve(reportsDir, 'tauri-driver.log'),
      (driverLog.join('') || '(无输出)\n'),
      'utf-8'
    );
  } catch {
    // 落盘失败不能影响测试流程本身
  }
}

// 进程名是否存在（tasklist 过滤；无匹配时输出为 "INFO: No tasks..."，不含进程名）
function processExists(imageName) {
  try {
    const r = spawnSync('tasklist', ['/FI', `IMAGENAME eq ${imageName}`], {
      encoding: 'utf8', timeout: 10000, shell: false,
    });
    return `${r.stdout || ''}`.toLowerCase().includes(imageName.toLowerCase());
  } catch {
    return false;
  }
}

// PID 是否存活（同样走 tasklist，避免 process.kill(pid, 0) 在 Windows 上的语义差异）
function pidAlive(pid) {
  if (!pid) return false;
  try {
    const r = spawnSync('tasklist', ['/FI', `PID eq ${pid}`], {
      encoding: 'utf8', timeout: 10000, shell: false,
    });
    return `${r.stdout || ''}`.includes(String(pid));
  } catch {
    return false;
  }
}

// 记录一次采样：**仅在状态变化时**落一行；每个变化行带相对 spawn 的秒数。
function samplerRecord(key, present) {
  const t = samplerState.targets[key];
  const secs = ((Date.now() - samplerState.startedAt) / 1000).toFixed(1);
  if (present) {
    if (!t.everSeen) {
      t.everSeen = true;
      t.firstSeen = secs;
    }
    t.lastSeen = secs;
  }
  if (t.present !== present) {
    const line = `[sampler +${secs}s] ${t.label}: ${present ? '出现' : '消失'}`;
    samplerLines.push(line);
    driverLog.push(`${line}\n`);
    console.log(line);
    t.present = present;
  }
}

async function samplerTick() {
  try {
    const now = Date.now();
    samplerRecord('app', processExists('asd-tauri.exe'));
    samplerRecord('native', processExists('msedgedriver.exe'));
    samplerRecord('vite', await checkPort('127.0.0.1', 5173));
    samplerRecord('tauri', pidAlive(tauriDriverProcess?.pid));
    // 心跳：即便毫无变化也每 30s 报一次当前四项的布尔值，证明采样器自身存活
    if (now - samplerState.beatAt >= 30000) {
      samplerState.beatAt = now;
      const secs = ((now - samplerState.startedAt) / 1000).toFixed(1);
      const alive = Object.values(samplerState.targets)
        .map((t) => `${t.label}=${t.present}`).join(' ');
      const line = `[sampler 心跳 +${secs}s] ${alive}`;
      samplerLines.push(line);
      driverLog.push(`${line}\n`);
      console.log(line);
    }
  } catch (e) {
    const line = `[sampler 异常] ${e.message}`;
    samplerLines.push(line);
    driverLog.push(`${line}\n`);
    console.log(line);
  }
}

// 收尾：停表 + 输出各目标「是否曾出现 / 首次 / 最后」汇总
// 自调度：前 15s 用 1s 网格（闪退窗口只有几秒，3s 太粗），之后回到 3s。
// 用 setTimeout 自调度而非固定 setInterval，是因为间隔需要在运行中切换。
function samplerSchedule() {
  const elapsed = Date.now() - samplerState.startedAt;
  const delay = elapsed < 15000 ? 1000 : 3000;
  samplerTimer = setTimeout(async () => {
    await samplerTick();
    samplerSchedule();
  }, delay);
  if (samplerTimer.unref) samplerTimer.unref();
}

function samplerStop() {
  if (samplerTimer) {
    clearTimeout(samplerTimer);
    samplerTimer = null;
  }
  const lines = ['[sampler 汇总] 时刻为相对 tauri-driver spawn 的秒数'];
  for (const t of Object.values(samplerState.targets)) {
    lines.push(
      t.everSeen
        ? `[sampler 汇总] ${t.label}: 曾出现，首次 +${t.firstSeen}s，最后 +${t.lastSeen}s`
        : `[sampler 汇总] ${t.label}: 从未出现`
    );
  }
  samplerLines.push(...lines);
  driverLog.push(lines.join('\n') + '\n');
  console.log(lines.join('\n'));
  try {
    if (!existsSync(reportsDir)) mkdirSync(reportsDir, { recursive: true });
    writeFileSync(resolve(reportsDir, 'e2e-sampler.log'), samplerLines.join('\n') + '\n', 'utf-8');
  } catch {
    // 落盘失败不阻塞
  }
}

// 轮询等待端口进入监听状态
async function waitForPort(host, port, timeoutMs = 40000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await checkPort(host, port)) return true;
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

export const config = {
  runner: 'local',
  specs: ['./specs/**/*.spec.js'],
  // 避免并发启动多个 Tauri 实例
  maxInstances: 1,
  // 显式指定 tauri-driver 监听地址与端口（避免 "Unknown browser name" 错误）
  hostname: '127.0.0.1',
  port: 4444,
  capabilities: [
    {
      browserName: 'wry',
      // (a) 强制走经典 WebDriver，不协商 BiDi。
      // 依据：wdio 9+ 默认用 WebDriver BiDi，会自动往 alwaysMatch 注入 webSocketUrl: true；
      //      tauri-driver 原样转发给 msedgedriver，但**不代理 BiDi websocket**。
      //      这是 tauri-apps/tauri#15415 给出的官方绕行（修复 PR #15605 至今 open）。
      'wdio:enforceWebDriverClassic': true,
      'tauri:options': {
        // 使用绝对路径，避免 tauri-driver 工作目录歧义
        application: binaryAbsPath,
        // (b) 把远程调试端口送进 WebView2 的**浏览器进程**。
        //     ⚠️ 不能靠给宿主 exe 传命令行参数 —— MS 文档对 ms:edgeOptions.args 明确写：
        //     "If you're launching a WebView2 app, then these arguments are passed to your app
        //      instead of the underlying Microsoft Edge browser process. To pass arguments to the
        //      browser process when launching a WebView2 app, use webviewOptions.additionalBrowserArguments"
        //     类型已核实为 **list of strings**（不是字符串），文档示例 ['start-maximized','log-level=0']。
        //     =0：让 WebView2 自选空闲端口并写出 DevToolsActivePort 文件；
        //     刻意不用固定端口，避免并行 / 重跑时端口撞车。
        //     转发链路：tauri-driver crates/tauri-driver/src/server.rs:60-61
        //     ms_edge_options.insert("webviewOptions", webview_options)
        webviewOptions: {
          additionalBrowserArguments: ['--remote-debugging-port=0'],
          userDataFolder: webviewUserDataFolder,
        },
      },
    },
  ],
  logLevel: 'info',
  waitforTimeout: 10000,
  // 默认 60000 —— **不要**把默认值调大，否则以后每一轮 E2E 都会白等几分钟。
  // 仅诊断时用环境变量 E2E_TIMEOUT_MS 放宽，用途是「换取被超时吃掉的真正错误串」：
  // run 35343866509 实测，60s 超时先触发，WebDriver 的真实错误根本没机会出现
  // （全日志 grep "DevToolsActivePort|webSocketUrl|session not created" 命中 0 次）；
  // 而上游 tauri-apps/webdriver-example 跑到 4m04s 才吐出
  // `session not created: DevToolsActivePort file doesn't exist`。
  // 放宽超时是为了拿到那串错误，从而区分「webviewOptions 没生效」
  // 与「生效了但后面还有别的阻塞」—— 这两种失败形态含义完全不同。
  connectionRetryTimeout: Number(process.env.E2E_TIMEOUT_MS ?? 60000),
  // ⚠️ 由 3 改为 0。依据：4444 端口就绪已由 onPrepare 的 waitForPort（:474，
  //    **无条件**执行，CI 与本地两条路径都走，无 process.env.CI 分支、无「复用已有
  //    driver」分支）独立把关，workers 是在端口确认监听之后才派发的。
  //    因此这 3 次重试重试的不是「driver 还没起来」，而是**一个已经挂死的 POST
  //    /session** —— run 35327797606 实测：9 个 spec 各 4 次尝试全部超时，
  //    每次都是同一个 connectionRetryTimeout(60s)，4×60s=240s，9×4min=36m32s，
  //    与汇总行 `in 00:36:32` 完全吻合。重试提供的价值为零，只把一轮 CI 反馈
  //    从 ~5 分钟拖到 42 分钟。
  //    connectionRetryTimeout 默认仍是 60000（诊断时可用 E2E_TIMEOUT_MS 覆盖，见上）——
  //    单次会话建立的预算没有被压缩，冷启动慢的场景仍然有完整 60s。
  connectionRetryCount: 0,
  framework: 'mocha',
  mochaOpts: {
    ui: 'bdd',
    timeout: 60000,
  },
  reporters: [['spec', { addConsoleLogs: true }]],

  // ----------------------------------------------------------------
  // onPrepare: 启动 tauri-driver 子进程（监听 4444 端口）
  // 增加诊断日志：检查 binary、前端 dist、Vite dev server、msedgedriver
  // ----------------------------------------------------------------
  onPrepare: async () => {
    // 确保 reports 目录存在
    if (!existsSync(reportsDir)) {
      mkdirSync(reportsDir, { recursive: true });
    }

    // ===== 诊断日志：记录 E2E 启动环境状态 =====
    const diagLines = [];
    diagLines.push(`[${new Date().toISOString()}] E2E 诊断启动`);

    // 0. AHK 执行器新鲜度（TD-046）—— 刻意放在**所有耗时检查之前**。
    //
    // `resolve_ahk_executor_path`（src-tauri/src/lib.rs:608）**优先**用
    // `ahk_executor/asd_executor.exe`；只要它存在，便携模式（AutoHotkey64.exe +
    // 当前 executor.ahk）就永远不会被选中。而它是 Ahk2Exe 的编译产物、被 `*.exe`
    // 规则排除在版本库外，**不会随 .ahk 源码改动自动重建**。
    //
    // 2026-09-17 实测代价：本地那份 exe 编译于 2026-06-29，而 executor.ahk /
    // ipc_client.ahk / sender.ahk 分别改到 9/11 / 9/12 / 9/15 —— E2E 一直在拿旧了
    // 2.5 个月的执行器跑，产出 12 条「AHK 子进程未启动 / 未捕获到任何按键事件」的
    // HIGH 已知问题，**全是假的**，还被当成产品缺陷登记进文档。
    //
    // 所以这里**硬失败而不是 warn**：跑旧二进制得到的不是「慢一点」的结果，而是
    // **结论无效**的结果 —— 而且它会被当成产品缺陷写进文档，污染后续判断。
    //
    // 位置也有讲究：Vite 预热实测要 109s（TD-016），若把这条放在预热之后，
    // 每次命中都要先白等两分钟才报错。故排在 onPrepare 的第一项。
    {
      const ahkDir = resolve(projectRoot, 'src-tauri/ahk_executor');
      const ahkExePath = resolve(ahkDir, 'asd_executor.exe');
      if (existsSync(ahkExePath)) {
        const exeMtime = statSync(ahkExePath).mtimeMs;
        const newerSources = readdirSync(ahkDir)
          .filter((f) => f.endsWith('.ahk'))
          .map((f) => ({ f, m: statSync(resolve(ahkDir, f)).mtimeMs }))
          .filter((x) => x.m > exeMtime);
        if (newerSources.length > 0) {
          const detail = newerSources
            .map((x) => `  - ${x.f} (${new Date(x.m).toISOString()})`)
            .join('\n');
          const fatal = [
            '',
            '========================================',
            'FATAL: asd_executor.exe 比 .ahk 源码旧 —— 本次运行结论无效',
            '========================================',
            `编译产物: ${ahkExePath}`,
            `编译时间: ${new Date(exeMtime).toISOString()}`,
            '比它新的源码:',
            detail,
            '',
            'Rust 侧优先用编译产物（resolve_ahk_executor_path，lib.rs:608），',
            '只要它存在就不会走便携模式，所以不重建就会一直用旧执行器。',
            '',
            '处置（二选一）:',
            '  1) 重建: 在 src-tauri/ 下执行 .\\build_ahk.ps1',
            '  2) 改用便携模式（始终跑当前源码）: 把 asd_executor.exe 移出该目录',
            '',
          ].join('\n');
          writeFileSync(resolve(reportsDir, 'FATAL-stale-ahk-executor.txt'), fatal, 'utf-8');
          writeFileSync(
            resolve(reportsDir, 'e2e-diagnostic.log'),
            diagLines.join('\n') + '\n' + fatal + '\n',
            'utf-8'
          );
          throw new Error(fatal);
        }
        diagLines.push(
          `[OK] asd_executor.exe 不比任何 .ahk 源码旧（编译于 ${new Date(exeMtime).toISOString()}）`
        );
      } else {
        diagLines.push(
          '[OK] 无编译产物，走便携模式 AutoHotkey64.exe + executor.ahk（始终是当前源码）'
        );
      }
    }

    // 1. 检查 binary
    if (existsSync(binaryAbsPath)) {
      diagLines.push(`[OK] Binary 存在: ${binaryAbsPath}`);
    } else {
      diagLines.push(`[FAIL] Binary 不存在: ${binaryAbsPath}`);
    }

    // 2. 检查 dist/index.html（前端构建产物）
    const distPath = resolve(__dirname, '../dist/index.html');
    if (existsSync(distPath)) {
      diagLines.push(`[OK] 前端 dist 存在: ${distPath}`);
    } else {
      diagLines.push(`[WARN] 前端 dist 不存在: ${distPath}`);
    }

    // 3. Vite dev server (5173 端口) —— BUG-1 关键修复点
    // debug 构建的 Tauri 二进制走 devUrl（tauri.conf.json build.devUrl），
    // Vite 未运行时 WebView 加载失败 → chrome-error://chromewebdata/ →
    // window.location.origin 为 null → Tauri IPC 自定义协议拒绝 →
    // 所有 invoke 报 "Origin header is not a valid URL"（BUG-1 真因）。
    // 因此这里必须**主动托管** Vite，而不是只告警。
    let viteRunning = await checkPort(VITE_HOST, VITE_PORT);
    if (viteRunning) {
      diagLines.push(`[OK] Vite dev server 已在运行 (${VITE_HOST}:${VITE_PORT})，复用现有实例`);
    } else {
      diagLines.push(`[INFO] Vite dev server 未运行，自动启动...`);
      if (!existsSync(viteBinPath)) {
        diagLines.push(`[FAIL] 未找到 vite 入口: ${viteBinPath}（请先在项目根执行 npm install）`);
      } else {
        viteProcess = spawn(process.execPath, [viteBinPath], {
          cwd: projectRoot,
          stdio: ['ignore', 'pipe', 'pipe'],
          shell: false,
          env: { ...process.env },
        });
        const viteLog = [];
        viteProcess.stdout?.on('data', (d) => viteLog.push(String(d)));
        viteProcess.stderr?.on('data', (d) => viteLog.push(String(d)));
        viteProcess.on('error', (err) => viteLog.push(`spawn error: ${err.message}`));

        viteRunning = await waitForPort(VITE_HOST, VITE_PORT, 40000);
        if (viteRunning) {
          diagLines.push(`[OK] Vite dev server 已启动 (PID ${viteProcess.pid})`);
        } else {
          diagLines.push(`[FAIL] Vite dev server 启动超时（40s）`);
          diagLines.push(viteLog.join('').slice(-2000));
        }
      }
    }
    if (!viteRunning) {
      const fatal = [
        '',
        '========================================',
        'FATAL: Vite dev server 不可用（127.0.0.1:5173 未监听）',
        '========================================',
        'debug 构建的 Tauri 二进制走 devUrl，必须依赖 Vite dev server。',
        '未启动时 WebView 会停留在 chrome-error://chromewebdata/，',
        '导致所有 invoke 报 "Origin header is not a valid URL"。',
        '',
        '排查: 在项目根手动执行 `npx vite` 观察是否能正常监听 5173。',
        '',
      ].join('\n');
      writeFileSync(resolve(reportsDir, 'FATAL-vite-not-running.txt'), fatal, 'utf-8');
      throw new Error(fatal);
    }

    // 3.5 预热 Vite（TD-016）：把首次模块转换的 ~51s 挪到会话建立之前。
    // 复用外部已运行的 Vite 实例时也照样预热 —— 无法判断那个实例的冷热。
    diagLines.push('[INFO] 开始预热 Vite 模块（首次转换极慢，见 TD-016）...');
    diagLines.push(...(await warmupVite()));

    // 4. 检查 msedgedriver.exe
    if (existsSync(msedgedriverExePath)) {
      diagLines.push(`[OK] msedgedriver.exe 存在: ${msedgedriverExePath}`);
    } else {
      diagLines.push(`[FAIL] msedgedriver.exe 不存在: ${msedgedriverExePath}`);
    }

    // 4.5 环境探测：msedgedriver 版本 + WebView2 Runtime 是否在位
    // ⚠️ 为什么必须在**建会话之前**打印：run 35327797606 的失败形态是 tauri-driver
    //    已监听 4444，但对 POST /session 永不返回（9 个 spec 各烧掉 4 分钟全挂）。
    //    当时 tauri-driver 自身的 stdout/stderr 一行都没落盘，所以「卡在哪」无从判断。
    //    这两条探测各用一行输出，即可证实或排除两个待验假设：
    //      ① runner 上根本没有 WebView2 Runtime（ci.yml 的 e2e job 无安装步骤，
    //         仅 :31 的描述文字提到 WebView2）—— 若成立，该通道设计上不可能成功；
    //      ② msedgedriver 版本与 runner 上的 WebView2 不匹配。
    //    输出同时进 artifact（diagLines）和 CI 日志（console.log）。
    {
      const probe = (label, cmd, args) => {
        try {
          const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: 15000, shell: false });
          const raw = `${r.stdout || ''}${r.stderr || ''}${r.error ? ` [error: ${r.error.message}]` : ''}`;
          const line = `[INFO] ${label}: ${raw.trim().split(/\r?\n/).join(' | ') || '(无输出)'}`;
          diagLines.push(line);
          console.log(line);
        } catch (e) {
          const line = `[WARN] ${label} 探测失败: ${e.message}`;
          diagLines.push(line);
          console.log(line);
        }
      };
      if (existsSync(msedgedriverExePath)) {
        probe('msedgedriver --version', msedgedriverExePath, ['--version']);
      } else {
        const line = '[WARN] msedgedriver.exe 不存在，跳过 --version 探测';
        diagLines.push(line);
        console.log(line);
      }
      // WebView2 Evergreen Runtime 在 EdgeUpdate 下的客户端 GUID；pv = 已安装版本。
      // 两个根都查：HKLM WOW6432Node（机器级）/ HKCU（用户级）。
      probe('WebView2 Runtime (HKLM WOW6432Node)', 'reg', [
        'query',
        'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        '/v', 'pv',
      ]);
      probe('WebView2 Runtime (HKCU)', 'reg', [
        'query',
        'HKCU\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        '/v', 'pv',
      ]);
    }

    // 5. 检查 4444 端口是否被占用（tauri-driver 端口冲突）
    const port4444InUse = await checkPort('127.0.0.1', 4444);
    if (port4444InUse) {
      diagLines.push(`[WARN] 端口 4444 已被占用，tauri-driver 可能无法启动`);
    } else {
      diagLines.push(`[OK] 端口 4444 空闲，tauri-driver 可启动`);
    }

    // 6. 检测二进制文件构建模式（devUrl vs frontendDist）
    // 通过扫描二进制文件内容判断:
    //   - 包含 <!DOCTYPE html> → frontendDist 模式（前端已嵌入）
    //   - 不包含 <!DOCTYPE html> → devUrl 模式（需 Vite dev server）
    // devUrl 模式 + Vite 未运行 → WebView 必然显示"127.0.0.1 拒绝连接",主动抛错
    try {
      const exeBuffer = readFileSync(binaryAbsPath);
      // latin1 是单字节编码,二进制安全,不会因多字节字符解析出错
      const exeText = exeBuffer.toString('latin1');
      const hasDevUrl = exeText.includes('127.0.0.1:5173');
      const hasFrontendHtml = exeText.includes('<!DOCTYPE html>');
      const stat = statSync(binaryAbsPath);

      diagLines.push(`[INFO] 二进制构建时间: ${stat.mtime.toISOString()}`);
      diagLines.push(`[INFO] 二进制大小: ${Math.round(exeBuffer.length / 1024 / 1024 * 100) / 100} MB`);
      diagLines.push(`[INFO] 含 devUrl 字符串: ${hasDevUrl}`);
      diagLines.push(`[INFO] 含前端 HTML (<!DOCTYPE html>): ${hasFrontendHtml}`);

      // 注意: 二进制内是否含 "<!DOCTYPE html>" **不能**用来判定运行模式。
      // debug 构建（debug_assertions 开启）即使内嵌了前端资源，运行时仍优先走 devUrl。
      // 实际运行模式的唯一可靠判据是 WebView 加载后的 window.location.href,
      // 由 helpers/tauri.js 的 startApp() 做健全性检查（见 BUG-1）。
      if (hasDevUrl) {
        diagLines.push(`[OK] 二进制含 devUrl 配置: ${hasDevUrl}（debug 构建运行时走 devUrl，已由上方确保 Vite 就绪）`);
      }
      if (hasFrontendHtml) {
        diagLines.push(`[INFO] 二进制含前端 HTML 片段（不据此判定运行模式）`);
      }
    } catch (e) {
      // 重新抛出 FATAL 错误（来自上面的 throw）
      if (e.message && e.message.includes('FATAL')) throw e;
      diagLines.push(`[WARN] 无法检测二进制构建模式: ${e.message}`);
    }

    diagLines.push(`[${new Date().toISOString()}] 诊断完成`);
    writeFileSync(resolve(reportsDir, 'e2e-diagnostic.log'), diagLines.join('\n') + '\n', 'utf-8');

    // 检查 binary 是否存在；不存在则记录到 skip-reason.txt 但不阻塞
    if (!existsSync(binaryAbsPath)) {
      writeFileSync(
        resolve(reportsDir, 'skip-reason.txt'),
        `Binary not found at: ${binaryAbsPath}\n`,
        'utf-8'
      );
    }
    // 检查 msedgedriver.exe 是否存在；缺失则记录但不阻塞（tauri-driver 启动后会因找不到而失败）
    if (!existsSync(msedgedriverExePath)) {
      writeFileSync(
        resolve(reportsDir, 'msedgedriver-missing.txt'),
        `msedgedriver.exe not found at: ${msedgedriverExePath}\n` +
        `tauri-driver will fail to start WebDriver session.\n` +
        `Download from https://msedgedriver.microsoft.com/<EDGE_VERSION>/edgedriver_win64.zip\n`,
        'utf-8'
      );
    }
    // 构造子进程环境变量：将 drivers 目录加入 PATH 头部（额外保险，
    // 主要通过 --native-driver 参数显式指定 msedgedriver 路径）
    const childEnv = {
      ...process.env,
      PATH: `${driversDir};${process.env.PATH || ''}`,
    };
    // 启动 tauri-driver 子进程：
    //   --port 4444           tauri-driver 监听端口
    //   --native-driver PATH  显式指定 msedgedriver.exe 路径（关键！）
    //                         不指定时 tauri-driver 在 Windows 上可能找不到 msedgedriver，
    //                         导致 session not created (HTTP 500)
    // 注意：tauri-driver 是 cargo 安装的 .exe 文件（非 npm .cmd），
    //       使用 shell:false 直接调用，避免 shell 拼接参数时路径解析问题（DEP0190）
    tauriDriverProcess = spawn('tauri-driver', [
      '--port', '4444',
      '--native-driver', msedgedriverExePath,
    ], {
      stdio: ['ignore', 'pipe', 'pipe'],
      // 显式禁用 shell，参数数组直接传递给子进程
      shell: false,
      env: childEnv,
    });
    // 复用模块级 driverLog（onComplete 需要可见），仅做清空
    driverLog.length = 0;
    tauriDriverProcess.stdout?.on('data', (d) => driverLog.push(String(d)));
    tauriDriverProcess.stderr?.on('data', (d) => driverLog.push(String(d)));
    tauriDriverProcess.on('error', (err) => {
      driverLog.push(`spawn error: ${err.message}`);
      writeFileSync(
        resolve(reportsDir, 'tauri-driver-error.txt'),
        `Failed to start tauri-driver: ${err.message}\n`,
        'utf-8'
      );
    });
    tauriDriverProcess.on('exit', (code, signal) => {
      driverLog.push(`tauri-driver exited: code=${code} signal=${signal}`);
      // 进程自己退出时也要留下输出（例如 --native-driver 拉不起来而静默退出）
      dumpDriverLog();
    });

    // 启动进程/端口采样器（第七道死因排查）：每 3s 采一次，但只在**状态变化**时落行。
    // 判别口径：应用进程从未出现 ⇒ tauri-driver 没走到拉起应用；
    //           应用出现并常驻 ⇒ 应用起来了但 WebView 不就绪（devUrl/Vite 或桌面会话）。
    samplerState.startedAt = Date.now();
    samplerState.beatAt = Date.now();
    // ⚠️ 首轮必须**同步立即**采一次（+0.0s 基线），否则「从未出现」无法区分两种成因：
    //    ① tauri-driver 根本没拉起应用；② 应用被拉起但在首轮采样之前就闪退。
    //    ② 恰恰是更可能的故障形态（启动期崩溃），若读成 ① 会把排查引向错误方向。
    await samplerTick();
    // 前 15s 用 1s 网格，之后回到 3s
    samplerSchedule();

    // ⚠️ 原来是「固定 sleep 2000ms 就继续」：端口没起来也照样发 9 个 worker，
    //    全部 ECONNREFUSED —— 真正的失败（--native-driver 指向不存在的
    //    msedgedriver.exe）被伪装成「driver 拒绝连接」，run 35310528367 实测
    //    排查全靠下载 artifact 才定位。改成**轮询校验 + 带输出硬失败**。
    const driverReady = await waitForPort('127.0.0.1', 4444, 30000);
    if (!driverReady) {
      const fatal = [
        '',
        '========================================',
        'FATAL: tauri-driver 未能在 30s 内监听 127.0.0.1:4444',
        '========================================',
        `启动命令: tauri-driver --port 4444 --native-driver ${msedgedriverExePath}`,
        `--native-driver 目标是否存在: ${existsSync(msedgedriverExePath)}`,
        `PID: ${tauriDriverProcess?.pid}`,
        '',
        '--- tauri-driver 输出 ---',
        driverLog.join('') || '(无输出)',
        '',
      ].join('\n');
      writeFileSync(resolve(reportsDir, 'FATAL-tauri-driver-not-listening.txt'), fatal, 'utf-8');
      throw new Error(fatal);
    }
    diagLines.push('[OK] tauri-driver 已在 127.0.0.1:4444 监听');
  },

  // ----------------------------------------------------------------
  // before: 每个 spec 文件执行前的全局钩子（M39）
  // 检查 binary 存在性，不存在则跳过所有测试（不 fail）。
  // AGENTS.md 强制规范："binary 缺失时所有测试 skip（不 fail）"。
  // ----------------------------------------------------------------
  before: function (capabilities, specs) {
    if (!existsSync(binaryAbsPath)) {
      // this.skip 在 Mocha 框架下可用于跳过当前 suite
      this.skip(`Binary not found at: ${binaryAbsPath}`);
    }
  },

  // ----------------------------------------------------------------
  // beforeTest: 全局 beforeEach 钩子，清理 reports/key_log.txt
  // ----------------------------------------------------------------
  beforeTest: function () {
    // M39 补充：before 钩子的 this.skip 在某些 WebDriverIO 版本中可能不生效，
    // 此处作为兜底检查，确保 binary 缺失时测试一定被跳过
    if (!existsSync(binaryAbsPath)) {
      this.skip(`Binary not found at: ${binaryAbsPath}`);
    }
    const keyLogPath = resolve(reportsDir, 'key_log.txt');
    try {
      if (existsSync(keyLogPath)) {
        unlinkSync(keyLogPath);
      }
    } catch {
      // 清理失败时忽略，不阻塞测试
    }
  },

  // ----------------------------------------------------------------
  // afterSpec: 每个 spec 文件执行完毕后清理残留进程
  // closeApp 调用 win.close() 后，Tauri 应用异步退出（graceful_shutdown）
  // 如果 graceful_shutdown 超时（IPC 超时 + WM_CLOSE 超时），进程可能残留
  // 这里强制杀死残留进程，防止下一个 spec 启动时冲突
  // ----------------------------------------------------------------
  afterSpec: async () => {
    try {
      // 强制终止残留的 Tauri 应用和 AHK 执行器
      // /F = 强制终止, /T = 终止子进程, 2>nul = 忽略错误
      execSync('taskkill /F /IM asd-tauri.exe /T 2>nul', { stdio: 'ignore' });
      execSync('taskkill /F /IM asd_executor.exe /T 2>nul', { stdio: 'ignore' });
    } catch { /* 忽略错误（进程可能已退出） */ }
    // 等待 1 秒确保进程完全退出和资源释放
    await new Promise(resolve => setTimeout(resolve, 1000));
  },

  // ----------------------------------------------------------------
  // onComplete: 关闭 tauri-driver 子进程
  // ----------------------------------------------------------------
  onComplete: () => {
    // ⚠️ 无条件落盘 tauri-driver 输出 —— 不再只在 waitForPort 失败时写。
    // 同时把尾部摘要打进 CI 日志（截断，避免超长），这样即使 artifact 没人下载，
    // 日志里也能直接看到「/session 不返回时 tauri-driver 在干什么」。
    // 先停采样器并出汇总（会写进 driverLog，故必须在 dumpDriverLog 之前）
    samplerStop();

    // ===== [UDF 探测 A/B] WebView2 是否真的写了 DevToolsActivePort =====
    // 判据：任一候选「找到」⇒ 目录已对齐（若仍失败则是别的原因）；
    //       两个候选都「存在但无」⇒ WebView2 根本不写该文件，「靠 webviewOptions
    //       开调试端口」这条路整体不成立，直接指向方案 1，不要再找第三个目录；
    //       两候选都「不存在」⇒ 推导仍错，先修推导。
    // ⚠️ 刻意扫**两个**候选而不单点赌：本轮推导已被推翻过一次（见上方 UDF 注释），
    //    单点赌错就要再付一轮 5 分钟 CI。两个都打印，一次拿全。
    // ⚠️ 放 onComplete 是为了「无论如何都执行」；位置紧挨 samplerStop() 之后、
    //    dumpDriverLog() 之前，这样探测结果会被 dumpDriverLog 一起落盘。
    // ⚠️ 用 Node 的 fs API，不用 `dir /s`（沙箱禁 powershell，且大目录上很慢）。
    {
      const udfLines = [];
      const candidates = [
        ['A', webviewUserDataFolder],
        ['B', webviewUserDataFolderLegacy],
      ];
      for (const [tag, dir] of candidates) {
        try {
          if (!dir) {
            udfLines.push(`[UDF 探测 ${tag}] 路径为空（LOCALAPPDATA 未设置？），跳过`);
            continue;
          }
          if (!existsSync(dir)) {
            udfLines.push(`[UDF 探测 ${tag}] 目录不存在: ${dir}`);
            continue;
          }
          const entries = readdirSync(dir);
          if (!entries.includes('DevToolsActivePort')) {
            udfLines.push(
              `[UDF 探测 ${tag}] 目录存在但无 DevToolsActivePort（共 ${entries.length} 项）: ${dir}`
            );
            udfLines.push(`[UDF 探测 ${tag}] 目录条目: ${entries.join(', ') || '(空)'}`);
            continue;
          }
          // 找到就原样打印文件内容（第一行是端口，第二行是 /devtools/browser 路径）
          const content = readFileSync(resolve(dir, 'DevToolsActivePort'), 'utf-8');
          udfLines.push(`[UDF 探测 ${tag}] 找到 DevToolsActivePort，端口=${content.trim()}`);
          udfLines.push(`[UDF 探测 ${tag}] 所在目录: ${dir}`);
        } catch (e) {
          udfLines.push(`[UDF 探测 ${tag}] 探测失败: ${e.message}`);
        }
      }
      // 同时进 driverLog（落盘）与 CI 日志（直接可见）
      driverLog.push(udfLines.join('\n') + '\n');
      console.log(udfLines.join('\n'));
    }

    dumpDriverLog();
    const tail = driverLog.join('').slice(-4000).trim();
    console.log(`[tauri-driver 输出尾部] ${tail || '(无输出)'}`);
    // sampler 单独全量打印一份，不受上面 4000 字符截断影响
    console.log(`[sampler 全量 ${samplerLines.length} 行]\n${samplerLines.join('\n')}`);
    if (viteProcess) {
      try {
        // Windows: /T 终止整个子进程树，避免残留 esbuild / node 子进程占用 5173
        execSync(`taskkill /PID ${viteProcess.pid} /T /F`, { stdio: 'ignore' });
      } catch {
        try {
          viteProcess.kill();
        } catch {
          // 进程可能已退出
        }
      }
      viteProcess = null;
    }
    if (tauriDriverProcess) {
      try {
        tauriDriverProcess.kill();
      } catch {
        // 进程可能已退出
      }
      tauriDriverProcess = null;
    }
  },
};
