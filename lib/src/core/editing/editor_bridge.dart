import 'dart:async';

import '../clarix_rust_runtime.dart';
import '../agent/agent_bridge.dart';
import '../ffi/editing_api.dart' as native;
import 'editor_bridge_types.dart';
import 'frb_native_editor_port.dart';

const int _editorSchemaVersion = 1;
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

abstract class NativeEditorPort {
  Stream<EditorEvent> get events;

  Future<EditorSessionMetadata> metadata();

  Future<EditorPageScene> pageScene({
    required int pageNumber,
    required int expectedRevision,
    required EditorViewportPriority priority,
  });

  Future<EditorCommandResult> submit(EditorCommandRequest request);

  Future<EditorSceneObject> objectDetails(String objectId);

  Future<EditorCleanPatchAsset> cleanPatch({
    required String objectId,
    required int dpi,
  });

  Future<void> releaseCleanPatchMemory();

  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      Future<EditorSaveResult>.error(
        UnsupportedError('native editor save is unavailable'),
      );

  Future<EditorCommandResult> checkpoint({
    required int baseRevision,
    required String label,
  });

  Future<void> close();
}

/// Optional two-phase command boundary for the Dart-owned live PDFium
/// document. A command is durable only after Dart applies its physical plan
/// and calls `publishPreparedLiveCommand` with the returned one-use token.
abstract interface class NativeLivePdfiumPort {
  Future<EditorPreparedLiveCommand> prepareLiveCommand(
    EditorCommandRequest request,
  );

  Future<EditorCommandResult> publishPreparedLiveCommand(String token);
}

abstract interface class NativeLivePageImportPort {
  Future<void> importLivePage(native.NativeLivePageImport request);
}

abstract interface class NativeLivePdfiumSavePort {
  Future<EditorSaveResult> saveLivePdfium(
    EditorSaveRequest request,
    List<int> pdfBytes,
  );
}

abstract interface class NativeFontFallbackPort {
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

abstract interface class NativePhaseTwoPort {
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

class EditorBridge {
  const EditorBridge();

  Future<EditorBridgeSession> open(
    String sourcePath, {
    String? projectRoot,
    bool livePdfiumImport = false,
  }) async {
    try {
      await ClarixRustRuntime.requireInitialized();
    } catch (error) {
      throw EditorNativeUnavailable(error);
    }
    final request = native.NativeOpenEditorRequest(
      sourcePath: sourcePath,
      projectRoot: projectRoot,
    );
    final handle = await (livePdfiumImport
        ? native.NativeEditorSession.openLivePdfium(request: request)
        : native.NativeEditorSession.open(request: request));
    return EditorBridgeSession._(FrbNativeEditorPort(handle));
  }
}

class EditorBridgeSession {
  EditorBridgeSession._(this._native) {
    _nativeSubscription = _native.events.listen(
      _acceptEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (!_closed) {
          _eventsController.addError(error, stackTrace);
        }
      },
    );
  }

  factory EditorBridgeSession.forTest(NativeEditorPort native) =>
      EditorBridgeSession._(native);

  final NativeEditorPort _native;
  final StreamController<EditorEvent> _eventsController =
      StreamController<EditorEvent>.broadcast(sync: true);
  late final StreamSubscription<EditorEvent> _nativeSubscription;
  int _lastEventSequence = 0;
  bool _closed = false;
  Future<void>? _closing;

  Stream<EditorEvent> get events => _eventsController.stream;

  NativeAgentPort get agentPort {
    final native = _native;
    if (native is NativeAgentPortProvider) {
      return (native as NativeAgentPortProvider).agentPort;
    }
    throw UnsupportedError('native agent session is unavailable');
  }

  Future<EditorSessionMetadata> metadata() async {
    _ensureOpen();
    final value = await _native.metadata();
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    _canonicalUuid(value.sessionId, 'sessionId');
    _canonicalUuid(value.documentId, 'documentId');
    return value;
  }

