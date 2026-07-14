# PDF Input Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a temporary Windows-first diagnostics startup experience that isolates stock `pdfrx`, records the pointer-to-viewer coordinate pipeline, and provides a PDF-free trackpad canvas for identifying the zoom-anchor defect.

**Architecture:** Keep diagnostics in `lib/src/features/reader_diagnostics/` and route to them with the existing `Navigator`. A pure immutable event model feeds a bounded in-memory recorder, which mirrors privacy-safe JSON records to the existing `clarixLog` logger. Stock and instrumented viewers share only file-picking and minimal shell widgets; diagnostics never write to the `PdfViewerController` camera.

**Tech Stack:** Flutter 3.44, Dart 3.12, `pdfrx` 2.4.7, `file_picker` 11.0.2, `logger` 2.7.0, Flutter `Navigator`, Flutter test.

## Global Constraints

- Preserve all existing workspace and Flutter Gemma migration changes.
- Do not add a router, state-management dependency, or logging dependency.
- Use the existing `clarixLog` from `lib/src/core/clarix_logger.dart` as the structured log sink.
- Never log PDF paths, titles, document text, model information, or document-derived content.
- Keep the stock viewer genuinely stock: default `PdfViewerParams`, no Clarix interaction delegate, matrix normalization, custom scrollbars, persistence, or diagnostics recorder.
- Diagnostic handlers may observe `PdfViewerController` but must never set `value`, invoke zoom/pan methods, or forward pointer signals.
- Bound the recorder to 500 records, hover sampling to 20 records per second, and controller snapshots to one per rendered frame.
- The agent must not run Flutter or Dart commands. At each test gate, ask the user to run the exact command and provide its output.
- Do not change the normal workspace implementation; only expose it as a destination from the temporary hub.

---

## File Map

- `lib/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart`: privacy-safe immutable event and viewer-snapshot value types.
- `lib/src/features/reader_diagnostics/domain/reader_diagnostic_math.dart`: finite-coordinate checks, matrix snapshots, and affine anchor calculations.
- `lib/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart`: bounded event recording, sampling, pause/clear, JSON export, and `clarixLog` emission.
- `lib/src/features/reader_diagnostics/application/diagnostic_pdf_picker.dart`: injectable one-file PDF picker with cancellation represented as `null`.
- `lib/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart`: four-destination temporary home screen.
- `lib/src/features/reader_diagnostics/presentation/diagnostic_viewer_chrome.dart`: minimal reusable Back/Open/status overlay and PDF empty/error states.
- `lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart`: unmodified `pdfrx` control case.
- `lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart`: observation-only viewer, crosshairs, and event panel.
- `lib/src/features/reader_diagnostics/presentation/pointer_trackpad_lab_screen.dart`: PDF-free pointer/focal diagnostic canvas.
- `lib/src/features/reader_diagnostics/presentation/widgets/diagnostic_crosshair.dart`: isolated cursor/focal overlay painter.
- `lib/src/features/reader_diagnostics/presentation/widgets/diagnostics_event_panel.dart`: pause, clear, copy, collapse, and recent-event UI.
- `lib/src/app.dart`: switch temporary home from `WorkspaceScreen` to `ReaderDiagnosticsHub`.
- `test/reader_diagnostics/reader_diagnostic_event_test.dart`: serialization, privacy, finite values, and affine math.
- `test/reader_diagnostics/reader_diagnostics_recorder_test.dart`: capacity, ordering, sampling, pause, clear, and logger-safe output.
- `test/reader_diagnostics/reader_diagnostics_hub_test.dart`: destinations and navigation.
- `test/reader_diagnostics/diagnostic_viewer_screens_test.dart`: picker cancellation, controls, independent crosshairs, and event-panel behavior.

---

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

---

### Task 2: Shared PDF Picker, Chrome, and Stock pdfrx Control

**Files:**
- Create: `lib/src/features/reader_diagnostics/application/diagnostic_pdf_picker.dart`
- Create: `lib/src/features/reader_diagnostics/presentation/diagnostic_viewer_chrome.dart`
- Create: `lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart`
- Create: `test/reader_diagnostics/diagnostic_viewer_screens_test.dart`

