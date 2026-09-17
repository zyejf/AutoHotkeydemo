//! TD-045 批次 9 的防复发守护：`doc_markdown` 不许再被 blanket 关掉。
//!
//! ## 为什么需要这条
//!
//! 批次 9 收干 `src-tauri` 全部 213 项 `clippy::doc_markdown`（实测数，台账早先记的
//! 211 是批次 8 补 `# Errors` 之前的旧口径），做法是「按模块补反引号，补完删 allow」。
//! 但 `#![allow(...)]` 是**源码级**的、编译期完全合法 —— 谁顺手加回一行，整个模块
//! 的文档排版就瞬间失去保护，而既有闸门 G2b（`-D warnings`）**依然全绿**。
//! 这与批次 5 补 `tauri_command_args_stay_owned`、批次 8 补
//! `no_blanket_missing_errors_doc_allow` 是同一个洞：allow 之后编译期就没信号了，
//! 只能靠静态扫描补。
//!
//! ## 查什么
//!
//! 两个层面，任一命中即失败：
//! 1. 任何 `.rs` 里的**模块级 / crate 级** `#![allow(...)]` 含 `clippy::doc_markdown`；
//! 2. `Cargo.toml` 的 `[lints.clippy]` 段里再出现 `doc_markdown = ...`。
//!
//! ⚠️ **只禁 `#![allow(`（带感叹号，作用于整个模块/crate），不禁 `#[allow(`**
//! —— 后者是「就地 allow + 代码内写理由」的合法用法，项目规矩里明确留了这个口子
//! （批次 6 的 `cast_*` 就有 3 处这样的豁免）。把就地 allow 也禁掉等于逼人写假文档，
//! 那是比 lint 告警更糟的结果。
//!
//! ## 防永真式
//!
//! 扫的是源码文本，所以必须带锚点：扫到的 `.rs` 少于 10 个、或 `Cargo.toml` 里
//! 找不到 `[lints.clippy]` 段，都判定为「遍历/解析失效」直接失败 —— 否则扫不到东西
//! 时会退化成「空集通过」的永真式，这条测试就白写了。

#![cfg(test)]

/// 只禁模块级 / crate 级 blanket allow 的前缀。
const BLANKET_PREFIX: &str = "#![allow(";

/// 被守护的 lint 名。
const GUARDED_LINT: &str = "clippy::doc_markdown";

/// 遍历 `src/` 下全部 `.rs`，返回 (扫到的文件数, 违规清单)。
fn scan_rs_files() -> (usize, Vec<String>) {
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
            for (i, line) in src.lines().enumerate() {
                let t = line.trim_start();
                if t.starts_with(BLANKET_PREFIX) && t.contains(GUARDED_LINT) {
                    offenders.push(format!(
                        "{}:{} 有模块级 blanket allow（{}）—— 补反引号，别整模块关掉",
                        path.display(),
                        i + 1,
                        t
                    ));
                }
            }
        }
    }
    (scanned, offenders)
}

/// 取 `Cargo.toml` 里 `[lints.clippy]` 段的正文（不含注释），找不到返回 `None`。
fn cargo_lints_clippy_section() -> Option<String> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let src = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("无法读取 {}: {e}", path.display()));

    let mut out = String::new();
    let mut in_section = false;
    for line in src.lines() {
        let t = line.trim();
        if t.starts_with('[') {
            in_section = t == "[lints.clippy]";
            continue;
        }
        if !in_section {
            continue;
        }
        // 去行注释（本 Cargo.toml 里没有带 `#` 的字符串值，简单截断即可）
        let code = match line.find('#') {
            Some(pos) => &line[..pos],
            None => line,
        };
        out.push_str(code);
        out.push('\n');
    }
    if out.trim().is_empty() {
        None
    } else {
        Some(out)
    }
}

/// 第一层：`src/` 下不许有模块级 `#![allow(clippy::doc_markdown)]`。
#[test]
fn no_blanket_doc_markdown_allow_in_source() {
    let (scanned, offenders) = scan_rs_files();

    assert!(
        scanned >= 10,
        "只扫到 {scanned} 个 .rs 文件 —— 目录遍历失效了，本条测试会退化成永真式"
    );
    assert!(
        offenders.is_empty(),
        "不该用 blanket allow 关掉 `clippy::doc_markdown`（TD-045 批次 9 已收干 213 项，\
         缺哪一处就补哪一处反引号，不要整模块关掉）：\n  {}",
        offenders.join("\n  ")
    );
}

/// 第二层：`Cargo.toml` 的 `[lints.clippy]` 里不许再有 `doc_markdown` 条目。
///
/// 与上一层互补：源码里没有 blanket allow 不代表 lint 是开着的 —— 只要 `Cargo.toml`
/// 里还躺着 `doc_markdown = "allow"`，全 crate 一个告警都不会报，G2b 照样全绿。
/// 这一层守的是「lint 本身被开着」这件事。
#[test]
fn cargo_toml_does_not_allow_doc_markdown() {
    let section = cargo_lints_clippy_section().expect(
        "Cargo.toml 里找不到 [lints.clippy] 段（或该段为空）—— 解析器失效了，\
         本条测试会退化成永真式。若确有意为之，请同步修改本测试。",
    );

    let offenders: Vec<String> = section
        .lines()
        .map(str::trim)
        .filter(|l| l.starts_with("doc_markdown") && l.contains('='))
        .map(|l| format!("[lints.clippy] 里仍有 `{l}`"))
        .collect();

    assert!(
        offenders.is_empty(),
        "不该在 Cargo.toml 里全局关掉 `clippy::doc_markdown`（TD-045 批次 9 已收干 213 项）：\n  {}",
        offenders.join("\n  ")
    );
}
