#[derive(Debug, thiserror::Error)]
pub enum IpcError {
    #[error("连接已关闭")]
    ConnectionClosed,
    #[error("消息超过大小上限: {0} > {1}")]
    MessageTooLarge(usize, usize),
    #[error("收到空行")]
    EmptyMessage,
    #[error("JSON 解析错误: {0}")]
    JsonError(String),
    #[error("IO 错误: {0}")]
    IoError(String),
    #[error("等待响应超时")]
    Timeout,
    #[error("发送消息超时")]
    SendTimeout,
    #[error("通道已关闭")]
    ChannelClosed,
    #[error("管道断裂: {0}")]
    PipeBroken(String),
    #[error("命名管道错误: {0}")]
    NameError(String),
    #[error("IPC 认证失败: {0}")]
    AuthFailed(String),
}

impl From<std::io::Error> for IpcError {
    fn from(e: std::io::Error) -> Self {
        // 优先使用 ErrorKind 判断，比字符串匹配更可靠
        if e.kind() == std::io::ErrorKind::BrokenPipe {
            return IpcError::PipeBroken(e.to_string());
        }
        // 字符串匹配作为后备，覆盖非标准 BrokenPipe 错误消息
        let msg = e.to_string();
        if msg.contains("broken pipe")
            || msg.contains("Broken pipe")
            || msg.contains("远程端已关闭")
            || msg.contains("No process")
        {
            IpcError::PipeBroken(msg)
        } else {
            IpcError::IoError(msg)
        }
    }
}

impl From<serde_json::Error> for IpcError {
    fn from(e: serde_json::Error) -> Self {
        IpcError::JsonError(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ipc_error_from_broken_pipe() {
        let err = std::io::Error::new(std::io::ErrorKind::BrokenPipe, "broken pipe");
        let ipc_err = IpcError::from(err);
        assert!(matches!(ipc_err, IpcError::PipeBroken(_)));
    }

    #[test]
    fn test_ipc_error_from_other_io() {
        let err = std::io::Error::other("some error");
        let ipc_err = IpcError::from(err);
        assert!(matches!(ipc_err, IpcError::IoError(_)));
    }

    #[test]
    fn test_ipc_error_from_json() {
        let json_str = "{invalid}";
        let result: Result<serde_json::Value, _> = serde_json::from_str(json_str);
        if let Err(e) = result {
            let ipc_err = IpcError::from(e);
            assert!(matches!(ipc_err, IpcError::JsonError(_)));
        }
    }

    #[test]
    fn test_ipc_error_display_messages() {
        assert_eq!(format!("{}", IpcError::ConnectionClosed), "连接已关闭");
        assert_eq!(format!("{}", IpcError::EmptyMessage), "收到空行");
        assert_eq!(format!("{}", IpcError::Timeout), "等待响应超时");
        assert_eq!(format!("{}", IpcError::ChannelClosed), "通道已关闭");

        let size_err = IpcError::MessageTooLarge(100, 64);
        assert!(format!("{size_err}").contains("100"));

        let json_err = IpcError::JsonError("parse error".to_string());
        assert!(format!("{json_err}").contains("parse error"));
    }

    #[test]
    fn test_ipc_error_auth_failed() {
        let err = IpcError::AuthFailed("token 不匹配".to_string());
        let msg = format!("{err}");
        assert!(
            msg.contains("认证失败"),
            "AuthFailed display should contain '认证失败': {msg}"
        );
        assert!(
            msg.contains("token 不匹配"),
            "AuthFailed display should contain reason: {msg}"
        );
    }
}
