# 技术债持续迭代报告：门禁漂移收口 + E2E 首次开火后挖出 P0 打包缺陷

**日期**：2026-09-18
**工作流**：工作流 5（技术债评估）+ 工作流 4（发布前检查）混合
**参与成员**：Cody（代码审查师）· Archi（系统架构师）· Rex（SRE）· 主理人甄宇航（独立复核）
**范围**（用户选定）：E2E 验真 + 门禁修复 TD-055 / TD-051

---

## 📌 TL;DR

- 🔴 **本轮挖出一个 P0 生产缺陷，与 E2E 无关却由 E2E 首次暴露**：`tauri.conf.json` 的 `bundle.resources` 漏了 `high_res_clock.ahk`，而 `sender.ahk:16` 与 `joystick.ahk:18` 都要 `#Include` 它 —— **任何干净的打包构建（含分发给用户的 release 安装包）里，AHK 执行器启动即崩**。已修（`e50f8c2`）+ 加 C11 守卫 + 登记 **TD-060**。
- 🔻 **E2E：三条路径全部实测失败，已止损**（§2.6–§2.12）。真实错误串是 `session not created: DevToolsActivePort file doesn't exist`，与 Tauri 官方示例 `tauri-apps/webdriver-example` 的 Windows 失败**逐字一致**（该示例 ubuntu success / windows failure、**连续 8 次**、上游自己无 tauri-driver CI）。两条**机制独立**的通道（① `webviewOptions.additionalBrowserArguments` ② `tauri.conf.json additionalBrowserArgs`）都已实测无法让 WebView2 写出 `DevToolsActivePort` ⇒ **不是参数没送到，是送到了也不写**。
- ✅ **门禁侧全绿并在 CI 验真**：TD-051（JS 边四分法，自检 30 用例通过）、TD-055（三处档位漂移）、**C10**（档位一致）、**C11**（打包资源同步）、**C12**（正式配置不得开调试端口）。E2E 虽不可用，但它**抓到了那个 P0**，且本轮新增的进程采样器 / `E2E_TIMEOUT_MS` / 双候选 UDF 探测**全部有效并保留**。
- **同一个 bug 形状被撞见三次**：`.sh` 与 `ci.yml` 都对，只有开发者实际会用的 `.ps1` 是错的。已修 G3d / G3c / G2b·G3a 三处，并新增 **C10** 让它们不可能再次漂移。
- 严重度分布：**🔴严重 1 项（已修，P0 打包缺陷）/ 🟠高 1 项（E2E 栈不成立，已止损并登记）/ 🟡中 3 项 / 🟢低 2 项**。
- ⚠️ **本轮我自己犯的错比修的问题多**：编过不存在的 run 号、把「变量单一」凌驾于「拿得到结论」（导致连续 6 轮错误串被自己的 60s 超时吃掉）、只读一层源码就下推导（错 2 次）、没看全探测输出就宣布结论（错 1 次）、收尾清单有 2 条方向性错误 —— **全部由 Rex 在执行前拦下**。详见 §"待完善"。

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| 整体评级 | 🟢 通过（门禁与技术债侧全绿；E2E 已**有据止损**、不构成阻塞） |
| 阻塞项数量 | **0** |
| 关键行动项 | **5 条** |
| E2E 状态 | 🔻 **不可用（已止损）**：与上游同型故障，两条独立通道实测失败，候选已穷尽 |
| 建议下一步 | ① 完成止损收尾（摘掉默认 `--config` + 登记 TD-061/062）→ ② 人工真终端跑一次 `.ps1` 全量 → ③ 台账自洽收尾（仍未做的 P0 欠账） |

---

## 一、🔴 P0：打包资源漏文件，执行器启动即崩（已修）

### 1.1 证据

run `35333326568`（job `105562440162`）日志 10:24:38，来自本轮新增的 `dumpDriverLog` 无条件落盘：

```
\\?\D:\a\...\asd-tauri\target\debug\ahk_executor\sender.ahk (16) : ==> #Include file "high_res_clock.ahk" cannot be opened.
   （重复多行）
Error serving connection: Os { code: 10054, kind: ConnectionReset, message: "An existing connection was forcibly closed by the remote host." }
```

### 1.2 成因

`asd-tauri/src-tauri/tauri.conf.json` 的 `bundle.resources` 只列了 7 项，而 `ahk_executor/` 目录下实际有 **6 个 `.ahk`**，多出的 `high_res_clock.ahk` **不在列表里**。偏偏两个生产文件都要 `#Include` 它：

| 引用方 | 行 |
|---|---|
| `sender.ahk` | `:16` |
| `joystick.ahk` | `:18` |

### 1.3 影响面与藏法

- **不只是 CI 问题**：`bundle.resources` 是 `tauri build` 打安装包用的，**分发给用户的 release 版本里 AHK 执行器同样会崩**。E2E 只是第一个撞上它的地方。
- **为什么长期没暴露**：开发机上有本地编译的 `asd_executor.exe`（Ahk2Exe 把 `#Include` 全部打进 exe），而 `resolve_ahk_executor_path`（`src-tauri/src/lib.rs:608`）**优先**用它，于是「便携模式 `AutoHotkey64.exe + executor.ahk`」这条路径在本机从不执行。**与 TD-046 同家族：有一条路径在本机永远走不到。**
- 推测引入时点：`high_res_clock.ahk` 是较晚新增的文件，加入时未同步 `bundle.resources`。

