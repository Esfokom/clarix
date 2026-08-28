import 'package:flutter/foundation.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../domain/editor_document_state.dart';
import '../infrastructure/editor_session_gateway.dart';

/// Maintains resident page scenes independently from command submission.
class EditorViewportController {
  EditorViewportController({
    required this.gateway,
    required this.maxResidentScenes,
    required this.state,
    required this.emit,
    required this.isDisposed,
  });

  final EditorSessionGateway gateway;
  final int maxResidentScenes;
  final EditorDocumentState Function() state;
  final void Function(EditorDocumentState) emit;
  final bool Function() isDisposed;
  final Map<int, int> _requestGenerations = <int, int>{};
  int _inFlight = 0;

  Future<void> refreshPage(
    int pageNumber, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
    bool force = false,
  }) async {
    final current = state();
    if (pageNumber < 1 || pageNumber > current.pageCount) return;
    if (!force && current.scenes[pageNumber]?.revision == current.revision) {
      return;
    }
    final generation = (_requestGenerations[pageNumber] ?? 0) + 1;
    _requestGenerations[pageNumber] = generation;
    _beginScan();
    try {
      final scene = await gateway.requestPage(
        pageNumber,
        current.revision,
        priority: priority,
      );
      final latest = state();
      if (isDisposed() ||
          _requestGenerations[pageNumber] != generation ||
          scene.revision != latest.revision) {
        debugPrint(
          '[editor] dropping scene for page $pageNumber: '
          'disposed=${isDisposed()} '
          'staleGeneration=${_requestGenerations[pageNumber] != generation} '
          'staleRevision=${scene.revision != latest.revision}',
        );
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
      while (scenes.length > maxResidentScenes) {
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
      emit(latest.copyWith(scenes: scenes, objects: objects));
    } catch (error) {
      debugPrint('[editor] page $pageNumber scene refresh failed: $error');
      if (priority == EditorViewportPriority.visible &&
          state().errorCode != 'page_scene_failed') {
        emit(state().copyWith(errorCode: 'page_scene_failed'));
      }
    } finally {
      _endScan();
    }
  }

  void _beginScan() {
    _inFlight++;
    if (_inFlight == 1) {
      emit(state().copyWith(scanning: true));
    }
  }

  void _endScan() {
    _inFlight--;
    if (_inFlight == 0) {
      emit(state().copyWith(scanning: false));
    }
  }

  void updateViewport(Set<int> visiblePages, {int preloadRadius = 2}) {
    final current = state();
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
        if (candidate >= 1 && candidate <= current.pageCount) {
          warm.add(candidate);
        }
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
