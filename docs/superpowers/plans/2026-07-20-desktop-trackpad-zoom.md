# Desktop Trackpad Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace pdfrx's drifting precision-trackpad zoom with a desktop input adapter that keeps the PDF point under the stationary cursor fixed, applies Clarix's zoom sensitivity, preserves ordinary two-finger panning, and restores safe viewer boundaries.

**Architecture:** `ReaderCursorLockedPdfRegion` will own desktop zoom signals while pdfrx retains pan and plain-wheel scrolling. pdfrx scaling will be disabled in every Clarix viewer so a raw event is never applied twice; a small gesture-state object will classify and damp cumulative trackpad scale before calling `PdfViewerController.zoomOnLocalPosition` at the gesture-start cursor.

**Tech Stack:** Flutter 3.44.2, Dart 3.12.2, pdfrx 2.4.7, `flutter_test` synthetic `PointerPanZoom` events.

## Global Constraints

- Clarix is currently desktop-only.
- Precision-trackpad pinch must keep the gesture-start PDF point beneath the stationary cursor.
- Ordinary two-finger movement with cumulative scale within `0.01` of `1.0` must remain available to pdfrx panning.
- Once a pan/zoom sequence becomes a zoom, it remains a zoom until `PointerPanZoomEndEvent`.
- Use `readerPointerZoomSensitivity`, currently `0.65`, for precision-trackpad, `PointerScaleEvent`, and Ctrl+mouse-wheel zoom.
- Plain mouse-wheel input remains pdfrx scrolling.
- Do not modify or vendor pdfrx.
- Do not restore the identity `normalizeMatrix` callback; use pdfrx's normal safe-range behavior.
- Preserve unrelated untracked assets and the existing untracked OpenAI implementation plan.

---

## File Map

- Modify `lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart`: add desktop gesture state and raw pointer routing to the existing shared reader input region; remove identity normalization.
- Modify `lib/src/features/workspace/presentation/widgets/document_workspace.dart`: disable pdfrx's internal scale path and stop passing identity normalization.
- Modify `lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart`: use the shared desktop scale ownership and normal matrix boundaries.
- Modify `lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart`: use the same production input path while retaining observation callbacks.
- Modify `test/phase1_reader_test.dart`: replace disconnected identity-normalizer assertions with gesture-state and raw-event regression coverage.
- Modify `test/reader_diagnostics/diagnostic_viewer_screens_test.dart`: verify the two diagnostic viewers disable pdfrx scaling and leave matrix normalization unset.

---

### Task 1: Define cumulative desktop zoom semantics

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart:1-20`
- Test: `test/phase1_reader_test.dart:1-65`

**Interfaces:**
- Produces: `double dampenReaderPointerScale(double rawScale, {double sensitivity = readerPointerZoomSensitivity})`.
- Produces: `ReaderTrackpadZoomGesture`, with `start`, `update`, `end`, `anchor`, and `isZooming`.
- `ReaderTrackpadZoomGesture.update` returns an absolute target zoom or `null` while the sequence remains a pan.

- [ ] **Step 1: Replace the obsolete normalization test with failing zoom-math tests**

Add these tests near the top of `test/phase1_reader_test.dart` and remove `cursor-locked PDF normalization preserves the affine camera matrix`:

```dart
test('trackpad scale is dampened from the gesture start zoom', () {
  final ReaderTrackpadZoomGesture gesture = ReaderTrackpadZoomGesture();
  gesture.start(startZoom: 2, anchor: const Offset(420, 315));

  final double? first = gesture.update(
    cumulativeScale: 1.5,
    minZoom: 0.25,
    maxZoom: 8,
  );
  final double? second = gesture.update(
    cumulativeScale: 1.75,
    minZoom: 0.25,
    maxZoom: 8,
  );

  expect(first, closeTo(2.65, 0.000001));
  expect(second, closeTo(2.975, 0.000001));
  expect(gesture.anchor, const Offset(420, 315));
});

test('trackpad scale noise remains a pan until zoom is established', () {
  final ReaderTrackpadZoomGesture gesture = ReaderTrackpadZoomGesture();
  gesture.start(startZoom: 2, anchor: const Offset(420, 315));

  expect(
    gesture.update(cumulativeScale: 1.009, minZoom: 0.25, maxZoom: 8),
    isNull,
  );
  expect(gesture.isZooming, isFalse);

  expect(
    gesture.update(cumulativeScale: 1.02, minZoom: 0.25, maxZoom: 8),
    isNotNull,
  );
  expect(gesture.isZooming, isTrue);

  expect(
    gesture.update(cumulativeScale: 1.001, minZoom: 0.25, maxZoom: 8),
    isNotNull,
  );
  expect(gesture.isZooming, isTrue);
});

