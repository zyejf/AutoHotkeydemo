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
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("无法读取 {}: {e}", path.display()))
}

/// 提取 `tauri::generate_handler![...]` 块内的全部 `commands::<module>::<func>` 完整路径。
///
/// `generate_handler!` 的每个条目形如 `commands::config_cmd::load_config`，
/// 因此这里提取 `module` 与 `func` 两段，用于精确的重复注册检测。
fn extract_command_paths(src: &str) -> Vec<(String, String)> {
    let start_marker = "generate_handler![";
    let start = src
        .find(start_marker)
        .expect("src/lib.rs 中未找到 tauri::generate_handler![。若已重命名该调用，请同步更新本测试。")
        + start_marker.len();

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
    assert!(depth == 0, "generate_handler![ 的方括号未闭合，源码可能被截断");

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
            let ok = |s: &str| !s.is_empty()
                && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
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
