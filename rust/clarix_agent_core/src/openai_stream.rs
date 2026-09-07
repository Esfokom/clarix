use std::collections::{BTreeMap, HashSet};

use serde_json::Value;

use crate::{AgentError, ProviderCompletion, ProviderEvent, ProviderToolCall, ProviderUsage};

#[derive(Default)]
struct ToolCallAccumulator {
    id: Option<String>,
    name: Option<String>,
    arguments: String,
}

#[derive(Default)]
pub struct OpenAiStreamDecoder {
    text: String,
    tool_calls: BTreeMap<u32, ToolCallAccumulator>,
    usage: Option<ProviderUsage>,
    done: bool,
}

impl OpenAiStreamDecoder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push_data(&mut self, frame: &str) -> Result<Vec<ProviderEvent>, AgentError> {
        if self.done {
            return Err(provider_error(
                "provider_stream_closed",
                "provider sent data after stream completion",
            ));
        }
        let payload = frame
            .strip_prefix("data:")
            .map_or(frame, str::trim_start)
            .trim();
        if payload.is_empty() {
            return Ok(Vec::new());
        }
        if payload == "[DONE]" {
            self.done = true;
            return Ok(Vec::new());
        }
        let value: Value = serde_json::from_str(payload).map_err(|_| {
            provider_error(
                "malformed_provider_stream",
                "provider returned malformed streaming JSON",
            )
        })?;
        let object = value.as_object().ok_or_else(|| {
            provider_error(
                "malformed_provider_stream",
                "provider stream frame must be a JSON object",
            )
        })?;
        if object.contains_key("error") {
            return Err(provider_error(
                "provider_response_error",
                "provider returned an error response",
            ));
        }
        let mut events = Vec::new();
        if let Some(choices) = object.get("choices") {
            let choices = choices.as_array().ok_or_else(|| {
                provider_error(
                    "malformed_provider_stream",
                    "provider choices must be an array",
                )
            })?;
            for choice in choices {
                let delta = choice
                    .get("delta")
                    .and_then(Value::as_object)
                    .ok_or_else(|| {
                        provider_error(
                            "malformed_provider_stream",
                            "provider choice is missing a delta object",
                        )
                    })?;
                if let Some(content) = delta.get("content").filter(|value| !value.is_null()) {
                    let content = content.as_str().ok_or_else(|| {
                        provider_error(
                            "malformed_provider_stream",
                            "provider text delta must be a string",
                        )
                    })?;
                    self.text.push_str(content);
                    events.push(ProviderEvent::TextDelta(content.to_owned()));
                } else if let Some(reasoning) = delta.get("reasoning_content").filter(|value| !value.is_null()) {
                    let reasoning = reasoning.as_str().ok_or_else(|| {
                        provider_error(
                            "malformed_provider_stream",
                            "provider reasoning delta must be a string",
                        )
                    })?;
                    self.text.push_str(reasoning);
                    events.push(ProviderEvent::TextDelta(reasoning.to_owned()));
                }
                if let Some(tool_calls) = delta.get("tool_calls") {
                    let tool_calls = tool_calls.as_array().ok_or_else(|| {
                        provider_error(
                            "malformed_provider_stream",
                            "provider tool call delta must be an array",
                        )
                    })?;
                    for tool_call in tool_calls {
                        self.push_tool_call(tool_call)?;
                    }
                }
            }
        }
        if let Some(usage) = object.get("usage").filter(|value| !value.is_null()) {
            self.usage = Some(parse_usage(usage)?);
        }
        Ok(events)
    }

    pub fn finish(self) -> Result<ProviderCompletion, AgentError> {
        let mut ids = HashSet::new();
        let mut tool_calls = Vec::with_capacity(self.tool_calls.len());
        for (_, call) in self.tool_calls {
            let id = call.id.ok_or_else(|| {
                provider_error(
                    "malformed_provider_tool_call",
                    "provider tool call is missing an ID",
                )
            })?;
            if !ids.insert(id.clone()) {
                return Err(provider_error(
                    "conflicting_provider_tool_call",
                    "provider repeated a tool call ID",
                ));
            }
            let name = call.name.ok_or_else(|| {
                provider_error(
                    "malformed_provider_tool_call",
                    "provider tool call is missing a name",
                )
            })?;
            let arguments = if call.arguments.trim().is_empty() {
                Value::Object(Default::default())
            } else {
                serde_json::from_str::<Value>(&call.arguments).map_err(|_| {
                    provider_error(
                        "malformed_provider_tool_call",
                        "provider tool arguments are not valid JSON",
                    )
                })?
            };
            if !arguments.is_object() {
                return Err(provider_error(
                    "malformed_provider_tool_call",
                    "provider tool arguments must be an object",
                ));
            }
            tool_calls.push(ProviderToolCall {
                id,
                name,
                arguments,
            });
        }
        Ok(ProviderCompletion {
            text: self.text,
            tool_calls,
            usage: self.usage,
        })
    }

    fn push_tool_call(&mut self, value: &Value) -> Result<(), AgentError> {
        let object = value.as_object().ok_or_else(|| {
            provider_error(
                "malformed_provider_stream",
                "provider tool call must be an object",
            )
        })?;
        let index = object
            .get("index")
            .and_then(Value::as_u64)
            .and_then(|index| u32::try_from(index).ok())
            .ok_or_else(|| {
                provider_error(
                    "malformed_provider_stream",
                    "provider tool call has an invalid index",
                )
            })?;
        let accumulator = self.tool_calls.entry(index).or_default();
        if let Some(id) = object.get("id").filter(|value| !value.is_null()) {
            merge_stable_field(&mut accumulator.id, id, "ID")?;
        }
        if let Some(function) = object.get("function").filter(|value| !value.is_null()) {
            let function = function.as_object().ok_or_else(|| {
                provider_error(
                    "malformed_provider_stream",
                    "provider tool function must be an object",
                )
            })?;
            if let Some(name) = function.get("name").filter(|value| !value.is_null()) {
                merge_stable_field(&mut accumulator.name, name, "name")?;
            }
            if let Some(arguments) = function.get("arguments").filter(|value| !value.is_null()) {
                let arguments = arguments.as_str().ok_or_else(|| {
                    provider_error(
                        "malformed_provider_stream",
                        "provider tool argument delta must be a string",
                    )
                })?;
                accumulator.arguments.push_str(arguments);
            }
        }
        Ok(())
    }
}