test('ending a trackpad zoom clears its locked state', () {
  final ReaderTrackpadZoomGesture gesture = ReaderTrackpadZoomGesture();
  gesture.start(startZoom: 2, anchor: const Offset(420, 315));
  gesture.update(cumulativeScale: 1.5, minZoom: 0.25, maxZoom: 8);

  gesture.end();

  expect(gesture.anchor, isNull);
  expect(gesture.isZooming, isFalse);
  expect(
    gesture.update(cumulativeScale: 1.5, minZoom: 0.25, maxZoom: 8),
    isNull,
  );
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
flutter test test/phase1_reader_test.dart --plain-name "trackpad"
```

Expected: compilation fails because `ReaderTrackpadZoomGesture` does not exist.

- [ ] **Step 3: Implement the minimal cumulative gesture state**

Add below `readerPointerZoomSensitivity` in `pdf_viewer_interaction_math.dart`:

```dart
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
    _isZooming = _isZooming ||
        (cumulativeScale - 1).abs() > readerTrackpadZoomThreshold;
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
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```powershell
flutter test test/phase1_reader_test.dart --plain-name "trackpad"
```

Expected: all matching tests pass.

- [ ] **Step 5: Run the complete math test file**

Run:

```powershell
flutter test test/phase1_reader_test.dart
```

Expected: all tests pass with no analyzer or runtime errors.

- [ ] **Step 6: Commit the gesture semantics**

```powershell
git add -- lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart test/phase1_reader_test.dart
git commit -m "test: define desktop trackpad zoom semantics"
```

---

### Task 2: Route raw desktop zoom through the shared reader region

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart:25-225`
- Test: `test/phase1_reader_test.dart`

**Interfaces:**
- Consumes: `ReaderTrackpadZoomGesture` and `dampenReaderPointerScale` from Task 1.
- Produces: `ReaderCursorLockedPdfInput.pdfrxScaleEnabled`, always `false` for the desktop adapter.
- Produces: raw handlers `handlePointerPanZoomStart`, `handlePointerPanZoomUpdate`, `handlePointerPanZoomEnd`, and `handlePointerSignal` used only by `ReaderCursorLockedPdfRegion`.

- [ ] **Step 1: Add a recording controller used by raw-event tests**

Add this private fake near the bottom of `test/phase1_reader_test.dart`:

```dart
class _ZoomCall {
  const _ZoomCall(this.localPosition, this.newZoom);

  final Offset localPosition;
  final double newZoom;
}

class _RecordingPdfViewerController extends PdfViewerController {
  _RecordingPdfViewerController({this.zoom = 2});

  double zoom;
  Offset translation = Offset.zero;
  final List<_ZoomCall> zoomCalls = <_ZoomCall>[];

  Offset documentPointAt(Offset localPosition) =>
      (localPosition - translation) / zoom;

  @override
  bool get isReady => true;

  @override
  double get currentZoom => zoom;

  @override
  double get minScale => 0.25;

  @override
  double get maxScale => 8;

  @override
  Size get viewSize => const Size(800, 600);

  @override
  Offset? globalToLocal(Offset global) => global;

  @override
  Future<void> zoomOnLocalPosition({
    required Offset localPosition,
    required double newZoom,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final Offset documentPoint = documentPointAt(localPosition);
    zoomCalls.add(_ZoomCall(localPosition, newZoom));
    zoom = newZoom;
    translation = localPosition - documentPoint * newZoom;
  }
}
```

- [ ] **Step 2: Add a failing synthetic `PointerPanZoom` widget test**

Add:

```dart
testWidgets('raw trackpad zoom ignores cumulative pan and locks the cursor', (
  WidgetTester tester,
) async {
  final _RecordingPdfViewerController controller =
      _RecordingPdfViewerController();
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: ReaderCursorLockedPdfRegion(
          controller: controller,
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
    ),
  );
  const Offset cursor = Offset(420, 315);
  final Offset documentPointBefore = controller.documentPointAt(cursor);
  final TestGesture gesture = await tester.startGesture(
    cursor,
    kind: PointerDeviceKind.trackpad,
  );

  await gesture.panZoomUpdate(
    cursor,
    pan: const Offset(-280, -200),
    scale: 1.5,
  );
  await gesture.panZoomUpdate(
    cursor,
    pan: const Offset(-470, -348),
    scale: 1.75,
  );
  await gesture.panZoomEnd();

  expect(controller.zoomCalls, hasLength(2));
  expect(
    controller.zoomCalls.map((_ZoomCall call) => call.localPosition),
    everyElement(cursor),
  );
  expect(controller.zoomCalls.first.newZoom, closeTo(2.65, 0.000001));
  expect(controller.zoomCalls.last.newZoom, closeTo(2.975, 0.000001));
  expect(controller.documentPointAt(cursor), documentPointBefore);
});

testWidgets('raw scale noise does not take ownership from trackpad pan', (
  WidgetTester tester,
) async {
  final _RecordingPdfViewerController controller =
      _RecordingPdfViewerController();
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderCursorLockedPdfRegion(
        controller: controller,
        builder: (_, _) => const SizedBox.expand(),
      ),
    ),
  );
  final TestGesture gesture = await tester.startGesture(
    const Offset(420, 315),
    kind: PointerDeviceKind.trackpad,
  );

  await gesture.panZoomUpdate(
    const Offset(420, 315),
    pan: const Offset(0, -80),
    scale: 1.009,
  );
  await gesture.panZoomEnd();

  expect(controller.zoomCalls, isEmpty);
});
```

- [ ] **Step 3: Run the raw adapter tests and verify RED**

Run:

```powershell
flutter test test/phase1_reader_test.dart --plain-name "raw"
```

Expected: tests fail because `ReaderCursorLockedPdfRegion` only records pointer positions and never calls `zoomOnLocalPosition`.

- [ ] **Step 4: Implement raw pan/zoom ownership in `ReaderCursorLockedPdfRegion`**

Change the region's `Listener` callbacks to explicit input methods:

```dart
return Listener(
  behavior: HitTestBehavior.translucent,
  onPointerHover: _input.rememberPointer,
  onPointerDown: _input.rememberPointer,
  onPointerMove: _input.rememberPointer,
  onPointerUp: _input.rememberPointer,
  onPointerCancel: _input.rememberPointer,
  onPointerSignal: _input.handlePointerSignal,
  onPointerPanZoomStart: _input.handlePointerPanZoomStart,
  onPointerPanZoomUpdate: _input.handlePointerPanZoomUpdate,
  onPointerPanZoomEnd: _input.handlePointerPanZoomEnd,
  child: widget.builder(context, _input),
);
```

Add state and handlers to `ReaderCursorLockedPdfInput`:

```dart
final ReaderTrackpadZoomGesture _trackpadZoom = ReaderTrackpadZoomGesture();

