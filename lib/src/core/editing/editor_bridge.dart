import 'dart:async';
import 'dart:typed_data';

import '../clarix_rust_runtime.dart';
import '../ffi/editing_api.dart' as native;
import 'editor_bridge_types.dart';

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

class EditorBridge {
  const EditorBridge();

  Future<EditorBridgeSession> open(
    String sourcePath, {
    String? projectRoot,
  }) async {
    try {
      await ClarixRustRuntime.requireInitialized();
    } catch (error) {
      throw EditorNativeUnavailable(error);
    }
    final handle = await native.NativeEditorSession.open(
      request: native.NativeOpenEditorRequest(
        sourcePath: sourcePath,
        projectRoot: projectRoot,
      ),
    );
    return EditorBridgeSession._(_FrbNativeEditorPort(handle));
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

class _FrbNativeEditorPort implements NativeEditorPort, NativeFontFallbackPort {
  _FrbNativeEditorPort(this._session);

  final native.NativeEditorSession _session;

  @override
  Stream<EditorEvent> get events => _session.events().map(_eventFromNative);

  @override
  Future<void> close() => _session.close();

  @override
  Future<EditorSessionMetadata> metadata() async {
    final value = await _session.metadata();
    return EditorSessionMetadata(
      schemaVersion: value.schemaVersion,
      sessionId: value.sessionId,
      documentId: value.documentId,
      sourceFingerprint: value.sourceFingerprint,
      revision: _intFromBigInt(value.revision, 'revision'),
      pageCount: value.pageCount,
    );
  }

  @override
  Future<EditorPageScene> pageScene({
    required int pageNumber,
    required int expectedRevision,
    required EditorViewportPriority priority,
  }) async {
    final value = await _session.pageScene(
      request: native.NativePageSceneRequest(
        pageNumber: pageNumber,
        expectedRevision: BigInt.from(expectedRevision),
        priority: switch (priority) {
          EditorViewportPriority.background =>
            native.NativeViewportPriority.background,
          EditorViewportPriority.preload =>
            native.NativeViewportPriority.preload,
          EditorViewportPriority.visible =>
            native.NativeViewportPriority.visible,
          EditorViewportPriority.activeSelection =>
            native.NativeViewportPriority.activeSelection,
        },
      ),
    );
    return EditorPageScene(
      schemaVersion: value.schemaVersion,
      pageId: value.pageId,
      pageNumber: value.pageNumber,
      width: value.width,
      height: value.height,
      revision: _intFromBigInt(value.revision, 'revision'),
      objects: value.objects
          .map(_sceneObjectFromNative)
          .toList(growable: false),
    );
  }

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    final value = await _session.submit(
      request: native.NativeSubmitCommandRequest(
        schemaVersion: request.schemaVersion,
        commandId: request.commandId,
        baseRevision: BigInt.from(request.baseRevision),
        payload: _commandToNative(request.payload),
      ),
    );
    return _commandResultFromNative(value);
  }

  @override
  Future<EditorFontFallbackProposal> proposeFontFallback({
    required int baseRevision,
    required String objectId,
    required int start,
    required int end,
    required String replacement,
  }) async {
    final value = await _session.proposeFontFallback(
      request: native.NativeFontFallbackProposalRequest(
        schemaVersion: _editorSchemaVersion,
        baseRevision: BigInt.from(baseRevision),
        objectId: objectId,
        start: start,
        end: end,
        replacement: replacement,
      ),
    );
    return EditorFontFallbackProposal(
      token: value.token,
      objectId: objectId,
      fontName: value.fontName,
      source: value.source,
      embeddingAllowed: value.embeddingAllowed,
      affectedCharacters: value.affectedCharacters,
    );
  }

  @override
  Future<EditorCommandResult> approveFontFallback({
    required String commandId,
    required int baseRevision,
    required String proposalToken,
  }) async => _commandResultFromNative(
    await _session.approveFontFallback(
      request: native.NativeApproveFontFallbackRequest(
        schemaVersion: _editorSchemaVersion,
        commandId: commandId,
        baseRevision: BigInt.from(baseRevision),
        proposalToken: proposalToken,
      ),
    ),
  );

  @override
  Future<EditorSceneObject> objectDetails(String objectId) async {
    final value = await _session.objectDetails(
      request: native.NativeObjectDetailsRequest(objectId: objectId),
    );
    return _sceneObjectFromNative(value);
  }

  @override
  Future<EditorCleanPatchAsset> cleanPatch({
    required String objectId,
    required int dpi,
  }) async {
    final value = await _session.cleanPatch(
      request: native.NativeCleanPatchRequest(objectId: objectId, dpi: dpi),
    );
    return EditorCleanPatchAsset(
      handle: value.handle,
      objectId: value.objectId,
      bounds: _boxFromNative(value.bounds),
      dpi: value.dpi,
      width: value.width,
      height: value.height,
      rgbaBytes: value.rgbaBytes,
      bleedPoints: value.bleedPoints,
    );
  }

  @override
  Future<void> releaseCleanPatchMemory() => _session.releaseCleanPatchMemory();

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) async {
    final value = await _session.save(
      request: native.NativeEditorSaveRequest(
        targetPath: request.targetPath,
        mode: switch (request.mode) {
          EditorSaveMode.save => native.NativeEditorSaveMode.save,
          EditorSaveMode.saveAs => native.NativeEditorSaveMode.saveAs,
        },
        association: switch (request.association) {
          EditorSaveAssociation.keepOriginalAssociation =>
            native.NativeSaveAssociation.keepOriginalAssociation,
          EditorSaveAssociation.followNewSource =>
            native.NativeSaveAssociation.followNewSource,
        },
        recoveryDirectory: request.recoveryDirectory,
      ),
    );
    return EditorSaveResult(
      schemaVersion: value.schemaVersion,
      targetPath: value.targetPath,
      materializedRevision: _intFromBigInt(
        value.materializedRevision,
        'materializedRevision',
      ),
      completedStages: value.completedStages,
      warnings: value.warnings,
      followsNewSource: value.followsNewSource,
    );
  }

