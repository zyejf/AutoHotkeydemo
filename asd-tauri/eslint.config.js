// ESLint 9 flat config（TD-012）
//
// 为什么只 lint `src/`：前端目前只有 api.js / main.js 两个源文件（约 1500 行），
// 而 JS 单测只覆盖 e2e/helpers —— **main.js 是零测试覆盖的**。
// 对没有测试兜底的代码，静态分析是唯一一道自动检查，值得为它单独配一套。
//
// 为什么不上 typescript-eslint / prettier：这里没有构建期的类型信息可用，
// 强上类型检查会逼出一轮「给 1500 行补 JSDoc」的机械改动，收益不在当下。
// 只开 recommended：它抓的是 no-undef / no-unreachable / no-constant-condition
// 这类「写了就一定错」的问题，误报率最低。
import js from "@eslint/js";
import globals from "globals";

export default [
  { ignores: ["dist/**", "target/**", "node_modules/**", "coverage/**"] },
  {
    files: ["src/**/*.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.browser,
        // Tauri v2 注入的全局（仅声明存在，实际调用走 @tauri-apps/api 的 import）
        __TAURI_INTERNALS__: "readonly",
        __TAURI__: "readonly",
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      // 事件回调里 `(_e) => {}` 之类的占位参数是常见写法，不要报错
      "no-unused-vars": ["warn", { argsIgnorePattern: "^_", caughtErrors: "none" }],

      // ── 以下 4 条在存量代码里共 70 处，全部是**风格债不是缺陷** ──
      //   · no-redeclare 42：var 时代在同一函数里重复声明 i/k/v
      //   · no-unused-vars 18：未使用的 promise 回调参数与几个赋值后未读的变量
      //   · no-empty 6：localStorage 写入的 `catch(ex) {}`
      //   · no-prototype-builtins 4：`obj.hasOwnProperty(k)`
      // main.js 目前**零测试覆盖**，在这种代码上批量改名/删变量的收益远小于风险，
      // 所以走棘轮：存量 70 只登记不报错（登记 TD-022），`npm run lint` 用
      // --max-warnings 把水位钉住，改好一处就把数字减一，新增一处立刻红。
      "no-redeclare": "warn",
      "no-empty": "warn",
      "no-prototype-builtins": "warn",
    },
  },
];
