use std::str::FromStr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use clarix_editing_core::{
    AffineTransform, CommandEnvelope, CommandId, CommandResult, DocumentId, DocumentModel,
    DocumentObject, DocumentRevision, EditingError, EditorCommand, EditorEvent, EditorSessionActor,
    ObjectId, ObjectPatch, PdfBox, SessionId, TextRun, TextStyle, Utf16Range,
};
use clarix_pdf_adapter::{PdfImporter, PdfOxideImporter, SourceRef};

use crate::frb_generated::StreamSink;

const EDITOR_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct NativeOpenEditorRequest {
    pub source_path: String,
}

#[derive(Debug, Clone)]
pub struct NativeEditorMetadata {
    pub schema_version: u32,
    pub session_id: String,
    pub document_id: String,
    pub source_fingerprint: String,
    pub revision: u64,
    pub page_count: u32,
}

#[derive(Debug, Clone)]
pub struct NativePageSceneRequest {
    pub page_number: u32,
    pub expected_revision: u64,
}

#[derive(Debug, Clone)]
pub struct NativePageScene {
    pub schema_version: u32,
    pub page_id: String,
    pub page_number: u32,
    pub width: f64,
    pub height: f64,
    pub revision: u64,
    pub objects: Vec<NativeSceneObject>,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeSceneObjectKind {
    Text,
    Unsupported,
}

#[derive(Debug, Clone)]
pub struct NativeSceneObject {
    pub kind: NativeSceneObjectKind,
    pub object_id: String,
    pub page_id: String,
    pub text: Option<String>,
    pub bounds: NativePdfBox,
    pub transform: NativeAffineTransform,
    pub capability: String,
    pub modified_revision: u64,
    pub runs: Vec<NativeTextRun>,
}

#[derive(Debug, Clone)]
pub struct NativeTextRun {
    pub start: u32,
    pub end: u32,
    pub style: NativeTextStyle,
}

#[derive(Debug, Clone)]
pub struct NativeTextStyle {
    pub font_family: Option<String>,
    pub font_size: f64,
    pub font_weight: u16,
    pub italic: bool,
    pub color_rgba: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct NativePdfBox {
    pub left: f64,
    pub bottom: f64,
    pub right: f64,
    pub top: f64,
}

#[derive(Debug, Clone)]
pub struct NativeAffineTransform {
    pub a: f64,
    pub b: f64,
    pub c: f64,
    pub d: f64,
    pub e: f64,
    pub f: f64,
}

#[derive(Debug, Clone)]
pub struct NativeSubmitCommandRequest {
    pub schema_version: u32,
    pub command_id: String,
    pub base_revision: u64,
    pub payload: NativeEditorCommand,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeEditorCommandKind {
    ReplaceTextRange,
    SetTextStyle,
    MoveObject,
    ResizeObject,
    RotateObject,
    CreateCheckpoint,
    Undo,
    Redo,
}

#[derive(Debug, Clone)]
pub struct NativeEditorCommand {
    pub kind: NativeEditorCommandKind,
    pub object_id: Option<String>,
    pub start: Option<u32>,
    pub end: Option<u32>,
    pub replacement: Option<String>,
    pub style: Option<NativeTextStyle>,
    pub transform: Option<NativeAffineTransform>,
    pub bounds: Option<NativePdfBox>,
    pub radians: Option<f64>,
    pub center_x: Option<f64>,
    pub center_y: Option<f64>,
    pub label: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NativeCommandResult {
    pub command_id: String,
    pub committed_revision: u64,
    pub object_patches: Vec<NativeObjectPatch>,
}

#[derive(Debug, Clone)]
pub struct NativeObjectPatch {
    pub object_id: String,
    pub page_id: String,
    pub modified_revision: u64,
    pub text: Option<String>,
    pub text_runs: Option<Vec<NativeTextRun>>,
    pub bounds: Option<NativePdfBox>,
    pub transform: Option<NativeAffineTransform>,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeEditorEventKind {
    Ready,
    CommandCommitted,
    Lagged,
    Closed,
}

#[derive(Debug, Clone)]
pub struct NativeEditorEvent {
    pub kind: NativeEditorEventKind,
    pub sequence: u64,
    pub revision: Option<u64>,
    pub latest_revision: Option<u64>,
    pub result: Option<NativeCommandResult>,
}

pub struct NativeEditorSession {
    actor: EditorSessionActor,
    importer: PdfOxideImporter,
    source: SourceRef,
    document_id: DocumentId,
    page_count: u32,
    event_sequence: Arc<AtomicU64>,
}

impl NativeEditorSession {
    pub fn open(request: NativeOpenEditorRequest) -> Result<Self, String> {
        let source = SourceRef::from_path(request.source_path).map_err(adapter_error)?;
        let importer = PdfOxideImporter;
        let inspection = importer.inspect_document(&source).map_err(adapter_error)?;
        let document_id = DocumentId::from_source_key(source.fingerprint());
        let model = DocumentModel::new(document_id, source.fingerprint().to_owned(), Vec::new())
            .map_err(|error| format!("invalid_document: {error}"))?;
        let session_id = SessionId::new();
        Ok(Self {
            actor: EditorSessionActor::spawn_with_session(session_id, model),
            importer,
            source,
            document_id,
            page_count: inspection.page_count,
            event_sequence: Arc::new(AtomicU64::new(0)),
        })
    }