  @override
  Future<EditorCommandResult> checkpoint({
    required int baseRevision,
    required String label,
  }) async => _commandResultFromNative(
    await _session.checkpoint(
      request: native.NativeCheckpointRequest(
        baseRevision: BigInt.from(baseRevision),
        label: label,
      ),
    ),
  );
}

EditorEvent _eventFromNative(native.NativeEditorEvent value) {
  final sequence = _intFromBigInt(value.sequence, 'event.sequence');
  switch (value.kind) {
    case native.NativeEditorEventKind.ready:
      return EditorEvent.ready(
        sessionId: _canonicalUuid(value.sessionId, 'event.sessionId'),
        sequence: sequence,
        revision: _requiredBigInt(value.revision, 'event.revision'),
      );
    case native.NativeEditorEventKind.commandCommitted:
      final result = value.result;
      if (result == null) {
        throw const EditorProtocolViolation('commit event has no result');
      }
      return EditorEvent.commandCommitted(
        sessionId: _canonicalUuid(value.sessionId, 'event.sessionId'),
        sequence: sequence,
        revision: _intFromBigInt(
          result.committedRevision,
          'event.committedRevision',
        ),
        commandId: _canonicalUuid(result.commandId, 'event.commandId'),
      );
    case native.NativeEditorEventKind.lagged:
      return EditorEvent.lagged(
        sessionId: _canonicalUuid(value.sessionId, 'event.sessionId'),
        sequence: sequence,
        latestRevision: _requiredBigInt(
          value.latestRevision,
          'event.latestRevision',
        ),
      );
    case native.NativeEditorEventKind.closed:
      return EditorEvent.closed(
        sessionId: _canonicalUuid(value.sessionId, 'event.sessionId'),
        sequence: sequence,
        revision: _requiredBigInt(value.revision, 'event.revision'),
      );
  }
}

EditorSceneObject _sceneObjectFromNative(native.NativeSceneObject value) =>
    EditorSceneObject(
      kind: switch (value.kind) {
        native.NativeSceneObjectKind.text => EditorSceneObjectKind.text,
        native.NativeSceneObjectKind.unsupported =>
          EditorSceneObjectKind.unsupported,
      },
      objectId: _canonicalUuid(value.objectId, 'object.objectId'),
      pageId: _canonicalUuid(value.pageId, 'object.pageId'),
      text: value.text,
      bounds: _boxFromNative(value.bounds),
      transform: _transformFromNative(value.transform),
      capability: value.capability,
      capabilityReason: value.capabilityReason,
      modifiedRevision: _intFromBigInt(
        value.modifiedRevision,
        'object.modifiedRevision',
      ),
      runs: value.runs.map(_textRunFromNative).toList(growable: false),
      characterBoxes: value.characterBoxes
          .map(
            (character) => EditorTextCharacterBox(
              start: character.start,
              end: character.end,
              bounds: _boxFromNative(character.bounds),
            ),
          )
          .toList(growable: false),
      layout: value.layout == null
          ? null
          : EditorTextLayoutRecipe(
              baseline: value.layout!.baseline,
              lineHeight: value.layout!.lineHeight,
              characterSpacing: value.layout!.characterSpacing,
              horizontalScale: value.layout!.horizontalScale,
              direction: value.layout!.direction,
            ),
      fontFingerprint: value.fontFingerprint,
      fontAssetHandle: value.fontAssetHandle,
    );

EditorTextRun _textRunFromNative(native.NativeTextRun value) => EditorTextRun(
  start: value.start,
  end: value.end,
  style: EditorTextStyle(
    fontFamily: value.style.fontFamily,
    fontSize: value.style.fontSize,
    fontWeight: value.style.fontWeight,
    italic: value.style.italic,
    colorRgba: _colorFromNative(value.style.colorRgba),
  ),
);

