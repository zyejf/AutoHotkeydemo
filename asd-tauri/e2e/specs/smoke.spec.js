// =================================================================
// 冒烟测试 - 验证 Tauri 应用窗口能启动并关闭
// =================================================================
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startApp, closeApp } from '../helpers/tauri.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const binaryPath = resolve(__dirname, '../../target/debug/asd-tauri.exe');

describe('Smoke Test', () => {
  it('E2E-SMOKE-001: 应用窗口能启动并关闭', async function () {
    // binary 不存在时跳过，而非失败
    if (!existsSync(binaryPath)) {
      this.skip(`Binary not found at: ${binaryPath}`);
    }

    // 等待窗口加载就绪
    await startApp(browser);

    // 获取窗口标题并断言非空
    const title = await browser.getTitle();
    if (!title || title.length === 0) {
      throw new Error('Window title is empty');
    }

    // 关闭窗口
    await closeApp(browser);
  });
});
