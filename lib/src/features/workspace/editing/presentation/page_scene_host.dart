import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import 'clean_patch_layer.dart';
import 'page_surface.dart';

typedef PageSceneBuilder =
    Widget Function(BuildContext context, EditorPageScene scene);

class PageSceneLifecycle extends ChangeNotifier {
  PageSceneLifecycle({
    required this.surface,
    required this.controller,
    this.preloadRadius = 2,
  });

  final PageSurface surface;
  final EditorSessionController controller;
  final int preloadRadius;
  StreamSubscription<Object?>? _documentChanges;
  final Map<String, CleanPatchAsset> _cleanPatches =
      <String, CleanPatchAsset>{};
  final Set<String> _patchesInFlight = <String>{};
  bool _started = false;

  Set<int> get visiblePages => surface.viewport.visiblePages;

  EditorPageScene? sceneFor(int pageNumber) =>
      controller.state.scenes[pageNumber];

  Map<String, CleanPatchAsset> cleanPatchesFor(int pageNumber) {
    final objectIds = controller.state.scenes[pageNumber]?.objects
        .map((object) => object.objectId)
        .toSet();
    if (objectIds == null) return const <String, CleanPatchAsset>{};
    return Map<String, CleanPatchAsset>.unmodifiable(
      Map<String, CleanPatchAsset>.fromEntries(
        _cleanPatches.entries.where((entry) => objectIds.contains(entry.key)),
      ),
    );
  }

  void start() {
    if (_started) return;
    _started = true;
    surface.addListener(_syncViewport);
    _documentChanges = controller.changes.listen((_) {
      unawaited(_ensureCleanPatches());
      notifyListeners();
    });
    _syncViewport();
  }

  void _syncViewport() {
    if (!_started || controller.state.isClosed) return;
    controller.updateViewport(
      surface.viewport.visiblePages,
      preloadRadius: preloadRadius,
    );
    _disposeColdPatches();
    unawaited(_ensureCleanPatches());
    notifyListeners();
  }

  Future<void> _ensureCleanPatches() async {
    if (!_started || controller.state.isClosed) return;
    final targetDpi = (144 * surface.viewport.zoom).round().clamp(72, 576);
    final objects = <EditorSceneObject>[
      for (final page in visiblePages)
        ...?controller.state.scenes[page]?.objects,
    ];
    for (final object in objects) {
      if (object.capability != 'editable' ||
          _patchesInFlight.contains(object.objectId) ||
          (_cleanPatches[object.objectId]?.dpi ?? 0) >= targetDpi) {
        continue;
      }
      _patchesInFlight.add(object.objectId);
      try {
        final native = await controller.cleanPatch(object.objectId, targetDpi);
        final decoded = await CleanPatchDecoder.decodeRgba(
          handle: native.handle,
          objectId: native.objectId,
          bounds: native.bounds,
          dpi: native.dpi,
          bleedPoints: native.bleedPoints,
          width: native.width,
          height: native.height,
          rgbaBytes: native.rgbaBytes,
        );
        if (!_started || !_isObjectVisible(object.objectId)) {
          decoded.image.dispose();
          continue;
        }
        _cleanPatches.remove(object.objectId)?.image.dispose();
        _cleanPatches[object.objectId] = decoded;
        notifyListeners();
      } catch (_) {
        // Unsupported patches leave the retained base page untouched.
      } finally {
        _patchesInFlight.remove(object.objectId);
      }
    }
  }

  bool _isObjectVisible(String objectId) => visiblePages.any(
    (page) =>
        controller.state.scenes[page]?.objects.any(
          (object) => object.objectId == objectId,
        ) ??
        false,
  );

  void _disposeColdPatches() {
    final visibleObjects = <String>{
      for (final page in visiblePages)
        for (final object
            in controller.state.scenes[page]?.objects ??
                const <EditorSceneObject>[])
          object.objectId,
    };
    for (final objectId in _cleanPatches.keys.toList(growable: false)) {
      if (!visibleObjects.contains(objectId)) {
        _cleanPatches.remove(objectId)?.image.dispose();
      }
    }
  }

  Future<void> releasePatchMemory() async {
    for (final patch in _cleanPatches.values) {
      patch.image.dispose();
    }
    _cleanPatches.clear();
    await controller.releaseCleanPatchMemory();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_started) surface.removeListener(_syncViewport);
    unawaited(_documentChanges?.cancel());
    for (final patch in _cleanPatches.values) {
      patch.image.dispose();
    }
    _cleanPatches.clear();
    _started = false;
    super.dispose();
  }
}

class PageSceneHost extends StatelessWidget {
  const PageSceneHost({
    required this.lifecycle,
    required this.pageNumber,
    this.builder,
    super.key,
  });

  final PageSceneLifecycle lifecycle;
  final int pageNumber;
  final PageSceneBuilder? builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: lifecycle,
    builder: (context, _) {
      final scene = lifecycle.sceneFor(pageNumber);
      if (!lifecycle.visiblePages.contains(pageNumber) || scene == null) {
        return const SizedBox.shrink();
      }
      return KeyedSubtree(
        key: ValueKey<String>('page-edit-scene-$pageNumber'),
        child: builder?.call(context, scene) ?? const SizedBox.expand(),
      );
    },
  );
}