fn merge_stable_field(
    target: &mut Option<String>,
    value: &Value,
    field: &str,
) -> Result<(), AgentError> {
    let value = value.as_str().ok_or_else(|| {
        provider_error(
            "malformed_provider_stream",
            "provider tool call identity must be a string",
        )
    })?;
    match target {
        Some(existing) if existing != value => Err(provider_error(
            "conflicting_provider_tool_call",
            &format!("provider sent conflicting tool call {field}"),
        )),
        Some(_) => Ok(()),
        None => {
            *target = Some(value.to_owned());
            Ok(())
        }
    }
}

fn parse_usage(value: &Value) -> Result<ProviderUsage, AgentError> {
    let object = value.as_object().ok_or_else(|| {
        provider_error(
            "malformed_provider_stream",
            "provider usage must be an object",
        )
    })?;
    Ok(ProviderUsage {
        input_tokens: usage_count(object, "prompt_tokens")?,
        output_tokens: usage_count(object, "completion_tokens")?,
        total_tokens: usage_count(object, "total_tokens")?,
    })
}

fn usage_count(object: &serde_json::Map<String, Value>, field: &str) -> Result<u32, AgentError> {
    object
        .get(field)
        .and_then(Value::as_u64)
        .and_then(|count| u32::try_from(count).ok())
        .ok_or_else(|| {
            provider_error(
                "malformed_provider_stream",
                "provider usage contains an invalid token count",
            )
        })
}

fn provider_error(code: &str, message: &str) -> AgentError {
    AgentError::Provider {
        code: code.into(),
        message: message.into(),
    }
}
