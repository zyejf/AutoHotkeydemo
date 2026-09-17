# E2E 已知问题

<!-- 清理说明（2026-06-29）：
     本次清理按以下规则执行：
     1. 删除 E2E-MODE 系列所有记录（已确认过时，测试 7/7 通过），包括范围记录、单独记录、IPC 变体
     2. 删除 E2E-KEY 系列所有记录（已确认过时，测试通过），包括范围记录、单独记录、IPC 变体
     3. 删除所有重复段落，同一 ISSUE ID 只保留第一次出现的那一份
     4. 删除所有空记录段落（"- **实际:**" 后面为空的段落）
     5. 保留 ISSUE-011/012（已解决）、ISSUE-013~016（环境配置问题）
     6. 保留 GRP/HK/IPC/REC/SYS 系列的唯一非空记录
     7. 保留 2 个 -RESOLVED 段落（E2E-SYS-005-RESOLVED、E2E-HK-003-RESOLVED）
     清理前：969 行；清理后：约 200 行
-->

<!-- 更新说明（2026-06-29 第二次更新）：
     基于 9/9 E2E 测试全部通过的验证结果，重组文件结构：
     1. ISSUE-013/014/016 已真正修复，移到"已解决问题"段并标记为 RESOLVED
     2. ISSUE-015 部分修复，降级为 [LOW] 并更新描述（根因未完全修复但当前不触发）
     3. 连带 ISSUE-E2E-GRP/HK/IPC/REC/SYS 系列全部标记为 RESOLVED（因根因 ISSUE-013/014/016 已修复）
     4. 合并 ISSUE-E2E-SYS-005-RESOLVED 和 ISSUE-E2E-HK-003-RESOLVED 到已解决问题段
     5. 保留 ISSUE-E2E-IPC-004-NO-EVENT 和 ISSUE-E2E-IPC-006-NO-EVENT（E2E 环境限制，非 bug）
     更新前：204 行；更新后：约 200 行
     已解决问题：16 个；未解决问题：1 个；环境限制记录：2 个
-->

<!-- 更新说明（2026-09-13）：
     1. 清理本次修复过程中 E2E 自动追加的 13 条记录（均为重复或已证伪）：
        - E2E-MODE-006 / E2E-KEY-005 / E2E-MODE-005 / E2E-KEY-003 等 [HIGH] 条目
          已确认是**测试脆弱性而非产品缺陷**（见 BUG-7）：失败项每次都不同、隔离运行必过。
          现已修复观察窗口与断言方式，E2E 全量连续 2 轮 9/9，故不登记为 ISSUE。
        - E2E-IPC-004/006-NO-EVENT 重复追加多份，保留原有唯一记录（在"环境限制"段）。
     2. **ISSUE-012 于本次回归并已彻底解决**（详见下方补充说明）。
     更新前：198 行；更新后：185 行
-->

## 已解决问题

### ISSUE-011 [RESOLVED] msedgedriver.exe 缺失

- **状态**: ✅ 已解决（2026-06-28）
- **原描述**: msedgedriver.exe 未安装，导致所有 E2E 测试无法启动 WebDriver 会话
- **解决方案**: 下载 msedgedriver 149.0.4022.98 到 `e2e/drivers/msedgedriver.exe`，tauri-driver 通过 `--native-driver` 参数显式指定
- **验证**: smoke 测试通过，WebDriver 会话成功建立

### ISSUE-012 [RESOLVED] Binary 使用 devUrl 而非 frontendDist

- **状态**: ✅ 已解决（2026-06-28）
- **原描述**: `cargo build --release` 构建的 binary 使用 `devUrl`（http://127.0.0.1:5173）而非 `frontendDist`（../dist），导致 webview 无法加载页面，msedgedriver 报 "Origin header is not a valid URL" 错误
- **解决方案**: 改用 `npx tauri build --debug --no-bundle` 构建 binary，正确嵌入前端
- **验证**: 页面标题返回 "技能管理器 v3.0"，executeScript 调用成功

