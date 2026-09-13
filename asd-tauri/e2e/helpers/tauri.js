// =================================================================
// Tauri 交互辅助函数 - 封装 window.__TAURI__.core.invoke 调用
// =================================================================
// 注：使用 browser.execute（同步）+ 轮询模式，而非 browser.executeAsync。
// 原因：msedgedriver 在 Tauri webview 上执行 /execute/async 端点时报错
// "Origin header is not a valid URL"（Tauri 自定义协议 origin 不被识别）。
// /execute/sync 端点正常工作，因此用同步执行 + 全局变量轮询模拟异步。
// =================================================================
import { execSync } from 'node:child_process';
import { extractErrorMessage, extractDeepErrorMessage, isFatalProtocolError } from './error_utils.js';

/**
 * 通过 browser.execute + 轮询调用 window.__TAURI__.core.invoke(command, args)
 * @param {object} browser - WebDriverIO browser 实例
 * @param {string} command - Tauri 命令名（如 get_config）
 * @param {object} args - 命令参数对象
 * @returns {Promise<any>} 命令返回结果
 */
export async function invoke(browser, command, args = {}) {
  // 清除上次的结果
  await browser.execute(() => { window.__e2e_result = null; });

  // 启动 invoke，Promise 结果写入 window.__e2e_result
  await browser.execute((cmd, cmdArgs) => {
    // 检查 __TAURI__ 是否存在（Tauri 后端初始化完成才会注入）
    if (!window.__TAURI__ || !window.__TAURI__.core || typeof window.__TAURI__.core.invoke !== 'function') {
      window.__e2e_result = {
        ok: false,
        error: 'window.__TAURI__ or core.invoke not available (Tauri backend not initialized)',
      };
      return;
    }
    Promise.resolve(window.__TAURI__.core.invoke(cmd, cmdArgs))
      .then((data) => { window.__e2e_result = { ok: true, data }; })
      .catch((err) => {
        // 将错误转为可序列化结构。
        // Error 实例经 WebDriverIO JSON 化会丢失 message，必须在此提取。
        // AppError {kind, message} 对象（I34 结构化序列化）原样保留字段，
        // 由 Node 侧 extractErrorMessage 统一提取，避免得到 "[object Object]"。
        let errorObj;
        if (err != null && typeof err === 'object') {
          errorObj = { message: String(err.message ?? ''), kind: err.kind };
        } else if (typeof err === 'string') {
          errorObj = { message: err };
        } else {
          errorObj = { message: String(err) };
        }
        window.__e2e_result = { ok: false, error: errorObj };
      });
  }, command, args);

  // 轮询等待结果（最多 15 秒 = 150 次 * 100ms）
  // 注意：browser.execute() 可能因 tauri-driver/msedgedriver 的 flaky 问题
  // 抛出 "unknown error"（HTTP 200 with error body）。
  // 此时需要继续重试而非直接抛出，因为 invoke 可能已在后端成功执行。
  let wrapped = null;
  let lastExecuteError = null;
  const maxAttempts = 150;
  for (let i = 0; i < maxAttempts; i++) {
    try {
      wrapped = await browser.execute(() => window.__e2e_result);
      if (wrapped) break;
    } catch (e) {
      // BUG-5：立即判定是否为协议层确定性错误。这类错误重试 150 次毫无意义，
      // 只会把失败延迟 15 秒并掩盖真实原因（旧实现 String(e) 得到 "[object Object]"）。
      const deep = extractDeepErrorMessage(e, '');
      if (isFatalProtocolError(deep)) {
        lastExecuteError = e;
        break;
      }
      lastExecuteError = e;
    }
    await new Promise((r) => setTimeout(r, 100));
  }

  if (!wrapped || !wrapped.ok) {
    // wrapped.error 是浏览器侧提取的可序列化错误对象 {message, kind?}，
    // 用 extractErrorMessage 统一提取可读消息（兼容 AppError {kind, message} 格式）。
    //
    // BUG-5：fallback 改用 extractDeepErrorMessage 深度展开，而非旧实现的
    // String(lastExecuteError)。协议层错误的真实原因（如
    // "Origin header is not a valid URL"）藏在嵌套字段，String() 会把它丢成
    // "[object Object]: unknown error"，导致失败长期无法定位。
    const fallback = lastExecuteError
      ? extractDeepErrorMessage(lastExecuteError, 'invoke timeout (15s)')
      : 'invoke timeout (15s)';
    const errMsg = extractErrorMessage(wrapped?.error, fallback);
    throw new Error(`Tauri invoke('${command}') failed: ${errMsg}`);
  }
  return wrapped.data;
}

