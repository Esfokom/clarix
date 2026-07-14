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
    'zoom': zoom,
    'translation': translation.toJson(),
    'viewport': <String, double>{
      'width': viewportSize.width,
      'height': viewportSize.height,
    },
    'document': <String, double>{
      'width': documentSize.width,
      'height': documentSize.height,
    },
    'visibleRect': <String, double>{
      'left': visibleRect.left,
      'top': visibleRect.top,
      'right': visibleRect.right,
      'bottom': visibleRect.bottom,
    },
    'pageNumber': pageNumber,
  };
}

@immutable
class ReaderDiagnosticEvent {
  const ReaderDiagnosticEvent({
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
    this.note,
  });

  final int sequence;
  final int elapsedMicros;
  final String source;
  final ReaderDiagnosticEventType type;
  final String? deviceKind;
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
    'source': source,
    'type': type.name,
    'deviceKind': deviceKind,
    'global': global?.toJson(),
    'listenerLocal': listenerLocal?.toJson(),
    'viewerLocal': viewerLocal?.toJson(),
    'document': document?.toJson(),
    'cursor': cursor?.toJson(),
    'focal': focal?.toJson(),
    'scale': scale,
    'pan': pan?.toJson(),
    'before': before?.toJson(),
    'after': after?.toJson(),
    'note': note,
  };
}