> **⚠️ 2026-09-13 回归记录与最终修复**
>
> 本问题于 2026-09-13 **再次回归**（E2E 1/9 通过）。根因与本次实测一致，
> 但**原解决方案存在缺陷**：它依赖**构建方式**（必须 `tauri build`），
> 一旦有人用 `cargo build` 重建 `target/debug/asd-tauri.exe`，运行时仍会走 `devUrl`，
> 且**二进制内是否含前端 HTML 无法用来判定运行模式** —— debug 构建即使内嵌资源也走 devUrl。
>
> **最终修复（运行时保障，不依赖构建方式）**：
> `wdio.conf.js` 的 `onPrepare` **自动托管 Vite dev server**（未监听则启动并等待就绪），
> `onComplete` 回收；`helpers/tauri.js` 的 `startApp()` 增加**页面加载健全性检查**
> （断言 `location.protocol !== 'chrome-error:'`），使同类故障立即报出可读根因。
>
> **排错要点**：`window.__TAURI__` 在错误页上**依然存在**（`withGlobalTauri` 注入对任何文档生效），
> 且**窗口标题非空 ≠ 页面加载成功**（标题取自 `tauri.conf.json`）—— 两者都曾误导定位。
>
> **验证**: E2E 全量 **9/9 通过（60/60 用例）**，连续两轮稳定。

### ISSUE-013 [RESOLVED] build_ahk.ps1 PowerShell 语法错误

- **状态**: ✅ 已解决（2026-06-29）
- **原描述**: 执行 `npx tauri build --debug --no-bundle`（beforeBuildCommand 调用 build_ahk.ps1）时报错 "表达式或语句中包含意外的标记'}'"（line 29 char 1），导致 AHK 子进程未构建，所有 IPC/key_send/modes 测试失败
- **解决方案**: 修复 build_ahk.ps1 的 PowerShell 语法错误
- **验证**: 成功运行 build_ahk.ps1，asd_executor.exe 正常生成（1.26 MB），编译过程无弹窗
- **影响范围**: 修复后连带解决 ISSUE-016 及所有依赖 AHK 子进程的 E2E 测试

### ISSUE-014 [RESOLVED] get_executor_status 字段命名不一致

- **状态**: ✅ 已解决（2026-06-29）
- **原描述**: 调用 `get_executor_status` 命令返回 `restart_count`（snake_case）而非 `restartCount`（camelCase），导致 E2E-SYS-001 断言失败
- **解决方案**: 在 `asd-tauri/src-tauri/src/infrastructure/watchdog.rs` 的 state.rs:20 添加 `#[serde(rename = "restartCount")]`，统一返回 camelCase
- **验证**: E2E-SYS-001 通过，断言期望 `status.restartCount`（camelCase）匹配成功
- **影响范围**: 连带解决 ISSUE-E2E-SYS-001

### ISSUE-016 [RESOLVED] AHK 子进程未运行导致 IPC 测试失败

- **状态**: ✅ 已解决（2026-06-29）
- **原描述**: 启动应用后调用依赖 AHK 子进程的命令（toggle_group 激活、key_send 等）时，IPC 通信错误 "连接已关闭"（AHK 子进程未启动），导致所有 IPC/key_send/modes 测试失败
- **解决方案**: ISSUE-013 修复后 asd_executor.exe 正常生成，watchdog.spawn_child 成功启动 AHK 子进程，named pipe 连接建立
- **验证**: E2E 测试 9/9 通过，IPC 通信成功，心跳维持正常
- **影响范围**: 连带解决 ISSUE-E2E-IPC-001、003~006 及所有依赖 AHK 子进程的 E2E 测试

### ISSUE-E2E-GRP-004 [RESOLVED] toggle_all 失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 调用 `toggle_all` 命令时 invoke 返回 "unknown error"，E2E-GRP-004 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，ISSUE-015 的 try-catch 修复使 invoke 错误被捕获后继续轮询
- **验证**: E2E-GRP-004 测试通过

