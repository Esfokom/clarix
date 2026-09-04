import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Friction used when a pan request looks like a discrete mouse-wheel notch.
///
/// The value is the exponential decay rate per second: roughly 99% of the
/// remaining distance is covered in `4.6 / friction` seconds, so a lower value
/// gives a longer glide.
const double readerPanGlideFriction = 14;

/// Friction used when pan requests arrive as a continuous high-resolution
/// stream (precision trackpads). Smoothing there only adds lag, so the target
/// is tracked almost 1:1 while jitter is still filtered out.
const double readerPanTrackingFriction = 34;

/// A pan request at or below this many logical pixels is treated as part of a
/// continuous stream rather than a wheel notch.
const double readerContinuousPanDeltaThreshold = 10;

/// Friction for cursor-anchored zoom smoothing.
const double readerZoomFriction = 20;

/// Duration for the discrete zoom affordances (HUD buttons, zoom presets).
const Duration readerZoomAnimationDuration = Duration(milliseconds: 220);

/// Distance in logical pixels at which a pan animation snaps to its target.
const double _panSettleEpsilon = 0.4;

/// Zoom delta at which a zoom animation snaps to its target.
const double _zoomSettleEpsilon = 0.0004;

/// Longest frame delta fed to the decay integrator. Guards against the huge
/// step after the app is suspended, which would otherwise teleport the view.
const double _maxFrameSeconds = 1 / 15;

/// Frame-paced pan and zoom smoothing shared by every reader input path.
///
/// Both the pdfrx interaction delegate (mouse wheel) and the reader's own
/// pointer handling (Ctrl+wheel, pointer scale) drive this single object, so a
/// glide and a cursor-anchored zoom can never fight over the same matrix:
/// starting one cancels the other instead of animating towards a stale target.
///
/// Every step is an exponential decay towards an accumulated target, which is
/// what lets rapid input compound smoothly: a second wheel notch extends the
/// target while the first one is still being consumed.
class ReaderViewportMotion {
  PdfViewerController? _controller;
  TickerProvider? _vsync;

  Ticker? _panTicker;
  Offset? _panTarget;
  Duration? _panFrame;
  double _panFriction = readerPanGlideFriction;

  Ticker? _zoomTicker;
  double? _zoomTarget;
  Offset? _zoomFocalPoint;
  Duration? _zoomFrame;

  /// Called each time an animation reaches its target.
  VoidCallback? onSettled;

  bool get isPanning => _panTicker != null;

  bool get isZooming => _zoomTicker != null;

  /// The zoom the viewer is heading towards, or the current zoom when idle.
  double? get targetZoom => _zoomTarget ?? _controller?.currentZoom;

  void attach(PdfViewerController controller, TickerProvider vsync) {
    if (identical(_controller, controller) && identical(_vsync, vsync)) {
      return;
    }
    stop();
    _controller = controller;
    _vsync = vsync;
  }

  void detach() {
    stop();
    _controller = null;
    _vsync = null;
  }

  void stop() {
    _stopPan();
    _stopZoom();
  }

  /// Requests a scroll of [delta] viewport pixels, smoothed over the next few
  /// frames.
  void panBy(Offset delta) {
    final PdfViewerController? controller = _controller;
    final TickerProvider? vsync = _vsync;
    if (controller == null ||
        vsync == null ||
        !controller.isReady ||
        !delta.isFinite ||
        delta == Offset.zero) {
      return;
    }
    _stopZoom();
    _panFriction = delta.distance <= readerContinuousPanDeltaThreshold
        ? readerPanTrackingFriction
        : readerPanGlideFriction;
    _panTarget = (_panTarget ?? _translation(controller)) + delta;
    if (_panTicker == null) {
      _panFrame = null;
      _panTicker = vsync.createTicker(_onPanTick)..start();
    }
  }

  /// Requests a relative zoom by [scaleFactor] keeping [focalPoint] pinned.
  void zoomBy({required double scaleFactor, required Offset focalPoint}) {
    final PdfViewerController? controller = _controller;
    if (controller == null ||
        !controller.isReady ||
        !scaleFactor.isFinite ||
        scaleFactor <= 0) {
      return;
    }
    zoomTo(
      zoom: (_zoomTarget ?? controller.currentZoom) * scaleFactor,
      focalPoint: focalPoint,
    );
  }

