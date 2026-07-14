import 'dart:ui' show Offset, PointerDeviceKind;

import 'package:clarix/src/features/reader_diagnostics/application/diagnostic_pdf_picker.dart';
import 'package:clarix/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_math.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/diagnostic_viewer_chrome.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/widgets/diagnostic_crosshair.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/widgets/diagnostics_event_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';

class InstrumentedPdfrxScreen extends StatefulWidget {
  const InstrumentedPdfrxScreen({
    this.pickPdf = pickDiagnosticPdf,
    this.onBack,
    this.recorder,
    super.key,
  });

  final DiagnosticPdfPicker pickPdf;
  final VoidCallback? onBack;
  final ReaderDiagnosticsRecorder? recorder;

  @override
  State<InstrumentedPdfrxScreen> createState() =>
      _InstrumentedPdfrxScreenState();
}

class _InstrumentedPdfrxScreenState extends State<InstrumentedPdfrxScreen> {
  static const String _emptyStatus =
      'Open a PDF to inspect raw pdfrx input behavior.';

  late final PdfViewerController _controller;
  late final ReaderDiagnosticsRecorder _recorder;
  late final bool _ownsRecorder;
  late final ValueNotifier<String> _status;
  late final ValueNotifier<_CrosshairPositions> _crosshairs;

