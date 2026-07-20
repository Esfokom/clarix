# pdfrx desktop trackpad zoom: root cause, reproduction, and upstream PR guide

## Status

- Clarix fix: implemented and verified.
- Clarix verification: 77 tests pass and `flutter analyze` reports no issues.
- Affected Clarix environment: Flutter 3.44.2, Dart 3.12.2, pdfrx 2.4.7, Windows desktop, precision trackpad.
- Upstream status checked on 2026-07-20: pdfrx `master` commit
  [`9a2d64ec`](https://github.com/espresso3389/pdfrx/commit/9a2d64ecf6be721ab21f93f20131956227b684b8)
  still contains the affected gesture path and still declares pdfrx 2.4.7.

## Executive summary

This was not a PDF rendering bug and it was not caused by the cursor moving.

The real bug was a coordinate-semantics mismatch in the trackpad gesture path:

1. Windows delivered a `PointerPanZoomUpdateEvent` with a stationary `position`, a cumulative `scale`, and a large
   `pan` component.
2. Flutter's `ScaleGestureRecognizer`, with `trackpadScrollCausesScale == false`, synthesizes the scale gesture focal
   point as `event.position + event.pan`.
3. pdfrx's forked `InteractiveViewer` used that synthesized `ScaleUpdateDetails.localFocalPoint` as the zoom pivot.
4. Therefore pdfrx preserved the document point under `position + pan`, not the document point under the stationary
   cursor at `position`.

On the observed Windows events, the `pan` component was not a small intentional two-finger translation. It matched the
affine compensation term `(1 - scale) * position`. Adding that value to the cursor produced a rapidly moving synthetic
focal point. The document consequently appeared to fly away from the cursor while zooming.

Two secondary problems made the behavior worse:

- pdfrx's documented `scaleByPointerScale` sensitivity was not applied to this raw `PointerPanZoom` path. It was only
  applied to `PointerScaleEvent` and Ctrl+wheel handling.
- Clarix had supplied an identity `normalizeMatrix` callback. That application callback bypassed pdfrx's normal safe
  boundary clamping, so the incorrect translation could expose very large blank regions.

The identity normalization callback was a Clarix configuration mistake, not an upstream pdfrx defect. The moving
trackpad zoom pivot and the bypassed trackpad sensitivity are suitable upstream pdfrx issues.

## User-visible behavior

### Expected

Desktop PDF editors such as Foxit behave as follows:

- The mouse cursor remains stationary during a trackpad pinch.
- The PDF point under that cursor remains under the cursor while the zoom changes.
- Two-finger panning remains responsive, including immediate reversal after reaching a document boundary.
- Zooming does not reveal unbounded empty canvas beyond the document's valid range.

### Actual before the fix

- The cursor remained still, but the PDF translated strongly during the pinch.
- The apparent zoom center moved toward or beyond a viewport corner.
- Reversing the pinch could cause another large translation in the opposite direction.
- Zoom sensitivity configuration did not affect native `PointerPanZoom` pinch events.
- With the identity `normalizeMatrix` callback, the incorrect translation could leave most of the viewer blank.

## Evidence from the captured event log

At the start of one gesture:

```text
cursor / event.position = (624.0, 460.8)
event.scale             = 1.4504809379577637
event.pan               = (-281.1001953125, -207.581689453125)
pdfrx localFocalPoint   = (342.8998046875, 253.21831054687502)
```

The pdfrx focal point is exactly the cursor plus the cumulative pan:

```text
(624.0, 460.8) + (-281.1001953125, -207.581689453125)
  = (342.8998046875, 253.218310546875)
```

The pan is also the affine scale compensation around the cursor:

```text
(1 - 1.4504809379577637) * (624.0, 460.8)
  = (-281.100105..., -207.581616...)
```

The small difference is consistent with platform/event precision. This is why the pan magnitude was hundreds of pixels
even though the pointer did not move.

The controller zoom then changed from `1.7745895291` to `2.5740082847`, a ratio of `1.4504809379`, confirming that the
raw cumulative trackpad scale was used directly. The document coordinate under the stationary cursor changed from about
`(286.04, 230.20)` to `(395.25, 310.84)`, proving cursor anchoring was lost.

## Source-level root cause

### 1. Flutter converts raw trackpad pan/zoom into scale details

Flutter represents modern desktop trackpad input as `PointerPanZoomStartEvent`, `PointerPanZoomUpdateEvent`, and
`PointerPanZoomEndEvent`. Mouse wheels continue to use pointer signal events. See Flutter's
[trackpad gesture migration documentation](https://docs.flutter.dev/release/breaking-changes/trackpad-gestures) and the
[`PointerPanZoomUpdateEvent` API](https://api.flutter.dev/flutter/gestures/PointerPanZoomUpdateEvent-class.html).

In Flutter 3.44.2, `_PointerPanZoomData.focalPoint` returns `_position + _pan` when
`trackpadScrollCausesScale` is false. `ScaleGestureRecognizer` then exposes this result through
`ScaleUpdateDetails.focalPoint` and `localFocalPoint`. See Flutter source at:

- [`scale.dart`, `_PointerPanZoomData`](https://github.com/flutter/flutter/blob/c9a6c484230f8b5e408ec57be1ef71dee1e77020/packages/flutter/lib/src/gestures/scale.dart#L52-L76)
- [`scale.dart`, focal-point aggregation](https://github.com/flutter/flutter/blob/c9a6c484230f8b5e408ec57be1ef71dee1e77020/packages/flutter/lib/src/gestures/scale.dart#L595-L618)

That synthesized focal point is useful for treating a trackpad stream as a general pan gesture, but it is not a reliable
stationary mouse-cursor zoom anchor on the observed Windows pinch events.

### 2. pdfrx treats the synthesized focal point as the zoom pivot

pdfrx uses a forked `InteractiveViewer` and connects a `GestureDetector.onScaleUpdate` callback. The current code uses
`details.localFocalPoint` to:

- calculate the scene point before scaling;
- apply the new scale; and
- translate the matrix so that the same scene point remains beneath that focal point.

See pdfrx
[`interactive_viewer.dart`, gesture classification and scale update](https://github.com/espresso3389/pdfrx/blob/9a2d64ecf6be721ab21f93f20131956227b684b8/packages/pdfrx/lib/src/widgets/interactive_viewer.dart#L826-L943).

The scale math itself is reasonable. The wrong input coordinate is the problem: for this trackpad stream,
`details.localFocalPoint` is the moving `position + pan` value rather than the stationary `event.localPosition`.

### 3. pdfrx's pointer-scale sensitivity does not cover this path

`PdfViewerParams.scaleByPointerScale` is documented as applying to pointer scale events, including trackpad pinch, and
Ctrl+scroll. See
[`pdf_viewer_params.dart`](https://github.com/espresso3389/pdfrx/blob/9a2d64ecf6be721ab21f93f20131956227b684b8/packages/pdfrx/lib/src/widgets/pdf_viewer_params.dart#L425-L435).

The factor is applied in pdfrx's `PointerScaleEvent` handler, but native `PointerPanZoom` gestures go through the
`GestureDetector`/`ScaleGestureRecognizer` path instead. See
[`pdf_viewer.dart`, `_onPointerScale`](https://github.com/espresso3389/pdfrx/blob/9a2d64ecf6be721ab21f93f20131956227b684b8/packages/pdfrx/lib/src/widgets/pdf_viewer.dart#L1904-L1914).

As a result, changing `scaleByPointerScale` did not change the problematic Windows trackpad pinch speed.

### 4. The Clarix normalization override amplified the symptom

Clarix previously returned every proposed matrix unchanged from `normalizeMatrix`. That disabled pdfrx's default safe
range calculation. Once the focal point drift generated an incorrect translation, there was no boundary clamp to limit
it.

This callback was removed. A pdfrx PR should not cite the identity callback as an upstream defect.

## Reproduction

### Hardware reproduction

1. Use Windows 11 with a precision trackpad.
2. Use Flutter 3.44.2 and pdfrx 2.4.7.
3. Run a `PdfViewer` with `panEnabled: true` and `scaleEnabled: true`.
4. Open a PDF and place the cursor well away from the viewport origin, for example near `(700, 500)`.
5. Without moving the mouse cursor, pinch outward on the trackpad.
6. Repeat near different areas of the page.

Expected: the PDF point under the cursor remains under the cursor.

Actual: the PDF translates during zoom because the preserved point follows `position + pan`.

The issue is easiest to see when the cursor is far from `(0, 0)` because the observed compensation pan is proportional
to the cursor position.

### Instrumented reproduction

Wrap the viewer in a `Listener` and record raw pan/zoom values alongside pdfrx interaction details:

```dart
Listener(
  onPointerPanZoomStart: (event) {
    debugPrint('start position=${event.position} local=${event.localPosition}');
  },
  onPointerPanZoomUpdate: (event) {
    debugPrint(
      'update position=${event.position} '
      'pan=${event.pan} panDelta=${event.panDelta} scale=${event.scale}',
    );
  },
  child: PdfViewer.file(
    filePath,
    params: PdfViewerParams(
      onInteractionUpdate: (details) {
        debugPrint(
          'pdfrx focal=${details.focalPoint} '
          'localFocal=${details.localFocalPoint} scale=${details.scale}',
        );
      },
    ),
  ),
)
```

During the failing gesture, verify all of the following:

```text
event.position remains stationary
details.localFocalPoint approximately equals event.localPosition + event.localPan
the controller's document coordinate at event.localPosition changes after every zoom update
```

### Minimal automated regression shape

The package test should synthesize real trackpad events rather than directly calling a math helper:

```dart
final pointer = TestPointer(1, PointerDeviceKind.trackpad);
final cursor = tester.getCenter(find.byType(InteractiveViewer));

await tester.sendEventToBinding(pointer.panZoomStart(cursor));
await tester.sendEventToBinding(
  pointer.panZoomUpdate(
    cursor,
    pan: const Offset(-281.1002, -207.5817),
    scale: 1.4504809,
  ),
);
await tester.pump();
```

Before sending the update, convert the stationary cursor into scene/document coordinates. After the update, convert the
same stationary cursor again. The two scene points must be equal within floating-point tolerance unless a real document
boundary makes exact anchoring impossible.

The test must not assert only that a callback fired. It must assert the resulting transformation matrix or the scene
point under the stationary cursor.

## How Clarix fixed it

Clarix owns native desktop `PointerPanZoom` streams outside pdfrx and disables pdfrx's competing scale recognizer for
those viewer surfaces.

The implementation is in:

- [`pdf_viewer_interaction_math.dart`](../lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart)
- [`document_workspace.dart`](../lib/src/features/workspace/presentation/widgets/document_workspace.dart)
- [`phase1_reader_test.dart`](../test/phase1_reader_test.dart)

### Gesture start

On `PointerPanZoomStartEvent`, Clarix captures:

- the stationary viewer-local cursor from `event.localPosition`;
- the PDF document point under that cursor;
- the controller's immutable gesture-start matrix;
- the starting zoom; and
- a separate last committed/clamped matrix for panning.

### Pan-versus-zoom classification

Small scale noise does not immediately turn two-finger panning into zooming:

```text
abs(event.scale - 1) <= 0.01  => pan
abs(event.scale - 1) >  0.01  => zoom for the rest of this gesture
```

Once classified as zoom, ownership remains sticky until `PointerPanZoomEndEvent`. This prevents a later event whose
scale happens to return to exactly `1.0` from leaking into pdfrx's pan path.

### Panning before the zoom threshold

Panning uses `event.panDelta`, not cumulative `event.pan`:

```text
next pan matrix = last committed/clamped pan matrix + event.panDelta
```

After applying pdfrx's safe-range clamp, Clarix records the actual committed matrix as the baseline for the next delta.
This detail is necessary at boundaries. If an outward delta is clamped, a small reverse delta must move immediately;
recomputing from `gestureStartMatrix + cumulativePan` creates unwanted reversal dead travel.

### Zooming after the threshold

Zoom uses cumulative scale relative to the gesture start, not a product of successive updates:

```text
dampenedScale = 1 + (event.scale - 1) * 0.65
targetZoom    = clamp(startZoom * dampenedScale, minZoom, maxZoom)
```

Before every sticky zoom update, the implementation starts from the immutable gesture-start matrix and applies the
cumulative target zoom while preserving the gesture-start document point beneath the stationary cursor. It then uses the
controller's normal safe-range clamping.

Using the start matrix avoids compounding cumulative scale and overwrites any transient child mutation from the same raw
event.

### Other desktop zoom inputs

The same `0.65` damping is used for:

- native `PointerPanZoom` pinch;
- `PointerScaleEvent`; and
- Ctrl+wheel.

Plain wheel events are left to pdfrx for normal scrolling.

Adapter-owned zoom changes call the workspace's existing debounced persistence path so zoom is restored when the
document is reopened.

### Boundary behavior

Clarix removed the identity `normalizeMatrix` callback. Normal pdfrx safe-range clamping is now authoritative. The cursor
anchor is preserved exactly until a real boundary makes that impossible, after which the minimum necessary clamp is
allowed.

## Should this be contributed to pdfrx?

Yes. An upstream pdfrx issue and PR are justified.

The reason is not merely that Clarix wanted Foxit-like sensitivity. Current pdfrx behavior violates its own cursor-anchor
expectation because the package uses a synthesized moving focal coordinate for native trackpad pinch, and the documented
`scaleByPointerScale` parameter does not affect that path.

As of the upstream check, the closest open reports were
[#538](https://github.com/espresso3389/pdfrx/issues/538) and
[#547](https://github.com/espresso3389/pdfrx/issues/547). Those concern Web Ctrl+wheel/`PointerScaleEvent` behavior and
boundary margins; they do not describe native Windows `PointerPanZoom` cursor drift. The older
[#89](https://github.com/espresso3389/pdfrx/issues/89) concerns interaction callback focal deltas and is also different.

Recommended sequence:

1. Open a focused pdfrx issue with the minimal reproduction, raw event log, equation, and expected invariant.
2. Ask whether the maintainer prefers a package-local raw trackpad handler or a custom gesture recognizer.
3. Submit a small PR that changes only pdfrx trackpad ownership and tests.
4. Separately consider filing a Flutter issue about Windows `PointerPanZoom` scale/pan synthesis. Link it from the pdfrx
   issue, but do not block the pdfrx fix on a framework change.

## Recommended pdfrx package fix

Do not copy Clarix's workspace adapter wholesale into pdfrx. Implement the behavior inside pdfrx's internal
`InteractiveViewer`, where touch, trackpad, pointer-signal, physics, clamping, and interaction callbacks can share one
owner.

### Required architecture

1. Handle `PointerPanZoomStart/Update/End` explicitly for trackpad devices.
2. Prevent the `ScaleGestureRecognizer` from also mutating the matrix for the same trackpad stream. A `Listener` that only
   observes events is insufficient because observation does not prevent the descendant recognizer from acting.
3. Keep touch-screen pinch on the existing `ScaleGestureRecognizer` path.
4. Use raw `event.localPosition` as the stationary zoom anchor.
5. Use cumulative `event.scale` relative to the start matrix and start zoom.
6. Apply `PdfViewerParams.scaleByPointerScale` to the native trackpad scale delta.
7. Use incremental `event.localPanDelta` against the last committed/clamped pan matrix before zoom classification.
8. Keep zoom classification sticky until the raw gesture ends.
9. Route every mutation through the existing matrix clamp and interaction lifecycle callbacks.
10. Preserve scroll physics and immediate boundary reversal.

One clean implementation is to replace the internal `GestureDetector` with a `RawGestureDetector` whose scale recognizer
excludes `PointerDeviceKind.trackpad`, then let the surrounding raw trackpad handler own the full trackpad stream. Flutter's
[trackpad migration guide](https://docs.flutter.dev/release/breaking-changes/trackpad-gestures) describes device filtering
with `RawGestureDetector`. A pdfrx-specific recognizer is also reasonable if the maintainer wants gesture-arena ownership
instead of raw event ownership.

### State-machine sketch

The exact names should follow pdfrx conventions, but the important state separation is:

```dart
Matrix4? trackpadStartMatrix;       // immutable until end
Matrix4? trackpadPanMatrix;         // last matrix actually committed after clamp
Offset? trackpadAnchorLocal;        // raw stationary event.localPosition
Offset? trackpadAnchorScene;        // scene point under the stationary cursor at start
double? trackpadStartScale;
bool trackpadIsZooming = false;
```

The event flow should be equivalent to:

```dart
onPanZoomStart(event) {
  stopActiveAnimations();
  trackpadStartMatrix = controller.value.clone();
  trackpadPanMatrix = controller.value.clone();
  trackpadAnchorLocal = event.localPosition;
  trackpadAnchorScene = controller.toScene(event.localPosition);
  trackpadStartScale = controller.value.getMaxScaleOnAxis();
  trackpadIsZooming = false;
  onInteractionStart(...);
}

onPanZoomUpdate(event) {
  trackpadIsZooming |= (event.scale - 1).abs() > scaleNoiseThreshold;

  if (!trackpadIsZooming) {
    final candidate = translate(trackpadPanMatrix!, event.localPanDelta);
    controller.value = clamp(candidate);
    trackpadPanMatrix = controller.value.clone();
  } else {
    final effective = 1 + (event.scale - 1) * scaleByPointerScale;
    final target = clampScale(trackpadStartScale! * effective);
    final candidate = zoomFromStartMatrixKeepingScenePointAtLocalAnchor(
      trackpadStartMatrix!,
      trackpadAnchorScene!,
      trackpadAnchorLocal!,
      target,
    );
    controller.value = clamp(candidate);
  }

  onInteractionUpdate(...);
}

onPanZoomEnd(event) {
  clearTrackpadState();
  onInteractionEnd(...);
}
```

The package may choose a different threshold or make it private. The invariant matters more than Clarix's exact `0.01`
value.

### Approaches that are not sufficient

#### Observing raw events without exclusive ownership

An ancestor `Listener` receives the raw event, but it does not prevent pdfrx's descendant `ScaleGestureRecognizer` from
handling the same stream. Both layers can mutate the same matrix. Event order can then produce doubled pan, a leaked pan
after zoom classification, or a correction one frame later. The package fix needs one effective matrix owner for the
entire trackpad sequence.

#### Setting only `scaleEnabled: false`

In current pdfrx, `_getGestureType` forces the classification scale to `1.0` when scaling is disabled, but the pan branch
still discards an update when the original `details.scale != 1.0`. Therefore scale noise such as `1.009` can be handled by
neither the outer zoom adapter nor pdfrx pan. A later exact-`1.0` update can still pan through pdfrx even after an outer
adapter has classified the sequence as zoom.

#### Recomputing pan from gesture-start matrix plus cumulative pan

This works away from boundaries but creates reversal dead travel at a clamp. For example, an outward cumulative movement
of `-120` may clamp at `-100`; a reverse movement to cumulative `-115` remains clamped instead of moving immediately.
Incremental `panDelta` against the last committed/clamped matrix correctly moves to `-95` on a `+5` reversal.

#### Applying each scale update to the current scaled matrix

`PointerPanZoomUpdateEvent.scale` is cumulative from the gesture start. Applying `1.2` and then `1.4` multiplicatively to
the current matrix compounds the gesture incorrectly. Every zoom update must derive its absolute target from the captured
start zoom and start matrix.

#### Returning the proposed matrix unchanged from `normalizeMatrix`

This hides clamping symptoms rather than fixing input coordinates and allows bad translations to expose unbounded blank
space. Keep pdfrx's normal safe-range behavior in the upstream reproduction and fix.

### Likely files

- `packages/pdfrx/lib/src/widgets/interactive_viewer.dart`
- `packages/pdfrx/lib/src/widgets/pdf_viewer.dart` if the sensitivity or interaction delegate must be passed through
- `packages/pdfrx/lib/src/widgets/pdf_viewer_params.dart` only if documentation/API semantics need clarification
- a new focused test such as `packages/pdfrx/test/interactive_viewer_trackpad_test.dart`

Avoid unrelated changes to PDF rendering, layout, selection, or release metadata.

## Required upstream regression tests

The PR should include all of these:

1. **Stationary-cursor invariant**
   - Fixed event position.
   - Large cumulative pan matching the Windows log.
   - Scale changes from `1.0` to `1.45`.
   - The scene point under the fixed cursor remains invariant.

2. **Cumulative scale does not compound**
   - Updates `1.2`, then `1.4`.
   - Final zoom is `startZoom * dampened(1.4)`, not the first result multiplied by `1.4`.

3. **Sensitivity is applied**
   - Configure `scaleByPointerScale: 0.65`.
   - Raw scale `1.5` produces effective scale `1.325`.

4. **Scale noise remains pan**
   - Scale `1.009` with a pan delta.
   - The matrix pans and does not zoom.

5. **Sticky zoom ownership**
   - Cross threshold with scale `1.02`.
   - Send a later update with scale `1.0`.
   - It remains a zoom-owned update and does not leak a pan mutation.

6. **No double mutation**
   - Use a child/recognizer path that would mutate the same controller if it were still active.
   - Assert the final matrix contains one mutation, not two.

7. **Immediate boundary reversal**
   - Start at a clamped edge.
   - Apply an outward delta that remains clamped.
   - Apply a small reverse delta.
   - The matrix moves immediately by that reverse delta.

8. **Touch pinch regression**
   - Existing touch pinch behavior and anchoring remain unchanged.

9. **Plain wheel regression**
   - Plain mouse wheel still scrolls instead of zooming.

10. **Interaction lifecycle**
    - Trackpad start/update/end invoke the same public callbacks and persistence-relevant controller notifications as other
      viewer interactions.

## Commands for a pdfrx contribution

From the pdfrx monorepo:

```bash
cd packages/pdfrx
flutter pub get
dart format .
flutter analyze
flutter test
```

These commands match the repository's current contributor guidance. Do not update package versions, changelogs, tags, or
release artifacts in a behavioral fix PR unless the maintainer explicitly requests it.

## Suggested upstream issue text

### Title

```text
Windows trackpad pinch zoom drifts away from stationary cursor
```

### Body

```text
Environment
- Flutter 3.44.2
- Dart 3.12.2
- pdfrx 2.4.7
- Windows 11 precision trackpad

Expected
During a trackpad pinch, the PDF scene point under the stationary mouse cursor
remains under the cursor, subject only to document boundary clamping.

Actual
The PDF translates strongly while zooming. The apparent focal point moves with
the cumulative PointerPanZoom pan value even though event.position is stationary.

Evidence from one update
event.position           = (624.0, 460.8)
event.scale              = 1.4504809379577637
event.pan                = (-281.1001953125, -207.581689453125)
ScaleUpdate local focal  = (342.8998046875, 253.218310546875)

The scale focal is exactly event.position + event.pan. On this Windows event,
event.pan also approximately equals (1 - scale) * event.position.

Root cause
Flutter ScaleGestureRecognizer synthesizes trackpad focalPoint as position + pan
when trackpadScrollCausesScale is false. pdfrx InteractiveViewer uses the
synthesized ScaleUpdateDetails.localFocalPoint as the zoom pivot. This preserves
the wrong scene point.

Additional issue
PdfViewerParams.scaleByPointerScale is documented for trackpad pinch, but native
PointerPanZoom goes through GestureDetector.onScaleUpdate and bypasses the
PointerScaleEvent dampening path.

Reproduction
1. Open any PDF on Windows desktop.
2. Place the cursor away from the top-left origin.
3. Pinch outward without moving the cursor.
4. Observe the PDF drift away from the cursor.

I can provide a PR that gives native PointerPanZoom a single owner inside the
internal InteractiveViewer, uses event.localPosition as the zoom anchor, applies
scaleByPointerScale, preserves pan/boundary behavior, and adds synthetic trackpad
matrix regression tests.
```

## Suggested PR description

```text
Fix native desktop trackpad pinch anchoring

What changed
- Handle PointerPanZoom streams explicitly inside pdfrx InteractiveViewer.
- Exclude trackpad input from the competing ScaleGestureRecognizer path.
- Anchor native trackpad pinch at the stationary raw event position.
- Apply scaleByPointerScale to native PointerPanZoom scale deltas.
- Preserve incremental panning, clamping, immediate boundary reversal, and
  interaction lifecycle callbacks.

Why
On Windows, ScaleGestureRecognizer reports a focal point derived from
event.position + event.pan. pdfrx used that moving value as its zoom pivot, so
the document drifted away from a stationary cursor.

Tests
- stationary cursor with large Windows-style pan compensation
- cumulative/non-compounding scale
- configured scale dampening
- subthreshold scale noise remains pan
- sticky ownership after zoom classification
- no double mutation
- immediate reversal at a clamped boundary
- touch pinch and plain wheel regressions

No public API is removed and touch behavior is unchanged.
```

## Acceptance criteria

The upstream change is complete when:

- a synthetic Windows-style `PointerPanZoom` test fails on the old implementation and passes on the new one;
- the scene coordinate under a stationary cursor remains invariant during pinch, except for necessary boundary clamps;
- `scaleByPointerScale` affects native trackpad pinch;
- pan noise, sticky ownership, and boundary reversal tests pass;
- touch pinch and mouse wheel behavior remain unchanged; and
- `dart format .`, `flutter analyze`, and `flutter test` pass in `packages/pdfrx`.
