import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import '../infrastructure/live_pdfium_tile_renderer.dart';
import 'clean_patch_layer.dart';
import 'live_pdfium_tile_layer.dart';
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
  StreamSubscription<List<EditorTileInvalidation>>? _liveTileInvalidations;
  final Map<String, CleanPatchAsset> _cleanPatches =
      <String, CleanPatchAsset>{};
  final Map<int, List<LivePdfiumTileAsset>> _liveTiles =
      <int, List<LivePdfiumTileAsset>>{};
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

  List<LivePdfiumTileAsset> liveTilesFor(int pageNumber) =>
      List<LivePdfiumTileAsset>.unmodifiable(
        _liveTiles[pageNumber] ?? const <LivePdfiumTileAsset>[],
      );

  /// Replaces only the affected page's live raster output. Tiles that become
  /// stale are disposed immediately, while unchanged pages remain resident.
  Future<void> replaceLiveTiles(List<EditorDirtyTile> tiles) async {
    if (!_started || tiles.isEmpty) return;
    final grouped = <int, List<EditorDirtyTile>>{};
    for (final tile in tiles) {
      (grouped[tile.pageNumber] ??= <EditorDirtyTile>[]).add(tile);
    }
    for (final entry in grouped.entries) {
      final decoded = <LivePdfiumTileAsset>[];
      try {
        for (final tile in entry.value) {
          decoded.add(await LivePdfiumTileDecoder.decode(tile));
        }
      } catch (_) {
        for (final tile in decoded) {
          tile.image.dispose();
        }
        rethrow;
      }
      if (!_started || !visiblePages.contains(entry.key)) {
        for (final tile in decoded) {
          tile.image.dispose();
        }
        continue;
      }
      // Merge new tiles into the existing set instead of replacing all
      // tiles for the page. Only dispose existing tiles whose bounds
      // intersect with the incoming patch — retain the rest so partial
      // invalidations don't wipe out the surrounding document.
      final existing =
          _liveTiles[entry.key] ?? const <LivePdfiumTileAsset>[];
      final retained = <LivePdfiumTileAsset>[];
      for (final old in existing) {
        final overlaps = decoded.any(
          (fresh) => _boundsOverlap(old.bounds, fresh.bounds),
        );
        if (overlaps) {
          old.image.dispose();
        } else {
          retained.add(old);
        }
      }
      _liveTiles[entry.key] = <LivePdfiumTileAsset>[...retained, ...decoded];
      _disposePagePatches(entry.key);
    }
    // Enforce a per-page tile limit to avoid unbounded memory growth.
    // When a page exceeds the cap, drop the oldest tiles first.
    const maxTilesPerPage = 32;
    for (final pageNumber in _liveTiles.keys.toList(growable: false)) {
      final pageTiles = _liveTiles[pageNumber]!;
      if (pageTiles.length > maxTilesPerPage) {
        final excess = pageTiles.length - maxTilesPerPage;
        for (var i = 0; i < excess; i++) {
          pageTiles[i].image.dispose();
        }
        _liveTiles[pageNumber] = pageTiles.sublist(excess);
      }
    }
    notifyListeners();
  }

  void start() {
    if (_started) return;
    _started = true;
    surface.addListener(_syncViewport);
    _documentChanges = controller.changes.listen((_) {
      unawaited(_ensureCleanPatches());
      notifyListeners();
    });
    _liveTileInvalidations = controller.liveTileInvalidations.listen(
      (invalidations) => unawaited(_replaceLiveInvalidations(invalidations)),
    );
    _syncViewport();
  }

  Future<void> _replaceLiveInvalidations(
    List<EditorTileInvalidation> invalidations,
  ) async {
    if (!_started || invalidations.isEmpty) return;
    final dpi = (144 * surface.viewport.zoom).round().clamp(72, 576);
    final visible = invalidations
        .where((invalidation) => visiblePages.contains(invalidation.pageNumber))
        .toList(growable: false);
    if (visible.isEmpty) return;
    try {
      final tiles = await Future.wait(
        visible.map(
          (invalidation) => controller.renderLiveTile(
            LivePdfiumTileRequest(
              pageNumber: invalidation.pageNumber,
              revision: invalidation.revision,
              bounds: invalidation.bounds,
              width: math.max(
                1,
                ((invalidation.bounds.right - invalidation.bounds.left) *
                        dpi /
                        72)
                    .ceil(),
              ),
              height: math.max(
                1,
                ((invalidation.bounds.top - invalidation.bounds.bottom) *
                        dpi /
                        72)
                    .ceil(),
              ),
            ),
          ),
        ),
      );
      await replaceLiveTiles(tiles);
    } catch (_) {
      // If a live tile cannot be produced, retain the normal page/patch path.
    }
  }

  void _syncViewport() {
    if (!_started || controller.state.isClosed) return;
    controller.updateViewport(
      surface.viewport.visiblePages,
      preloadRadius: preloadRadius,
    );
    _disposeColdPatches();
    _disposeColdTiles();
    unawaited(_ensureCleanPatches());
    notifyListeners();
  }

  Future<void> _ensureCleanPatches() async {
    if (!_started || controller.state.isClosed) return;
    final targetDpi = (144 * surface.viewport.zoom).round().clamp(72, 576);
    final objects = <EditorSceneObject>[
      for (final page in visiblePages)
        if (!_liveTiles.containsKey(page))
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

  void _disposePagePatches(int pageNumber) {
    final objectIds = controller.state.scenes[pageNumber]?.objects
        .map((object) => object.objectId)
        .toSet();
    if (objectIds == null) return;
    for (final objectId in objectIds) {
      _cleanPatches.remove(objectId)?.image.dispose();
    }
  }

  void _disposeColdTiles() {
    for (final pageNumber in _liveTiles.keys.toList(growable: false)) {
      if (visiblePages.contains(pageNumber)) continue;
      for (final tile in _liveTiles.remove(pageNumber)!) {
        tile.image.dispose();
      }
    }
  }

  Future<void> releasePatchMemory() async {
    for (final patch in _cleanPatches.values) {
      patch.image.dispose();
    }
    _cleanPatches.clear();
    for (final tiles in _liveTiles.values) {
      for (final tile in tiles) {
        tile.image.dispose();
      }
    }
    _liveTiles.clear();
    await controller.releaseCleanPatchMemory();
    notifyListeners();
  }

  static bool _boundsOverlap(EditorPdfBox a, EditorPdfBox b) {
    // PDF coordinates: left < right, bottom < top.
    // Two boxes overlap when neither is fully to the left/right/above/below
    // the other.
    if (a.right <= b.left || b.right <= a.left) return false;
    final aBottom = a.bottom < a.top ? a.bottom : a.top;
    final aTop = a.bottom < a.top ? a.top : a.bottom;
    final bBottom = b.bottom < b.top ? b.bottom : b.top;
    final bTop = b.bottom < b.top ? b.top : b.bottom;
    if (aTop <= bBottom || bTop <= aBottom) return false;
    return true;
  }

  @override
  void dispose() {
    if (_started) surface.removeListener(_syncViewport);
    unawaited(_documentChanges?.cancel());
    unawaited(_liveTileInvalidations?.cancel());
    for (final patch in _cleanPatches.values) {
      patch.image.dispose();
    }
    _cleanPatches.clear();
    for (final tiles in _liveTiles.values) {
      for (final tile in tiles) {
        tile.image.dispose();
      }
    }
    _liveTiles.clear();
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
