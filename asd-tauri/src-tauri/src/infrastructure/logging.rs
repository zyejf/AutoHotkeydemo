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

    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

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
