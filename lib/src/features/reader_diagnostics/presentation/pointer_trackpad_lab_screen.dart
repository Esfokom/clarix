import 'dart:ui' show Offset, PointerDeviceKind;

import 'package:clarix/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_math.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/widgets/diagnostic_crosshair.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/widgets/diagnostics_event_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

@immutable
class PointerLabState {
  const PointerLabState({
    this.cursor,
    this.focal,
    this.scale = 1,
    this.translation = Offset.zero,
    this.pan = Offset.zero,
    this.deviceKind = 'unknown',
  });

  final Offset? cursor;
  final Offset? focal;
  final double scale;
  final Offset translation;
  final Offset pan;
  final String deviceKind;

  PointerLabState copyWith({
    Offset? cursor,
    Offset? focal,
    double? scale,
    Offset? translation,
    Offset? pan,
    String? deviceKind,
  }) {
    return PointerLabState(
      cursor: cursor ?? this.cursor,
      focal: focal ?? this.focal,
      scale: scale ?? this.scale,
      translation: translation ?? this.translation,
      pan: pan ?? this.pan,
      deviceKind: deviceKind ?? this.deviceKind,
    );
  }

  PointerLabState withDeviceKind(PointerDeviceKind value) =>
      copyWith(deviceKind: value.name);
}

class PointerTrackpadLabScreen extends StatefulWidget {
  const PointerTrackpadLabScreen({
    this.onBack,
    this.recorder,
    this.copyDiagnosticsText,
    super.key,
  });

  final VoidCallback? onBack;
  final ReaderDiagnosticsRecorder? recorder;
  final DiagnosticsCopyText? copyDiagnosticsText;

  @override
  State<PointerTrackpadLabScreen> createState() =>
      _PointerTrackpadLabScreenState();
}

class _PointerTrackpadLabScreenState extends State<PointerTrackpadLabScreen> {
  late final ReaderDiagnosticsRecorder _recorder;
  late final bool _ownsRecorder;
  late final ValueNotifier<PointerLabState> _state;
  final GlobalKey _canvasKey = GlobalKey();

