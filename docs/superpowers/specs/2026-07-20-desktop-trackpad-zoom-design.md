# Desktop Trackpad Zoom Design

## Goal

Make Clarix's desktop PDF zoom behave like Foxit PDF Editor: a pinch zooms smoothly around the stationary mouse cursor, the PDF point beneath that cursor remains fixed, and ordinary two-finger movement without scaling continues to pan.

## Scope

Clarix is currently desktop-only. This change covers precision-trackpad pinch, desktop `PointerScaleEvent` input, and Ctrl+mouse-wheel zoom in every pdfrx viewer that uses `ReaderCursorLockedPdfRegion`. It does not add touch-screen pinch behavior or modify pdfrx itself.

## Root Cause

pdfrx's internal `InteractiveViewer` receives Flutter `ScaleUpdateDetails` for a precision trackpad. Flutter derives the focal point as the stationary pointer position plus cumulative trackpad pan. pdfrx uses that derived focal directly, so the zoom anchor drifts far from the cursor. The existing `PdfViewerScrollInteractionDelegate` is not called for this path, and the existing `onInteractionUpdate` callback can only observe the already-applied transform.

`scaleByPointerScale` is likewise bypassed by this path. In addition, the current identity `normalizeMatrix` callback disables pdfrx boundary clamping and makes incorrect translations produce large blank regions.

## Architecture

`ReaderCursorLockedPdfRegion` becomes the owner of desktop zoom input. Its descendant `PdfViewer` keeps pdfrx panning enabled but sets pdfrx scaling disabled. This prevents the internal scale recognizer from mutating the matrix during a precision-trackpad pinch.

The region handles raw pointer events through its existing `Listener`:

- On `PointerPanZoomStartEvent`, capture the stationary cursor in viewer-local coordinates, the starting zoom, and reset the gesture classification.
- On `PointerPanZoomUpdateEvent`, classify the sequence as zoom once cumulative scale differs from 1 by a small threshold. Before that threshold, do nothing and allow pdfrx to perform ordinary two-finger panning.
- Once classified as zoom, compute a dampened cumulative scale from the gesture-start zoom. Apply the new zoom around the captured cursor. Ignore cumulative pan for anchor selection.
- On `PointerPanZoomEndEvent`, clear gesture state.
- Handle `PointerScaleEvent` as an incremental zoom around `event.position` converted to viewer-local coordinates.
- Handle Ctrl+mouse-wheel as an incremental zoom around the wheel event position. Non-Ctrl wheel input remains owned by pdfrx.

The adapter will expose a single `pdfrxScaleEnabled` value so every viewer configuration explicitly disables the bypassed pdfrx scale path.

## Zoom Mathematics

For a trackpad gesture with cumulative raw scale `s`, sensitivity `k`, starting zoom `z0`, and locked cursor `a`:

```text
dampenedScale = 1 + (s - 1) * k
targetZoom = clamp(z0 * dampenedScale, minZoom, maxZoom)
```

The controller zoom operation must preserve this invariant:

```text
documentPointBefore(anchor) == documentPointAfter(anchor)
```

The stationary event position, not `event.pan`, `event.panDelta`, or Flutter's synthesized `ScaleUpdateDetails.localFocalPoint`, supplies the anchor.

## Boundary Behavior

Remove the identity `normalizeMatrix` override from all affected pdfrx viewers. Zoom mutations use the controller's normal safe-range behavior so the document cannot be translated indefinitely outside its valid viewport. Cursor anchoring takes precedence until a real document boundary requires clamping; boundary clamping may then move the anchor by only the minimum necessary amount.

## Components

### Desktop gesture state

A small state object records the gesture-start zoom, locked viewer-local anchor, and whether the scale threshold has been crossed. It contains no widget or pdfrx rendering logic.

### Gesture math

Pure helpers calculate dampened cumulative scale and determine when a pan/zoom sequence becomes a zoom. These helpers are shared by the adapter and unit tests.

### Reader input region

`ReaderCursorLockedPdfRegion` routes raw pointer input into the desktop gesture state and controller. Existing tracked-cursor support remains available for toolbar zoom and any delegate-based pointer-scale paths that remain useful.

### Viewer configuration

The workspace, stock diagnostic viewer, and instrumented diagnostic viewer consume the region's scale setting. They no longer install the identity matrix normalizer.

## Event Ownership

- Plain mouse wheel: pdfrx scrolling.
- Two-finger trackpad pan with scale near 1: pdfrx panning.
- Precision-trackpad pinch: Clarix desktop adapter zooming.
- `PointerScaleEvent`: Clarix desktop adapter zooming.
- Ctrl+mouse-wheel: Clarix desktop adapter zooming.
- Toolbar zoom controls: existing controller methods.

The same raw event must never be applied by both Clarix and pdfrx.

## Error and Edge Handling

- Ignore events until the `PdfViewerController` is ready.
- Reject non-finite or non-positive scale values.
- Fall back to the viewport center only when the event position cannot be converted to a valid in-viewport local coordinate.
- Clamp target zoom to controller minimum and maximum values.
- Do not start zooming for scale noise below the classification threshold.
- Once a sequence is classified as zoom, keep that classification until its end to prevent oscillation between pan and zoom.

## Tests

Implementation follows red-green-refactor.

1. A synthetic `PointerPanZoom` sequence with a fixed `position`, large cumulative `pan`, and changing `scale` must keep the same document point under the fixed cursor.
2. Scale damping must be applied to cumulative trackpad scale from the gesture-start zoom.
3. Scale noise beneath the threshold must not be classified as zoom, preserving ordinary two-finger panning.
4. Once classified as zoom, later near-1 scale values must not revert the sequence to pan.
5. Viewer widget tests must assert that pdfrx scaling is disabled and the identity matrix normalizer is absent.
6. Existing reader diagnostics and workspace tests must remain green.

## Acceptance Criteria

- The Foxit-style cursor anchor is stable throughout precision-trackpad pinch in the stock, instrumented, and workspace PDF viewers.
- Zoom no longer follows cumulative two-finger pan diagonally across the screen.
- Zoom sensitivity affects precision-trackpad pinch.
- Ordinary two-finger panning and plain-wheel scrolling still work.
- The PDF cannot be moved arbitrarily outside safe viewer bounds during zoom.
- Automated tests exercise the raw desktop gesture adapter rather than only testing disconnected helper functions.
