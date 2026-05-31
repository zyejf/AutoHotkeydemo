pub fn format_timestamp() -> String {
    chrono::Local::now().format("%Y%m%d_%H%M%S").to_string()
}

pub fn format_datetime() -> String {
    chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_timestamp_format() {
        let ts = format_timestamp();
        assert_eq!(ts.len(), 15, "格式应为 YYYYMMDD_HHmmss");
        assert_eq!(ts.chars().nth(8), Some('_'));
        let date_part = &ts[0..8];
        let time_part = &ts[9..15];
        for c in date_part.chars() {
            assert!(c.is_ascii_digit());
        }
        for c in time_part.chars() {
            assert!(c.is_ascii_digit());
        }
    }

    #[test]
    fn test_format_datetime_format() {
        let dt = format_datetime();
        assert_eq!(dt.len(), 19, "格式应为 YYYY-MM-DD HH:mm:ss");
        assert_eq!(&dt[4..5], "-");
        assert_eq!(&dt[7..8], "-");
        assert_eq!(&dt[10..11], " ");
        assert_eq!(&dt[13..14], ":");
        assert_eq!(&dt[16..17], ":");
    }

    #[test]
    fn test_format_timestamp_uses_local_time() {
        let ts = format_timestamp();
        let now = chrono::Local::now();
        let expected_prefix = now.format("%Y%m%d_").to_string();
        assert!(
            ts.starts_with(&expected_prefix),
            "时间戳应使用本地时间: got {ts}, expected prefix {expected_prefix}"
        );
    }

    #[test]
    fn test_format_datetime_uses_local_time() {
        let dt = format_datetime();
        let now = chrono::Local::now();
        let expected_prefix = now.format("%Y-%m-%d ").to_string();
        assert!(
            dt.starts_with(&expected_prefix),
            "日期时间应使用本地时间: got {dt}, expected prefix {expected_prefix}"
        );
    }
}
