import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/editing/editor_bridge_types.dart';
import 'editor_text_painter.dart';

/// A decoded raster region produced by the authoritative live PDFium document.
class LivePdfiumTileAsset {
  const LivePdfiumTileAsset({
    required this.pageNumber,
    required this.revision,
    required this.bounds,
    required this.image,
  });

  final int pageNumber;
  final int revision;
  final EditorPdfBox bounds;
  final ui.Image image;
}

abstract final class LivePdfiumTileDecoder {
  static Future<LivePdfiumTileAsset> decode(EditorDirtyTile tile) async {
    if (tile.rgbaBytes.length != tile.width * tile.height * 4) {
      throw ArgumentError.value(
        tile.rgbaBytes,
        'rgbaBytes',
        'invalid tile size',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(tile.rgbaBytes),
    );
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: tile.width,
      height: tile.height,
      rowBytes: tile.width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return LivePdfiumTileAsset(
      pageNumber: tile.pageNumber,
      revision: tile.revision,
      bounds: tile.bounds,
      image: frame.image,
    );
  }
}

/// Paints live PDFium output in page coordinates; Flutter overlays remain
/// responsible for selections, carets, and controls only.
class LivePdfiumTileLayer extends StatelessWidget {
  const LivePdfiumTileLayer({
    required this.tiles,
    required this.pageSize,
    required this.displaySize,
    super.key,
  });

  final List<LivePdfiumTileAsset> tiles;
  final Size pageSize;
  final Size displaySize;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const Key('live-pdfium-tile'),
    child: CustomPaint(
      size: displaySize,
      painter: _LivePdfiumTilePainter(
        tiles: tiles,
        pageSize: pageSize,
        displaySize: displaySize,
      ),
    ),
  );
}

class _LivePdfiumTilePainter extends CustomPainter {
  const _LivePdfiumTilePainter({
    required this.tiles,
    required this.pageSize,
    required this.displaySize,
  });

  final List<LivePdfiumTileAsset> tiles;
  final Size pageSize;
  final Size displaySize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final tile in tiles) {
      final destination = EditorPageGeometry.rectForBox(
        tile.bounds,
        pageSize: pageSize,
        displaySize: displaySize,
      );
      canvas.drawImageRect(
        tile.image,
        Rect.fromLTWH(
          0,
          0,
          tile.image.width.toDouble(),
          tile.image.height.toDouble(),
        ),
        destination,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LivePdfiumTilePainter oldDelegate) =>
      !identical(tiles, oldDelegate.tiles) ||
      pageSize != oldDelegate.pageSize ||
      displaySize != oldDelegate.displaySize;
}
