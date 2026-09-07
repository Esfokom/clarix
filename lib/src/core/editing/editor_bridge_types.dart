import 'dart:typed_data';

enum EditorSceneObjectKind { text, unsupported }

enum EditorCommandKind {
  replaceTextRange,
  setTextStyle,
  moveObject,
  resizeObject,
  rotateObject,
  createCheckpoint,
  undo,
  redo,
}

enum EditorSearchMode { exact, caseFolded, normalized, regex }

enum EditorSelectionKind { textRanges, objects }

enum EditorAnnotationKind { bookmark, highlight, comment }

enum EditorAnnotationAnchorKind { pagePoint, textRanges }

enum EditorMemoryPressureLevel { moderate, critical }

enum EditorEventKind { ready, commandCommitted, lagged, closed }

enum EditorViewportPriority { background, preload, visible, activeSelection }

enum EditorSaveMode { save, saveAs }

enum EditorSaveAssociation { keepOriginalAssociation, followNewSource }

class EditorSaveRequest {
  const EditorSaveRequest({
    required this.targetPath,
    required this.mode,
    required this.association,
    this.recoveryDirectory,
  });

  final String targetPath;
  final EditorSaveMode mode;
  final EditorSaveAssociation association;
  final String? recoveryDirectory;
}

class EditorSaveResult {
  const EditorSaveResult({
    this.schemaVersion = 1,
    required this.targetPath,
    required this.materializedRevision,
    required this.completedStages,
    required this.warnings,
    required this.followsNewSource,
  });

  final int schemaVersion;
  final String targetPath;
  final int materializedRevision;
  final List<String> completedStages;
  final List<String> warnings;
  final bool followsNewSource;
}

class EditorCleanPatchAsset {
  const EditorCleanPatchAsset({
    required this.handle,
    required this.objectId,
    required this.bounds,
    required this.dpi,
    required this.width,
    required this.height,
    required this.rgbaBytes,
    required this.bleedPoints,
  });

  final String handle;
  final String objectId;
  final EditorPdfBox bounds;
  final int dpi;
  final int width;
  final int height;
  final Uint8List rgbaBytes;
  final double bleedPoints;
}

class EditorFontFallbackProposal {
  const EditorFontFallbackProposal({
    required this.token,
    required this.objectId,
    required this.fontName,
    required this.source,
    required this.embeddingAllowed,
    required this.affectedCharacters,
  });

  final String token;
  final String objectId;
  final String fontName;
  final String source;
  final bool embeddingAllowed;
  final String affectedCharacters;
}

class EditorPdfBox {
  const EditorPdfBox({
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  });

  final double left;
  final double bottom;
  final double right;
  final double top;
}

/// A stable route from a semantic editor object to the physical PDFium object
/// that produces its content. The recursive path supports objects nested in
/// Form XObjects without leaking native handles across the bridge.
class EditorPhysicalLocator {
  const EditorPhysicalLocator({
    required this.pageNumber,
    required this.objectPath,
    required this.objectType,
    required this.sourceFingerprint,
    required this.objectRevision,
    this.objectPaths = const <List<int>>[],
  });

  final int pageNumber;

  /// The primary (first) PDFium object path — the stable identity used for
  /// source-key derivation and by consumers that only need one path.
  final List<int> objectPath;
  final String objectType;
  final String sourceFingerprint;
  final int objectRevision;

  /// Every PDFium object path covered by this locator's block. Empty for
  /// single-object locators; [allObjectPaths] falls back to [objectPath].
  final List<List<int>> objectPaths;

  List<List<int>> get allObjectPaths =>
      objectPaths.isEmpty ? <List<int>>[objectPath] : objectPaths;
}

/// A raster tile rendered from the live PDFium document at one revision.
class EditorDirtyTile {
  const EditorDirtyTile({
    required this.pageNumber,
    required this.revision,
    required this.bounds,
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });

  final int pageNumber;
  final int revision;
  final EditorPdfBox bounds;
  final int width;
  final int height;
  final List<int> rgbaBytes;
}

/// Identifies the PDF-space region that must be rerendered after a command.
class EditorTileInvalidation {
  const EditorTileInvalidation({
    required this.pageNumber,
    required this.bounds,
    required this.revision,
  });

  final int pageNumber;
  final EditorPdfBox bounds;
  final int revision;
}

