use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::time::{Duration, Instant};

use clarix_pdf_oxide::agent_api::NativeStartAgentRunRequest;
use clarix_pdf_oxide::editing_api::{
    NativeEditorSession, NativeOpenEditorRequest, NativePageSceneRequest, NativeSelectionKind,
    NativeSelectionRange, NativeSelectionSet, NativeViewportPriority,
};

fn fixture_path() -> String {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated/standard-latin.pdf")
        .to_string_lossy()
        .into_owned()
}

fn selection_for(session: &NativeEditorSession) -> NativeSelectionSet {
    let scene = session
        .page_scene(NativePageSceneRequest {
            page_number: 1,
            expected_revision: 0,
            priority: NativeViewportPriority::ActiveSelection,
        })
        .unwrap();
    let object = scene
        .objects
        .iter()
        .find(|object| object.text.as_ref().is_some_and(|text| !text.is_empty()))
        .unwrap();
    let text = object.text.clone().unwrap();
    NativeSelectionSet {
        expected_revision: 0,
        kind: NativeSelectionKind::TextRanges,
        ranges: vec![NativeSelectionRange {
            object_id: object.object_id.clone(),
            page_id: scene.page_id,
            page_number: 1,
            start_utf16: 0,
            end_utf16: text.encode_utf16().count() as u32,
            quoted_text: text,
        }],
        object_ids: vec![],
        primary_index: Some(0),
    }
}

struct TwoRoundServer {
    endpoint: String,
    worker: Option<thread::JoinHandle<()>>,
}

impl TwoRoundServer {
    fn start(document_id: String) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let worker = thread::spawn(move || {
            for round in 0..2 {
                let (mut stream, _) = listener.accept().unwrap();
                read_request(&mut stream);
                let body = if round == 0 {
                    format!(
                        "data: {{\"choices\":[{{\"delta\":{{\"tool_calls\":[{{\"index\":0,\"id\":\"rewrite\",\"function\":{{\"name\":\"replace_text_range\",\"arguments\":\"{{\\\"document_id\\\":\\\"{document_id}\\\",\\\"replacement\\\":\\\"new\\\"}}\"}}}}]}}}}]}}\n\ndata: [DONE]\n\n"
                    )
                } else {
                    "data: {\"choices\":[{\"delta\":{\"content\":\"Done\"}}]}\n\ndata: [DONE]\n\n"
                        .into()
                };
                write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                )
                .unwrap();
            }
        });
        Self {
            endpoint,
            worker: Some(worker),
        }
    }
}

impl Drop for TwoRoundServer {
    fn drop(&mut self) {
        if let Some(worker) = self.worker.take() {
            worker.join().unwrap();
        }
    }
}

fn read_request(stream: &mut TcpStream) {
    let mut bytes = Vec::new();
    let mut buffer = [0_u8; 4096];
    let header_end;
    loop {
        let read = stream.read(&mut buffer).unwrap();
        bytes.extend_from_slice(&buffer[..read]);
        if let Some(index) = bytes.windows(4).position(|window| window == b"\r\n\r\n") {
            header_end = index + 4;
            break;
        }
    }
    let headers = String::from_utf8_lossy(&bytes[..header_end]);
    let content_length = headers
        .lines()
        .find_map(|line| {
            line.to_ascii_lowercase()
                .strip_prefix("content-length: ")
                .map(str::to_owned)
        })
        .unwrap()
        .parse::<usize>()
        .unwrap();
    while bytes.len() < header_end + content_length {
        let read = stream.read(&mut buffer).unwrap();
        bytes.extend_from_slice(&buffer[..read]);
    }
}

#[test]
fn native_run_uses_the_same_editor_actor_and_persists_monotonic_events() {
    let project_root = tempfile::tempdir().unwrap();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    })
    .unwrap();
    let selection = selection_for(&session);
    let context = session
        .selection_context(selection.clone(), 512, 512, 8)
        .unwrap();
    let server = TwoRoundServer::start(context.document_id.clone());
    let run = session
        .start_agent_run(NativeStartAgentRunRequest {
            schema_version: 1,
            provider_endpoint: server.endpoint.clone(),
            model_id: "fixture".into(),
            headers: HashMap::new(),
            api_key: "sk-secret".into(),
            conversation_id: None,
            user_prompt: "rewrite".into(),
            selection,
            disclosure_sha256: context.disclosure_sha256,
            max_tool_calls: 4,
            max_provider_rounds: 3,
            max_elapsed_ms: 10_000,
            max_output_tokens: 256,
        })
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    let audit = loop {
        if let Ok(audit) = session.read_agent_audit(run.run_id.clone()) {
            if matches!(audit.status.as_str(), "completed" | "failed" | "cancelled") {
                break audit;
            }
        }
        assert!(Instant::now() < deadline, "agent run did not terminate");
        thread::sleep(Duration::from_millis(20));
    };

    assert_eq!(audit.status, "completed");
    assert!(audit
        .events
        .windows(2)
        .all(|pair| pair[0].sequence < pair[1].sequence));
    assert_eq!(session.metadata().unwrap().revision, 1);
    session.close().unwrap();
}

#[test]
fn secrets_are_redacted_and_closed_session_rejects_late_agent_actions() {
    let project_root = tempfile::tempdir().unwrap();
    let session = NativeEditorSession::open(NativeOpenEditorRequest {
        source_path: fixture_path(),
        project_root: Some(project_root.path().to_string_lossy().into_owned()),
    })
    .unwrap();
    let selection = selection_for(&session);
    let request = NativeStartAgentRunRequest {
        schema_version: 1,
        provider_endpoint: "https://example.invalid/v1".into(),
        model_id: "fixture".into(),
        headers: HashMap::new(),
        api_key: "sk-must-not-print".into(),
        conversation_id: None,
        user_prompt: "rewrite".into(),
        selection,
        disclosure_sha256: "digest".into(),
        max_tool_calls: 1,
        max_provider_rounds: 1,
        max_elapsed_ms: 1000,
        max_output_tokens: 32,
    };
    assert!(!format!("{request:?}").contains("sk-must-not-print"));
    session.close().unwrap();
    let error = session
        .cancel_agent_run("not-even-a-run-id".into())
        .unwrap_err();
    assert!(error.starts_with("session_closed:"));
}
