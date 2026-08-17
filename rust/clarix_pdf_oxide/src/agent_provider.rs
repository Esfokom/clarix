use std::collections::BTreeMap;
use std::fmt;
use std::io::{BufRead, BufReader};
use std::time::Duration;

use clarix_agent_core::{
    AgentError, CancellationToken, ModelProvider, OpenAiStreamDecoder, ProviderCompletion,
    ProviderEventSink, ProviderMessage, ProviderRequest, ProviderRole, SecretString,
};
use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue, AUTHORIZATION};
use reqwest::{StatusCode, Url};
use serde_json::{json, Value};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_REQUEST_TIMEOUT: Duration = Duration::from_secs(120);

pub struct OpenAiCompatibleRustProvider {
    endpoint: Url,
    model: String,
    profile_headers: HeaderMap,
    api_key: SecretString,
    request_timeout: Duration,
    client: Client,
}

impl fmt::Debug for OpenAiCompatibleRustProvider {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OpenAiCompatibleRustProvider")
            .field("endpoint", &self.endpoint)
            .field("model", &self.model)
            .field(
                "profile_header_names",
                &self.profile_headers.keys().collect::<Vec<_>>(),
            )
            .field("api_key", &self.api_key)
            .field("request_timeout", &self.request_timeout)
            .finish()
    }
}

impl OpenAiCompatibleRustProvider {
    pub fn new(
        endpoint: impl AsRef<str>,
        model: impl Into<String>,
        profile_headers: BTreeMap<String, String>,
        api_key: impl Into<String>,
        request_timeout: Duration,
    ) -> Result<Self, AgentError> {
        let endpoint = normalize_endpoint(endpoint.as_ref())?;
        let model = model.into();
        if model.trim().is_empty() {
            return Err(config_error("provider model must not be empty"));
        }
        if request_timeout.is_zero() {
            return Err(config_error("provider timeout must be positive"));
        }
        let mut headers = HeaderMap::new();
        for (name, value) in profile_headers {
            if name.eq_ignore_ascii_case("authorization") {
                continue;
            }
            let name = HeaderName::from_bytes(name.as_bytes())
                .map_err(|_| config_error("provider profile contains an invalid header name"))?;
            let value = HeaderValue::from_str(&value)
                .map_err(|_| config_error("provider profile contains an invalid header value"))?;
            headers.insert(name, value);
        }
        let request_timeout = request_timeout.min(MAX_REQUEST_TIMEOUT);
        let client = Client::builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .timeout(request_timeout)
            .build()
            .map_err(|_| config_error("failed to construct provider HTTP client"))?;
        Ok(Self {
            endpoint,
            model,
            profile_headers: headers,
            api_key: SecretString::new(api_key),
            request_timeout,
            client,
        })
    }
}

impl ModelProvider for OpenAiCompatibleRustProvider {
    fn complete(
        &self,
        request: ProviderRequest,
        cancellation: &CancellationToken,
        sink: &mut dyn ProviderEventSink,
    ) -> Result<ProviderCompletion, AgentError> {
        cancellation.check()?;
        let authorization =
            HeaderValue::from_str(&format!("Bearer {}", self.api_key.expose_secret()))
                .map_err(|_| config_error("provider API key cannot be encoded as a header"))?;
        let mut headers = self.profile_headers.clone();
        headers.insert(AUTHORIZATION, authorization);
        let response = self
            .client
            .post(self.endpoint.clone())
            .headers(headers)
            .json(&openai_request(&self.model, request))
            .send()
            .map_err(map_transport_error)?;
        if !response.status().is_success() {
            return Err(map_status(response.status()));
        }

        let mut decoder = OpenAiStreamDecoder::new();
        let mut reader = BufReader::new(response);
        let mut line = String::new();
        loop {
            cancellation.check()?;
            line.clear();
            let read = reader
                .read_line(&mut line)
                .map_err(|_| AgentError::Provider {
                    code: "provider_stream_io".into(),
                    message: "provider stream ended with an I/O failure".into(),
                })?;
            if read == 0 {
                break;
            }
            let line = line.trim_end_matches(['\r', '\n']);
            if line.starts_with("data:") {
                for event in decoder.push_data(line)? {
                    cancellation.check()?;
                    sink.emit(event)?;
                }
            }
        }
        cancellation.check()?;
        decoder.finish()
    }
}

fn normalize_endpoint(raw: &str) -> Result<Url, AgentError> {
    let mut endpoint = Url::parse(raw).map_err(|_| config_error("provider endpoint is invalid"))?;
    let plaintext_allowed = endpoint.scheme() == "http"
        && matches!(endpoint.host_str(), Some("localhost" | "127.0.0.1" | "::1"));
    if endpoint.scheme() != "https" && !plaintext_allowed {
        return Err(config_error(
            "provider endpoint must use HTTPS except for loopback testing",
        ));
    }
    if !endpoint
        .path()
        .trim_end_matches('/')
        .ends_with("/chat/completions")
    {
        let path = format!("{}/chat/completions", endpoint.path().trim_end_matches('/'));
        endpoint.set_path(&path);
    }
    Ok(endpoint)
}

fn openai_request(model: &str, request: ProviderRequest) -> Value {
    json!({
        "model": model,
        "messages": request.messages.iter().map(openai_message).collect::<Vec<_>>(),
        "tools": request.tools.into_iter().map(|tool| json!({
            "type":"function",
            "function":{
                "name":tool.name,
                "description":tool.description,
                "parameters":tool.parameters
            }
        })).collect::<Vec<_>>(),
        "max_tokens": request.max_output_tokens,
        "stream": true,
        "stream_options":{"include_usage":true}
    })
}

fn openai_message(message: &ProviderMessage) -> Value {
    let role = match message.role {
        ProviderRole::System => "system",
        ProviderRole::User => "user",
        ProviderRole::Assistant => "assistant",
        ProviderRole::Tool => "tool",
    };
    let mut value = json!({"role":role,"content":message.content});
    let object = value.as_object_mut().expect("message is an object");
    if let Some(tool_call_id) = &message.tool_call_id {
        object.insert("tool_call_id".into(), json!(tool_call_id));
    }
    if !message.tool_calls.is_empty() {
        object.insert(
            "tool_calls".into(),
            Value::Array(
                message
                    .tool_calls
                    .iter()
                    .map(|call| {
                        json!({
                            "id":call.id,
                            "type":"function",
                            "function":{
                                "name":call.name,
                                "arguments":call.arguments.to_string()
                            }
                        })
                    })
                    .collect(),
            ),
        );
    }
    value
}

fn map_transport_error(error: reqwest::Error) -> AgentError {
    if error.is_timeout() {
        AgentError::Provider {
            code: "provider_timeout".into(),
            message: "provider request timed out".into(),
        }
    } else {
        AgentError::Provider {
            code: "provider_transport".into(),
            message: "provider request could not be completed".into(),
        }
    }
}

fn map_status(status: StatusCode) -> AgentError {
    let (code, message) = match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => (
            "provider_authentication",
            "provider rejected the configured credentials",
        ),
        StatusCode::TOO_MANY_REQUESTS => {
            ("provider_rate_limited", "provider rate limit was reached")
        }
        status if status.is_server_error() => (
            "provider_unavailable",
            "provider is temporarily unavailable",
        ),
        _ => ("provider_http_error", "provider rejected the request"),
    };
    AgentError::Provider {
        code: code.into(),
        message: message.into(),
    }
}

fn config_error(message: &str) -> AgentError {
    AgentError::Provider {
        code: "invalid_provider_config".into(),
        message: message.into(),
    }
}