bool get pdfrxScaleEnabled => false;

void handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
  rememberPointer(event);
  if (!controller.isReady) {
    _trackpadZoom.end();
    return;
  }
  final Offset anchor = _validLocalAnchor(event.position);
  _trackpadZoom.start(startZoom: controller.currentZoom, anchor: anchor);
}

void handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
  rememberPointer(event);
  if (!controller.isReady) {
    return;
  }
  final double? newZoom = _trackpadZoom.update(
    cumulativeScale: event.scale,
    minZoom: controller.minScale,
    maxZoom: controller.maxScale,
  );
  final Offset? anchor = _trackpadZoom.anchor;
  if (newZoom == null || anchor == null) {
    return;
  }
  unawaited(
    controller.zoomOnLocalPosition(
      localPosition: anchor,
      newZoom: newZoom,
      duration: Duration.zero,
    ),
  );
}

void handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
  rememberPointer(event);
  _trackpadZoom.end();
}

Offset _validLocalAnchor(Offset globalPosition) {
  final Offset? local = controller.globalToLocal(globalPosition);
  if (local != null && _isInsideViewport(local, controller.viewSize)) {
    return local;
  }
  return controller.viewSize.center(Offset.zero);
}
```

Keep `rememberPointer` for cursor tracking. Do not read `event.pan` or `event.panDelta` in the zoom handler.

- [ ] **Step 5: Run the raw adapter tests and verify GREEN**

Run:

```powershell
flutter test test/phase1_reader_test.dart --plain-name "raw"
```

Expected: both raw-event tests pass; the recorded local position remains `(420, 315)` despite large cumulative pan.

- [ ] **Step 6: Add failing pointer-scale and Ctrl-wheel tests**

Ensure `phase1_reader_test.dart` imports `package:flutter/gestures.dart`, `package:flutter/material.dart`, and `package:flutter/services.dart`, then add:

```dart
testWidgets('pointer scale zooms incrementally around the cursor', (
  WidgetTester tester,
) async {
  final _RecordingPdfViewerController controller =
      _RecordingPdfViewerController();
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderCursorLockedPdfRegion(
        controller: controller,
        builder: (_, _) => const SizedBox.expand(),
      ),
    ),
  );
  const Offset cursor = Offset(420, 315);

  await tester.sendEventToBinding(
    const PointerScaleEvent(position: cursor, scale: 1.2),
  );

  expect(controller.zoomCalls, hasLength(1));
  expect(controller.zoomCalls.single.localPosition, cursor);
  expect(controller.zoomCalls.single.newZoom, closeTo(2.26, 0.000001));
});