### ISSUE-E2E-GRP-005 [RESOLVED] batch_toggle_groups 失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 调用 `batch_toggle_groups` 命令时 invoke 返回 "unknown error"，E2E-GRP-005 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，IPC 通信成功
- **验证**: E2E-GRP-005 测试通过

### ISSUE-E2E-HK-002 [RESOLVED] unregister_hotkey 失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 调用 `unregister_hotkey` 命令时 invoke 返回 "unknown error"，E2E-HK-002 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，热键注销成功
- **验证**: E2E-HK-002 测试通过

### ISSUE-E2E-HK-003 [RESOLVED] 热键实际触发失败

- **状态**: ✅ 已解决（2026-06-28）
- **原描述**: 注册热键并模拟按下后，key_log.txt 未捕获按键事件，E2E-HK-003 测试失败
- **根因**: 两个问题协同导致失败：
  1. 临时脚本 `Send("{F8}")` 默认 SendLevel=0，无法触发热键钩子（AHK 默认行为：Send 模拟的按键不触发热键，除非 SendLevel > hook level）
  2. key_receiver.ahk 使用 `Hotkey("IfWinActive", "ahk_id " keyGui.Hwnd)` 限定热键上下文为 GUI 窗口，但 ASD Tauri 应用抢占前台导致窗口激活失败，IfWinActive 上下文不匹配
- **解决方案**:
  1. 在 hotkey_cmd.spec.js 临时脚本中添加 `SendLevel(10)`，让 Send 发送的按键携带 level=10 标记，触发 key_receiver 默认 level=0 的热键钩子
  2. 在 key_receiver.ahk 中移除 `Hotkey("IfWinActive", "ahk_id " keyGui.Hwnd)` 上下文限制，改为全局热键，避免窗口激活问题
- **验证**: 修复后 E2E-HK-003 通过（耗时 1508ms），key_log.txt 正确捕获到 F8 down/up 事件

### ISSUE-E2E-IPC-001 [RESOLVED] watchdog 状态断言失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 应用启动后调用 `get_executor_status` 命令，AHK 子进程未启动时 watchdog 可能进入 Failed 状态，导致 E2E-IPC-001 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常启动，watchdog 维持 Running 状态
- **验证**: E2E-IPC-001 测试通过，watchdog 状态为 Running

### ISSUE-E2E-IPC-003 [RESOLVED] 心跳维持测试失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 等待 5 秒后 watchdog 仍应为 Running，但 AHK 子进程未运行导致心跳无法维持，E2E-IPC-003 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，心跳维持正常
- **验证**: E2E-IPC-003 测试通过，5 秒后 watchdog 仍为 Running

### ISSUE-E2E-IPC-004~006 [RESOLVED] 事件转发测试失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 注册事件监听器后激活分组，AHK 子进程未运行导致无事件产生，E2E-IPC-004 (hotkey_event)、005 (key_send_event)、006 (key_record_event) 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，事件转发链路恢复
- **验证**: E2E-IPC-004~006 测试通过（注：IPC-004/006 的 NO-EVENT 环境限制仍存在，见下方"环境限制"段）

### ISSUE-E2E-REC-002~005 [RESOLVED] 录制状态机测试失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: start_recording → pause/resume/stop 流程中 invoke 返回 "unknown error"（不匹配预期正则），E2E-REC-002 (pause)、003 (resume)、004 (stop)、005 (完整流程) 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，录制状态机命令成功执行
- **验证**: E2E-REC-002~005 测试通过

### ISSUE-E2E-SYS-001 [RESOLVED] restartCount 字段不存在

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-014 修复）
- **原描述**: 调用 `get_executor_status` 命令返回 `restart_count`（snake_case）而非 `restartCount`（camelCase），导致 E2E-SYS-001 测试失败
- **解决方案**: 见 ISSUE-014（添加 `#[serde(rename = "restartCount")]`）
- **验证**: E2E-SYS-001 测试通过

