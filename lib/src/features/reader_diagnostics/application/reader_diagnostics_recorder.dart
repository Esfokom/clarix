import 'dart:convert';

import 'package:clarix/src/core/clarix_logger.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:flutter/foundation.dart';

typedef ReaderDiagnosticLogSink = void Function(String jsonLine);

class ReaderDiagnosticsRecorder {
  ReaderDiagnosticsRecorder({
    int capacity = maxCapacity,
    int Function()? nowMicros,
    ReaderDiagnosticLogSink? logSink,
  })  : capacity = _boundedCapacity(capacity),
        _nowMicros = nowMicros ?? _stopwatchMicros,
        _logSink = logSink ?? _defaultLogSink {
    _originMicros = _nowMicros();
  }

  static const int maxCapacity = 500;
  static final List<ReaderDiagnosticEvent> _emptyEvents =
      List<ReaderDiagnosticEvent>.unmodifiable(<ReaderDiagnosticEvent>[]);

  final int capacity;
  final ValueNotifier<List<ReaderDiagnosticEvent>> events =
      ValueNotifier<List<ReaderDiagnosticEvent>>(_emptyEvents);
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  final int Function() _nowMicros;
  final ReaderDiagnosticLogSink _logSink;
  late final int _originMicros;
  int _sequence = 0;
  int? _lastHoverMicros;

  static final Stopwatch _clock = Stopwatch()..start();

  static int _boundedCapacity(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'capacity', 'must be positive');
    }
    return value > maxCapacity ? maxCapacity : value;
  }

  static int _stopwatchMicros() => _clock.elapsedMicroseconds;

  static void _defaultLogSink(String value) =>
      clarixLog.t('reader_diagnostics $value');

  void record({
    required ReaderDiagnosticSource source,
    required ReaderDiagnosticEventType type,
    String? deviceKind,
    ReaderDiagnosticPoint? global,
    ReaderDiagnosticPoint? listenerLocal,
    ReaderDiagnosticPoint? viewerLocal,
    ReaderDiagnosticPoint? document,
    ReaderDiagnosticPoint? cursor,
    ReaderDiagnosticPoint? focal,
    double? scale,
    ReaderDiagnosticPoint? pan,
    ReaderViewerSnapshot? before,
    ReaderViewerSnapshot? after,
    String? note,
  }) {
    if (paused.value) {
      return;
    }
    final int now = _nowMicros();
    if (type == ReaderDiagnosticEventType.pointerHover &&
        _lastHoverMicros != null &&
        now - _lastHoverMicros! < 50000) {
      return;
    }
    if (type == ReaderDiagnosticEventType.pointerHover) {
      _lastHoverMicros = now;
    }
    final ReaderDiagnosticEvent event = ReaderDiagnosticEvent(
      sequence: ++_sequence,
      elapsedMicros: now - _originMicros,
      source: source,
      type: type,
      deviceKind: deviceKind,
      global: global,
      listenerLocal: listenerLocal,
      viewerLocal: viewerLocal,
      document: document,
      cursor: cursor,
      focal: focal,
      scale: scale,
      pan: pan,
      before: before,
      after: after,
      note: note,
    );
    final List<ReaderDiagnosticEvent> next = <ReaderDiagnosticEvent>[
      ...events.value,
      event,
    ];
    events.value = next.length <= capacity
        ? List<ReaderDiagnosticEvent>.unmodifiable(next)
        : List<ReaderDiagnosticEvent>.unmodifiable(
            next.sublist(next.length - capacity),
          );
    _logSink(jsonEncode(event.toJson()));
  }

  String exportJson() => jsonEncode(
    events.value.map((ReaderDiagnosticEvent event) => event.toJson()).toList(),
  );

  void clear() => events.value = _emptyEvents;

  void dispose() {
    events.dispose();
    paused.dispose();
  }
}