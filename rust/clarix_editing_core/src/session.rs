use std::collections::{HashMap, HashSet};
use unicode_segmentation::UnicodeSegmentation;

use crate::history::{can_coalesce, HistoryEntry};
use crate::text::utf16_range_to_byte_range;
use crate::{
    AffineTransform, AtomicEdit, CommandEnvelope, CommandId, CommandResult, DocumentModel,
    DocumentObject, DocumentRevision, EditCapability, EditingError, EditorCommand, FontSource,
    InverseOperation, ObjectId, ObjectPatch, OverflowPolicy, PageNode, PdfBox, PreparedCommand,
    ProposedToolEdit, RecoveredCommand, ReplaceAllPreview, SearchIndex, SearchRequest,
    SelectionRebase, SelectionSet, SessionId, TextCharacterBox, TextRun, ToolTransactionPreview,
    Utf16Range, WritingDirection,
};

#[derive(Debug, Clone)]
pub struct EditorSessionState {
    session_id: SessionId,
    model: DocumentModel,
    committed_commands: HashSet<CommandId>,
    undo_stack: Vec<HistoryEntry>,
    redo_stack: Vec<HistoryEntry>,
    replace_previews: HashMap<String, ReplaceAllPreview>,
    tool_transaction_previews: HashMap<String, ToolTransactionPreview>,
    closed: bool,
}

impl EditorSessionState {
    pub fn new(session_id: SessionId, model: DocumentModel) -> Self {
        Self {
            session_id,
            model,
            committed_commands: HashSet::new(),
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            replace_previews: HashMap::new(),
            tool_transaction_previews: HashMap::new(),
            closed: false,
        }
    }

