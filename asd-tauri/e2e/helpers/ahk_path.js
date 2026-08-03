// =================================================================
// AHK 路径集中管理模块 - 消除 E2E 测试中的硬编码 AHK v2 路径
// =================================================================
// 设计说明：
//   - 支持通过环境变量 AHK_PATH 覆盖默认路径，提升跨机器可移植性
//   - 其他开发者若 AHK 安装在 C:\Program Files\AutoHotkey\ 或使用
//     32 位版本，只需设置 AHK_PATH 环境变量即可，无需修改源码
// =================================================================

// 默认 AHK v2 可执行文件路径（64 位）
const DEFAULT_AHK_PATH = 'D:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';

/**
 * 获取 AHK v2 可执行文件路径
 * 优先级：环境变量 AHK_PATH > 默认路径
 * @returns {string} AHK 可执行文件绝对路径
 */
export function getAhkPath() {
  return process.env.AHK_PATH || DEFAULT_AHK_PATH;
}

/**
 * 获取 AHK v2 可执行文件所在目录
 * @returns {string} 目录路径（不含文件名）
 */
export function getAhkDir() {
  const ahkPath = getAhkPath();
  return ahkPath.substring(0, ahkPath.lastIndexOf('\\'));
}

export { DEFAULT_AHK_PATH };
