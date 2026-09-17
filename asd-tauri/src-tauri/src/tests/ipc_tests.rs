use crate::infrastructure::ipc::*;
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use asd_test_harness::unique_pipe_name;
use interprocess::local_socket::traits::tokio::{Listener as ListenerTrait, Stream as StreamTrait};
use serial_test::serial;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[tokio::test]
#[serial]
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
#[serial]
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
#[serial]
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
    let mut sorted = latencies.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p50 = sorted[sorted.len() / 2];
    let p95 = sorted[(sorted.len() as f64 * 0.95).ceil() as usize - 1];

    eprintln!("\n=== IPC 往返延迟测量 ===");
    eprintln!("样本数: {rounds} (预热: {warmup})");
    eprintln!("平均: {avg:.2} μs");
    eprintln!("最小: {min:.2} μs");
    eprintln!("最大: {max:.2} μs");
    eprintln!("P50:  {p50:.2} μs");
    eprintln!("P95:  {p95:.2} μs");
    eprintln!("目标: P50 < 1200 μs (1.2ms)");
    eprintln!("========================\n");

    // 统计口径：**判定用 P50，不是平均值**。
    // 实测（CI 共享 runner，2 vCPU）：100 个样本里出现一次 158ms 的宿主调度停顿，
    // 单次就给平均值贡献约 1580 μs，把平均值从 ~150 μs 抬到 **2454 μs** 而失败；
    // 同一批样本的 P50 只有 **153.8 μs**。平均值测的是宿主抖动，P50 才反映 IPC
    // 实现本身的系统性开销 —— 若实现真的退化（例如每次往返多一次固定等待），
    // 偏移是系统性的，P50 会整体抬升。
    // 参考量级：本机 P50 ≈ 66 μs、CI P50 ≈ 154 μs，距 1200 μs 目标有 7.8× 余量。
    assert!(p50 < 1200.0, "P50 往返延迟 {p50:.2} μs 超过 1200 μs 目标");

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(2), server_task).await;
}

#[test]
#[serial]
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
#[serial]
fn test_seq_counter_monotonic() {
    use std::sync::atomic::{AtomicU64, Ordering};
    let counter = AtomicU64::new(1);
    let s1 = counter.fetch_add(1, Ordering::Relaxed);
    let s2 = counter.fetch_add(1, Ordering::Relaxed);
    let s3 = counter.fetch_add(1, Ordering::Relaxed);

    assert!(s2 > s1, "seq 应单调递增: {s2} > {s1}");
    assert!(s3 > s2, "seq 应单调递增: {s3} > {s2}");
}

#[test]
#[serial]
fn test_ipc_error_from_io() {
    let err = std::io::Error::new(std::io::ErrorKind::BrokenPipe, "broken pipe");
    let ipc_err = IpcError::from(err);
    assert!(matches!(ipc_err, IpcError::PipeBroken(_)));

    let err2 = std::io::Error::other("some other error");
    let ipc_err2 = IpcError::from(err2);
    assert!(matches!(ipc_err2, IpcError::IoError(_)));
}

#[test]
#[serial]
fn test_ipc_error_display() {
    let err = IpcError::ConnectionClosed;
    assert_eq!(format!("{err}"), "连接已关闭");

    let err = IpcError::MessageTooLarge(100, 64);
    assert!(format!("{err}").contains("100"));

    let err = IpcError::Timeout;
    assert_eq!(format!("{err}"), "等待响应超时");
}

#[test]
#[serial]
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
#[serial]
fn test_hotkey_merger_default() {
    let merger = HotkeyMerger::default();
    assert_eq!(merger.merge_window(), Duration::from_millis(100));
}

