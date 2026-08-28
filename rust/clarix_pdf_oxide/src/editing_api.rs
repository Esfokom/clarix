use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use clarix_editing_core::{
    AffineTransform, AnnotationAnchor, AnnotationKind, AnnotationNode, AnnotationTextRange,
    CommandEnvelope, CommandId, CommandResult, CompatibilityReporter, DocumentId, DocumentModel,
    DocumentObject, DocumentRevision, EditingError, EditorCommand, EditorEvent, EditorSessionActor,
    FontFallbackApproval, FontRef, FontSource, MaterializationPort, MaterializationReport,
    MemoryPressureLevel, ObjectId, ObjectPatch, PageId, PageIndexTask, PageSceneRequest,
    PageSceneService, PdfBox, PhysicalEditOperation, PhysicalEditPlan, PreparedCommand,
    RecoveryRequest, SaveAssociation, SaveCoordinator, SaveError, SaveMode, SaveRequest,
    SearchMode, SearchRequest, SelectionKind, SelectionSet, SessionId, SourceBinding,
    SourceReference, TextBlock, TextRangeRef, TextRun, TextStyle, Utf16Range, ViewportPriority,
};
use clarix_editing_store::{
    ProjectLocation, ProjectSeed, SqliteAgentRunRepository, SqliteProjectRepository,
};
use clarix_pdf_adapter::{
    CleanPatchCache, CleanPatchRenderRequest, CleanPatchRenderer, IndependentPdfValidator,
    InstalledFontCatalog, InstalledFontRequest, PdfImporter, PdfOxideImporter, PdfTextMaterializer,
    SourceRef, WindowsAtomicReplacer,
};
use sha2::{Digest, Sha256};

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

/// A page inspected by the Dart-owned live PDFium document. Its source keys
/// are canonical path identities, not matches derived from visual content.
#[derive(Debug, Clone)]
pub struct NativeLivePageImport {
    pub expected_revision: u64,
    pub page_number: u32,
    pub width: f64,
    pub height: f64,
    pub objects: Vec<NativeLiveTextObject>,
}

