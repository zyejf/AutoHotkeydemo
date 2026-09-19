//! TD-089：AHK 执行器路径诊断快照的单元测试。
//!
//! 守护对象：[`crate::format_resource_snapshot`]。
//!
//! # 为什么诊断信息本身也要有测试
//!
//! 本项目的贯穿性失效模式是「东西写了，但没接上」（生产就绪度报告 §四列了 11 处）。
//! 诊断代码同样会犯这个病：快照函数写好了，但一旦有人把它改成空串 / 少拼一半，
//! **编译照样过、业务测试照样绿** —— 等到真出故障需要靠它排障时，它已经坏了。
//! 所以它必须有自己的测试，且测试必须**断言输出内容**（而不是只断言"能跑通"），
//! 这样把输出改成空串时测试会红并点名。

use crate::format_resource_snapshot;
use std::fs;
use std::path::{Path, PathBuf};

/// 建一个本用例独占的临时目录（不依赖 `tempfile`，避免为测试引入新依赖）。
///
/// 名字里带进程号 + 自增序号，保证并行跑用例时不撞车。
fn unique_temp_dir(tag: &str) -> PathBuf {
    use std::sync::atomic::{AtomicU32, Ordering};
    static SEQ: AtomicU32 = AtomicU32::new(0);
    let n = SEQ.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!(
        "asd_td089_{tag}_{}_{n}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).expect("建临时目录失败");
    dir
}

/// 目录存在、文件也存在 ⇒ 两级都报存在，且文件出现在目录列举里。
#[test]
fn snapshot_reports_both_levels_when_dir_and_file_exist() {
    let dir = unique_temp_dir("both_exist");
    let file = dir.join("AutoHotkey64.exe");
    fs::write(&file, b"stub").expect("写桩文件失败");

    let s = format_resource_snapshot(Some(&dir), &file);

    assert!(s.contains("存在=true"), "目录级应报存在=true，实际: {s}");
    assert!(
        s.contains("AutoHotkey64.exe"),
        "快照应点名目标文件，实际: {s}"
    );
    // 出现两次：一次是「资源目录=…」不含文件名，另一次是目录列举 + 目标文件。
    // 这里只断言列举里**有**它，避免对具体次数过度耦合。
    assert!(
        s.contains("目录共 1 项"),
        "目录列举应统计到 1 项，实际: {s}"
    );
    let _ = fs::remove_dir_all(&dir);
}

/// **核心用例**：目录存在但文件缺失 ⇒ 必须能一眼看出「缺的是文件，不是目录」。
///
/// 这正是 TD-089 要解决的伪装：`os error 3` 与 `os error 2` 在日志里长得像，
/// 只有两级快照能区分。
#[test]
fn snapshot_distinguishes_missing_file_from_missing_dir() {
    let dir = unique_temp_dir("file_missing");
    let file = dir.join("AutoHotkey64.exe"); // 故意不创建

    let s = format_resource_snapshot(Some(&dir), &file);

    assert!(
        s.contains("存在=true"),
        "目录应报存在=true（缺的是文件），实际: {s}"
    );
    assert!(
        s.contains("存在=false"),
        "文件应报存在=false，实际: {s}"
    );
    assert!(
        s.contains("目录共 0 项"),
        "空目录应统计为 0 项，实际: {s}"
    );
    let _ = fs::remove_dir_all(&dir);
}

/// 目录本身不存在 ⇒ 目录级报不存在，且**不做**目录列举（列举必然失败，无意义）。
#[test]
fn snapshot_reports_missing_dir_and_skips_listing() {
    let base = unique_temp_dir("dir_missing");
    let dir = base.join("ahk_executor"); // 故意不创建
    let file = dir.join("AutoHotkey64.exe");

    let s = format_resource_snapshot(Some(&dir), &file);

    assert!(s.contains("存在=false"), "目录应报不存在，实际: {s}");
    assert!(
        !s.contains("目录共"),
        "目录不存在时不应尝试列举，实际: {s}"
    );
    let _ = fs::remove_dir_all(&base);
}

/// 父目录无法推导 ⇒ 只输出文件一级，不臆造目录信息。
///
/// ⚠️ 本用例**实测推翻了一个想当然的假设**：`Path::new("AutoHotkey64.exe").parent()`
/// 返回的不是 `None`，而是 `Some("")`（裸文件名的父目录是空路径）。初版实现只判断
/// `None`，于是输出了「资源目录= 存在=false」—— 既不表示目录不存在，也不指向任何
/// 东西，是比不输出更糟的误导。现已改为 `None` **与空路径**一并按「无法推导」处理。
#[test]
fn snapshot_handles_unknown_parent_dir() {
    let file = Path::new("AutoHotkey64.exe"); // 纯文件名

    let s = format_resource_snapshot(file.parent(), file);

    assert!(
        s.contains("父目录无法推导"),
        "应显式说明父目录无法推导，实际: {s}"
    );
    assert!(s.contains("目标文件=AutoHotkey64.exe"), "应点名目标文件，实际: {s}");
}

/// 列举必须**有界**：超过上限只列出前 N 项，并明确标注已截断。
#[test]
fn snapshot_listing_is_bounded_and_marks_truncation() {
    let dir = unique_temp_dir("bounded");
    for i in 0..25 {
        fs::write(dir.join(format!("entry_{i:02}.txt")), b"x").expect("写桩失败");
    }

    let s = format_resource_snapshot(Some(&dir), &dir.join("AutoHotkey64.exe"));

    assert!(s.contains("目录共 25 项"), "总数应如实报 25，实际: {s}");
    assert!(s.contains("前 20 项"), "应只列前 20 项，实际: {s}");
    assert!(s.contains("已截断"), "超过上限必须标注截断，实际: {s}");
    assert!(
        !s.contains("entry_24.txt"),
        "第 21 项之后不应出现在列举里，实际: {s}"
    );
    let _ = fs::remove_dir_all(&dir);
}

/// 快照不得为空 —— 这是**变异验证的锚点**。
///
/// 把 `format_resource_snapshot` 的返回改成 `String::new()`，本用例必须失败；
/// 上面几条则保证它不只是"非空"，而是真的带上了该有的信息。
#[test]
fn snapshot_is_never_empty() {
    let dir = unique_temp_dir("never_empty");
    let file = dir.join("AutoHotkey64.exe");
    fs::write(&file, b"stub").expect("写桩文件失败");

    let s = format_resource_snapshot(Some(&dir), &file);

    assert!(
        !s.trim().is_empty(),
        "快照不得为空串 —— 若这条失败，说明 format_resource_snapshot 被改成不产出信息了"
    );
    assert!(
        s.contains("[AHK 资源快照]"),
        "快照应带可检索的前缀，实际: {s}"
    );
    let _ = fs::remove_dir_all(&dir);
}