#[test]
#[serial]
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
#[serial]
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
#[serial]
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
#[serial]
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
#[serial]
fn test_shutdown_message() {
    let msg = IpcMessage::shutdown(42);
    assert_eq!(msg.r#type, "shutdown");
    assert_eq!(msg.seq, 42);
    assert_eq!(msg.action.as_deref(), Some("shutdown"));
}

#[test]
#[serial]
fn test_heartbeat_message() {
    let msg = IpcMessage::heartbeat(100);
    assert_eq!(msg.r#type, "heartbeat");
    assert_eq!(msg.seq, 100);
}

#[test]
#[serial]
fn test_hotkey_event_message() {
    let msg = IpcMessage::hotkey_event(1, "F1");
    assert_eq!(msg.r#type, "hotkey");
    assert_eq!(msg.action.as_deref(), Some("hotkey_event"));
    assert_eq!(msg.keys.as_deref(), Some(&["F1".to_string()][..]));
}

// ---- C-14: Named Pipe 认证测试 ----

#[tokio::test]
#[serial]
async fn test_accept_from_ahk_valid_auth() {
    let pipe_name = unique_pipe_name("auth_ok");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) =
        IpcManager::new_with_token(&name_clone, "TEST_AUTH_TOKEN".to_string());
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
    assert!(result.is_ok(), "有效认证应成功: {result:?}");

    drop(client);
}

#[tokio::test]
#[serial]
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
        "应返回 AuthFailed: {result:?}"
    );
}

#[tokio::test]
#[serial]
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
        "应返回 AuthFailed: {result:?}"
    );
}

// ---- IPC 传输层边界条件测试 (Task 2) ----

#[tokio::test]
#[serial]
async fn test_message_size_limit_exceeded() {
    // 构造超过 64KB 的消息，验证 recv() 检测并拒绝超大消息
    let pipe_name = unique_pipe_name("oversize");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (_recv, mut writer) = conn.split();
        // 70KB 负载 + JSON 包裹 + 换行，总大小约 70KB+，远超 64KB 限制。
        // 换行符放在末尾，前 64KB 内无换行，触发 recv() 的超大消息检测路径。
        let big_payload = "A".repeat(70 * 1024);
        let line = format!("{{\"type\":\"ping\",\"seq\":1,\"data\":\"{big_payload}\"}}\n");
        let bytes = line.as_bytes();
        assert!(
            bytes.len() > 64 * 1024,
            "测试消息应超过 64KB，实际 {} 字节",
            bytes.len()
        );
        tokio::io::AsyncWriteExt::write_all(&mut writer, bytes)
            .await
            .expect("写入失败");
        tokio::io::AsyncWriteExt::flush(&mut writer)
            .await
            .expect("flush 失败");
        // 保持连接，等待 client 读取
        tokio::time::sleep(Duration::from_secs(2)).await;
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("Client 连接失败");

    let result = tokio::time::timeout(Duration::from_secs(3), client.recv())
        .await
        .expect("recv 不应挂起");
    assert!(result.is_err(), "超大消息应返回错误");
    let err = result.unwrap_err();
    assert!(
        matches!(err, IpcError::MessageTooLarge(_, _)),
        "应返回 MessageTooLarge，实际: {err:?}"
    );

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(3), server_task).await;
}

