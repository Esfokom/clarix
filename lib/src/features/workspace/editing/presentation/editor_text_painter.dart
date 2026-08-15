import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../../core/editing/editor_bridge_types.dart';

abstract interface class EditorLayerObserver {
  void layerPainted(String layer, {String? objectId});
}

abstract final class EditorPageGeometry {
  static Rect rectForBox(
    EditorPdfBox bounds, {
    required Size pageSize,
    required Size displaySize,
    double bleedPoints = 0,
  }) {
    final sx = displaySize.width / pageSize.width;
    final sy = displaySize.height / pageSize.height;
    return Rect.fromLTRB(
      (bounds.left - bleedPoints) * sx,
      (pageSize.height - bounds.top - bleedPoints) * sy,
      (bounds.right + bleedPoints) * sx,
      (pageSize.height - bounds.bottom + bleedPoints) * sy,
    );
  }

  static Offset pointForPdf(
    Offset point, {
    required Size pageSize,
    required Size displaySize,
  }) => Offset(
    point.dx * displaySize.width / pageSize.width,
    (pageSize.height - point.dy) * displaySize.height / pageSize.height,
  );
}

class EditorTextObjectLayer extends StatelessWidget {
  const EditorTextObjectLayer({
    required this.object,
    required this.text,
    required this.pageSize,
    required this.displaySize,
    this.observer,
    super.key,
  });

  final EditorSceneObject object;
  final String text;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: ValueKey<String>('text-object-${object.objectId}'),
    child: CustomPaint(
      size: displaySize,
      painter: EditorTextPainter(
        object: object,
        text: text,
        pageSize: pageSize,
        displaySize: displaySize,
        observer: observer,
      ),
    ),
  );
}

class EditorTextPainter extends CustomPainter {
  EditorTextPainter({
    required this.object,
    required this.text,
    required this.pageSize,
    required this.displaySize,
    this.observer,
  }) : _signature = _paintSignature(object, text, pageSize, displaySize);

  final EditorSceneObject object;
  final String text;
  final Size pageSize;
  final Size displaySize;
  final EditorLayerObserver? observer;
  final int _signature;

  @override
  void paint(Canvas canvas, Size size) {
    observer?.layerPainted('text-object', objectId: object.objectId);
    final bounds = EditorPageGeometry.rectForBox(
      object.bounds,
      pageSize: pageSize,
      displaySize: displaySize,
    );
    final painter = TextPainter(
      text: _textSpan(),
      textDirection: object.layout?.direction == 'rtl'
          ? TextDirection.rtl
          : TextDirection.ltr,
      textScaler: TextScaler.linear(displaySize.width / pageSize.width),
      maxLines: null,
    )..layout(maxWidth: bounds.width);

    canvas.save();
    canvas.clipRect(bounds);
    final transform = object.transform;
    final matrix = Float64List.fromList(<double>[
      transform.a,
      transform.b,
      0,
      0,
      transform.c,
      transform.d,
      0,
      0,
      0,
      0,
      1,
      0,
      transform.e,
      -transform.f,
      0,
      1,
    ]);
    canvas.translate(bounds.left, bounds.top);
    canvas.transform(matrix);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  InlineSpan _textSpan() {
    if (object.runs.isEmpty) {
      return TextSpan(text: text, style: _style(null));
    }
    final units = text.codeUnits;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final run in object.runs) {
      final start = run.start.clamp(cursor, units.length);
      final end = run.end.clamp(start, units.length);
      if (start > cursor) {
        spans.add(
          TextSpan(
            text: String.fromCharCodes(units.sublist(cursor, start)),
            style: _style(null),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: String.fromCharCodes(units.sublist(start, end)),
          style: _style(run.style),
        ),
      );
      cursor = end;
    }
    if (cursor < units.length) {
      spans.add(
        TextSpan(
          text: String.fromCharCodes(units.sublist(cursor)),
          style: _style(null),
        ),
      );
    }
    return TextSpan(children: spans);
  }

  TextStyle _style(EditorTextStyle? style) {
    final effective = style ?? (object.runs.firstOrNull?.style);
    final rgba = effective?.colorRgba ?? const <int>[0, 0, 0, 255];
    return TextStyle(
      color: Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]),
      fontFamily: effective?.fontFamily,
      fontSize: effective?.fontSize ?? 12,
      fontWeight: FontWeight
          .values[(((effective?.fontWeight ?? 400) ~/ 100) - 1).clamp(0, 8)],
      fontStyle: effective?.italic == true
          ? FontStyle.italic
          : FontStyle.normal,
      letterSpacing: object.layout?.characterSpacing,
      height: object.layout == null || effective == null
          ? null
          : object.layout!.lineHeight / effective.fontSize,
    );
  }

  @override
  bool shouldRepaint(covariant EditorTextPainter oldDelegate) =>
      _signature != oldDelegate._signature;
}

int _paintSignature(
  EditorSceneObject object,
  String text,
  Size pageSize,
  Size displaySize,
) => Object.hashAll(<Object?>[
  object.objectId,
  text,
  object.modifiedRevision,
  object.bounds.left,
  object.bounds.bottom,
  object.bounds.right,
  object.bounds.top,
  object.transform.a,
  object.transform.b,
  object.transform.c,
  object.transform.d,
  object.transform.e,
  object.transform.f,
  object.fontFingerprint,
  object.layout?.baseline,
  object.layout?.lineHeight,
  object.layout?.characterSpacing,
  object.layout?.horizontalScale,
  object.layout?.direction,
  Object.hashAll(
    object.runs.map(
      (run) => Object.hash(
        run.start,
        run.end,
        run.style.fontFamily,
        run.style.fontSize,
        run.style.fontWeight,
        run.style.italic,
        Object.hashAll(run.style.colorRgba),
      ),
    ),
  ),
  pageSize,
  displaySize,
]);
