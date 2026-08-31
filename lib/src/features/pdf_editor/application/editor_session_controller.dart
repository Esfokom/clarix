import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../domain/editor_document_state.dart';
import '../domain/editor_save_state.dart';
import '../domain/editor_selection.dart';
import '../infrastructure/editor_session_gateway.dart';
import '../infrastructure/live_pdfium_tile_renderer.dart';
import 'editor_viewport_controller.dart';

typedef EditorCommandIdFactory = String Function();
typedef EditorPhaseTwoMutation =
    Future<EditorCommandResult> Function(
      EditorPhaseTwoGateway gateway,
      String commandId,
      int baseRevision,
    );

class EditorSessionController {
  factory EditorSessionController({
    required EditorSessionGateway gateway,
    required EditorCommandIdFactory commandIds,
    int maxResidentScenes = 8,
  }) {
    if (maxResidentScenes < 1) {
      throw ArgumentError.value(
        maxResidentScenes,
        'maxResidentScenes',
        'must be positive',
      );
    }
    return EditorSessionController._(gateway, commandIds, maxResidentScenes);
  }

  EditorSessionController._(
    this._gateway,
    this._commandIds,
    this._maxResidentScenes,
  );

  final EditorSessionGateway _gateway;
  final EditorCommandIdFactory _commandIds;
  final int _maxResidentScenes;
  final StreamController<EditorDocumentState> _changes =
      StreamController<EditorDocumentState>.broadcast(sync: true);
  StreamSubscription<EditorEvent>? _events;
  EditorDocumentState _state = const EditorDocumentState();
  bool _disposed = false;
  Future<void> Function()? _commitComposition;
  bool _saveCancelled = false;
  int _fontFallbackEpoch = 0;
  Completer<void>? _phaseTwoMutationCompletion;
  late final EditorViewportController _viewport = EditorViewportController(
    gateway: _gateway,
    maxResidentScenes: _maxResidentScenes,
    state: () => _state,
    emit: _emit,
    isDisposed: () => _disposed,
  );

  EditorDocumentState get state => _state;
  Stream<EditorDocumentState> get changes => _changes.stream;
  Stream<List<EditorTileInvalidation>> get liveTileInvalidations {
    final gateway = _gateway;
    return gateway is EditorLivePdfiumTileGateway
        ? (gateway as EditorLivePdfiumTileGateway).liveTileInvalidations
        : const Stream<List<EditorTileInvalidation>>.empty();
  }

  bool get canUndo =>
      _state.undoDepth > 0 &&
      _state.pendingCommand == null &&
      !_phaseTwoMutationOutstanding;
  bool get canRedo =>
      _state.redoDepth > 0 &&
      _state.pendingCommand == null &&
      !_phaseTwoMutationOutstanding;
  bool get commandOutstanding =>
      _state.pendingCommand != null || _phaseTwoMutationOutstanding;

  bool get _phaseTwoMutationOutstanding => _phaseTwoMutationCompletion != null;

  EditorPhaseTwoGateway get phaseTwoGatewayForFeature => _phaseTwoGateway;
  int get revisionForFeature => _state.revision;
  void ensureActiveForFeature() => _ensureActive();
  EditorDocumentState get stateForFeature => _state;
  void replaceStateForFeature(EditorDocumentState next) => _emit(next);
  Future<EditorCommandResult> submitPhaseTwoMutationForFeature(
    EditorPhaseTwoMutation mutation,
  ) => _submitPhaseTwoMutation(mutation);

  Future<void> open(String sourcePath) async {
    _ensureActive();
    final metadata = await _gateway.open(sourcePath);
    _events = _gateway.events.listen(_onEvent);
    _emit(
      _state.copyWith(
        sourcePath: sourcePath,
        sessionId: metadata.sessionId,
        revision: metadata.revision,
        recoveredRevision: metadata.revision > 0 ? metadata.revision : null,
        pageCount: metadata.pageCount,
        isOpen: true,
        clearError: true,
      ),
    );
    if (metadata.pageCount > 0) {
      try {
        await refreshPage(1);
      } catch (error) {
        debugPrint('[editor] page 1 scene refresh failed: $error');
        _emit(_state.copyWith(errorCode: 'page_scene_failed'));
      }
    }
  }

