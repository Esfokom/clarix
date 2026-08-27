import 'dart:collection';

import '../../../core/editing/editor_bridge_types.dart';

typedef LivePdfiumTileProducer =
    Future<EditorDirtyTile> Function(LivePdfiumTileRequest request);

/// A revision-keyed, byte-bounded cache for tiles rendered by a live PDFium
/// document. PDFium rendering itself is supplied by the document-owning
/// session so this class has no native handles or isolate affinity.
final class LivePdfiumTileRenderer {
  LivePdfiumTileRenderer({
    required this.producer,
    this.maximumBytes = 64 * 1024 * 1024,
  }) {
    if (maximumBytes <= 0) {
      throw ArgumentError.value(
        maximumBytes,
        'maximumBytes',
        'must be positive',
      );
    }
  }

  final LivePdfiumTileProducer producer;
  final int maximumBytes;
  final LinkedHashMap<_TileKey, EditorDirtyTile> _cache =
      LinkedHashMap<_TileKey, EditorDirtyTile>();
  int _cachedBytes = 0;

  int get cachedTileCount => _cache.length;

  Future<EditorDirtyTile> render(LivePdfiumTileRequest request) async {
    final key = _TileKey.fromRequest(request);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final tile = await producer(request);
    if (tile.pageNumber != request.pageNumber ||
        tile.revision != request.revision ||
        tile.width != request.width ||
        tile.height != request.height) {
      throw StateError('live PDFium tile producer returned a mismatched tile');
    }
    _insert(key, tile);
    return tile;
  }

  bool contains(LivePdfiumTileRequest request) =>
      _cache.containsKey(_TileKey.fromRequest(request));

  void invalidate({
    required int pageNumber,
    required EditorPdfBox bounds,
    required int revision,
  }) {
    final stale = _cache.keys
        .where(
          (key) =>
              key.pageNumber == pageNumber &&
              key.revision < revision &&
              key.intersects(bounds),
        )
        .toList(growable: false);
    for (final key in stale) {
      _remove(key);
    }
  }

  void clear() {
    _cache.clear();
    _cachedBytes = 0;
  }

  void _insert(_TileKey key, EditorDirtyTile tile) {
    _cache[key] = tile;
    _cachedBytes += tile.rgbaBytes.length;
    while (_cachedBytes > maximumBytes && _cache.isNotEmpty) {
      _remove(_cache.keys.first);
    }
  }

  void _remove(_TileKey key) {
    final tile = _cache.remove(key);
    if (tile != null) _cachedBytes -= tile.rgbaBytes.length;
  }
}

final class LivePdfiumTileRequest {
  const LivePdfiumTileRequest({
    required this.pageNumber,
    required this.revision,
    required this.bounds,
    required this.width,
    required this.height,
  });

  final int pageNumber;
  final int revision;
  final EditorPdfBox bounds;
  final int width;
  final int height;
}

final class _TileKey {
  const _TileKey({
    required this.pageNumber,
    required this.revision,
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
    required this.width,
    required this.height,
  });

  factory _TileKey.fromRequest(LivePdfiumTileRequest request) => _TileKey(
    pageNumber: request.pageNumber,
    revision: request.revision,
    left: request.bounds.left,
    bottom: request.bounds.bottom,
    right: request.bounds.right,
    top: request.bounds.top,
    width: request.width,
    height: request.height,
  );

  final int pageNumber;
  final int revision;
  final double left;
  final double bottom;
  final double right;
  final double top;
  final int width;
  final int height;

  bool intersects(EditorPdfBox bounds) =>
      left < bounds.right &&
      right > bounds.left &&
      bottom < bounds.top &&
      top > bounds.bottom;

  @override
  bool operator ==(Object other) =>
      other is _TileKey &&
      pageNumber == other.pageNumber &&
      revision == other.revision &&
      left == other.left &&
      bottom == other.bottom &&
      right == other.right &&
      top == other.top &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(
    pageNumber,
    revision,
    left,
    bottom,
    right,
    top,
    width,
    height,
  );
}
