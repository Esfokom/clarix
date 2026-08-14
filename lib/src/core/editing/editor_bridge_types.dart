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
    required this.modifiedRevision,
    required this.runs,
  });

  final EditorSceneObjectKind kind;
  final String objectId;
  final String pageId;
  final String? text;
  final EditorPdfBox bounds;
  final EditorAffineTransform transform;
  final String capability;
  final int modifiedRevision;
  final List<EditorTextRun> runs;
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
    required this.committedRevision,
    required this.objectPatches,
  });

  final int schemaVersion;
  final String commandId;
  final int committedRevision;
  final List<EditorObjectPatch> objectPatches;
}

class EditorEvent {
  const EditorEvent._({
    required this.kind,
    required this.sequence,
    this.revision,
    this.latestRevision,
    this.commandId,
  });

  const EditorEvent.ready({required int sequence, required int revision})
    : this._(
        kind: EditorEventKind.ready,
        sequence: sequence,
        revision: revision,
      );

  const EditorEvent.commandCommitted({
    required int sequence,
    required int revision,
    required String commandId,
  }) : this._(
         kind: EditorEventKind.commandCommitted,
         sequence: sequence,
         revision: revision,
         commandId: commandId,
       );

  const EditorEvent.lagged({required int sequence, required int latestRevision})
    : this._(
        kind: EditorEventKind.lagged,
        sequence: sequence,
        latestRevision: latestRevision,
      );

  const EditorEvent.closed({required int sequence, required int revision})
    : this._(
        kind: EditorEventKind.closed,
        sequence: sequence,
        revision: revision,
      );

  final EditorEventKind kind;
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
