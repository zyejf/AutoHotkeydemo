//! TD-050 守护：**注释里的反引号不许把中文包进去**。
//!
//! ## 背景
//!
//! `clippy::doc_markdown` 不认 CJK 词边界（见台账 TD-045 批次 9）：它把「中文 + ASCII
//! 标识符」当成一个词，`cargo clippy --fix` 会把整段中文一起套进反引号，例如
//! 「用 `try_send`，通道满时丢弃而非 await 阻塞」被改成反引号跨过整段中文的写法 —— 渲染
//! 成代码的中文本身就是误导，**比不加更糟**。历史上已经有若干处这类损坏被提交进来了
//! （TD-050 的 A 类 5 处，本次修复）。
//!
//! ## 判据（`judge`）
//!
//! 一个反引号 span 只有在**同时**满足下面几条时才被放过，任一命中即 FAIL：
//!
//! 0. 先把 span 里的 `"..."` 字面量区域与 `<...>` 占位符区域**遮蔽**掉 —— 这两种形态里的
//!    中文是数据不是散文（`` `"无效的文件路径"` ``、`` `backup_<时间戳>.json` `` 都是正确写法）。
//! 1. 遮蔽后不含 CJK 表意文字 → 放过。
//! 2. 某个 CJK 连续段与 ASCII 标识符字符（`[A-Za-z0-9_]`）**之间没有空白**（中间隔着
//!    中英文标点也算） → FAIL。这是 A 类 5 处的共同特征：**反引号边界落在中文散文中间**。
//! 3. span 被 `(`/`<`/`[` 与 `)`/`>`/`]` **整体包住** → 放过（元组/参数/占位描述，
//!    例如 `` `(函数名, 参数列表)` ``）。
//! 4. 遮蔽后仍有 **≥2 个** CJK 连续段 → FAIL（中文散文把 ASCII 标识符夹在中间）。
//! 5. span 里**一个 ASCII 标识符字符都没有** → FAIL（整句中文被当成代码）。
//!
//! ⚠️ **不许用「加豁免」的方式让误报消失**：如果下面 `judgement_accepts_known_good_spans`
//! 挂了，说明判据太粗，改 `judge`，不要在扫描器里给具体文件/行开后门。
//!
//! ## 防永真式
//!
//! 扫的是源码文本，所以带两个锚点：① 从 `CARGO_MANIFEST_DIR` 向上找不到带 `[workspace]`
//! 的 `Cargo.toml` → 直接 panic；② 扫到的 `.rs` 少于 10 个 → 判定目录遍历失效并 FAIL。
//! 否则扫不到东西时会退化成「空集通过」。
//!
//! ## ⚠️ 维护注意
//!
//! 本文件的**注释里不许写损坏样本的原文** —— 它会被本扫描器自己扫出来。所有样本一律
//! 放在下面的 `A_CLASS_SAMPLES` / `KNOWN_GOOD_SPANS` 常量里（常量不是注释，不参与扫描）。

/// CJK 表意文字的码点区间（CJK 统一表意文字 + 扩展 A + 兼容表意文字）。
const IDEOGRAPH_RANGES: &[(u32, u32)] = &[(0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF)];

/// TD-050 A 类 5 处损坏的**原文**（已在本轮修复，留作判据的回归样本）。
///
/// 这 5 条必须被 `judge` 判为损坏；若哪天它们被放过了，说明判据被人改松了。
const A_CLASS_SAMPLES: &[&str] = &[
    "config_state）和",
    "Ok(Some(占用的 group_id))",
    "引入测试工具的测试文件（backup_service_tests",
    "recording_service_tests）。新增测试应直接使用",
    "此测试验证回滚逻辑正确执行，recording_mode",
];