    pub(crate) fn from_recovered(
        session_id: SessionId,
        model: DocumentModel,
        commands: Vec<RecoveredCommand>,
    ) -> Result<Self, EditingError> {
        let model_revision = model.revision;
        let mut state = Self::new(session_id, model);
        let mut expected_revision = DocumentRevision::INITIAL;
        for command in commands {
            if command.previous_revision != expected_revision
                || command.envelope.base_revision != expected_revision
                || command.committed_revision
                    != expected_revision
                        .next()
                        .map_err(|_| EditingError::RevisionOverflow)?
            {
                return Err(EditingError::SidecarCommitFailed(
                    "recovered command revisions are not contiguous".into(),
                ));
            }
            if !state.committed_commands.insert(command.envelope.command_id) {
                return Err(EditingError::SidecarCommitFailed(
                    "recovered command ID is duplicated".into(),
                ));
            }
            match &command.envelope.payload {
                EditorCommand::Undo => {
                    let entry = state.undo_stack.pop().ok_or_else(|| {
                        EditingError::SidecarCommitFailed(
                            "recovered undo has no matching history entry".into(),
                        )
                    })?;
                    state.redo_stack.push(entry);
                }
                EditorCommand::Redo => {
                    let entry = state.redo_stack.pop().ok_or_else(|| {
                        EditingError::SidecarCommitFailed(
                            "recovered redo has no matching history entry".into(),
                        )
                    })?;
                    state.undo_stack.push(entry);
                }
                EditorCommand::CreateCheckpoint { label } => {
                    state.undo_stack.push(HistoryEntry::Checkpoint {
                        label: label.clone(),
                    });
                    state.redo_stack.clear();
                }
                EditorCommand::ApplyTransaction { .. } => {
                    if command.before_objects.is_empty()
                        || command.before_objects.len() != command.after_objects.len()
                    {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered transaction has invalid object state".into(),
                        ));
                    }
                    state.undo_stack.push(HistoryEntry::Objects {
                        before: command.before_objects,
                        after: command.after_objects,
                    });
                    state.redo_stack.clear();
                }
                EditorCommand::CreateAnnotation { .. } => {
                    let [] = command.before_objects.as_slice() else {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered annotation creation has invalid before state".into(),
                        ));
                    };
                    let [after] = command.after_objects.as_slice() else {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered annotation creation has invalid after state".into(),
                        ));
                    };
                    state.undo_stack.push(HistoryEntry::Inserted {
                        object: Box::new(after.clone()),
                    });
                    state.redo_stack.clear();
                }
                EditorCommand::DeleteAnnotation { .. } => {
                    let [before] = command.before_objects.as_slice() else {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered annotation deletion has invalid before state".into(),
                        ));
                    };
                    let [] = command.after_objects.as_slice() else {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered annotation deletion has invalid after state".into(),
                        ));
                    };
                    state.undo_stack.push(HistoryEntry::Deleted {
                        object: Box::new(before.clone()),
                    });
                    state.redo_stack.clear();
                }
                _ => {
                    let [before] = command.before_objects.as_slice() else {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered object command has invalid before state".into(),
                        ));
                    };
                    let [after] = command.after_objects.as_slice() else {
                        return Err(EditingError::SidecarCommitFailed(
                            "recovered object command has invalid after state".into(),
                        ));
                    };
                    let typing = command.envelope.typing_group.clone();
                    if matches!(
                        command.envelope.payload,
                        EditorCommand::ReplaceTextRange { .. }
                    ) && state
                        .undo_stack
                        .last()
                        .is_some_and(|previous| can_coalesce(previous, before, typing.as_ref()))
                    {
                        if let Some(HistoryEntry::Object {
                            after: previous_after,
                            typing: previous_typing,
                            ..
                        }) = state.undo_stack.last_mut()
                        {
                            **previous_after = after.clone();
                            *previous_typing = typing;
                        }
                    } else {
                        state.undo_stack.push(HistoryEntry::Object {
                            before: Box::new(before.clone()),
                            after: Box::new(after.clone()),
                            typing,
                        });
                    }
                    state.redo_stack.clear();
                }
            }
            expected_revision = command.committed_revision;
        }
        if expected_revision != model_revision {
            return Err(EditingError::SidecarCommitFailed(
                "recovered journal does not reach the model revision".into(),
            ));
        }
        Ok(state)
    }

    pub(crate) fn undo_cursor(&self) -> u64 {
        self.undo_stack.len() as u64
    }

    pub fn session_id(&self) -> SessionId {
        self.session_id
    }

    pub fn revision(&self) -> DocumentRevision {
        self.model.revision
    }

    pub fn snapshot(&self) -> Result<DocumentModel, EditingError> {
        self.ensure_open()?;
        Ok(self.model.clone())
    }

    pub fn text(&self, object_id: ObjectId) -> Result<&str, EditingError> {
        self.ensure_open()?;
        match self.model.object(object_id) {
            Some(DocumentObject::Text(block)) => Ok(&block.text),
            Some(_) => Err(EditingError::WrongObjectKind(object_id)),
            None => Err(EditingError::ObjectNotFound(object_id)),
        }
    }

    pub fn prepare(&self, envelope: CommandEnvelope) -> Result<PreparedCommand, EditingError> {
        self.ensure_open()?;
        let before_model = self.model.clone();
        let previous_revision = self.revision();
        let mut next_state = self.clone();
        let result = next_state.apply_envelope(envelope.clone())?;
        let (before_objects, after_objects) = changed_objects(&before_model, &next_state.model);
        let inverse = if before_objects.is_empty() && !after_objects.is_empty() {
            InverseOperation::RemoveObjects(after_objects.iter().map(DocumentObject::id).collect())
        } else if before_objects.is_empty() {
            InverseOperation::Checkpoint
        } else {
            InverseOperation::ReplaceObjects(before_objects.clone())
        };
        let physical_plan = physical_plan_from_changes(
            previous_revision,
            result.committed_revision,
            &before_objects,
            &after_objects,
        );
        Ok(PreparedCommand {
            envelope,
            previous_revision,
            committed_revision: result.committed_revision,
            before_objects,
            after_objects,
            inverse,
            physical_plan,
            result,
            next_state: Box::new(next_state),
        })
    }

    pub fn publish(&mut self, prepared: PreparedCommand) -> Result<CommandResult, EditingError> {
        self.ensure_open()?;
        if prepared.previous_revision != self.revision() {
            return Err(EditingError::RevisionConflict {
                expected: prepared.previous_revision,
                actual: self.revision(),
            });
        }
        if self
            .committed_commands
            .contains(&prepared.envelope.command_id)
        {
            return Err(EditingError::DuplicateCommand);
        }
        let result = prepared.result.clone();
        *self = *prepared.next_state;
        Ok(result)
    }

    pub fn submit(&mut self, envelope: CommandEnvelope) -> Result<CommandResult, EditingError> {
        let prepared = self.prepare(envelope)?;
        self.publish(prepared)
    }

    pub fn preview_replace_all(
        &mut self,
        request: SearchRequest,
        replacement: impl Into<String>,
    ) -> Result<ReplaceAllPreview, EditingError> {
        self.ensure_open()?;
        let matches = SearchIndex::from_document(&self.model)
            .all_matches(&request)
            .map_err(|error| EditingError::InvalidCommand(error.to_string()))?;
        if matches.is_empty() {
            return Err(EditingError::InvalidCommand(
                "replace-all query has no matches".into(),
            ));
        }
        let preview = ReplaceAllPreview {
            preview_id: uuid::Uuid::new_v4().to_string(),
            revision: self.revision(),
            replacement: replacement.into(),
            matches,
        };
        self.replace_previews
            .insert(preview.preview_id.clone(), preview.clone());
        Ok(preview)
    }

    pub fn approve_replace_all(
        &mut self,
        preview_id: &str,
        command_id: CommandId,
        base_revision: DocumentRevision,
    ) -> Result<CommandResult, EditingError> {
        let prepared = self.prepare_replace_all(
            preview_id,
            command_id,
            base_revision,
            crate::ActorKind::User,
            Vec::new(),
        )?;
        self.publish(prepared)
    }

    pub fn prepare_replace_all(
        &self,
        preview_id: &str,
        command_id: CommandId,
        base_revision: DocumentRevision,
        actor: crate::ActorKind,
        provenance_ids: Vec<String>,
    ) -> Result<PreparedCommand, EditingError> {
        self.ensure_open()?;
        let preview = self
            .replace_previews
            .get(preview_id)
            .cloned()
            .ok_or_else(|| {
                EditingError::InvalidCommand("replace-all preview is unavailable".into())
            })?;
        if base_revision != self.revision() || preview.revision != base_revision {
            return Err(EditingError::RevisionConflict {
                expected: base_revision,
                actual: self.revision(),
            });
        }
        let edits = preview
            .matches
            .iter()
            .rev()
            .map(|matched| AtomicEdit::ReplaceTextRange {
                object_id: matched.object_id,
                range: Utf16Range::new(matched.start_utf16, matched.end_utf16)
                    .expect("search ranges are ordered"),
                replacement: preview.replacement.clone(),
            })
            .collect();
        self.prepare(CommandEnvelope {
            command_id,
            base_revision,
            transaction_id: Some(preview.preview_id),
            actor,
            provenance_ids,
            typing_group: None,
            payload: EditorCommand::ApplyTransaction { edits },
        })
    }

    pub fn preview_tool_transaction(
        &mut self,
        revision: DocumentRevision,
        edits: Vec<ProposedToolEdit>,
    ) -> Result<ToolTransactionPreview, EditingError> {
        self.ensure_open()?;
        if revision != self.revision() {
            return Err(EditingError::RevisionConflict {
                expected: revision,
                actual: self.revision(),
            });
        }
        let edits = crate::tools::normalize_proposed_edits(self, edits)?;
        let atomic_edits = crate::tools::proposed_atomic_edits(&edits)?;
        let preview_id = uuid::Uuid::new_v4().to_string();
        self.prepare(CommandEnvelope {
            command_id: CommandId::new(),
            base_revision: revision,
            transaction_id: Some(preview_id.clone()),
            actor: crate::ActorKind::Agent,
            provenance_ids: Vec::new(),
            typing_group: None,
            payload: EditorCommand::ApplyTransaction {
                edits: atomic_edits,
            },
        })?;
        let mut affected_object_ids = edits
            .iter()
            .flat_map(|edit| match edit {
                ProposedToolEdit::ReplaceText { selection, .. }
                | ProposedToolEdit::SetTextStyle { selection, .. } => selection
                    .ranges
                    .iter()
                    .map(|range| range.object_id)
                    .collect::<Vec<_>>(),
            })
            .collect::<Vec<_>>();
        affected_object_ids.sort_by_key(ToString::to_string);
        affected_object_ids.dedup();
        let preview = ToolTransactionPreview {
            preview_id,
            revision,
            edits,
            affected_object_ids,
        };
        self.tool_transaction_previews
            .insert(preview.preview_id.clone(), preview.clone());
        Ok(preview)
    }

    pub fn prepare_tool_transaction(
        &self,
        preview_id: &str,
        command_id: CommandId,
        base_revision: DocumentRevision,
        provenance_ids: Vec<String>,
    ) -> Result<PreparedCommand, EditingError> {
        self.ensure_open()?;
        let preview = self
            .tool_transaction_previews
            .get(preview_id)
            .ok_or_else(|| {
                EditingError::InvalidCommand("transaction preview is unavailable".into())
            })?;
        if base_revision != self.revision() || preview.revision != base_revision {
            return Err(EditingError::RevisionConflict {
                expected: base_revision,
                actual: self.revision(),
            });
        }
        let edits = crate::tools::proposed_atomic_edits(&preview.edits)?;
        self.prepare(crate::tools::agent_envelope(
            command_id,
            base_revision,
            Some(preview.preview_id.clone()),
            provenance_ids,
            EditorCommand::ApplyTransaction { edits },
        ))
    }

    pub fn validate_selection(
        &self,
        selection: SelectionSet,
    ) -> Result<SelectionSet, EditingError> {
        self.ensure_open()?;
        crate::selection::validate_selection(&self.model, selection)
    }

    pub(crate) fn hydrate_page(
        &mut self,
        page: PageNode,
        expected_revision: DocumentRevision,
    ) -> Result<(), EditingError> {
        self.ensure_open()?;
        if expected_revision != self.revision() {
            return Err(EditingError::RevisionConflict {
                expected: expected_revision,
                actual: self.revision(),
            });
        }
        self.model
            .hydrate_page(page)
            .map_err(|error| EditingError::InvalidCommand(error.to_string()))
    }

    pub fn close(&mut self) {
        self.closed = true;
    }

    fn ensure_open(&self) -> Result<(), EditingError> {
        if self.closed {
            Err(EditingError::SessionClosed)
        } else {
            Ok(())
        }
    }

    fn apply_envelope(&mut self, envelope: CommandEnvelope) -> Result<CommandResult, EditingError> {
        if envelope.base_revision != self.revision() {
            return Err(EditingError::RevisionConflict {
                expected: envelope.base_revision,
                actual: self.revision(),
            });
        }
        if self.committed_commands.contains(&envelope.command_id) {
            return Err(EditingError::DuplicateCommand);
        }
        let previous_revision = self.revision();
        let next_revision = previous_revision
            .next()
            .map_err(|_| EditingError::RevisionOverflow)?;
        let selection_rebase = match &envelope.payload {
            EditorCommand::ReplaceTextRange {
                object_id,
                range,
                replacement,
            }
            | EditorCommand::ReplaceTextRangeWithFontFallback {
                object_id,
                range,
                replacement,
                ..
            } => Some(SelectionRebase {
                object_id: *object_id,
                replaced_range: *range,
                inserted_utf16_length: replacement.encode_utf16().count() as u32,
            }),
            _ => None,
        };
        let mut removed_object_ids = Vec::new();
        let object_patches = match &envelope.payload {
            EditorCommand::Undo => self.apply_undo(next_revision)?,
            EditorCommand::Redo => self.apply_redo(next_revision)?,
            EditorCommand::CreateCheckpoint { label } => {
                if label.trim().is_empty() {
                    return Err(EditingError::InvalidCommand(
                        "checkpoint label must not be empty".into(),
                    ));
                }
                self.undo_stack.push(HistoryEntry::Checkpoint {
                    label: label.clone(),
                });
                self.redo_stack.clear();
                Vec::new()
            }
            EditorCommand::ApplyTransaction { edits } => {
                let transaction_id = envelope.transaction_id.as_deref().ok_or_else(|| {
                    EditingError::InvalidCommand(
                        "transaction commands require a transaction ID".into(),
                    )
                })?;
                if uuid::Uuid::parse_str(transaction_id).is_err() {
                    return Err(EditingError::InvalidCommand(
                        "transaction ID must be a UUID".into(),
                    ));
                }
                if edits.is_empty() {
                    return Err(EditingError::InvalidCommand(
                        "transaction must contain at least one edit".into(),
                    ));
                }
                let before_model = self.model.clone();
                let undo_len = self.undo_stack.len();
                for edit in edits {
                    self.apply_object_command(&edit.as_command(), next_revision, None)?;
                }
                self.undo_stack.truncate(undo_len);
                let (before_objects, after_objects) = changed_objects(&before_model, &self.model);
                if before_objects.is_empty() {
                    return Err(EditingError::InvalidCommand(
                        "transaction did not change any object".into(),
                    ));
                }
                let object_patches = before_objects
                    .iter()
                    .zip(&after_objects)
                    .map(|(before, after)| object_patch(before, after, next_revision))
                    .collect();
                self.undo_stack.push(HistoryEntry::Objects {
                    before: before_objects,
                    after: after_objects,
                });
                self.redo_stack.clear();
                object_patches
            }
            EditorCommand::CreateAnnotation { annotation } => {
                let mut object = DocumentObject::Annotation(annotation.clone());
                if self.model.object(object.id()).is_some() {
                    return Err(EditingError::InvalidCommand(
                        "annotation ID already exists in the document".into(),
                    ));
                }
                object.set_modified_revision(next_revision);
                self.model
                    .insert_object(object.clone())
                    .map_err(|error| EditingError::InvalidCommand(error.to_string()))?;
                self.undo_stack.push(HistoryEntry::Inserted {
                    object: Box::new(object.clone()),
                });
                self.redo_stack.clear();
                vec![created_object_patch(&object, next_revision)]
            }
            EditorCommand::DeleteAnnotation { object_id } => {
                let existing = self
                    .model
                    .object(*object_id)
                    .cloned()
                    .ok_or(EditingError::ObjectNotFound(*object_id))?;
                if !matches!(existing, DocumentObject::Annotation(_)) {
                    return Err(EditingError::WrongObjectKind(*object_id));
                }
                let removed = self
                    .model
                    .remove_object(*object_id)
                    .map_err(|_| EditingError::ObjectNotFound(*object_id))?;
                self.undo_stack.push(HistoryEntry::Deleted {
                    object: Box::new(removed),
                });
                self.redo_stack.clear();
                removed_object_ids.push(*object_id);
                Vec::new()
            }
            command => {
                self.apply_object_command(command, next_revision, envelope.typing_group.as_ref())?
            }
        };
        self.model.set_revision(next_revision);
        self.committed_commands.insert(envelope.command_id);
        self.replace_previews.clear();
        Ok(CommandResult {
            command_id: envelope.command_id,
            previous_revision,
            committed_revision: next_revision,
            object_patches,
            removed_object_ids,
            selection_rebase,
            warnings: Vec::new(),
            durable: false,
        })
    }

    fn apply_object_command(
        &mut self,
        command: &EditorCommand,
        revision: DocumentRevision,
        typing: Option<&crate::TypingGroup>,
    ) -> Result<Vec<ObjectPatch>, EditingError> {
        let object_id = command_object_id(command).ok_or_else(|| {
            EditingError::InvalidCommand("command does not target an object".into())
        })?;
        let before = self
            .model
            .object(object_id)
            .cloned()
            .ok_or(EditingError::ObjectNotFound(object_id))?;
        if before.capability() != EditCapability::Editable {
            return Err(EditingError::ReadOnly(object_id));
        }
        let mut after = before.clone();
        let object_bounds = after.bounds();
        let mut expanded_text_bounds = None;
        match command {
            EditorCommand::ReplaceTextRange { .. }
            | EditorCommand::ReplaceTextRangeWithFontFallback { .. } => {
                let (range, replacement, fallback) = match command {
                    EditorCommand::ReplaceTextRange {
                        range, replacement, ..
                    } => (range, replacement, None),
                    EditorCommand::ReplaceTextRangeWithFontFallback {
                        range,
                        replacement,
                        approval,
                        ..
                    } => (range, replacement, Some(approval.as_ref())),
                    _ => unreachable!("replace arm must contain a replace command"),
                };
                let DocumentObject::Text(block) = &mut after else {
                    return Err(EditingError::WrongObjectKind(object_id));
                };
                let byte_range = utf16_range_to_byte_range(&block.text, *range)
                    .map_err(|_| EditingError::InvalidTextBoundary)?;
                let mut candidate = block.text.clone();
                candidate.replace_range(byte_range, replacement);
                if let Some(approval) = fallback {
                    let valid_font = approval.font.is_valid()
                        && approval.font.embeddable
                        && approval.font.source == FontSource::ApprovedFallback
                        && approval
                            .font
                            .asset_id
                            .as_deref()
                            .is_some_and(|asset| !asset.trim().is_empty());
                    let glyphs_cover_candidate = !approval.glyphs.is_empty()
                        && candidate.chars().all(|character| {
                            approval
                                .glyphs
                                .iter()
                                .any(|glyph| glyph.character_code == character as u32)
                        });
                    if approval.proposal_token.trim().is_empty()
                        || !valid_font
                        || !glyphs_cover_candidate
                    {
                        return Err(EditingError::InvalidCommand(
                            "font fallback approval is invalid or incomplete".into(),
                        ));
                    }
                    for run in &mut block.runs {
                        run.style.font_family = Some(approval.font.postscript_name.clone());
                    }
                    block.font = Some(approval.font.clone());
                    block.source_glyphs = approval.glyphs.clone();
                }
                if block.font.is_some() && !block.source_glyphs.is_empty() {
                    let mut affected_characters = String::new();
                    for character in candidate.chars().filter(|character| {
                        !block
                            .source_glyphs
                            .iter()
                            .any(|glyph| glyph.character_code == *character as u32)
                    }) {
                        if !affected_characters.contains(character) {
                            affected_characters.push(character);
                        }
                    }
                    if !affected_characters.is_empty() {
                        return Err(EditingError::FontFallbackRequired {
                            object_id,
                            affected_characters,
                        });
                    }
                }
                let capacity_graphemes = block.layout_capacity_graphemes as usize;
                let required_graphemes = candidate.graphemes(true).count();
                let layout_bounds =
                    if capacity_graphemes > 0 && required_graphemes > capacity_graphemes {
                        match block.layout.overflow {
                            OverflowPolicy::Reject => {
                                return Err(EditingError::TextOverflow {
                                    object_id,
                                    required_graphemes,
                                    capacity_graphemes,
                                });
                            }
                            OverflowPolicy::IncreaseBounds => {
                                let expanded = expand_text_bounds(
                                    object_bounds,
                                    block.layout.direction,
                                    required_graphemes as f64 / capacity_graphemes as f64,
                                );
                                expanded_text_bounds = Some(expanded);
                                block.layout_capacity_graphemes = required_graphemes as u32;
                                expanded
                            }
                        }
                    } else {
                        object_bounds
                    };
                block.text = candidate;
                block.character_boxes =
                    reflow_character_boxes(&block.text, layout_bounds, block.layout.direction);
                let full_range = Utf16Range::new(0, block.text.encode_utf16().count() as u32)
                    .map_err(|_| EditingError::InvalidTextBoundary)?;
                let style = block
                    .runs
                    .first()
                    .map(|run| run.style.clone())
                    .unwrap_or_default();
                block.runs = vec![TextRun {
                    range: full_range,
                    style,
                }];
            }
            EditorCommand::SetTextStyle { range, style, .. } => {
                let DocumentObject::Text(block) = &mut after else {
                    return Err(EditingError::WrongObjectKind(object_id));
                };
                utf16_range_to_byte_range(&block.text, *range)
                    .map_err(|_| EditingError::InvalidTextBoundary)?;
                if range.is_empty() {
                    return Err(EditingError::InvalidCommand(
                        "text style range must not be empty".into(),
                    ));
                }
                block.runs = split_text_runs(&block.runs, *range, style.clone());
            }
            EditorCommand::SetParagraphStyle { style, .. } => {
                if !style.line_spacing.is_finite() || style.line_spacing <= 0.0 {
                    return Err(EditingError::InvalidCommand(
                        "paragraph line spacing must be finite and positive".into(),
                    ));
                }
                let DocumentObject::Text(block) = &mut after else {
                    return Err(EditingError::WrongObjectKind(object_id));
                };
                block.layout.paragraph = style.clone();
            }
            EditorCommand::MoveObject { transform, .. } => after.set_transform(*transform),
            EditorCommand::ResizeObject { bounds, .. } => {
                after.set_bounds(*bounds);
                if let DocumentObject::Text(block) = &mut after {
                    let current_capacity = if block.layout_capacity_graphemes == 0 {
                        block.character_boxes.len()
                    } else {
                        block.layout_capacity_graphemes as usize
                    };
                    let old_extent = primary_extent(object_bounds, block.layout.direction);
                    let new_extent = primary_extent(*bounds, block.layout.direction);
                    if old_extent > 0.0 && current_capacity > 0 {
                        block.layout_capacity_graphemes =
                            ((current_capacity as f64 * new_extent / old_extent).floor() as usize)
                                .max(block.character_boxes.len())
                                as u32;
                    }
                    block.character_boxes =
                        reflow_character_boxes(&block.text, *bounds, block.layout.direction);
                }
            }
            EditorCommand::RotateObject {
                radians,
                center_x,
                center_y,
                ..
            } => {
                if !radians.is_finite() || !center_x.is_finite() || !center_y.is_finite() {
                    return Err(EditingError::InvalidCommand(
                        "rotation values must be finite".into(),
                    ));
                }
                after.set_transform(rotated_transform(
                    after.transform(),
                    *radians,
                    *center_x,
                    *center_y,
                ));
            }
            EditorCommand::UpdateAnnotation { annotation } => {
                if annotation.id() != object_id || annotation.page_id() != before.page_id() {
                    return Err(EditingError::InvalidCommand(
                        "annotation update identity does not match the target object".into(),
                    ));
                }
                after = DocumentObject::Annotation(annotation.clone());
            }
            EditorCommand::CreateAnnotation { .. }
            | EditorCommand::DeleteAnnotation { .. }
            | EditorCommand::ApplyTransaction { .. }
            | EditorCommand::CreateCheckpoint { .. }
            | EditorCommand::Undo
            | EditorCommand::Redo => {
                return Err(EditingError::InvalidCommand(
                    "history command reached object dispatcher".into(),
                ));
            }
        }
        if let Some(bounds) = expanded_text_bounds {
            after.set_bounds(bounds);
        }
        after.set_modified_revision(revision);
        self.model
            .replace_object(after.clone())
            .map_err(|_| EditingError::ObjectNotFound(object_id))?;
        let entry = HistoryEntry::Object {
            before: Box::new(before.clone()),
            after: Box::new(after.clone()),
            typing: typing.cloned(),
        };
        if matches!(command, EditorCommand::ReplaceTextRange { .. })
            && self
                .undo_stack
                .last()
                .is_some_and(|previous| can_coalesce(previous, &before, typing))
        {
            if let Some(HistoryEntry::Object {
                after: previous_after,
                typing: previous_typing,
                ..
            }) = self.undo_stack.last_mut()
            {
                **previous_after = after.clone();
                *previous_typing = typing.cloned();
            }
        } else {
            self.undo_stack.push(entry);
        }
        self.redo_stack.clear();
        Ok(vec![object_patch(&before, &after, revision)])
    }

    fn apply_undo(&mut self, revision: DocumentRevision) -> Result<Vec<ObjectPatch>, EditingError> {
        let entry = self
            .undo_stack
            .last()
            .cloned()
            .ok_or(EditingError::NothingToUndo)?;
        let patches = match &entry {
            HistoryEntry::Object { before, .. } => {
                let current = self
                    .model
                    .object(before.id())
                    .cloned()
                    .ok_or(EditingError::ObjectNotFound(before.id()))?;
                let mut restored = (**before).clone();
                restored.set_modified_revision(revision);
                self.model
                    .replace_object(restored.clone())
                    .map_err(|_| EditingError::ObjectNotFound(before.id()))?;
                vec![object_patch(&current, &restored, revision)]
            }
            HistoryEntry::Checkpoint { label } => {
                let _ = label;
                Vec::new()
            }
            HistoryEntry::Objects { before, .. } => before
                .iter()
                .map(|before| {
                    let current = self
                        .model
                        .object(before.id())
                        .cloned()
                        .ok_or(EditingError::ObjectNotFound(before.id()))?;
                    let mut restored = before.clone();
                    restored.set_modified_revision(revision);
                    self.model
                        .replace_object(restored.clone())
                        .map_err(|_| EditingError::ObjectNotFound(before.id()))?;
                    Ok(object_patch(&current, &restored, revision))
                })
                .collect::<Result<Vec<_>, EditingError>>()?,
            HistoryEntry::Inserted { object } => {
                self.model
                    .remove_object(object.id())
                    .map_err(|_| EditingError::ObjectNotFound(object.id()))?;
                Vec::new()
            }
            HistoryEntry::Deleted { object } => {
                let mut restored = (**object).clone();
                restored.set_modified_revision(revision);
                self.model
                    .insert_object(restored.clone())
                    .map_err(|error| EditingError::InvalidCommand(error.to_string()))?;
                vec![created_object_patch(&restored, revision)]
            }
        };
        self.undo_stack.pop();
        self.redo_stack.push(entry);
        Ok(patches)
    }

    fn apply_redo(&mut self, revision: DocumentRevision) -> Result<Vec<ObjectPatch>, EditingError> {
        let entry = self
            .redo_stack
            .last()
            .cloned()
            .ok_or(EditingError::NothingToRedo)?;
        let patches = match &entry {
            HistoryEntry::Object { after, .. } => {
                let current = self
                    .model
                    .object(after.id())
                    .cloned()
                    .ok_or(EditingError::ObjectNotFound(after.id()))?;
                let mut restored = (**after).clone();
                restored.set_modified_revision(revision);
                self.model
                    .replace_object(restored.clone())
                    .map_err(|_| EditingError::ObjectNotFound(after.id()))?;
                vec![object_patch(&current, &restored, revision)]
            }
            HistoryEntry::Checkpoint { label } => {
                let _ = label;
                Vec::new()
            }
            HistoryEntry::Objects { after, .. } => after
                .iter()
                .map(|after| {
                    let current = self
                        .model
                        .object(after.id())
                        .cloned()
                        .ok_or(EditingError::ObjectNotFound(after.id()))?;
                    let mut restored = after.clone();
                    restored.set_modified_revision(revision);
                    self.model
                        .replace_object(restored.clone())
                        .map_err(|_| EditingError::ObjectNotFound(after.id()))?;
                    Ok(object_patch(&current, &restored, revision))
                })
                .collect::<Result<Vec<_>, EditingError>>()?,
            HistoryEntry::Inserted { object } => {
                let mut restored = (**object).clone();
                restored.set_modified_revision(revision);
                self.model
                    .insert_object(restored.clone())
                    .map_err(|error| EditingError::InvalidCommand(error.to_string()))?;
                vec![created_object_patch(&restored, revision)]
            }
            HistoryEntry::Deleted { object } => {
                self.model
                    .remove_object(object.id())
                    .map_err(|_| EditingError::ObjectNotFound(object.id()))?;
                Vec::new()
            }
        };
        self.redo_stack.pop();
        self.undo_stack.push(entry);
        Ok(patches)
    }
}

