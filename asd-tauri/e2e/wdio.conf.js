// =================================================================
// WebDriverIO 配置 - Tauri E2E 测试
// =================================================================
// 通过 tauri-driver（监听 4444 端口）驱动 Tauri 应用窗口
// 所有 JS 使用 ESM 语法（package.json type=module）
// =================================================================
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

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
  // ----------------------------------------------------------------
  onPrepare: () => {
    // 确保 reports 目录存在
    if (!existsSync(reportsDir)) {
      mkdirSync(reportsDir, { recursive: true });
    }
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
    return new Promise((startupResolve) => setTimeout(() => startupResolve(), 2000));
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
