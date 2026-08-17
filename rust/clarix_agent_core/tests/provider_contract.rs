use clarix_agent_core::{
    AgentError, CancellationToken, ModelProvider, OpenAiStreamDecoder, ProviderCompletion,
    ProviderEvent, ProviderEventSink, ProviderMessage, ProviderRequest, ProviderRole,
    ProviderUsage,
};

#[test]
fn fragmented_openai_tool_arguments_normalize_to_one_typed_call() {
    let mut decoder = OpenAiStreamDecoder::new();
    decoder
        .push_data(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"search_text","arguments":"{\"query\":"}}]},"finish_reason":null}]}"#,
        )
        .unwrap();
    decoder
        .push_data(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"termination\"}"}}]},"finish_reason":"tool_calls"}]}"#,
        )
        .unwrap();

    let completion = decoder.finish().unwrap();

    assert_eq!(completion.tool_calls.len(), 1);
    assert_eq!(completion.tool_calls[0].id, "call_1");
    assert_eq!(completion.tool_calls[0].name, "search_text");
    assert_eq!(
        completion.tool_calls[0].arguments,
        serde_json::json!({"query": "termination"})
    );
}

#[test]
fn decoder_emits_text_deltas_and_records_usage_without_mirroring_expectations() {
    let mut decoder = OpenAiStreamDecoder::new();
    let first = decoder
        .push_data(r#"data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"#)
        .unwrap();
    let second = decoder
        .push_data(
            r#"{"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}],"usage":{"prompt_tokens":9,"completion_tokens":2,"total_tokens":11}}"#,
        )
        .unwrap();
    decoder.push_data("data: [DONE]").unwrap();

    let completion = decoder.finish().unwrap();

    assert_eq!(first, vec![ProviderEvent::TextDelta("Hel".into())]);
    assert_eq!(second, vec![ProviderEvent::TextDelta("lo".into())]);
    assert_eq!(completion.text, "Hello");
    assert_eq!(
        completion.usage,
        Some(ProviderUsage {
            input_tokens: 9,
            output_tokens: 2,
            total_tokens: 11,
        })
    );
}

#[test]
fn decoder_rejects_non_object_tool_arguments() {
    let mut decoder = OpenAiStreamDecoder::new();
    decoder
        .push_data(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"search_text","arguments":"[]"}}]},"finish_reason":"tool_calls"}]}"#,
        )
        .unwrap();

    let error = decoder.finish().unwrap_err();

    assert_eq!(error.code(), "provider_failure");
    assert!(!error.to_string().contains("[]"));
}

#[test]
fn decoder_rejects_conflicting_tool_names_for_one_index() {
    let mut decoder = OpenAiStreamDecoder::new();
    decoder
        .push_data(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"search_text","arguments":"{}"}}]},"finish_reason":null}]}"#,
        )
        .unwrap();

    let error = decoder
        .push_data(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"replace_text_range"}}]},"finish_reason":"tool_calls"}]}"#,
        )
        .unwrap_err();

    assert_eq!(error.code(), "provider_failure");
    assert!(!error.to_string().contains("replace_text_range"));
}

#[test]
fn malformed_provider_frames_return_sanitized_errors() {
    let mut decoder = OpenAiStreamDecoder::new();
    let secret_frame = r#"{"authorization":"Bearer sk-secret","choices":["#;

    let error = decoder.push_data(secret_frame).unwrap_err();

    assert_eq!(error.code(), "provider_failure");
    assert!(!error.to_string().contains("sk-secret"));
    assert!(!error.to_string().contains("Bearer"));
}

#[test]
fn provider_error_objects_cannot_be_misread_as_empty_successes() {
    let mut decoder = OpenAiStreamDecoder::new();

    let error = decoder
        .push_data(
            r#"{"error":{"message":"Bearer sk-secret is invalid","type":"authentication_error"}}"#,
        )
        .unwrap_err();

    assert_eq!(error.code(), "provider_failure");
    assert!(!error.to_string().contains("sk-secret"));
    assert!(!error.to_string().contains("Bearer"));
}

#[test]
fn cancellation_stops_a_provider_before_its_next_delta() {
    let provider = ScriptedProvider {
        deltas: vec!["one".into(), "two".into()],
    };
    let token = CancellationToken::new();
    let mut sink = CancellingSink {
        token: token.clone(),
        received: Vec::new(),
    };

    let error = provider
        .complete(provider_request(), &token, &mut sink)
        .unwrap_err();

    assert_eq!(error, AgentError::Cancelled);
    assert_eq!(sink.received, vec!["one"]);
}

fn provider_request() -> ProviderRequest {
    ProviderRequest {
        messages: vec![ProviderMessage {
            role: ProviderRole::User,
            content: "Hello".into(),
            tool_call_id: None,
            tool_calls: vec![],
        }],
        tools: vec![],
        max_output_tokens: 100,
    }
}

struct ScriptedProvider {
    deltas: Vec<String>,
}

impl ModelProvider for ScriptedProvider {
    fn complete(
        &self,
        _request: ProviderRequest,
        cancellation: &CancellationToken,
        sink: &mut dyn ProviderEventSink,
    ) -> Result<ProviderCompletion, AgentError> {
        let mut text = String::new();
        for delta in &self.deltas {
            cancellation.check()?;
            sink.emit(ProviderEvent::TextDelta(delta.clone()))?;
            text.push_str(delta);
        }
        Ok(ProviderCompletion {
            text,
            tool_calls: vec![],
            usage: None,
        })
    }
}

struct CancellingSink {
    token: CancellationToken,
    received: Vec<String>,
}

impl ProviderEventSink for CancellingSink {
    fn emit(&mut self, event: ProviderEvent) -> Result<(), AgentError> {
        let ProviderEvent::TextDelta(text) = event;
        self.received.push(text);
        self.token.cancel();
        Ok(())
    }
}