  Future<EditorPageScene> pageScene({
    required int pageNumber,
    required int expectedRevision,
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async {
    _ensureOpen();
    final value = await _native.pageScene(
      pageNumber: pageNumber,
      expectedRevision: expectedRevision,
      priority: priority,
    );
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    _canonicalUuid(value.pageId, 'pageId');
    return value;
  }

  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    _ensureOpen();
    _validateSchema(request.schemaVersion);
    _canonicalUuid(request.commandId, 'commandId');
    final value = await _native.submit(request);
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    _canonicalUuid(value.commandId, 'commandId');
    if (value.previousRevision != request.baseRevision || !value.durable) {
      throw const EditorProtocolViolation(
        'native command acknowledgement is not durably based on the requested revision',
      );
    }
    return value;
  }

  Future<EditorPreparedLiveCommand> prepareLiveCommand(
    EditorCommandRequest request,
  ) async {
    _ensureOpen();
    _validateSchema(request.schemaVersion);
    _canonicalUuid(request.commandId, 'commandId');
    final native = _native;
    if (native is! NativeLivePdfiumPort) {
      throw UnsupportedError('live PDFium command preparation is unavailable');
    }
    final value = await (native as NativeLivePdfiumPort).prepareLiveCommand(
      request,
    );
    _ensureOpen();
    _canonicalUuid(value.token, 'preparedCommandToken');
    _canonicalUuid(value.commandId, 'commandId');
    if (value.commandId != request.commandId ||
        value.previousRevision != request.baseRevision ||
        value.committedRevision <= value.previousRevision ||
        value.plan.previousRevision != value.previousRevision ||
        value.plan.revision != value.committedRevision ||
        value.plan.operations.isEmpty) {
      throw const EditorProtocolViolation(
        'prepared live command does not describe a valid uncommitted revision',
      );
    }
    return value;
  }

  Future<void> importLivePage(native.NativeLivePageImport request) async {
    _ensureOpen();
    final port = _native;
    if (port is! NativeLivePageImportPort) {
      throw UnsupportedError('live PDFium page import is unavailable');
    }
    await (port as NativeLivePageImportPort).importLivePage(request);
    _ensureOpen();
  }

  Future<EditorCommandResult> publishPreparedLiveCommand(String token) async {
    _ensureOpen();
    final native = _native;
    if (native is! NativeLivePdfiumPort) {
      throw UnsupportedError('live PDFium command publication is unavailable');
    }
    final value = await (native as NativeLivePdfiumPort)
        .publishPreparedLiveCommand(
          _canonicalUuid(token, 'preparedCommandToken'),
        );
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    _canonicalUuid(value.commandId, 'commandId');
    if (!value.durable) {
      throw const EditorProtocolViolation(
        'published live command is not durable',
      );
    }
    return value;
  }

  Future<EditorFontFallbackProposal> proposeFontFallback({
    required int baseRevision,
    required String objectId,
    required int start,
    required int end,
    required String replacement,
  }) async {
    _ensureOpen();
    final fallback = _native;
    if (fallback is! NativeFontFallbackPort) {
      throw UnsupportedError('native font fallback proposals are unavailable');
    }
    final fontFallback = fallback as NativeFontFallbackPort;
    final value = await fontFallback.proposeFontFallback(
      baseRevision: baseRevision,
      objectId: _canonicalUuid(objectId, 'objectId'),
      start: start,
      end: end,
      replacement: replacement,
    );
    _ensureOpen();
    _canonicalUuid(value.token, 'proposalToken');
    return value;
  }

  Future<EditorCommandResult> approveFontFallback({
    required String commandId,
    required int baseRevision,
    required String proposalToken,
  }) async {
    _ensureOpen();
    final fallback = _native;
    if (fallback is! NativeFontFallbackPort) {
      throw UnsupportedError('native font fallback approval is unavailable');
    }
    final fontFallback = fallback as NativeFontFallbackPort;
    final value = await fontFallback.approveFontFallback(
      commandId: _canonicalUuid(commandId, 'commandId'),
      baseRevision: baseRevision,
      proposalToken: _canonicalUuid(proposalToken, 'proposalToken'),
    );
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    if (value.commandId != commandId ||
        value.previousRevision != baseRevision ||
        !value.durable) {
      throw const EditorProtocolViolation(
        'font fallback acknowledgement is not durably based on the requested revision',
      );
    }
    return value;
  }

  Future<EditorSceneObject> objectDetails(String objectId) async {
    _ensureOpen();
    final value = await _native.objectDetails(
      _canonicalUuid(objectId, 'objectId'),
    );
    _ensureOpen();
    return value;
  }

  Future<EditorCleanPatchAsset> cleanPatch({
    required String objectId,
    required int dpi,
  }) async {
    _ensureOpen();
    final value = await _native.cleanPatch(objectId: objectId, dpi: dpi);
    _ensureOpen();
    if (value.objectId != objectId || value.dpi <= 0) {
      throw const EditorProtocolViolation(
        'native clean patch identity is invalid',
      );
    }
    return value;
  }

  Future<void> releaseCleanPatchMemory() async {
    _ensureOpen();
    await _native.releaseCleanPatchMemory();
    _ensureOpen();
  }

  Future<EditorSaveResult> save(EditorSaveRequest request) async {
    _ensureOpen();
    final value = await _native.save(request);
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    return value;
  }

  Future<EditorSaveResult> saveLivePdfium(
    EditorSaveRequest request,
    List<int> pdfBytes,
  ) async {
    _ensureOpen();
    final port = _native;
    if (port is! NativeLivePdfiumSavePort) {
      throw UnsupportedError('live PDFium save is unavailable');
    }
    final value = await (port as NativeLivePdfiumSavePort).saveLivePdfium(
      request,
      pdfBytes,
    );
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    return value;
  }

  Future<EditorCommandResult> checkpoint({
    required int baseRevision,
    required String label,
  }) async {
    _ensureOpen();
    final value = await _native.checkpoint(
      baseRevision: baseRevision,
      label: label,
    );
    _ensureOpen();
    if (!value.durable) {
      throw const EditorProtocolViolation(
        'checkpoint acknowledgement is not durable',
      );
    }
    return value;
  }

  Future<EditorSearchResult> search(EditorSearchRequest request) async {
    _ensureOpen();
    final phaseTwo = _phaseTwoPort();
    final value = await phaseTwo.search(request);
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    return value;
  }

  Future<EditorSelectionSet> validateSelection(
    EditorSelectionSet selection,
  ) async {
    _ensureOpen();
    final phaseTwo = _phaseTwoPort();
    final value = await phaseTwo.validateSelection(selection);
    _ensureOpen();
    return value;
  }

  Future<EditorCompatibilityReport> compatibilityReport(
    int expectedRevision,
  ) async {
    _ensureOpen();
    final value = await _phaseTwoPort().compatibilityReport(expectedRevision);
    _ensureOpen();
    _validateSchema(value.schemaVersion);
    return value;
  }

  Future<void> reportMemoryPressure(EditorMemoryPressureLevel level) async {
    _ensureOpen();
    await _phaseTwoPort().reportMemoryPressure(level);
    _ensureOpen();
  }

  Future<EditorAnnotation> annotationDetails(String objectId) async {
    _ensureOpen();
    final value = await _phaseTwoPort().annotationDetails(
      _canonicalUuid(objectId, 'objectId'),
    );
    _ensureOpen();
    return value;
  }

  Future<EditorCommandResult> createAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  }) => _submitAnnotation(
    commandId: commandId,
    baseRevision: baseRevision,
    annotation: annotation,
    submit: _phaseTwoPort().createAnnotation,
  );