### ISSUE-E2E-SYS-004 [RESOLVED] toggle_hold_mode 失败

- **状态**: ✅ 已解决（2026-06-29，随 ISSUE-013/016 修复）
- **原描述**: 调用 `toggle_hold_mode` 命令时 invoke 返回 "unknown error"，E2E-SYS-004 测试失败
- **解决方案**: ISSUE-013 修复后 AHK 子进程正常运行，toggle_hold_mode 成功返回新状态
- **验证**: E2E-SYS-004 测试通过

### ISSUE-E2E-SYS-005 [RESOLVED] reset_watchdog 失败

- **状态**: ✅ 已解决（2026-06-28）
- **原描述**: 调用 reset_watchdog 时，invoke 辅助函数的 browser.execute() 轮询循环因 tauri-driver/msedgedriver 的 flaky "unknown error"（HTTP 200 with error body）而抛出异常，导致 E2E-SYS-005 测试失败
- **根因**: tauri-driver 在执行 /execute/sync 端点时间歇性返回 HTTP 200 + error body，WebDriverIO 重试 3 次后抛出 "unknown error"，错误消息不匹配测试期望的正则表达式
- **解决方案**: 在 e2e/helpers/tauri.js 的 invoke 辅助函数轮询循环中添加 try-catch，捕获 browser.execute() 的异常后继续轮询，因为 invoke 可能已在后端成功执行，仅前端读取 window.__e2e_result 失败
- **验证**: 修复后 E2E-SYS-005 通过（耗时 18742ms，证明 try-catch 生效，"unknown error" 被捕获后继续轮询直到成功）

## 未解决问题

### ISSUE-015 [LOW] Tauri invoke 错误消息为 "unknown error"

- **状态**: ⚠️ 部分修复（2026-06-29，降级为 LOW）
- **关联用例**: 历史关联 E2E-GRP-004, 005, E2E-HK-002, 003, E2E-REC-002~005, E2E-SYS-004, 005（共 15 个，现均已通过）
- **直接修复**: 在 `e2e/helpers/tauri.js` 第 49-57 行的 invoke 轮询循环中添加 try-catch，捕获 flaky "unknown error" 异常并继续轮询
- **间接修复**: ISSUE-016 修复后 AHK 子进程正常运行，IPC 不再失败，invoke 不再返回 "unknown error"
- **仍存在的问题**: `e2e/helpers/tauri.js` 第 33-39 行的 invoke 错误消息提取逻辑未改进，当 IPC 真正失败时仍可能返回不友好的 "unknown error" 错误消息
- **当前状态**: 因 AHK 子进程正常运行（ISSUE-013/016 修复后），此问题当前不触发，但根因（错误消息提取逻辑不完善）未完全修复
- **建议**: 后续可改进 invoke 错误消息提取逻辑，序列化完整错误对象以便调试

## 环境限制（非 bug）

### ISSUE-E2E-IPC-004-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-004)

- **复现步骤**: 激活分组后等待 3s，前端未收到 hotkey_event 事件
- **预期**: 按下 F1 后前端应收到 hotkey_event 事件
- **实际**: E2E 环境无法可靠模拟真实键盘按下，hotkey_event 未触发
- **影响**: 热键事件转发链路无法完整验证
- **建议**: 在手动测试环境按下 F1 验证，或使用 key_receiver 辅助验证

### ISSUE-E2E-IPC-006-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-006)

- **复现步骤**: 开始录制后等待 2s，前端未收到 key_record_event 事件
- **预期**: 录制时按下按键前端应收到 key_record_event 事件
- **实际**: E2E 环境无法可靠模拟真实键盘按下，key_record_event 未触发
- **影响**: key_record_event 转发链路无法完整验证
- **建议**: 在手动测试环境按下按键验证
## ISSUE-017 [HIGH]

