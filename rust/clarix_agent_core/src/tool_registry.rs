use std::{collections::HashSet, str::FromStr};

use clarix_editing_core::{
    DocumentId, DocumentRevision, ObjectId, PageId, ProposedToolEdit, SearchMode, SelectionKind,
    SelectionSet, TextRangeRef, TextStyle,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

use crate::{AgentError, ProviderToolCall, ProviderToolDefinition};

#[derive(Debug, Clone)]
pub struct ToolValidationContext {
    pub active_document_id: DocumentId,
    pub active_revision: DocumentRevision,
    pub selection: Option<SelectionSet>,
    pub allowed_document_ids: HashSet<DocumentId>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToolScope {
    Read,
    Write,
    UiRequest,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToolRiskClass {
    ReadOnly,
    Preview,
    LocalMutation,
    BulkMutation,
    HistoryMutation,
    ExplicitSave,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToolApprovalRule {
    Automatic,
    Conditional,
    Required,
    ExplicitUiAction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToolRevisionBehavior {
    ExactRead,
    ExactWrite,
    PreviewOnly,
    UiOnly,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolManifest {
    pub name: String,
    pub version: u32,
    pub description: String,
    pub parameters: Value,
    pub scope: ToolScope,
    pub risk: ToolRiskClass,
    pub approval: ToolApprovalRule,
    pub reversible: bool,
    pub idempotent: bool,
    pub revision_behavior: ToolRevisionBehavior,
    pub supports_cancellation: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AffectedScope {
    pub range_count: u32,
    pub object_count: u32,
    pub bulk: bool,
}

impl AffectedScope {
    const NONE: Self = Self {
        range_count: 0,
        object_count: 0,
        bulk: false,
    };
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ToolExecution {
    InspectSelection {
        document_id: DocumentId,
        selection: SelectionSet,
        before_utf16: u32,
        after_utf16: u32,
        max_ranges: u32,
    },
    InspectTextObject {
        document_id: DocumentId,
        revision: DocumentRevision,
        object_id: ObjectId,
    },
    SearchText {
        document_id: DocumentId,
        revision: DocumentRevision,
        query: String,
        mode: SearchMode,
        whole_word: bool,
        offset: u32,
        limit: u32,
    },
    ProposeTextRewrite {
        document_id: DocumentId,
        selection: SelectionSet,
        replacement: String,
    },
    ReplaceTextRange {
        document_id: DocumentId,
        selection: SelectionSet,
        replacement: String,
    },
    PreviewReplaceAll {
        document_id: DocumentId,
        revision: DocumentRevision,
        query: String,
        replacement: String,
        mode: SearchMode,
        whole_word: bool,
    },
    CommitReplaceAll {
        document_id: DocumentId,
        revision: DocumentRevision,
        preview_id: String,
    },
    ApplyTextStyle {
        document_id: DocumentId,
        selection: SelectionSet,
        style: TextStyle,
    },
    PreviewTransaction {
        document_id: DocumentId,
        revision: DocumentRevision,
        edits: Vec<ProposedToolEdit>,
    },
    Undo {
        document_id: DocumentId,
        revision: DocumentRevision,
    },
    Redo {
        document_id: DocumentId,
        revision: DocumentRevision,
    },
    RequestSave {
        document_id: DocumentId,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ValidatedToolCall {
    pub provider_call_id: String,
    pub manifest: ToolManifest,
    pub execution: ToolExecution,
    pub affected: AffectedScope,
}

#[derive(Debug, Clone)]
pub struct ToolRegistry {
    manifests: Vec<ToolManifest>,
}

impl Default for ToolRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self {
            manifests: manifests(),
        }
    }

    pub fn definitions(&self) -> Vec<ProviderToolDefinition> {
        self.manifests
            .iter()
            .map(|manifest| ProviderToolDefinition {
                name: manifest.name.clone(),
                description: manifest.description.clone(),
                parameters: manifest.parameters.clone(),
            })
            .collect()
    }

    pub fn validate_call(
        &self,
        call: ProviderToolCall,
        context: &ToolValidationContext,
    ) -> Result<ValidatedToolCall, AgentError> {
        let manifest = self
            .manifests
            .iter()
            .find(|manifest| manifest.name == call.name)
            .cloned()
            .ok_or_else(|| AgentError::UnknownTool(call.name.clone()))?;
        let arguments = call.arguments.as_object().ok_or_else(|| {
            AgentError::InvalidToolArguments("tool arguments must be an object".into())
        })?;
        let document_id = validate_document(arguments, context)?;
        let execution = match manifest.name.as_str() {
            "inspect_selection" => {
                ensure_keys(
                    arguments,
                    &["document_id", "before_utf16", "after_utf16", "max_ranges"],
                    &["document_id"],
                )?;
                ToolExecution::InspectSelection {
                    document_id,
                    selection: active_selection(context)?,
                    before_utf16: optional_u32(arguments, "before_utf16", 512)?,
                    after_utf16: optional_u32(arguments, "after_utf16", 512)?,
                    max_ranges: optional_u32(arguments, "max_ranges", 8)?,
                }
            }
            "inspect_text_object" => {
                ensure_keys(
                    arguments,
                    &["document_id", "object_id"],
                    &["document_id", "object_id"],
                )?;
                ToolExecution::InspectTextObject {
                    document_id,
                    revision: context.active_revision,
                    object_id: parse_object_id(required_string(arguments, "object_id")?)?,
                }
            }
            "search_text" => {
                ensure_keys(
                    arguments,
                    &[
                        "document_id",
                        "query",
                        "mode",
                        "whole_word",
                        "offset",
                        "limit",
                    ],
                    &["document_id", "query"],
                )?;
                let query = required_string(arguments, "query")?.trim().to_owned();
                if query.is_empty() || query.len() > 4096 {
                    return Err(invalid("query must contain 1 to 4096 bytes"));
                }
                let limit = optional_u32(arguments, "limit", 20)?;
                if !(1..=200).contains(&limit) {
                    return Err(invalid("limit must be between 1 and 200"));
                }
                ToolExecution::SearchText {
                    document_id,
                    revision: context.active_revision,
                    query,
                    mode: parse_search_mode(
                        optional_string(arguments, "mode")?.unwrap_or("exact"),
                    )?,
                    whole_word: optional_bool(arguments, "whole_word", false)?,
                    offset: optional_u32(arguments, "offset", 0)?,
                    limit,
                }
            }
            "propose_text_rewrite" => {
                ensure_keys(
                    arguments,
                    &["document_id", "replacement"],
                    &["document_id", "replacement"],
                )?;
                ToolExecution::ProposeTextRewrite {
                    document_id,
                    selection: active_selection(context)?,
                    replacement: required_string(arguments, "replacement")?.to_owned(),
                }
            }
            "replace_text_range" => {
                ensure_keys(
                    arguments,
                    &["document_id", "replacement"],
                    &["document_id", "replacement"],
                )?;
                ToolExecution::ReplaceTextRange {
                    document_id,
                    selection: active_selection(context)?,
                    replacement: required_string(arguments, "replacement")?.to_owned(),
                }
            }
            "preview_replace_all" => {
                ensure_keys(
                    arguments,
                    &["document_id", "query", "replacement", "mode", "whole_word"],
                    &["document_id", "query", "replacement"],
                )?;
                ToolExecution::PreviewReplaceAll {
                    document_id,
                    revision: context.active_revision,
                    query: nonempty_string(arguments, "query")?,
                    replacement: required_string(arguments, "replacement")?.to_owned(),
                    mode: parse_search_mode(
                        optional_string(arguments, "mode")?.unwrap_or("exact"),
                    )?,
                    whole_word: optional_bool(arguments, "whole_word", false)?,
                }
            }
            "commit_replace_all" => {
                ensure_keys(
                    arguments,
                    &["document_id", "preview_id"],
                    &["document_id", "preview_id"],
                )?;
                ToolExecution::CommitReplaceAll {
                    document_id,
                    revision: context.active_revision,
                    preview_id: parse_uuid_string(
                        required_string(arguments, "preview_id")?,
                        "preview_id",
                    )?,
                }
            }
            "apply_text_style" => {
                ensure_keys(
                    arguments,
                    &["document_id", "style"],
                    &["document_id", "style"],
                )?;
                ToolExecution::ApplyTextStyle {
                    document_id,
                    selection: active_selection(context)?,
                    style: parse_style(required_object(arguments, "style")?)?,
                }
            }
            "preview_transaction" => {
                ensure_keys(
                    arguments,
                    &["document_id", "edits"],
                    &["document_id", "edits"],
                )?;
                ToolExecution::PreviewTransaction {
                    document_id,
                    revision: context.active_revision,
                    edits: parse_transaction_edits(arguments, context)?,
                }
            }
            "undo" => {
                ensure_keys(arguments, &["document_id"], &["document_id"])?;
                ToolExecution::Undo {
                    document_id,
                    revision: context.active_revision,
                }
            }
            "redo" => {
                ensure_keys(arguments, &["document_id"], &["document_id"])?;
                ToolExecution::Redo {
                    document_id,
                    revision: context.active_revision,
                }
            }
            "request_save" => {
                ensure_keys(arguments, &["document_id"], &["document_id"])?;
                ToolExecution::RequestSave { document_id }
            }
            _ => return Err(AgentError::UnknownTool(manifest.name.clone())),
        };
        let affected = affected_scope(&execution);
        Ok(ValidatedToolCall {
            provider_call_id: call.id,
            manifest,
            execution,
            affected,
        })
    }
}

fn affected_scope(execution: &ToolExecution) -> AffectedScope {
    let selection = match execution {
        ToolExecution::ProposeTextRewrite { selection, .. }
        | ToolExecution::ReplaceTextRange { selection, .. }
        | ToolExecution::ApplyTextStyle { selection, .. } => Some(selection),
        _ => None,
    };
    if let Some(selection) = selection {
        return selection_scope(selection, false);
    }
    match execution {
        ToolExecution::CommitReplaceAll { .. } => AffectedScope {
            range_count: 2,
            object_count: 2,
            bulk: true,
        },
        ToolExecution::PreviewTransaction { edits, .. } => {
            let mut ranges = 0_u32;
            let mut objects = HashSet::new();
            for edit in edits {
                let selection = match edit {
                    ProposedToolEdit::ReplaceText { selection, .. }
                    | ProposedToolEdit::SetTextStyle { selection, .. } => selection,
                };
                ranges = ranges.saturating_add(selection.ranges.len() as u32);
                objects.extend(selection.ranges.iter().map(|range| range.object_id));
            }
            AffectedScope {
                range_count: ranges,
                object_count: objects.len() as u32,
                bulk: true,
            }
        }
        _ => AffectedScope::NONE,
    }
}

fn selection_scope(selection: &SelectionSet, bulk: bool) -> AffectedScope {
    let object_count = selection
        .ranges
        .iter()
        .map(|range| range.object_id)
        .collect::<HashSet<_>>()
        .len() as u32;
    AffectedScope {
        range_count: selection.ranges.len() as u32,
        object_count,
        bulk,
    }
}

fn active_selection(context: &ToolValidationContext) -> Result<SelectionSet, AgentError> {
    let selection = context
        .selection
        .clone()
        .ok_or_else(|| invalid("tool requires an active selection"))?;
    if selection.revision != context.active_revision {
        return Err(invalid("active selection revision is stale"));
    }
    if selection.kind != SelectionKind::TextRanges || selection.ranges.is_empty() {
        return Err(invalid("tool requires a nonempty text selection"));
    }
    Ok(selection)
}

fn validate_document(
    arguments: &Map<String, Value>,
    context: &ToolValidationContext,
) -> Result<DocumentId, AgentError> {
    let raw = required_string(arguments, "document_id")?;
    let document_id =
        DocumentId::from_str(raw).map_err(|_| invalid("document_id must be a UUID"))?;
    if document_id != context.active_document_id
        || !context.allowed_document_ids.contains(&document_id)
    {
        return Err(AgentError::DocumentNotAllowed(document_id));
    }
    Ok(document_id)
}

fn parse_transaction_edits(
    arguments: &Map<String, Value>,
    context: &ToolValidationContext,
) -> Result<Vec<ProposedToolEdit>, AgentError> {
    let edits = arguments
        .get("edits")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("edits must be an array"))?;
    if edits.is_empty() || edits.len() > 100 {
        return Err(invalid("edits must contain between 1 and 100 items"));
    }
    edits
        .iter()
        .map(|value| {
            let edit = value
                .as_object()
                .ok_or_else(|| invalid("each edit must be an object"))?;
            let kind = required_string(edit, "type")?;
            let allowed = match kind {
                "replace_text" => vec![
                    "type",
                    "object_id",
                    "page_id",
                    "page_number",
                    "start_utf16",
                    "end_utf16",
                    "quoted_text",
                    "replacement",
                ],
                "set_text_style" => vec![
                    "type",
                    "object_id",
                    "page_id",
                    "page_number",
                    "start_utf16",
                    "end_utf16",
                    "quoted_text",
                    "style",
                ],
                _ => return Err(invalid("edit type must be replace_text or set_text_style")),
            };
            ensure_keys(edit, &allowed, &allowed)?;
            let start = required_u32(edit, "start_utf16")?;
            let end = required_u32(edit, "end_utf16")?;
            if end <= start {
                return Err(invalid("edit UTF-16 range must be nonempty and ordered"));
            }
            let selection = SelectionSet {
                revision: context.active_revision,
                kind: SelectionKind::TextRanges,
                ranges: vec![TextRangeRef {
                    object_id: parse_object_id(required_string(edit, "object_id")?)?,
                    page_id: parse_page_id(required_string(edit, "page_id")?)?,
                    page_number: required_u32(edit, "page_number")?,
                    start_utf16: start,
                    end_utf16: end,
                    quoted_text: nonempty_string(edit, "quoted_text")?,
                }],
                object_ids: vec![],
                primary_index: Some(0),
            };
            match kind {
                "replace_text" => Ok(ProposedToolEdit::ReplaceText {
                    selection,
                    replacement: required_string(edit, "replacement")?.to_owned(),
                }),
                "set_text_style" => Ok(ProposedToolEdit::SetTextStyle {
                    selection,
                    style: parse_style(required_object(edit, "style")?)?,
                }),
                _ => unreachable!("edit kind was validated"),
            }
        })
        .collect()
}

fn parse_style(style: &Map<String, Value>) -> Result<TextStyle, AgentError> {
    ensure_keys(
        style,
        &[
            "font_family",
            "font_size",
            "font_weight",
            "italic",
            "color_rgba",
        ],
        &["font_size", "font_weight", "italic", "color_rgba"],
    )?;
    let font_size = style
        .get("font_size")
        .and_then(Value::as_f64)
        .filter(|size| size.is_finite() && *size > 0.0)
        .ok_or_else(|| invalid("font_size must be finite and positive"))?;
    let font_weight = required_u32(style, "font_weight")?;
    if !(1..=1000).contains(&font_weight) {
        return Err(invalid("font_weight must be between 1 and 1000"));
    }
    let colors = style
        .get("color_rgba")
        .and_then(Value::as_array)
        .filter(|colors| colors.len() == 4)
        .ok_or_else(|| invalid("color_rgba must contain four bytes"))?;
    let mut color_rgba = [0_u8; 4];
    for (index, color) in colors.iter().enumerate() {
        color_rgba[index] = color
            .as_u64()
            .and_then(|value| u8::try_from(value).ok())
            .ok_or_else(|| invalid("color_rgba values must be bytes"))?;
    }
    let font_family = match style.get("font_family") {
        None | Some(Value::Null) => None,
        Some(Value::String(value)) if !value.trim().is_empty() => Some(value.trim().to_owned()),
        _ => return Err(invalid("font_family must be a nonempty string or null")),
    };
    Ok(TextStyle {
        font_family,
        font_size,
        font_weight: font_weight as u16,
        italic: style
            .get("italic")
            .and_then(Value::as_bool)
            .ok_or_else(|| invalid("italic must be a boolean"))?,
        color_rgba,
    })
}

fn manifests() -> Vec<ToolManifest> {
    vec![
        manifest(
            "inspect_selection",
            "Inspect the exact active selection.",
            document_schema(
                &[
                    ("before_utf16", integer_schema(0, 4096)),
                    ("after_utf16", integer_schema(0, 4096)),
                    ("max_ranges", integer_schema(1, 100)),
                ],
                &[],
            ),
            ToolScope::Read,
            ToolRiskClass::ReadOnly,
            ToolApprovalRule::Automatic,
            false,
            true,
            ToolRevisionBehavior::ExactRead,
        ),
        manifest(
            "inspect_text_object",
            "Inspect one stable text object.",
            document_schema(&[("object_id", uuid_schema())], &["object_id"]),
            ToolScope::Read,
            ToolRiskClass::ReadOnly,
            ToolApprovalRule::Automatic,
            false,
            true,
            ToolRevisionBehavior::ExactRead,
        ),
        manifest(
            "search_text",
            "Search canonical document text.",
            document_schema(
                &[
                    (
                        "query",
                        json!({"type":"string","minLength":1,"maxLength":4096}),
                    ),
                    (
                        "mode",
                        json!({"type":"string","enum":["exact","case_folded","normalized","regex"]}),
                    ),
                    ("whole_word", json!({"type":"boolean"})),
                    ("offset", integer_schema(0, u32::MAX)),
                    ("limit", integer_schema(1, 200)),
                ],
                &["query"],
            ),
            ToolScope::Read,
            ToolRiskClass::ReadOnly,
            ToolApprovalRule::Automatic,
            false,
            true,
            ToolRevisionBehavior::ExactRead,
        ),
        manifest(
            "propose_text_rewrite",
            "Preview replacement text for the active selection.",
            document_schema(
                &[("replacement", json!({"type":"string"}))],
                &["replacement"],
            ),
            ToolScope::Read,
            ToolRiskClass::Preview,
            ToolApprovalRule::Automatic,
            false,
            true,
            ToolRevisionBehavior::PreviewOnly,
        ),
        manifest(
            "replace_text_range",
            "Replace the exact active text selection.",
            document_schema(
                &[("replacement", json!({"type":"string"}))],
                &["replacement"],
            ),
            ToolScope::Write,
            ToolRiskClass::LocalMutation,
            ToolApprovalRule::Conditional,
            true,
            false,
            ToolRevisionBehavior::ExactWrite,
        ),
        manifest(
            "preview_replace_all",
            "Preview a deterministic document-wide replacement.",
            document_schema(
                &[
                    (
                        "query",
                        json!({"type":"string","minLength":1,"maxLength":4096}),
                    ),
                    ("replacement", json!({"type":"string"})),
                    (
                        "mode",
                        json!({"type":"string","enum":["exact","case_folded","normalized","regex"]}),
                    ),
                    ("whole_word", json!({"type":"boolean"})),
                ],
                &["query", "replacement"],
            ),
            ToolScope::Read,
            ToolRiskClass::Preview,
            ToolApprovalRule::Automatic,
            false,
            true,
            ToolRevisionBehavior::PreviewOnly,
        ),
        manifest(
            "commit_replace_all",
            "Request approval for a replace-all preview.",
            document_schema(&[("preview_id", uuid_schema())], &["preview_id"]),
            ToolScope::Write,
            ToolRiskClass::BulkMutation,
            ToolApprovalRule::Required,
            true,
            false,
            ToolRevisionBehavior::ExactWrite,
        ),
        manifest(
            "apply_text_style",
            "Apply an exact style to selected text.",
            document_schema(&[("style", style_schema())], &["style"]),
            ToolScope::Write,
            ToolRiskClass::LocalMutation,
            ToolApprovalRule::Conditional,
            true,
            false,
            ToolRevisionBehavior::ExactWrite,
        ),
        manifest(
            "preview_transaction",
            "Preview an atomic multi-edit transaction.",
            document_schema(&[("edits", transaction_edits_schema())], &["edits"]),
            ToolScope::Read,
            ToolRiskClass::Preview,
            ToolApprovalRule::Automatic,
            false,
            true,
            ToolRevisionBehavior::PreviewOnly,
        ),
        manifest(
            "undo",
            "Request undo of document history.",
            document_schema(&[], &[]),
            ToolScope::Write,
            ToolRiskClass::HistoryMutation,
            ToolApprovalRule::Required,
            true,
            false,
            ToolRevisionBehavior::ExactWrite,
        ),
        manifest(
            "redo",
            "Request redo of document history.",
            document_schema(&[], &[]),
            ToolScope::Write,
            ToolRiskClass::HistoryMutation,
            ToolApprovalRule::Required,
            true,
            false,
            ToolRevisionBehavior::ExactWrite,
        ),
        manifest(
            "request_save",
            "Focus the explicit Save user interface.",
            document_schema(&[], &[]),
            ToolScope::UiRequest,
            ToolRiskClass::ExplicitSave,
            ToolApprovalRule::ExplicitUiAction,
            false,
            true,
            ToolRevisionBehavior::UiOnly,
        ),
    ]
}

#[allow(clippy::too_many_arguments)]
fn manifest(
    name: &str,
    description: &str,
    parameters: Value,
    scope: ToolScope,
    risk: ToolRiskClass,
    approval: ToolApprovalRule,
    reversible: bool,
    idempotent: bool,
    revision_behavior: ToolRevisionBehavior,
) -> ToolManifest {
    ToolManifest {
        name: name.into(),
        version: 1,
        description: description.into(),
        parameters,
        scope,
        risk,
        approval,
        reversible,
        idempotent,
        revision_behavior,
        supports_cancellation: true,
    }
}

fn document_schema(extra: &[(&str, Value)], required: &[&str]) -> Value {
    let mut properties = Map::from_iter([("document_id".into(), uuid_schema())]);
    for (name, schema) in extra {
        properties.insert((*name).into(), schema.clone());
    }
    let mut required_fields = vec![Value::String("document_id".into())];
    required_fields.extend(required.iter().map(|field| Value::String((*field).into())));
    json!({
        "type": "object",
        "properties": properties,
        "required": required_fields,
        "additionalProperties": false
    })
}

fn uuid_schema() -> Value {
    json!({"type":"string","format":"uuid"})
}

fn integer_schema(minimum: u32, maximum: u32) -> Value {
    json!({"type":"integer","minimum":minimum,"maximum":maximum})
}

fn style_schema() -> Value {
    json!({
        "type":"object",
        "properties":{
            "font_family":{"type":["string","null"]},
            "font_size":{"type":"number","exclusiveMinimum":0},
            "font_weight":{"type":"integer","minimum":1,"maximum":1000},
            "italic":{"type":"boolean"},
            "color_rgba":{"type":"array","minItems":4,"maxItems":4,"items":{"type":"integer","minimum":0,"maximum":255}}
        },
        "required":["font_size","font_weight","italic","color_rgba"],
        "additionalProperties":false
    })
}

fn transaction_edits_schema() -> Value {
    let range_properties = Map::from_iter([
        ("object_id".into(), uuid_schema()),
        ("page_id".into(), uuid_schema()),
        ("page_number".into(), integer_schema(1, u32::MAX)),
        ("start_utf16".into(), integer_schema(0, u32::MAX)),
        ("end_utf16".into(), integer_schema(1, u32::MAX)),
        ("quoted_text".into(), json!({"type":"string","minLength":1})),
    ]);
    let edit_schema = |kind: &str, field: &str, field_schema: Value| {
        let mut properties = range_properties.clone();
        properties.insert("type".into(), json!({"const":kind}));
        properties.insert(field.into(), field_schema);
        json!({
            "type":"object",
            "properties": properties,
            "required":[
                "type", "object_id", "page_id", "page_number", "start_utf16",
                "end_utf16", "quoted_text", field
            ],
            "additionalProperties":false
        })
    };
    json!({
        "type":"array",
        "minItems":1,
        "maxItems":100,
        "items":{"oneOf":[
            edit_schema("replace_text", "replacement", json!({"type":"string"})),
            edit_schema("set_text_style", "style", style_schema())
        ]}
    })
}

fn ensure_keys(
    arguments: &Map<String, Value>,
    allowed: &[&str],
    required: &[&str],
) -> Result<(), AgentError> {
    if let Some(extra) = arguments
        .keys()
        .find(|key| !allowed.contains(&key.as_str()))
    {
        return Err(invalid(&format!("unexpected argument: {extra}")));
    }
    if let Some(missing) = required
        .iter()
        .find(|field| !arguments.contains_key(**field))
    {
        return Err(invalid(&format!("missing required argument: {missing}")));
    }
    Ok(())
}

fn required_string<'a>(
    arguments: &'a Map<String, Value>,
    field: &str,
) -> Result<&'a str, AgentError> {
    arguments
        .get(field)
        .and_then(Value::as_str)
        .ok_or_else(|| invalid(&format!("{field} must be a string")))
}

fn optional_string<'a>(
    arguments: &'a Map<String, Value>,
    field: &str,
) -> Result<Option<&'a str>, AgentError> {
    arguments
        .get(field)
        .map(|value| {
            value
                .as_str()
                .ok_or_else(|| invalid(&format!("{field} must be a string")))
        })
        .transpose()
}

fn nonempty_string(arguments: &Map<String, Value>, field: &str) -> Result<String, AgentError> {
    let value = required_string(arguments, field)?.trim();
    if value.is_empty() {
        return Err(invalid(&format!("{field} must not be empty")));
    }
    Ok(value.to_owned())
}

fn required_object<'a>(
    arguments: &'a Map<String, Value>,
    field: &str,
) -> Result<&'a Map<String, Value>, AgentError> {
    arguments
        .get(field)
        .and_then(Value::as_object)
        .ok_or_else(|| invalid(&format!("{field} must be an object")))
}

fn required_u32(arguments: &Map<String, Value>, field: &str) -> Result<u32, AgentError> {
    arguments
        .get(field)
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .ok_or_else(|| invalid(&format!("{field} must be a nonnegative 32-bit integer")))
}

fn optional_u32(
    arguments: &Map<String, Value>,
    field: &str,
    default: u32,
) -> Result<u32, AgentError> {
    arguments
        .get(field)
        .map(|_| required_u32(arguments, field))
        .unwrap_or(Ok(default))
}

fn optional_bool(
    arguments: &Map<String, Value>,
    field: &str,
    default: bool,
) -> Result<bool, AgentError> {
    arguments
        .get(field)
        .map(|value| {
            value
                .as_bool()
                .ok_or_else(|| invalid(&format!("{field} must be a boolean")))
        })
        .unwrap_or(Ok(default))
}

fn parse_search_mode(value: &str) -> Result<SearchMode, AgentError> {
    match value {
        "exact" => Ok(SearchMode::Exact),
        "case_folded" => Ok(SearchMode::CaseFolded),
        "normalized" => Ok(SearchMode::Normalized),
        "regex" => Ok(SearchMode::Regex),
        _ => Err(invalid(
            "mode must be exact, case_folded, normalized, or regex",
        )),
    }
}

fn parse_object_id(value: &str) -> Result<ObjectId, AgentError> {
    ObjectId::from_str(value).map_err(|_| invalid("object_id must be a UUID"))
}

fn parse_page_id(value: &str) -> Result<PageId, AgentError> {
    PageId::from_str(value).map_err(|_| invalid("page_id must be a UUID"))
}

fn parse_uuid_string(value: &str, field: &str) -> Result<String, AgentError> {
    uuid::Uuid::parse_str(value)
        .map(|uuid| uuid.hyphenated().to_string())
        .map_err(|_| invalid(&format!("{field} must be a UUID")))
}

fn invalid(message: &str) -> AgentError {
    AgentError::InvalidToolArguments(message.into())
}