### 1.4 处置（已完成，`e50f8c2`）

1. `bundle.resources` 补 `ahk_executor/high_res_clock.ahk`（现 8 项，6 个 `.ahk` 全覆盖）
2. 新增 **C11** 打包资源清单同步（硬失败、不做棘轮），随 G3e 在三处门禁 + CI 跑
3. 登记 **TD-060**（`3c8496e`）

**C11 的三个刻意收窄**（Cody 设计，我复核认可）：
- 只管**同目录**：跨目录（如 `../domain/x.ahk`）各有自己的打包口径，混进来只会制造无法归因的噪声
- **引用了目录里根本不存在的 `.ahk` 也报**：否则 `resolve_include` 返回 `None` 就静默跳过 —— 那是**假绿**，比不校验更危险
- 目录里有但**从未被引用**只提示、不判失败：`executor.ahk` 是入口脚本（由 `asd_executor.bat` / Rust 直接拉起，本就不该有入边），机器判了就是误报

阳性对照三组全部成立：去掉 `high_res_clock.ahk` → FAIL 并点名两个引用位置；注入不存在的 `zz_probe.ahk` → FAIL 并注明文件不存在；还原 → PASS 且零残留。

> 💡 **这条是本轮最有价值的产出，而它完全来自「让通道先能自证」**。如果本轮只是继续修 E2E 断言、或者干脆把 E2E 当死门删掉，这个 P0 会一直躺在分发版本里。**「假阳性 > 静默失效 > 通道腐烂」的代价排序再次得到验证。**

---

## 二、E2E：通道第一次真正开火

### 2.1 执行序列（修正后）

| 次序 | run id | commit | 结论 | 关键事实 |
|---|---|---|---|---|
| 1 | `35309066359` | — | failure | 零用例执行（死因④：e2e 未装依赖、`npx wdio` 静默降级废弃 `wdio@6.0.1`） |
| 2 | `35310528367` | `e53d136` | failure | 9 spec 全挂、`ECONNREFUSED`（死因⑤） |
| 3 | **`35312497783`** | `ce78fb1` | failure | **42 分钟**——上轮报告中从未被记录，本轮捞出 |
| 4 | `35327797606` | `ce78fb1` | failure | `Spec Files: 0 passed, 9 failed, 9 total in 00:36:32` |
| 5 | `35333326568` | `cce526f` | failure | 14m23s；探测数据到手 → **真因定位** |
| 6 | `35335990999` | `e50f8c2` | failure | `0 passed, 9 failed, 9 total in 00:09:18`；**AHK 报错归零、`/session` 仍超时** → 存在独立第七道死因 |

### 2.2 前五道死因修复确认生效

诊断日志原文：`[OK] msedgedriver.exe 存在: ...\asd-tauri\e2e\drivers\msedgedriver.exe`；失败形态由 `ECONNREFUSED`（连不上）变为「连得上但无响应」——**tauri-driver 已成功绑定 4444**，9 个 spec 全部派发（`RUNNING in wry` ×9）。

### 2.3 第五次执行的探测结果（假设①被证伪）

```
[INFO] msedgedriver --version: Microsoft Edge WebDriver 152.0.4191.88
[INFO] WebView2 Runtime (HKLM WOW6432Node): ... | pv REG_SZ 152.0.4191.66
[INFO] WebView2 Runtime (HKCU): ERROR: The system was unable to find the specified registry key or value.
```

- **WebView2 Runtime 确实装着**（机器级安装，在 HKLM；HKCU 找不到属正常）
- ⚠️ 我先前核实到「`ci.yml` 全文只在第 31 行描述文字里提到 WebView2、无安装步骤」，但那**不等于**运行时缺失——`windows-latest` 镜像预装了。假设①**已证伪**，这正是加那行探测的意义。
- msedgedriver `152.0.4191.88` vs WebView2 `152.0.4191.66`：主版本一致（152），**不构成版本不匹配**。

### 2.4 `connectionRetryCount` 3→0 生效

每个 spec 由 4 分钟降为 **60 秒**（`10:15:27 RUNNING` → `10:16:27 FAILED`），整轮 42m26s → **14m23s**。依据是我要求 Rex 给出的实断，且我已独立复核：全文件仅一处 `waitForPort('127.0.0.1', 4444, 30000)`，`process.env.CI` 只出现在注释里。

### 2.5 第六次执行：P0 修复生效，但它不是 `/session` 超时的主因

`Spec Files:	 0 passed, 9 failed, 9 total (100% completed) in 00:09:18`

| 判据 | 结果 | 含义 |
|---|---|---|
| `grep -c "cannot be opened"` | **0** | ✅ **P0 修复生效**：AHK `#Include` 报错**完全消失** |
| wdio 汇总行 | 0 passed / 9 failed | ❌ `POST /session` **仍然超时**，零用例执行 |
| driver 输出 | 仅 `hyper::Error(IncompleteMessage)` + `ConnectionReset` | 不再有 AHK 层面的错误 |
| 探测 | msedgedriver `152.0.4191.88` / WebView2 `152.0.4191.66` | 与第五次一致，环境未变 |

