# `tauri.e2e.conf.json` —— 方案 1 的载体，**已实测证伪，默认不启用**

> 本文件说明**为什么这个配置还在、为什么不生效、以及将来该怎么重试**。
> 旁边那份 `tauri.e2e.conf.json` 是纯 JSON，**无法写注释**（JSON 不支持注释；且
> `tauri-utils` 的配置结构体多处带 `deny_unknown_fields`（`tauri-utils-2.9.2/src/config.rs`
> 的 320 / 337 / 389 / 405 / 436 / 512 / 523 / 534 / 548 / 612 行），塞 `$comment`
> 这类键有解析失败的风险），故说明单独放这里。

## 它想解决什么

Windows 上 msedgedriver 要挂上 WebView2，需要 WebView2 的浏览器进程开着远程调试端口，
并写出 `DevToolsActivePort` 文件。本配置试图通过 `app.windows[0].additionalBrowserArgs`
把 `--remote-debugging-port=9333` 直接塞进 WebView2 的 `AdditionalBrowserArguments`
（经 `tauri-runtime-wry-2.11.2/src/lib.rs:5054-5055` → `wry::with_additional_browser_args`）。

端口用固定 9333 而不是 0：`=0` 时 WebView2 自选端口但**不写** `DevToolsActivePort`，
EdgeDriver 无从得知端口。固定端口也不能靠 `ms:edgeOptions.debuggerAddress` 注入 ——
tauri-driver 用 `always_match.extend(native)` **整体替换** `ms:edgeOptions`
（`crates/tauri-driver/src/server.rs:150-152`），注入必被覆盖。

`--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection` 是 wry 的默认值，
`tauri-utils-2.x/src/config.rs:2080-2083` 注释明写「设了会被替换，需自行补回」，故必须显式带上。

## 结果：无效（run 35354358075）

```
[UDF 探测 A] 目录存在但无 DevToolsActivePort（共 1 项）: C:\Users\runneradmin\AppData\Local\com.asd.tauri
[UDF 探测 A] 目录条目: EBWebView
[UDF 探测 B] 目录不存在
[0-0] ERROR webdriver: WebDriverError: session not created: DevToolsActivePort file doesn't exist
```

真实 UDF（`%LOCALAPPDATA%\com.asd.tauri`，有 `EBWebView` 说明 WebView2 确实在用它）
里**仍然没有** `DevToolsActivePort` ⇒ 端口没开。

## 为什么这是决定性的

在此之前，`webviewOptions.additionalBrowserArguments`（run 35350670139）已失败，
结果**完全同型**。两条路径机制上互相独立：

| 通道 | 链路 | 结果 |
|---|---|---|
| `webviewOptions` | msedgedriver →（未知通道）→ WebView2 | 失败（35350670139） |
| `additionalBrowserArgs`（本文件） | conf → tauri-runtime-wry → wry 显式 API → WebView2 | 失败（35354358075） |

第二条是**必达**的（直接调 wry 的 API，不经过任何转发），它也失败 ⇒ 候选已穷尽。
错误串与上游 `tauri-apps/webdriver-example` 的 windows-latest 作业**逐字一致**
（`session not created: DevToolsActivePort file doesn't exist`），而上游同一次 run 的
ubuntu-latest 是通过的 ⇒ 这是栈在 Windows 上不成立，不是本仓配置问题。详见 **TD-061**。

## 当前状态

- **默认不启用**：`ci.yml` 的 `e2e_build_config` 输入默认为空，E2E 构建走正式 `tauri.conf.json`。
- **保留本文件**是为了将来重试时不必重新推导（端口为什么固定、`--disable-features` 为什么
  必须补回、合并语义是什么，都在上面）。
- ⚠️ **安全红线**：`--remote-debugging-port` 只许出现在 E2E 专用配置里。正式
  `tauri.conf.json` 出现即 **C12** 硬失败（`scripts/check-tech-debt.py`）。

## 将来重试的前提

不是再换第三个配置字段 —— 而是等下列任一条件成立：

1. 上游 tauri-driver / msedgedriver 在 Windows 上的 DevToolsActivePort 问题被修复
   （关注 `tauri-apps/tauri` #15415 与 PR #15605）；
2. 改用不依赖 msedgedriver 的方案（如 WebdriverIO 的 embedded provider
   `tauri-plugin-wdio-webdriver`，它绕过 tauri-driver；但需改应用代码并 feature gate，
   绝不能让正式产物内嵌 WebDriver server）。

重试前请先看 `docs/tech-debt-register.md` 的 TD-061 / TD-062。
