import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A smaller delta gives mouse wheels finer steps while high-resolution
/// trackpads remain continuous.
const double readerPointerZoomSensitivity = 0.65;
const double readerTrackpadZoomThreshold = 0.01;

double dampenReaderPointerScale(
  double rawScale, {
  double sensitivity = readerPointerZoomSensitivity,
}) {
  if (!rawScale.isFinite || rawScale <= 0) {
    return 1;
  }
  return 1 + (rawScale - 1) * sensitivity;
}

class ReaderTrackpadZoomGesture {
  double? _startZoom;
  Offset? _anchor;
  bool _isZooming = false;

  Offset? get anchor => _anchor;
  bool get isZooming => _isZooming;

  void start({required double startZoom, required Offset anchor}) {
    _startZoom = startZoom;
    _anchor = anchor;
    _isZooming = false;
  }

  double? update({
    required double cumulativeScale,
    required double minZoom,
    required double maxZoom,
  }) {
    final double? startZoom = _startZoom;
    if (startZoom == null ||
        _anchor == null ||
        !cumulativeScale.isFinite ||
        cumulativeScale <= 0) {
      return null;
    }
    _isZooming =
        _isZooming || (cumulativeScale - 1).abs() > readerTrackpadZoomThreshold;
    if (!_isZooming) {
      return null;
    }
    return (startZoom * dampenReaderPointerScale(cumulativeScale))
        .clamp(minZoom, maxZoom)
        .toDouble();
  }

  void end() {
    _startZoom = null;
    _anchor = null;
    _isZooming = false;
  }
}

typedef ReaderZoomAnchorProvider = Offset? Function();

/// Keeps pdfrx from re-centering content at viewport boundaries during zoom.
Matrix4 preserveReaderCursorLockedMatrix(Matrix4 matrix) => matrix;

Offset resolveLockedPointerFocalPoint({
  required Offset? lockedFocalPoint,
  required Offset reportedFocalPoint,
}) {
  return lockedFocalPoint ?? reportedFocalPoint;
}

typedef ReaderCursorLockedPdfBuilder =
    Widget Function(BuildContext context, ReaderCursorLockedPdfInput input);

class ReaderCursorLockedPdfRegion extends StatefulWidget {
  const ReaderCursorLockedPdfRegion({
    required this.controller,
    required this.builder,
    super.key,
  });

  final PdfViewerController controller;
  final ReaderCursorLockedPdfBuilder builder;

  @override
  State<ReaderCursorLockedPdfRegion> createState() =>
      _ReaderCursorLockedPdfRegionState();
}

class _ReaderCursorLockedPdfRegionState
    extends State<ReaderCursorLockedPdfRegion> {
  late ReaderCursorLockedPdfInput _input;

  @override
  void initState() {
    super.initState();
    _input = ReaderCursorLockedPdfInput(widget.controller);
  }

  @override
  void didUpdateWidget(covariant ReaderCursorLockedPdfRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _input = ReaderCursorLockedPdfInput(widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _input.rememberPointer,
      onPointerDown: _input.rememberPointer,
      onPointerMove: _input.rememberPointer,
      onPointerUp: _input.rememberPointer,
      onPointerCancel: _input.rememberPointer,
      onPointerSignal: _input.rememberPointer,
      onPointerPanZoomStart: _input.rememberPointer,
      onPointerPanZoomUpdate: _input.rememberPointer,
      onPointerPanZoomEnd: _input.rememberPointer,
      child: widget.builder(context, _input),
    );
  }
}

class ReaderCursorLockedPdfInput {
  ReaderCursorLockedPdfInput(this.controller) {
    interactionDelegateProvider =
        ReaderCursorAnchoredInteractionDelegateProvider(localAnchor);
  }

  final PdfViewerController controller;
  late final ReaderCursorAnchoredInteractionDelegateProvider
  interactionDelegateProvider;
  Offset? _lastPointerGlobalPosition;

  void rememberPointer(PointerEvent event) {
    _lastPointerGlobalPosition = event.position;
  }

  Offset? localAnchor() {
    if (!controller.isReady) {
      return null;
    }
    final Offset? global = _lastPointerGlobalPosition;
    if (global == null) {
      return null;
    }
    final Offset? local = controller.globalToLocal(global);
    if (local == null ||
        !local.dx.isFinite ||
        !local.dy.isFinite ||
        !_isInsideViewport(local, controller.viewSize)) {
      return null;
    }
    return local;
  }

  Matrix4 normalizeMatrix(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? viewerController,
  ) {
    return preserveReaderCursorLockedMatrix(matrix);
  }
}