⚠️ **必须如实定性：P0 打包缺陷是真的、也已确实修好（报错归零），但它不是 `/session` 超时的主因。**

两者在第五次日志里**同时出现，是相关不是因果**——执行器崩溃很可能与应用启动失败同源于更早的某个环节，或者干脆是两个独立问题。这是本轮一个值得记的判断教训：

> **「改完之后还是红」不等于「没修对」**；同理，**「修好了日志里最显眼的那条错误」也不等于「修好了这个故障」**。
> 若没有 `dumpDriverLog` 做前后对照（`cannot be opened` 由多行 → **0**），我们无法区分这两种情况，只能靠猜。

**当前准确表述**：前五道死因修复确认生效；AHK 打包缺陷（P0）已修复且经复跑证实报错归零；`POST /session` 超时存在**独立的第七道死因，根因未定**。E2E 仍为不可用状态。

⚠️ **禁用表述**：「E2E 已修复」「通道已通」「P0 是 E2E 失败的根因」—— 后一条尤其要避免，它已被第六次执行**直接证伪**。

### 2.6 第七次执行：采样器给出判别性证据，根因下沉到机制层

单 spec 诊断轮 run `35338969816`（`-f e2e_spec=specs/smoke.spec.js`，全程 6m49s）。新增的**进程存活采样器**第一次把「猜」变成了「测」：

```
[sampler 汇总] 时刻为相对 tauri-driver spawn 的秒数
[sampler 汇总] asd-tauri.exe:     曾出现，首次 +2.5s，最后 +59.7s
[sampler 汇总] msedgedriver.exe:  曾出现，首次 +0.1s，最后 +59.7s
[sampler 汇总] 5173 (Vite):       曾出现，首次 +0.1s，最后 +59.7s
[sampler 汇总] tauri-driver PID:  曾出现，首次 +0.2s，最后 +59.8s
```

按**事先钉死**的判别口径（避免事后挑口径）：

| 假设 | 判据 | 结论 |
|---|---|---|
| tauri-driver 没走到拉起应用 | 应用**从未出现** | ❌ 证伪（+2.5s 出现） |
| 应用亚秒级闪退 | 出现后很快消失 | ❌ 证伪（存活至 +59.7s，跨越整个 60s 窗口） |
| **应用起来了但 WebView 不就绪** | 出现并常驻 | ✅ **与实测一致** |

⚠️ 残留口径（Rex 提出、我采纳）：若应用在**亚秒级**内闪退，仍可能落在两个采样点之间而显示「从未出现」。本次实测「曾出现且常驻」，**不受该残留影响**。

#### 源码级三事实（读 `tauri-driver 2.0.6` crate 源码，非推断）

1. **tauri-driver 不拉起应用，它只是 HTTP 透明代理**。`src/server.rs:79-105` 把 `POST /session` 的 body 改掉后转给 msedgedriver；Windows 上的映射在 `server.rs:51-69`：
   `ms:edgeChromium=true` / `browserName="webview2"` / `ms:edgeOptions.binary=<应用 exe>` / 可选 `ms:edgeOptions.webviewOptions`。
   ⇒ **真正拉起应用、并卡住 60 秒的是 msedgedriver**（它把应用当"浏览器"启动）。