  double _lastGestureScale = 1;
  bool _overlaysHidden = false;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? ReaderDiagnosticsRecorder();
    _ownsRecorder = widget.recorder == null;
    _state = ValueNotifier<PointerLabState>(
      const PointerLabState(focal: Offset(40, 40)),
    );
  }

  @override
  void dispose() {
    _state.dispose();
    if (_ownsRecorder) {
      _recorder.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10151C),
      body: SafeArea(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerHover: _onPointerHover,
          onPointerMove: _onPointerMove,
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomStart: _onPointerPanZoomStart,
          onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
          onPointerPanZoomEnd: _onPointerPanZoomEnd,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                KeyedSubtree(
                  key: const Key('pointer-lab-canvas'),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: _canvasKey,
                      painter: _PointerLabCanvasPainter(state: _state),
                    ),
                  ),
                ),
                const _QuadrantLabel(
                  label: 'Q1',
                  alignment: Alignment(-0.5, -0.5),
                ),
                const _QuadrantLabel(
                  label: 'Q2',
                  alignment: Alignment(0.5, -0.5),
                ),
                const _QuadrantLabel(
                  label: 'Q3',
                  alignment: Alignment(-0.5, 0.5),
                ),
                const _QuadrantLabel(
                  label: 'Q4',
                  alignment: Alignment(0.5, 0.5),
                ),
                Positioned.fill(
                  child: ValueListenableBuilder<PointerLabState>(
                    valueListenable: _state,
                    builder: (
                      BuildContext context,
                      PointerLabState state,
                      Widget? child,
                    ) {
                      return Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          DiagnosticCrosshairOverlay(
                            cursor: state.cursor,
                            focal: state.focal,
                          ),
                          if (!_overlaysHidden)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: _PointerLabReadout(
                                state: state,
                                canvasKey: _canvasKey,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (!_overlaysHidden)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: DiagnosticsEventPanel(
                      recorder: _recorder,
                      copyText: widget.copyDiagnosticsText,
                    ),
                  ),
                if (!_overlaysHidden)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: OutlinedButton.icon(
                      key: const Key('pointer-lab-back'),
                      onPressed:
                          widget.onBack ?? () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: const Color(0xD9141B24),
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: const Key('pointer-lab-overlays-toggle'),
                        tooltip: _overlaysHidden
                            ? 'Show lab overlays'
                            : 'Hide lab overlays',
                        onPressed: () => setState(
                          () => _overlaysHidden = !_overlaysHidden,
                        ),
                        icon: Icon(
                          _overlaysHidden
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onPointerHover(PointerHoverEvent event) {
    _setCursor(event.localPosition);
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.pointerHover,
      event: event,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    _setCursor(event.localPosition);
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.pointerMove,
      event: event,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.pointerSignal,
      event: event,
    );
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.panZoomStart,
      event: event,
    );
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.panZoomUpdate,
      event: event,
      scale: event.scale,
      pan: event.pan,
      panDelta: event.panDelta,
    );
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.panZoomEnd,
      event: event,
    );
  }

  void _setCursor(Offset cursor) {
    _state.value = _state.value.copyWith(cursor: cursor);
  }

  void _setDeviceKind(PointerDeviceKind deviceKind) {
    final PointerLabState current = _state.value;
    if (current.deviceKind == deviceKind.name) {
      return;
    }
    _state.value = current.withDeviceKind(deviceKind);
  }

  Size _canvasSize() {
    final RenderObject? renderObject = _canvasKey.currentContext
        ?.findRenderObject();
    return renderObject is RenderBox ? renderObject.size : Size.zero;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastGestureScale = 1;
    final PointerLabState current = _state.value;
    _state.value = current.copyWith(focal: details.localFocalPoint);
    _recordScaleEvent(
      type: ReaderDiagnosticEventType.scaleStart,
      globalPosition: details.focalPoint,
      localFocalPoint: details.localFocalPoint,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final double cumulativeScale = details.scale;
    if (!cumulativeScale.isFinite || cumulativeScale <= 0) {
      return;
    }
    final double scaleRatio = cumulativeScale / _lastGestureScale;
    if (!scaleRatio.isFinite || scaleRatio <= 0) {
      return;
    }

    final PointerLabState current = _state.value;
    final double oldScale = current.scale;
    final double newScale = (oldScale * scaleRatio).clamp(0.25, 8.0).toDouble();
    final Size canvasSize = _canvasSize();
    final Offset currentAnchor = canvasCenteredFocalPoint(
      localFocalPoint: details.localFocalPoint,
      canvasSize: canvasSize,
    );
    final Offset previousAnchor = canvasCenteredFocalPoint(
      localFocalPoint: details.localFocalPoint - details.focalPointDelta,
      canvasSize: canvasSize,
    );
    final Offset translation = anchoredPanZoomTranslation(
      previousAnchor: previousAnchor,
      currentAnchor: currentAnchor,
      oldTranslation: current.translation,
      oldScale: oldScale,
      newScale: newScale,
    );
    _lastGestureScale = cumulativeScale;
    _state.value = current.copyWith(
      focal: details.localFocalPoint,
      scale: newScale,
      translation: translation,
      pan: details.focalPointDelta,
    );
    _recordScaleEvent(
      type: ReaderDiagnosticEventType.scaleUpdate,
      globalPosition: details.focalPoint,
      localFocalPoint: details.localFocalPoint,
      scale: newScale,
      pan: details.focalPointDelta,
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastGestureScale = 1;
    _recordScaleEvent(type: ReaderDiagnosticEventType.scaleEnd);
  }

  void _recordPointerEvent({
    required ReaderDiagnosticEventType type,
    required PointerEvent event,
    double? scale,
    Offset? pan,
    Offset? panDelta,
  }) {
    _setDeviceKind(event.kind);
    final PointerLabState state = _state.value;
    _recorder.record(
      source: ReaderDiagnosticSource.pointerListener,
      type: type,
      deviceKind: _diagnosticDeviceKind(event.kind),
      global: ReaderDiagnosticPoint.fromOffset(event.position),
      listenerLocal: ReaderDiagnosticPoint.fromOffset(event.localPosition),
      cursor: _pointOrNull(state.cursor),
      focal: _pointOrNull(state.focal),
      scale: scale,
      pan: _pointOrNull(pan),
      panDelta: _pointOrNull(panDelta),
    );
  }

  void _recordScaleEvent({
    required ReaderDiagnosticEventType type,
    Offset? globalPosition,
    Offset? localFocalPoint,
    double? scale,
    Offset? pan,
  }) {
    final PointerLabState state = _state.value;
    _recorder.record(
      source: ReaderDiagnosticSource.pointerListener,
      type: type,
      deviceKind: ReaderDiagnosticDeviceKind.fromRaw(state.deviceKind),
      global: _pointOrNull(globalPosition),
      listenerLocal: _pointOrNull(localFocalPoint),
      cursor: _pointOrNull(state.cursor),
      focal: _pointOrNull(state.focal),
      scale: scale,
      pan: _pointOrNull(pan),
      panDelta: _pointOrNull(pan),
    );
  }
}

Offset canvasCenteredFocalPoint({
  required Offset localFocalPoint,
  required Size canvasSize,
}) =>
    localFocalPoint - canvasSize.center(Offset.zero);

ReaderDiagnosticPoint? _pointOrNull(Offset? value) =>
    value == null ? null : ReaderDiagnosticPoint.fromOffset(value);

ReaderDiagnosticDeviceKind _diagnosticDeviceKind(PointerDeviceKind kind) {
  return switch (kind) {
    PointerDeviceKind.mouse => ReaderDiagnosticDeviceKind.mouse,
    PointerDeviceKind.touch => ReaderDiagnosticDeviceKind.touch,
    PointerDeviceKind.stylus => ReaderDiagnosticDeviceKind.stylus,
    PointerDeviceKind.invertedStylus =>
      ReaderDiagnosticDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad => ReaderDiagnosticDeviceKind.trackpad,
    PointerDeviceKind.unknown => ReaderDiagnosticDeviceKind.unknown,
  };
}

class _QuadrantLabel extends StatelessWidget {
  const _QuadrantLabel({required this.label, required this.alignment});

  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC10151C),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PointerLabReadout extends StatelessWidget {
  const _PointerLabReadout({
    required this.state,
    required this.canvasKey,
  });

  final PointerLabState state;
  final GlobalKey canvasKey;

  @override
  Widget build(BuildContext context) {
    final RenderObject? renderObject = canvasKey.currentContext
        ?.findRenderObject();
    final RenderBox? canvas = renderObject is RenderBox ? renderObject : null;
    final Offset? cursorGlobal = _globalPosition(canvas, state.cursor);
    final Offset? focalGlobal = _globalPosition(canvas, state.focal);

    return Material(
      color: const Color(0xE6141B24),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Pointer / Trackpad Lab',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('cursor local: ${_formatOffset(state.cursor)}'),
                Text('cursor global: ${_formatOffset(cursorGlobal)}'),
                Text('focal local:  ${_formatOffset(state.focal)}'),
                Text('focal global: ${_formatOffset(focalGlobal)}'),
                Text('scale: ${state.scale.toStringAsFixed(4)}'),
                Text('translation: ${_formatOffset(state.translation)}'),
                Text('pan: ${_formatOffset(state.pan)}'),
                Text('device: ${state.deviceKind}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Offset? _globalPosition(RenderBox? box, Offset? local) =>
      box == null || local == null ? null : box.localToGlobal(local);

  String _formatOffset(Offset? value) {
    if (value == null) {
      return '—';
    }
    return '(${value.dx.toStringAsFixed(2)}, ${value.dy.toStringAsFixed(2)})';
  }
}

class _PointerLabCanvasPainter extends CustomPainter {
  _PointerLabCanvasPainter({required this.state}) : super(repaint: state);

  final ValueListenable<PointerLabState> state;

  @override
  void paint(Canvas canvas, Size size) {
    final PointerLabState value = state.value;
    final Rect viewport = Offset.zero & size;
    final Paint background = Paint()..color = const Color(0xFF10151C);
    final Paint grid = Paint()
      ..color = const Color(0xFF263341)
      ..strokeWidth = 1;
    final Paint axes = Paint()
      ..color = const Color(0xFF7F91A6)
      ..strokeWidth = 1.5;
    final Paint camera = Paint()
      ..color = const Color(0xFFFFB74D)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Paint border = Paint()
      ..color = const Color(0xFF526577)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRect(viewport, background);
    canvas.save();
    canvas.translate(
      size.width / 2 + value.translation.dx,
      size.height / 2 + value.translation.dy,
    );
    canvas.scale(value.scale);

    const double extent = 2400;
    const double spacing = 40;
    for (double coordinate = -extent; coordinate <= extent; coordinate += spacing) {
      canvas.drawLine(
        Offset(coordinate, -extent),
        Offset(coordinate, extent),
        grid,
      );
      canvas.drawLine(
        Offset(-extent, coordinate),
        Offset(extent, coordinate),
        grid,
      );
    }
    canvas.drawLine(const Offset(-extent, 0), const Offset(extent, 0), axes);
    canvas.drawLine(const Offset(0, -extent), const Offset(0, extent), axes);
    canvas.drawRect(
      const Rect.fromCenter(center: Offset.zero, width: 360, height: 240),
      camera,
    );
    canvas.restore();
    canvas.drawRect(viewport.deflate(1), border);
  }

  @override
  bool shouldRepaint(_PointerLabCanvasPainter oldDelegate) => false;
}
