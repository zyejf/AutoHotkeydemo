// =================================================================
// 「诊断信息」页与 UI 事件接线的静态契约测试
// =================================================================
// 为什么需要它：
//   本轮为事故可观测性新增了「🩺 诊断信息」页（版本号 + 日志目录 + 一键复制），
//   约 120 行 UI 代码。它有两条**错了不会报错、只会给错信息**的性质：
//
//   1. **日志目录口径**：Rust 侧日志实际落在 `app.path().app_data_dir()`
//      （`src-tauri/src/infrastructure/logging.rs:19-33`，文件名前缀 `asd`）。
//      前端若误取 `appLogDir()`（Tauri 另一个目录 API），编译、lint、构建全绿，
//      只会**给用户一个打不开的路径** —— 而这一页存在的唯一目的就是在事故时
//      给出可用信息，给错等于比不给更糟。这条把「为什么是 appDataDir」钉死。
//
//   2. **按钮点了没反应**：页面走 `data-action` 事件委托（CSP 已去掉
//      `unsafe-inline`，不能用内联 `onclick`）。HTML 里写了一个 `data-action`，
//      `main.js` 里却没有对应分支时，**没有任何报错**，按钮就是静默无效。
//      这条做 HTML → JS 的单向对拍。
//
//   与 `api_contract.test.js` 同一思路：只读源码、不跑构建、不依赖
//   `@tauri-apps/api` 能否解析，因此不会因 Tauri 运行时缺失而假失败。
//
// 运行：node --test src/__tests__/*.test.js
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ASD_TAURI = join(__dirname, '..', '..'); // asd-tauri/

const INDEX_HTML = join(ASD_TAURI, 'index.html');
const API_JS = join(ASD_TAURI, 'src', 'api.js');
const MAIN_JS = join(ASD_TAURI, 'src', 'main.js');

const read = (p) => readFileSync(p, 'utf8');

/// 取出某个函数的源码片段：从 `function <name>(` 起，到下一个顶层声明为止。
function functionSource(src, name) {
  const start = src.indexOf(`function ${name}(`);
  if (start < 0) return '';
  const rest = src.slice(start);
  const marks = ['\nexport ', '\nfunction ', '\nconst ', '\nvar ', '\nlet '];
  const cuts = marks
    .map((m) => rest.indexOf(m, 1))
    .filter((i) => i > 0);
  return cuts.length ? rest.slice(0, Math.min(...cuts)) : rest;
}

/// 收集 HTML 里所有 `data-action="X"`（只取静态写死的，动态拼接的不在范围内）。
function htmlActions(html) {
  return new Set([...html.matchAll(/data-action="([A-Za-z]+)"/g)].map((m) => m[1]));
}

