//! Tauri 命令数量守护测试（2026-09-12 审查 B-5 修复）
//!
//! ## 背景
//!
//! 原 `EXPECTED_TAURI_COMMAND_COUNT` 编译期断言为「常量自比」永真式，不构成守护
//! （见 2026-08-20 审查 T5-02）。该常量已被移除，但未建立替代机制，导致
//! 「34 个 Tauri commands」这一对外契约完全失去保护——误删或重复注册命令，
//! 编译与测试均不会发现，直到前端调用失败。
//!
//! ## 本测试的作用
//!
//! 通过静态扫描 `src/lib.rs` 的 `tauri::generate_handler![...]` 块，断言：
//! 1. 注册的命令总数为 `EXPECTED_COMMAND_COUNT`（误删/误加即失败）
//! 2. 每个命令模块的注册数量与已知分项一致（定位到具体模块的漂移）
//! 3. 注册项无重复（重复注册同一命令会被 Tauri 拒绝或产生歧义）
//!
//! ## 维护方式
//!
//! 新增/删除 Tauri command 时，**必须同步更新本文件的 `EXPECTED_*` 常量与
//! `AGENTS.md` 中的命令数量描述**。这是刻意的摩擦：让契约变更显式化。

#![cfg(test)]

/// 期望的 Tauri command 总数。
///
/// 与 `AGENTS.md` 中「34 Tauri commands」的描述保持一致。
/// 分项：config_cmd 11 + group_cmd 8 + hotkey_cmd 2 + recording_cmd 8 + system_cmd 5
const EXPECTED_COMMAND_COUNT: usize = 34;

/// 各命令模块的期望注册数量，用于精确定位漂移来源。
const EXPECTED_PER_MODULE: &[(&str, usize)] = &[
    ("config_cmd", 11),
    ("group_cmd", 8),
    ("hotkey_cmd", 2),
    ("recording_cmd", 8),
    ("system_cmd", 5),
];

/// 读取 `src/lib.rs` 源码全文。
fn read_lib_rs() -> String {
    // CARGO_MANIFEST_DIR 指向 src-tauri/
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/lib.rs");
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("无法读取 {}: {e}", path.display()))
}

/// 提取 `tauri::generate_handler![...]` 块内的全部 `commands::<module>::<func>` 完整路径。
///
/// `generate_handler!` 的每个条目形如 `commands::config_cmd::load_config`，
/// 因此这里提取 `module` 与 `func` 两段，用于精确的重复注册检测。
fn extract_command_paths(src: &str) -> Vec<(String, String)> {
    let start_marker = "generate_handler![";
    let start = src.find(start_marker).expect(
        "src/lib.rs 中未找到 tauri::generate_handler![。若已重命名该调用，请同步更新本测试。",
    ) + start_marker.len();

    let bytes = src.as_bytes();
    let mut depth = 1usize;
    let mut end = start;
    for (i, &b) in bytes[start..].iter().enumerate() {
        match b {
            b'[' => depth += 1,
            b']' => {
                depth -= 1;
                if depth == 0 {
                    end = start + i;
                    break;
                }
            }
            _ => {}
        }
    }
    assert!(
        depth == 0,
        "generate_handler![ 的方括号未闭合，源码可能被截断"
    );

    let block = &src[start..end];
    block
        .split("commands::")
        .skip(1)
        .filter_map(|seg| {
            let seg = seg.trim_start();
            let rest = seg.split(',').next().unwrap_or("").trim();
            let mut parts = rest.split("::");
            let module = parts.next()?.trim().to_string();
            let func = parts.next()?.trim().to_string();
            let ok =
                |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
            if ok(&module) && ok(&func) {
                Some((module, func))
            } else {
                None
            }
        })
        .collect()
}

#[test]
fn tauri_command_count_matches_expected() {
    let src = read_lib_rs();
    let cmds = extract_command_paths(&src);

    assert_eq!(
        cmds.len(),
        EXPECTED_COMMAND_COUNT,
        "Tauri command 总数与期望不符（实际 {}，期望 {}）。\n\
         若本次为有意的契约变更，请同步更新：\n\
         1. 本文件 EXPECTED_COMMAND_COUNT 与 EXPECTED_PER_MODULE\n\
         2. AGENTS.md 中的「34 Tauri commands」描述\n\
         实际注册清单：{:?}",
        cmds.len(),
        EXPECTED_COMMAND_COUNT,
        cmds
    );
}