  Future<EditorCommandResult> updateAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  }) => _submitAnnotation(
    commandId: commandId,
    baseRevision: baseRevision,
    annotation: annotation,
    submit: _phaseTwoPort().updateAnnotation,
  );

  Future<EditorCommandResult> deleteAnnotation({
    required String commandId,
    required int baseRevision,
    required String objectId,
  }) async {
    _ensureOpen();
    final canonicalCommandId = _canonicalUuid(commandId, 'commandId');
    final value = await _phaseTwoPort().deleteAnnotation(
      commandId: canonicalCommandId,
      baseRevision: baseRevision,
      objectId: _canonicalUuid(objectId, 'objectId'),
    );
    _ensureOpen();
    _validateAnnotationAck(value, canonicalCommandId, baseRevision);
    return value;
  }

  NativePhaseTwoPort _phaseTwoPort() {
    final native = _native;
    if (native is NativePhaseTwoPort) {
      return native as NativePhaseTwoPort;
    }
    throw UnsupportedError('native Phase 2 editing workflows are unavailable');
  }

  Future<EditorCommandResult> _submitAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
    required Future<EditorCommandResult> Function({
      required String commandId,
      required int baseRevision,
      required EditorAnnotation annotation,
    })
    submit,
  }) async {
    _ensureOpen();
    final canonicalCommandId = _canonicalUuid(commandId, 'commandId');
    final value = await submit(
      commandId: canonicalCommandId,
      baseRevision: baseRevision,
      annotation: annotation,
    );
    _ensureOpen();
    _validateAnnotationAck(value, canonicalCommandId, baseRevision);
    return value;
  }

  void _validateAnnotationAck(
    EditorCommandResult value,
    String commandId,
    int baseRevision,
  ) {
    _validateSchema(value.schemaVersion);
    if (value.commandId != commandId ||
        value.previousRevision != baseRevision ||
        !value.durable) {
      throw const EditorProtocolViolation(
        'annotation acknowledgement is not durably based on the requested revision',
      );
    }
  }

  Future<void> close() => _closing ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _nativeSubscription.cancel();
    try {
      await _native.close();
    } finally {
      await _eventsController.close();
    }
  }

  void _acceptEvent(EditorEvent event) {
    if (_closed) {
      return;
    }
    if (event.sequence <= _lastEventSequence) {
      _eventsController.addError(
        EditorProtocolViolation(
          'event sequence ${event.sequence} is not greater than '
          '$_lastEventSequence',
        ),
      );
      return;
    }
    _lastEventSequence = event.sequence;
    _eventsController.add(event);
  }

  void _ensureOpen() {
    if (_closed) {
      throw const EditorSessionClosed();
    }
  }

  static void _validateSchema(int schemaVersion) {
    if (schemaVersion != _editorSchemaVersion) {
      throw EditorProtocolViolation(
        'expected schema $_editorSchemaVersion, received $schemaVersion',
      );
    }
  }
}

String _canonicalUuid(String value, String field) {
  if (!_uuidPattern.hasMatch(value)) {
    throw EditorProtocolViolation('$field is not a canonical UUID');
  }
  return value;
}
