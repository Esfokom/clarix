import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/editing/editor_bridge_types.dart';
import 'editor_text_painter.dart';

class CleanPatchAsset {
  const CleanPatchAsset({
    required this.handle,
    required this.objectId,
    required this.bounds,
    required this.dpi,
    required this.bleedPoints,
    required this.image,
  });

  final String handle;
  final String objectId;
  final EditorPdfBox bounds;
  final int dpi;
  final double bleedPoints;
  final ui.Image image;
}

abstract final class CleanPatchDecoder {
  static Future<CleanPatchAsset> decodeRgba({
    required String handle,
    required String objectId,
    required EditorPdfBox bounds,
    required int dpi,
    required double bleedPoints,
    required int width,
    required int height,
    required Uint8List rgbaBytes,
  }) async {
    if (rgbaBytes.length != width * height * 4) {
      throw ArgumentError.value(
        rgbaBytes.length,
        'rgbaBytes',
        'must contain exactly width * height * 4 bytes',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgbaBytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return CleanPatchAsset(
      handle: handle,
      objectId: objectId,
      bounds: bounds,
      dpi: dpi,
      bleedPoints: bleedPoints,
      image: frame.image,
    );
  }
}

class CleanPatchLayer extends StatelessWidget {
  const CleanPatchLayer({
    required this.asset,
    required this.pageSize,
    required this.displaySize,
    this.observer,
    super.key,
  });

  final CleanPatchAsset asset;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: ValueKey<String>('clean-patch-${asset.objectId}'),
    child: CustomPaint(
      size: displaySize,
      painter: _CleanPatchPainter(
        asset: asset,
        pageSize: pageSize,
        displaySize: displaySize,
        observer: observer,
      ),
    ),
  );
}

class _CleanPatchPainter extends CustomPainter {
  const _CleanPatchPainter({
    required this.asset,
    required this.pageSize,
    required this.displaySize,
    required this.observer,
  });

  final CleanPatchAsset asset;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;

  @override
  void paint(Canvas canvas, Size size) {
    observer?.layerPainted('clean-patch', objectId: asset.objectId);
    final destination = EditorPageGeometry.rectForBox(
      asset.bounds,
      pageSize: pageSize,
      displaySize: displaySize,
    );
    canvas.save();
    canvas.clipRect(destination);
    canvas.drawImageRect(
      asset.image,
      Rect.fromLTWH(
        0,
        0,
        asset.image.width.toDouble(),
        asset.image.height.toDouble(),
      ),
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CleanPatchPainter oldDelegate) =>
      asset.handle != oldDelegate.asset.handle ||
      asset.dpi != oldDelegate.asset.dpi ||
      displaySize != oldDelegate.displaySize ||
      pageSize != oldDelegate.pageSize;
}