2. **`TAURI_WEBVIEW_AUTOMATION` 在 Windows 上是死开关**。tauri-driver 给 msedgedriver 注入该变量（`webdriver.rs:50-51`），`tauri-runtime-wry-2.11.2/src/lib.rs:4791` 读它并调 `web_context.set_allows_automation(...)；但 **wry 0.55.1 的这个方法只有 Linux/WebKitGTK 有真实现**（`src/webkitgtk/web_context.rs:86-89`），通用默认实现 `src/web_context.rs:112` 是空函数 `fn set_allows_automation(&mut self, _flag: bool) {}`。
3. **Tauri 的 WebView2 `additional_browser_args` 只能由应用代码显式设置**（`tauri-2.11.2/src/webview/webview_window.rs:1015`），**不**从命令行参数或环境变量自动取；`tauri-runtime-wry-2.11.2/src/lib.rs:5054-5055` 才把它传给 wry。

**「60 秒静默」的直接原因也找到了**：`webdriver.rs:58` 把 msedgedriver 的 **stdout 直接丢弃**（`cmd.stdout(Stdio::null())`），只继承 stderr。Edge WebDriver 的日志主要走 stdout ⇒ **日志通道本来就是断的**。这是本轮第四次栽在「静默」上（driverLog 静默、diag 不进 stdout、tauri-driver 零输出、msedgedriver stdout 被弃）。

#### 已排除（累计）

| # | 曾怀疑 | 排除依据 |
|---|---|---|
| 1 | WebView2 Runtime 缺失 | 探测：HKLM `pv 152.0.4191.66` |
| 2 | AHK 打包缺文件（P0） | 已修、报错归零，但 `/session` 仍超时 → **非主因** |
| 3 | msedgedriver / WebView2 版本不匹配 | 主版本同为 152 |
| 4 | 二进制名错误 | `Cargo.toml` name = `asd-tauri`，`target/debug/asd-tauri.exe` 存在 |
| 5 | 应用没被拉起 / 闪退 | 采样器：+2.5s 出现、+59.7s 仍存活 |
| 6 | devUrl / Vite 未起 | CI 用 `npm run tauri build -- --debug`（custom-protocol 内嵌 dist）；且 5173 全程在监听 |

**当前收口**：应用活着，但 WebView2 未向 msedgedriver 暴露可用的自动化端点。已派 Cody（代码侧：启动路径是否阻塞建窗 / capabilities 是否漏 `webviewOptions` / 应用侧开调试端口的最小改动与安全代价）与 Rex（外部权威：WebView2 自动化的必要条件、tauri-driver on Windows 是否已知不成立、**该继续修还是该止损**）并行核实，结论将补入本报告（见文末「数据来源」的成员产出索引）。

### 2.7 门禁修复在 CI 上验真（TD-051 / TD-055 收口）

run `35338969816` 的「四闸门 (windows-latest)」= **success**；本轮新增/修复的守卫**全部真的跑到了**（不是"写了没跑"）：

| 闸门 | CI 实测输出 |
|---|---|
| **G3i** | `== JS 边归类自检（30 用例）==` → `全部通过（含 9 条仅类型 / 8 条重导出 / 阴性对照 8 条）` |
| **C10** | `核对 6 处 … 通过：三处档位一致`；三处 G3d 均识别为 `FULL(含运行时对账)`（`.sh:203` / `.ps1:231` / `ci.yml:242`） |
| **C11** | `核对 5 个被引用文件，resources 共 8 项 … 通过：被引用的同目录 .ahk 全部已打包` |
| **C9** | `核对 60 行 … 通过：DPI 与档位全部符合公式与阈值` |

至此 **TD-051、TD-055 验真完成**。

### 2.8 机制层定级：是「栈在 Windows 上不成立」，不是「我们配错了」

这是本轮**最重要的一条结论**，它改变了问题的性质。

#### 外部权威证据（Rex）

| 证据 | 内容 |
|---|---|
| **官方示例自身在 Windows 上就是红的** | `tauri-apps/webdriver-example`（tauri 2.9.2 + wdio 9.21.0 + tauri-driver 0.1.6，与我们的栈同型）最近一次 run **`34766587019`（2026-09-13）：`ubuntu-latest × webdriverio` = **success**，`windows-latest × webdriverio` = **failure****，报错 `DevToolsActivePort file doesn't exist` |
| 不是 flaky | 该 job **连续 8 次** Windows 失败 |
| 上游自己没有这条 CI | tauri 官方仓库**不含 tauri-driver 的 CI 验证**（"unknown host" 说明未启用），即 Windows 路径**从未被上游保障过** |
| 已知未修缺陷 | tauri issue **#15415**：wdio 9 默认走 BiDi，`webSocketUrl` 未被 tauri-driver 2.0.6 剥离；官方 workaround 是 `wdio:enforceWebDriverClassic=true`。对应 PR **#15605 仍 open** |
| **根因机制** | Microsoft 文档明确：`ms:edgeOptions.args` 是传给**宿主 exe** 的，**不会**透传进 WebView2 浏览器进程；附加参数必须走 **`webviewOptions.additionalBrowserArguments`**。官方示例的 capabilities **恰恰没有**这一项 |

#### 代码侧交叉验证（Cody）

- **启动路径已排除**：主窗口在 `app.rs:2516-2518` 创建，setup 在 `:2522` 之后 —— 窗口**先于** setup 存在，不存在"卡在建窗前"。
- **`ms:edgeOptions.args` 确实到不了 WebView2**：`wry-0.55.1/src/webview2/mod.rs:294-327` 只从 `AdditionalBrowserArguments`（WebView2 creation option）取参，不从宿主命令行取。⇒ **补 `args` 是假修**。
- **`additional_browser_args` 本来就是 `tauri.conf.json` 的窗口字段**（`tauri-utils-2.9.2/src/config.rs:2083`），不需要改 Rust。

#### 定级与决策

> 我们观察到的 `POST /session` 永久挂起，与上游官方示例的 Windows 失败**同型**（都缺 WebView2 的 CDP 端点；上游表现为 `DevToolsActivePort file doesn't exist`，我们表现为 60s 超时 —— 只因我们设了 `connectionRetryTimeout=60000`）。

**这不是"我们哪里配错了"，而是栈在 Windows 上缺乏保障。** 因此本轮**不做无边界的试错**，按 Rex 建议给 **1 次 bounded 尝试**：只改 `asd-tauri/e2e/wdio.conf.js`（E2E 配置，**不动任何生产代码**），加 `wdio:enforceWebDriverClassic=true` + `tauri:options.webviewOptions{ additionalBrowserArguments: '--remote-debugging-port=0', userDataFolder: <每次新建> }`，跑一次定生死。

**失败即止损**（Rex 建议、我采纳）：把 E2E job 降级为 `continue-on-error: true` + 手动触发，并**按债项登记本栈在 Windows 上不成立**及全部证据，而不是继续烧 CI 分钟。备选方案（test-only `tauri.e2e.conf.json` 走 `additionalBrowserArgs` / `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` 环境变量）由 Cody 前置设计，作为第二次尝试的候选。

