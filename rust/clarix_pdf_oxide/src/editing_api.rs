use std::str::FromStr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use clarix_editing_core::{
    AffineTransform, CommandEnvelope, CommandId, CommandResult, DocumentId, DocumentModel,
    DocumentObject, DocumentRevision, EditingError, EditorCommand, EditorEvent, EditorSessionActor,
    ObjectId, ObjectPatch, PageIndexTask, PageSceneRequest, PageSceneService, PdfBox,
    RecoveryRequest, SaveAssociation, SaveCoordinator, SaveMode, SaveRequest, SessionId,
    SourceReference, TextRun, TextStyle, Utf16Range, ViewportPriority,
};
use clarix_editing_store::{ProjectLocation, ProjectSeed, SqliteProjectRepository};
use clarix_pdf_adapter::{
    CleanPatchCache, CleanPatchRenderRequest, CleanPatchRenderer, IndependentPdfValidator,
    PdfImporter, PdfOxideImporter, PdfTextMaterializer, SourceRef, WindowsAtomicReplacer,
};

use crate::frb_generated::StreamSink;

const EDITOR_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct NativeOpenEditorRequest {
    pub source_path: String,
    pub project_root: Option<String>,
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
    pub priority: NativeViewportPriority,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeViewportPriority {
    Background,
    Preload,
    Visible,
    ActiveSelection,
}

#[derive(Debug, Clone)]
pub struct NativeObjectDetailsRequest {
    pub object_id: String,
}

#[derive(Debug, Clone)]
pub struct NativeCleanPatchRequest {
    pub object_id: String,
    pub dpi: u32,
}

#[derive(Debug, Clone)]
pub struct NativeCleanPatchAsset {
    pub handle: String,
    pub object_id: String,
    pub bounds: NativePdfBox,
    pub dpi: u32,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: Vec<u8>,
    pub bleed_points: f64,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeEditorSaveMode {
    Save,
    SaveAs,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeSaveAssociation {
    KeepOriginalAssociation,
    FollowNewSource,
}

#[derive(Debug, Clone)]
pub struct NativeEditorSaveRequest {
    pub target_path: String,
    pub mode: NativeEditorSaveMode,
    pub association: NativeSaveAssociation,
    pub recovery_directory: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NativeEditorSaveResult {
    pub schema_version: u32,
    pub target_path: String,
    pub materialized_revision: u64,
    pub completed_stages: Vec<String>,
    pub warnings: Vec<String>,
    pub follows_new_source: bool,
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
    pub capability_reason: Option<String>,
    pub modified_revision: u64,
    pub runs: Vec<NativeTextRun>,
    pub layout: Option<NativeTextLayoutRecipe>,
    pub font_fingerprint: Option<String>,
    pub font_asset_handle: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NativeTextLayoutRecipe {
    pub baseline: f64,
    pub line_height: f64,
    pub character_spacing: f64,
    pub horizontal_scale: f64,
    pub direction: String,
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
    pub previous_revision: u64,
    pub committed_revision: u64,
    pub durable: bool,
    pub warnings: Vec<String>,
    pub selection_rebase: Option<NativeSelectionRebase>,
    pub object_patches: Vec<NativeObjectPatch>,
}

#[derive(Debug, Clone)]
pub struct NativeSelectionRebase {
    pub object_id: String,
    pub start: u32,
    pub end: u32,
    pub inserted_utf16_length: u32,
}

#[derive(Debug, Clone)]
pub struct NativeCheckpointRequest {
    pub base_revision: u64,
    pub label: String,
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
    pub session_id: String,
    pub sequence: u64,
    pub revision: Option<u64>,
    pub latest_revision: Option<u64>,
    pub result: Option<NativeCommandResult>,
}

pub struct NativeEditorSession {
    actor: EditorSessionActor,
    page_service: PageSceneService,
    background_indexing: PageIndexTask,
    clean_patches: CleanPatchCache,
    _repository: Arc<SqliteProjectRepository>,
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
        let project_root = request
            .project_root
            .map(std::path::PathBuf::from)
            .or_else(|| std::env::var_os("LOCALAPPDATA").map(std::path::PathBuf::from))
            .ok_or_else(|| "project_location_unavailable: LOCALAPPDATA is not set".to_owned())?;
        let repository = Arc::new(
            SqliteProjectRepository::open(
                ProjectLocation::under(&project_root, document_id),
                ProjectSeed {
                    model: model.clone(),
                    undo_cursor: 0,
                    materialized_revision: None,
                },
            )
            .map_err(|error| format!("sidecar_open_failed: {error}"))?,
        );
        let session_id = SessionId::new();
        let actor = EditorSessionActor::spawn_recovered(
            session_id,
            repository.clone(),
            RecoveryRequest {
                document_id,
                source_fingerprint: source.fingerprint().to_owned(),
            },
        )
        .map_err(editing_error)?;
        let page_service = PageSceneService::new(
            document_id,
            SourceReference::new(source.fingerprint(), source.path()),
            inspection.page_count,
            2,
            Arc::new(importer),
        )
        .map_err(|error| format!("{}: {error}", error.code()))?
        .with_index_repository(repository.clone());
        let background_indexing = page_service.start_background_indexing();
        Ok(Self {
            actor,
            page_service,
            background_indexing,
            clean_patches: CleanPatchCache::for_document(Arc::new(CleanPatchRenderer)),
            _repository: repository,
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
                .page_service
                .request(PageSceneRequest {
                    page_number: request.page_number,
                    expected_revision,
                    priority: viewport_priority(request.priority),
                })
                .map_err(|error| format!("{}: {error}", error.code()))?;
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
        let result = self
            .actor
            .submit(CommandEnvelope::user(
                command_id,
                DocumentRevision::from_value(request.base_revision),
                payload,
            ))
            .map_err(editing_error)?;
        self.page_service.set_revision(result.committed_revision);
        Ok(native_command_result(result))
    }

    pub fn object_details(
        &self,
        request: NativeObjectDetailsRequest,
    ) -> Result<NativeSceneObject, String> {
        let object_id = parse_object_id(&request.object_id)?;
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        snapshot
            .object(object_id)
            .map(native_scene_object)
            .ok_or_else(|| format!("object_not_found: {object_id}"))
    }

    pub fn clean_patch(
        &self,
        request: NativeCleanPatchRequest,
    ) -> Result<NativeCleanPatchAsset, String> {
        let object_id = parse_object_id(&request.object_id)?;
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        let object = snapshot
            .object(object_id)
            .ok_or_else(|| format!("object_not_found: {object_id}"))?;
        let page_number = snapshot
            .pages
            .iter()
            .find(|page| page.id == object.page_id())
            .map(|page| page.page_number)
            .ok_or_else(|| format!("page_not_loaded: object {object_id} has no loaded page"))?;
        let binding = object.source_binding().ok_or_else(|| {
            format!("clean_patch_unavailable: object {object_id} has no source binding")
        })?;
        let patch = self
            .clean_patches
            .get_or_render(CleanPatchRenderRequest {
                source: self.source.clone(),
                page_number,
                source_key: binding.source_key.clone(),
                bounds: object.bounds(),
                dpi: request.dpi,
            })
            .map_err(adapter_error)?;
        Ok(NativeCleanPatchAsset {
            handle: format!(
                "{}:{}:{}",
                patch.key.source_fingerprint, patch.key.source_key, patch.key.dpi_bucket
            ),
            object_id: object_id.to_string(),
            bounds: native_box(patch.bounds),
            dpi: patch.key.dpi_bucket,
            width: patch.width,
            height: patch.height,
            rgba_bytes: patch.rgba_bytes.clone(),
            bleed_points: patch.bleed_points,
        })
    }

    pub fn release_clean_patch_memory(&self) {
        self.clean_patches.clear();
    }

    pub fn save(&self, request: NativeEditorSaveRequest) -> Result<NativeEditorSaveResult, String> {
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        let target = std::path::PathBuf::from(&request.target_path);
        let materializer = PdfTextMaterializer::new(self.source.clone());
        let validator = IndependentPdfValidator;
        let replacer = WindowsAtomicReplacer;
        let report = SaveCoordinator::new(&materializer, &validator, &replacer)
            .with_repository(self._repository.as_ref())
            .save(SaveRequest {
                source: SourceReference::new(self.source.fingerprint(), self.source.path()),
                target: target.clone(),
                mode: match request.mode {
                    NativeEditorSaveMode::Save => SaveMode::Save,
                    NativeEditorSaveMode::SaveAs => SaveMode::SaveAs,
                },
                association: match request.association {
                    NativeSaveAssociation::KeepOriginalAssociation => {
                        SaveAssociation::KeepOriginalAssociation
                    }
                    NativeSaveAssociation::FollowNewSource => SaveAssociation::FollowNewSource,
                },
                recovery_directory: request.recovery_directory.map(std::path::PathBuf::from),
                snapshot: snapshot.clone(),
            })
            .map_err(|error| {
                format!(
                    "save_failed:{}:{:?}:{}",
                    error.code, error.stage, error.message
                )
            })?;
        Ok(NativeEditorSaveResult {
            schema_version: EDITOR_SCHEMA_VERSION,
            target_path: target.to_string_lossy().into_owned(),
            materialized_revision: snapshot.revision.value(),
            completed_stages: report
                .completed_stages
                .iter()
                .map(|stage| format!("{stage:?}"))
                .collect(),
            warnings: report.validation.warnings,
            follows_new_source: report.association == SaveAssociation::FollowNewSource,
        })
    }

    pub fn checkpoint(
        &self,
        request: NativeCheckpointRequest,
    ) -> Result<NativeCommandResult, String> {
        self.actor
            .submit(CommandEnvelope::user(
                CommandId::new(),
                DocumentRevision::from_value(request.base_revision),
                EditorCommand::CreateCheckpoint {
                    label: request.label,
                },
            ))
            .map(native_command_result)
            .map_err(editing_error)
    }

    pub fn events(&self, sink: StreamSink<NativeEditorEvent>) -> Result<(), String> {
        let events = self.actor.subscribe().map_err(editing_error)?;
        let event_sequence = Arc::clone(&self.event_sequence);
        let session_id = self.actor.session_id().to_string();
        std::thread::Builder::new()
            .name(format!("clarix-editor-events-{}", self.actor.session_id()))
            .spawn(move || {
                for event in events {
                    let sequence = event_sequence.fetch_add(1, Ordering::AcqRel) + 1;
                    let native = native_event(event, &session_id, sequence);
                    if sink.add(native).is_err() {
                        break;
                    }
                }
            })
            .map_err(|error| format!("event_stream_failed: {error}"))?;
        Ok(())
    }

    pub fn close(&self) -> Result<(), String> {
        self.clean_patches.cancel();
        self.background_indexing
            .cancel_and_wait()
            .map_err(|error| format!("{}: {error}", error.code()))?;
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
            capability_reason: block.capability_reason().map(|reason| reason.code.clone()),
            modified_revision: object.modified_revision().value(),
            runs: block.runs.iter().map(native_text_run).collect(),
            layout: Some(NativeTextLayoutRecipe {
                baseline: block.layout.baseline,
                line_height: block.layout.line_height,
                character_spacing: block.layout.character_spacing,
                horizontal_scale: block.layout.horizontal_scale,
                direction: format!("{:?}", block.layout.direction).to_ascii_lowercase(),
            }),
            font_fingerprint: block.font().map(|font| font.bytes_sha256.clone()),
            font_asset_handle: block.font().and_then(|font| font.asset_id.clone()),
        },
        _ => NativeSceneObject {
            kind: NativeSceneObjectKind::Unsupported,
            object_id: object.id().to_string(),
            page_id: object.page_id().to_string(),
            text: None,
            bounds: native_box(object.bounds()),
            transform: native_transform(object.transform()),
            capability: format!("{:?}", object.capability()).to_ascii_lowercase(),
            capability_reason: None,
            modified_revision: object.modified_revision().value(),
            runs: Vec::new(),
            layout: None,
            font_fingerprint: None,
            font_asset_handle: None,
        },
    }
}

fn native_command_result(result: CommandResult) -> NativeCommandResult {
    NativeCommandResult {
        command_id: result.command_id.to_string(),
        previous_revision: result.previous_revision.value(),
        committed_revision: result.committed_revision.value(),
        durable: result.durable,
        warnings: result
            .warnings
            .into_iter()
            .map(|warning| format!("{}: {}", warning.code, warning.message))
            .collect(),
        selection_rebase: result.selection_rebase.map(|rebase| NativeSelectionRebase {
            object_id: rebase.object_id.to_string(),
            start: rebase.replaced_range.start,
            end: rebase.replaced_range.end,
            inserted_utf16_length: rebase.inserted_utf16_length,
        }),
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

fn native_event(event: EditorEvent, session_id: &str, sequence: u64) -> NativeEditorEvent {
    match event {
        EditorEvent::Ready { revision } => NativeEditorEvent {
            kind: NativeEditorEventKind::Ready,
            session_id: session_id.into(),
            sequence,
            revision: Some(revision.value()),
            latest_revision: None,
            result: None,
        },
        EditorEvent::CommandCommitted { result } => NativeEditorEvent {
            kind: NativeEditorEventKind::CommandCommitted,
            session_id: session_id.into(),
            sequence,
            revision: Some(result.committed_revision.value()),
            latest_revision: None,
            result: Some(native_command_result(result)),
        },
        EditorEvent::Lagged { latest_revision } => NativeEditorEvent {
            kind: NativeEditorEventKind::Lagged,
            session_id: session_id.into(),
            sequence,
            revision: None,
            latest_revision: Some(latest_revision.value()),
            result: None,
        },
        EditorEvent::Closed { revision } => NativeEditorEvent {
            kind: NativeEditorEventKind::Closed,
            session_id: session_id.into(),
            sequence,
            revision: Some(revision.value()),
            latest_revision: None,
            result: None,
        },
    }
}

fn viewport_priority(priority: NativeViewportPriority) -> ViewportPriority {
    match priority {
        NativeViewportPriority::Background => ViewportPriority::Background,
        NativeViewportPriority::Preload => ViewportPriority::Preload,
        NativeViewportPriority::Visible => ViewportPriority::Visible,
        NativeViewportPriority::ActiveSelection => ViewportPriority::ActiveSelection,
    }
}

fn editing_error(error: EditingError) -> String {
    format!("{}: {error}", error.code())
}

fn adapter_error(error: clarix_pdf_adapter::PdfAdapterError) -> String {
    format!("{}: {error}", error.code())
}