#[derive(Debug, Clone)]
pub struct NativeLiveTextObject {
    pub object_id: String,
    pub source_key: String,
    pub source_revision: String,
    pub text: String,
    pub bounds: NativePdfBox,
    pub style: NativeTextStyle,
    pub baseline: f64,
    pub editable: bool,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeViewportPriority {
    Background,
    Preload,
    Visible,
    ActiveSelection,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeSearchMode {
    Exact,
    CaseFolded,
    Normalized,
    Regex,
}

#[derive(Debug, Clone)]
pub struct NativeSearchRequest {
    pub expected_revision: u64,
    pub query: String,
    pub mode: NativeSearchMode,
    pub whole_word: bool,
    pub offset: u32,
    pub limit: u32,
}

#[derive(Debug, Clone)]
pub struct NativeSearchMatch {
    pub object_id: String,
    pub page_id: String,
    pub page_number: u32,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub quoted_text: String,
}

#[derive(Debug, Clone)]
pub struct NativeSearchResult {
    pub schema_version: u32,
    pub revision: u64,
    pub matches: Vec<NativeSearchMatch>,
    pub total_matches: u32,
    pub indexed_pages: u32,
    pub page_count: u32,
    pub is_complete: bool,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeSelectionKind {
    TextRanges,
    Objects,
}

#[derive(Debug, Clone)]
pub struct NativeSelectionRange {
    pub object_id: String,
    pub page_id: String,
    pub page_number: u32,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub quoted_text: String,
}

#[derive(Debug, Clone)]
pub struct NativeSelectionSet {
    pub expected_revision: u64,
    pub kind: NativeSelectionKind,
    pub ranges: Vec<NativeSelectionRange>,
    pub object_ids: Vec<String>,
    pub primary_index: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct NativeValidatedSelection {
    pub schema_version: u32,
    pub revision: u64,
    pub kind: NativeSelectionKind,
    pub ranges: Vec<NativeSelectionRange>,
    pub object_ids: Vec<String>,
    pub primary_index: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct NativeCompatibilityIssue {
    pub object_id: String,
    pub page_id: String,
    pub kind: String,
    pub capability: String,
    pub code: String,
    pub message: String,
    pub supported_operations: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct NativeCompatibilityReport {
    pub schema_version: u32,
    pub revision: u64,
    pub editable_count: u32,
    pub overlay_only_count: u32,
    pub read_only_count: u32,
    pub issues: Vec<NativeCompatibilityIssue>,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeAnnotationKind {
    Bookmark,
    Highlight,
    Comment,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeAnnotationAnchorKind {
    PagePoint,
    TextRanges,
}

#[derive(Debug, Clone)]
pub struct NativeAnnotationRange {
    pub range_id: String,
    pub object_id: String,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub quoted_text: String,
}

#[derive(Debug, Clone)]
pub struct NativeAnnotation {
    pub object_id: String,
    pub page_id: String,
    pub bounds: NativePdfBox,
    pub kind: NativeAnnotationKind,
    pub anchor_kind: NativeAnnotationAnchorKind,
    pub anchor_x: Option<f64>,
    pub anchor_y: Option<f64>,
    pub ranges: Vec<NativeAnnotationRange>,
    pub title: String,
    pub body: String,
    pub color_rgba: Vec<u8>,
    pub opacity: f32,
    pub resolved: bool,
}

#[derive(Debug, Clone)]
pub struct NativeAnnotationCommandRequest {
    pub schema_version: u32,
    pub command_id: String,
    pub base_revision: u64,
    pub annotation: NativeAnnotation,
}

#[derive(Debug, Clone)]
pub struct NativeDeleteAnnotationRequest {
    pub schema_version: u32,
    pub command_id: String,
    pub base_revision: u64,
    pub object_id: String,
}

#[derive(Debug, Clone, Copy)]
pub enum NativeMemoryPressureLevel {
    Moderate,
    Critical,
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

#[derive(Debug, Clone)]
pub struct NativeFontFallbackProposalRequest {
    pub schema_version: u32,
    pub base_revision: u64,
    pub object_id: String,
    pub start: u32,
    pub end: u32,
    pub replacement: String,
}

#[derive(Debug, Clone)]
pub struct NativeFontFallbackProposal {
    pub token: String,
    pub font_name: String,
    pub source: String,
    pub embedding_allowed: bool,
    pub affected_characters: String,
}

#[derive(Debug, Clone)]
pub struct NativeApproveFontFallbackRequest {
    pub schema_version: u32,
    pub command_id: String,
    pub base_revision: u64,
    pub proposal_token: String,
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
    pub character_boxes: Vec<NativeTextCharacterBox>,
    pub layout: Option<NativeTextLayoutRecipe>,
    pub font_fingerprint: Option<String>,
    pub font_asset_handle: Option<String>,
    /// Populated only by the live PDFium backend. Legacy adapter scenes do
    /// not have a physical PDFium object path and must remain explicit about
    /// that absence.
    pub physical_locator: Option<NativePhysicalLocator>,
}

#[derive(Debug, Clone)]
pub struct NativePhysicalLocator {
    pub page_number: u32,
    pub object_path: Vec<u32>,
    pub object_type: String,
    pub source_fingerprint: String,
    pub object_revision: u64,
}

#[derive(Debug, Clone)]
pub struct NativeDirtyTile {
    pub page_number: u32,
    pub revision: u64,
    pub bounds: NativePdfBox,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct NativeTileInvalidation {
    pub page_number: u32,
    pub bounds: NativePdfBox,
    pub revision: u64,
}

#[derive(Debug, Clone)]
pub struct NativeTextCharacterBox {
    pub start: u32,
    pub end: u32,
    pub bounds: NativePdfBox,
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
    pub removed_object_ids: Vec<String>,
    pub selection_rebase: Option<NativeSelectionRebase>,
    pub object_patches: Vec<NativeObjectPatch>,
}

/// A prepared semantic command paired with the physical text changes that the
/// single live PDFium owner must apply before this command may be published.
#[derive(Debug, Clone)]
pub struct NativePreparedLiveCommand {
    /// Opaque, single-use token consumed by `publish_prepared_live_command`.
    pub token: String,
    pub command_id: String,
    pub previous_revision: u64,
    pub committed_revision: u64,
    pub plan: NativePhysicalEditPlan,
}

#[derive(Debug, Clone)]
pub struct NativePhysicalEditPlan {
    pub previous_revision: u64,
    pub revision: u64,
    pub operations: Vec<NativePhysicalEditOperation>,
    pub inverse_operations: Vec<NativePhysicalEditOperation>,
}

#[derive(Debug, Clone)]
pub struct NativePhysicalEditOperation {
    pub kind: NativePhysicalEditOperationKind,
    pub object_id: String,
    /// Stable source key used by the live PDFium scene's locator table.
    pub source_key: String,
    pub source_revision: String,
    pub expected_text: Option<String>,
    pub replacement: Option<String>,
    pub expected_transform: Option<NativeAffineTransform>,
    pub transform: Option<NativeAffineTransform>,
    pub old_bounds: NativePdfBox,
    pub new_bounds: NativePdfBox,
}

#[derive(Debug, Clone, Copy)]
pub enum NativePhysicalEditOperationKind {
    ReplaceText,
    SetTextTransform,
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
    pub character_boxes: Option<Vec<NativeTextCharacterBox>>,
    pub bounds: Option<NativePdfBox>,
    pub transform: Option<NativeAffineTransform>,
    pub font_fingerprint: Option<String>,
    pub font_asset_handle: Option<String>,
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
    pub(crate) actor: EditorSessionActor,
    page_service: PageSceneService,
    background_indexing: Option<PageIndexTask>,
    clean_patches: CleanPatchCache,
    _repository: Arc<SqliteProjectRepository>,
    source: SourceRef,
    document_id: DocumentId,
    page_count: u32,
    event_sequence: Arc<AtomicU64>,
    fallback_proposals: Mutex<HashMap<String, PendingFontFallback>>,
    prepared_live_commands: Mutex<HashMap<String, PreparedCommand>>,
    fallback_assets: PathBuf,
    pub(crate) agent_runtime: crate::agent_api::NativeAgentRuntime,
}

#[derive(Debug, Clone)]
struct PendingFontFallback {
    base_revision: DocumentRevision,
    object_id: ObjectId,
    range: Utf16Range,
    replacement: String,
    approval: FontFallbackApproval,
}

struct EncodedPdfMaterializer {
    bytes: Vec<u8>,
}

impl MaterializationPort for EncodedPdfMaterializer {
    fn materialize(
        &self,
        _: &DocumentModel,
        target: &Path,
    ) -> Result<MaterializationReport, SaveError> {
        std::fs::write(target, &self.bytes).map_err(|error| {
            SaveError::new(
                clarix_editing_core::SaveStage::MaterializeTemp,
                "live_pdfium_write_failed",
                error.to_string(),
            )
        })?;
        Ok(MaterializationReport {
            output_sha256: format!("{:x}", Sha256::digest(&self.bytes)),
            bytes_written: self.bytes.len() as u64,
            warnings: Vec::new(),
        })
    }
}

impl NativeEditorSession {
    pub fn open(request: NativeOpenEditorRequest) -> Result<Self, String> {
        Self::open_with_background_indexing(request, true)
    }

    /// Opens a semantic session whose visible pages will be hydrated from the
    /// Dart-owned live PDFium document. The legacy span importer must stay
    /// idle: it produces a different source-identity domain.
    pub fn open_live_pdfium(request: NativeOpenEditorRequest) -> Result<Self, String> {
        Self::open_with_background_indexing(request, false)
    }

    fn open_with_background_indexing(
        request: NativeOpenEditorRequest,
        start_background_indexing: bool,
    ) -> Result<Self, String> {
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
        // Live PDFium uses path-derived object identities. Older sessions used
        // a span-derived projection in the unversioned project directory;
        // isolate the live projection without deleting that recoverable state.
        let project_root = if start_background_indexing {
            project_root
        } else {
            project_root.join("live-pdfium-v1")
        };
        let project_location = ProjectLocation::under(&project_root, document_id);
        let fallback_assets = project_location.assets.clone();
        let repository = Arc::new(
            SqliteProjectRepository::open(
                project_location.clone(),
                ProjectSeed {
                    model: model.clone(),
                    undo_cursor: 0,
                    materialized_revision: None,
                },
            )
            .map_err(|error| format!("sidecar_open_failed: {error}"))?,
        );
        let agent_repository = Arc::new(
            SqliteAgentRunRepository::open(&project_location.database)
                .map_err(|error| format!("agent_sidecar_open_failed: {error}"))?,
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
        let background_indexing =
            start_background_indexing.then(|| page_service.start_background_indexing());
        let agent_runtime =
            crate::agent_api::NativeAgentRuntime::new(actor.clone(), agent_repository);
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
            fallback_proposals: Mutex::new(HashMap::new()),
            prepared_live_commands: Mutex::new(HashMap::new()),
            fallback_assets,
            agent_runtime,
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

    pub fn import_live_page(&self, request: NativeLivePageImport) -> Result<(), String> {
        let revision = DocumentRevision::from_value(request.expected_revision);
        let page_id = PageId::from_source_key(&format!(
            "{}/live-pdfium/page/{}",
            self.source.fingerprint(),
            request.page_number
        ));
        let mut objects = Vec::with_capacity(request.objects.len());
        for imported in request.objects {
            if imported.source_revision != self.source.fingerprint() {
                return Err("live_pdfium_import_source_mismatch".into());
            }
            let object_id = parse_object_id(&imported.object_id)?;
            let mut block =
                TextBlock::plain(object_id, page_id, imported.text, pdf_box(imported.bounds)?)
                    .with_source_binding(SourceBinding {
                        adapter_id: "live-pdfium".into(),
                        source_revision: imported.source_revision,
                        source_key: imported.source_key,
                        confidence: 1.0,
                    })
                    .with_capability(
                        if imported.editable {
                            clarix_editing_core::EditCapability::Editable
                        } else {
                            clarix_editing_core::EditCapability::ReadOnly
                        },
                        None,
                    );
            block.runs[0].style = text_style(imported.style)?;
            block.layout.baseline = imported.baseline;
            objects.push(DocumentObject::text(block));
        }
        let page = clarix_editing_core::PageNode::new(
            page_id,
            request.page_number,
            request.width,
            request.height,
            objects,
        );
        self.actor
            .hydrate_live_page(page, revision)
            .map_err(editing_error)
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

    pub fn search(&self, request: NativeSearchRequest) -> Result<NativeSearchResult, String> {
        let expected_revision = DocumentRevision::from_value(request.expected_revision);
        let result = self
            .actor
            .search(SearchRequest {
                query: request.query,
                mode: native_search_mode(request.mode),
                whole_word: request.whole_word,
                offset: request.offset,
                limit: request.limit,
            })
            .map_err(editing_error)?;
        if result.revision != expected_revision {
            return Err(editing_error(EditingError::RevisionConflict {
                expected: expected_revision,
                actual: result.revision,
            }));
        }
        Ok(NativeSearchResult {
            schema_version: EDITOR_SCHEMA_VERSION,
            revision: result.revision.value(),
            matches: result
                .matches
                .into_iter()
                .map(|matched| NativeSearchMatch {
                    object_id: matched.object_id.to_string(),
                    page_id: matched.page_id.to_string(),
                    page_number: matched.page_number,
                    start_utf16: matched.start_utf16,
                    end_utf16: matched.end_utf16,
                    quoted_text: matched.quoted_text,
                })
                .collect(),
            total_matches: result.total_matches,
            indexed_pages: result.indexed_pages,
            page_count: result.page_count,
            is_complete: result.is_complete,
        })
    }

    pub fn validate_selection(
        &self,
        selection: NativeSelectionSet,
    ) -> Result<NativeValidatedSelection, String> {
        let validated = self
            .actor
            .validate_selection(SelectionSet {
                revision: DocumentRevision::from_value(selection.expected_revision),
                kind: native_selection_kind(selection.kind),
                ranges: selection
                    .ranges
                    .into_iter()
                    .map(native_selection_range)
                    .collect::<Result<Vec<_>, _>>()?,
                object_ids: selection
                    .object_ids
                    .iter()
                    .map(|object_id| parse_object_id(object_id))
                    .collect::<Result<Vec<_>, _>>()?,
                primary_index: selection.primary_index,
            })
            .map_err(editing_error)?;
        Ok(NativeValidatedSelection {
            schema_version: EDITOR_SCHEMA_VERSION,
            revision: validated.revision.value(),
            kind: native_selection_kind_to_native(validated.kind),
            ranges: validated
                .ranges
                .into_iter()
                .map(native_selection_range_from_core)
                .collect(),
            object_ids: validated
                .object_ids
                .into_iter()
                .map(|object_id| object_id.to_string())
                .collect(),
            primary_index: validated.primary_index,
        })
    }

    pub fn compatibility_report(
        &self,
        expected_revision: u64,
    ) -> Result<NativeCompatibilityReport, String> {
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        let expected_revision = DocumentRevision::from_value(expected_revision);
        if snapshot.revision != expected_revision {
            return Err(editing_error(EditingError::RevisionConflict {
                expected: expected_revision,
                actual: snapshot.revision,
            }));
        }
        let report = CompatibilityReporter::for_document(&snapshot);
        Ok(NativeCompatibilityReport {
            schema_version: EDITOR_SCHEMA_VERSION,
            revision: report.revision.value(),
            editable_count: report.editable_count,
            overlay_only_count: report.overlay_only_count,
            read_only_count: report.read_only_count,
            issues: report
                .issues
                .into_iter()
                .map(|issue| NativeCompatibilityIssue {
                    object_id: issue.object_id.to_string(),
                    page_id: issue.page_id.to_string(),
                    kind: format!("{:?}", issue.kind).to_ascii_lowercase(),
                    capability: format!("{:?}", issue.capability).to_ascii_lowercase(),
                    code: issue.code,
                    message: issue.message,
                    supported_operations: issue.supported_operations,
                })
                .collect(),
        })
    }

    pub fn report_memory_pressure(&self, level: NativeMemoryPressureLevel) {
        self.page_service.report_memory_pressure(match level {
            NativeMemoryPressureLevel::Moderate => MemoryPressureLevel::Moderate,
            NativeMemoryPressureLevel::Critical => MemoryPressureLevel::Critical,
        });
        if matches!(level, NativeMemoryPressureLevel::Critical) {
            self.clean_patches.clear();
        }
    }

    pub fn create_annotation(
        &self,
        request: NativeAnnotationCommandRequest,
    ) -> Result<NativeCommandResult, String> {
        let annotation = native_annotation_request(&request)?;
        self.submit_annotation_command(
            request.command_id,
            request.base_revision,
            EditorCommand::CreateAnnotation { annotation },
        )
    }

    pub fn update_annotation(
        &self,
        request: NativeAnnotationCommandRequest,
    ) -> Result<NativeCommandResult, String> {
        let annotation = native_annotation_request(&request)?;
        self.submit_annotation_command(
            request.command_id,
            request.base_revision,
            EditorCommand::UpdateAnnotation { annotation },
        )
    }

    pub fn delete_annotation(
        &self,
        request: NativeDeleteAnnotationRequest,
    ) -> Result<NativeCommandResult, String> {
        if request.schema_version != EDITOR_SCHEMA_VERSION {
            return Err(format!(
                "schema_mismatch: expected {EDITOR_SCHEMA_VERSION}, got {}",
                request.schema_version
            ));
        }
        self.submit_annotation_command(
            request.command_id,
            request.base_revision,
            EditorCommand::DeleteAnnotation {
                object_id: parse_object_id(&request.object_id)?,
            },
        )
    }

    pub fn annotation_details(&self, object_id: String) -> Result<NativeAnnotation, String> {
        let object_id = parse_object_id(&object_id)?;
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        let Some(DocumentObject::Annotation(annotation)) = snapshot.object(object_id) else {
            return Err(format!("annotation_not_found: {object_id}"));
        };
        Ok(native_annotation_from_core(annotation))
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
        self.fallback_proposals
            .lock()
            .map_err(|_| "font_fallback_unavailable: proposal lock poisoned".to_owned())?
            .clear();
        self.page_service.set_revision(result.committed_revision);
        Ok(native_command_result(result))
    }

    /// Validates a semantic command and exposes its live-PDFium physical plan
    /// without changing the canonical Rust revision or durable journal.
    pub fn prepare_live_command(
        &self,
        request: NativeSubmitCommandRequest,
    ) -> Result<NativePreparedLiveCommand, String> {
        if request.schema_version != EDITOR_SCHEMA_VERSION {
            return Err(format!(
                "schema_mismatch: expected {EDITOR_SCHEMA_VERSION}, got {}",
                request.schema_version
            ));
        }
        let command_id = CommandId::from_str(&request.command_id)
            .map_err(|error| format!("invalid_command_id: {error}"))?;
        let payload = editor_command(request.payload)?;
        let prepared = self
            .actor
            .prepare(CommandEnvelope::user(
                command_id,
                DocumentRevision::from_value(request.base_revision),
                payload,
            ))
            .map_err(editing_error)?;
        let plan = prepared.physical_plan.as_ref().ok_or_else(|| {
            "live_pdfium_unsupported: command has no physical PDFium edit plan".to_owned()
        })?;
        let token = CommandId::new().to_string();
        let response = NativePreparedLiveCommand {
            token: token.clone(),
            command_id: prepared.envelope.command_id.to_string(),
            previous_revision: prepared.previous_revision.value(),
            committed_revision: prepared.committed_revision.value(),
            plan: native_physical_edit_plan(plan),
        };
        self.prepared_live_commands
            .lock()
            .map_err(|_| "prepared_command_unavailable: lock poisoned".to_owned())?
            .insert(token, prepared);
        Ok(response)
    }

    /// Publishes the prepared command only after the Dart-owned live PDFium
    /// document reports that it applied the returned physical edit plan.
    pub fn publish_prepared_live_command(
        &self,
        token: String,
    ) -> Result<NativeCommandResult, String> {
        let prepared = self
            .prepared_live_commands
            .lock()
            .map_err(|_| "prepared_command_unavailable: lock poisoned".to_owned())?
            .remove(&token)
            .ok_or_else(|| "prepared_command_not_found".to_owned())?;
        let result = self.actor.publish(prepared).map_err(editing_error)?;
        self.fallback_proposals
            .lock()
            .map_err(|_| "font_fallback_unavailable: proposal lock poisoned".to_owned())?
            .clear();
        self.page_service.set_revision(result.committed_revision);
        Ok(native_command_result(result))
    }

    fn submit_annotation_command(
        &self,
        command_id: String,
        base_revision: u64,
        payload: EditorCommand,
    ) -> Result<NativeCommandResult, String> {
        let command_id = CommandId::from_str(&command_id)
            .map_err(|error| format!("invalid_command_id: {error}"))?;
        let result = self
            .actor
            .submit(CommandEnvelope::user(
                command_id,
                DocumentRevision::from_value(base_revision),
                payload,
            ))
            .map_err(editing_error)?;
        self.page_service.set_revision(result.committed_revision);
        Ok(native_command_result(result))
    }

    pub fn propose_font_fallback(
        &self,
        request: NativeFontFallbackProposalRequest,
    ) -> Result<NativeFontFallbackProposal, String> {
        if request.schema_version != EDITOR_SCHEMA_VERSION {
            return Err(format!(
                "schema_mismatch: expected {EDITOR_SCHEMA_VERSION}, got {}",
                request.schema_version
            ));
        }
        let expected_revision = DocumentRevision::from_value(request.base_revision);
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        if snapshot.revision != expected_revision {
            return Err(editing_error(EditingError::RevisionConflict {
                expected: expected_revision,
                actual: snapshot.revision,
            }));
        }
        let object_id = parse_object_id(&request.object_id)?;
        let object = snapshot
            .object(object_id)
            .ok_or_else(|| format!("object_not_found: {object_id}"))?;
        let DocumentObject::Text(block) = object else {
            return Err(format!("wrong_object_kind: {object_id}"));
        };
        let range = Utf16Range::new(request.start, request.end)
            .map_err(|error| format!("invalid_text_boundary: {error}"))?;
        let candidate = replace_utf16(&block.text, range, &request.replacement)?;
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
        if affected_characters.is_empty() {
            return Err("font_fallback_unavailable: replacement needs no fallback".into());
        }
        let style = block.runs.first().map(|run| &run.style);
        let preferred_family = style
            .and_then(|style| style.font_family.clone())
            .or_else(|| block.font().map(|font| font.postscript_name.clone()))
            .unwrap_or_default();
        let face = InstalledFontCatalog::windows()
            .propose(&InstalledFontRequest {
                preferred_family,
                weight: style.map_or(400, |style| style.font_weight),
                italic: style.is_some_and(|style| style.italic),
                text: candidate,
            })
            .ok_or_else(|| {
                "font_fallback_unavailable: no embeddable installed TrueType font covers the replacement"
                    .to_owned()
            })?;
        let token = CommandId::new().to_string();
        let font_name = face.family.clone();
        let approval = FontFallbackApproval {
            proposal_token: token.clone(),
            font: FontRef {
                postscript_name: face.postscript_name,
                bytes_sha256: face.bytes_sha256,
                asset_id: Some(face.path.to_string_lossy().into_owned()),
                source: FontSource::ApprovedFallback,
                embeddable: true,
            },
            glyphs: face.glyphs,
        };
        let pending = PendingFontFallback {
            base_revision: expected_revision,
            object_id,
            range,
            replacement: request.replacement,
            approval,
        };
        let mut proposals = self
            .fallback_proposals
            .lock()
            .map_err(|_| "font_fallback_unavailable: proposal lock poisoned".to_owned())?;
        proposals.retain(|_, proposal| {
            proposal.base_revision == expected_revision && proposal.object_id != object_id
        });
        proposals.insert(token.clone(), pending);
        Ok(NativeFontFallbackProposal {
            token,
            font_name,
            source: "installed".into(),
            embedding_allowed: true,
            affected_characters,
        })
    }

    pub fn approve_font_fallback(
        &self,
        request: NativeApproveFontFallbackRequest,
    ) -> Result<NativeCommandResult, String> {
        if request.schema_version != EDITOR_SCHEMA_VERSION {
            return Err(format!(
                "schema_mismatch: expected {EDITOR_SCHEMA_VERSION}, got {}",
                request.schema_version
            ));
        }
        let command_id = CommandId::from_str(&request.command_id)
            .map_err(|error| format!("invalid_command_id: {error}"))?;
        let mut pending = self
            .fallback_proposals
            .lock()
            .map_err(|_| "font_fallback_proposal_invalid: proposal lock poisoned".to_owned())?
            .get(&request.proposal_token)
            .cloned()
            .ok_or_else(|| {
                "font_fallback_proposal_invalid: proposal is unknown or already used".to_owned()
            })?;
        let source_asset = pending.approval.font.asset_id.as_deref().ok_or_else(|| {
            "font_fallback_asset_invalid: proposal has no source font asset".to_owned()
        })?;
        let durable_asset = persist_fallback_asset(
            Path::new(source_asset),
            &self.fallback_assets,
            &pending.approval.font.bytes_sha256,
        )?;
        pending.approval.font.asset_id = Some(durable_asset.to_string_lossy().into_owned());
        let base_revision = DocumentRevision::from_value(request.base_revision);
        if pending.base_revision != base_revision {
            return Err("font_fallback_proposal_invalid: proposal revision is stale".into());
        }
        let result = self
            .actor
            .submit(CommandEnvelope::user(
                command_id,
                base_revision,
                EditorCommand::ReplaceTextRangeWithFontFallback {
                    object_id: pending.object_id,
                    range: pending.range,
                    replacement: pending.replacement,
                    approval: Box::new(pending.approval),
                },
            ))
            .map_err(editing_error)?;
        self.fallback_proposals
            .lock()
            .map_err(|_| "font_fallback_proposal_invalid: proposal lock poisoned".to_owned())?
            .remove(&request.proposal_token);
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
        let materializer = PdfTextMaterializer::new(self.source.clone());
        self.save_with_materializer(request, &materializer)
    }

    pub fn save_live_pdfium(
        &self,
        request: NativeEditorSaveRequest,
        pdf_bytes: Vec<u8>,
    ) -> Result<NativeEditorSaveResult, String> {
        if pdf_bytes.is_empty() {
            return Err("live_pdfium_save_empty".into());
        }
        let materializer = EncodedPdfMaterializer { bytes: pdf_bytes };
        self.save_with_materializer(request, &materializer)
    }

    fn save_with_materializer(
        &self,
        request: NativeEditorSaveRequest,
        materializer: &dyn MaterializationPort,
    ) -> Result<NativeEditorSaveResult, String> {
        let snapshot = self.actor.snapshot().map_err(editing_error)?;
        let target = std::path::PathBuf::from(&request.target_path);
        let validator = IndependentPdfValidator;
        let replacer = WindowsAtomicReplacer;
        let report = SaveCoordinator::new(materializer, &validator, &replacer)
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
        self.agent_runtime.close()?;
        self.prepared_live_commands
            .lock()
            .map_err(|_| "prepared_command_unavailable: lock poisoned".to_owned())?
            .clear();
        self.clean_patches.cancel();
        if let Some(background_indexing) = &self.background_indexing {
            background_indexing
                .cancel_and_wait()
                .map_err(|error| format!("{}: {error}", error.code()))?;
        }
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

fn replace_utf16(text: &str, range: Utf16Range, replacement: &str) -> Result<String, String> {
    clarix_editing_core::validate_utf16_range(text, range)
        .map_err(|error| format!("invalid_text_boundary: {error}"))?;
    let mut utf16_offset = 0_u32;
    let mut start = None;
    let mut end = None;
    for (byte_offset, character) in text.char_indices() {
        if utf16_offset == range.start {
            start = Some(byte_offset);
        }
        if utf16_offset == range.end {
            end = Some(byte_offset);
            break;
        }
        utf16_offset += character.len_utf16() as u32;
    }
    if utf16_offset == range.start {
        start.get_or_insert(text.len());
    }
    if utf16_offset == range.end {
        end.get_or_insert(text.len());
    }
    let mut output = text.to_owned();
    output.replace_range(
        start.expect("validated UTF-16 start")..end.expect("validated UTF-16 end"),
        replacement,
    );
    Ok(output)
}

fn persist_fallback_asset(
    source: &Path,
    assets: &Path,
    expected_sha256: &str,
) -> Result<PathBuf, String> {
    let bytes =
        std::fs::read(source).map_err(|error| format!("font_fallback_asset_invalid: {error}"))?;
    let actual_sha256 = format!("{:x}", Sha256::digest(&bytes));
    if actual_sha256 != expected_sha256.to_ascii_lowercase() {
        return Err(
            "font_fallback_asset_invalid: installed font changed after proposal".to_owned(),
        );
    }
    let destination = assets.join(format!("font-{actual_sha256}.ttf"));
    if destination.exists() {
        let existing = std::fs::read(&destination)
            .map_err(|error| format!("font_fallback_asset_invalid: {error}"))?;
        if format!("{:x}", Sha256::digest(&existing)) != actual_sha256 {
            return Err(
                "font_fallback_asset_invalid: content-addressed asset is corrupt".to_owned(),
            );
        }
        return Ok(destination);
    }
    let mut output = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&destination)
        .map_err(|error| format!("font_fallback_asset_invalid: {error}"))?;
    if let Err(error) = output.write_all(&bytes).and_then(|()| output.sync_all()) {
        drop(output);
        let _ = std::fs::remove_file(&destination);
        return Err(format!("font_fallback_asset_invalid: {error}"));
    }
    Ok(destination)
}

fn parse_object_id(value: &str) -> Result<ObjectId, String> {
    ObjectId::from_str(value).map_err(|error| format!("invalid_object_id: {error}"))
}

fn native_selection_kind(kind: NativeSelectionKind) -> SelectionKind {
    match kind {
        NativeSelectionKind::TextRanges => SelectionKind::TextRanges,
        NativeSelectionKind::Objects => SelectionKind::Objects,
    }
}

fn native_selection_kind_to_native(kind: SelectionKind) -> NativeSelectionKind {
    match kind {
        SelectionKind::TextRanges => NativeSelectionKind::TextRanges,
        SelectionKind::Objects => NativeSelectionKind::Objects,
    }
}

fn native_selection_range(range: NativeSelectionRange) -> Result<TextRangeRef, String> {
    Ok(TextRangeRef {
        object_id: parse_object_id(&range.object_id)?,
        page_id: clarix_editing_core::PageId::from_str(&range.page_id)
            .map_err(|error| format!("invalid_page_id: {error}"))?,
        page_number: range.page_number,
        start_utf16: range.start_utf16,
        end_utf16: range.end_utf16,
        quoted_text: range.quoted_text,
    })
}

fn native_selection_range_from_core(range: TextRangeRef) -> NativeSelectionRange {
    NativeSelectionRange {
        object_id: range.object_id.to_string(),
        page_id: range.page_id.to_string(),
        page_number: range.page_number,
        start_utf16: range.start_utf16,
        end_utf16: range.end_utf16,
        quoted_text: range.quoted_text,
    }
}

fn native_annotation_request(
    request: &NativeAnnotationCommandRequest,
) -> Result<AnnotationNode, String> {
    if request.schema_version != EDITOR_SCHEMA_VERSION {
        return Err(format!(
            "schema_mismatch: expected {EDITOR_SCHEMA_VERSION}, got {}",
            request.schema_version
        ));
    }
    native_annotation(request.annotation.clone())
}

fn native_annotation(annotation: NativeAnnotation) -> Result<AnnotationNode, String> {
    let id = parse_object_id(&annotation.object_id)?;
    let page_id = clarix_editing_core::PageId::from_str(&annotation.page_id)
        .map_err(|error| format!("invalid_page_id: {error}"))?;
    let bounds = pdf_box(annotation.bounds)?;
    let color_rgba = annotation
        .color_rgba
        .try_into()
        .map_err(|_| "invalid_annotation: RGBA must contain four channels".to_owned())?;
    if !annotation.opacity.is_finite() || !(0.0..=1.0).contains(&annotation.opacity) {
        return Err("invalid_annotation: opacity must be finite and between zero and one".into());
    }
    let anchor = match annotation.anchor_kind {
        NativeAnnotationAnchorKind::PagePoint => {
            if !annotation.ranges.is_empty() {
                return Err(
                    "invalid_annotation: page-point anchors cannot contain text ranges".into(),
                );
            }
            let x = required(annotation.anchor_x, "annotation.anchor_x")?;
            let y = required(annotation.anchor_y, "annotation.anchor_y")?;
            if !x.is_finite() || !y.is_finite() {
                return Err("invalid_annotation: page-point coordinates must be finite".into());
            }
            AnnotationAnchor::PagePoint { x, y }
        }
        NativeAnnotationAnchorKind::TextRanges => {
            if annotation.ranges.is_empty() {
                return Err("invalid_annotation: text anchors require at least one range".into());
            }
            AnnotationAnchor::Text {
                ranges: annotation
                    .ranges
                    .into_iter()
                    .map(|range| {
                        if range.range_id.trim().is_empty() {
                            return Err(
                                "invalid_annotation: text range ID must not be empty".into()
                            );
                        }
                        if range.start_utf16 >= range.end_utf16 {
                            return Err("invalid_annotation: text range must not be empty".into());
                        }
                        Ok(AnnotationTextRange {
                            range_id: range.range_id,
                            object_id: parse_object_id(&range.object_id)?,
                            start_utf16: range.start_utf16,
                            end_utf16: range.end_utf16,
                            quoted_text: range.quoted_text,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
            }
        }
    };
    Ok(AnnotationNode::new(
        id,
        page_id,
        bounds,
        match annotation.kind {
            NativeAnnotationKind::Bookmark => AnnotationKind::Bookmark,
            NativeAnnotationKind::Highlight => AnnotationKind::Highlight,
            NativeAnnotationKind::Comment => AnnotationKind::Comment,
        },
        anchor,
        annotation.title,
        annotation.body,
        color_rgba,
        annotation.opacity,
        annotation.resolved,
    ))
}

fn native_annotation_from_core(annotation: &AnnotationNode) -> NativeAnnotation {
    let (anchor_kind, anchor_x, anchor_y, ranges) = match &annotation.anchor {
        AnnotationAnchor::PagePoint { x, y } => (
            NativeAnnotationAnchorKind::PagePoint,
            Some(*x),
            Some(*y),
            Vec::new(),
        ),
        AnnotationAnchor::Text { ranges } => (
            NativeAnnotationAnchorKind::TextRanges,
            None,
            None,
            ranges
                .iter()
                .map(|range| NativeAnnotationRange {
                    range_id: range.range_id.clone(),
                    object_id: range.object_id.to_string(),
                    start_utf16: range.start_utf16,
                    end_utf16: range.end_utf16,
                    quoted_text: range.quoted_text.clone(),
                })
                .collect(),
        ),
    };
    NativeAnnotation {
        object_id: annotation.id().to_string(),
        page_id: annotation.page_id().to_string(),
        bounds: native_box(annotation.bounds()),
        kind: match annotation.kind {
            AnnotationKind::Bookmark => NativeAnnotationKind::Bookmark,
            AnnotationKind::Highlight => NativeAnnotationKind::Highlight,
            AnnotationKind::Comment => NativeAnnotationKind::Comment,
        },
        anchor_kind,
        anchor_x,
        anchor_y,
        ranges,
        title: annotation.title.clone(),
        body: annotation.body.clone(),
        color_rgba: annotation.color_rgba.to_vec(),
        opacity: annotation.opacity,
        resolved: annotation.resolved,
    }
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
            character_boxes: block
                .character_boxes
                .iter()
                .map(|character| NativeTextCharacterBox {
                    start: character.range.start,
                    end: character.range.end,
                    bounds: native_box(character.bounds),
                })
                .collect(),
            layout: Some(NativeTextLayoutRecipe {
                baseline: block.layout.baseline,
                line_height: block.layout.line_height,
                character_spacing: block.layout.character_spacing,
                horizontal_scale: block.layout.horizontal_scale,
                direction: format!("{:?}", block.layout.direction).to_ascii_lowercase(),
            }),
            font_fingerprint: block.font().map(|font| font.bytes_sha256.clone()),
            font_asset_handle: block.font().and_then(|font| font.asset_id.clone()),
            physical_locator: None,
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
            character_boxes: Vec::new(),
            layout: None,
            font_fingerprint: None,
            font_asset_handle: None,
            physical_locator: None,
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
        removed_object_ids: result
            .removed_object_ids
            .into_iter()
            .map(|object_id| object_id.to_string())
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

fn native_physical_edit_plan(plan: &PhysicalEditPlan) -> NativePhysicalEditPlan {
    NativePhysicalEditPlan {
        previous_revision: plan.previous_revision.value(),
        revision: plan.revision.value(),
        operations: plan
            .operations
            .iter()
            .map(native_physical_edit_operation)
            .collect(),
        inverse_operations: plan
            .inverse_operations
            .iter()
            .map(native_physical_edit_operation)
            .collect(),
    }
}

fn native_physical_edit_operation(
    operation: &PhysicalEditOperation,
) -> NativePhysicalEditOperation {
    match operation {
        PhysicalEditOperation::ReplaceText {
            object_id,
            source_key,
            source_revision,
            expected_text,
            replacement,
            bounds,
        } => NativePhysicalEditOperation {
            kind: NativePhysicalEditOperationKind::ReplaceText,
            object_id: object_id.to_string(),
            source_key: source_key.clone(),
            source_revision: source_revision.clone(),
            expected_text: Some(expected_text.clone()),
            replacement: Some(replacement.clone()),
            expected_transform: None,
            transform: None,
            old_bounds: native_box(*bounds),
            new_bounds: native_box(*bounds),
        },
        PhysicalEditOperation::SetTextTransform {
            object_id,
            source_key,
            source_revision,
            expected_transform,
            transform,
            old_bounds,
            new_bounds,
        } => NativePhysicalEditOperation {
            kind: NativePhysicalEditOperationKind::SetTextTransform,
            object_id: object_id.to_string(),
            source_key: source_key.clone(),
            source_revision: source_revision.clone(),
            expected_text: None,
            replacement: None,
            expected_transform: Some(native_transform(*expected_transform)),
            transform: Some(native_transform(*transform)),
            old_bounds: native_box(*old_bounds),
            new_bounds: native_box(*new_bounds),
        },
    }
}

fn native_object_patch(patch: ObjectPatch) -> NativeObjectPatch {
    let font_fingerprint = patch.font.as_ref().map(|font| font.bytes_sha256.clone());
    let font_asset_handle = patch.font.as_ref().and_then(|font| font.asset_id.clone());
    NativeObjectPatch {
        object_id: patch.object_id.to_string(),
        page_id: patch.page_id.to_string(),
        modified_revision: patch.modified_revision.value(),
        text: patch.text,
        text_runs: patch
            .text_runs
            .map(|runs| runs.iter().map(native_text_run).collect()),
        character_boxes: patch.character_boxes.map(|characters| {
            characters
                .into_iter()
                .map(|character| NativeTextCharacterBox {
                    start: character.range.start,
                    end: character.range.end,
                    bounds: native_box(character.bounds),
                })
                .collect()
        }),
        bounds: patch.bounds.map(native_box),
        transform: patch.transform.map(native_transform),
        font_fingerprint,
        font_asset_handle,
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

fn native_search_mode(mode: NativeSearchMode) -> SearchMode {
    match mode {
        NativeSearchMode::Exact => SearchMode::Exact,
        NativeSearchMode::CaseFolded => SearchMode::CaseFolded,
        NativeSearchMode::Normalized => SearchMode::Normalized,
        NativeSearchMode::Regex => SearchMode::Regex,
    }
}

fn editing_error(error: EditingError) -> String {
    format!("{}: {error}", error.code())
}

fn adapter_error(error: clarix_pdf_adapter::PdfAdapterError) -> String {
    format!("{}: {error}", error.code())
}
