use std::fs;
use tauri::Manager;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

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