**Interfaces:**
- Produces: `DiagnosticPdfPicker`, `pickDiagnosticPdf()`, `DiagnosticViewerChrome`, and `StockPdfrxScreen`.
- Consumes: `FilePicker.platform.pickFiles()` and stock `PdfViewer.file`.

- [ ] **Step 1: Write failing cancellation and stock-screen tests**

```dart
testWidgets('stock viewer stays empty when picking is cancelled', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: StockPdfrxScreen(pickPdf: () async => null),
  ));
  await tester.tap(find.byKey(const Key('stock-open-pdf')));
  await tester.pump();
  expect(find.text('Open a PDF to test stock pdfrx input behavior.'), findsOneWidget);
  expect(find.byType(PdfViewer), findsNothing);
});

testWidgets('stock screen exposes only minimal control chrome', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: StockPdfrxScreen(pickPdf: () async => null),
  ));
  expect(find.byKey(const Key('diagnostic-back')), findsOneWidget);
  expect(find.byKey(const Key('stock-open-pdf')), findsOneWidget);
  expect(find.byKey(const Key('diagnostics-event-panel')), findsNothing);
});
```

- [ ] **Step 2: Ask the user to verify Task 2 tests fail**

Ask the user to run:

```text
flutter test test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: compilation fails because `StockPdfrxScreen` does not exist.

- [ ] **Step 3: Implement the injectable PDF picker**

```dart
typedef DiagnosticPdfPicker = Future<String?> Function();

Future<String?> pickDiagnosticPdf() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
    allowMultiple: false,
  );
  return result?.files.single.path;
}
```

- [ ] **Step 4: Implement minimal viewer chrome and stock viewer**

`DiagnosticViewerChrome` must use a `Stack` and contain only Back, Open PDF, status text, and an optional trailing widget. `StockPdfrxScreen` must use:

```dart
PdfViewer.file(
  path,
  key: ValueKey<String>(path),
  controller: _controller,
  params: const PdfViewerParams(),
)
```

The screen may add a controller listener solely to update a small `ValueNotifier<DiagnosticViewerStatus>` containing current page and zoom. It must dispose the controller listener and status notifier. It must not wrap the viewer in `Listener`, `GestureDetector`, `InteractiveViewer`, or `PointerSignalResolver`.

- [ ] **Step 5: Ask the user to verify Task 2 tests pass**

Ask the user to run:

```text
flutter test test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: cancellation and minimal-control tests pass.

- [ ] **Step 6: Commit Task 2**

```text
git add lib/src/features/reader_diagnostics/application/diagnostic_pdf_picker.dart lib/src/features/reader_diagnostics/presentation/diagnostic_viewer_chrome.dart lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
git commit -m "feat: add stock pdfrx diagnostic control"
```

---

### Task 3: Instrumented pdfrx Viewer and Event Panel

**Files:**
- Create: `lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart`
- Create: `lib/src/features/reader_diagnostics/presentation/widgets/diagnostic_crosshair.dart`
- Create: `lib/src/features/reader_diagnostics/presentation/widgets/diagnostics_event_panel.dart`
- Modify: `test/reader_diagnostics/diagnostic_viewer_screens_test.dart`

**Interfaces:**
- Produces: `InstrumentedPdfrxScreen`, `DiagnosticCrosshairOverlay`, and `DiagnosticsEventPanel`.
- Consumes: `ReaderDiagnosticsRecorder`, `PdfViewerController.globalToLocal`, `localToDocument`, `value`, `visibleRect`, `viewSize`, `documentSize`, and `pageNumber`.

- [ ] **Step 1: Add failing event-panel and crosshair tests**

