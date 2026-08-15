import 'dart:async';

import '../../../../core/editing/editor_bridge_types.dart';
import '../domain/editor_document_state.dart';
import '../domain/editor_save_state.dart';
import '../domain/editor_selection.dart';
import '../infrastructure/editor_session_gateway.dart';

typedef EditorCommandIdFactory = String Function();

class EditorSessionController {
  factory EditorSessionController({
    required EditorSessionGateway gateway,
    required EditorCommandIdFactory commandIds,
  }) => EditorSessionController._(gateway, commandIds);

  EditorSessionController._(this._gateway, this._commandIds);

  final EditorSessionGateway _gateway;
  final EditorCommandIdFactory _commandIds;
  final StreamController<EditorDocumentState> _changes =
      StreamController<EditorDocumentState>.broadcast(sync: true);
  StreamSubscription<EditorEvent>? _events;
  final Map<int, int> _pageRequestGenerations = <int, int>{};
  EditorDocumentState _state = const EditorDocumentState();
  bool _disposed = false;

  EditorDocumentState get state => _state;
  Stream<EditorDocumentState> get changes => _changes.stream;

  Future<void> open(String sourcePath) async {
    _ensureActive();
    final metadata = await _gateway.open(sourcePath);
    _events = _gateway.events.listen(_onEvent);
    _emit(
      _state.copyWith(
        sourcePath: sourcePath,
        sessionId: metadata.sessionId,
        revision: metadata.revision,
        pageCount: metadata.pageCount,
        isOpen: true,
        clearError: true,
      ),
    );
    if (metadata.pageCount > 0) {
      await refreshPage(1);
    }
  }

  Future<void> refreshPage(
    int pageNumber, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
    bool force = false,
  }) async {
    _ensureActive();
    if (pageNumber < 1 || pageNumber > _state.pageCount) {
      return;
    }
    if (!force && _state.scenes[pageNumber]?.revision == _state.revision) {
      return;
    }
    final requestedRevision = _state.revision;
    final generation = (_pageRequestGenerations[pageNumber] ?? 0) + 1;
    _pageRequestGenerations[pageNumber] = generation;
    final scene = await _gateway.requestPage(
      pageNumber,
      requestedRevision,
      priority: priority,
    );
    if (_disposed ||
        _pageRequestGenerations[pageNumber] != generation ||
        scene.revision != _state.revision) {
      return;
    }
    final scenes = Map<int, EditorPageScene>.of(_state.scenes)
      ..[pageNumber] = scene;
    final objects = Map<String, EditorObjectState>.of(_state.objects);
    for (final object in scene.objects) {
      if (object.text == null) continue;
      objects[object.objectId] = EditorObjectState(
        objectId: object.objectId,
        pageId: object.pageId,
        acceptedText: object.text!,
        modifiedRevision: object.modifiedRevision,
      );
    }
    _emit(_state.copyWith(scenes: scenes, objects: objects));
  }

  void updateViewport(Set<int> visiblePages, {int preloadRadius = 2}) {
    _ensureActive();
    final visible = visiblePages
        .where((page) => page >= 1 && page <= _state.pageCount)
        .toSet();
    final warm = <int>{};
    for (final page in visible) {
      for (
        var candidate = page - preloadRadius;
        candidate <= page + preloadRadius;
        candidate++
      ) {
        if (candidate >= 1 && candidate <= _state.pageCount) {
          warm.add(candidate);
        }
      }
    }
    for (final page in _pageRequestGenerations.keys.toList(growable: false)) {
      if (!warm.contains(page) && !_state.scenes.containsKey(page)) {
        _pageRequestGenerations[page] = _pageRequestGenerations[page]! + 1;
      }
    }
    for (final page in warm) {
      unawaited(
        refreshPage(
          page,
          priority: visible.contains(page)
              ? EditorViewportPriority.visible
              : EditorViewportPriority.preload,
        ),
      );
    }
  }

  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) {
    _ensureActive();
    return _gateway.cleanPatch(objectId, dpi);
  }

  Future<void> releaseCleanPatchMemory() {
    _ensureActive();
    return _gateway.releaseCleanPatchMemory();
  }

  void updateSelection(EditorSelection? selection) {
    _ensureActive();
    _emit(
      _state.copyWith(selection: selection, clearSelection: selection == null),
    );
  }

  void applyLocalDelta({
    required String objectId,
    required EditorTextRange range,
    required String replacement,
  }) {
    _ensureActive();
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
}

String _errorCode(Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError):\s*'),
    '',
  );
  final separator = message.indexOf(':');
  return separator <= 0
      ? 'editor_command_failed'
      : message.substring(0, separator);
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