- **复现步骤:** 运行 cd asd-tauri/e2e 后执行 npm test
- **预期:** WebDriver 会话成功建立，9 个 suite / 53 个用例正常运行
- **实际:** session not created: This version of Microsoft Edge WebDriver only supports Microsoft Edge version 149. Current browser version is 151.0.4129.93。全部 9 个 spec 在创建 WebDriver 会话阶段失败（Spec Files: 0 passed, 9 failed, 9 total）
- **影响:** E2E 全部用例无法运行（WebDriver 会话建立失败，未进入任何测试用例）
- **建议:** 更新 e2e/drivers/msedgedriver.exe 至与 WebView2 Runtime 151.0.4129.93 匹配的版本（从 https://msedgedriver.microsoft.com/ 下载对应 Edge 版本）

### ISSUE-018 [RESOLVED] 首次 getTitle() 卡 60s（真因：Vite 首次模块转换 ~51s，非窗口未就绪）

- **状态:** ✅ 已解决（2026-09-16）
- **原描述:** WebDriver 会话创建成功、应用进程也已起来，但 `startApp()` 里的第一个
  `browser.getTitle()` 要 **54~60 秒**才返回，直接吃满 mocha 的 60s 预算，报
  `Timeout` / `App window did not become ready`。长期被记成「页面级加载问题」（TD-016）。
- **⚠️ 定位过程中被排除的三个错误假设**（都实测推翻了，别再重复踩）：
  1. ~~应用启动慢~~ —— 应用日志显示 `04:39:22.581` 启动、`04:39:23.393` 全部就绪，**0.8 秒**。
  2. ~~前端编译慢 / 代理作祟~~ —— curl 直连 `http://127.0.0.1:5173/` 只要 0.046s；
     去掉 `HTTP_PROXY`/`HTTPS_PROXY` 后重跑**依然 53s**。
  3. ~~getTitle 本身慢~~ —— 页面就绪后实测 `getTitle()` **5ms**、`getWindowHandles()` **4ms**。
- **真因:** Vite dev server 的**首次**模块转换极慢。实测 `vite --debug`：
  ```
  vite:load     549.79ms  [fs] /src/styles.css
  vite:transform 51166.73ms /src/styles.css   ← 51.2 秒（0 imports rewritten）
  vite:cache [memory] /src/styles.css → 0.68ms
  ```
  curl 冷请求 `/src/styles.css` 耗时 **59.79s** 且 `time_starttransfer` ≈ `time_total`
  （整整 58s 一个字节都没发），热请求 0.004s。
  于是首屏 `loadEventEnd` 约 54s；而 WebDriver 的 `getTitle()` / `execute()` 都会
  **阻塞到页面 load 完成**（不是它们慢），首个命令因此吃掉整个 60s 预算 ——
  **表面是 `getTitle()` 超时，真因是前端冷转换**。
- **解决方案:** `wdio.conf.js` 的 `onPrepare` 在**建立 WebDriver 会话之前**预热 Vite
  （顺序请求 `/`、`/@vite/client`、`/src/main.js`、`/src/styles.css`，单请求超时 120s）。
  刻意**顺序**而非并发：并发会让多个冷转换互相争抢（实测并发时 styles.css 52.7s /
  api.js 22.3s / env.mjs 20.7s 各自都慢），顺序时除第一个外均 <3s。
- **验证:** `readyState` 阻塞 **53847ms → 837ms**；`loadEventEnd` **53809ms → 853ms**；
  首次 `getTitle()` **54644ms → 7ms**。全量 E2E（修复后实测）**Spec Files 8 passed / 1 failed / 9 total，耗时 10m43s**；
  唯一失败的 `E2E-MODE-002` 隔离复跑 **7/7 全绿**（负载相关抖动）。
  ⚠️ **未取修复前的全量基线**：修复前只实测到单跑 smoke 必然失败（首个命令必吃满 60s 预算），
  **没有**跑过 9 套件全量，因此不要引用「修复前 0 passed / 9 failed」—— 那是推断不是实测。
