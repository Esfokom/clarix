import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

bool isFiniteOffset(Offset? value) =>
    value != null && value.dx.isFinite && value.dy.isFinite;

Offset matrixTranslation(Matrix4 matrix) =>
    Offset(matrix.storage[12], matrix.storage[13]);

Offset anchoredTranslation({
  required Offset anchor,
  required Offset oldTranslation,
  required double oldScale,
  required double newScale,
}) {
  final Offset documentPoint = (anchor - oldTranslation) / oldScale;
  return anchor - documentPoint * newScale;
}
