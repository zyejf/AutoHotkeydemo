use std::fs;
use tauri::Manager;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

/// 初始化日志系统：控制台（带 ANSI）+ 按天滚动的文件（`asd.log`，保留最近 7 份）。
///
/// 日志级别默认 `info`，可用环境变量 `RUST_LOG` 覆盖。
///
/// # Errors
///
/// 以下任一步失败都会返回错误，且此时**日志系统未就绪** —— 调用方需要自己决定
/// 是「没日志也继续跑」还是中止启动（本仓库目前选择记 stderr 后继续）：
///
/// - 取不到应用数据目录（`app.path().app_data_dir()`）
/// - 数据目录创建失败（权限不足 / 路径被占用）
/// - 滚动文件 appender 构建失败
/// - tracing subscriber 初始化失败（典型是**已被初始化过** —— 进程内只允许一次）
pub fn init(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let app_data_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| -> Box<dyn std::error::Error> {
            format!("获取应用数据目录失败: {e}").into()
        })?;

    fs::create_dir_all(&app_data_dir)?;

    let file_appender = tracing_appender::rolling::RollingFileAppender::builder()
        .rotation(tracing_appender::rolling::Rotation::DAILY)
        .filename_prefix("asd")
        .filename_suffix("log")
        .max_log_files(7)
        .build(&app_data_dir)
        .map_err(|e| -> Box<dyn std::error::Error> { e.into() })?;

    let env_filter = env_filter_from(std::env::var("RUST_LOG").ok().as_deref());

    let fmt_layer = fmt::layer()
        .with_target(true)
        .with_thread_ids(false)
        .with_file(false)
        .with_line_number(false);

    let file_layer = fmt::layer()
        .with_writer(file_appender)
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .with_ansi(false);

    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt_layer)
        .with(file_layer)
        .try_init()?;

    tracing::info!("ASD Tauri 日志系统初始化完成");

    Ok(())
}

/// 按给定 spec 构造 `EnvFilter`：spec 有效则用之，缺失或非法一律回落到 `info`。
///
/// ⚠️ 之所以抽成**纯函数**（不自己读环境变量）：`init()` 依赖真实的 `tauri::App`，
/// 在单测里构造不了，本文件因此长期 0% 覆盖。抽出来后，这条契约
/// （「默认 `info`，可用 `RUST_LOG` 覆盖」）成了本文件唯一可测的部分 —— 而它
/// 恰恰是最容易被改坏的部分：改坏了日志会静默变多或变少，没有任何信号。
///
/// 放在文件末尾而不是 `init()` 之前，是为了不和 `init()` 的文档块首尾相接
/// （两段 `///` 会被合并成同一份文档，让 `init()` 丢掉 `# Errors`）。
fn env_filter_from(log_spec: Option<&str>) -> EnvFilter {
    match log_spec {
        Some(spec) => EnvFilter::try_new(spec).unwrap_or_else(|_| EnvFilter::new("info")),
        None => EnvFilter::new("info"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 契约一：不指定时默认 `info`（`init()` 文档注释里写死的承诺）。
    #[test]
    fn env_filter_defaults_to_info_when_spec_missing() {
        let f = env_filter_from(None);
        assert_eq!(f.to_string(), "info", "未指定时默认级别必须是 info");
    }

    /// 契约二：显式指定时生效（`RUST_LOG=debug` 这类用法）。
    #[test]
    fn env_filter_uses_explicit_spec() {
        let f = env_filter_from(Some("debug"));
        assert!(
            f.to_string().contains("debug"),
            "显式指定 `debug` 时应生效，实际得到: {f}"
        );
    }

    /// 契约三：非法 spec 必须**回落**到 `info`，而不是让日志整体静默失效 ——
    /// 这是最容易被改坏的一条：若把 `unwrap_or_else` 改成 `unwrap()`，
    /// 非法 `RUST_LOG` 会直接 panic 在启动阶段。
    #[test]
    fn env_filter_falls_back_to_info_on_invalid_spec() {
        let f = env_filter_from(Some("invalid=not_a_real_level"));
        assert_eq!(
            f.to_string(),
            "info",
            "非法 spec 必须回落到 `info`，而不是让日志静默失效或 panic"
        );
    }
}
