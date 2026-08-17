import '../../../core/editing/editor_bridge_types.dart';
import '../domain/editor_document_state.dart';
import '../infrastructure/editor_session_gateway.dart';

/// Maintains resident page scenes independently from command submission.
class EditorViewportController {
  EditorViewportController({
    required EditorSessionGateway gateway,
    required int maxResidentScenes,
    required EditorDocumentState Function() state,
    required void Function(EditorDocumentState) emit,
    required bool Function() isDisposed,
  }) : _gateway = gateway,
       _maxResidentScenes = maxResidentScenes,
       _state = state,
       _emit = emit,
       _isDisposed = isDisposed;

  final EditorSessionGateway _gateway;
  final int _maxResidentScenes;
  final EditorDocumentState Function() _state;
  final void Function(EditorDocumentState) _emit;
  final bool Function() _isDisposed;
  final Map<int, int> _requestGenerations = <int, int>{};

  Future<void> refreshPage(
    int pageNumber, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
    bool force = false,
  }) async {
    final current = _state();
    if (pageNumber < 1 || pageNumber > current.pageCount) return;
    if (!force && current.scenes[pageNumber]?.revision == current.revision) {
      return;
    }
    final generation = (_requestGenerations[pageNumber] ?? 0) + 1;
    _requestGenerations[pageNumber] = generation;
    final scene = await _gateway.requestPage(
      pageNumber,
      current.revision,
      priority: priority,
    );
    final latest = _state();
    if (_isDisposed() ||
        _requestGenerations[pageNumber] != generation ||
        scene.revision != latest.revision) {
      return;
    }
    final scenes = Map<int, EditorPageScene>.of(latest.scenes)
      ..remove(pageNumber)
      ..[pageNumber] = scene;
    final objects = Map<String, EditorObjectState>.of(latest.objects);
    final protectedObjects = <String>{
      if (latest.selection case final selection?) selection.objectId,
      if (latest.optimisticEdit case final edit?) edit.objectId,
      if (latest.queuedEdit case final edit?) edit.objectId,
    };
    while (scenes.length > _maxResidentScenes) {
      final candidates = scenes.keys.where(
        (candidate) =>
            candidate != pageNumber &&
            !scenes[candidate]!.objects.any(
              (object) => protectedObjects.contains(object.objectId),
            ),
      );
      if (candidates.isEmpty) break;
      final coldPage = candidates.first;
      final coldScene = scenes.remove(coldPage)!;
      _requestGenerations.remove(coldPage);
      for (final object in coldScene.objects) {
        if (!protectedObjects.contains(object.objectId)) {
          objects.remove(object.objectId);
        }
      }
    }
    for (final object in scene.objects) {
      if (object.text == null) continue;
      objects[object.objectId] = EditorObjectState(
        objectId: object.objectId,
        pageId: object.pageId,
        acceptedText: object.text!,
        modifiedRevision: object.modifiedRevision,
      );
    }
    _emit(latest.copyWith(scenes: scenes, objects: objects));
  }

  void updateViewport(Set<int> visiblePages, {int preloadRadius = 2}) {
    final current = _state();
    final visible = visiblePages
        .where((page) => page >= 1 && page <= current.pageCount)
        .toSet();
    final warm = <int>{};
    for (final page in visible) {
      for (
        var candidate = page - preloadRadius;
        candidate <= page + preloadRadius;
        candidate++
      ) {
        if (candidate >= 1 && candidate <= current.pageCount)
          warm.add(candidate);
      }
    }
    for (final page in _requestGenerations.keys.toList(growable: false)) {
      if (!warm.contains(page) && !current.scenes.containsKey(page)) {
        _requestGenerations[page] = _requestGenerations[page]! + 1;
      }
    }
    for (final page in warm) {
      refreshPage(
        page,
        priority: visible.contains(page)
            ? EditorViewportPriority.visible
            : EditorViewportPriority.preload,
      );
    }
  }
}
