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
  // Keep small invalidation records after raster eviction. The pdfrx base
  // document still contains the source pixels until Save/reopen.
  final Map<(int, int, int), EditorTileInvalidation> _dirtyCells = {};
  final Set<(int, int, int)> _cellsInFlight = {};
  int _rasterEpoch = 0;
  bool _started = false;
  bool _disposed = false;

  Set<int> get visiblePages => surface.viewport.visiblePages;

  bool get started => _started;

  /// True once [dispose] has run. pdfrx invokes page overlay builders lazily,
  /// outside the pane's build, so hosts must refuse to build against a
  /// disposed lifecycle (AnimatedBuilder would attach to a dead ChangeNotifier).
  bool get isDisposed => _disposed;

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
    final epoch = _rasterEpoch;
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
      if (!_started ||
          epoch != _rasterEpoch ||
          !visiblePages.contains(entry.key)) {
        for (final tile in decoded) {
          tile.image.dispose();
        }
        continue;
      }
      final existing = _liveTiles[entry.key] ?? const <LivePdfiumTileAsset>[];
      final retained = <LivePdfiumTileAsset>[];
      // An asynchronous old render must never replace newer pixels.
      decoded.removeWhere((fresh) {
        final stale = existing.any(
          (old) =>
              _boundsOverlap(old.bounds, fresh.bounds) &&
              old.revision > fresh.revision,
        );
        if (stale) fresh.image.dispose();
        return stale;
      });
      for (final old in existing) {
        final covered = decoded.any(
          (fresh) =>
              fresh.bounds.left <= old.bounds.left &&
              fresh.bounds.right >= old.bounds.right &&
              fresh.bounds.bottom <= old.bounds.bottom &&
              fresh.bounds.top >= old.bounds.top,
        );
        if (covered) {
          old.image.dispose();
        } else {
          retained.add(old);
        }
      }
      _liveTiles[entry.key] = <LivePdfiumTileAsset>[...retained, ...decoded];
      _disposePagePatches(entry.key);
    }
    notifyListeners();
  }

  void start() {
    if (_started) return;
    _started = true;
    debugPrint('[editor] page scene lifecycle started');
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
    const cellSize = 256.0;
    for (final invalidation in invalidations) {
      final size = surface.pageSize(invalidation.pageNumber);
      final bounds = invalidation.bounds;
      final left = bounds.left.clamp(0.0, size.width);
      final right = bounds.right.clamp(0.0, size.width);
      final bottom = bounds.bottom.clamp(0.0, size.height);
      final top = bounds.top.clamp(0.0, size.height);
      for (
        var x = (left / cellSize).floor();
        x < (right / cellSize).ceil();
        x++
      ) {
        for (
          var y = (bottom / cellSize).floor();
          y < (top / cellSize).ceil();
          y++
        ) {
          final key = (invalidation.pageNumber, x, y);
          if ((_dirtyCells[key]?.revision ?? -1) > invalidation.revision) {
            continue;
          }
          _dirtyCells[key] = EditorTileInvalidation(
            pageNumber: invalidation.pageNumber,
            revision: invalidation.revision,
            bounds: EditorPdfBox(
              left: x * cellSize,
              bottom: y * cellSize,
              right: math.min((x + 1) * cellSize, size.width),
              top: math.min((y + 1) * cellSize, size.height),
            ),
          );
        }
      }
    }
    await _ensureLiveCells();
  }

  Future<void> _ensureLiveCells() async {
    if (!_started) return;
    // Bound decoded raster memory to roughly 32 MiB across visible pages.
    // Fixed cells also bound metadata by page area, independent of key count.
    final area = visiblePages.fold<double>(0, (sum, page) {
      final size = surface.pageSize(page);
      return sum + size.width * size.height;
    });
    final scale = math.min(
      (2 * surface.viewport.zoom).clamp(1.0, 8.0),
      math.sqrt(8 * 1024 * 1024 / math.max(1, area)),
    );
    for (final key in _dirtyCells.keys.toList(growable: false)) {
      if (!_started ||
          !visiblePages.contains(key.$1) ||
          _cellsInFlight.contains(key)) {
        continue;
      }
      final dirty = _dirtyCells[key]!;
      final bounds = dirty.bounds;
      final width = math.max(1, ((bounds.right - bounds.left) * scale).ceil());
      final height = math.max(1, ((bounds.top - bounds.bottom) * scale).ceil());
      final current = _liveTiles[key.$1]
          ?.where(
            (tile) =>
                tile.bounds.left == bounds.left &&
                tile.bounds.bottom == bounds.bottom,
          )
          .firstOrNull;
      if (current != null &&
          current.revision >= dirty.revision &&
          current.image.width == width &&
          current.image.height == height) {
        continue;
      }
      _cellsInFlight.add(key);
      final epoch = _rasterEpoch;
      try {
        final tile = await controller.renderLiveTile(
          LivePdfiumTileRequest(
            pageNumber: key.$1,
            revision: dirty.revision,
            bounds: bounds,
            width: width,
            height: height,
          ),
        );
        if (_started &&
            epoch == _rasterEpoch &&
            identical(_dirtyCells[key], dirty)) {
          await replaceLiveTiles([tile]);
        }
      } catch (error) {
        debugPrint('[editor] live region render failed: $error');
      } finally {
        _cellsInFlight.remove(key);
      }
      if (_started && !identical(_dirtyCells[key], dirty)) {
        unawaited(_ensureLiveCells());
      }
    }
  }

  void _syncViewport() {
    if (!_started || controller.state.isClosed) return;
    debugPrint(
      '[editor] viewport sync: visible=${surface.viewport.visiblePages} '
      'preloadRadius=$preloadRadius',
    );
    controller.updateViewport(
      surface.viewport.visiblePages,
      preloadRadius: preloadRadius,
    );
    _disposeColdPatches();
    _disposeColdTiles();
    unawaited(_ensureLiveCells());
    unawaited(_ensureCleanPatches());
    notifyListeners();
  }

  Future<void> _ensureCleanPatches() async {
    if (!_started || controller.state.isClosed) return;
    if (controller.usesLivePdfiumRendering) return;
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
    _rasterEpoch++;
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
    if (_disposed) return;
    _disposed = true;
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
      // pdfrx only lays out pages near the viewport (plus cache extent), so
      // a delivered scene is safe to render; gating on visiblePages here made
      // preloaded scenes flash empty on scroll. Tile/patch memory discipline
      // keeps its own visibility gates.
      final scene = lifecycle.sceneFor(pageNumber);
      if (!lifecycle.started || scene == null) {
        return const SizedBox.shrink();
      }
      return KeyedSubtree(
        key: ValueKey<String>('page-edit-scene-$pageNumber'),
        child: builder?.call(context, scene) ?? const SizedBox.expand(),
      );
    },
  );
}
