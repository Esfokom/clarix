use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::Duration;

use clarix_agent_core::{
    AgentError, CancellationToken, ModelProvider, ProviderEvent, ProviderEventSink,
    ProviderMessage, ProviderRequest, ProviderRole,
};
use clarix_pdf_oxide::agent_provider::OpenAiCompatibleRustProvider;

struct Sink(Vec<ProviderEvent>);

impl ProviderEventSink for Sink {
    fn emit(&mut self, event: ProviderEvent) -> Result<(), AgentError> {
        self.0.push(event);
        Ok(())
    }
}

struct ReceivedRequest {
    raw: String,
    json: serde_json::Value,
}

struct ScriptedServer {
    endpoint: String,
    received: Receiver<ReceivedRequest>,
    worker: Option<thread::JoinHandle<()>>,
}

impl ScriptedServer {
    fn start(status: &str, body: &str) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let (sender, received) = mpsc::channel();
        let status = status.to_owned();
        let body = body.to_owned();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let raw = read_request(&mut stream);
            let json = serde_json::from_str(raw.split("\r\n\r\n").nth(1).unwrap()).unwrap();
            sender.send(ReceivedRequest { raw, json }).unwrap();
            write!(
                stream,
                "HTTP/1.1 {status}\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
        });
        Self {
            endpoint,
            received,
            worker: Some(worker),
        }
    }

    fn received(&self) -> ReceivedRequest {
        self.received.recv_timeout(Duration::from_secs(2)).unwrap()
    }
}

impl Drop for ScriptedServer {
    fn drop(&mut self) {
        if let Some(worker) = self.worker.take() {
            worker.join().unwrap();
        }
    }
}

fn read_request(stream: &mut TcpStream) -> String {
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
    String::from_utf8(bytes).unwrap()
}

fn request() -> ProviderRequest {
    ProviderRequest {
        messages: vec![ProviderMessage {
            role: ProviderRole::User,
            content: "hello".into(),
            tool_call_id: None,
            tool_calls: vec![],
        }],
        tools: vec![],
        max_output_tokens: 128,
    }
}

fn provider(endpoint: &str, key: &str) -> OpenAiCompatibleRustProvider {
    OpenAiCompatibleRustProvider::new(
        endpoint,
        "test-model",
        BTreeMap::from([("X-Profile".into(), "fixture".into())]),
        key,
        Duration::from_secs(3),
    )
    .unwrap()
}

#[test]
fn provider_sends_standard_stream_request_and_redacts_auth() {
    let server = ScriptedServer::start(
        "200 OK",
        "data: {\"choices\":[{\"delta\":{\"content\":\"Done\"}}]}\n\ndata: [DONE]\n\n",
    );
    let provider = provider(&server.endpoint, "sk-secret");
    let mut sink = Sink(vec![]);

    let completion = provider
        .complete(request(), &CancellationToken::new(), &mut sink)
        .unwrap();

    assert_eq!(completion.text, "Done");
    assert_eq!(sink.0, vec![ProviderEvent::TextDelta("Done".into())]);
    let received = server.received();
    assert!(received
        .raw
        .to_ascii_lowercase()
        .contains("authorization: bearer sk-secret"));
    assert_eq!(received.json["model"], "test-model");
    assert_eq!(received.json["stream"], true);
    assert!(!format!("{provider:?}").contains("sk-secret"));
}

#[test]
fn provider_maps_http_and_stream_failures_to_sanitized_codes() {
    let unauthorized = ScriptedServer::start("401 Unauthorized", "secret response body");
    let error = provider(&unauthorized.endpoint, "key")
        .complete(request(), &CancellationToken::new(), &mut Sink(vec![]))
        .unwrap_err();
    assert_eq!(error.code(), "provider_failure");
    assert!(
        matches!(error, AgentError::Provider { code, message } if code == "provider_authentication" && !message.contains("secret"))
    );

    let malformed = ScriptedServer::start("200 OK", "data: definitely-not-json\n\n");
    let error = provider(&malformed.endpoint, "key")
        .complete(request(), &CancellationToken::new(), &mut Sink(vec![]))
        .unwrap_err();
    assert!(
        matches!(error, AgentError::Provider { code, .. } if code == "malformed_provider_stream")
    );
}

#[test]
fn provider_normalizes_fragmented_streaming_tool_calls() {
    let server = ScriptedServer::start(
        "200 OK",
        concat!(
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"search_text\",\"arguments\":\"{\\\"query\\\":\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"old\\\"}\"}}]}}]}\n\n",
            "data: [DONE]\n\n"
        ),
    );

    let completion = provider(&server.endpoint, "key")
        .complete(request(), &CancellationToken::new(), &mut Sink(vec![]))
        .unwrap();

    assert_eq!(completion.tool_calls.len(), 1);
    assert_eq!(completion.tool_calls[0].name, "search_text");
    assert_eq!(completion.tool_calls[0].arguments["query"], "old");
}

#[test]
fn cancelled_calls_do_not_open_a_connection_and_nonlocal_http_is_rejected() {
    let cancellation = CancellationToken::new();
    cancellation.cancel();
    let provider = OpenAiCompatibleRustProvider::new(
        "https://example.invalid/v1",
        "model",
        BTreeMap::new(),
        "key",
        Duration::from_secs(1),
    )
    .unwrap();
    assert_eq!(
        provider
            .complete(request(), &cancellation, &mut Sink(vec![]))
            .unwrap_err(),
        AgentError::Cancelled
    );

    assert!(OpenAiCompatibleRustProvider::new(
        "http://example.com/v1",
        "model",
        BTreeMap::new(),
        "key",
        Duration::from_secs(1),
    )
    .is_err());
}