testWidgets('Ctrl-wheel zooms while plain wheel remains pdfrx-owned', (
  WidgetTester tester,
) async {
  final _RecordingPdfViewerController controller =
      _RecordingPdfViewerController();
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderCursorLockedPdfRegion(
        controller: controller,
        builder: (_, _) => const SizedBox.expand(),
      ),
    ),
  );
  const Offset cursor = Offset(420, 315);

  await tester.sendEventToBinding(
    const PointerScrollEvent(
      position: cursor,
      scrollDelta: Offset(0, -120),
    ),
  );
  expect(controller.zoomCalls, isEmpty);

  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendEventToBinding(
    const PointerScrollEvent(
      position: cursor,
      scrollDelta: Offset(0, -120),
    ),
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

  expect(controller.zoomCalls, hasLength(1));
  expect(controller.zoomCalls.single.localPosition, cursor);
  expect(controller.zoomCalls.single.newZoom, closeTo(2.26, 0.000001));
});
```

- [ ] **Step 7: Run those signal tests and verify RED**

Run:

```powershell
flutter test test/phase1_reader_test.dart --plain-name "pointer scale"
flutter test test/phase1_reader_test.dart --plain-name "Ctrl-wheel"
```

Expected: no controller zoom calls are recorded because `handlePointerSignal` has not implemented desktop zoom signals.

- [ ] **Step 8: Implement pointer-scale and Ctrl-wheel handling**

Import `dart:math` as `math` and `package:flutter/services.dart`. Add:

```dart
void handlePointerSignal(PointerSignalEvent event) {
  rememberPointer(event);
  if (!controller.isReady) {
    return;
  }
  if (event is PointerScaleEvent) {
    _applyIncrementalZoom(
      globalPosition: event.position,
      rawScale: event.scale,
    );
    return;
  }
  if (event is PointerScrollEvent &&
      HardwareKeyboard.instance.isControlPressed) {
    final double wheelSteps =
        -(event.scrollDelta.dx + event.scrollDelta.dy) / 120;
    _applyIncrementalZoom(
      globalPosition: event.position,
      rawScale: math.pow(1.2, wheelSteps).toDouble(),
    );
  }
}