  /// Requests an absolute zoom keeping [focalPoint] pinned.
  void zoomTo({required double zoom, required Offset focalPoint}) {
    final PdfViewerController? controller = _controller;
    final TickerProvider? vsync = _vsync;
    if (controller == null ||
        vsync == null ||
        !controller.isReady ||
        !zoom.isFinite) {
      return;
    }
    _stopPan();
    _zoomTarget = zoom
        .clamp(controller.minScale, controller.maxScale)
        .toDouble();
    _zoomFocalPoint = focalPoint;
    if (_zoomTicker == null) {
      _zoomFrame = null;
      _zoomTicker = vsync.createTicker(_onZoomTick)..start();
    }
  }

  void _stopPan() {
    _panTicker?.dispose();
    _panTicker = null;
    _panTarget = null;
    _panFrame = null;
  }

  void _stopZoom() {
    _zoomTicker?.dispose();
    _zoomTicker = null;
    _zoomTarget = null;
    _zoomFocalPoint = null;
    _zoomFrame = null;
  }

  void _onPanTick(Duration elapsed) {
    final PdfViewerController? controller = _controller;
    final Offset? target = _panTarget;
    if (controller == null || !controller.isReady || target == null) {
      _stopPan();
      return;
    }
    final double dt = _frameSeconds(_panFrame, elapsed);
    _panFrame = elapsed;

    final Offset current = _translation(controller);
    final Offset diff = target - current;
    if (diff.distance < _panSettleEpsilon) {
      _applyTranslation(controller, target);
      _stopPan();
      onSettled?.call();
      return;
    }
    _applyTranslation(controller, current + diff * _alpha(_panFriction, dt));
  }

  void _onZoomTick(Duration elapsed) {
    final PdfViewerController? controller = _controller;
    final double? target = _zoomTarget;
    final Offset? focalPoint = _zoomFocalPoint;
    if (controller == null ||
        !controller.isReady ||
        target == null ||
        focalPoint == null) {
      _stopZoom();
      return;
    }
    final double dt = _frameSeconds(_zoomFrame, elapsed);
    _zoomFrame = elapsed;

    final double current = controller.currentZoom;
    final double diff = target - current;
    if (diff.abs() < _zoomSettleEpsilon) {
      _applyZoom(controller, target, focalPoint);
      _stopZoom();
      onSettled?.call();
      return;
    }
    _applyZoom(
      controller,
      current + diff * _alpha(readerZoomFriction, dt),
      focalPoint,
    );
  }

  void _applyTranslation(PdfViewerController controller, Offset translation) {
    final Matrix4 matrix = controller.value.clone()
      ..setEntry(0, 3, translation.dx)
      ..setEntry(1, 3, translation.dy);
    controller.value = controller.makeMatrixInSafeRange(
      matrix,
      forceClamp: true,
    );

    // Re-seat the target on whichever axis got clamped: otherwise the decay
    // keeps pushing against the boundary and a reverse notch first has to pay
    // back the distance the clamp discarded.
    final Offset? target = _panTarget;
    if (target == null) {
      return;
    }
    final Offset actual = _translation(controller);
    _panTarget = Offset(
      (actual.dx - translation.dx).abs() > 1 ? actual.dx : target.dx,
      (actual.dy - translation.dy).abs() > 1 ? actual.dy : target.dy,
    );
  }

  void _applyZoom(
    PdfViewerController controller,
    double zoom,
    Offset focalPoint,
  ) {
    unawaited(
      controller.zoomOnLocalPosition(
        localPosition: focalPoint,
        newZoom: zoom,
        duration: Duration.zero,
      ),
    );
  }

  static double _alpha(double friction, double dt) =>
      (1 - math.exp(-friction * dt)).clamp(0, 1).toDouble();

  static double _frameSeconds(Duration? previous, Duration elapsed) {
    if (previous == null) {
      return 1 / 60;
    }
    final double dt = (elapsed - previous).inMicroseconds / 1000000;
    if (!dt.isFinite || dt <= 0) {
      return 1 / 60;
    }
    return math.min(dt, _maxFrameSeconds);
  }

  static Offset _translation(PdfViewerController controller) {
    final Matrix4 matrix = controller.value;
    return Offset(matrix.entry(0, 3), matrix.entry(1, 3));
  }
}