#[tokio::test]
#[serial]
async fn test_message_size_boundary() {
    // 构造恰好 65535 字节 (64KB - 1) 的消息，验证正常处理
    let pipe_name = unique_pipe_name("boundary");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    // 手工构建 JSON 以精确控制字节数:
    // {"type":"ping","seq":1,"data":"<padding>"}\n
    // 前缀 {"type":"ping","seq":1,"data":" = 31 字节
    // 后缀 "}\n = 3 字节
    // 总计 31 + N + 3 = 34 + N，目标 65535 → N = 65501
    let padding = "A".repeat(65501);
    let line = format!("{{\"type\":\"ping\",\"seq\":1,\"data\":\"{padding}\"}}\n");
    assert_eq!(line.len(), 65535, "消息总长应为 65535 字节");
    let line_bytes = line.into_bytes();

    let server_task = tokio::spawn(async move {
        let conn = listener.accept().await.expect("Server 接受连接失败");
        let (_recv, mut writer) = conn.split();
        tokio::io::AsyncWriteExt::write_all(&mut writer, &line_bytes)
            .await
            .expect("写入失败");
        tokio::io::AsyncWriteExt::flush(&mut writer)
            .await
            .expect("flush 失败");
        tokio::time::sleep(Duration::from_secs(2)).await;
    });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("Client 连接失败");

    let result = tokio::time::timeout(Duration::from_secs(3), client.recv())
        .await
        .expect("recv 不应挂起");
    assert!(result.is_ok(), "边界大小消息应正常处理: {:?}", result.err());
    let msg = result.unwrap();
    assert_eq!(msg.r#type, "ping");
    assert_eq!(msg.seq, 1);
    assert!(msg.data.is_some(), "data 字段应保留");

    drop(client);
    let _ = tokio::time::timeout(Duration::from_secs(3), server_task).await;
}

#[tokio::test]
#[serial]
async fn test_auth_token_mismatch() {
    // 服务端设置特定 token，客户端发送不匹配的 token，验证认证失败
    let pipe_name = unique_pipe_name("auth_mismatch");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new_with_token(&name_clone, "CORRECT_TOKEN".to_string());
    let server_handle = tokio::spawn(async move { server.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("客户端连接失败");

    let auth_msg = IpcMessage::auth("DIFFERENT_TOKEN");
    client.send(&auth_msg).await.expect("发送失败");

    let result = tokio::time::timeout(Duration::from_secs(3), server_handle)
        .await
        .expect("超时")
        .expect("任务 panic");
    assert!(result.is_err(), "token 不匹配应失败");
    match result {
        Err(IpcError::AuthFailed(msg)) => {
            assert!(
                msg.contains("token 不匹配"),
                "错误消息应包含 'token 不匹配': {msg}"
            );
        }
        other => panic!("期望 AuthFailed(token 不匹配)，实际: {other:?}"),
    }

    drop(client);
}

#[tokio::test]
#[serial]
async fn test_auth_wrong_message_type() {
    // 客户端发送 pong 而非 auth 作为首条消息，验证认证失败
    let pipe_name = unique_pipe_name("auth_wrong_type");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new_with_token(&name_clone, "TOKEN".to_string());
    let server_handle = tokio::spawn(async move { server.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("客户端连接失败");

    let pong_msg = IpcMessage::pong(1, 0);
    client.send(&pong_msg).await.expect("发送失败");

    let result = tokio::time::timeout(Duration::from_secs(3), server_handle)
        .await
        .expect("超时")
        .expect("任务 panic");
    assert!(result.is_err(), "非 auth 首条消息应失败");
    match result {
        Err(IpcError::AuthFailed(msg)) => {
            assert!(
                msg.contains("期望 auth"),
                "错误消息应包含 '期望 auth': {msg}"
            );
            assert!(msg.contains("pong"), "错误消息应包含实际类型 'pong': {msg}");
        }
        other => panic!("期望 AuthFailed(期望 auth)，实际: {other:?}"),
    }

    drop(client);
}

#[tokio::test]
#[serial]
async fn test_pipe_broken_reconnect() {
    // 建立连接后突然断开客户端，验证 pipe_broken 回调被触发
    let pipe_name = unique_pipe_name("broken_reconnect");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new_with_token(&name_clone, "TOKEN".to_string());
    let broken_flag = Arc::new(AtomicBool::new(false));
    let broken_flag_clone = broken_flag.clone();
    server.set_pipe_broken_callback(Arc::new(move || {
        broken_flag_clone.store(true, Ordering::SeqCst);
    }));

    let server_for_accept = server.clone();
    let accept_handle =
        tokio::spawn(async move { server_for_accept.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("连接失败");
    client
        .send(&IpcMessage::auth("TOKEN"))
        .await
        .expect("发送 auth 失败");

    let auth_result = tokio::time::timeout(Duration::from_secs(3), accept_handle)
        .await
        .expect("认证超时")
        .expect("任务 panic");
    assert!(auth_result.is_ok(), "认证应成功: {:?}", auth_result.err());

    // 启动 listen_ahk 监听客户端消息
    let server_for_listen = server.clone();
    let listen_handle = tokio::spawn(async move {
        server_for_listen.listen_ahk().await;
    });

    // 突然断开客户端，触发 pipe_broken
    drop(client);

    // 轮询等待 pipe_broken 回调触发
    let start = Instant::now();
    while !broken_flag.load(Ordering::SeqCst) && start.elapsed() < Duration::from_secs(3) {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(
        broken_flag.load(Ordering::SeqCst),
        "pipe_broken 回调应在客户端断开后触发"
    );

    listen_handle.abort();
}

#[tokio::test]
#[serial]
async fn test_heartbeat_callback_on_pong() {
    // 说明: IpcManager 本身不含心跳超时逻辑（超时由 ProcessWatchdog 管理）。
    // 此测试验证 pong 消息能正确触发 on_heartbeat 回调，作为心跳信号路径的间接测试。
    let pipe_name = unique_pipe_name("heartbeat");
    let name_clone = pipe_name.clone();
    let listener = create_listener(&pipe_name).expect("创建 Listener 失败");

    let (server, _server_rx) = IpcManager::new_with_token(&name_clone, "TOKEN".to_string());
    let hb_flag = Arc::new(AtomicBool::new(false));
    let hb_flag_clone = hb_flag.clone();
    server.set_heartbeat_callback(Arc::new(move || {
        hb_flag_clone.store(true, Ordering::SeqCst);
    }));

    let server_for_accept = server.clone();
    let accept_handle =
        tokio::spawn(async move { server_for_accept.accept_from_ahk(&listener).await });

    tokio::time::sleep(Duration::from_millis(100)).await;

    let (client, _client_rx) = IpcManager::new(&name_clone);
    client.connect_to_ahk().await.expect("连接失败");
    client
        .send(&IpcMessage::auth("TOKEN"))
        .await
        .expect("发送 auth 失败");

    let auth_result = tokio::time::timeout(Duration::from_secs(3), accept_handle)
        .await
        .expect("认证超时")
        .expect("任务 panic");
    assert!(auth_result.is_ok(), "认证应成功");

    let server_for_listen = server.clone();
    let listen_handle = tokio::spawn(async move {
        server_for_listen.listen_ahk().await;
    });

    // 发送 pong 消息触发 heartbeat 回调
    let pong = IpcMessage::pong(100, 1);
    client.send(&pong).await.expect("发送 pong 失败");

    let start = Instant::now();
    while !hb_flag.load(Ordering::SeqCst) && start.elapsed() < Duration::from_secs(3) {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(
        hb_flag.load(Ordering::SeqCst),
        "pong 消息应触发 on_heartbeat 回调"
    );

    drop(client);
    listen_handle.abort();
}

#[tokio::test]
#[serial]
async fn test_pending_responses_cleanup() {
    // 注册 pending response 后不响应，调用 cleanup_stale_pending 模拟超时清理，
    // 验证条目被清理且 oneshot 接收方收到 error_response
    let (manager, _rx) = IpcManager::new(&unique_pipe_name("pending_cleanup"));

    let manager_for_wait = manager.clone();
    let wait_handle = tokio::spawn(async move {
        // 使用较长超时，确保不会因 timeout 先返回，只能被 cleanup 唤醒
        manager_for_wait
            .wait_response(42, Duration::from_secs(60))
            .await
    });

    // 等待 pending entry 插入
    tokio::time::sleep(Duration::from_millis(100)).await;

    // 直接调用 cleanup_stale_pending(max_age=0)，立即清理所有条目
    manager
        .cleanup_stale_pending(Duration::from_millis(0))
        .await;

    let result = tokio::time::timeout(Duration::from_secs(2), wait_handle)
        .await
        .expect("清理后 wait_response 应立即返回")
        .expect("任务 panic");

    assert!(
        result.is_ok(),
        "cleanup 应通过 oneshot 发送 error_response，使 wait_response 返回 Ok: {:?}",
        result.err()
    );
    let msg = result.unwrap();
    assert!(msg.is_error(), "清理消息应为 error 类型");
    assert_eq!(msg.ack_seq, Some(42), "ack_seq 应为被清理的 seq");
    let data = msg.data.as_ref().expect("应有 data 字段");
    let error_str = data.get("error").and_then(|v| v.as_str()).unwrap_or("");
    assert!(
        error_str.contains("超时清理"),
        "错误消息应包含 '超时清理': {error_str}"
    );
}
