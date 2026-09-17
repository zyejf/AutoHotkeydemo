// =================================================================
// 前端 API 层 ↔ Rust 命令 的契约测试（TD-005 / TD-007）
// =================================================================
// 为什么需要它：
//   `src/api.js` 是前端唯一与 Rust 通信的出口，每个函数 invoke 一个命令名并传一组参数。
//   命令名写错、参数漏传、参数名大小写不对（JS camelCase ↔ Rust snake_case）——
//   这三种错**都要等运行到那一步才炸**，而且 Tauri 的报错（invalid args ... missing
//   required key ...）不指向真正的调用点。main.js 有 1500+ 行且零测试覆盖，
//   靠人眼核对 34 个命令不现实。
//
//   这里做**静态双向核对**：JS 侧命令集 == Rust 侧 `#[tauri::command]` 命令集，
//   且每个参数名能对上。只读源码、不跑构建、不依赖 @tauri-apps/api 能否解析
//   —— 与 e2e/helpers/__tests__/ahk_path.test.js 同一思路。
//
//   这套检查第一次跑就抓到真问题：`export_recording` 的 Rust 签名要求
//   `delays: Vec<u64>`，而 api.js 没传 —— 调用必失败（详见下面的用例注释）。
//
// 运行：node --test src/__tests__/*.test.js
// =================================================================
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ASD_TAURI = join(__dirname, '..', '..'); // asd-tauri/
const API_JS = join(ASD_TAURI, 'src', 'api.js');
const RUST_SRC = join(ASD_TAURI, 'src-tauri', 'src');

/** camelCase -> snake_case（Tauri 默认按 snake_case 匹配命令参数） */
function toSnake(name) {
  return name.replace(/[A-Z]/g, (c) => '_' + c.toLowerCase());
}

/** 递归收集目录下所有 .rs 文件 */
function collectRs(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...collectRs(full));
    else if (entry.endsWith('.rs')) out.push(full);
  }
  return out;
}

/**
 * 按顶层分隔符切分，**尊重 `<>`/`()`/`[]`/`{}` 嵌套**。
 * 不能直接 `split(',')`：`state: tauri::State<'_, Arc<AppState>>` 里的逗号在泛型内，
 * 直接切会把参数名解析成 `Arc<AppState>` 这种鬼东西（第一版就踩了这个，
 * 于是 34 个命令全部被误报「漏传参数」）。
 */
function splitTopLevel(s, sep = ',') {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of s) {
    if (ch === '<' || ch === '(' || ch === '[' || ch === '{') depth++;
    else if (ch === '>' || ch === ')' || ch === ']' || ch === '}') depth--;
    if (ch === sep && depth === 0) {
      out.push(cur);
      cur = '';
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out;
}

/** 解析 JS 对象字面量里的键名：`{ groupId, active: x }` -> ['groupId', 'active'] */
function payloadKeys(body) {
  if (!body) return [];
  return body
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => (s.includes(':') ? s.slice(0, s.indexOf(':')) : s).trim());
}

/** 从 api.js 抽出所有 invoke 调用：{ cmd, keys } */
function jsInvocations() {
  const src = readFileSync(API_JS, 'utf8');
  const calls = [];
  const re = /invoke\(\s*'([a-z0-9_]+)'\s*(?:,\s*\{([^}]*)\})?\s*\)/g;
  let m;
  while ((m = re.exec(src))) {
    calls.push({ cmd: m[1], keys: payloadKeys(m[2]) });
  }
  return calls;
}

/** Tauri 注入的参数（不由前端传），按类型识别 */
const INJECTED = /State<|AppHandle|Window|Webview|Manager|App\b/;