### 2.9 bounded 尝试 #1 实测：无变化，且失败信息量为零

提交 `199f20f`（只改 `asd-tauri/e2e/wdio.conf.js`）：加 `wdio:enforceWebDriverClassic=true` + `tauri:options.webviewOptions{ additionalBrowserArguments: ['--remote-debugging-port=0'], userDataFolder: <mkdtempSync 每次新建> }`。

run **`35343866509`** 结果 **failure**，形态与之前**完全一致**：

```
[0-0] ERROR webdriver: WebDriverError: Request timed out! ...
      when running "http://127.0.0.1:4444/session" with method "POST"
Spec Files:  0 passed, 1 failed, 1 total (100% completed) in 00:01:01
[sampler 汇总] asd-tauri.exe: 曾出现，首次 +2.4s，最后 +59.8s
```

全日志 `grep -c "DevToolsActivePort|webSocketUrl|session not created"` = **0**。

#### ⚠️ 关键自省：判别信息被我自己的超时设着吃掉了

我为了「变量单一」锁死 `connectionRetryTimeout=60000`，却忽略了**上游要到 4m04s 才吐出 `DevToolsActivePort` 错误串** —— 我们 60 秒就超时，**真正的错误根本没有机会出现**。

结果：这次尝试**既不能证明修复生效，也不能证明它没生效**：

> 无法区分「`webviewOptions` 没生效」与「生效了但后面还有阻塞」。

> **教训（已入项目记忆）：排查「永久挂起」时先自问 —— 是不是我自己的超时把真正的错误串盖住了？** 报错被超时吃掉，会让你看到一个错误的故障面。

#### bounded 尝试 #2：不改修复方案，只把错误串换出来

目的**不是继续试错，而是为止损拿证据**：把 `connectionRetryTimeout` 改成带默认值的开关 `Number(process.env.E2E_TIMEOUT_MS ?? 60000)`（默认仍 60s，不拖慢常规运行），CI 侧加 `e2e_timeout_ms` 入参；诊断时传 `300000` 跑一次，拿到真实错误串。

- 拿到 `DevToolsActivePort file doesn't exist` ⇒ 与上游**同型坐实** ⇒ 止损
- 拿到别的错误串 ⇒ 通道可能有戏，再议

`webviewOptions` / `enforceWebDriverClassic` **不回退**（零生产风险、尚未证伪）。

### 2.10 bounded 尝试 #2 实测：拿到真实错误串，与上游逐字一致

提交 `a487f5f`（`E2E_TIMEOUT_MS` 开关，默认仍 60000）→ run **`35346668109`**（`-f e2e_timeout_ms=300000`）。

**真实错误串终于出现**：

```
WebDriverError: session not created: DevToolsActivePort file doesn't exist
   when running "http://127.0.0.1:4444/session" with method "POST"
```

时间线：`POST /session` `12:54:34.175` → 服务端报错 `12:55:34.299`，**正好 60.1 秒**。
**与上游 `tauri-apps/webdriver-example` 的 Windows 失败逐字一致。**

#### 为什么之前五次都看不到它

| | 之前（60s 客户端超时） | 本次（300s） |
|---|---|---|
| 客户端超时 | 60.000s | 300.000s |
| msedgedriver 放弃时间 | 约 60.1s | 约 60.1s |
| 结果 | **客户端先超时**，服务端错误被覆盖，只看到 `Request timed out` | 客户端等到服务端返回，拿到 `DevToolsActivePort` |

⇒ **这是一次「竞态」而非「超时不够」**：两边都约 60 秒，客户端每次都抢先一步把结论盖掉。放宽客户端超时后竞态消失。**该开关是必要的，不是白加。**

#### 由此确立的事实

1. **我们的故障与上游官方示例是同一个**（错误串逐字一致），不是我们独有的配置错误。
2. **在已传 `webviewOptions{ additionalBrowserArguments: ['--remote-debugging-port=0'], userDataFolder: <临时目录> }` 的前提下仍报此错** ⇒ 该 capability **没有把调试端口送进 WebView2 浏览器进程**。
3. 候选里只剩**唯一一条机制独立**的路径：**方案 1** —— 走 `tauri.conf.json` 的 `additionalBrowserArgs`，经 `tauri-runtime-wry-2.11.2/src/lib.rs:5054-5055` 直接设进 WebView2 的 `AdditionalBrowserArguments`，**不经过 `webviewOptions` 通道**。

#### 方案 1 的关键前提：目录必须对齐

`tauri-utils-2.x/src/config.rs:2225` 有一条 Windows 专属硬约束：

> **Windows**: WebViews with different values for settings like `additionalBrowserArgs` … **must have different data directories**.

且 `:2219` 写明配置里的 `dataDirectory` 是**相对于 `appDataDir()/${label}`**（绝对路径需走 Rust API）。

⇒ 高度怀疑根因是**目录错位**：WebView2 把 `DevToolsActivePort` 写在它**自己实际使用**的 user data folder（wry 侧由 `webview_attributes.data_directory` 决定，默认 `None` → 走 wry 默认目录，`tauri-runtime-wry-2.11.2/src/lib.rs:4795`），而我们传给 EdgeDriver 的 `userDataFolder` 是**另一个**临时目录 ⇒ **EdgeDriver 去错地方找**。已派 Cody 核实并给出对齐方案，作为**最后一次** CI 尝试的依据。