Offset resolveReaderZoomFocalPoint({
  required Offset? trackedCursorLocal,
  required Offset reportedTrackpadFocalPoint,
  required Size viewportSize,
}) {
  final Offset? tracked = trackedCursorLocal;
  if (tracked != null && _isInsideViewport(tracked, viewportSize)) {
    return tracked;
  }
  if (_isInsideViewport(reportedTrackpadFocalPoint, viewportSize)) {
    return reportedTrackpadFocalPoint;
  }
  return viewportSize.center(Offset.zero);
}

bool _isInsideViewport(Offset point, Size viewportSize) {
  return point.dx.isFinite &&
      point.dy.isFinite &&
      point.dx >= 0 &&
      point.dy >= 0 &&
      point.dx <= viewportSize.width &&
      point.dy <= viewportSize.height;
}

/// Locks zoom to the actual cursor tracked by the reader. The focal point
/// reported by a trackpad gesture may include cumulative two-finger pan and is
/// used only when no valid cursor position is available.
class ReaderCursorAnchoredInteractionDelegateProvider
    extends PdfViewerScrollInteractionDelegateProvider {
  ReaderCursorAnchoredInteractionDelegateProvider(this.anchorProvider);

  final ReaderZoomAnchorProvider anchorProvider;

  @override
  PdfViewerScrollInteractionDelegate create() {
    return _ReaderCursorAnchoredInteractionDelegate(anchorProvider);
  }

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

class _ReaderCursorAnchoredInteractionDelegate
    implements PdfViewerScrollInteractionDelegate {
  _ReaderCursorAnchoredInteractionDelegate(this.anchorProvider);

  final ReaderZoomAnchorProvider anchorProvider;
  PdfViewerController? _controller;

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {
    _controller = controller;
  }

  @override
  void dispose() {
    _controller = null;
  }

  @override
  void stop() {}

  @override
  void pan(Offset delta, PdfViewerLayoutMetrics layoutMetrics) {
    final PdfViewerController? controller = _controller;
    if (controller == null || !controller.isReady) {
      return;
    }
    final Matrix4 matrix = controller.value.clone()
      ..setEntry(0, 3, controller.value.entry(0, 3) + delta.dx)
      ..setEntry(1, 3, controller.value.entry(1, 3) + delta.dy);
    controller.value = controller.makeMatrixInSafeRange(
      matrix,
      forceClamp: true,
    );
  }

  @override
  void zoom(
    double scale,
    Offset reportedFocalPoint,
    PdfViewerLayoutMetrics layoutMetrics,
  ) {
    final PdfViewerController? controller = _controller;
    if (controller == null || !controller.isReady) {
      return;
    }
    final double currentZoom = controller.currentZoom;
    final double newZoom = (currentZoom * scale)
        .clamp(layoutMetrics.minScale, layoutMetrics.maxScale)
        .toDouble();
    if ((newZoom - currentZoom).abs() < 0.0001) {
      return;
    }
    final Offset focalPoint = resolveReaderZoomFocalPoint(
      trackedCursorLocal: anchorProvider(),
      reportedTrackpadFocalPoint: reportedFocalPoint,
      viewportSize: controller.viewSize,
    );
    unawaited(
      controller.zoomOnLocalPosition(
        localPosition: focalPoint,
        newZoom: newZoom,
        duration: Duration.zero,
      ),
    );
  }
}

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
  final double trackExtent = axis == PdfScrollbarAxis.vertical
      ? viewportSize.height
      : viewportSize.width;
  final double visibleExtent = axis == PdfScrollbarAxis.vertical
      ? visibleRect.height
      : visibleRect.width;
  final double visibleLeading = axis == PdfScrollbarAxis.vertical
      ? visibleRect.top
      : visibleRect.left;
  final double documentExtent = axis == PdfScrollbarAxis.vertical
      ? documentSize.height
      : documentSize.width;

  if (trackExtent <= 0 ||
      visibleExtent <= 0 ||
      documentExtent <= visibleExtent) {
    return null;
  }

  final double visibleRatio = (visibleExtent / documentExtent)
      .clamp(0, 1)
      .toDouble();
  final double thumbExtent = (trackExtent * visibleRatio)
      .clamp(minThumbExtent, trackExtent)
      .toDouble();
  final double maxThumbLeading = (trackExtent - thumbExtent)
      .clamp(0, double.infinity)
      .toDouble();
  final double maxVisibleLeading = documentExtent - visibleExtent;
  final double scrollRatio = maxVisibleLeading == 0
      ? 0
      : (visibleLeading / maxVisibleLeading).clamp(0, 1).toDouble();

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
  final Offset? converted = globalToLocal(globalPosition);
  if (converted == null || !converted.dx.isFinite || !converted.dy.isFinite) {
    return fallbackLocalPosition;
  }
  return converted;
}
