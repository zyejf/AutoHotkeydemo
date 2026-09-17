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

      // ── 曾经的三条降级覆盖已撤销（TD-022，2026-09-17）──
      // 之前把 no-redeclare / no-empty / no-prototype-builtins 从 recommended 的
      // error 降成 warn，是为了让存量 52 处（42 重复声明 + 6 空块 + 4 原型方法调用）
      // 不阻断。那些已全部清掉，因此撤掉覆盖 —— 三条回到 **error** 级，
      // 比原来的 warn 更严；`npm run lint` 的水位也从 70 收到 **0**。
      // 如果将来又出现这类问题，请先修代码，不要重新加回降级。
    },
  },
];
