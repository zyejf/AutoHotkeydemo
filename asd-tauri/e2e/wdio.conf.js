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

    // 3. 检查 Vite dev server (5173 端口)
    // 如果 binary 是用 "cargo build" 构建的 debug binary，Tauri 会使用 devUrl 连接 5173
    // 如果 Vite 未运行，WebView 会显示 "127.0.0.1 拒绝连接"
    const viteRunning = await checkPort('127.0.0.1', 5173);
    if (viteRunning) {
      diagLines.push(`[OK] Vite dev server 运行中 (127.0.0.1:5173)`);
    } else {
      diagLines.push(`[WARN] Vite dev server 未运行 (127.0.0.1:5173)`);
      diagLines.push(`      如果 binary 是用 "cargo build" 构建的，WebView 会显示 "连接被拒绝"`);
      diagLines.push(`      解决方案: 用 "npx tauri build --debug --no-bundle" 重新构建，内嵌前端资源`);
    }

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

      // devUrl 模式判断: 不含前端 HTML (纯 cargo build 构建的 debug 版本)
      const isDevUrlMode = !hasFrontendHtml;

      if (isDevUrlMode && !viteRunning) {
        // devUrl 模式 + Vite 未运行 → WebView 必然显示"拒绝连接"
        const errorMsg = [
          '',
          '========================================',
          'FATAL: 二进制为 devUrl 模式且 Vite dev server 未运行',
          '========================================',
          `二进制路径: ${binaryAbsPath}`,
          `构建时间: ${stat.mtime.toISOString()}`,
          `大小: ${Math.round(exeBuffer.length / 1024 / 1024 * 100) / 100} MB`,
          '',
          '原因: 二进制文件用 "cargo build" 构建的 debug 版本,',
          '      运行时连接 http://127.0.0.1:5173 (Vite dev server),',
          '      但 E2E 测试未启动 Vite,导致 WebView 显示 "127.0.0.1 拒绝连接"',
          '',
          '修复: 用 "npx tauri build --debug --no-bundle" 重新构建,嵌入前端资源',
          '  cd asd-tauri',
          '  npx tauri build --debug --no-bundle',
          '',
        ].join('\n');

        writeFileSync(resolve(reportsDir, 'FATAL-devurl-mode.txt'), errorMsg, 'utf-8');
        throw new Error(errorMsg);
      }

      if (hasFrontendHtml) {
        diagLines.push(`[OK] 二进制构建模式: frontendDist (前端已嵌入)`);
      } else if (viteRunning) {
        diagLines.push(`[OK] 二进制构建模式: devUrl (Vite 运行中,可加载前端)`);
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
  // beforeTest: 全局 beforeEach 钩子，清理 reports/key_log.txt
  // ----------------------------------------------------------------
  beforeTest: () => {
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