```dart
testWidgets('event panel pauses clears collapses and copies JSON', (tester) async {
  final recorder = ReaderDiagnosticsRecorder(logSink: (_) {});
  recorder.record(source: 'test', type: ReaderDiagnosticEventType.scaleStart);
  var copied = '';
  await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: DiagnosticsEventPanel(
      recorder: recorder,
      copyText: (value) async => copied = value,
    ),
  )));
  await tester.tap(find.byKey(const Key('diagnostics-pause')));
  expect(recorder.paused.value, isTrue);
  await tester.tap(find.byKey(const Key('diagnostics-copy')));
  expect(copied, contains('scaleStart'));
  await tester.tap(find.byKey(const Key('diagnostics-clear')));
  expect(recorder.events.value, isEmpty);
  await tester.tap(find.byKey(const Key('diagnostics-collapse')));
  expect(find.byKey(const Key('diagnostics-event-list')), findsNothing);
});

testWidgets('cursor and focal crosshairs are independently positioned', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox(
    width: 400,
    height: 300,
    child: DiagnosticCrosshairOverlay(
      cursor: Offset(70, 80),
      focal: Offset(250, 190),
    ),
  )));
  expect(find.byKey(const Key('cursor-crosshair')), findsOneWidget);
  expect(find.byKey(const Key('focal-crosshair')), findsOneWidget);
});
```

- [ ] **Step 2: Ask the user to verify the new widget tests fail**

Ask the user to run:

```text
flutter test test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: compilation fails because the panel and crosshair widgets do not exist.

- [ ] **Step 3: Implement crosshair overlay and event panel**

Paint cursor in cyan and focal point in amber. Give each crosshair a keyed `Positioned` child for widget tests. Keep the overlay inside `IgnorePointer`.

`DiagnosticsEventPanel` must:

```dart
Future<void> _copy() async {
  try {
    await widget.copyText(widget.recorder.exportJson());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic JSON copied.')),
    );
  } catch (error, stackTrace) {
    clarixLog.e('Failed to copy diagnostic JSON', error: error, stackTrace: stackTrace);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not copy diagnostic JSON.')),
    );
  }
}
```

Default `copyText` uses `Clipboard.setData(ClipboardData(text: value))`. The panel displays the newest 100 of the recorder's 500 records to bound widget work.

- [ ] **Step 4: Implement observation-only instrumented viewer**

Use a screen-level `MouseRegion` for cursor position and a `Listener` with `behavior: HitTestBehavior.translucent` only for raw pointer observation. Register `onPointerHover`, `onPointerMove`, `onPointerSignal`, `onPointerPanZoomStart`, `onPointerPanZoomUpdate`, and `onPointerPanZoomEnd`. Record `PointerPanZoomUpdateEvent.position`, `localPosition`, `pan`, `panDelta`, and `scale` without handling, resolving, or forwarding the event. Configure `PdfViewerParams` only with callbacks that observe:

```dart
PdfViewerParams(
  onInteractionStart: _onInteractionStart,
  onInteractionUpdate: _onInteractionUpdate,
  onInteractionEnd: _onInteractionEnd,
  onViewerReady: (document, controller) => _recordViewerReady(),
  errorBannerBuilder: (context, error, stackTrace, documentRef) {
    _recordViewerError(error);
    return PdfErrorWidget(error: error, stackTrace: stackTrace);
  },
)
```

If `PdfErrorWidget` is not publicly exported by `pdfrx`, replace the builder body with a local centered `Text('Unable to open PDF: ${error.runtimeType}')` and do not display `error.toString()` because it can include a path.

Capture the cursor through the `MouseRegion`. For scale callbacks, store `details.localFocalPoint` separately from the tracked cursor. Build snapshots only when `_controller.isReady`:

```dart
ReaderViewerSnapshot? _snapshot() {
  if (!_controller.isReady) return null;
  final matrix = _controller.value;
  return ReaderViewerSnapshot(
    zoom: _controller.currentZoom,
    translation: ReaderDiagnosticPoint.fromOffset(matrixTranslation(matrix)),
    viewportSize: _controller.viewSize,
    documentSize: _controller.documentSize,
    visibleRect: _controller.visibleRect,
    pageNumber: _controller.pageNumber,
  );
}
```

Convert coordinates without fallback substitution:

```dart
final viewerLocal = _controller.isReady
    ? _controller.globalToLocal(globalPosition)
    : null;
final document = viewerLocal != null && _controller.isReady
    ? _controller.localToDocument(viewerLocal)
    : null;