class EditorSearchRequest {
  const EditorSearchRequest({
    required this.expectedRevision,
    required this.query,
    this.mode = EditorSearchMode.exact,
    this.wholeWord = false,
    this.offset = 0,
    this.limit = 100,
  });

  final int expectedRevision;
  final String query;
  final EditorSearchMode mode;
  final bool wholeWord;
  final int offset;
  final int limit;
}

class EditorSearchMatch {
  const EditorSearchMatch({
    required this.objectId,
    required this.pageId,
    required this.pageNumber,
    required this.startUtf16,
    required this.endUtf16,
    required this.quotedText,
  });

  final String objectId;
  final String pageId;
  final int pageNumber;
  final int startUtf16;
  final int endUtf16;
  final String quotedText;
}

class EditorSearchResult {
  const EditorSearchResult({
    required this.schemaVersion,
    required this.revision,
    required this.matches,
    required this.totalMatches,
    required this.indexedPages,
    required this.pageCount,
    required this.isComplete,
  });

  final int schemaVersion;
  final int revision;
  final List<EditorSearchMatch> matches;
  final int totalMatches;
  final int indexedPages;
  final int pageCount;
  final bool isComplete;
}

class EditorSelectionRange {
  const EditorSelectionRange({
    required this.objectId,
    required this.pageId,
    required this.pageNumber,
    required this.startUtf16,
    required this.endUtf16,
    required this.quotedText,
  });

  final String objectId;
  final String pageId;
  final int pageNumber;
  final int startUtf16;
  final int endUtf16;
  final String quotedText;
}

class EditorSelectionSet {
  const EditorSelectionSet({
    required this.revision,
    required this.kind,
    this.ranges = const <EditorSelectionRange>[],
    this.objectIds = const <String>[],
    this.primaryIndex,
  });

  final int revision;
  final EditorSelectionKind kind;
  final List<EditorSelectionRange> ranges;
  final List<String> objectIds;
  final int? primaryIndex;
}

class EditorCompatibilityIssue {
  const EditorCompatibilityIssue({
    required this.objectId,
    required this.pageId,
    required this.kind,
    required this.capability,
    required this.code,
    required this.message,
    required this.supportedOperations,
  });

  final String objectId;
  final String pageId;
  final String kind;
  final String capability;
  final String code;
  final String message;
  final List<String> supportedOperations;
}

class EditorCompatibilityReport {
  const EditorCompatibilityReport({
    required this.schemaVersion,
    required this.revision,
    required this.editableCount,
    required this.overlayOnlyCount,
    required this.readOnlyCount,
    required this.issues,
  });

  final int schemaVersion;
  final int revision;
  final int editableCount;
  final int overlayOnlyCount;
  final int readOnlyCount;
  final List<EditorCompatibilityIssue> issues;
}

class EditorAnnotationRange {
  const EditorAnnotationRange({
    required this.rangeId,
    required this.objectId,
    required this.startUtf16,
    required this.endUtf16,
    required this.quotedText,
  });

  final String rangeId;
  final String objectId;
  final int startUtf16;
  final int endUtf16;
  final String quotedText;
}

class EditorAnnotation {
  const EditorAnnotation({
    required this.objectId,
    required this.pageId,
    required this.bounds,
    required this.kind,
    required this.anchorKind,
    this.anchorX,
    this.anchorY,
    this.ranges = const <EditorAnnotationRange>[],
    this.title = '',
    this.body = '',
    this.colorRgba = const <int>[255, 212, 59, 255],
    this.opacity = 1,
    this.resolved = false,
  });

  final String objectId;
  final String pageId;
  final EditorPdfBox bounds;
  final EditorAnnotationKind kind;
  final EditorAnnotationAnchorKind anchorKind;
  final double? anchorX;
  final double? anchorY;
  final List<EditorAnnotationRange> ranges;
  final String title;
  final String body;
  final List<int> colorRgba;
  final double opacity;
  final bool resolved;
}

class EditorAffineTransform {
  const EditorAffineTransform({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
  });

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;
}

class EditorTextStyle {
  const EditorTextStyle({
    this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.italic,
    required this.colorRgba,
    this.underline = false,
    this.strikethrough = false,
    this.baselineShift = 0.0,
    this.alignment = 'left',
    this.highlightRgba,
  });