/// TD-050 B 类 + 字符串字面量形态：这些是**刻意保留**的正确写法。
///
/// 它们必须被 `judge` 放过；若被报出来，说明判据太粗（改判据，不许加豁免）。
const KNOWN_GOOD_SPANS: &[&str] = &[
    // B 类：任务清单条目名的整体引用，中文是条目名的一部分
    "emergency_release 在无效状态下失败",
    "toggle_hold_mode 无效参数失败",
    "get_system_status 状态查询",
    // B 类：代码表达式 / 元组字段描述
    "(seq, 响应接收端)",
    ".expect(\"Tauri 应用启动失败\")",
    "(函数名, 参数列表)",
    // B 类：文件名模板，中文是占位名的一部分
    ".tmp_<name>_<pid>_<纳秒>",
    "backup_<时间戳>.json",
    // 字符串字面量里的中文是数据，不是散文
    "\"无效的文件路径\"",
    "AppError::Validation(\"无效的文件路径\")",
];

fn is_ideograph(c: char) -> bool {
    let o = u32::from(c);
    IDEOGRAPH_RANGES
        .iter()
        .any(|&(lo, hi)| (lo..=hi).contains(&o))
}

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// 把 `"..."` 与 `<...>` 两个端点之间的区域替换成空格，返回新的字符串。
fn mask_regions(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = chars.clone();
    let mut i = 0usize;
    while i < chars.len() {
        let closer = match chars[i] {
            '"' => '"',
            '<' => '>',
            _ => {
                i += 1;
                continue;
            }
        };
        let rest = &chars[i + 1..];
        match rest.iter().position(|&c| c == closer) {
            Some(offset) => {
                let end = i + 1 + offset;
                for slot in out.iter_mut().take(end + 1).skip(i) {
                    *slot = ' ';
                }
                i = end + 1;
            }
            None => i += 1,
        }
    }
    out.into_iter().collect()
}

/// 返回 CJK 表意文字的极大连续段，元素为 `[start, end)` 的字符下标。
fn ideograph_runs(s: &str) -> Vec<(usize, usize)> {
    let chars: Vec<char> = s.chars().collect();
    let mut runs = Vec::new();
    let mut i = 0usize;
    while i < chars.len() {
        if !is_ideograph(chars[i]) {
            i += 1;
            continue;
        }
        let mut j = i;
        while j < chars.len() && is_ideograph(chars[j]) {
            j += 1;
        }
        runs.push((i, j));
        i = j;
    }
    runs
}

/// 从 `idx` 往左走：先遇到空白 → `false`（有分隔）；先遇到标识符字符 → `true`（粘连）。
fn glued_left(chars: &[char], idx: usize) -> bool {
    let mut i = idx;
    while i > 0 {
        i -= 1;
        let c = chars[i];
        if c.is_whitespace() {
            return false;
        }
        if is_ident_char(c) {
            return true;
        }
    }
    false
}

/// 从 `idx` 往右走，语义同 [`glued_left`]。
fn glued_right(chars: &[char], idx: usize) -> bool {
    let mut i = idx + 1;
    while i < chars.len() {
        let c = chars[i];
        if c.is_whitespace() {
            return false;
        }
        if is_ident_char(c) {
            return true;
        }
        i += 1;
    }
    false
}

/// 判定一个反引号 span 是否损坏；返回 `Some(_)` 表示损坏，`_` 里是给人看的理由文本。
fn judge(span: &str) -> Option<String> {
    let masked = mask_regions(span);
    let masked_chars: Vec<char> = masked.chars().collect();
    let runs = ideograph_runs(&masked);
    if runs.is_empty() {
        return None;
    }

    for &(start, end) in &runs {
        if glued_left(&masked_chars, start) || glued_right(&masked_chars, end - 1) {
            let sample: String = span.chars().skip(start).take(end - start).collect();
            return Some(format!(
                "反引号边界落在中文中间（与 ASCII 标识符粘连）：{sample:?}"
            ));
        }
    }

    let span_chars: Vec<char> = span.chars().collect();
    let bracketed = matches!(span_chars.first(), Some('(' | '<' | '['))
        && matches!(span_chars.last(), Some(')' | '>' | ']'));
    if bracketed {
        return None;
    }
    if runs.len() >= 2 {
        return Some(format!("中文散文把 ASCII 标识符夹在中间：{span:?}"));
    }
    if !span.chars().any(is_ident_char) {
        return Some(format!("整句中文被当成代码包进反引号：{span:?}"));
    }
    None
}