```

Coalesce controller changes by guarding one `SchedulerBinding.instance.addPostFrameCallback` at a time. Retain `_lastViewerSnapshot`; each frame records it as `before` and the new snapshot as `after`, then replaces `_lastViewerSnapshot`. Compute boundary proximity without clamping coordinates:

```dart
bool _isNearBoundary(ReaderViewerSnapshot snapshot) {
  const tolerance = 1.0;
  final visible = snapshot.visibleRect;
  final document = snapshot.documentSize;
  return visible.left <= tolerance ||
      visible.top <= tolerance ||
      visible.right >= document.width - tolerance ||
      visible.bottom >= document.height - tolerance;
}
```

Include `nearBoundary=${_isNearBoundary(after)}` in the non-sensitive event note. Update only `ValueNotifier` objects for status and crosshairs.

- [ ] **Step 5: Ask the user to verify Task 3 tests pass**

Ask the user to run:

```text
flutter test test/reader_diagnostics/reader_diagnostics_recorder_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: recorder, event panel, crosshair, and viewer empty-state tests pass.

- [ ] **Step 6: Commit Task 3**

```text
git add lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart lib/src/features/reader_diagnostics/presentation/widgets test/reader_diagnostics/diagnostic_viewer_screens_test.dart
git commit -m "feat: instrument pdfrx pointer and camera events"
```

---

### Task 4: PDF-Free Pointer and Trackpad Canvas Lab

**Files:**
- Create: `lib/src/features/reader_diagnostics/presentation/pointer_trackpad_lab_screen.dart`
- Modify: `test/reader_diagnostics/diagnostic_viewer_screens_test.dart`

**Interfaces:**
- Produces: `PointerTrackpadLabScreen` and `PointerLabState`.
- Consumes: `ReaderDiagnosticsRecorder`, `anchoredTranslation`, and `DiagnosticCrosshairOverlay`.

- [ ] **Step 1: Add failing canvas-lab tests**

```dart
testWidgets('pointer lab renders four quadrants and separate markers', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: PointerTrackpadLabScreen()));
  expect(find.text('Q1'), findsOneWidget);
  expect(find.text('Q2'), findsOneWidget);
  expect(find.text('Q3'), findsOneWidget);
  expect(find.text('Q4'), findsOneWidget);
  expect(find.byKey(const Key('pointer-lab-canvas')), findsOneWidget);
});

testWidgets('hover moves cursor without moving focal marker', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: PointerTrackpadLabScreen()));
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(80, 90));
  await gesture.moveTo(const Offset(140, 150));
  await tester.pump();
  final cursor = tester.widget<Positioned>(find.byKey(const Key('cursor-crosshair')));
  final focal = tester.widget<Positioned>(find.byKey(const Key('focal-crosshair')));
  expect(cursor.left, isNot(focal.left));
  await gesture.removePointer();
});
```

- [ ] **Step 2: Ask the user to verify the canvas tests fail**

Ask the user to run:

```text
flutter test test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: compilation fails because `PointerTrackpadLabScreen` does not exist.

- [ ] **Step 3: Implement pointer state and affine camera**

```dart
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
}
```

On hover/move, update only `cursor`. On `ScaleStartDetails`, update only `focal` from `localFocalPoint` and set `_lastGestureScale = 1`. On each `ScaleUpdateDetails`, use the scale ratio since the previous callback so cumulative Flutter scale values are not compounded:

```dart
final scaleRatio = details.scale / _lastGestureScale;
final oldScale = state.scale;
final newScale = (oldScale * scaleRatio).clamp(0.25, 8.0);
final anchored = anchoredTranslation(
  anchor: details.localFocalPoint,
  oldTranslation: state.translation,
  oldScale: oldScale,
  newScale: newScale,
);
_lastGestureScale = details.scale;
state = state.copyWith(
  focal: details.localFocalPoint,
  scale: newScale,
  translation: anchored + details.focalPointDelta,
  pan: details.focalPointDelta,
);
```

Reset `_lastGestureScale` to `1` on interaction end. Record every scale interaction through `ReaderDiagnosticsRecorder`; sample hover through the recorder's existing policy.

- [ ] **Step 4: Implement the lab canvas and readout**

Use a `CustomPainter` for the grid, center axes, viewport border, and simulated camera rectangle. Overlay Q1-Q4 labels and `DiagnosticCrosshairOverlay`. Show exact global/local cursor, focal, scale, translation, pan, and device kind in a compact top-right card. Wrap only the readout/crosshairs with `ValueListenableBuilder<PointerLabState>` so the outer screen does not rebuild on every event.

- [ ] **Step 5: Ask the user to verify Task 4 tests pass**

Ask the user to run:

```text
flutter test test/reader_diagnostics/reader_diagnostic_event_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: affine and canvas behavior tests pass.