fn physical_plan_from_changes(
    previous_revision: DocumentRevision,
    revision: DocumentRevision,
    before: &[DocumentObject],
    after: &[DocumentObject],
) -> Option<crate::PhysicalEditPlan> {
    let mut operations = Vec::new();
    let mut inverse_operations = Vec::new();
    for after_object in after {
        let before_object = before
            .iter()
            .find(|candidate| candidate.id() == after_object.id())?;
        let (DocumentObject::Text(before_text), DocumentObject::Text(after_text)) =
            (before_object, after_object)
        else {
            return None;
        };
        let binding = after_object.source_binding()?;
        operations.push(crate::PhysicalEditOperation::ReplaceText {
            object_id: after_object.id(),
            source_key: binding.source_key.clone(),
            source_revision: binding.source_revision.clone(),
            expected_text: before_text.text.clone(),
            replacement: after_text.text.clone(),
            bounds: after_object.bounds(),
        });
        inverse_operations.push(crate::PhysicalEditOperation::ReplaceText {
            object_id: before_object.id(),
            source_key: binding.source_key.clone(),
            source_revision: binding.source_revision.clone(),
            expected_text: after_text.text.clone(),
            replacement: before_text.text.clone(),
            bounds: before_object.bounds(),
        });
    }
    (!operations.is_empty()).then_some(crate::PhysicalEditPlan {
        previous_revision,
        revision,
        operations,
        inverse_operations,
    })
}

