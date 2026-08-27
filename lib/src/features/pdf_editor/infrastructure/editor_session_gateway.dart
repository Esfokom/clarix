import '../../../core/editing/editor_bridge.dart';
import '../../../core/editing/editor_bridge_types.dart';
import '../../../core/editing/live_pdfium_editor_port.dart';
import '../../../core/agent/agent_bridge.dart';
import 'live_pdfium_session.dart';

typedef OpenBridgeEditorSession =
    Future<EditorBridgeSession> Function(
      String sourcePath, {
      String? projectRoot,
    });

typedef OpenLivePdfiumSession =
    Future<LivePdfiumSessionOwner> Function(String sourcePath);

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

abstract interface class EditorAgentGateway {
  AgentBridgeSession agentBridgeSession();
}

class BridgeEditorSessionGateway
    implements
        EditorSessionGateway,
        EditorFontFallbackGateway,
        EditorPhaseTwoGateway,
        EditorAgentGateway {
  factory BridgeEditorSessionGateway({
    EditorBridge bridge = const EditorBridge(),
    String? projectRoot,
  }) => BridgeEditorSessionGateway._(
    (sourcePath, {projectRoot}) =>
        bridge.open(sourcePath, projectRoot: projectRoot),
    LivePdfiumSession.open,
    projectRoot,
  );

  factory BridgeEditorSessionGateway.forTest({
    required OpenBridgeEditorSession openBridgeSession,
    required OpenLivePdfiumSession openLivePdfiumSession,
    String? projectRoot,
  }) => BridgeEditorSessionGateway._(
    openBridgeSession,
    openLivePdfiumSession,
    projectRoot,
  );

  BridgeEditorSessionGateway._(
    this._openBridgeSession,
    this._openLivePdfiumSession,
    this._projectRoot,
  );

  final OpenBridgeEditorSession _openBridgeSession;
  final OpenLivePdfiumSession _openLivePdfiumSession;
  final String? _projectRoot;
  EditorBridgeSession? _session;
  String? _sessionId;
  LivePdfiumSessionOwner? _livePdfiumSession;
  LivePdfiumLocatorRegistry? _livePdfiumLocatorRegistry;

  bool get hasLivePdfiumSession => _livePdfiumSession != null;
  bool get hasLivePdfiumLocatorRegistry => _livePdfiumLocatorRegistry != null;

  @override
  Stream<EditorEvent> get events =>
      _session?.events ?? const Stream<EditorEvent>.empty();

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async {
    if (_session != null || _livePdfiumSession != null) {
      throw StateError('editor session is already open');
    }
    final liveSession = await _openLivePdfiumSession(sourcePath);
    try {
      final session = await _openBridgeSession(
        sourcePath,
        projectRoot: _projectRoot,
      );
      final metadata = await session.metadata();
      _session = session;
      _sessionId = metadata.sessionId;
      _livePdfiumSession = liveSession;
      _livePdfiumLocatorRegistry = LivePdfiumLocatorRegistry();
      return metadata;
    } catch (_) {
      await liveSession.close();
      rethrow;
    }
  }

  @override
  AgentBridgeSession agentBridgeSession() => AgentBridgeSession.forTest(
    _required().agentPort,
    sessionId:
        _sessionId ?? (throw StateError('editor metadata is unavailable')),
  );

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
    final liveSession = _livePdfiumSession;
    final locatorRegistry = _livePdfiumLocatorRegistry;
    _session = null;
    _sessionId = null;
    _livePdfiumSession = null;
    _livePdfiumLocatorRegistry = null;
    try {
      await session?.close();
    } finally {
      locatorRegistry?.clear();
      await liveSession?.close();
    }
  }

  EditorBridgeSession _required() =>
      _session ?? (throw StateError('editor session is not open'));
}