/**
 * 调用 get_executor_status 命令，获取执行器/看门狗状态
 */
export async function getExecutorStatus(browser) {
  return invoke(browser, 'get_executor_status', {});
}

/**
 * 调用 get_config 命令，获取当前配置
 */
export async function getConfig(browser) {
  return invoke(browser, 'get_config', {});
}

/**
 * 调用 save_config 命令，保存配置
 * @param {object} config - Config 结构体
 */
export async function saveConfig(browser, config) {
  return invoke(browser, 'save_config', { config });
}

/**
 * 等待应用窗口就绪（窗口标题非空）
 * @param {object} browser - WebDriverIO browser 实例
 */
export async function startApp(browser) {
  await browser.waitUntil(
    async () => {
      try {
        const title = await browser.getTitle();
        return typeof title === 'string' && title.length > 0;
      } catch {
        return false;
      }
    },
    {
      timeout: 30000,
      timeoutMsg: 'App window did not become ready within 30s',
      interval: 500,
    }
  );

  // 页面加载健全性检查（BUG-1 防回归）
  // 窗口标题非空**不代表页面加载成功**：Tauri 从 tauri.conf.json 取标题，
  // 即使 WebView 停在网络错误页 chrome-error://chromewebdata/ 标题依然有值。
  // 该错误页的 origin 为 null，会让 Tauri IPC 自定义协议拒绝所有 invoke，
  // 报 "Origin header is not a valid URL" —— 表面看像 IPC/协议问题，
  // 真因却是 devUrl 指向的 Vite dev server 未启动。
  // 这里提前断言，把 15 秒后的 "unknown error" 变成即时、可定位的失败。
  try {
    const page = await browser.execute(() => ({
      href: window.location.href,
      protocol: window.location.protocol,
      hasTauri: !!(window.__TAURI__ && window.__TAURI__.core && typeof window.__TAURI__.core.invoke === 'function'),
      bodyText: (document.body ? document.body.innerText : '').slice(0, 300),
    }));
    if (page.protocol === 'chrome-error:' || page.href.startsWith('chrome-error://')) {
      throw new Error(
        `应用页面未加载：WebView 停留在错误页 ${page.href}。\n` +
        `错误页内容: ${page.bodyText.replace(/\s+/g, ' ').trim()}\n` +
        `最可能原因: debug 二进制走 devUrl，但 Vite dev server (127.0.0.1:5173) 未运行。\n` +
        `修复: wdio.conf.js 的 onPrepare 会自动启动 Vite；若仍失败请检查项目根 npm install 与 5173 端口占用。`
      );
    }
    if (!page.hasTauri) {
      throw new Error(
        `window.__TAURI__.core.invoke 不可用（页面 ${page.href}，protocol=${page.protocol}）。\n` +
        `Tauri 后端未初始化完成或页面加载异常。`
      );
    }
  } catch (e) {
    // 上面的诊断性 Error 直接向上抛；WebDriver 本身的异常也一并附上上下文
    throw e;
  }

  return browser;
}

/**
 * 关闭应用窗口
 * @param {object} browser - WebDriverIO browser 实例
 */
export async function closeApp(browser) {
  try {
    await browser.execute(() => {
      const tauri = window.__TAURI__;
      if (tauri && tauri.window && typeof tauri.window.getCurrentWindow === 'function') {
        const win = tauri.window.getCurrentWindow();
        if (win && typeof win.close === 'function') {
          win.close();
          return;
        }
      }
      window.close();
    });
  } catch {
    // 忽略错误
  }

  // 等待 asd-tauri.exe 进程退出（最多 15 秒）
  // Tauri 应用关闭是异步的（prevent_close + graceful_shutdown + exit）
  // 不等待会导致下一个 spec 启动时残留进程冲突（全局热键、named pipe 等）
  const maxWaitMs = 15000;
  const intervalMs = 500;
  const startTime = Date.now();
  while (Date.now() - startTime < maxWaitMs) {
    try {
      // 检查 asd-tauri.exe 是否还在运行
      const output = execSync('tasklist /FI "IMAGENAME eq asd-tauri.exe" /NH /FO CSV', {
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 2000,
      }).toString();
      if (!output.includes('asd-tauri.exe')) {
        // 进程已退出
        break;
      }
    } catch {
      // tasklist 失败，假设进程已退出
      break;
    }
    await new Promise(resolve => setTimeout(resolve, intervalMs));
  }
}