fn changed_objects(
    before: &DocumentModel,
    after: &DocumentModel,
) -> (Vec<DocumentObject>, Vec<DocumentObject>) {
    let mut before_objects = Vec::new();
    let mut after_objects = Vec::new();
    for before_page in &before.pages {
        for before_object in &before_page.objects {
            let Some(after_object) = after.object(before_object.id()) else {
                before_objects.push(before_object.clone());
                continue;
            };
            if after_object != before_object {
                before_objects.push(before_object.clone());
                after_objects.push(after_object.clone());
            }
        }
    }
    for after_page in &after.pages {
        for after_object in &after_page.objects {
            if before.object(after_object.id()).is_none() {
                after_objects.push(after_object.clone());
            }
        }
    }
    (before_objects, after_objects)
}

fn command_object_id(command: &EditorCommand) -> Option<ObjectId> {
    match command {
        EditorCommand::ReplaceTextRange { object_id, .. }
        | EditorCommand::ReplaceTextRangeWithFontFallback { object_id, .. }
        | EditorCommand::SetTextStyle { object_id, .. }
        | EditorCommand::SetParagraphStyle { object_id, .. }
        | EditorCommand::MoveObject { object_id, .. }
        | EditorCommand::ResizeObject { object_id, .. }
        | EditorCommand::RotateObject { object_id, .. } => Some(*object_id),
        EditorCommand::UpdateAnnotation { annotation } => Some(annotation.id()),
        EditorCommand::CreateAnnotation { .. }
        | EditorCommand::DeleteAnnotation { .. }
        | EditorCommand::ApplyTransaction { .. }
        | EditorCommand::CreateCheckpoint { .. }
        | EditorCommand::Undo
        | EditorCommand::Redo => None,
    }
}

