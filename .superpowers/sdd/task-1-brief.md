### Task 1: Diagnostic Event Model, Math, and Recorder

**Files:**
- Create: `lib/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart`
- Create: `lib/src/features/reader_diagnostics/domain/reader_diagnostic_math.dart`
- Create: `lib/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart`
- Create: `test/reader_diagnostics/reader_diagnostic_event_test.dart`
- Create: `test/reader_diagnostics/reader_diagnostics_recorder_test.dart`

**Interfaces:**
- Produces: `ReaderDiagnosticPoint`, `ReaderViewerSnapshot`, `ReaderDiagnosticEvent`, `ReaderDiagnosticEventType`, `ReaderDiagnosticsRecorder`, `isFiniteOffset`, `matrixTranslation`, and `anchoredTranslation`.
- Consumes: `clarixLog` from `lib/src/core/clarix_logger.dart`.

- [ ] **Step 1: Write failing event-model and math tests**

```dart
test('event JSON contains coordinates but no sensitive document fields', () {
  final event = ReaderDiagnosticEvent(
    sequence: 7,
    elapsedMicros: 1200,
    source: 'instrumented_pdfrx',
    type: ReaderDiagnosticEventType.scaleUpdate,
    deviceKind: 'trackpad',
    global: const ReaderDiagnosticPoint(410, 260),
    viewerLocal: const ReaderDiagnosticPoint(390, 220),
    note: 'scale update',
  );

  final json = event.toJson();
  expect(json['sequence'], 7);
  expect(json['global'], <String, double>{'x': 410, 'y': 260});
  expect(json.keys, isNot(contains('path')));
  expect(json.keys, isNot(contains('title')));
  expect(json.keys, isNot(contains('text')));
  expect(json.keys, isNot(contains('model')));
});

test('affine camera keeps the anchor invariant', () {
  const anchor = Offset(173, 91);
  const oldScale = 1.0;
  const newScale = 1.75;
  const oldTranslation = Offset(22, -14);
  final documentPoint = (anchor - oldTranslation) / oldScale;
  final next = anchoredTranslation(
    anchor: anchor,
    oldTranslation: oldTranslation,
    oldScale: oldScale,
    newScale: newScale,
  );

  expect(documentPoint * newScale + next, anchor);
});
```

- [ ] **Step 2: Ask the user to verify the focused tests fail**

Ask the user to run:

```text
flutter test test/reader_diagnostics/reader_diagnostic_event_test.dart
```

Expected: compilation fails because the diagnostic types do not exist.

- [ ] **Step 3: Implement immutable privacy-safe event types and affine helpers**

```dart
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
    'viewport': <String, double>{'width': viewportSize.width, 'height': viewportSize.height},
    'document': <String, double>{'width': documentSize.width, 'height': documentSize.height},
    'visibleRect': <String, double>{
      'left': visibleRect.left,
      'top': visibleRect.top,
      'right': visibleRect.right,
      'bottom': visibleRect.bottom,
    },
    'pageNumber': pageNumber,
  };
}
```

Implement `ReaderDiagnosticEvent.toJson()` with only the explicitly declared diagnostic fields. Implement:

```dart
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
  final documentPoint = (anchor - oldTranslation) / oldScale;
  return anchor - documentPoint * newScale;
}
```

- [ ] **Step 4: Write failing recorder tests**

```dart
test('recorder evicts oldest records at capacity', () {
  final recorder = ReaderDiagnosticsRecorder(capacity: 3, logSink: (_) {});
  for (var index = 0; index < 5; index++) {
    recorder.record(source: 'lab', type: ReaderDiagnosticEventType.pointerMove);
  }
  expect(recorder.events.value.map((event) => event.sequence), <int>[3, 4, 5]);
});

test('pause blocks records and clear resets the visible buffer', () {
  final recorder = ReaderDiagnosticsRecorder(logSink: (_) {});
  recorder.paused.value = true;
  recorder.record(source: 'lab', type: ReaderDiagnosticEventType.scaleStart);
  expect(recorder.events.value, isEmpty);
  recorder.paused.value = false;
  recorder.record(source: 'lab', type: ReaderDiagnosticEventType.scaleStart);
  recorder.clear();
  expect(recorder.events.value, isEmpty);
});

test('hover is sampled but scale updates are retained', () {
  var micros = 0;
  final recorder = ReaderDiagnosticsRecorder(
    nowMicros: () => micros,
    logSink: (_) {},
  );
  recorder.record(source: 'lab', type: ReaderDiagnosticEventType.pointerHover);
  micros = 10 * 1000;
  recorder.record(source: 'lab', type: ReaderDiagnosticEventType.pointerHover);
  recorder.record(source: 'lab', type: ReaderDiagnosticEventType.scaleUpdate);
  expect(recorder.events.value.length, 2);
});
```

- [ ] **Step 5: Implement recorder with logger-package output**

```dart
typedef ReaderDiagnosticLogSink = void Function(String jsonLine);

class ReaderDiagnosticsRecorder {
  ReaderDiagnosticsRecorder({
    this.capacity = 500,
    int Function()? nowMicros,
    ReaderDiagnosticLogSink? logSink,
  })  : _nowMicros = nowMicros ?? _stopwatchMicros,
        _logSink = logSink ?? _defaultLogSink {
    _originMicros = _nowMicros();
  }

  final int capacity;
  final ValueNotifier<List<ReaderDiagnosticEvent>> events =
      ValueNotifier<List<ReaderDiagnosticEvent>>(<ReaderDiagnosticEvent>[]);
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  final int Function() _nowMicros;
  final ReaderDiagnosticLogSink _logSink;
  late final int _originMicros;
  int _sequence = 0;
  int? _lastHoverMicros;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _stopwatchMicros() => _clock.elapsedMicroseconds;
  static void _defaultLogSink(String value) =>
      clarixLog.t('reader_diagnostics $value');

  void record({
    required String source,
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
    if (paused.value) return;
    final now = _nowMicros();
    if (type == ReaderDiagnosticEventType.pointerHover &&
        _lastHoverMicros != null && now - _lastHoverMicros! < 50000) {
      return;
    }
    if (type == ReaderDiagnosticEventType.pointerHover) _lastHoverMicros = now;
    final event = ReaderDiagnosticEvent(
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
    final next = <ReaderDiagnosticEvent>[...events.value, event];
    events.value = next.length <= capacity
        ? List<ReaderDiagnosticEvent>.unmodifiable(next)
        : List<ReaderDiagnosticEvent>.unmodifiable(next.sublist(next.length - capacity));
    _logSink(jsonEncode(event.toJson()));
  }

  String exportJson() => jsonEncode(events.value.map((event) => event.toJson()).toList());
  void clear() => events.value = <ReaderDiagnosticEvent>[];
  void dispose() { events.dispose(); paused.dispose(); }
}
```

- [ ] **Step 6: Ask the user to verify Task 1 tests pass**

Ask the user to run:

```text
flutter test test/reader_diagnostics/reader_diagnostic_event_test.dart test/reader_diagnostics/reader_diagnostics_recorder_test.dart
```

Expected: all diagnostic model and recorder tests pass.

- [ ] **Step 7: Commit Task 1**

```text
git add lib/src/features/reader_diagnostics/domain lib/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart test/reader_diagnostics/reader_diagnostic_event_test.dart test/reader_diagnostics/reader_diagnostics_recorder_test.dart
git commit -m "test: add bounded reader diagnostics recorder"
```