- [ ] **Step 6: Commit Task 4**

```text
git add lib/src/features/reader_diagnostics/presentation/pointer_trackpad_lab_screen.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
git commit -m "feat: add trackpad pointer diagnostics lab"
```

---

### Task 5: Diagnostics Hub and Temporary Startup

**Files:**
- Create: `lib/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart`
- Modify: `lib/src/app.dart`
- Create: `test/reader_diagnostics/reader_diagnostics_hub_test.dart`

**Interfaces:**
- Produces: `ReaderDiagnosticsHub` as the temporary `ClarixApp.home`.
- Consumes: `StockPdfrxScreen`, `InstrumentedPdfrxScreen`, `PointerTrackpadLabScreen`, and existing `WorkspaceScreen`.

- [ ] **Step 1: Write failing hub destination tests**

```dart
testWidgets('hub exposes all four diagnostic destinations', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: ReaderDiagnosticsHub()));
  expect(find.byKey(const Key('open-stock-pdfrx')), findsOneWidget);
  expect(find.byKey(const Key('open-instrumented-pdfrx')), findsOneWidget);
  expect(find.byKey(const Key('open-pointer-lab')), findsOneWidget);
  expect(find.byKey(const Key('open-workspace')), findsOneWidget);
});

testWidgets('hub opens stock viewer and returns', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: ReaderDiagnosticsHub()));
  await tester.tap(find.byKey(const Key('open-stock-pdfrx')));
  await tester.pumpAndSettle();
  expect(find.byType(StockPdfrxScreen), findsOneWidget);
  await tester.tap(find.byKey(const Key('diagnostic-back')));
  await tester.pumpAndSettle();
  expect(find.byType(ReaderDiagnosticsHub), findsOneWidget);
});

testWidgets('hub opens the injected workspace destination and returns', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: ReaderDiagnosticsHub(
      workspaceBuilder: (_) => const Scaffold(body: Text('Workspace test double')),
    ),
  ));
  await tester.tap(find.byKey(const Key('open-workspace')));
  await tester.pumpAndSettle();
  expect(find.text('Workspace test double'), findsOneWidget);
  Navigator.of(tester.element(find.text('Workspace test double'))).pop();
  await tester.pumpAndSettle();
  expect(find.byType(ReaderDiagnosticsHub), findsOneWidget);
});
```

- [ ] **Step 2: Ask the user to verify hub tests fail**

Ask the user to run:

```text
flutter test test/reader_diagnostics/reader_diagnostics_hub_test.dart
```

Expected: compilation fails because `ReaderDiagnosticsHub` does not exist.

- [ ] **Step 3: Implement the diagnostics hub**

Build a responsive dark hub with a concise explanation and four keyed destination cards. Its constructor accepts `WidgetBuilder? workspaceBuilder`; default it at navigation time to `(_) => const WorkspaceScreen()` so widget tests can avoid initializing the production workspace. Push screens using:

```dart
void _open(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}
```

Use `const WorkspaceScreen()` for the normal application destination. Label the stock screen as the control, the instrumented screen as the observation case, and the pointer lab as the Flutter-input isolation case.

- [ ] **Step 4: Change only the temporary startup home**

Replace the workspace import/home in `lib/src/app.dart` with:

```dart
import 'features/reader_diagnostics/presentation/reader_diagnostics_hub.dart';

// ...
home: const _WindowBootstrap(child: ReaderDiagnosticsHub()),
```