fn reflow_character_boxes(
    text: &str,
    bounds: PdfBox,
    direction: WritingDirection,
) -> Vec<TextCharacterBox> {
    let graphemes = text.graphemes(true).collect::<Vec<_>>();
    let count = graphemes.len();
    let mut utf16_start = 0_u32;

    graphemes
        .into_iter()
        .enumerate()
        .map(|(index, grapheme)| {
            let utf16_end = utf16_start + grapheme.encode_utf16().count() as u32;
            let fraction_start = index as f64 / count as f64;
            let fraction_end = (index + 1) as f64 / count as f64;
            let character_bounds = match direction {
                WritingDirection::LeftToRight => PdfBox {
                    left: bounds.left + (bounds.right - bounds.left) * fraction_start,
                    bottom: bounds.bottom,
                    right: bounds.left + (bounds.right - bounds.left) * fraction_end,
                    top: bounds.top,
                },
                WritingDirection::RightToLeft => PdfBox {
                    left: bounds.right - (bounds.right - bounds.left) * fraction_end,
                    bottom: bounds.bottom,
                    right: bounds.right - (bounds.right - bounds.left) * fraction_start,
                    top: bounds.top,
                },
                WritingDirection::TopToBottom => PdfBox {
                    left: bounds.left,
                    bottom: bounds.top - (bounds.top - bounds.bottom) * fraction_end,
                    right: bounds.right,
                    top: bounds.top - (bounds.top - bounds.bottom) * fraction_start,
                },
            };
            let character = TextCharacterBox {
                range: Utf16Range {
                    start: utf16_start,
                    end: utf16_end,
                },
                bounds: character_bounds,
            };
            utf16_start = utf16_end;
            character
        })
        .collect()
}

