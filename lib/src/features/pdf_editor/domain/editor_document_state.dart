import '../../../core/editing/editor_bridge_types.dart';
import 'editor_save_state.dart';
import 'editor_selection.dart';

class EditorObjectState {
  const EditorObjectState({
    required this.objectId,
    required this.pageId,
    required this.acceptedText,
    required this.modifiedRevision,
  });

  final String objectId;
  final String pageId;
  final String acceptedText;
  final int modifiedRevision;

  EditorObjectState copyWith({String? acceptedText, int? modifiedRevision}) =>
      EditorObjectState(
        objectId: objectId,
        pageId: pageId,
        acceptedText: acceptedText ?? this.acceptedText,
        modifiedRevision: modifiedRevision ?? this.modifiedRevision,
      );
}

class OptimisticTextEdit {
  const OptimisticTextEdit({
    required this.commandId,
    required this.objectId,
    required this.range,
    required this.replacement,
    required this.baseRevision,
  });

  final String commandId;
  final String objectId;
  final EditorTextRange range;
  final String replacement;
  final int baseRevision;
}

class EditorDocumentState {
  const EditorDocumentState({
    this.sourcePath,
    this.sessionId,
    this.revision = 0,
    this.pageCount = 0,
    this.scenes = const <int, EditorPageScene>{},
    this.objects = const <String, EditorObjectState>{},
    this.optimisticEdit,
    this.queuedEdit,
    this.fontFallbackProposal,
    this.selection,
    this.pendingCommand,
    this.undoDepth = 0,
    this.redoDepth = 0,
    this.recoveredRevision,
    this.save = const EditorSaveState(),
    this.errorCode,
    this.isOpen = false,
    this.isClosed = false,
    this.scanning = false,
  });

  final String? sourcePath;
  final String? sessionId;
  final int revision;
  final int pageCount;
  final Map<int, EditorPageScene> scenes;
  final Map<String, EditorObjectState> objects;
  final OptimisticTextEdit? optimisticEdit;
  final OptimisticTextEdit? queuedEdit;
  final EditorFontFallbackProposal? fontFallbackProposal;
  final EditorSelection? selection;
  final EditorCommandKind? pendingCommand;
  final int undoDepth;
  final int redoDepth;
  final int? recoveredRevision;
  final EditorSaveState save;
  final String? errorCode;
  final bool isOpen;
  final bool isClosed;

  /// True while page scenes are being hydrated from the native side.
  final bool scanning;

  bool get hasEdits =>
      revision > 0 ||
      optimisticEdit != null ||
      queuedEdit != null ||
      objects.values.any((o) => o.modifiedRevision > 0);

  String? visibleText(String objectId) {
    final object = objects[objectId];
    if (object == null) return null;
    final edits = <OptimisticTextEdit>[
      if (optimisticEdit?.objectId == objectId) optimisticEdit!,
      if (queuedEdit?.objectId == objectId) queuedEdit!,
    ];
    var text = object.acceptedText;
    for (final edit in edits) {
      text = _replaceUtf16(text, edit.range, edit.replacement);
    }
    return text;
  }

  EditorDocumentState copyWith({
    String? sourcePath,
    String? sessionId,
    int? revision,
    int? pageCount,
    Map<int, EditorPageScene>? scenes,
    Map<String, EditorObjectState>? objects,
    OptimisticTextEdit? optimisticEdit,
    OptimisticTextEdit? queuedEdit,
    EditorFontFallbackProposal? fontFallbackProposal,
    EditorSelection? selection,
    EditorCommandKind? pendingCommand,
    int? undoDepth,
    int? redoDepth,
    int? recoveredRevision,
    EditorSaveState? save,
    String? errorCode,
    bool? isOpen,
    bool? isClosed,
    bool? scanning,
    bool clearOptimistic = false,
    bool clearQueued = false,
    bool clearFontFallbackProposal = false,
    bool clearSelection = false,
    bool clearPendingCommand = false,
    bool clearRecovery = false,
    bool clearError = false,
  }) => EditorDocumentState(
    sourcePath: sourcePath ?? this.sourcePath,
    sessionId: sessionId ?? this.sessionId,
    revision: revision ?? this.revision,
    pageCount: pageCount ?? this.pageCount,
    scenes: Map.unmodifiable(scenes ?? this.scenes),
    objects: Map.unmodifiable(objects ?? this.objects),
    optimisticEdit: clearOptimistic
        ? null
        : (optimisticEdit ?? this.optimisticEdit),
    queuedEdit: clearQueued ? null : (queuedEdit ?? this.queuedEdit),
    fontFallbackProposal: clearFontFallbackProposal
        ? null
        : (fontFallbackProposal ?? this.fontFallbackProposal),
    selection: clearSelection ? null : (selection ?? this.selection),
    pendingCommand: clearPendingCommand
        ? null
        : (pendingCommand ?? this.pendingCommand),
    undoDepth: undoDepth ?? this.undoDepth,
    redoDepth: redoDepth ?? this.redoDepth,
    recoveredRevision: clearRecovery
        ? null
        : (recoveredRevision ?? this.recoveredRevision),
    save: save ?? this.save,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    isOpen: isOpen ?? this.isOpen,
    isClosed: isClosed ?? this.isClosed,
    scanning: scanning ?? this.scanning,
  );
}

String _replaceUtf16(String source, EditorTextRange range, String replacement) {
  final units = source.codeUnits;
  if (range.end > units.length) return source;
  return String.fromCharCodes(<int>[
    ...units.take(range.start),
    ...replacement.codeUnits,
    ...units.skip(range.end),
  ]);
}