EditorCommandResult _commandResultFromNative(
  native.NativeCommandResult value,
) => EditorCommandResult(
  commandId: _canonicalUuid(value.commandId, 'commandId'),
  previousRevision: _intFromBigInt(value.previousRevision, 'previousRevision'),
  committedRevision: _intFromBigInt(
    value.committedRevision,
    'committedRevision',
  ),
  durable: value.durable,
  warnings: List<String>.unmodifiable(value.warnings),
  objectPatches: value.objectPatches
      .map(
        (patch) => EditorObjectPatch(
          objectId: _canonicalUuid(patch.objectId, 'patch.objectId'),
          pageId: _canonicalUuid(patch.pageId, 'patch.pageId'),
          modifiedRevision: _intFromBigInt(
            patch.modifiedRevision,
            'patch.modifiedRevision',
          ),
          text: patch.text,
          textRuns: patch.textRuns
              ?.map(_textRunFromNative)
              .toList(growable: false),
          characterBoxes: patch.characterBoxes
              ?.map(
                (character) => EditorTextCharacterBox(
                  start: character.start,
                  end: character.end,
                  bounds: _boxFromNative(character.bounds),
                ),
              )
              .toList(growable: false),
          bounds: patch.bounds == null ? null : _boxFromNative(patch.bounds!),
          transform: patch.transform == null
              ? null
              : _transformFromNative(patch.transform!),
          fontFingerprint: patch.fontFingerprint,
          fontAssetHandle: patch.fontAssetHandle,
        ),
      )
      .toList(growable: false),
);

native.NativeEditorCommand _commandToNative(EditorCommand value) =>
    native.NativeEditorCommand(
      kind: switch (value.kind) {
        EditorCommandKind.replaceTextRange =>
          native.NativeEditorCommandKind.replaceTextRange,
        EditorCommandKind.setTextStyle =>
          native.NativeEditorCommandKind.setTextStyle,
        EditorCommandKind.moveObject =>
          native.NativeEditorCommandKind.moveObject,
        EditorCommandKind.resizeObject =>
          native.NativeEditorCommandKind.resizeObject,
        EditorCommandKind.rotateObject =>
          native.NativeEditorCommandKind.rotateObject,
        EditorCommandKind.createCheckpoint =>
          native.NativeEditorCommandKind.createCheckpoint,
        EditorCommandKind.undo => native.NativeEditorCommandKind.undo,
        EditorCommandKind.redo => native.NativeEditorCommandKind.redo,
      },
      objectId: value.objectId,
      start: value.start,
      end: value.end,
      replacement: value.replacement,
      style: value.style == null
          ? null
          : native.NativeTextStyle(
              fontFamily: value.style!.fontFamily,
              fontSize: value.style!.fontSize,
              fontWeight: value.style!.fontWeight,
              italic: value.style!.italic,
              colorRgba: Uint8List.fromList(value.style!.colorRgba),
            ),
      transform: value.transform == null
          ? null
          : native.NativeAffineTransform(
              a: value.transform!.a,
              b: value.transform!.b,
              c: value.transform!.c,
              d: value.transform!.d,
              e: value.transform!.e,
              f: value.transform!.f,
            ),
      bounds: value.bounds == null
          ? null
          : native.NativePdfBox(
              left: value.bounds!.left,
              bottom: value.bounds!.bottom,
              right: value.bounds!.right,
              top: value.bounds!.top,
            ),
      radians: value.radians,
      centerX: value.centerX,
      centerY: value.centerY,
      label: value.label,
    );

EditorPdfBox _boxFromNative(native.NativePdfBox value) => EditorPdfBox(
  left: value.left,
  bottom: value.bottom,
  right: value.right,
  top: value.top,
);

EditorAffineTransform _transformFromNative(
  native.NativeAffineTransform value,
) => EditorAffineTransform(
  a: value.a,
  b: value.b,
  c: value.c,
  d: value.d,
  e: value.e,
  f: value.f,
);

int _requiredBigInt(BigInt? value, String field) {
  if (value == null) {
    throw EditorProtocolViolation('$field is missing');
  }
  return _intFromBigInt(value, field);
}

int _intFromBigInt(BigInt value, String field) {
  final max = BigInt.parse('9223372036854775807');
  if (value.isNegative || value > max) {
    throw EditorProtocolViolation('$field is outside the supported range');
  }
  return value.toInt();
}

String _canonicalUuid(String value, String field) {
  if (!_uuidPattern.hasMatch(value)) {
    throw EditorProtocolViolation('$field is not a canonical UUID');
  }
  return value;
}

List<int> _colorFromNative(Uint8List value) {
  if (value.length != 4) {
    throw const EditorProtocolViolation('text color must have four channels');
  }
  return List<int>.unmodifiable(value);
}
