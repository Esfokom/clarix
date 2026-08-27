import 'dart:async';

import '../../../core/editing/editor_bridge.dart';
import '../../../core/editing/editor_bridge_types.dart';
import '../../../core/editing/live_pdfium_editor_port.dart';
import '../../../core/agent/agent_bridge.dart';
import 'live_pdfium_import_manifest_builder.dart';
import 'live_pdfium_session.dart';
import 'live_pdfium_tile_renderer.dart';

abstract interface class EditorLivePdfiumTileGateway {
  Stream<List<EditorTileInvalidation>> get liveTileInvalidations;

  Future<EditorDirtyTile> renderLiveTile(LivePdfiumTileRequest request);
}

typedef OpenBridgeEditorSession =
    Future<EditorBridgeSession> Function(
      String sourcePath, {
      String? projectRoot,
    });

typedef OpenLivePdfiumSession =
    Future<LivePdfiumSessionOwner> Function(String sourcePath);

typedef LoadLivePdfiumImportManifest =
    Future<LivePdfiumImportManifest> Function(String sourcePath);

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
        EditorAgentGateway,
        EditorLivePdfiumTileGateway {
  factory BridgeEditorSessionGateway({
    EditorBridge bridge = const EditorBridge(),
    String? projectRoot,
    LoadLivePdfiumImportManifest? loadLivePdfiumImportManifest,
  }) => BridgeEditorSessionGateway._(
    (sourcePath, {projectRoot}) => bridge.open(
      sourcePath,
      projectRoot: projectRoot,
      livePdfiumImport: true,
    ),
    LivePdfiumSession.open,
    loadLivePdfiumImportManifest ?? _emptyLivePdfiumImportManifest,
    projectRoot,
  );

  factory BridgeEditorSessionGateway.forTest({
    required OpenBridgeEditorSession openBridgeSession,
    required OpenLivePdfiumSession openLivePdfiumSession,
    LoadLivePdfiumImportManifest? loadLivePdfiumImportManifest,
    String? projectRoot,
  }) => BridgeEditorSessionGateway._(
    openBridgeSession,
    openLivePdfiumSession,
    loadLivePdfiumImportManifest ?? _emptyLivePdfiumImportManifest,
    projectRoot,
  );

  BridgeEditorSessionGateway._(
    this._openBridgeSession,
    this._openLivePdfiumSession,
    this._loadLivePdfiumImportManifest,
    this._projectRoot,
  );

  final OpenBridgeEditorSession _openBridgeSession;
  final OpenLivePdfiumSession _openLivePdfiumSession;
  final LoadLivePdfiumImportManifest _loadLivePdfiumImportManifest;
  final String? _projectRoot;
  EditorBridgeSession? _session;
  String? _sessionId;
  LivePdfiumSessionOwner? _livePdfiumSession;
  LivePdfiumLocatorRegistry? _livePdfiumLocatorRegistry;
  LivePdfiumEditorPort? _livePdfiumEditorPort;
  final Set<int> _liveImportedPages = <int>{};
  final Map<int, Future<void>> _livePageImports = <int, Future<void>>{};
  final StreamController<List<EditorTileInvalidation>> _liveTileInvalidations =
      StreamController<List<EditorTileInvalidation>>.broadcast(sync: true);

  bool get hasLivePdfiumSession => _livePdfiumSession != null;
  bool get hasLivePdfiumLocatorRegistry => _livePdfiumLocatorRegistry != null;

  /// Registers a binding supplied by the canonical live import manifest.
  /// Callers must never derive this association from text, geometry, or order.
  void registerLivePdfiumBinding({
    required String objectId,
    required String sourceKey,
    required String sourceRevision,
    required EditorPhysicalLocator locator,
  }) {
    final registry = _livePdfiumLocatorRegistry;
    if (registry == null) throw StateError('editor session is not open');
    registry.register(
      objectId: objectId,
      sourceKey: sourceKey,
      sourceRevision: sourceRevision,
      locator: locator,
    );
  }

  @override
  Stream<EditorEvent> get events =>
      _session?.events ?? const Stream<EditorEvent>.empty();

  @override
  Stream<List<EditorTileInvalidation>> get liveTileInvalidations =>
      _liveTileInvalidations.stream;

  @override
  Future<EditorDirtyTile> renderLiveTile(LivePdfiumTileRequest request) {
    final liveSession = _livePdfiumSession;
    if (liveSession is! LivePdfiumSession) {
      return Future<EditorDirtyTile>.error(
        UnsupportedError('live PDFium tile rendering is unavailable'),
      );
    }
    return liveSession.renderTile(request);
  }

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async {
    if (_session != null || _livePdfiumSession != null) {
      throw StateError('editor session is already open');
    }
    final liveSession = await _openLivePdfiumSession(sourcePath);
    EditorBridgeSession? semanticSession;
    try {
      semanticSession = await _openBridgeSession(
        sourcePath,
        projectRoot: _projectRoot,
      );
      final metadata = await semanticSession.metadata();
      final manifest = await _loadLivePdfiumImportManifest(sourcePath);
      _session = semanticSession;
      _sessionId = metadata.sessionId;
      _livePdfiumSession = liveSession;
      final locatorRegistry = LivePdfiumLocatorRegistry();
      locatorRegistry.registerManifest(
        manifest,
        sourceFingerprint: metadata.sourceFingerprint,
      );
      _livePdfiumLocatorRegistry = locatorRegistry;
      _livePdfiumEditorPort = LivePdfiumEditorPort(
        semantic: _BridgeLivePdfiumPort(semanticSession),
        session: liveSession,
        locatorRegistry: locatorRegistry,
        onApplied: (result) {
          if (result.invalidations.isNotEmpty) {
            _liveTileInvalidations.add(result.invalidations);
          }
        },
      );
      return metadata;
    } catch (_) {
      try {
        await semanticSession?.close();
      } finally {
        await liveSession.close();
      }
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
  }) async {
    await _hydrateLivePageIfAvailable(pageNumber, expectedRevision);
    return _required().pageScene(
      pageNumber: pageNumber,
      expectedRevision: expectedRevision,
      priority: priority,
    );
  }

  Future<void> _hydrateLivePageIfAvailable(
    int pageNumber,
    int expectedRevision,
  ) {
    if (_liveImportedPages.contains(pageNumber)) return Future<void>.value();
    final pending = _livePageImports[pageNumber];
    if (pending != null) return pending;
    final hydration = _hydrateLivePage(pageNumber, expectedRevision);
    _livePageImports[pageNumber] = hydration;
    return hydration.whenComplete(() {
      if (identical(_livePageImports[pageNumber], hydration)) {
        _livePageImports.remove(pageNumber);
      }
    });
  }

  Future<void> _hydrateLivePage(int pageNumber, int expectedRevision) async {
    final liveSession = _livePdfiumSession;
    if (liveSession is! LivePdfiumPageImportSource) return;
    final semanticSession = _required();
    final metadata = await semanticSession.metadata();
    if (metadata.revision != expectedRevision) return;
    final inspection = await (liveSession as LivePdfiumPageImportSource)
        .inspectPageForImport(
          sourceRevision: metadata.sourceFingerprint,
          pageNumber: pageNumber,
        );
    final builder = const LivePdfiumImportManifestBuilder();
    final manifest = builder.build(
      sourceFingerprint: metadata.sourceFingerprint,
      blocks: inspection.blocks,
    );
    await semanticSession.importLivePage(
      builder.buildPageImport(
        expectedRevision: expectedRevision,
        sourceFingerprint: metadata.sourceFingerprint,
        pageNumber: inspection.pageNumber,
        width: inspection.width,
        height: inspection.height,
        blocks: inspection.blocks,
      ),
    );
    _livePdfiumLocatorRegistry?.registerManifest(
      manifest,
      sourceFingerprint: metadata.sourceFingerprint,
    );
    _liveImportedPages.add(pageNumber);
  }

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      _submitRouted(request);

  Future<EditorCommandResult> _submitRouted(EditorCommandRequest request) {
    final objectId = request.payload.objectId;
    final registry = _livePdfiumLocatorRegistry;
    final livePort = _livePdfiumEditorPort;
    if (request.payload.kind == EditorCommandKind.replaceTextRange &&
        objectId != null &&
        registry != null &&
        registry.hasObject(objectId) &&
        livePort != null) {
      return livePort.submit(request);
    }
    return _required().submit(request);
  }

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
  Future<EditorSaveResult> save(EditorSaveRequest request) async {
    final liveSession = _livePdfiumSession;
    if (liveSession is LivePdfiumSaveSource) {
      return _required().saveLivePdfium(
        request,
        await (liveSession as LivePdfiumSaveSource).saveBytes(),
      );
    }
    return _required().save(request);
  }

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
    _livePdfiumEditorPort = null;
    _liveImportedPages.clear();
    _livePageImports.clear();
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

final class _BridgeLivePdfiumPort implements NativeLivePdfiumPort {
  const _BridgeLivePdfiumPort(this._session);

  final EditorBridgeSession _session;

  @override
  Future<EditorPreparedLiveCommand> prepareLiveCommand(
    EditorCommandRequest request,
  ) => _session.prepareLiveCommand(request);

  @override
  Future<EditorCommandResult> publishPreparedLiveCommand(String token) =>
      _session.publishPreparedLiveCommand(token);
}

Future<LivePdfiumImportManifest> _emptyLivePdfiumImportManifest(
  String _,
) async => const LivePdfiumImportManifest.empty();