#[test]
fn tauri_command_count_per_module_matches_expected() {
    let src = read_lib_rs();
    let cmds = extract_command_paths(&src);

    for (module, expected) in EXPECTED_PER_MODULE {
        let actual = cmds.iter().filter(|(m, _)| m == module).count();
        assert_eq!(
            actual, *expected,
            "模块 `{module}` 的 command 注册数不符（实际 {actual}，期望 {expected}）。"
        );
    }

    let known: Vec<&str> = EXPECTED_PER_MODULE.iter().map(|(m, _)| *m).collect();
    let unknown: Vec<&str> = cmds
        .iter()
        .map(|(m, _)| m.as_str())
        .filter(|m| !known.contains(m))
        .collect();
    assert!(
        unknown.is_empty(),
        "发现未登记的命令模块 {unknown:?}。新增命令模块时需同步更新 EXPECTED_PER_MODULE。"
    );
}

/// 扫描一个命令模块源码，返回 `(函数名, 参数列表)`。
///
/// 只认 `#[tauri::command]` 之后紧跟的 `pub [async] fn`，与
/// `extract_command_paths`（扫 lib.rs 的注册块）互补。
fn extract_command_params(src: &str) -> Vec<(String, Vec<String>)> {
    let mut out = Vec::new();
    let lines: Vec<&str> = src.lines().collect();
    let mut i = 0;
    while i < lines.len() {
        if lines[i].trim() != "#[tauri::command]" {
            i += 1;
            continue;
        }
        // 跳过属性与注释，找到 fn 行
        let mut j = i + 1;
        while j < lines.len() {
            let t = lines[j].trim();
            if t.starts_with("pub fn ") || t.starts_with("pub async fn ") {
                break;
            }
            if t.starts_with("#[") || t.starts_with("//") {
                j += 1;
                continue;
            }
            break;
        }
        if j >= lines.len() {
            break;
        }
        let fn_line = lines[j].trim();
        let name = fn_line
            .trim_start_matches("pub async fn ")
            .trim_start_matches("pub fn ")
            .split('(')
            .next()
            .unwrap_or("")
            .trim()
            .to_string();
        // 收集到参数列表右括号为止
        let mut depth = 0i32;
        let mut buf = String::new();
        let mut k = j;
        let mut done = false;
        while k < lines.len() {
            for ch in lines[k].chars() {
                match ch {
                    '(' => {
                        depth += 1;
                        continue;
                    }
                    ')' => {
                        depth -= 1;
                        if depth == 0 {
                            done = true;
                            break;
                        }
                    }
                    _ => {}
                }
                if depth >= 1 {
                    buf.push(ch);
                }
            }
            if done {
                break;
            }
            buf.push('\n');
            k += 1;
        }
        let params = buf
            .split(',')
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>();
        out.push((name, params));
        i = j + 1;
    }
    out
}