    pub fn metadata(&self) -> Result<NativeEditorMetadata, String> {
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        Ok(NativeEditorMetadata {
            schema_version: EDITOR_SCHEMA_VERSION,
            session_id: self.actor.session_id().to_string(),
            document_id: self.document_id.to_string(),
            source_fingerprint: self.source.fingerprint().to_owned(),
            revision: snapshot.revision.value(),
            page_count: self.page_count,
        })
    }

    pub fn page_scene(&self, request: NativePageSceneRequest) -> Result<NativePageScene, String> {
        let expected_revision = DocumentRevision::from_value(request.expected_revision);
        let mut snapshot = self.actor.snapshot().map_err(editing_error)?;
        if snapshot.revision != expected_revision {
            return Err(editing_error(EditingError::RevisionConflict {
                expected: expected_revision,
                actual: snapshot.revision,
            }));
        }
        if snapshot.page(request.page_number).is_none() {
            let imported = self
                .importer
                .inspect_page(&self.source, request.page_number)
                .map_err(adapter_error)?;
            self.actor
                .hydrate_page(imported.page, expected_revision)
                .map_err(editing_error)?;
            snapshot = self.actor.snapshot().map_err(editing_error)?;
        }
        let page = snapshot
            .page(request.page_number)
            .ok_or_else(|| "page_not_loaded: requested page is unavailable".to_owned())?;
        Ok(NativePageScene {
            schema_version: EDITOR_SCHEMA_VERSION,
            page_id: page.id.to_string(),
            page_number: page.page_number,
            width: page.width,
            height: page.height,
            revision: snapshot.revision.value(),
            objects: page.objects.iter().map(native_scene_object).collect(),
        })
    }

    pub fn submit(
        &self,
        request: NativeSubmitCommandRequest,
    ) -> Result<NativeCommandResult, String> {
        if request.schema_version != EDITOR_SCHEMA_VERSION {
            return Err(format!(
                "schema_mismatch: expected {EDITOR_SCHEMA_VERSION}, got {}",
                request.schema_version
            ));
        }
        let command_id = CommandId::from_str(&request.command_id)
            .map_err(|error| format!("invalid_command_id: {error}"))?;
        let payload = editor_command(request.payload)?;
        self.actor
            .submit(CommandEnvelope::user(
                command_id,
                DocumentRevision::from_value(request.base_revision),
                payload,
            ))
            .map(native_command_result)
            .map_err(editing_error)
    }

