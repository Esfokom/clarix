import 'dart:ui';

import 'package:flutter/material.dart';

class DiagnosticCrosshairOverlay extends StatelessWidget {
  const DiagnosticCrosshairOverlay({
    required this.cursor,
    required this.focal,
    super.key,
  });

  final Offset? cursor;
  final Offset? focal;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          if (cursor case final Offset position)
            _positionedCrosshair(
              key: const Key('cursor-crosshair'),
              position: position,
              color: Colors.cyanAccent,
            ),
          if (focal case final Offset position)
            _positionedCrosshair(
              key: const Key('focal-crosshair'),
              position: position,
              color: Colors.amberAccent,
            ),
        ],
      ),
    );
  }

  Widget _positionedCrosshair({
    required Key key,
    required Offset position,
    required Color color,
  }) {
    const double size = 28;
    return Positioned(
      key: key,
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      width: size,
      height: size,
      child: CustomPaint(painter: _DiagnosticCrosshairPainter(color)),
    );
  }
}

class _DiagnosticCrosshairPainter extends CustomPainter {
  const _DiagnosticCrosshairPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final Paint outline = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final Paint foreground = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final Paint paint in <Paint>[outline, foreground]) {
      canvas
        ..drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint)
        ..drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint)
        ..drawCircle(center, 5, paint);
    }
  }

  @override
  bool shouldRepaint(_DiagnosticCrosshairPainter oldDelegate) =>
      color != oldDelegate.color;
}