- **副作用:** 每次 E2E 多付约 60s（一次性，在 onPrepare 内，不占用例预算）。
  预热失败**不阻塞**，只打 `[WARN]` 并退化成原来的慢首屏。

## ISSUE-E2E-IPC-004-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-004)

- **复现步骤:** 激活分组后等待 3s，前端未收到 hotkey_event 事件
- **预期:** 按下 F1 后前端应收到 hotkey_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，hotkey_event 未触发
- **影响:** 热键事件转发链路无法完整验证
- **建议:** 在手动测试环境按下 F1 验证，或使用 key_receiver 辅助验证

## ISSUE-E2E-IPC-006-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-006)

- **复现步骤:** 开始录制后等待 2s，前端未收到 key_record_event 事件
- **预期:** 录制时按下按键前端应收到 key_record_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，key_record_event 未触发
- **影响:** key_record_event 转发链路无法完整验证
- **建议:** 在手动测试环境按下按键验证

## ISSUE-E2E-KEY-001-IPC [HIGH] (关联用例: E2E-KEY-001)

- **复现步骤:** 启动分组并等待按键执行（periodic Space）
- **预期:** key_log.txt 应包含 periodic Space 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-001 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-002-IPC [HIGH] (关联用例: E2E-KEY-002)

- **复现步骤:** 启动分组并等待按键执行（periodic Space 间隔）
- **预期:** key_log.txt 应包含 periodic Space 间隔 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-002 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-003-IPC [HIGH] (关联用例: E2E-KEY-003)

- **复现步骤:** 启动分组并等待按键执行（sequence 1,2,3）
- **预期:** key_log.txt 应包含 sequence 1,2,3 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-003 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-004-IPC [HIGH] (关联用例: E2E-KEY-004)

- **复现步骤:** 启动分组并等待按键执行（hold Shift down）
- **预期:** key_log.txt 应包含 hold Shift down 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-004 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-005-IPC [HIGH] (关联用例: E2E-KEY-005)

- **复现步骤:** 启动分组并等待按键执行（periodic Space 紧急释放前）
- **预期:** key_log.txt 应包含 periodic Space 紧急释放前 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-005 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-MODE-001-IPC [HIGH] (关联用例: E2E-MODE-001)

- **复现步骤:** 启动分组并等待按键执行（periodic Space）
- **预期:** key_log.txt 应包含 periodic Space 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-001 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-002-IPC [HIGH] (关联用例: E2E-MODE-002)

- **复现步骤:** 启动分组并等待按键执行（sequence 1,2,3）
- **预期:** key_log.txt 应包含 sequence 1,2,3 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-002 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-003-IPC [HIGH] (关联用例: E2E-MODE-003)

- **复现步骤:** 启动分组并等待按键执行（hybrid Space+1,2）
- **预期:** key_log.txt 应包含 hybrid Space+1,2 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-003 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-004-IPC [HIGH] (关联用例: E2E-MODE-004)

- **复现步骤:** 启动分组并等待按键执行（hold Shift）
- **预期:** key_log.txt 应包含 hold Shift 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-004 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-005-IPC [HIGH] (关联用例: E2E-MODE-005)

- **复现步骤:** 启动分组并等待按键执行（enhanced_periodic Space,1）
- **预期:** key_log.txt 应包含 enhanced_periodic Space,1 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-005 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-006-IPC [HIGH] (关联用例: E2E-MODE-006)

- **复现步骤:** 启动分组并等待按键执行（enhanced_sequence 1,2,3）
- **预期:** key_log.txt 应包含 enhanced_sequence 1,2,3 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-006 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-007-IPC [HIGH] (关联用例: E2E-MODE-007)

- **复现步骤:** 启动分组并等待按键执行（enhanced_hybrid Space+1,2）
- **预期:** key_log.txt 应包含 enhanced_hybrid Space+1,2 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-007 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