fn expand_text_bounds(bounds: PdfBox, direction: WritingDirection, scale: f64) -> PdfBox {
    match direction {
        WritingDirection::LeftToRight => PdfBox {
            right: bounds.left + (bounds.right - bounds.left) * scale,
            ..bounds
        },
        WritingDirection::RightToLeft => PdfBox {
            left: bounds.right - (bounds.right - bounds.left) * scale,
            ..bounds
        },
        WritingDirection::TopToBottom => PdfBox {
            bottom: bounds.top - (bounds.top - bounds.bottom) * scale,
            ..bounds
        },
    }
}

fn primary_extent(bounds: PdfBox, direction: WritingDirection) -> f64 {
    match direction {
        WritingDirection::LeftToRight | WritingDirection::RightToLeft => bounds.right - bounds.left,
        WritingDirection::TopToBottom => bounds.top - bounds.bottom,
    }
}

fn split_text_runs(runs: &[TextRun], range: Utf16Range, style: crate::TextStyle) -> Vec<TextRun> {
    let mut output = Vec::new();
    for run in runs {
        if run.range.end <= range.start || run.range.start >= range.end {
            output.push(run.clone());
            continue;
        }
        if run.range.start < range.start {
            output.push(TextRun {
                range: Utf16Range::new(run.range.start, range.start).expect("ordered run split"),
                style: run.style.clone(),
            });
        }
        output.push(TextRun {
            range: Utf16Range::new(
                run.range.start.max(range.start),
                run.range.end.min(range.end),
            )
            .expect("ordered intersection"),
            style: style.clone(),
        });
        if run.range.end > range.end {
            output.push(TextRun {
                range: Utf16Range::new(range.end, run.range.end).expect("ordered run split"),
                style: run.style.clone(),
            });
        }
    }
    output
}

