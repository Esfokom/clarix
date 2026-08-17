use serde::{Deserialize, Serialize};

use crate::{
    ActorKind, AtomicEdit, CommandEnvelope, CommandId, CommandResult, ContextLimits,
    DocumentObject, DocumentRevision, EditingError, EditorCommand, EditorSessionActor,
    EditorSessionState, ObjectId, ObjectKind, PageId, PdfBox, ProjectRepository, ReplaceAllPreview,
    SearchIndex, SearchMode, SearchPage, SearchRequest, SelectionContext, SelectionContextBuilder,
    SelectionKind, SelectionSet, TextRangeRef, TextRun, TextStyle, Utf16Range,
};

pub trait EditingToolGateway: Send + Sync + 'static {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError>;
}

impl EditingToolGateway for EditorSessionActor {
    fn invoke(&self, request: ToolRequest) -> Result<ToolObservation, EditingError> {
        self.invoke_agent_tool(request)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ProposedToolEdit {
    ReplaceText {
        selection: SelectionSet,
        replacement: String,
    },
    SetTextStyle {
        selection: SelectionSet,
        style: TextStyle,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolTransactionPreview {
    pub preview_id: String,
    pub revision: DocumentRevision,
    pub edits: Vec<ProposedToolEdit>,
    pub affected_object_ids: Vec<ObjectId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ToolRequest {
    InspectDocument {
        revision: DocumentRevision,
    },
    InspectSelection {
        selection: SelectionSet,
        limits: ContextLimits,
    },
    InspectTextObject {
        revision: DocumentRevision,
        object_id: ObjectId,
    },
    SearchText {
        revision: DocumentRevision,
        query: String,
        mode: SearchMode,
        whole_word: bool,
        offset: u32,
        limit: u32,
    },
    PreviewTextRewrite {
        selection: SelectionSet,
        replacement: String,
    },
    ReplaceTextRange {
        command_id: CommandId,
        selection: SelectionSet,
        replacement: String,
        provenance_ids: Vec<String>,
    },
    PreviewReplaceAll {
        revision: DocumentRevision,
        query: String,
        replacement: String,
        mode: SearchMode,
        whole_word: bool,
    },
    CommitReplaceAll {
        command_id: CommandId,
        preview_id: String,
        base_revision: DocumentRevision,
        provenance_ids: Vec<String>,
    },
    ApplyTextStyle {
        command_id: CommandId,
        selection: SelectionSet,
        style: TextStyle,
        provenance_ids: Vec<String>,
    },
    PreviewTransaction {
        revision: DocumentRevision,
        edits: Vec<ProposedToolEdit>,
    },
    CommitTransaction {
        command_id: CommandId,
        preview_id: String,
        base_revision: DocumentRevision,
        provenance_ids: Vec<String>,
    },
    Undo {
        command_id: CommandId,
        revision: DocumentRevision,
        provenance_ids: Vec<String>,
    },
    Redo {
        command_id: CommandId,
        revision: DocumentRevision,
        provenance_ids: Vec<String>,
    },
}

impl ToolRequest {
    pub const fn risk(&self) -> ToolRisk {
        match self {
            Self::InspectDocument { .. }
            | Self::InspectSelection { .. }
            | Self::InspectTextObject { .. }
            | Self::SearchText { .. } => ToolRisk::ReadOnly,
            Self::PreviewTextRewrite { .. }
            | Self::PreviewReplaceAll { .. }
            | Self::PreviewTransaction { .. } => ToolRisk::Preview,
            Self::ReplaceTextRange { selection, .. } | Self::ApplyTextStyle { selection, .. }
                if selection.ranges.len() == 1 =>
            {
                ToolRisk::ReversibleMutation
            }
            Self::ReplaceTextRange { .. }
            | Self::CommitReplaceAll { .. }
            | Self::ApplyTextStyle { .. }
            | Self::CommitTransaction { .. } => ToolRisk::BulkMutation,
            Self::Undo { .. } | Self::Redo { .. } => ToolRisk::HistoryMutation,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToolRisk {
    ReadOnly,
    Preview,
    ReversibleMutation,
    BulkMutation,
    HistoryMutation,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ObjectSummary {
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub kind: ObjectKind,
    pub bounds: PdfBox,
    pub text_preview: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextObjectObservation {
    pub revision: DocumentRevision,
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub bounds: PdfBox,
    pub text: String,
    pub runs: Vec<TextRun>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ToolObservation {
    Document {
        revision: DocumentRevision,
        page_count: u32,
        object_count: u32,
    },
    Selection {
        context: SelectionContext,
    },
    TextObject {
        object: TextObjectObservation,
    },
    Search {
        revision: DocumentRevision,
        matches: Vec<TextRangeRef>,
        total_matches: u32,
        indexed_pages: u32,
        page_count: u32,
        is_complete: bool,
    },
    RewritePreview {
        revision: DocumentRevision,
        selection: SelectionSet,
        replacement: String,
    },
    ReplaceAllPreview {
        preview: ReplaceAllPreview,
    },
    TransactionPreview {
        preview: ToolTransactionPreview,
    },
    Command {
        result: CommandResult,
    },
}

impl ToolObservation {
    pub const fn revision(&self) -> DocumentRevision {
        match self {
            Self::Document { revision, .. }
            | Self::Search { revision, .. }
            | Self::RewritePreview { revision, .. } => *revision,
            Self::Selection { context } => context.document_revision,
            Self::TextObject { object } => object.revision,
            Self::ReplaceAllPreview { preview } => preview.revision,
            Self::TransactionPreview { preview } => preview.revision,
            Self::Command { result } => result.committed_revision,
        }
    }
}

pub(crate) fn invoke_tool(
    session: &mut EditorSessionState,
    repository: Option<&dyn ProjectRepository>,
    request: ToolRequest,
) -> Result<ToolObservation, EditingError> {
    match request {
        ToolRequest::InspectDocument { revision } => {
            let model = revisioned_snapshot(session, revision)?;
            Ok(ToolObservation::Document {
                revision: model.revision,
                page_count: model.pages.len() as u32,
                object_count: model
                    .pages
                    .iter()
                    .map(|page| page.objects.len() as u32)
                    .sum(),
            })
        }
        ToolRequest::InspectSelection { selection, limits } => {
            let model = session.snapshot()?;
            Ok(ToolObservation::Selection {
                context: SelectionContextBuilder::build(&model, selection, limits)?,
            })
        }
        ToolRequest::InspectTextObject {
            revision,
            object_id,
        } => {
            let model = revisioned_snapshot(session, revision)?;
            let object = model
                .object(object_id)
                .ok_or(EditingError::ObjectNotFound(object_id))?;
            let DocumentObject::Text(text) = object else {
                return Err(EditingError::WrongObjectKind(object_id));
            };
            Ok(ToolObservation::TextObject {
                object: TextObjectObservation {
                    revision,
                    object_id,
                    page_id: object.page_id(),
                    bounds: object.bounds(),
                    text: text.text.clone(),
                    runs: text.runs.clone(),
                },
            })
        }
        ToolRequest::SearchText {
            revision,
            query,
            mode,
            whole_word,
            offset,
            limit,
        } => {
            if limit > 200 {
                return Err(EditingError::InvalidCommand(
                    "agent search limit must not exceed 200".into(),
                ));
            }
            let model = revisioned_snapshot(session, revision)?;
            let page = SearchIndex::from_document(&model)
                .search(SearchRequest {
                    query,
                    mode,
                    whole_word,
                    offset,
                    limit,
                })
                .map_err(|error| EditingError::InvalidCommand(error.to_string()))?;
            Ok(search_observation(page))
        }
        ToolRequest::PreviewTextRewrite {
            selection,
            replacement,
        } => {
            let selection = session.validate_selection(selection)?;
            ensure_text_selection(&selection)?;
            Ok(ToolObservation::RewritePreview {
                revision: selection.revision,
                selection,
                replacement,
            })
        }
        ToolRequest::ReplaceTextRange {
            command_id,
            selection,
            replacement,
            provenance_ids,
        } => {
            let selection = session.validate_selection(selection)?;
            let edits = replacement_edits(&selection, &replacement)?;
            let envelope =
                envelope_for_edits(command_id, selection.revision, edits, provenance_ids);
            commit_envelope(session, repository, envelope)
        }
        ToolRequest::PreviewReplaceAll {
            revision,
            query,
            replacement,
            mode,
            whole_word,
        } => {
            revisioned_snapshot(session, revision)?;
            let preview = session.preview_replace_all(
                SearchRequest {
                    query,
                    mode,
                    whole_word,
                    offset: 0,
                    limit: 500,
                },
                replacement,
            )?;
            Ok(ToolObservation::ReplaceAllPreview { preview })
        }
        ToolRequest::CommitReplaceAll {
            command_id,
            preview_id,
            base_revision,
            provenance_ids,
        } => {
            let prepared = session.prepare_replace_all(
                &preview_id,
                command_id,
                base_revision,
                ActorKind::Agent,
                provenance_ids,
            )?;
            commit_prepared(session, repository, prepared)
        }
        ToolRequest::ApplyTextStyle {
            command_id,
            selection,
            style,
            provenance_ids,
        } => {
            let selection = session.validate_selection(selection)?;
            let edits = style_edits(&selection, &style)?;
            let envelope =
                envelope_for_edits(command_id, selection.revision, edits, provenance_ids);
            commit_envelope(session, repository, envelope)
        }
        ToolRequest::PreviewTransaction { revision, edits } => {
            let preview = session.preview_tool_transaction(revision, edits)?;
            Ok(ToolObservation::TransactionPreview { preview })
        }
        ToolRequest::CommitTransaction {
            command_id,
            preview_id,
            base_revision,
            provenance_ids,
        } => {
            let prepared = session.prepare_tool_transaction(
                &preview_id,
                command_id,
                base_revision,
                provenance_ids,
            )?;
            commit_prepared(session, repository, prepared)
        }
        ToolRequest::Undo {
            command_id,
            revision,
            provenance_ids,
        } => commit_envelope(
            session,
            repository,
            agent_envelope(
                command_id,
                revision,
                None,
                provenance_ids,
                EditorCommand::Undo,
            ),
        ),
        ToolRequest::Redo {
            command_id,
            revision,
            provenance_ids,
        } => commit_envelope(
            session,
            repository,
            agent_envelope(
                command_id,
                revision,
                None,
                provenance_ids,
                EditorCommand::Redo,
            ),
        ),
    }
}

pub(crate) fn normalize_proposed_edits(
    session: &EditorSessionState,
    edits: Vec<ProposedToolEdit>,
) -> Result<Vec<ProposedToolEdit>, EditingError> {
    if edits.is_empty() {
        return Err(EditingError::InvalidCommand(
            "transaction preview must contain at least one edit".into(),
        ));
    }
    edits
        .into_iter()
        .map(|edit| match edit {
            ProposedToolEdit::ReplaceText {
                selection,
                replacement,
            } => {
                let selection = session.validate_selection(selection)?;
                ensure_text_selection(&selection)?;
                Ok(ProposedToolEdit::ReplaceText {
                    selection,
                    replacement,
                })
            }
            ProposedToolEdit::SetTextStyle { selection, style } => {
                let selection = session.validate_selection(selection)?;
                ensure_text_selection(&selection)?;
                Ok(ProposedToolEdit::SetTextStyle { selection, style })
            }
        })
        .collect()
}

pub(crate) fn proposed_atomic_edits(
    edits: &[ProposedToolEdit],
) -> Result<Vec<AtomicEdit>, EditingError> {
    let mut atomic = Vec::new();
    for edit in edits {
        match edit {
            ProposedToolEdit::ReplaceText {
                selection,
                replacement,
            } => atomic.extend(replacement_edits(selection, replacement)?),
            ProposedToolEdit::SetTextStyle { selection, style } => {
                atomic.extend(style_edits(selection, style)?)
            }
        }
    }
    Ok(atomic)
}

fn replacement_edits(
    selection: &SelectionSet,
    replacement: &str,
) -> Result<Vec<AtomicEdit>, EditingError> {
    ensure_text_selection(selection)?;
    Ok(selection
        .ranges
        .iter()
        .rev()
        .map(|range| AtomicEdit::ReplaceTextRange {
            object_id: range.object_id,
            range: Utf16Range::new(range.start_utf16, range.end_utf16)
                .expect("validated selection ranges are ordered"),
            replacement: replacement.to_owned(),
        })
        .collect())
}

fn style_edits(
    selection: &SelectionSet,
    style: &TextStyle,
) -> Result<Vec<AtomicEdit>, EditingError> {
    ensure_text_selection(selection)?;
    Ok(selection
        .ranges
        .iter()
        .map(|range| AtomicEdit::SetTextStyle {
            object_id: range.object_id,
            range: Utf16Range::new(range.start_utf16, range.end_utf16)
                .expect("validated selection ranges are ordered"),
            style: style.clone(),
        })
        .collect())
}

fn ensure_text_selection(selection: &SelectionSet) -> Result<(), EditingError> {
    if selection.kind != SelectionKind::TextRanges || selection.ranges.is_empty() {
        return Err(EditingError::InvalidCommand(
            "text tool requires a nonempty text-range selection".into(),
        ));
    }
    Ok(())
}

fn envelope_for_edits(
    command_id: CommandId,
    revision: DocumentRevision,
    mut edits: Vec<AtomicEdit>,
    provenance_ids: Vec<String>,
) -> CommandEnvelope {
    if edits.len() == 1 {
        let payload = edits
            .pop()
            .expect("single-edit envelope has exactly one edit")
            .as_command();
        agent_envelope(command_id, revision, None, provenance_ids, payload)
    } else {
        agent_envelope(
            command_id,
            revision,
            Some(uuid::Uuid::new_v4().to_string()),
            provenance_ids,
            EditorCommand::ApplyTransaction { edits },
        )
    }
}

pub(crate) fn agent_envelope(
    command_id: CommandId,
    base_revision: DocumentRevision,
    transaction_id: Option<String>,
    provenance_ids: Vec<String>,
    payload: EditorCommand,
) -> CommandEnvelope {
    CommandEnvelope {
        command_id,
        base_revision,
        transaction_id,
        actor: ActorKind::Agent,
        provenance_ids,
        typing_group: None,
        payload,
    }
}

fn revisioned_snapshot(
    session: &EditorSessionState,
    revision: DocumentRevision,
) -> Result<crate::DocumentModel, EditingError> {
    let model = session.snapshot()?;
    if model.revision != revision {
        return Err(EditingError::RevisionConflict {
            expected: revision,
            actual: model.revision,
        });
    }
    Ok(model)
}

fn search_observation(page: SearchPage) -> ToolObservation {
    ToolObservation::Search {
        revision: page.revision,
        matches: page.matches,
        total_matches: page.total_matches,
        indexed_pages: page.indexed_pages,
        page_count: page.page_count,
        is_complete: page.is_complete,
    }
}

fn commit_envelope(
    session: &mut EditorSessionState,
    repository: Option<&dyn ProjectRepository>,
    envelope: CommandEnvelope,
) -> Result<ToolObservation, EditingError> {
    let prepared = session.prepare(envelope)?;
    commit_prepared(session, repository, prepared)
}

fn commit_prepared(
    session: &mut EditorSessionState,
    repository: Option<&dyn ProjectRepository>,
    prepared: crate::PreparedCommand,
) -> Result<ToolObservation, EditingError> {
    if let Some(repository) = repository {
        repository
            .append(&crate::DurableCommit::from_prepared(&prepared))
            .map_err(|error| EditingError::SidecarCommitFailed(error.to_string()))?;
    }
    let mut result = session.publish(prepared)?;
    result.durable = repository.is_some();
    Ok(ToolObservation::Command { result })
}
