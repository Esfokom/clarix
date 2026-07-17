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

Offset anchoredPanZoomTranslation({
  required Offset previousAnchor,
  required Offset currentAnchor,
  required Offset oldTranslation,
  required double oldScale,
  required double newScale,
}) {
  final Offset documentPoint = (previousAnchor - oldTranslation) / oldScale;
  return currentAnchor - documentPoint * newScale;
}

bool shouldLockTrackpadZoomAnchor({
  required bool alreadyLocked,
  required double cumulativeScale,
  double scaleThreshold = 0.01,
}) {
  return alreadyLocked ||
      (cumulativeScale.isFinite &&
          (cumulativeScale - 1).abs() > scaleThreshold);
}

Offset trackpadGestureTranslation({
  required Offset zoomAnchor,
  required Offset focalPointDelta,
  required Offset oldTranslation,
  required double oldScale,
  required double newScale,
  required bool zoomAnchorLocked,
}) {
  if (!zoomAnchorLocked) {
    return oldTranslation + focalPointDelta;
  }
  return anchoredTranslation(
    anchor: zoomAnchor,
    oldTranslation: oldTranslation,
    oldScale: oldScale,
    newScale: newScale,
  );
}