### 2.11 真实 UDF 已测定（双候选探测）—— 并顺带推翻我的推导

run **`35350670139`**（提交 `9de4c4d`，双候选探测）：

```
[UDF 探测 A] 目录存在但无 DevToolsActivePort（共 1 项）: C:\Users\runneradmin\AppData\Local\com.asd.tauri
[UDF 探测 A] 目录条目: EBWebView
[UDF 探测 B] 目录不存在: D:\a\...\asd-tauri.exe.WebView2
```

| 结论 | 依据 |
|---|---|
| **A（`%LOCALAPPDATA%\com.asd.tauri`）是真实 UDF** | 含 `EBWebView`（WebView2 UDF 的标准子目录） |
| **B（`<exe>.WebView2`）不是** | 本轮**根本不存在**；上一轮它存在纯属我们当时把 `userDataFolder` 指向它而**自己造出的残留** |
| **⇒ 我 2.10 里的推导是错的** | Tauri 在 wry 之上强制填 `data_directory`（`tauri-2.11.2/src/manager/webview.rs:534-543`），wry 从不到 `None`，「空串 → 默认 UDF」这条链不成立 |

> ⚠️ **教训（本轮第二次同类错误）**：跨层行为必须追到「**谁最后赋值**」，不能只看声明处。
> 我读了 `wry` 的 `unwrap_or_default()` 就下结论，却没看它上面那层 Tauri 已经把值填了。
> 已写入项目记忆。

同时坐实：**A 在用（有 `EBWebView`）但没有 `DevToolsActivePort`** ⇒ WebView2 没开远程调试端口 ⇒ **`webviewOptions` 通道确定不通**。

### 2.12 bounded 尝试 #3（方案 1，最后一招）：同样失败，止损

方案 1 = 走 `tauri.conf.json` 的 `additionalBrowserArgs`（提交 `7bc17e5` + E2E 专用 `tauri.e2e.conf.json`）：

```json
"additionalBrowserArgs": "--remote-debugging-port=9333 --disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection"
```

- 字段已核实：`tauri-utils-2.x/src/config.rs:2080-2083`，JSON 键 `additionalBrowserArgs`，类型 **String**；
  文档明确警告「设了会**替换** wry 默认值，须自行补回 `--disable-features=...`」（已补）。
- `--config` 合并语义**已实测为深合并**（Rex 本地实跑 rc=0：delta 里没有 `productName`/`bundle`，
  产物仍带这些 ⇒ 必为 merge），故只需写增量。
- 端口用**固定 9333**：`=0` 时 WebView2 不写 `DevToolsActivePort`；且固定端口不能靠
  `debuggerAddress` 注入（tauri-driver 用 `always_match.extend(native)` 整体替换 `ms:edgeOptions`）。

run **`35354358075`** 结果 **failure**，判据与 #2 **完全一致**：

```
[UDF 探测 A] 目录存在但无 DevToolsActivePort（共 1 项）: ...\com.asd.tauri
[0-0] ERROR webdriver: session not created: DevToolsActivePort file doesn't exist
```

#### 结论：止损

**两条机制上相互独立的通道均已实测失败，候选已穷尽：**

| # | 通道 | 机制 | 结果 |
|---|---|---|---|
| ① | `webviewOptions.additionalBrowserArguments` | msedgedriver →（未证明的通道）→ WebView2 | ❌ UDF 有 `EBWebView`、无 `DevToolsActivePort` |
| ② | `tauri.conf.json additionalBrowserArgs` | wry 显式 API → `AdditionalBrowserArguments`（必达） | ❌ 同上 |

⇒ 不是"参数没送进去"，而是**即便送进去了，WebView2 仍不写 `DevToolsActivePort`**。
叠加 §2.8 的外部证据（上游官方示例 Windows 连续 8 次失败、上游自己无 tauri-driver CI、
#15415 / #15605 未修），判定：**该 WebDriver 栈在 Windows 上当前不成立，停止投入。**

#### 止损动作（已派 Rex 执行）

1. **安全整改（必做）**：`ci.yml` 的 `e2e_build_config` 默认改回**空**，构建步仅在其非空时带 `--config`
   —— 避免常规 debug 构建长期产出带 `--remote-debugging-port` 的二进制（纯风险、零收益，方案 1 已失败）
2. `tauri.e2e.conf.json` 顶部标注**已证伪**（含 run 号与探测结果），保留供将来重试，但默认不启用
3. 登记 **TD-061**（栈不成立 + 完整证据链）与 **TD-062**（E2E 有诊断价值但未接入常规门禁）
4. E2E job **保持手动触发**，不改为默认门禁 —— **一个已知红的门禁比没有门禁更糟**

> ⚠️ 我原本的收尾清单里有两条错的（"让 `e2e_build_config` 默认打开"、"E2E 改为默认开启"），
> 由 Rex 驳回、我采纳。详见 §"待完善"。

---

## 三、门禁漂移收口（同一个 bug 形状三次）

