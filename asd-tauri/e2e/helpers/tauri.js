// =================================================================
// Tauri 交互辅助函数 - 封装 window.__TAURI__.core.invoke 调用
// =================================================================
// 注：使用 browser.execute（同步）+ 轮询模式，而非 browser.executeAsync。
// 原因：msedgedriver 在 Tauri webview 上执行 /execute/async 端点时报错
// "Origin header is not a valid URL"（Tauri 自定义协议 origin 不被识别）。
// /execute/sync 端点正常工作，因此用同步执行 + 全局变量轮询模拟异步。
// =================================================================

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
    Promise.resolve(window.__TAURI__.core.invoke(cmd, cmdArgs))
      .then((data) => { window.__e2e_result = { ok: true, data }; })
      .catch((err) => {
        window.__e2e_result = {
          ok: false,
          error: err instanceof Error ? err.message : String(err),
        };
      });
  }, command, args);

  // 轮询等待结果（最多 15 秒 = 150 次 * 100ms）
  let wrapped = null;
  const maxAttempts = 150;
  for (let i = 0; i < maxAttempts; i++) {
    wrapped = await browser.execute(() => window.__e2e_result);
    if (wrapped) break;
    await new Promise((r) => setTimeout(r, 100));
  }

  if (!wrapped || !wrapped.ok) {
    const errMsg = wrapped?.error || 'invoke timeout (15s)';
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
      // 回退：尝试原生 window.close
      window.close();
    });
  } catch {
    // 窗口可能已关闭，忽略错误
  }
}
