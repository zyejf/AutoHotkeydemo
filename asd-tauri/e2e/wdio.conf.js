// =================================================================
// WebDriverIO 配置 - Tauri E2E 测试
// =================================================================
// 通过 tauri-driver（监听 4444 端口）驱动 Tauri 应用窗口
// 所有 JS 使用 ESM 语法（package.json type=module）
// =================================================================
import { spawn, execSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
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

// 全局引用：保存 tauri-driver 子进程，供 onComplete 关闭
let tauriDriverProcess = null;
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
      'tauri:options': {
        // 使用绝对路径，避免 tauri-driver 工作目录歧义
        application: binaryAbsPath,
      },
    },
  ],
  logLevel: 'info',
  waitforTimeout: 10000,
  connectionRetryTimeout: 60000,
  connectionRetryCount: 3,
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
    tauriDriverProcess.on('error', (err) => {
      // tauri-driver 启动失败时记录错误，但不抛出（让用例自行处理）
      writeFileSync(
        resolve(reportsDir, 'tauri-driver-error.txt'),
        `Failed to start tauri-driver: ${err.message}\n`,
        'utf-8'
      );
    });
    // 给 tauri-driver 2 秒启动时间后再继续
    await new Promise((startupResolve) => setTimeout(startupResolve, 2000));
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
