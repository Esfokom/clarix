import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ReaderDiagnosticEventType {
  pointerHover,
  pointerMove,
  pointerSignal,
  panZoomStart,
  panZoomUpdate,
  panZoomEnd,
  scaleStart,
  scaleUpdate,
  scaleEnd,
  controllerSnapshot,
  viewerReady,
  viewerError,
}

enum ReaderDiagnosticSource {
  instrumentedPdfrx,
  pointerListener,
  controllerListener,
  unknown;

  static ReaderDiagnosticSource fromRaw(String value) {
    switch (value) {
      case 'instrumented_pdfrx':
        return ReaderDiagnosticSource.instrumentedPdfrx;
      case 'pointer_listener':
        return ReaderDiagnosticSource.pointerListener;
      case 'controller_listener':
        return ReaderDiagnosticSource.controllerListener;
      default:
        return ReaderDiagnosticSource.unknown;
    }
  }

  String get jsonValue {
    switch (this) {
      case ReaderDiagnosticSource.instrumentedPdfrx:
        return 'instrumented_pdfrx';
      case ReaderDiagnosticSource.pointerListener:
        return 'pointer_listener';
      case ReaderDiagnosticSource.controllerListener:
        return 'controller_listener';
      case ReaderDiagnosticSource.unknown:
        return 'unknown';
    }
  }
}

enum ReaderDiagnosticDeviceKind {
  unknown,
  mouse,
  touch,
  stylus,
  invertedStylus,
  trackpad;

  static ReaderDiagnosticDeviceKind fromRaw(String value) {
    switch (value) {
      case 'mouse':
        return ReaderDiagnosticDeviceKind.mouse;
      case 'touch':
        return ReaderDiagnosticDeviceKind.touch;
      case 'stylus':
        return ReaderDiagnosticDeviceKind.stylus;
      case 'invertedStylus':
      case 'inverted_stylus':
        return ReaderDiagnosticDeviceKind.invertedStylus;
      case 'trackpad':
        return ReaderDiagnosticDeviceKind.trackpad;
      default:
        return ReaderDiagnosticDeviceKind.unknown;
    }
  }

  String get jsonValue {
    switch (this) {
      case ReaderDiagnosticDeviceKind.unknown:
        return 'unknown';
      case ReaderDiagnosticDeviceKind.mouse:
        return 'mouse';
      case ReaderDiagnosticDeviceKind.touch:
        return 'touch';
      case ReaderDiagnosticDeviceKind.stylus:
        return 'stylus';
      case ReaderDiagnosticDeviceKind.invertedStylus:
        return 'invertedStylus';
      case ReaderDiagnosticDeviceKind.trackpad:
        return 'trackpad';
    }
  }
}

const String readerDiagnosticNearBoundaryNote = 'near_boundary';
const String _readerDiagnosticScaleUpdateNote = 'scale_update';

String? sanitizeReaderDiagnosticNote(String? value) {
  switch (value) {
    case readerDiagnosticNearBoundaryNote:
    case _readerDiagnosticScaleUpdateNote:
      return value;
    default:
      return null;
  }
}

double? _finiteDouble(double? value) =>
    value != null && value.isFinite ? value : null;

@immutable
class ReaderDiagnosticPoint {
  const ReaderDiagnosticPoint(this.x, this.y);

  factory ReaderDiagnosticPoint.fromOffset(Offset value) =>
      ReaderDiagnosticPoint(value.dx, value.dy);

  final double x;
  final double y;

  Offset get offset => Offset(x, y);

  bool get isFinite => x.isFinite && y.isFinite;

  Map<String, double>? toJson() =>
      isFinite ? <String, double>{'x': x, 'y': y} : null;
}

@immutable
class ReaderViewerSnapshot {
  const ReaderViewerSnapshot({
    required this.zoom,
    required this.translation,
    required this.viewportSize,
    required this.documentSize,
    required this.visibleRect,
    required this.pageNumber,
  });

  final double zoom;
  final ReaderDiagnosticPoint translation;
  final Size viewportSize;
  final Size documentSize;
  final Rect visibleRect;
  final int? pageNumber;

  Map<String, Object?> toJson() => <String, Object?>{
    'zoom': _finiteDouble(zoom),
    'translation': translation.toJson(),
    'viewport': <String, Object?>{
      'width': _finiteDouble(viewportSize.width),
      'height': _finiteDouble(viewportSize.height),
    },
    'document': <String, Object?>{
      'width': _finiteDouble(documentSize.width),
      'height': _finiteDouble(documentSize.height),
    },
    'visibleRect': <String, Object?>{
      'left': _finiteDouble(visibleRect.left),
      'top': _finiteDouble(visibleRect.top),
      'right': _finiteDouble(visibleRect.right),
      'bottom': _finiteDouble(visibleRect.bottom),
    },
    'pageNumber': pageNumber,
  };
}

@immutable
class ReaderDiagnosticEvent {
  ReaderDiagnosticEvent({
    required this.sequence,
    required this.elapsedMicros,
    required this.source,
    required this.type,
    this.deviceKind,
    this.global,
    this.listenerLocal,
    this.viewerLocal,
    this.document,
    this.cursor,
    this.focal,
    this.scale,
    this.pan,
    this.before,
    this.after,
    String? note,
  }) : note = sanitizeReaderDiagnosticNote(note);

  final int sequence;
  final int elapsedMicros;
  final ReaderDiagnosticSource source;
  final ReaderDiagnosticEventType type;
  final ReaderDiagnosticDeviceKind? deviceKind;
  final ReaderDiagnosticPoint? global;
  final ReaderDiagnosticPoint? listenerLocal;
  final ReaderDiagnosticPoint? viewerLocal;
  final ReaderDiagnosticPoint? document;
  final ReaderDiagnosticPoint? cursor;
  final ReaderDiagnosticPoint? focal;
  final double? scale;
  final ReaderDiagnosticPoint? pan;
  final ReaderViewerSnapshot? before;
  final ReaderViewerSnapshot? after;
  final String? note;

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'elapsedMicros': elapsedMicros,
    'source': source.jsonValue,
    'type': type.name,
    'deviceKind': deviceKind?.jsonValue,
    'global': global?.toJson(),
    'listenerLocal': listenerLocal?.toJson(),
    'viewerLocal': viewerLocal?.toJson(),
    'document': document?.toJson(),
    'cursor': cursor?.toJson(),
    'focal': focal?.toJson(),
    'scale': _finiteDouble(scale),
    'pan': pan?.toJson(),
    'before': before?.toJson(),
    'after': after?.toJson(),
    'note': note,
  };
}