/** 从 Rust 源码抽出所有 #[tauri::command]：{ name, params:[{name,type}] } */
function rustCommands() {
  const cmds = [];
  for (const file of collectRs(RUST_SRC)) {
    const src = readFileSync(file, 'utf8');
    // ⚠️ 必须**整行锚定**：属性独占一行，而文档注释里的 `/// ... #[tauri::command] ...`
    // 是散文。用裸的 /#\[tauri::command\]/g 会把注释里提到它的地方也当成属性，
    // 然后取「后面第一个 fn」—— 于是 `*_impl`、测试函数都被当成命令
    // （2026-09-17 实测：一次新增注释就抽出 6 个幻影命令，G3c 变红）。
    const attr = /^[ \t]*#\[tauri::command\][ \t]*$/gm;
    let m;
    while ((m = attr.exec(src))) {
      const rest = src.slice(m.index);
      const fn = /fn\s+([a-z0-9_]+)\s*\(/.exec(rest);
      if (!fn) continue;
      const start = rest.indexOf('(', fn.index);
      let depth = 0;
      let i = start;
      for (; i < rest.length; i++) {
        if (rest[i] === '(') depth++;
        else if (rest[i] === ')') {
          depth--;
          if (depth === 0) break;
        }
      }
      const params = splitTopLevel(rest.slice(start + 1, i))
        .map((p) => p.trim())
        .filter(Boolean)
        .map((p) => {
          const colon = p.indexOf(':');
          return {
            name: p.slice(0, colon).trim(),
            type: p.slice(colon + 1).trim(),
          };
        })
        .filter((p) => p.name && !INJECTED.test(p.type));
      cmds.push({ name: fn[1], params, file });
    }
  }
  return cmds;
}

const js = jsInvocations();
const rust = rustCommands();
const jsByName = new Map(js.map((c) => [c.cmd, c]));
const rustByName = new Map(rust.map((c) => [c.name, c]));

describe('api.js 与 Rust 命令的契约', () => {
  test('抽取得出内容（防止解析器静默失效）', () => {
    // 解析器一旦写错（比如正则不匹配了），下面所有断言都会「空集对空集」通过。
    // 这条是那套断言的阳性对照锚点。
    assert.ok(js.length >= 30, `api.js 应抽出 >=30 个 invoke，实际 ${js.length}`);
    assert.ok(rust.length >= 30, `Rust 应抽出 >=30 个命令，实际 ${rust.length}`);
  });

  test('JS 调用的命令在 Rust 侧都存在', () => {
    const missing = js.filter((c) => !rustByName.has(c.cmd)).map((c) => c.cmd);
    assert.deepEqual(
      missing,
      [],
      `api.js 调用了 Rust 侧不存在的命令（Tauri 会报 "command not found"）：${missing.join(', ')}`
    );
  });

  test('Rust 注册的命令都被前端用到（或明确豁免）', () => {
    // 允许存在「Rust 有但前端暂未接入」的命令，但必须显式登记，避免悄悄堆积。
    const allowUnused = new Set([]);
    const unused = rust
      .filter((c) => !jsByName.has(c.name) && !allowUnused.has(c.name))
      .map((c) => c.name);
    assert.deepEqual(
      unused,
      [],
      `以下 Rust 命令没有任何前端调用方；若确实暂不接入，请加进 allowUnused 并写明原因：${unused.join(', ')}`
    );
  });

  test('抽出的命令都在 lib.rs 的 generate_handler 里注册过（防幻影命令）', () => {
    // 2026-09-17 实测踩到：解析器用裸的 /#\[tauri::command\]/g 搜索，把文档注释里
    // 提到这个字面量的散文也当成属性，再取「后面第一个 fn」，于是抽出
    // `get_config_impl`、`extract_command_params` 这类幻影命令 —— 它们不在注册块里，
    // 却被当成命令去和前端比对，直接红掉 G3c。
    // 光把正则改对不够：这条断言把「抽出的必须是真注册过的」钉死，
    // 以后谁再让解析器产生幻影，这里会立刻报名字。
    const lib = readFileSync(join(ASD_TAURI, 'src-tauri', 'src', 'lib.rs'), 'utf8');
    const start = lib.indexOf('generate_handler![');
    assert.ok(start >= 0, 'src/lib.rs 里没找到 generate_handler![ —— 解析器前提失效');
    const block = lib.slice(start, lib.indexOf(']', start));
    const registered = new Set(
      block
        .split(',')
        .map((s) => s.trim().split('::').pop().trim())
        .filter(Boolean)
    );
    assert.ok(registered.size >= 30, `注册块应解析出 >=30 个命令，实际 ${registered.size}`);

    const phantom = rust.filter((c) => !registered.has(c.name)).map((c) => c.name);
    assert.deepEqual(
      phantom,
      [],
      `抽出了未注册的命令（解析器把注释/非命令函数当成了命令）：${phantom.join(', ')}`
    );
  });

  test('JS 传的每个参数名都能对上 Rust 的 snake_case 参数', () => {
    const problems = [];
    for (const call of js) {
      const rc = rustByName.get(call.cmd);
      if (!rc) continue; // 由上面的用例负责报
      const paramNames = new Set(rc.params.map((p) => p.name));
      for (const key of call.keys) {
        if (!paramNames.has(toSnake(key))) {
          problems.push(
            `${call.cmd}: 前端传了 '${key}'（-> ${toSnake(key)}），` +
              `但 Rust 参数是 [${[...paramNames].join(', ') || '无'}]`
          );
        }
      }
    }
    assert.deepEqual(problems, [], problems.join('\n'));
  });

  test('Rust 的必填参数都被前端传了（漏传会被 Tauri 拒收）', () => {
    // 这条是抓 export_recording 漏传 delays 的那一条。
    const problems = [];
    for (const call of js) {
      const rc = rustByName.get(call.cmd);
      if (!rc) continue;
      const sent = new Set(call.keys.map(toSnake));
      for (const p of rc.params) {
        if (!sent.has(p.name)) {
          problems.push(
            `${call.cmd}: Rust 要求参数 '${p.name}: ${p.type}'，但前端只传了 [${call.keys.join(', ') || '无'}]`
          );
        }
      }
    }
    assert.deepEqual(problems, [], problems.join('\n'));
  });
});

describe('api.js 自身的封装约定', () => {
  test('getGroupListForValidation 复用 getGroups（不重复定义命令）', () => {
    const src = readFileSync(API_JS, 'utf8');
    const fn = /export async function getGroupListForValidation\(\)\s*\{([^}]*)\}/.exec(src);
    assert.ok(fn, '应能找到 getGroupListForValidation');
    assert.match(fn[1], /return getGroups\(\)/, '它应转调 getGroups()，而不是自己再 invoke 一次');
  });

  test('事件订阅都走 listen 且只转发 payload', () => {
    const src = readFileSync(API_JS, 'utf8');
    const subs = [...src.matchAll(/export function (on\w+)\(callback\)\s*\{([^}]*)\}/g)];
    assert.ok(subs.length >= 5, `应有 >=5 个事件订阅，实际 ${subs.length}`);
    for (const [, name, body] of subs) {
      assert.match(body, /listen\('/, `${name} 应使用 listen(`);
      assert.match(body, /callback\(event\.payload\)/, `${name} 应只把 payload 交给回调`);
    }
  });
});
