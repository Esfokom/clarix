import 'package:flutter/material.dart';

enum PdfScrollbarAxis { vertical, horizontal }

class PdfScrollbarGeometry {
  const PdfScrollbarGeometry({
    required this.axis,
    required this.trackExtent,
    required this.thumbExtent,
    required this.thumbLeading,
    required this.visibleExtent,
    required this.documentExtent,
    required this.visibleLeading,
  });

  final PdfScrollbarAxis axis;
  final double trackExtent;
  final double thumbExtent;
  final double thumbLeading;
  final double visibleExtent;
  final double documentExtent;
  final double visibleLeading;

  double get maxThumbLeading =>
      (trackExtent - thumbExtent).clamp(0, double.infinity).toDouble();

  double get maxVisibleLeading =>
      (documentExtent - visibleExtent).clamp(0, double.infinity).toDouble();

  bool get isScrollable => documentExtent > visibleExtent && trackExtent > 0;

  double visibleLeadingForThumbLeading(double leading) {
    if (!isScrollable || maxThumbLeading == 0) {
      return 0;
    }
    final double clampedLeading = leading.clamp(0, maxThumbLeading).toDouble();
    return (clampedLeading / maxThumbLeading) * maxVisibleLeading;
  }

  double visibleLeadingForThumbDrag(double dragDelta) {
    return visibleLeadingForThumbLeading(thumbLeading + dragDelta);
  }
}

PdfScrollbarGeometry? calculatePdfScrollbarGeometry({
  required PdfScrollbarAxis axis,
  required Size viewportSize,
  required Rect visibleRect,
  required Size documentSize,
  double minThumbExtent = 28,
}) {
  final double trackExtent =
      axis == PdfScrollbarAxis.vertical ? viewportSize.height : viewportSize.width;
  final double visibleExtent =
      axis == PdfScrollbarAxis.vertical ? visibleRect.height : visibleRect.width;
  final double visibleLeading =
      axis == PdfScrollbarAxis.vertical ? visibleRect.top : visibleRect.left;
  final double documentExtent =
      axis == PdfScrollbarAxis.vertical ? documentSize.height : documentSize.width;

  if (trackExtent <= 0 || visibleExtent <= 0 || documentExtent <= visibleExtent) {
    return null;
  }

  final double visibleRatio = (visibleExtent / documentExtent).clamp(0, 1).toDouble();
  final double thumbExtent =
      (trackExtent * visibleRatio).clamp(minThumbExtent, trackExtent).toDouble();
  final double maxThumbLeading = (trackExtent - thumbExtent).clamp(0, double.infinity).toDouble();
  final double maxVisibleLeading = documentExtent - visibleExtent;
  final double scrollRatio =
      maxVisibleLeading == 0 ? 0 : (visibleLeading / maxVisibleLeading).clamp(0, 1).toDouble();

  return PdfScrollbarGeometry(
    axis: axis,
    trackExtent: trackExtent,
    thumbExtent: thumbExtent,
    thumbLeading: maxThumbLeading * scrollRatio,
    visibleExtent: visibleExtent,
    documentExtent: documentExtent,
    visibleLeading: visibleLeading,
  );
}

Offset resolvePdfZoomAnchor({
  required Offset globalPosition,
  required Offset fallbackLocalPosition,
  required Offset? Function(Offset globalPosition) globalToLocal,
}) {
  return globalToLocal(globalPosition) ?? fallbackLocalPosition;
}