    pub fn events(&self, sink: StreamSink<NativeEditorEvent>) -> Result<(), String> {
        let events = self.actor.subscribe().map_err(editing_error)?;
        let event_sequence = Arc::clone(&self.event_sequence);
        std::thread::Builder::new()
            .name(format!("clarix-editor-events-{}", self.actor.session_id()))
            .spawn(move || {
                for event in events {
                    let sequence = event_sequence.fetch_add(1, Ordering::AcqRel) + 1;
                    let native = native_event(event, sequence);
                    if sink.add(native).is_err() {
                        break;
                    }
                }
            })
            .map_err(|error| format!("event_stream_failed: {error}"))?;
        Ok(())
    }

    pub fn close(&self) -> Result<(), String> {
        self.actor.close().map_err(editing_error)
    }
}

fn editor_command(command: NativeEditorCommand) -> Result<EditorCommand, String> {
    let NativeEditorCommand {
        kind,
        object_id,
        start,
        end,
        replacement,
        style,
        transform,
        bounds,
        radians,
        center_x,
        center_y,
        label,
    } = command;
    Ok(match kind {
        NativeEditorCommandKind::ReplaceTextRange => EditorCommand::ReplaceTextRange {
            object_id: parse_object_id(&required(object_id, "object_id")?)?,
            range: Utf16Range::new(required(start, "start")?, required(end, "end")?)
                .map_err(|error| format!("invalid_text_boundary: {error}"))?,
            replacement: required(replacement, "replacement")?,
        },
        NativeEditorCommandKind::SetTextStyle => EditorCommand::SetTextStyle {
            object_id: parse_object_id(&required(object_id, "object_id")?)?,
            range: Utf16Range::new(required(start, "start")?, required(end, "end")?)
                .map_err(|error| format!("invalid_text_boundary: {error}"))?,
            style: text_style(required(style, "style")?)?,
        },
        NativeEditorCommandKind::MoveObject => EditorCommand::MoveObject {
            object_id: parse_object_id(&required(object_id, "object_id")?)?,
            transform: affine_transform(required(transform, "transform")?)?,
        },
        NativeEditorCommandKind::ResizeObject => EditorCommand::ResizeObject {
            object_id: parse_object_id(&required(object_id, "object_id")?)?,
            bounds: pdf_box(required(bounds, "bounds")?)?,
        },
        NativeEditorCommandKind::RotateObject => EditorCommand::RotateObject {
            object_id: parse_object_id(&required(object_id, "object_id")?)?,
            radians: required(radians, "radians")?,
            center_x: required(center_x, "center_x")?,
            center_y: required(center_y, "center_y")?,
        },
        NativeEditorCommandKind::CreateCheckpoint => EditorCommand::CreateCheckpoint {
            label: required(label, "label")?,
        },
        NativeEditorCommandKind::Undo => EditorCommand::Undo,
        NativeEditorCommandKind::Redo => EditorCommand::Redo,
    })
}

fn required<T>(value: Option<T>, field: &str) -> Result<T, String> {
    value.ok_or_else(|| format!("invalid_command: missing {field}"))
}

fn parse_object_id(value: &str) -> Result<ObjectId, String> {
    ObjectId::from_str(value).map_err(|error| format!("invalid_object_id: {error}"))
}

fn text_style(style: NativeTextStyle) -> Result<TextStyle, String> {
    if !style.font_size.is_finite() || style.font_size <= 0.0 {
        return Err("invalid_text_style: font size must be finite and positive".into());
    }
    let color_rgba: [u8; 4] = style
        .color_rgba
        .try_into()
        .map_err(|_| "invalid_text_style: RGBA must contain four channels".to_owned())?;
    Ok(TextStyle {
        font_family: style.font_family,
        font_size: style.font_size,
        font_weight: style.font_weight,
        italic: style.italic,
        color_rgba,
    })
}

fn pdf_box(bounds: NativePdfBox) -> Result<PdfBox, String> {
    PdfBox::new(bounds.left, bounds.bottom, bounds.right, bounds.top)
        .map_err(|error| format!("invalid_geometry: {error}"))
}

fn affine_transform(transform: NativeAffineTransform) -> Result<AffineTransform, String> {
    AffineTransform::new(
        transform.a,
        transform.b,
        transform.c,
        transform.d,
        transform.e,
        transform.f,
    )
    .map_err(|error| format!("invalid_geometry: {error}"))
}

fn native_scene_object(object: &DocumentObject) -> NativeSceneObject {
    match object {
        DocumentObject::Text(block) => NativeSceneObject {
            kind: NativeSceneObjectKind::Text,
            object_id: object.id().to_string(),
            page_id: object.page_id().to_string(),
            text: Some(block.text.clone()),
            bounds: native_box(object.bounds()),
            transform: native_transform(object.transform()),
            capability: format!("{:?}", object.capability()).to_ascii_lowercase(),
            modified_revision: object.modified_revision().value(),
            runs: block.runs.iter().map(native_text_run).collect(),
        },
        _ => NativeSceneObject {
            kind: NativeSceneObjectKind::Unsupported,
            object_id: object.id().to_string(),
            page_id: object.page_id().to_string(),
            text: None,
            bounds: native_box(object.bounds()),
            transform: native_transform(object.transform()),
            capability: format!("{:?}", object.capability()).to_ascii_lowercase(),
            modified_revision: object.modified_revision().value(),
            runs: Vec::new(),
        },
    }
}

fn native_command_result(result: CommandResult) -> NativeCommandResult {
    NativeCommandResult {
        command_id: result.command_id.to_string(),
        committed_revision: result.committed_revision.value(),
        object_patches: result
            .object_patches
            .into_iter()
            .map(native_object_patch)
            .collect(),
    }
}

fn native_object_patch(patch: ObjectPatch) -> NativeObjectPatch {
    NativeObjectPatch {
        object_id: patch.object_id.to_string(),
        page_id: patch.page_id.to_string(),
        modified_revision: patch.modified_revision.value(),
        text: patch.text,
        text_runs: patch
            .text_runs
            .map(|runs| runs.iter().map(native_text_run).collect()),
        bounds: patch.bounds.map(native_box),
        transform: patch.transform.map(native_transform),
    }
}

fn native_text_run(run: &TextRun) -> NativeTextRun {
    NativeTextRun {
        start: run.range.start,
        end: run.range.end,
        style: NativeTextStyle {
            font_family: run.style.font_family.clone(),
            font_size: run.style.font_size,
            font_weight: run.style.font_weight,
            italic: run.style.italic,
            color_rgba: run.style.color_rgba.to_vec(),
        },
    }
}

fn native_box(bounds: PdfBox) -> NativePdfBox {
    NativePdfBox {
        left: bounds.left,
        bottom: bounds.bottom,
        right: bounds.right,
        top: bounds.top,
    }
}

fn native_transform(transform: AffineTransform) -> NativeAffineTransform {
    NativeAffineTransform {
        a: transform.a,
        b: transform.b,
        c: transform.c,
        d: transform.d,
        e: transform.e,
        f: transform.f,
    }
}

fn native_event(event: EditorEvent, sequence: u64) -> NativeEditorEvent {
    match event {
        EditorEvent::Ready { revision } => NativeEditorEvent {
            kind: NativeEditorEventKind::Ready,
            sequence,
            revision: Some(revision.value()),
            latest_revision: None,
            result: None,
        },
        EditorEvent::CommandCommitted { result } => NativeEditorEvent {
            kind: NativeEditorEventKind::CommandCommitted,
            sequence,
            revision: Some(result.committed_revision.value()),
            latest_revision: None,
            result: Some(native_command_result(result)),
        },
        EditorEvent::Lagged { latest_revision } => NativeEditorEvent {
            kind: NativeEditorEventKind::Lagged,
            sequence,
            revision: None,
            latest_revision: Some(latest_revision.value()),
            result: None,
        },
        EditorEvent::Closed { revision } => NativeEditorEvent {
            kind: NativeEditorEventKind::Closed,
            sequence,
            revision: Some(revision.value()),
            latest_revision: None,
            result: None,
        },
    }
}

fn editing_error(error: EditingError) -> String {
    format!("{}: {error}", error.code())
}

fn adapter_error(error: clarix_pdf_adapter::PdfAdapterError) -> String {
    format!("{}: {error}", error.code())
}