  final String? fontFamily;
  final double fontSize;
  final int fontWeight;
  final bool italic;
  final List<int> colorRgba;
  final bool underline;
  final bool strikethrough;
  final double baselineShift;
  final String alignment;
  final List<int>? highlightRgba;
}

class EditorTextRun {
  const EditorTextRun({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final EditorTextStyle style;
}

class EditorTextCharacterBox {
  const EditorTextCharacterBox({
    required this.start,
    required this.end,
    required this.bounds,
  });

  final int start;
  final int end;
  final EditorPdfBox bounds;
}

class EditorSceneObject {
  const EditorSceneObject({
    required this.kind,
    required this.objectId,
    required this.pageId,
    this.text,
    required this.bounds,
    required this.transform,
    required this.capability,
    this.capabilityReason,
    required this.modifiedRevision,
    required this.runs,
    this.characterBoxes = const <EditorTextCharacterBox>[],
    this.layout,
    this.fontFingerprint,
    this.fontAssetHandle,
    this.physicalLocator,
  });

  final EditorSceneObjectKind kind;
  final String objectId;
  final String pageId;
  final String? text;
  final EditorPdfBox bounds;
  final EditorAffineTransform transform;
  final String capability;
  final String? capabilityReason;
  final int modifiedRevision;
  final List<EditorTextRun> runs;
  final List<EditorTextCharacterBox> characterBoxes;
  final EditorTextLayoutRecipe? layout;
  final String? fontFingerprint;
  final String? fontAssetHandle;
  final EditorPhysicalLocator? physicalLocator;
}

class EditorTextLayoutRecipe {
  const EditorTextLayoutRecipe({
    required this.baseline,
    required this.lineHeight,
    required this.characterSpacing,
    required this.horizontalScale,
    required this.direction,
  });

  final double baseline;
  final double lineHeight;
  final double characterSpacing;
  final double horizontalScale;
  final String direction;
}

class EditorSessionMetadata {
  const EditorSessionMetadata({
    required this.schemaVersion,
    required this.sessionId,
    required this.documentId,
    required this.sourceFingerprint,
    required this.revision,
    required this.pageCount,
  });

  final int schemaVersion;
  final String sessionId;
  final String documentId;
  final String sourceFingerprint;
  final int revision;
  final int pageCount;
}

class EditorPageScene {
  const EditorPageScene({
    required this.schemaVersion,
    required this.pageId,
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.revision,
    required this.objects,
  });

  final int schemaVersion;
  final String pageId;
  final int pageNumber;
  final double width;
  final double height;
  final int revision;
  final List<EditorSceneObject> objects;
}

class EditorCommand {
  const EditorCommand({
    required this.kind,
    this.objectId,
    this.start,
    this.end,
    this.replacement,
    this.style,
    this.transform,
    this.bounds,
    this.radians,
    this.centerX,
    this.centerY,
    this.label,
  });

  final EditorCommandKind kind;
  final String? objectId;
  final int? start;
  final int? end;
  final String? replacement;
  final EditorTextStyle? style;
  final EditorAffineTransform? transform;
  final EditorPdfBox? bounds;
  final double? radians;
  final double? centerX;
  final double? centerY;
  final String? label;
}

class EditorCommandRequest {
  const EditorCommandRequest({
    this.schemaVersion = 1,
    required this.commandId,
    required this.baseRevision,
    required this.payload,
  });

  final int schemaVersion;
  final String commandId;
  final int baseRevision;
  final EditorCommand payload;
}

/// A physical mutation that the sole live PDFium document can apply after the
/// Rust editor core has validated a semantic command, but before that command
/// becomes durable in the canonical session.
enum EditorPhysicalEditOperationKind { replaceText, setTextTransform }

class EditorPhysicalEditOperation {
  const EditorPhysicalEditOperation({
    required this.kind,
    required this.objectId,
    required this.sourceKey,
    required this.sourceRevision,
    this.expectedText,
    this.replacement,
    this.expectedTransform,
    this.transform,
    required this.oldBounds,
    required this.newBounds,
  });

  final EditorPhysicalEditOperationKind kind;
  final String objectId;
  final String sourceKey;
  final String sourceRevision;
  final String? expectedText;
  final String? replacement;
  final EditorAffineTransform? expectedTransform;
  final EditorAffineTransform? transform;
  final EditorPdfBox oldBounds;
  final EditorPdfBox newBounds;
}

class EditorPhysicalEditPlan {
  const EditorPhysicalEditPlan({
    required this.previousRevision,
    required this.revision,
    required this.operations,
    required this.inverseOperations,
  });

  final int previousRevision;
  final int revision;
  final List<EditorPhysicalEditOperation> operations;
  final List<EditorPhysicalEditOperation> inverseOperations;
}

class EditorPreparedLiveCommand {
  const EditorPreparedLiveCommand({
    required this.token,
    required this.commandId,
    required this.previousRevision,
    required this.committedRevision,
    required this.plan,
  });

  /// A one-use opaque token. It may only be published after its plan was
  /// successfully applied to the live PDFium session.
  final String token;
  final String commandId;
  final int previousRevision;
  final int committedRevision;
  final EditorPhysicalEditPlan plan;
}

class EditorObjectPatch {
  const EditorObjectPatch({
    required this.objectId,
    required this.pageId,
    required this.modifiedRevision,
    this.text,
    this.textRuns,
    this.characterBoxes,
    this.bounds,
    this.transform,
    this.fontFingerprint,
    this.fontAssetHandle,
  });

  final String objectId;
  final String pageId;
  final int modifiedRevision;
  final String? text;
  final List<EditorTextRun>? textRuns;
  final List<EditorTextCharacterBox>? characterBoxes;
  final EditorPdfBox? bounds;
  final EditorAffineTransform? transform;
  final String? fontFingerprint;
  final String? fontAssetHandle;
}

class EditorCommandResult {
  const EditorCommandResult({
    this.schemaVersion = 1,
    required this.commandId,
    required this.previousRevision,
    required this.committedRevision,
    required this.durable,
    required this.warnings,
    required this.objectPatches,
    this.removedObjectIds = const <String>[],
  });

  final int schemaVersion;
  final String commandId;
  final int previousRevision;
  final int committedRevision;
  final bool durable;
  final List<String> warnings;
  final List<EditorObjectPatch> objectPatches;
  final List<String> removedObjectIds;
}

class EditorEvent {
  const EditorEvent._({
    required this.kind,
    required this.sessionId,
    required this.sequence,
    this.revision,
    this.latestRevision,
    this.commandId,
  });

  const EditorEvent.ready({
    required String sessionId,
    required int sequence,
    required int revision,
  }) : this._(
         kind: EditorEventKind.ready,
         sessionId: sessionId,
         sequence: sequence,
         revision: revision,
       );

  const EditorEvent.commandCommitted({
    required String sessionId,
    required int sequence,
    required int revision,
    required String commandId,
  }) : this._(
         kind: EditorEventKind.commandCommitted,
         sessionId: sessionId,
         sequence: sequence,
         revision: revision,
         commandId: commandId,
       );

  const EditorEvent.lagged({
    required String sessionId,
    required int sequence,
    required int latestRevision,
  }) : this._(
         kind: EditorEventKind.lagged,
         sessionId: sessionId,
         sequence: sequence,
         latestRevision: latestRevision,
       );

  const EditorEvent.closed({
    required String sessionId,
    required int sequence,
    required int revision,
  }) : this._(
         kind: EditorEventKind.closed,
         sessionId: sessionId,
         sequence: sequence,
         revision: revision,
       );

  final EditorEventKind kind;
  final String sessionId;
  final int sequence;
  final int? revision;
  final int? latestRevision;
  final String? commandId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorEvent &&
          kind == other.kind &&
          sequence == other.sequence &&
          revision == other.revision &&
          latestRevision == other.latestRevision &&
          commandId == other.commandId;

  @override
  int get hashCode =>
      Object.hash(kind, sequence, revision, latestRevision, commandId);
}

class EditorSessionClosed implements Exception {
  const EditorSessionClosed();

  @override
  String toString() => 'EditorSessionClosed: the editor session is closed';
}

class EditorProtocolViolation implements Exception {
  const EditorProtocolViolation(this.message);

  final String message;

  @override
  String toString() => 'EditorProtocolViolation: $message';
}

class EditorNativeUnavailable implements Exception {
  const EditorNativeUnavailable(this.cause);

  final Object? cause;

  @override
  String toString() => 'EditorNativeUnavailable: $cause';
}
