use clarix_pdf_oxide::chat_api::{parse_chat_sse_data, NativeChatEvent};

#[test]
fn chat_sse_emits_text_and_done_without_agent_or_tool_events() {
    assert_eq!(
        parse_chat_sse_data(r#"{"choices":[{"delta":{"content":"Hello"}}]}"#),
        Some(NativeChatEvent::TextDelta {
            text: "Hello".to_owned(),
        }),
    );
    assert_eq!(parse_chat_sse_data("[DONE]"), Some(NativeChatEvent::Done));
}
