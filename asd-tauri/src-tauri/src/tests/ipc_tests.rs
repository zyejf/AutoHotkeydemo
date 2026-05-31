use crate::infrastructure::ipc::*;
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use interprocess::local_socket::traits::tokio::{Listener as ListenerTrait, Stream as StreamTrait};
use std::sync::Arc;
use std::time::{Duration, Instant};

fn unique_pipe_name(tag: &str) -> String {
    let id = std::process::id();
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("asd_ipc_poc_{}_{}_{}", tag, id, ts % 100000)
}

#[tokio::test]
async fn test_ping_pong() {
    let pipe_name = unique_pipe_name("ping");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (recv, send) = conn.split();
        let mut reader = tokio::io::BufReader::new(recv);
        let mut writer = send;

        let mut line = String::new();
        tokio::io::AsyncBufReadExt::read_line(&mut reader, &mut line)
            .await
            .expect("读取失败");
        let msg: IpcMessage = serde_json::from_str(line.trim()).expect("解析失败");
        assert_eq!(msg.r#type, "ping");

        let pong = IpcMessage::pong(msg.seq + 100, msg.seq);
        let mut json = serde_json::to_string(&pong).unwrap();
        json.push('\n');
        tokio::io::AsyncWriteExt::write_all(&mut writer, json.as_bytes())
            .await
            .expect("发送 pong 失败");
        tokio::io::AsyncWriteExt::flush(&mut writer)
            .await
            .expect("flush 失败");
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("Client 连接失败");

    let seq = client.next_seq();
    let ping = IpcMessage::ping(seq);
    client.send(&ping).await.expect("Client 发送 ping 失败");

    let pong = client.recv().await.expect("Client 接收 pong 失败");
    assert_eq!(pong.r#type, "pong");
    assert_eq!(pong.ack_seq, Some(seq));

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
}

#[tokio::test]
async fn test_execute_result() {
    let pipe_name = unique_pipe_name("exec");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (recv, send) = conn.split();
        let mut reader = tokio::io::BufReader::new(recv);
        let mut writer = send;

        let mut line = String::new();
        tokio::io::AsyncBufReadExt::read_line(&mut reader, &mut line)
            .await
            .expect("读取失败");
        let msg: IpcMessage = serde_json::from_str(line.trim()).expect("解析失败");
        assert_eq!(msg.r#type, "execute");
        assert_eq!(msg.action.as_deref(), Some("keypress"));
        assert_eq!(
            msg.keys.as_deref(),
            Some(&["1".to_string(), "2".to_string()][..])
        );
        assert_eq!(msg.delay, Some(50));

        let result_data = serde_json::json!({"status": "ok", "executed": 2});
        let result = IpcMessage::result(msg.seq + 200, msg.seq, result_data);
        let mut json = serde_json::to_string(&result).unwrap();
        json.push('\n');
        tokio::io::AsyncWriteExt::write_all(&mut writer, json.as_bytes())
            .await
            .expect("发送 result 失败");
        tokio::io::AsyncWriteExt::flush(&mut writer)
            .await
            .expect("flush 失败");
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("Client 连接失败");

    let seq = client.next_seq();
    let exec_msg = IpcMessage::execute(seq, vec!["1".to_string(), "2".to_string()], 50);
    client
        .send(&exec_msg)
        .await
        .expect("Client 发送 execute 失败");

    let result = client.recv().await.expect("Client 接收 result 失败");
    assert_eq!(result.r#type, "result");
    assert_eq!(result.ack_seq, Some(seq));
    assert_eq!(result.data.as_ref().unwrap()["status"], "ok");
    assert_eq!(result.data.as_ref().unwrap()["executed"], 2);

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
}

#[tokio::test]
async fn test_roundtrip_latency() {
    let pipe_name = unique_pipe_name("latency");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (recv, send) = conn.split();
        let mut reader = tokio::io::BufReader::new(recv);
        let mut writer = send;

        for _ in 0..200 {
            let mut line = String::new();
            match tokio::io::AsyncBufReadExt::read_line(&mut reader, &mut line).await {
                Ok(0) => break,
                Ok(_) => {}
                Err(_) => break,
            }
            let msg: IpcMessage = match serde_json::from_str(line.trim()) {
                Ok(m) => m,
                Err(_) => break,
            };
            let pong = IpcMessage::pong(msg.seq + 1000, msg.seq);
            let mut json = serde_json::to_string(&pong).unwrap();
            json.push('\n');
            if tokio::io::AsyncWriteExt::write_all(&mut writer, json.as_bytes())
                .await
                .is_err()
            {
                break;
            }
            if tokio::io::AsyncWriteExt::flush(&mut writer).await.is_err() {
                break;
            }
        }
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("Client 连接失败");

    let warmup = 10;
    let rounds = 100;
    let mut latencies = Vec::with_capacity(rounds);

    for i in 0..(warmup + rounds) {
        let seq = client.next_seq();
        let ping = IpcMessage::ping(seq);

        let start = Instant::now();
        client.send(&ping).await.expect("发送 ping 失败");
        let _pong = client.recv().await.expect("接收 pong 失败");
        let elapsed = start.elapsed();

        if i >= warmup {
            latencies.push(elapsed.as_nanos() as f64 / 1000.0);
        }
    }

    let avg = latencies.iter().sum::<f64>() / latencies.len() as f64;
    let min = latencies.iter().cloned().fold(f64::INFINITY, f64::min);
    let max = latencies.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let p50 = {
        let mut sorted = latencies.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        sorted[sorted.len() / 2]
    };

    eprintln!("\n=== IPC 往返延迟测量 ===");
    eprintln!("样本数: {} (预热: {})", rounds, warmup);
    eprintln!("平均: {:.2} μs", avg);
    eprintln!("最小: {:.2} μs", min);
    eprintln!("最大: {:.2} μs", max);
    eprintln!("P50:  {:.2} μs", p50);
    eprintln!("目标: < 1200 μs (1.2ms)");
    eprintln!("========================\n");

    assert!(avg < 1200.0, "平均往返延迟 {:.2} μs 超过 1200 μs 目标", avg);

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
}

#[test]
fn test_message_serialization_roundtrip() {
    let msg = IpcMessage::execute(42, vec!["Space".to_string()], 100);
    let json = serde_json::to_string(&msg).unwrap();
    let decoded: IpcMessage = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded.r#type, "execute");
    assert_eq!(decoded.seq, 42);
    assert_eq!(decoded.action.as_deref(), Some("keypress"));
    assert_eq!(decoded.keys.as_deref(), Some(&["Space".to_string()][..]));
    assert_eq!(decoded.delay, Some(100));
}

#[test]
fn test_seq_counter_monotonic() {
    use std::sync::atomic::{AtomicU64, Ordering};
    let counter = AtomicU64::new(1);
    let s1 = counter.fetch_add(1, Ordering::Relaxed);
    let s2 = counter.fetch_add(1, Ordering::Relaxed);
    let s3 = counter.fetch_add(1, Ordering::Relaxed);

    assert!(s2 > s1, "seq 应单调递增: {} > {}", s2, s1);
    assert!(s3 > s2, "seq 应单调递增: {} > {}", s3, s2);
}

#[test]
fn test_ipc_error_from_io() {
    let err = std::io::Error::new(std::io::ErrorKind::BrokenPipe, "broken pipe");
    let ipc_err = IpcError::from(err);
    assert!(matches!(ipc_err, IpcError::PipeBroken(_)));

    let err2 = std::io::Error::new(std::io::ErrorKind::Other, "some other error");
    let ipc_err2 = IpcError::from(err2);
    assert!(matches!(ipc_err2, IpcError::IoError(_)));
}

#[test]
fn test_ipc_error_display() {
    let err = IpcError::ConnectionClosed;
    assert_eq!(format!("{err}"), "连接已关闭");

    let err = IpcError::MessageTooLarge(100, 64);
    assert!(format!("{err}").contains("100"));

    let err = IpcError::Timeout;
    assert_eq!(format!("{err}"), "等待响应超时");
}

#[test]
fn test_hotkey_merger() {
    let mut merger = HotkeyMerger::new(100);

    merger.push(IpcMessage::hotkey_event(1, "F1"));
    merger.push(IpcMessage::hotkey_event(2, "F2"));
    merger.push(IpcMessage::hotkey_event(3, "F1"));

    assert!(!merger.should_flush());

    std::thread::sleep(std::time::Duration::from_millis(110));
    assert!(merger.should_flush());

    let flushed = merger.flush();
    assert_eq!(flushed.len(), 2);

    let has_f1 = flushed.iter().any(|m| {
        m.keys
            .as_ref()
            .map(|k| k.contains(&"F1".to_string()))
            .unwrap_or(false)
    });
    let has_f2 = flushed.iter().any(|m| {
        m.keys
            .as_ref()
            .map(|k| k.contains(&"F2".to_string()))
            .unwrap_or(false)
    });
    assert!(has_f1);
    assert!(has_f2);
}

#[test]
fn test_hotkey_merger_default() {
    let merger = HotkeyMerger::default();
    assert_eq!(merger.merge_window(), Duration::from_millis(100));
}

#[test]
fn test_ipc_command_serialization() {
    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
        mode: None,
        key_press_duration: None,
        hold_keys: None,
        hold_mode: None,
        mode_data: None,
    };
    let json = serde_json::to_string(&cmd).unwrap();
    let decoded: IpcCommand = serde_json::from_str(&json).unwrap();
    match decoded {
        IpcCommand::ToggleGroup {
            group_id, active, ..
        } => {
            assert_eq!(group_id, "1");
            assert!(active);
        }
        _ => panic!("Expected ToggleGroup"),
    }
}

#[tokio::test]
async fn test_send_command_and_wait_response() {
    let pipe_name = unique_pipe_name("cmdwait");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (recv, send) = conn.split();
        let mut reader = tokio::io::BufReader::new(recv);
        let mut writer = send;

        let mut line = String::new();
        tokio::io::AsyncBufReadExt::read_line(&mut reader, &mut line)
            .await
            .expect("读取失败");
        let msg: IpcMessage = serde_json::from_str(line.trim()).expect("解析失败");

        let result = IpcMessage::result(999, msg.seq, serde_json::json!({"ok": true}));
        let mut json = serde_json::to_string(&result).unwrap();
        json.push('\n');
        tokio::io::AsyncWriteExt::write_all(&mut writer, json.as_bytes())
            .await
            .expect("发送失败");
        tokio::io::AsyncWriteExt::flush(&mut writer)
            .await
            .expect("flush 失败");
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("连接失败");

    let client = Arc::new(client);
    let listen_client = client.clone();
    let listen_handle = tokio::spawn(async move {
        listen_client.listen_ahk().await;
    });

    let cmd = IpcCommand::Ping;

    let result = client
        .send_and_wait(cmd, Duration::from_secs(5))
        .await
        .expect("send_and_wait 失败");

    assert_eq!(result.r#type, "result");
    assert_eq!(result.seq, 999);
    assert_eq!(result.data.as_ref().unwrap()["ok"], true);

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
    let _ = tokio::time::timeout(Duration::from_secs(1), listen_handle).await;
}

#[tokio::test]
async fn test_wait_response_timeout() {
    let pipe_name = unique_pipe_name("timeout");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let _server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (_recv, _send) = conn.split();
        tokio::time::sleep(Duration::from_secs(5)).await;
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("连接失败");

    let seq = client.next_seq();
    let result = client.wait_response(seq, Duration::from_millis(200)).await;
    assert!(matches!(result, Err(IpcError::Timeout)));

    drop(client);
}

#[tokio::test]
async fn test_is_connected() {
    let pipe_name = unique_pipe_name("connected");
    let name_clone = pipe_name.clone();

    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let server_task = tokio::spawn(async move {
        let _conn = listener.accept().await.expect("Server 接受连接失败");
        tokio::time::sleep(Duration::from_secs(2)).await;
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    assert!(!client.is_connected().await);

    client.connect_to_ahk().await.expect("连接失败");
    assert!(client.is_connected().await);

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(3), server_task).await;
}

#[test]
fn test_shutdown_message() {
    let msg = IpcMessage::shutdown(42);
    assert_eq!(msg.r#type, "shutdown");
    assert_eq!(msg.seq, 42);
    assert_eq!(msg.action.as_deref(), Some("shutdown"));
}

#[test]
fn test_heartbeat_message() {
    let msg = IpcMessage::heartbeat(100);
    assert_eq!(msg.r#type, "heartbeat");
    assert_eq!(msg.seq, 100);
}

#[test]
fn test_hotkey_event_message() {
    let msg = IpcMessage::hotkey_event(1, "F1");
    assert_eq!(msg.r#type, "hotkey");
    assert_eq!(msg.action.as_deref(), Some("hotkey_event"));
    assert_eq!(msg.keys.as_deref(), Some(&["F1".to_string()][..]));
}

// ---- C-14: Named Pipe 认证测试 ----

#[tokio::test]
async fn test_accept_from_ahk_valid_auth() {
    let pipe_name = unique_pipe_name("auth_ok");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new_with_token(&name_clone, "TEST_AUTH_TOKEN".to_string());
    let server_handle = tokio::spawn(async move { server.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("客户端连接失败");

    let auth_msg = IpcMessage::auth("TEST_AUTH_TOKEN");
    client.send(&auth_msg).await.expect("发送认证消息失败");

    let result = tokio::time::timeout(Duration::from_secs(2), server_handle)
        .await
        .expect("超时")
        .expect("任务 panic");
    assert!(result.is_ok(), "有效认证应成功: {:?}", result);

    drop(client);
}

#[tokio::test]
async fn test_accept_from_ahk_invalid_auth_token() {
    let pipe_name = unique_pipe_name("auth_bad");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new(&name_clone);
    let server_handle = tokio::spawn(async move { server.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("客户端连接失败");

    let auth_msg = IpcMessage::auth("WRONG_TOKEN");
    client.send(&auth_msg).await.expect("发送失败");

    let result = tokio::time::timeout(Duration::from_secs(2), server_handle)
        .await
        .expect("超时")
        .expect("任务 panic");
    assert!(result.is_err(), "无效认证应失败");
    assert!(
        matches!(result, Err(IpcError::AuthFailed(_))),
        "应返回 AuthFailed: {:?}",
        result
    );
}

#[tokio::test]
async fn test_accept_from_ahk_no_auth_message() {
    let pipe_name = unique_pipe_name("auth_none");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new(&name_clone);
    let server_handle = tokio::spawn(async move { server.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("客户端连接失败");

    let ping_msg = IpcMessage::ping(1);
    client.send(&ping_msg).await.expect("发送失败");

    let result = tokio::time::timeout(Duration::from_secs(2), server_handle)
        .await
        .expect("超时")
        .expect("任务 panic");
    assert!(result.is_err(), "无认证应失败");
    assert!(
        matches!(result, Err(IpcError::AuthFailed(_))),
        "应返回 AuthFailed: {:?}",
        result
    );
}
