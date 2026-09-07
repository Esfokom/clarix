use std::collections::HashMap;
use std::io::{BufRead, BufReader};

use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue, AUTHORIZATION};
use reqwest::Url;
use serde_json::{json, Value};

use crate::frb_generated::StreamSink;

#[derive(Debug, Clone)]
pub struct NativeChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Clone)]
pub struct NativeChatRequest {
    pub provider_endpoint: String,
    pub model_id: String,
    pub headers: HashMap<String, String>,
    pub api_key: String,
    pub messages: Vec<NativeChatMessage>,
}

impl std::fmt::Debug for NativeChatRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("NativeChatRequest")
            .field("provider_endpoint", &self.provider_endpoint)
            .field("model_id", &self.model_id)
            .field("header_names", &self.headers.keys().collect::<Vec<_>>())
            .field("api_key", &"[REDACTED]")
            .field("messages", &self.messages)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NativeChatEvent {
    TextDelta { text: String },
    Error { message: String },
    Done,
}

pub fn stream_chat(request: NativeChatRequest, sink: StreamSink<NativeChatEvent>) -> Result<(), String> {
    let endpoint = chat_endpoint(&request.provider_endpoint)?;
    let mut headers = HeaderMap::new();
    for (name, value) in request.headers {
        if name.eq_ignore_ascii_case("authorization") {
            continue;
        }
        let name = HeaderName::from_bytes(name.as_bytes())
            .map_err(|_| "provider profile contains an invalid header name".to_owned())?;
        let value = HeaderValue::from_str(&value)
            .map_err(|_| "provider profile contains an invalid header value".to_owned())?;
        headers.insert(name, value);
    }
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {}", request.api_key))
            .map_err(|_| "provider API key cannot be encoded as a header".to_owned())?,
    );
    let body = json!({
        "model": request.model_id,
        "messages": request.messages.into_iter().map(|message| json!({
            "role": message.role,
            "content": message.content,
        })).collect::<Vec<_>>(),
        "stream": true,
    });
    let response = Client::builder()
        .build()
        .map_err(|error| error.to_string())?
        .post(endpoint)
        .headers(headers)
        .json(&body)
        .send()
        .map_err(|error| error.to_string())?;
    if !response.status().is_success() {
        return Err(format!("provider returned HTTP {}", response.status()));
    }
    for line in BufReader::new(response).lines() {
        let line = line.map_err(|error| error.to_string())?;
        let Some(data) = line.strip_prefix("data:") else { continue };
        let Some(event) = parse_chat_sse_data(data.trim()) else { continue };
        let done = event == NativeChatEvent::Done;
        sink.add(event).map_err(|error| error.to_string())?;
        if done {
            return Ok(());
        }
    }
    sink.add(NativeChatEvent::Done)
        .map_err(|error| error.to_string())
}

pub fn parse_chat_sse_data(data: &str) -> Option<NativeChatEvent> {
    if data == "[DONE]" {
        return Some(NativeChatEvent::Done);
    }
    let value: Value = serde_json::from_str(data).ok()?;
    let text = value
        .get("choices")?
        .as_array()?
        .first()?
        .get("delta")?
        .get("content")?
        .as_str()?;
    (!text.is_empty()).then(|| NativeChatEvent::TextDelta {
        text: text.to_owned(),
    })
}

fn chat_endpoint(raw: &str) -> Result<Url, String> {
    let mut endpoint = Url::parse(raw).map_err(|_| "provider endpoint is invalid".to_owned())?;
    let local_http = endpoint.scheme() == "http"
        && matches!(endpoint.host_str(), Some("localhost" | "127.0.0.1" | "::1"));
    if endpoint.scheme() != "https" && !local_http {
        return Err("provider endpoint must use HTTPS except for loopback testing".to_owned());
    }
    if !endpoint.path().trim_end_matches('/').ends_with("/chat/completions") {
        endpoint.set_path(&format!("{}/chat/completions", endpoint.path().trim_end_matches('/')));
    }
    Ok(endpoint)
}
