# 第三方组件声明 / Third-Party Notices

本软件在分发时包含以下组件。

---

## 0. 本软件自身

| 项目 | 内容 |
|---|---|
| 名称 | ASD 技能管理器（Tauri 包标识 `com.asd.tauri`） |
| 许可证 | **GNU General Public License v2.0 only（SPDX: `GPL-2.0-only`）** |
| 许可证全文 | 仓库根目录 `LICENSE`（亦随安装包分发） |

本仓库的 Rust 与 AHK 自研代码，以及前端代码，均以 `GPL-2.0-only` 授权。
许可证字段已同时写入：`asd-tauri/Cargo.toml` 的 `[workspace.package]`（5 个 crate
通过 `license.workspace = true` 继承）、`asd-tauri/package.json`、
`asd-tauri/src-tauri/tauri.conf.json` 的 `bundle.license` 与 `bundle.licenseFile`。

---

## 1. AutoHotkey v2.0.26

| 项目 | 内容 |
|---|---|
| 组件名 | AutoHotkey |
| 版本 | 2.0.26 |
| 许可证 | **GNU General Public License v2.0（GPL-2.0）** |
| 许可证全文 | 见同目录 **`AutoHotkey-license.txt`** |
| 在本软件中的用途 | 作为**独立子进程**执行器，负责按键模拟与热键钩子 |
| 分发形态 | `ahk_executor/AutoHotkey64.exe`（随安装包分发） |

> ⚠️ **关于 `AutoHotkey-license.txt` 的构成（易误读，必读）**
>
> 该文件是上游 `AutoHotkey-2.0.26/license.txt` 的**逐字节原文副本，未作任何删改**，共 351 行。
> 它是**一个复合文件，不是纯 GPLv2 文本**：
>
> | 行范围 | 内容 |
> |---|---|
> | 1–280 | GNU GPL v2 正文（至 `END OF TERMS AND CONDITIONS`） |
> | 282–351 | 内嵌的 **PCRE LICENCE**（BSD 风格，见下节） |
>
> 因此本文件**曾一度被命名为 `AutoHotkey-GPLv2.txt`，该命名已于 2026-09-19 订正为
> `AutoHotkey-license.txt`**（与上游文件名语义一致）——旧名会让人误以为其中只有 GPLv2，
> 从而漏掉内嵌的 BSD 声明义务。

### 源码获取

AutoHotkey v2.0.26 的**完整源码随本软件一同分发**，位于本仓库的 `AutoHotkey-2.0.26/source/`
（与上游官方 tag `v2.0.26` 一致，由仓库内的 **C6 校验**守护，禁止改动、fork 或重新编译）。

若你是通过安装包获得本软件而未获得源码仓库，可通过以下任一方式获取：

1. 访问本项目的公开代码仓库并下载对应版本的完整源码；
2. 依据 GPL-2.0 第 3 条，向本项目维护者索取源码副本（本要约在最后一次分发后三年内有效）。

---

## 2. PCRE（随 AutoHotkey 一同分发）

| 项目 | 内容 |
|---|---|
| 组件名 | PCRE（Perl Compatible Regular Expressions） |
| 版本 | Release 6 |
| 许可证 | **BSD 风格（PCRE LICENCE）** |
| 许可证全文 | 见 `AutoHotkey-license.txt` 第 282–351 行 |
| 版权 | Copyright (c) 1997-2006 University of Cambridge（基础库）；Copyright (c) 2006, Google Inc.（C++ 封装） |
| 分发形态 | 静态链接进 `ahk_executor/AutoHotkey64.exe`，无独立产物 |

PCRE 由 AutoHotkey 上游静态链接，本软件不单独引入、不修改。
BSD 许可证要求「二进制形式的再分发须在文档中复现版权声明与免责声明」，
已通过随附完整的 `AutoHotkey-license.txt` 满足。

---

## 3. 关系说明

本软件与 AutoHotkey 为**两个独立程序**：二者通过进程间通信（Windows 命名管道）交互，
各自运行在独立进程中，本软件不链接、不修改 AutoHotkey 的二进制或源码。

**2026-09-19 更新**：本项目**自身已选择 `GPL-2.0-only`**（与 AutoHotkey 同版本、同条款）。
因此「自研代码是否因分发 GPL 二进制而被传染」这一问题，**已不再影响本项目的分发策略** ——
无论该问题的答案如何，本项目对外授权的条款都是同一份 GPL-2.0。
此前登记为待法务复核的 Q2，其法律意见**降级为建议性**（用于外部沟通与合规存档），
不再是任何分发动作的前置阻塞项。

> 上述说明是对客观事实的描述，**不构成法律意见**。GPL-2.0 义务的具体范围
> 应由专业法务判断。

---

**本文件、`AutoHotkey-license.txt` 与仓库根 `LICENSE` 均随安装包分发**，
以满足 GPL-2.0 关于「随附许可证副本与源码获取说明」的要求
（对应技术债台账 TD-080 与 TD-081）。