  Future<void> refreshPage(
    int pageNumber, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
    bool force = false,
  }) async {
    _ensureActive();
    try {
      await _viewport.refreshPage(pageNumber, priority: priority, force: force);
    } catch (error) {
      if (!_disposed && _errorCode(error) == 'live_hydration_failed') {
        _emit(_state.copyWith(errorCode: 'live_hydration_failed'));
      }
      rethrow;
    }
  }

  void updateViewport(Set<int> visiblePages, {int preloadRadius = 2}) {
    _ensureActive();
    _viewport.updateViewport(visiblePages, preloadRadius: preloadRadius);
  }

  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) {
    _ensureActive();
    return _gateway.cleanPatch(objectId, dpi);
  }

  Future<EditorDirtyTile> renderLiveTile(LivePdfiumTileRequest request) {
    _ensureActive();
    final gateway = _gateway;
    if (gateway is! EditorLivePdfiumTileGateway) {
      return Future<EditorDirtyTile>.error(
        UnsupportedError('live PDFium tile rendering is unavailable'),
      );
    }
    return (gateway as EditorLivePdfiumTileGateway).renderLiveTile(request);
  }

  Future<void> releaseCleanPatchMemory() {
    _ensureActive();
    return _gateway.releaseCleanPatchMemory();
  }

  void setCompositionCommitter(Future<void> Function()? committer) {
    if (_disposed) return;
    _commitComposition = committer;
  }

  Future<void> flushCommands() async {
    _ensureActive();
    while (_state.optimisticEdit != null ||
        _state.queuedEdit != null ||
        _state.pendingCommand != null ||
        _phaseTwoMutationOutstanding) {
      final phaseTwoCompletion = _phaseTwoMutationCompletion;
      if (phaseTwoCompletion != null) {
        await phaseTwoCompletion.future;
        continue;
      }
      await changes.firstWhere(
        (state) =>
            state.optimisticEdit == null &&
            state.queuedEdit == null &&
            state.pendingCommand == null,
      );
    }
  }

  Future<EditorSaveResult> save(EditorSaveRequest request) async {
    _ensureActive();
    _saveCancelled = false;
    _emit(
      _state.copyWith(
        save: _state.save.copyWith(
          phase: EditorSavePhase.saving,
          stage: 'CommitComposition',
          clearError: true,
        ),
      ),
    );
    try {
      await _commitComposition?.call();
      _throwIfSaveCancelled();
      _emit(
        _state.copyWith(save: _state.save.copyWith(stage: 'FlushCommands')),
      );
      await flushCommands();
      _throwIfSaveCancelled();
      _emit(
        _state.copyWith(save: _state.save.copyWith(stage: 'MaterializeTemp')),
      );
      final result = await _gateway.save(request);
      if (_disposed) throw const EditorSessionClosed();
      _emit(
        _state.copyWith(
          save: _state.save.copyWith(
            phase: result.followsNewSource
                ? EditorSavePhase.clean
                : EditorSavePhase.dirty,
            clearStage: true,
            clearError: true,
          ),
          clearError: true,
        ),
      );
      return result;
    } on EditorSaveCancelled {
      if (!_disposed) {
        _emit(
          _state.copyWith(
            save: _state.save.copyWith(
              phase: EditorSavePhase.dirty,
              clearStage: true,
              clearError: true,
            ),
          ),
        );
      }
      rethrow;
    } catch (error) {
      if (!_disposed) {
        final code = _saveErrorCode(error);
        _emit(
          _state.copyWith(
            save: _state.save.copyWith(
              phase: EditorSavePhase.failed,
              errorCode: code,
              clearStage: true,
            ),
            errorCode: code,
          ),
        );
      }
      rethrow;
    }
  }

  void cancelSave() {
    _ensureActive();
    if (_state.save.phase != EditorSavePhase.saving) return;
    if (_state.save.stage == 'CommitComposition' ||
        _state.save.stage == 'FlushCommands') {
      _saveCancelled = true;
    }
  }

  void _throwIfSaveCancelled() {
    if (_saveCancelled) throw const EditorSaveCancelled();
  }

  void applyLocalDelta({
    required String objectId,
    required EditorTextRange range,
    required String replacement,
  }) {
    _ensureActive();
    _fontFallbackEpoch++;
    if (_state.fontFallbackProposal != null) {
      _emit(_state.copyWith(clearFontFallbackProposal: true));
    }
    if (_state.pendingCommand != null || _phaseTwoMutationOutstanding) {
      throw StateError('an editor command is already outstanding');
    }
    if (!_state.objects.containsKey(objectId)) {
      throw ArgumentError.value(objectId, 'objectId', 'object is not loaded');
    }
    final edit = OptimisticTextEdit(
      commandId: _commandIds(),
      objectId: objectId,
      range: range,
      replacement: replacement,
      baseRevision: _state.revision,
    );
    final active = _state.optimisticEdit;
    if (active == null) {
      _emit(
        _state.copyWith(
          optimisticEdit: edit,
          selection: EditorSelection(
            objectId: objectId,
            range: EditorTextRange(
              start: range.start + replacement.codeUnits.length,
              end: range.start + replacement.codeUnits.length,
            ),
          ),
          clearError: true,
        ),
      );
      unawaited(_submit(edit));
      return;
    }
    if (active.objectId != objectId) {
      throw StateError('only one object may have an optimistic edit');
    }
    final object = _state.objects[objectId]!;
    final activeText = _replaceUtf16(
      object.acceptedText,
      active.range,
      active.replacement,
    );
    final desiredText = _replaceUtf16(
      _state.visibleText(objectId)!,
      range,
      replacement,
    );
    final coalesced = OptimisticTextEdit(
      commandId: edit.commandId,
      objectId: objectId,
      range: EditorTextRange(start: 0, end: activeText.codeUnits.length),
      replacement: desiredText,
      baseRevision: _state.revision,
    );
    _emit(
      _state.copyWith(
        queuedEdit: coalesced,
        selection: EditorSelection(
          objectId: objectId,
          range: EditorTextRange(
            start: range.start + replacement.codeUnits.length,
            end: range.start + replacement.codeUnits.length,
          ),
        ),
        clearError: true,
      ),
    );
  }

  Future<EditorCommandResult> submitCommand(EditorCommand command) async {
    _ensureActive();
    if (_state.optimisticEdit != null ||
        _state.pendingCommand != null ||
        _phaseTwoMutationOutstanding) {
      throw StateError('an editor command is already outstanding');
    }
    final commandId = _commandIds();
    final baseRevision = _state.revision;
    _emit(_state.copyWith(pendingCommand: command.kind, clearError: true));
    try {
      final result = await _gateway.submit(
        EditorCommandRequest(
          commandId: commandId,
          baseRevision: baseRevision,
          payload: command,
        ),
      );
      if (_disposed || result.commandId != commandId) {
        throw const EditorProtocolViolation('command acknowledgement mismatch');
      }
      var undoDepth = _state.undoDepth;
      var redoDepth = _state.redoDepth;
      switch (command.kind) {
        case EditorCommandKind.undo:
          if (undoDepth > 0) undoDepth--;
          redoDepth++;
        case EditorCommandKind.redo:
          if (redoDepth > 0) redoDepth--;
          undoDepth++;
        case EditorCommandKind.createCheckpoint:
          break;
        case EditorCommandKind.replaceTextRange:
        case EditorCommandKind.setTextStyle:
        case EditorCommandKind.moveObject:
        case EditorCommandKind.resizeObject:
        case EditorCommandKind.rotateObject:
          undoDepth++;
          redoDepth = 0;
      }
      _emit(
        _state.copyWith(
          revision: result.committedRevision,
          scenes: _patchScenes(_state.scenes, result.objectPatches),
          objects: _patchObjects(_state.objects, result.objectPatches),
          save: _state.save.copyWith(
            phase: EditorSavePhase.dirty,
            clearError: true,
          ),
          undoDepth: undoDepth,
          redoDepth: redoDepth,
          clearPendingCommand: true,
          clearError: true,
        ),
      );
      return result;
    } catch (error) {
      if (!_disposed) {
        _emit(
          _state.copyWith(
            errorCode: _errorCode(error),
            clearPendingCommand: true,
          ),
        );
      }
      rethrow;
    }
  }

  void dispatchCommand(EditorCommand command) {
    unawaited(submitCommand(command).then<void>((_) {}, onError: (_) {}));
  }

  Future<void> undo() async {
    await submitCommand(const EditorCommand(kind: EditorCommandKind.undo));
  }

  Future<void> redo() async {
    await submitCommand(const EditorCommand(kind: EditorCommandKind.redo));
  }

  Future<void> createCheckpoint(String label) async {
    await submitCommand(
      EditorCommand(kind: EditorCommandKind.createCheckpoint, label: label),
    );
  }

  void rejectFontFallback() {
    _ensureActive();
    _fontFallbackEpoch++;
    _emit(_state.copyWith(clearFontFallbackProposal: true, clearError: true));
  }

  Future<void> approveFontFallback(String proposalToken) async {
    _ensureActive();
    if (_state.pendingCommand != null || _phaseTwoMutationOutstanding) {
      throw StateError('an editor command is already outstanding');
    }
    final proposal = _state.fontFallbackProposal;
    if (proposal == null || proposal.token != proposalToken) {
      throw StateError('font fallback proposal is no longer pending');
    }
    final commandId = _commandIds();
    final baseRevision = _state.revision;
    final epoch = ++_fontFallbackEpoch;
    _emit(
      _state.copyWith(
        pendingCommand: EditorCommandKind.replaceTextRange,
        clearError: true,
      ),
    );
    try {
      final result = await _fontFallbackGateway.approveFontFallback(
        commandId: commandId,
        baseRevision: baseRevision,
        proposalToken: proposalToken,
      );
      if (_disposed ||
          epoch != _fontFallbackEpoch ||
          result.commandId != commandId ||
          result.previousRevision != baseRevision ||
          !result.durable) {
        throw const EditorProtocolViolation(
          'font fallback acknowledgement mismatch',
        );
      }
      _emit(
        _state.copyWith(
          revision: result.committedRevision,
          scenes: _patchScenes(_state.scenes, result.objectPatches),
          objects: _patchObjects(_state.objects, result.objectPatches),
          save: _state.save.copyWith(
            phase: EditorSavePhase.dirty,
            clearError: true,
          ),
          undoDepth: _state.undoDepth + 1,
          redoDepth: 0,
          clearPendingCommand: true,
          clearFontFallbackProposal: true,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!_disposed) {
        _emit(
          _state.copyWith(
            errorCode: _errorCode(error),
            clearPendingCommand: true,
            clearFontFallbackProposal: true,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _submit(OptimisticTextEdit edit) async {
    try {
      final result = await _gateway.submit(
        EditorCommandRequest(
          commandId: edit.commandId,
          baseRevision: edit.baseRevision,
          payload: EditorCommand(
            kind: EditorCommandKind.replaceTextRange,
            objectId: edit.objectId,
            start: edit.range.start,
            end: edit.range.end,
            replacement: edit.replacement,
          ),
        ),
      );
      if (_disposed || _state.optimisticEdit?.commandId != result.commandId) {
        return;
      }
      final objects = Map<String, EditorObjectState>.of(_state.objects);
      for (final patch in result.objectPatches) {
        final existing = objects[patch.objectId];
        if (existing == null || patch.text == null) continue;
        objects[patch.objectId] = existing.copyWith(
          acceptedText: patch.text,
          modifiedRevision: patch.modifiedRevision,
        );
      }
      final queued = _state.queuedEdit;
      _emit(
        _state.copyWith(
          revision: result.committedRevision,
          objects: objects,
          save: _state.save.copyWith(
            phase: EditorSavePhase.dirty,
            clearError: true,
          ),
          clearOptimistic: true,
          clearQueued: true,
          clearError: true,
          undoDepth: _state.undoDepth + 1,
          redoDepth: 0,
        ),
      );
      if (queued != null) {
        final next = OptimisticTextEdit(
          commandId: queued.commandId,
          objectId: queued.objectId,
          range: queued.range,
          replacement: queued.replacement,
          baseRevision: result.committedRevision,
        );
        _emit(_state.copyWith(optimisticEdit: next));
        unawaited(_submit(next));
      }
    } catch (error) {
      if (_disposed || _state.optimisticEdit?.commandId != edit.commandId) {
        return;
      }
      final errorCode = _errorCode(error);
      final stalePage = _state.objects[edit.objectId]?.pageId;
      _emit(
        _state.copyWith(
          errorCode: errorCode,
          clearOptimistic: true,
          clearQueued: true,
        ),
      );
      if (errorCode == 'font_fallback_required') {
        final epoch = ++_fontFallbackEpoch;
        try {
          final proposal = await _fontFallbackGateway.proposeFontFallback(
            baseRevision: edit.baseRevision,
            objectId: edit.objectId,
            start: edit.range.start,
            end: edit.range.end,
            replacement: edit.replacement,
          );
          if (!_disposed &&
              epoch == _fontFallbackEpoch &&
              _state.revision == edit.baseRevision) {
            if (proposal.embeddingAllowed) {
              // Silently approve the nearest available font rather than
              // interrupting the user with a dialog. The proposal must be
              // pending in state for approveFontFallback to accept it.
              _emit(
                _state.copyWith(
                  fontFallbackProposal: proposal,
                  clearError: true,
                ),
              );
              unawaited(approveFontFallback(proposal.token));
            } else {
              // Embedding not permitted — surface the proposal so the
              // user can decide.
              _emit(
                _state.copyWith(
                  fontFallbackProposal: proposal,
                  clearError: true,
                ),
              );
            }
          }
        } catch (proposalError) {
          if (!_disposed && epoch == _fontFallbackEpoch) {
            _emit(
              _state.copyWith(
                errorCode: _errorCode(proposalError),
                clearFontFallbackProposal: true,
              ),
            );
          }
        }
      }
      if (errorCode == 'revision_conflict' && stalePage != null) {
        final pageNumber = _state.scenes.entries
            .where((entry) => entry.value.pageId == stalePage)
            .map((entry) => entry.key)
            .firstOrNull;
        if (pageNumber != null) {
          unawaited(refreshPage(pageNumber, force: true));
        }
      }
    }
  }

  Future<EditorCommandResult> _submitPhaseTwoMutation(
    EditorPhaseTwoMutation mutation,
  ) async {
    _ensureActive();
    if (_state.optimisticEdit != null ||
        _state.pendingCommand != null ||
        _phaseTwoMutationOutstanding) {
      throw StateError('an editor command is already outstanding');
    }
    final commandId = _commandIds();
    final baseRevision = _state.revision;
    final completion = Completer<void>();
    _phaseTwoMutationCompletion = completion;
    try {
      final result = await mutation(_phaseTwoGateway, commandId, baseRevision);
      if (_disposed ||
          result.commandId != commandId ||
          result.previousRevision != baseRevision ||
          !result.durable) {
        throw const EditorProtocolViolation(
          'Phase 2 command acknowledgement mismatch',
        );
      }
      final scenes = _removeObjectsFromScenes(
        _patchScenes(_state.scenes, result.objectPatches),
        result.removedObjectIds,
      );
      final objects = _patchObjects(_state.objects, result.objectPatches)
        ..removeWhere(
          (objectId, _) => result.removedObjectIds.contains(objectId),
        );
      _emit(
        _state.copyWith(
          revision: result.committedRevision,
          scenes: scenes,
          objects: objects,
          save: _state.save.copyWith(
            phase: EditorSavePhase.dirty,
            clearError: true,
          ),
          undoDepth: _state.undoDepth + 1,
          redoDepth: 0,
          clearError: true,
        ),
      );
      return result;
    } catch (error) {
      if (!_disposed) {
        _emit(_state.copyWith(errorCode: _errorCode(error)));
      }
      rethrow;
    } finally {
      if (identical(_phaseTwoMutationCompletion, completion)) {
        _phaseTwoMutationCompletion = null;
        completion.complete();
      }
    }
  }

  void _onEvent(EditorEvent event) {
    if (_disposed || event.sessionId != _state.sessionId) return;
    if (event.kind == EditorEventKind.lagged) {
      for (final pageNumber in _state.scenes.keys.toList(growable: false)) {
        unawaited(refreshPage(pageNumber, force: true));
      }
    }
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    await _events?.cancel();
    await _gateway.close();
    _state = _state.copyWith(isOpen: false, isClosed: true);
    await _changes.close();
  }

  void _emit(EditorDocumentState next) {
    if (_disposed) return;
    _state = next;
    _changes.add(next);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('editor session controller is closed');
  }

  EditorFontFallbackGateway get _fontFallbackGateway {
    final gateway = _gateway;
    if (gateway is! EditorFontFallbackGateway) {
      throw UnsupportedError('font fallback is unavailable for this session');
    }
    return gateway as EditorFontFallbackGateway;
  }

  EditorPhaseTwoGateway get _phaseTwoGateway {
    final gateway = _gateway;
    if (gateway is! EditorPhaseTwoGateway) {
      throw UnsupportedError(
        'Phase 2 workflows are unavailable for this session',
      );
    }
    return gateway as EditorPhaseTwoGateway;
  }
}

Map<String, EditorObjectState> _patchObjects(
  Map<String, EditorObjectState> current,
  List<EditorObjectPatch> patches,
) {
  final next = Map<String, EditorObjectState>.of(current);
  for (final patch in patches) {
    final object = next[patch.objectId];
    if (object == null || patch.text == null) continue;
    next[patch.objectId] = object.copyWith(
      acceptedText: patch.text,
      modifiedRevision: patch.modifiedRevision,
    );
  }
  return next;
}

Map<int, EditorPageScene> _patchScenes(
  Map<int, EditorPageScene> current,
  List<EditorObjectPatch> patches,
) {
  final byId = <String, EditorObjectPatch>{
    for (final patch in patches) patch.objectId: patch,
  };
  return <int, EditorPageScene>{
    for (final entry in current.entries)
      entry.key: EditorPageScene(
        schemaVersion: entry.value.schemaVersion,
        pageId: entry.value.pageId,
        pageNumber: entry.value.pageNumber,
        width: entry.value.width,
        height: entry.value.height,
        revision: patches.isEmpty
            ? entry.value.revision
            : patches
                  .map((patch) => patch.modifiedRevision)
                  .fold(entry.value.revision, math.max),
        objects: entry.value.objects
            .map((object) {
              final patch = byId[object.objectId];
              if (patch == null) return object;
              return EditorSceneObject(
                kind: object.kind,
                objectId: object.objectId,
                pageId: object.pageId,
                text: patch.text ?? object.text,
                bounds: patch.bounds ?? object.bounds,
                transform: patch.transform ?? object.transform,
                capability: object.capability,
                capabilityReason: object.capabilityReason,
                modifiedRevision: patch.modifiedRevision,
                runs: patch.textRuns ?? object.runs,
                characterBoxes: patch.characterBoxes ?? object.characterBoxes,
                layout: object.layout,
                fontFingerprint:
                    patch.fontFingerprint ?? object.fontFingerprint,
                fontAssetHandle:
                    patch.fontAssetHandle ?? object.fontAssetHandle,
              );
            })
            .toList(growable: false),
      ),
  };
}

Map<int, EditorPageScene> _removeObjectsFromScenes(
  Map<int, EditorPageScene> current,
  List<String> removedObjectIds,
) {
  if (removedObjectIds.isEmpty) return current;
  final removed = removedObjectIds.toSet();
  return <int, EditorPageScene>{
    for (final entry in current.entries)
      entry.key: EditorPageScene(
        schemaVersion: entry.value.schemaVersion,
        pageId: entry.value.pageId,
        pageNumber: entry.value.pageNumber,
        width: entry.value.width,
        height: entry.value.height,
        revision: entry.value.revision,
        objects: entry.value.objects
            .where((object) => !removed.contains(object.objectId))
            .toList(growable: false),
      ),
  };
}

String _errorCode(Object error) {
  final rawMessage = error is StateError ? error.message : error.toString();
  if (rawMessage.startsWith('live PDFium revision conflict')) {
    return 'live_pdfium_revision_conflict';
  }
  if (rawMessage.contains('glyph') || rawMessage.contains('FPDFText_SetText')) {
    return 'glyph_unsupported';
  }
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError):\s*'),
    '',
  );
  final separator = message.indexOf(':');
  return separator <= 0
      ? 'editor_command_failed'
      : message.substring(0, separator);
}

String _saveErrorCode(Object error) {
  final message = error.toString();
  final marker = message.indexOf('save_failed:');
  if (marker < 0) return _errorCode(error);
  final tail = message.substring(marker + 'save_failed:'.length);
  final separator = tail.indexOf(':');
  return separator < 0 ? tail : tail.substring(0, separator);
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
