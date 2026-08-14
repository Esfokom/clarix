use std::collections::HashSet;

use crate::text::utf16_range_to_byte_range;
use crate::{
    AffineTransform, CommandEnvelope, CommandId, CommandResult, DocumentModel, DocumentObject,
    DocumentRevision, EditCapability, EditingError, EditorCommand, ObjectId, ObjectPatch,
    SessionId, TextRun, Utf16Range,
};

#[derive(Debug, Clone)]
enum HistoryEntry {
    Object {
        before: Box<DocumentObject>,
        after: Box<DocumentObject>,
    },
    Checkpoint {
        label: String,
    },
}

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

    pub fn submit(&mut self, envelope: CommandEnvelope) -> Result<CommandResult, EditingError> {
        self.ensure_open()?;
        if envelope.base_revision != self.revision() {
            return Err(EditingError::RevisionConflict {
                expected: envelope.base_revision,
                actual: self.revision(),
            });
        }
        if self.committed_commands.contains(&envelope.command_id) {
            return Err(EditingError::DuplicateCommand);
        }

        let next_revision = self
            .revision()
            .next()
            .map_err(|_| EditingError::RevisionOverflow)?;
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
            command => self.apply_object_command(command, next_revision)?,
        };

        self.model.set_revision(next_revision);
        self.committed_commands.insert(envelope.command_id);
        Ok(CommandResult {
            command_id: envelope.command_id,
            committed_revision: next_revision,
            object_patches,
        })
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

    fn apply_object_command(
        &mut self,
        command: &EditorCommand,
        revision: DocumentRevision,
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
                block.runs = vec![TextRun {
                    range: *range,
                    style: style.clone(),
                }];
            }
            EditorCommand::MoveObject { transform, .. } => {
                after.set_transform(*transform);
            }
            EditorCommand::ResizeObject { bounds, .. } => {
                after.set_bounds(*bounds);
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
        self.undo_stack.push(HistoryEntry::Object {
            before: Box::new(before.clone()),
            after: Box::new(after.clone()),
        });
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

fn command_object_id(command: &EditorCommand) -> Option<ObjectId> {
    match command {
        EditorCommand::ReplaceTextRange { object_id, .. }
        | EditorCommand::SetTextStyle { object_id, .. }
        | EditorCommand::MoveObject { object_id, .. }
        | EditorCommand::ResizeObject { object_id, .. }
        | EditorCommand::RotateObject { object_id, .. } => Some(*object_id),
        EditorCommand::CreateCheckpoint { .. } | EditorCommand::Undo | EditorCommand::Redo => None,
    }
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
