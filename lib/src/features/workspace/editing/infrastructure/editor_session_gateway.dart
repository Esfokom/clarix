import '../../../../core/editing/editor_bridge.dart';
import '../../../../core/editing/editor_bridge_types.dart';

abstract class EditorSessionGateway {
  Stream<EditorEvent> get events;

  Future<EditorSessionMetadata> open(String sourcePath);

  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  });

  Future<EditorCommandResult> submit(EditorCommandRequest request);

  Future<EditorSceneObject> objectDetails(String objectId);

  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi);

  Future<void> releaseCleanPatchMemory();

  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      Future<EditorSaveResult>.error(
        UnsupportedError('editor save is unavailable'),
      );

  Future<void> close();
}

abstract interface class EditorFontFallbackGateway {
  Future<EditorFontFallbackProposal> proposeFontFallback({
    required int baseRevision,
    required String objectId,
    required int start,
    required int end,
    required String replacement,
  });

  Future<EditorCommandResult> approveFontFallback({
    required String commandId,
    required int baseRevision,
    required String proposalToken,
  });
}

abstract interface class EditorPhaseTwoGateway {
  Future<EditorSearchResult> search(EditorSearchRequest request);

  Future<EditorSelectionSet> validateSelection(EditorSelectionSet selection);

  Future<EditorCompatibilityReport> compatibilityReport(int expectedRevision);

  Future<void> reportMemoryPressure(EditorMemoryPressureLevel level);

  Future<EditorAnnotation> annotationDetails(String objectId);

  Future<EditorCommandResult> createAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  });

  Future<EditorCommandResult> updateAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  });

  Future<EditorCommandResult> deleteAnnotation({
    required String commandId,
    required int baseRevision,
    required String objectId,
  });
}

class BridgeEditorSessionGateway
    implements
        EditorSessionGateway,
        EditorFontFallbackGateway,
        EditorPhaseTwoGateway {
  factory BridgeEditorSessionGateway({
    EditorBridge bridge = const EditorBridge(),
    String? projectRoot,
  }) => BridgeEditorSessionGateway._(bridge, projectRoot);

  BridgeEditorSessionGateway._(this._bridge, this._projectRoot);

  final EditorBridge _bridge;
  final String? _projectRoot;
  EditorBridgeSession? _session;

  @override
  Stream<EditorEvent> get events =>
      _session?.events ?? const Stream<EditorEvent>.empty();

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async {
    _session = await _bridge.open(sourcePath, projectRoot: _projectRoot);
    return _session!.metadata();
  }

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) => _required().pageScene(
    pageNumber: pageNumber,
    expectedRevision: expectedRevision,
    priority: priority,
  );

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      _required().submit(request);

  @override
  Future<EditorFontFallbackProposal> proposeFontFallback({
    required int baseRevision,
    required String objectId,
    required int start,
    required int end,
    required String replacement,
  }) => _required().proposeFontFallback(
    baseRevision: baseRevision,
    objectId: objectId,
    start: start,
    end: end,
    replacement: replacement,
  );

  @override
  Future<EditorCommandResult> approveFontFallback({
    required String commandId,
    required int baseRevision,
    required String proposalToken,
  }) => _required().approveFontFallback(
    commandId: commandId,
    baseRevision: baseRevision,
    proposalToken: proposalToken,
  );

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      _required().objectDetails(objectId);

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      _required().cleanPatch(objectId: objectId, dpi: dpi);

  @override
  Future<void> releaseCleanPatchMemory() =>
      _required().releaseCleanPatchMemory();

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      _required().save(request);

  @override
  Future<EditorSearchResult> search(EditorSearchRequest request) =>
      _required().search(request);

  @override
  Future<EditorSelectionSet> validateSelection(EditorSelectionSet selection) =>
      _required().validateSelection(selection);

  @override
  Future<EditorCompatibilityReport> compatibilityReport(int expectedRevision) =>
      _required().compatibilityReport(expectedRevision);

  @override
  Future<void> reportMemoryPressure(EditorMemoryPressureLevel level) =>
      _required().reportMemoryPressure(level);

  @override
  Future<EditorAnnotation> annotationDetails(String objectId) =>
      _required().annotationDetails(objectId);

  @override
  Future<EditorCommandResult> createAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  }) => _required().createAnnotation(
    commandId: commandId,
    baseRevision: baseRevision,
    annotation: annotation,
  );

  @override
  Future<EditorCommandResult> updateAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  }) => _required().updateAnnotation(
    commandId: commandId,
    baseRevision: baseRevision,
    annotation: annotation,
  );

  @override
  Future<EditorCommandResult> deleteAnnotation({
    required String commandId,
    required int baseRevision,
    required String objectId,
  }) => _required().deleteAnnotation(
    commandId: commandId,
    baseRevision: baseRevision,
    objectId: objectId,
  );

  @override
  Future<void> close() async {
    final session = _session;
    _session = null;
    await session?.close();
  }

  EditorBridgeSession _required() =>
      _session ?? (throw StateError('editor session is not open'));
}
