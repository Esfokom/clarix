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
  });

  final String? fontFamily;
  final double fontSize;
  final int fontWeight;
  final bool italic;
  final List<int> colorRgba;
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
    this.layout,
    this.fontFingerprint,
    this.fontAssetHandle,
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
  final EditorTextLayoutRecipe? layout;
  final String? fontFingerprint;
  final String? fontAssetHandle;
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

class EditorObjectPatch {
  const EditorObjectPatch({
    required this.objectId,
    required this.pageId,
    required this.modifiedRevision,
    this.text,
    this.textRuns,
    this.bounds,
    this.transform,
  });

  final String objectId;
  final String pageId;
  final int modifiedRevision;
  final String? text;
  final List<EditorTextRun>? textRuns;
  final EditorPdfBox? bounds;
  final EditorAffineTransform? transform;
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
  });

  final int schemaVersion;
  final String commandId;
  final int previousRevision;
  final int committedRevision;
  final bool durable;
  final List<String> warnings;
  final List<EditorObjectPatch> objectPatches;
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