| 闸门 | 问题 | 处置 |
|---|---|---|
| **G3d** | `.ps1` 跑 `--no-cargo` 快速档（只查文档内部自洽），运行期对账从未真正执行 | 切完整模式，实测 **15.8s**、exit 0 |
| **G3c** | `.ps1` 只跑 `e2e/helpers/__tests__`，**漏掉 `src/__tests__`** | 显式收集两目录绝对路径；目录不存在即硬失败 |
| **G2b / G3a** | 缺 `CARGO_INCREMENTAL=0`（`.sh` 有）→ ICE 风险 | 补上，try/finally 不污染后续闸门 |

G3c 的阳性对照**复现了旧配置的静默失效**：少收一个文件却仍显示 ✓，漏掉 `src/__tests__/api_contract.test.js`——那是 TD-005 里唯一抓到过真缺陷的测试（发现 `export_recording` 缺 `delays` 参数）。真跑 `node --test` **39 tests / 39 pass**。

**C10 防漂移守卫**（硬失败、不棘轮），双探针：G3d 的 `--no-cargo` 有无、G3i 的 `--selftest` 有无。两个刻意设计：
1. 判据每次从三份文件**正则提取后互比**，脚本里**不存**标准清单——否则那份清单就成了第五份权威副本
2. 判定用「**标志有无**」而非「调用命令全文」——三处 shell 语法天然不同，比全文必然全是假阳性

✅ Cody 主动**否决了 C10 的通用化**，论证成立：做成「任一闸门命令一致」会因语法差异全是假阳性；做成「闸门 ID 集合齐备」一上就红（G3g 只在 `.sh`/`ci.yml`、G3f/G3h 只在 `ci.yml`），压下去又要维护豁免清单——**而豁免清单正是 C10 要消灭的假权威副本**。

**G3i**：`build_graph.py --selftest` 接入三处，紧挨 G1，且**刻意不进 `--quick` / `-SkipGraph`**——自检类闸门被跳过即等于不存在。阳性对照是端到端真跑：破坏重导出正则 → `bash scripts/check-gates.sh` 真的 FAIL、结尾 `FAILED GATES: G3i`。

---

## 四、TD-051：图谱 JS 依赖提取（Archi）

JS 边改**互斥穷尽的四分法**：

| 类别 | 内容 | 进环检测 |
|---|---|---|
| value | 普通 `import` | ✅ |
| **type-only** | `import type X from` / `import { type X } from` / `export type { X } from` | ❌ |
| **re-export** | `export { x } from` / `export * from` / `export * as ns from` | ✅ |
| builtin | `node:` 前缀 | ❌ |

- 仅类型边编译后被完全擦除、不产生运行时依赖，进环检测会把无害的类型循环判成真环并硬失败阻断提交
- 重导出是此前的**假阴性**，现已计为值边并参与环检测
- 新增 `--selftest` + 闸门 `check_js_edge_taxonomy`：拿 `js.edges` 独立重算环检测输入，与留痕的 `cycle_input_edges` **对撞**（防永真式）
- **基线零漂移**：`counts` 一字未改

**阳性对照用了「新旧行为同注入复算」**：`import type` 注入在旧行为下复算为**环 1**、新行为**环 0**；重导出注入在禁用识别后**环 0**（假阴性坐实）、启用后**环 1** 且闸门点名两文件。

> ⚠️ **我下发的前提有一条是错的，已被 Archi 纠正**：我以为 e2e 目录被整体排除、JS 依赖不在图里。实测 `js_e2e_files=19` 已在图内，该盲区在 TD-051 前半就修掉了。**旧报告的前提要先验证再用。**

---

## ✅ 行动清单

| # | 行动 | 负责角色 | 紧急度 | 预期完成 |
|---|------|---------|--------|---------|
| 1 | **止损收尾**：`ci.yml` 的 `e2e_build_config` 默认改回空（摘掉常规构建上的调试端口）+ `tauri.e2e.conf.json` 标注已证伪 + 登记 **TD-061 / TD-062** | Rex | P0 | 进行中 |
| 2 | **人工在真终端跑一次 `check-gates.ps1` 全量**（沙箱禁止 PowerShell 启外部进程，端到端未验） | 用户 / 主理人 | P0 | 提 PR 前 |
| 3 | **台账自洽收尾**（统计行 / 状态词 / TD-007 前提纠错 / 快照数字改指针）—— 用户本轮未选，仍是 P0 欠账 | Docu / 主理人 | P1 | 下轮 |
| 4 | TD-059 到期复查（2026-12-18）：先读描述里三个坑是否仍在 | Cody | P1 | 2026-12-18 |
| 5 | G3f 覆盖率棘轮补「基线文件必须全部出现在本次 lcov」+ 文件数下限 | Tessa / Cody | P1 | 下轮 |
| 6 | G4 清单固化：抽 `docs/g4-manual-checklist.md` 单一来源 ⚠️ 编号改用 **C13**（**C12 本轮已被占用**） | Docu | P2 | 下轮 |

---

## ⚠️ 待完善 / 已知局限