Do not alter `_WindowBootstrap`, themes, `ProviderScope`, or window sizing.

- [ ] **Step 5: Ask the user to verify hub tests pass**

Ask the user to run:

```text
flutter test test/reader_diagnostics/reader_diagnostics_hub_test.dart
```

Expected: all hub destination and navigation tests pass.

- [ ] **Step 6: Commit Task 5**

```text
git add lib/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart lib/src/app.dart test/reader_diagnostics/reader_diagnostics_hub_test.dart
git commit -m "feat: start Clarix in reader diagnostics hub"
```

---

### Task 6: Full Verification and Manual Diagnostic Runbook

**Files:**
- Create: `docs/testing/pdf-input-diagnostics-runbook.md`
- Modify: diagnostic source/tests only if user-provided compiler or test output identifies defects.

**Interfaces:**
- Produces: a repeatable side-by-side diagnostic procedure and a clean final verification report.
- Consumes: all prior tasks.

- [ ] **Step 1: Write the manual runbook**

The runbook must require the same PDF and these locations in both viewers:

```text
1. Center of the visible page at fit width.
2. 20 px inside the page's top-left corner.
3. 20 px inside the page's top-right corner.
4. 20 px inside the page's bottom-left corner.
5. 20 px inside the page's bottom-right corner.
```

For each location, record ten zoom-in and ten zoom-out gestures across the fit-width threshold. Copy instrumented JSON after each location. Then repeat equivalent gestures in the pointer lab and note whether the amber focal marker jumps to a viewport corner while the cyan cursor remains stable.

- [ ] **Step 2: Ask the user to run formatting and static analysis**

Ask the user to run and paste the complete output:

```text
dart format --output=none --set-exit-if-changed lib/src/features/reader_diagnostics test/reader_diagnostics lib/src/app.dart
flutter analyze
```

Expected: formatter reports no changes required and analyzer reports no issues. If formatting is required, ask the user to run `dart format` on the listed paths, then inspect the resulting diff before continuing.

- [ ] **Step 3: Ask the user to run the focused and full tests**

Ask the user to run and paste the complete output:

```text
flutter test test/reader_diagnostics
flutter test
```

Expected: all focused diagnostics tests and the complete existing test suite pass.

- [ ] **Step 4: Ask the user to build Windows**

Ask the user to run and paste the complete output:

```text
flutter build windows
```

Expected: Windows build succeeds without native-asset or `pdfrx` compilation errors.

- [ ] **Step 5: Perform source-level privacy and architecture checks**

Run non-Flutter source checks:

```text
rg -n "clarixLog|ReaderDiagnosticsRecorder" lib/src/features/reader_diagnostics
rg -n "filePath|documentText|modelId|PdfViewerController.*=|\.value\s*=|zoomOnLocalPosition|handlePointerSignalEvent" lib/src/features/reader_diagnostics
```

Expected: logger calls contain event JSON or local diagnostic errors only; no sensitive fields or controller writes appear. The stock screen contains neither recorder nor pointer handlers.

- [ ] **Step 6: Commit the runbook and any verified corrections**

```text
git add docs/testing/pdf-input-diagnostics-runbook.md lib/src/features/reader_diagnostics test/reader_diagnostics lib/src/app.dart
git commit -m "docs: add PDF input diagnostics runbook"
```

---

## Completion Gate

- Startup displays the diagnostics hub and normal Clarix remains one click away.
- Stock viewer opens a local PDF with default `PdfViewerParams` and no diagnostic handlers.
- Instrumented viewer logs raw pointer, focal, converted viewer/document coordinates, scale/pan, and before/after camera state through `clarixLog`.
- Cursor and focal crosshairs remain visually independent.
- Pointer lab works without loading `pdfrx` or a PDF.
- Recorder memory and UI work remain bounded.
- Exported JSON contains no path, title, text, model, or document content.
- Diagnostics never modify the `PdfViewerController` camera.
- User-provided format, analysis, test, and Windows build outputs are clean.
- Manual comparison can distinguish Flutter input, stock `pdfrx`, and Clarix workspace behavior.