fn object_patch(
    before: &DocumentObject,
    after: &DocumentObject,
    revision: DocumentRevision,
) -> ObjectPatch {
    let (text, text_runs, character_boxes, font) = match (before, after) {
        (DocumentObject::Text(before), DocumentObject::Text(after)) => (
            (before.text != after.text).then(|| after.text.clone()),
            (before.runs != after.runs).then(|| after.runs.clone()),
            (before.character_boxes != after.character_boxes)
                .then(|| after.character_boxes.clone()),
            (before.font != after.font)
                .then(|| after.font.clone())
                .flatten(),
        ),
        _ => (None, None, None, None),
    };
    ObjectPatch {
        object_id: after.id(),
        page_id: after.page_id(),
        modified_revision: revision,
        text,
        text_runs,
        character_boxes,
        font,
        bounds: (before.bounds() != after.bounds()).then(|| after.bounds()),
        transform: (before.transform() != after.transform()).then(|| after.transform()),
    }
}

fn created_object_patch(object: &DocumentObject, revision: DocumentRevision) -> ObjectPatch {
    let (text, text_runs, character_boxes, font) = match object {
        DocumentObject::Text(block) => (
            Some(block.text.clone()),
            Some(block.runs.clone()),
            Some(block.character_boxes.clone()),
            block.font.clone(),
        ),
        _ => (None, None, None, None),
    };
    ObjectPatch {
        object_id: object.id(),
        page_id: object.page_id(),
        modified_revision: revision,
        text,
        text_runs,
        character_boxes,
        font,
        bounds: Some(object.bounds()),
        transform: Some(object.transform()),
    }
}

fn rotated_transform(
    current: AffineTransform,
    radians: f64,
    center_x: f64,
    center_y: f64,
) -> AffineTransform {
    let cosine = radians.cos();
    let sine = radians.sin();
    let rotation = AffineTransform {
        a: cosine,
        b: sine,
        c: -sine,
        d: cosine,
        e: center_x - cosine * center_x + sine * center_y,
        f: center_y - sine * center_x - cosine * center_y,
    };
    AffineTransform {
        a: rotation.a * current.a + rotation.c * current.b,
        b: rotation.b * current.a + rotation.d * current.b,
        c: rotation.a * current.c + rotation.c * current.d,
        d: rotation.b * current.c + rotation.d * current.d,
        e: rotation.a * current.e + rotation.c * current.f + rotation.e,
        f: rotation.b * current.e + rotation.d * current.f + rotation.f,
    }
}