- **`.ps1` 端到端未验证**：`.sh` 那处是端到端真跑；`.ps1` / `ci.yml` 两处是命令级 + C10 互比验证。提 PR 前必须人工在真终端跑一次全量。
- **第三次执行的 wdio 汇总行至今拿不到**（日志接口 `403 Must have admin rights`）。「第 3、4 次同一失败形态、非 flaky」基于**时长签名**（36m37s / 36m32s，地板 36m00s；第 2 次仅 39 秒），**是推断非原文引用**。
- `connectionRetryCount` 3→0 的残留风险：`waitForPort` 只把关 TCP 可连接、不把关 session 可建立，若 driver 冷启动真超 60s 会少掉重试窗口。已知取舍。
- ⚠️ **「执行器崩 → `/session` 超时」这条因果链已被 run `35335990999` 证伪**：P0 修复后 AHK 报错归零，`/session` 依旧超时 —— 日志里同时出现的两件事**是相关不是因果**。第七道死因根因未定，已排除三项：WebView2 缺失（探测证伪）、AHK 打包（已修且非主因）、msedgedriver/WebView2 版本不匹配（主版本同为 152）。
- TD-051 已知限制：动态 `import()` 与 `import x = require()` 仍不识别（非回归）。
- 本轮**未做**：台账自洽收尾（统计行 / 状态词 / TD-007 前提纠错 / 快照数字改指针）—— 用户本轮未选，仍是 P0 欠账。

### 主理人（甄宇航）本轮自认的错误 —— 全部由成员在执行前拦下

| # | 错误 | 后果 | 谁拦下 |
|---|---|---|---|
| 1 | **编了一个不存在的 run 号 `35345137616`** 写进判定表 | 违反自己定的红线「只报你实际看到的东西」；Rex 一查 404 | Rex |
| 2 | 为「变量单一」锁死 `connectionRetryTimeout=60000` | **连续 6 轮**真实错误串被自己的超时盖掉，全部白跑 | 自查（run `35343866509` 后） |
| 3 | 只读 `wry` 的 `unwrap_or_default()` 就推「UDF = `<exe>.WebView2`」 | 推导错误；未看到上层 Tauri 已强制填 `data_directory`（`manager/webview.rs:534-543`） | Rex |
| 4 | 只读 `tauri` 的 `additional_browser_args` 就推「必须改 Rust」 | 推导错误；它本来就是 `tauri.conf.json` 的窗口字段 | Cody |
| 5 | 没看全 `[UDF 探测 B]` 就宣布「通道确定不通」 | 在自己定的红线上犯第二次；`EBWebView` 只证明被用过、不证明当前在用 | Rex |
| 6 | 判定表缺一格（B 有 `DevToolsActivePort`），且用「目录存在」当判据 | 会把「存在但无端口」误判成「路径对」 | Rex |
| 7 | 收尾清单两条方向性错误：让 `e2e_build_config` 默认打开、E2E 改默认门禁 | 前者让常规构建长期带调试端口；后者会制造**已知红的噪音门禁** | Rex |

> **可复用教训**：① **报错被超时吃掉会呈现错误的故障面** —— 排查"永久挂起"先自问超时是否盖住了服务端错误；
> ② **跨层行为必须追到「谁最后赋值」**，不能只看声明处；
> ③ **探测类判据要设计成自带判据**（本次双候选 UDF 探测），否则错一次就要多跑一轮；
> ④ **`cancel-in-progress: true` 会让同一 ref 的新 run 取消旧 run** —— 今天 4 次 run 这么没了，dispatch 前先看 concurrency 配置；
> ⑤ **修好 ≠ 生效**：本次及此前的 G3d 跑 `--no-cargo`、G3c 漏收目录、E2E 从未真跑，全是同一形状。

---

## 📚 数据来源 & 成员产出索引

- **Cody**：TD-055 实测 15.8s；G3c/G2b/G3a 三处漂移修复（含「旧配置复现 → 少收文件仍显示 ✓」存证）；C10 双探针设计与通用化否决论证；G3i 三处接入 + 端到端阳性对照；TD-059 登记与否决理由；**P0 打包缺陷修复 + C11 守卫 + TD-060 登记**；逐条实测我给的三个行号（全部准确）。
- **Archi**：JS 边四分法；`--selftest`；`check_js_edge_taxonomy` 对撞校验；新旧行为同注入复算的阳性对照；**纠正我下发的过时前提**。
- **Rex**：第四次执行完整诊断（汇总行原文 + 9×4min=36m32s 算术交叉验证）；第五道修复生效证据；`driverLog` 提模块级 + 三行环境探测 + `connectionRetryCount` 实断；**两度拒绝在无证据时推断根因、拒绝引用未看到的数字**。
- **主理人独立复核**：远端 main 实为 `ce78fb1`（`origin/main` 因代理 fetch 失败陈旧，误报"领先 206 提交"）；`ci.yml` WebView2 仅出现在第 31 行描述文字；`wdio.conf.js` 语法校验 + `waitForPort` 单调用 + 无 CI 分支；`tauri.conf.json` resources 与 `ahk_executor/` 实际文件比对；第五次执行日志中 driverLog 关键行提取；`C11` 与 `C10` 独立跑通。
- **提交**：`613a282` → `081953a` → `9b4d5e6` → `cce526f` → `33d3c07` → `e50f8c2` → `3c8496e`。
- **CI 佐证**：run `35335990999` 的「四闸门 (windows-latest)」= **success in 4m52s**（含 C11 在内的全部门禁在 CI 的 Windows 上通过）。

---

> 本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