/// `#[tauri::command]` 的参数必须保持 owned（TD-045 批次 5 的豁免守卫）。
///
/// `clippy::needless_pass_by_value` 会建议把 `group_id: String` 改成 `&str`、
/// `group_ids: Vec<String>` 改成 `&[String]`。2026-09-17 **实测**核实：
///   · `state: tauri::State<...>` 必须按值 —— Tauri 按类型从 DI 容器提取；
///   · `&Config` / `&[String]` 在 serde 里**没有** `Deserialize` 实现，改了编译不过
///     （clippy 那句 "consider `&[String]`" 它自己也给不出，事实正是如此）；
///   · `&str` **技术上可行** —— Tauri 走 `&'de serde_json::Value` 的 Deserializer，
///     实测能借出 `&str`。所以这不是「运行时必炸」那类坑，而是**改对外 IPC 契约**，
///     而 E2E 覆盖不全（TD-016），一条 pedantic 告警不值得冒这个险。
///
/// 三个 command 模块因此整模块 `allow` 了该 lint —— allow 之后就没有编译期保护了，
/// 这条测试补上：静态扫描，命令参数除 `state` 外不得出现借用类型。
#[test]
fn tauri_command_args_stay_owned() {
    let files = [
        "config_cmd.rs",
        "group_cmd.rs",
        "hotkey_cmd.rs",
        "recording_cmd.rs",
        "system_cmd.rs",
    ];
    let mut checked = 0usize;
    let mut offenders = Vec::new();
    for file in files {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src/commands")
            .join(file);
        let src = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("无法读取 {}: {e}", path.display()));
        for (fn_name, params) in extract_command_params(&src) {
            for p in params {
                let (name, ty) = p.split_once(':').unwrap_or((&p, ""));
                let name = name.trim();
                let ty = ty.trim();
                if name == "state" {
                    continue;
                }
                if ty.starts_with('&') {
                    offenders.push(format!("{file}::{fn_name} 的参数 `{p}`"));
                }
                checked += 1;
            }
        }
    }
    assert!(
        checked > 0,
        "一个命令参数都没扫到 —— 解析器失效了，本条测试会退化成「空集通过」的永真式"
    );
    assert!(
        offenders.is_empty(),
        "Tauri 命令参数出现借用类型 —— 这是改对外 IPC 契约，须先确认 E2E 能验证它（TD-016）：\n  {}",
        offenders.join("\n  ")
    );
}

#[test]
fn tauri_commands_have_no_duplicate_registration() {
    let src = read_lib_rs();
    let cmds = extract_command_paths(&src);

    let mut seen = std::collections::HashSet::new();
    let mut dups = Vec::new();
    for (module, func) in &cmds {
        if !seen.insert((module.clone(), func.clone())) {
            dups.push(format!("{module}::{func}"));
        }
    }
    assert!(
        dups.is_empty(),
        "发现重复注册的 Tauri command：{dups:?}。同一命令注册两次会导致 handler 歧义。"
    );
}

/// TD-045 批次 8 的防复发守护：**不允许用「文件头 blanket allow」把文档契约
/// lint 整体关掉**。
///
/// 为什么需要这条：批次 8 的做法是「补完一个模块就删掉该模块头的 allow」，
/// 靠的是 G2b（`-D warnings`）。但 `#![allow(...)]` 是**源码级**的，编译期完全
/// 合法 —— 谁顺手加回一行，那整个模块的 `# Errors` 契约就瞬间失去保护，
/// 而 G2b 依然全绿（与批次 5 补 `tauri_command_args_stay_owned` 是同一个洞：
/// allow 之后编译期就没有信号了）。本测试补上这一层静态扫描。
///
/// 与 `tauri_command_args_stay_owned` 同思路：扫的是源码文本，所以要带
/// 「解析器不许静默失效」的锚点，否则扫不到东西时会退化成空集通过的永真式。
#[test]
fn no_blanket_missing_errors_doc_allow() {
    const BANNED: &[&str] = &["clippy::missing_errors_doc", "clippy::missing_panics_doc"];

    let src_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut scanned = 0usize;
    let mut offenders = Vec::new();

    let mut stack = vec![src_root.clone()];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).unwrap_or_else(|e| panic!("无法读取 {dir:?}: {e}"))
        {
            let path = entry.expect("目录项读取失败").path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            if path.extension().and_then(|s| s.to_str()) != Some("rs") {
                continue;
            }
            let src = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("无法读取 {}: {e}", path.display()));
            scanned += 1;
            for banned in BANNED {
                if src.contains(&format!("#![allow({banned})]")) {
                    offenders.push(format!(
                        "{} 里有 blanket `#![allow({banned})]`",
                        path.display()
                    ));
                }
            }
        }
    }

    assert!(
        scanned >= 10,
        "只扫到 {scanned} 个 .rs 文件 —— 目录遍历失效了，本条测试会退化成永真式"
    );
    assert!(
        offenders.is_empty(),
        "不该用 blanket allow 关掉文档契约 lint（TD-045 批次 8 已全部补完，\
         缺哪一条就补哪一条，不要整模块关掉）：\n  {}",
        offenders.join("\n  ")
    );
}