  String? _path;
  ReaderViewerSnapshot? _lastViewerSnapshot;
  bool _controllerSnapshotScheduled = false;
  Type? _lastViewerErrorType;
  Offset _observedPan = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _recorder = widget.recorder ?? ReaderDiagnosticsRecorder();
    _ownsRecorder = widget.recorder == null;
    _status = ValueNotifier<String>(_emptyStatus);
    _crosshairs = ValueNotifier<_CrosshairPositions>(
      const _CrosshairPositions(),
    );
    _controller.addListener(_scheduleControllerSnapshot);
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleControllerSnapshot);
    _status.dispose();
    _crosshairs.dispose();
    if (_ownsRecorder) {
      _recorder.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? path = _path;
    final Widget pdf = path == null
        ? const SizedBox.expand()
        : PdfViewer.file(
            path,
            key: ValueKey<String>(path),
            controller: _controller,
            params: PdfViewerParams(
              onInteractionStart: _onInteractionStart,
              onInteractionUpdate: _onInteractionUpdate,
              onInteractionEnd: _onInteractionEnd,
              onViewerReady: (PdfDocument document, PdfViewerController value) {
                _recordViewerReady();
              },
              errorBannerBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
                PdfDocumentRef documentRef,
              ) {
                _recordViewerError(error);
                return Center(
                  child: Text(
                    'Unable to open PDF: ${error.runtimeType}',
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          );

    final Widget viewer = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        pdf,
        ValueListenableBuilder<_CrosshairPositions>(
          valueListenable: _crosshairs,
          builder: (
            BuildContext context,
            _CrosshairPositions positions,
            Widget? child,
          ) {
            return DiagnosticCrosshairOverlay(
              cursor: positions.cursor,
              focal: positions.focal,
            );
          },
        ),
      ],
    );

    return MouseRegion(
      onHover: _trackCursor,
      onExit: (_) => _setCursor(null),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _onPointerHover,
        onPointerMove: _onPointerMove,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
        onPointerPanZoomEnd: _onPointerPanZoomEnd,
        child: ValueListenableBuilder<String>(
          valueListenable: _status,
          builder: (BuildContext context, String status, Widget? child) {
            return DiagnosticViewerChrome(
              viewer: viewer,
              status: status,
              onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
              onOpenPdf: _openPdf,
              trailing: DiagnosticsEventPanel(recorder: _recorder),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPdf() async {
    final String? path = await widget.pickPdf();
    if (!mounted || path == null) {
      return;
    }
    _lastViewerSnapshot = null;
    _lastViewerErrorType = null;
    _status.value = _emptyStatus;
    final _CrosshairPositions positions = _crosshairs.value;
    _crosshairs.value = _CrosshairPositions(cursor: positions.cursor);
    setState(() => _path = path);
  }

  void _trackCursor(PointerHoverEvent event) =>
      _setCursor(event.localPosition);

  void _setCursor(Offset? cursor) {
    final _CrosshairPositions current = _crosshairs.value;
    _crosshairs.value = _CrosshairPositions(
      cursor: cursor,
      focal: current.focal,
    );
  }

  void _setFocal(Offset focal) {
    final _CrosshairPositions current = _crosshairs.value;
    _crosshairs.value = _CrosshairPositions(
      cursor: current.cursor,
      focal: focal,
    );
  }

  void _onPointerHover(PointerHoverEvent event) {
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.pointerHover,
      event: event,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
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
    _observedPan = Offset.zero;
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.panZoomStart,
      event: event,
    );
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _observedPan += event.panDelta;
    if (_observedPan != event.pan) {
      _observedPan = event.pan;
    }
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.panZoomUpdate,
      event: event,
      pan: _observedPan,
      panDelta: event.panDelta,
      scale: event.scale,
    );
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _recordPointerEvent(
      type: ReaderDiagnosticEventType.panZoomEnd,
      event: event,
    );
  }

  void _recordPointerEvent({
    required ReaderDiagnosticEventType type,
    required PointerEvent event,
    Offset? pan,
    Offset? panDelta,
    double? scale,
  }) {
    final Offset globalPosition = event.position;
    final Offset? viewerLocal = _controller.isReady
        ? _controller.globalToLocal(globalPosition)
        : null;
    final Offset? document = viewerLocal != null && _controller.isReady
        ? _controller.localToDocument(viewerLocal)
        : null;
    final _CrosshairPositions positions = _crosshairs.value;

    _recorder.record(
      source: ReaderDiagnosticSource.pointerListener,
      type: type,
      deviceKind: _diagnosticDeviceKind(event.kind),
      global: ReaderDiagnosticPoint.fromOffset(globalPosition),
      listenerLocal: ReaderDiagnosticPoint.fromOffset(event.localPosition),
      viewerLocal: viewerLocal == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(viewerLocal),
      document: document == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(document),
      cursor: positions.cursor == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(positions.cursor!),
      focal: positions.focal == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(positions.focal!),
      scale: scale,
      pan: pan == null ? null : ReaderDiagnosticPoint.fromOffset(pan),
      panDelta: panDelta == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(panDelta),
    );
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _setFocal(details.localFocalPoint);
    _recordScaleEvent(
      type: ReaderDiagnosticEventType.scaleStart,
      globalPosition: details.focalPoint,
      localFocalPoint: details.localFocalPoint,
    );
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    _setFocal(details.localFocalPoint);
    _recordScaleEvent(
      type: ReaderDiagnosticEventType.scaleUpdate,
      globalPosition: details.focalPoint,
      localFocalPoint: details.localFocalPoint,
      scale: details.scale,
      pan: details.focalPointDelta,
    );
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    _recordScaleEvent(type: ReaderDiagnosticEventType.scaleEnd);
  }

  void _recordScaleEvent({
    required ReaderDiagnosticEventType type,
    Offset? globalPosition,
    Offset? localFocalPoint,
    double? scale,
    Offset? pan,
  }) {
    final Offset? viewerLocal = globalPosition != null && _controller.isReady
        ? _controller.globalToLocal(globalPosition)
        : null;
    final Offset? document = viewerLocal != null && _controller.isReady
        ? _controller.localToDocument(viewerLocal)
        : null;
    final _CrosshairPositions positions = _crosshairs.value;

    _recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: type,
      global: globalPosition == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(globalPosition),
      listenerLocal: localFocalPoint == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(localFocalPoint),
      viewerLocal: viewerLocal == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(viewerLocal),
      document: document == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(document),
      cursor: positions.cursor == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(positions.cursor!),
      focal: localFocalPoint == null
          ? null
          : ReaderDiagnosticPoint.fromOffset(localFocalPoint),
      scale: scale,
      pan: pan == null ? null : ReaderDiagnosticPoint.fromOffset(pan),
    );
  }

  void _recordViewerReady() {
    _lastViewerErrorType = null;
    final ReaderViewerSnapshot? after = _snapshot();
    if (after != null) {
      _syncStatus(after);
      _lastViewerSnapshot = after;
    }
    _recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.viewerReady,
      after: after,
    );
  }

  void _recordViewerError(Object error) {
    final Type errorType = error.runtimeType;
    if (_lastViewerErrorType == errorType) {
      return;
    }
    _lastViewerErrorType = errorType;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _status.value = 'Unable to open PDF.';
      _recorder.record(
        source: ReaderDiagnosticSource.instrumentedPdfrx,
        type: ReaderDiagnosticEventType.viewerError,
      );
    });
  }

  void _scheduleControllerSnapshot() {
    if (_controllerSnapshotScheduled) {
      return;
    }
    _controllerSnapshotScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _controllerSnapshotScheduled = false;
      if (!mounted) {
        return;
      }
      final ReaderViewerSnapshot? after = _snapshot();
      if (after == null) {
        return;
      }
      final ReaderViewerSnapshot? before = _lastViewerSnapshot;
      _syncStatus(after);
      _recorder.record(
        source: ReaderDiagnosticSource.controllerListener,
        type: ReaderDiagnosticEventType.controllerSnapshot,
        before: before,
        after: after,
        nearBoundary: _isNearBoundary(after),
      );
      _lastViewerSnapshot = after;
    });
  }

  ReaderViewerSnapshot? _snapshot() {
    if (!_controller.isReady) {
      return null;
    }
    final matrix = _controller.value;
    return ReaderViewerSnapshot(
      zoom: _controller.currentZoom,
      translation: ReaderDiagnosticPoint.fromOffset(
        matrixTranslation(matrix),
      ),
      viewportSize: _controller.viewSize,
      documentSize: _controller.documentSize,
      visibleRect: _controller.visibleRect,
      pageNumber: _controller.pageNumber,
    );
  }

  bool _isNearBoundary(ReaderViewerSnapshot snapshot) {
    const double tolerance = 1;
    final visible = snapshot.visibleRect;
    final document = snapshot.documentSize;
    return visible.left <= tolerance ||
        visible.top <= tolerance ||
        visible.right >= document.width - tolerance ||
        visible.bottom >= document.height - tolerance;
  }

  void _syncStatus(ReaderViewerSnapshot snapshot) {
    final int? page = snapshot.pageNumber;
    _status.value = page == null
        ? 'PDF ready at ${(snapshot.zoom * 100).round()}%'
        : 'Page $page at ${(snapshot.zoom * 100).round()}%';
  }
}

class _CrosshairPositions {
  const _CrosshairPositions({this.cursor, this.focal});

  final Offset? cursor;
  final Offset? focal;
}

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