/// 取出一行里所有反引号包裹的内容（按反引号配对，取奇数段）。
fn backtick_spans(line: &str) -> Vec<String> {
    line.split('`')
        .enumerate()
        .filter_map(|(i, part)| {
            if i % 2 == 1 {
                Some(part.to_string())
            } else {
                None
            }
        })
        .collect()
}

/// 从 `CARGO_MANIFEST_DIR` 向上找到带 `[workspace]` 的目录。
fn workspace_root() -> std::path::PathBuf {
    let mut dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf();
    loop {
        let candidate = dir.join("Cargo.toml");
        if let Ok(text) = std::fs::read_to_string(&candidate) {
            if text.lines().any(|l| l.trim() == "[workspace]") {
                return dir;
            }
        }
        if !dir.pop() {
            break;
        }
    }
    panic!(
        "从 CARGO_MANIFEST_DIR 向上找不到带 [workspace] 的 Cargo.toml —— \
         解析器失效了，本条测试会退化成永真式"
    );
}

/// 遍历工作区全部 `.rs`（跳过 `target/`），返回 (扫到的文件数, 违规清单)。
fn scan_workspace() -> (usize, Vec<String>) {
    let root = workspace_root();
    let mut scanned = 0usize;
    let mut offenders = Vec::new();
    let mut stack = vec![root];

    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir)
            .unwrap_or_else(|e| panic!("无法读取 {}: {e}", dir.display()))
            .flatten()
        {
            let path = entry.path();
            if path.is_dir() {
                if path.file_name().and_then(|n| n.to_str()) == Some("target") {
                    continue;
                }
                stack.push(path);
                continue;
            }
            if path.extension().and_then(|s| s.to_str()) != Some("rs") {
                continue;
            }
            let text = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("无法读取 {}: {e}", path.display()));
            scanned += 1;
            for (idx, line) in text.lines().enumerate() {
                if !line.trim_start().starts_with("//") {
                    continue;
                }
                for span in backtick_spans(line) {
                    if let Some(why) = judge(&span) {
                        let loc = format!("{}:{}", path.display(), idx + 1);
                        let text = line.trim();
                        offenders.push(format!("{loc}  {why}\n        | {text}"));
                    }
                }
            }
        }
    }
    (scanned, offenders)
}

#[test]
fn no_backtick_swallows_chinese() {
    let (scanned, offenders) = scan_workspace();

    assert!(
        scanned >= 10,
        "只扫到 {scanned} 个 .rs 文件 —— 目录遍历失效了，本条测试会退化成永真式"
    );
    assert!(
        offenders.is_empty(),
        "注释里的反引号把中文包进去了（TD-050 已修 A 类 5 处，B 类 10 处是刻意保留的正确写法）：\n  {}",
        offenders.join("\n  ")
    );
}

/// 判据不许被改松：A 类损坏样本必须全部被判为损坏。
#[test]
fn judgement_flags_known_corruption() {
    let missed: Vec<&str> = A_CLASS_SAMPLES
        .iter()
        .copied()
        .filter(|s| judge(s).is_none())
        .collect();
    assert!(
        missed.is_empty(),
        "判据退化了 —— 这些损坏样本竟然被放过：{missed:?}。\
         请修 `judge`，不要放宽阈值。"
    );
}

/// 判据不许过粗：B 类与字符串字面量形态必须全部被放过。
///
/// 挂了就改 `judge`，**不许**在扫描器里给具体文件/行加豁免。
#[test]
fn judgement_accepts_known_good_spans() {
    let flagged: Vec<&str> = KNOWN_GOOD_SPANS
        .iter()
        .copied()
        .filter(|s| judge(s).is_some())
        .collect();
    assert!(
        flagged.is_empty(),
        "判据过粗 —— 这些刻意保留的正确写法被误报了：{flagged:?}。\
         改判据，不要加豁免。"
    );
}