/// 收集 main.js 事件分发器里所有 `action === 'X'` 分支。
function jsHandledActions(js) {
  return new Set(
    [...js.matchAll(/action\s*===\s*['"]([A-Za-z]+)['"]/g)].map((m) => m[1])
  );
}

const INLINE_HANDLER_RE = /\son(?:click|change|input|submit|keydown|keyup|blur|focus|dblclick|mouse[a-z]+)\s*=/gi;

describe('data-action 事件接线完整性', () => {
  test('抽取得出内容（防止解析器静默失效）', () => {
    const html = read(INDEX_HTML);
    const js = read(MAIN_JS);
    assert.ok(htmlActions(html).size > 20, 'index.html 应抽出足量 data-action');
    assert.ok(jsHandledActions(js).size > 20, 'main.js 应抽出足量分发分支');
  });

  test('HTML 里每个 data-action 都在 main.js 有对应分支（防"按钮点了没反应"）', () => {
    const declared = htmlActions(read(INDEX_HTML));
    const handled = jsHandledActions(read(MAIN_JS));
    const unhandled = [...declared].filter((a) => !handled.has(a));
    assert.deepEqual(
      unhandled,
      [],
      `以下 data-action 在 index.html 中声明但 main.js 无分发分支，点击会静默无效：${unhandled.join(', ')}`
    );
  });

  test('诊断页的两个 action 已接线（本轮新增，重点盯）', () => {
    const handled = jsHandledActions(read(MAIN_JS));
    for (const a of ['copyDiagnostics', 'refreshDiagnostics']) {
      assert.ok(handled.has(a), `main.js 缺少 ${a} 的分发分支`);
    }
  });
});

describe('诊断信息页的取值口径', () => {
  test('日志目录取 appDataDir()，而不是 appLogDir()', () => {
    const src = read(API_JS);
    const body = functionSource(src, 'getLogDirPath');
    assert.ok(body, 'api.js 中应存在 getLogDirPath()');
    assert.ok(
      /\bappDataDir\s*\(/.test(body),
      'getLogDirPath() 必须返回 appDataDir() —— Rust 日志实际落在 app_data_dir()（logging.rs:19-33）'
    );
    assert.ok(
      !/\bappLogDir\s*\(/.test(body),
      'getLogDirPath() 不得返回 appLogDir() —— 那是 Tauri 的另一个目录，与 Rust 日志落盘位置不一致'
    );
  });

  test('版本号走 getVersion()（不硬编码，避免与 tauri.conf.json 漂移）', () => {
    const body = functionSource(read(API_JS), 'getAppVersion');
    assert.ok(body, 'api.js 中应存在 getAppVersion()');
    assert.ok(/\bgetVersion\s*\(/.test(body), 'getAppVersion() 必须调用 getVersion()');
    // 硬编码版本字符串会让产物版本与界面自述分叉（见台账 TD-078）。
    assert.ok(
      !/\breturn\s*['"]\d+\.\d+/.test(body),
      'getAppVersion() 不得硬编码版本字符串（与 tauri.conf.json 会分叉，见 TD-078）'
    );
  });
});

describe('CSP 硬指标（#16 修复的回归防线）', () => {
  test('index.html 无内联事件处理器', () => {
    const hits = read(INDEX_HTML).match(INLINE_HANDLER_RE) || [];
    assert.deepEqual(
      hits,
      [],
      `index.html 出现内联事件处理器，CSP 的 script-src 'self' 无 unsafe-inline 会直接拦掉：${hits.join(', ')}`
    );
  });

  test('main.js 生成的 HTML 字符串也无内联事件处理器', () => {
    // innerHTML 注入的 onclick 同样受 CSP 约束，且比静态 HTML 更难发现。
    const hits = read(MAIN_JS).match(INLINE_HANDLER_RE) || [];
    assert.deepEqual(
      hits,
      [],
      `main.js 生成的 HTML 出现内联事件处理器，会被 CSP 拦掉：${hits.slice(0, 5).join(', ')}`
    );
  });
});

describe('诊断页结构与失败兜底', () => {
  test('必需元素齐备（页面 / 版本 / 日志目录 / 兜底区）', () => {
    const html = read(INDEX_HTML);
    for (const id of [
      'page-diagnostics',
      'diagVersion',
      'diagLogDir',
      'diagFallbackHint',
      'diagFallbackText',
    ]) {
      assert.ok(html.includes(`id="${id}"`), `index.html 缺少 #${id}`);
    }
  });

  test('复制失败有兜底路径（不静默失败）', () => {
    const js = read(MAIN_JS);
    assert.ok(/function showDiagFallback\s*\(/.test(js), '缺少 showDiagFallback()');
    assert.ok(/function legacyCopyText\s*\(/.test(js), '缺少 legacyCopyText()');
    // 有兜底函数还不够：必须真的被 copyDiagnostics 调到，否则等于没写。
    const body = functionSource(js, 'copyDiagnostics');
    assert.ok(body, 'main.js 中应存在 copyDiagnostics()');
    assert.ok(
      /showDiagFallback\s*\(/.test(body),
      'copyDiagnostics() 必须在复制失败时调用 showDiagFallback() —— 否则用户点了复制却什么也没发生'
    );
  });
});

// =================================================================
// 执行器失败态的自助恢复（TD-082 / 阻断项 B4 的真实缺口）
// =================================================================
// ⚠️ 定性的订正：B4 原判「UI 零提示」并不成立 —— Rust 侧
// `update_watchdog_state`(asd-application/src/state.rs:343) 轮询到状态变化就 emit
// `executor_status`，前端 onExecutorStatus 会把导航栏圆点变红、文字改「失败」。
// 判据里那个「grep getExecutorStatus/resetWatchdog 零命中」只证明了**拉模式命令没被调用**，
// 推模式通道一直是通的。真正缺的是：① 进入 Failed 时只有 6px 圆点变色，没有 toast；
// ② api.js 里的 resetWatchdog() 封装从未被 UI 调用，没有任何自助恢复入口。
// 下面 4 条把这两条缺口钉住，并防「Rust 加状态变体 / 前端漏翻」的漂移。
describe('执行器状态的自助恢复入口（TD-082 / B4）', () => {
  // 与 Rust WatchdogStateEnum（asd-domain/src/config.rs:299 起）一一对应
  const WATCHDOG_STATES = ['Idle', 'Starting', 'Running', 'Hung', 'Restarting', 'Recovering', 'Failed'];

  test('EXEC_STATUS_MAP 覆盖 WatchdogStateEnum 全部变体（防状态名漂移）', () => {
    const js = read(MAIN_JS);
    const m = js.match(/var EXEC_STATUS_MAP = \{([^}]*)\}/);
    assert.ok(m, 'main.js 中应存在 EXEC_STATUS_MAP');
    const keys = [...m[1].matchAll(/(\w+)\s*:/g)].map((x) => x[1]);
    assert.deepEqual(
      keys.sort(),
      [...WATCHDOG_STATES].sort(),
      `EXEC_STATUS_MAP 的键必须与 Rust WatchdogStateEnum 一致：多一个键是已删的过期状态，` +
      `少一个键会把英文原文直接显示给用户（当前前端=${keys.join(',')}）`
    );
  });

  test('诊断页有状态/重启次数元素，且有一键重置入口', () => {
    const html = read(INDEX_HTML);
    for (const id of ['diagExecStatus', 'diagExecRestart']) {
      assert.ok(html.includes(`id="${id}"`), `index.html 缺少 #${id}`);
    }
    assert.ok(/data-action="resetWatchdog"/.test(html), 'index.html 缺少「重置看门狗」按钮');
  });

  test('resetWatchdogDiag() 真的调用 api.resetWatchdog()（防按钮静默无效）', () => {
    const body = functionSource(read(MAIN_JS), 'resetWatchdogDiag');
    assert.ok(body, 'main.js 中应存在 resetWatchdogDiag()');
    assert.ok(
      /api\.resetWatchdog\s*\(/.test(body),
      'resetWatchdogDiag() 必须调用 api.resetWatchdog() —— 该封装此前一直零调用，正是本条债的成因'
    );
  });

  test('进入 Failed 有 toast + 日志，且只在状态跃迁时提示一次', () => {
    const m = read(MAIN_JS).match(/api\.onExecutorStatus\(function\(data\) \{[\s\S]*?\n {2}\}\);/);
    assert.ok(m, '未找到 onExecutorStatus 处理函数');
    const body = m[0];
    assert.ok(
      /showToast\(/.test(body) && /Failed/.test(body),
      'onExecutorStatus 必须在 Failed 时给 toast —— 仅 6px 圆点变色用户不会注意到'
    );
    assert.ok(/addLog\(/.test(body), 'onExecutorStatus 在 Failed 时应落一条 error 日志');
    assert.ok(
      /_lastExecStatus\s*!==\s*["']Failed["']/.test(body),
      'Failed 提示必须由「上一次状态」守卫 —— 事件每次状态变化都推，不守卫会反复弹 toast'
    );
    assert.ok(/_lastExecStatus\s*=/.test(body), '必须在处理末尾更新 _lastExecStatus');
  });
});
