use std::collections::HashSet;

use crate::history::{can_coalesce, HistoryEntry};
use crate::text::utf16_range_to_byte_range;
use crate::{
    AffineTransform, CommandEnvelope, CommandId, CommandResult, DocumentModel, DocumentObject,
    DocumentRevision, EditCapability, EditingError, EditorCommand, InverseOperation, ObjectId,
    ObjectPatch, PageNode, PreparedCommand, RecoveredCommand, SelectionRebase, SessionId, TextRun,
    Utf16Range,
};

#[derive(Debug, Clone)]
pub struct EditorSessionState {
    session_id: SessionId,
    model: DocumentModel,
    committed_commands: HashSet<CommandId>,
    undo_stack: Vec<HistoryEntry>,
    redo_stack: Vec<HistoryEntry>,
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
        let inverse = if before_objects.is_empty() {
            InverseOperation::Checkpoint
        } else {
            InverseOperation::ReplaceObjects(before_objects.clone())
        };
        Ok(PreparedCommand {
            envelope,
            previous_revision,
            committed_revision: result.committed_revision,
            before_objects,
            after_objects,
            inverse,
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
            } => Some(SelectionRebase {
                object_id: *object_id,
                replaced_range: *range,
                inserted_utf16_length: replacement.encode_utf16().count() as u32,
            }),
            _ => None,
        };
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
            command => {
                self.apply_object_command(command, next_revision, envelope.typing_group.as_ref())?
            }
        };
        self.model.set_revision(next_revision);
        self.committed_commands.insert(envelope.command_id);
        Ok(CommandResult {
            command_id: envelope.command_id,
            previous_revision,
            committed_revision: next_revision,
            object_patches,
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
        match command {
            EditorCommand::ReplaceTextRange {
                range, replacement, ..
            } => {
                let DocumentObject::Text(block) = &mut after else {
                    return Err(EditingError::WrongObjectKind(object_id));
                };
                let byte_range = utf16_range_to_byte_range(&block.text, *range)
                    .map_err(|_| EditingError::InvalidTextBoundary)?;
                block.text.replace_range(byte_range, replacement);
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
            EditorCommand::ResizeObject { bounds, .. } => after.set_bounds(*bounds),
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
            EditorCommand::CreateCheckpoint { .. } | EditorCommand::Undo | EditorCommand::Redo => {
                return Err(EditingError::InvalidCommand(
                    "history command reached object dispatcher".into(),
                ));
            }
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
        };
        self.redo_stack.pop();
        self.undo_stack.push(entry);
        Ok(patches)
    }
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
                continue;
            };
            if after_object != before_object {
                before_objects.push(before_object.clone());
                after_objects.push(after_object.clone());
            }
        }
    }
    (before_objects, after_objects)
}

fn command_object_id(command: &EditorCommand) -> Option<ObjectId> {
    match command {
        EditorCommand::ReplaceTextRange { object_id, .. }
        | EditorCommand::SetTextStyle { object_id, .. }
        | EditorCommand::SetParagraphStyle { object_id, .. }
        | EditorCommand::MoveObject { object_id, .. }
        | EditorCommand::ResizeObject { object_id, .. }
        | EditorCommand::RotateObject { object_id, .. } => Some(*object_id),
        EditorCommand::CreateCheckpoint { .. } | EditorCommand::Undo | EditorCommand::Redo => None,
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
    let (text, text_runs) = match (before, after) {
        (DocumentObject::Text(before), DocumentObject::Text(after)) => (
            (before.text != after.text).then(|| after.text.clone()),
            (before.runs != after.runs).then(|| after.runs.clone()),
        ),
        _ => (None, None),
    };
    ObjectPatch {
        object_id: after.id(),
        page_id: after.page_id(),
        modified_revision: revision,
        text,
        text_runs,
        bounds: (before.bounds() != after.bounds()).then(|| after.bounds()),
        transform: (before.transform() != after.transform()).then(|| after.transform()),
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