void _applyIncrementalZoom({
  required Offset globalPosition,
  required double rawScale,
}) {
  if (!rawScale.isFinite || rawScale <= 0) {
    return;
  }
  final double scale = dampenReaderPointerScale(rawScale);
  if (!scale.isFinite || scale <= 0) {
    return;
  }
  final double newZoom = (controller.currentZoom * scale)
      .clamp(controller.minScale, controller.maxScale)
      .toDouble();
  unawaited(
    controller.zoomOnLocalPosition(
      localPosition: _validLocalAnchor(globalPosition),
      newZoom: newZoom,
      duration: Duration.zero,
    ),
  );
}
```

- [ ] **Step 9: Run all phase-one reader tests and verify GREEN**

Run:

```powershell
flutter test test/phase1_reader_test.dart
```

Expected: every test passes.

- [ ] **Step 10: Commit the raw desktop adapter**

```powershell
git add -- lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart test/phase1_reader_test.dart
git commit -m "fix: own desktop PDF zoom input"
```

---

### Task 3: Disable the bypassed pdfrx scale path and restore boundaries

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart:548-575`
- Modify: `lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart:70-100`
- Modify: `lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart:80-100`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart:12-20,109-116`
- Test: `test/reader_diagnostics/diagnostic_viewer_screens_test.dart:80-125`
- Test: `test/phase1_reader_test.dart:10-25`

**Interfaces:**
- Consumes: `ReaderCursorLockedPdfInput.pdfrxScaleEnabled` from Task 2.
- Removes: `preserveReaderCursorLockedMatrix` and `ReaderCursorLockedPdfInput.normalizeMatrix`.
- Keeps: the existing interaction delegate for pdfrx-owned panning and any non-scale delegate responsibilities.

- [ ] **Step 1: Tighten viewer configuration tests first**

Change both diagnostic viewer tests to assert:

```dart
expect(viewer.params.scaleEnabled, isFalse);
expect(viewer.params.normalizeMatrix, isNull);
```

Keep the existing assertion that `interactionDelegateProvider` is a `ReaderCursorAnchoredInteractionDelegateProvider`. Task 1 has already removed the obsolete normalization-preservation unit test from `phase1_reader_test.dart`; do not add a replacement identity-normalization test.

- [ ] **Step 2: Run the diagnostic viewer tests and verify RED**

Run:

```powershell
flutter test test/reader_diagnostics/diagnostic_viewer_screens_test.dart --plain-name "shared cursor-locked PDF input"
```

Expected: both tests fail because `scaleEnabled` is still `true` and `normalizeMatrix` is still non-null.

- [ ] **Step 3: Wire all viewers to the desktop adapter**

In the workspace, stock diagnostic, and instrumented diagnostic `PdfViewerParams`, replace:

```dart
scaleEnabled: true,
```

with:

```dart
scaleEnabled: input.pdfrxScaleEnabled,
```

Delete each of these parameter assignments:

```dart
normalizeMatrix: input.normalizeMatrix,
```

Delete `preserveReaderCursorLockedMatrix` and `ReaderCursorLockedPdfInput.normalizeMatrix` from `pdf_viewer_interaction_math.dart`.

- [ ] **Step 4: Run the diagnostic viewer tests and verify GREEN**

Run:

```powershell
flutter test test/reader_diagnostics/diagnostic_viewer_screens_test.dart --plain-name "shared cursor-locked PDF input"
```

Expected: both tests pass with pdfrx scale disabled and default normalization restored.

- [ ] **Step 5: Run formatting and static analysis**

Run:

```powershell
dart format lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart test/phase1_reader_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
dart analyze lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/reader_diagnostics test/phase1_reader_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: formatter completes and analyzer reports `No issues found!`.

- [ ] **Step 6: Run the focused regression suite**

Run:

```powershell
flutter test test/phase1_reader_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit viewer integration**

```powershell
git add -- lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart test/phase1_reader_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
git commit -m "fix: route pdfrx zoom through desktop adapter"
```

---

### Task 4: Full verification and handoff

**Files:**
- Verify only; no planned production edits.

**Interfaces:**
- Consumes the completed desktop adapter and viewer integration.
- Produces verification evidence and a concise manual trackpad checklist.

- [ ] **Step 1: Inspect the final diff and workspace ownership**

Run:

```powershell
git status --short
git diff HEAD~3 --check
git diff HEAD~3 -- lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart test/phase1_reader_test.dart test/reader_diagnostics/diagnostic_viewer_screens_test.dart
```

Expected: no whitespace errors; untracked `assets/` and `docs/superpowers/plans/2026-07-20-openai-compatible-agent-runtime.md` remain untouched.

- [ ] **Step 2: Run the complete test suite**

Run:

```powershell
flutter test
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Run project-wide static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 4: Perform the Windows trackpad acceptance check**

Run Clarix on Windows, open the same PDF used in the instrumented recording, and verify:

1. Place the cursor over a recognizable word and pinch outward; that word remains beneath the cursor.
2. Reverse the pinch without lifting; zoom reverses smoothly without a diagonal jump.
3. Move two fingers together without changing their distance; the document pans normally.
4. Ctrl+mouse-wheel zooms around the cursor; plain wheel scrolls.
5. Pinch near document edges; the viewer clamps without exposing an unbounded blank canvas.

Expected: behavior visually matches `assets/Expected zoom logic.mp4`, and a new diagnostic log no longer satisfies `scaleUpdate.focal == pointer.position + cumulativePan` for the matrix-driving anchor.

- [ ] **Step 5: Record final evidence**

Report the exact test count, analyzer result, commits created, files changed, and whether the physical trackpad acceptance check was performed or remains for the user.
