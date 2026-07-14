# PDF Input Diagnostics Design

## Purpose

Clarix needs an isolated way to determine whether imprecise Windows trackpad zoom originates in Flutter pointer events, stock `pdfrx` 2.4.7, or Clarix's document workspace integration. The temporary diagnostics experience replaces the normal startup screen while leaving the production workspace one click away.

## Goals

- Establish a genuinely stock `pdfrx` control case.
- Capture the complete pointer-to-camera data path without logging document content.
- Visualize the real cursor and the focal point reported by trackpad events.
- Reproduce pointer behavior without PDF rendering or `pdfrx` involved.
- Produce bounded, copyable JSON logs suitable for comparing runs.
- Keep all diagnostics easy to remove after the zoom defect is resolved.

## Non-goals

- Fix zoom behavior as part of the diagnostics feature.
- Persist diagnostic sessions across application restarts.
- Read, extract, index, or log PDF text.
- Add diagnostics to Android or iOS.
- Replace the normal Clarix workspace permanently.

## Startup and Navigation

`ClarixApp` temporarily starts on `ReaderDiagnosticsHub` inside the existing window bootstrap and theme. The hub presents four destinations:

1. **Stock pdfrx viewer**
2. **Instrumented pdfrx viewer**
3. **Pointer and trackpad canvas lab**
4. **Normal Clarix workspace**

Navigation uses the existing Flutter `Navigator`; no routing dependency is introduced. Each diagnostic screen has a consistent Back action. The workspace remains unchanged and can be opened from the hub.

## Screen Design

### Stock pdfrx viewer

The stock screen is the control case. It contains:

- A minimal Open PDF action using `file_picker`.
- A `PdfViewer.file` or equivalent `PdfDocumentRefFile` using default `PdfViewerParams`.
- A `PdfViewerController` only for read-only status such as zoom and page number.
- A small dismissible overlay for Back, Open, current page, and current zoom.

It must not install Clarix's interaction delegate, matrix normalizer, custom scrollbars, annotations, Riverpod workspace state, or viewer-state persistence. This screen answers whether stock `pdfrx` is precise inside the Clarix process and window.

### Instrumented pdfrx viewer

The instrumented screen starts from the same viewer configuration, then adds observation without changing camera calculations. It records:

- Pointer event type and device kind.
- Global, listener-local, viewer-local, and document coordinates when available.
- Tracked cursor position.
- Trackpad-reported focal point.
- Scale and pan deltas.
- Controller zoom before and after an event.
- Matrix scale and X/Y translation before and after an event.
- Viewport size, document size, and visible document rectangle.
- Page number and whether the candidate position is near a boundary.

The screen paints separate crosshairs for the tracked cursor and reported focal point. A collapsible diagnostics panel shows recent events and offers Pause, Clear, and Copy JSON. The viewer remains fullscreen when the panel is collapsed.

### Pointer and trackpad canvas lab

The canvas lab excludes PDF rendering and `pdfrx`. It contains:

- A full-window grid divided into four labeled quadrants.
- Coordinate axes, viewport bounds, and a center marker.
- A cursor crosshair driven by hover/move events.
- A separate focal crosshair driven by pointer scale events.
- Live scale, pan, global position, local position, and device-kind readouts.
- A simulated camera rectangle using the standard affine anchor formula.

This screen establishes whether Windows and Flutter report a corner-like focal point before `pdfrx` receives the event.

## Diagnostics Model

`ReaderDiagnosticEvent` is an immutable structured record containing:

- Monotonic sequence number.
- Elapsed microseconds from recorder creation.
- Screen source and event type.
- Pointer/device metadata.
- Optional coordinate values.
- Optional scale and pan values.
- Optional viewer snapshot before and after processing.
- A short non-sensitive note.

`ReaderViewerSnapshot` contains zoom, translation, viewport size, document size, visible rectangle, and page number.

`ReaderDiagnosticsRecorder` owns a 500-event ring buffer and a `ValueNotifier` snapshot for UI updates. It emits the same structured record through `clarixLog`. Hover and controller-listener updates are sampled to avoid flooding, while scale, pointer-signal, interaction-start, and interaction-end events are never sampled.

Copied JSON excludes file paths, PDF titles, document text, and model information. The recorder is in-memory only and is disposed with its screen.

## Data Flow

1. A pointer event enters the screen-level listener.
2. The screen records raw global and local event values.
3. The instrumented viewer converts the global cursor through `PdfViewerController.globalToLocal` and, when possible, `localToDocument`.
4. A pre-event controller snapshot is recorded.
5. `pdfrx` processes the event normally.
6. The controller listener records the resulting matrix and visible rectangle.
7. The recorder correlates records by sequence and elapsed time for visual and JSON inspection.

No diagnostic handler writes to `PdfViewerController` on the stock or instrumented screens.

## Error Handling

- File-picker cancellation is silent.
- Unsupported, encrypted, or corrupted PDFs show the viewer error without crashing the hub.
- Coordinate conversion failures are represented as null values rather than substituted corners.
- Non-finite coordinates and matrix values are tagged in the event note and excluded from crosshair painting.
- Copy failures show a local snackbar and preserve the buffer.

## Performance Constraints

- Recorder capacity is fixed at 500 events.
- Hover events are sampled to at most 20 records per second.
- Controller matrix events are coalesced to one per rendered frame.
- Crosshair updates are isolated with `ValueNotifier`/`ValueListenableBuilder` and do not rebuild the PDF viewer.
- The stock screen has no diagnostics recorder and remains the lowest-overhead baseline.

## Testing

Unit tests cover:

- Event JSON serialization and omission of sensitive fields.
- Ring-buffer ordering and 500-event eviction.
- Hover sampling while scale events remain unsampled.
- Finite-coordinate validation.
- Affine zoom-anchor invariance at center and four non-central points.
- Correlation of before/after viewer snapshots.

Widget tests cover:

- Diagnostics hub destinations.
- Navigation to the workspace and back.
- Empty-state and file-picker cancellation behavior through injected picker callbacks.
- Canvas cursor and focal crosshairs remaining independent.
- Pause, Clear, collapse, and Copy JSON controls.

Manual acceptance covers:

- Opening the same PDF in stock and instrumented viewers.
- Trackpad zoom at the center and four non-central positions near fit width.
- Comparing cursor and reported focal crosshairs.
- Confirming logs show raw event coordinates and resulting matrix movement.
- Confirming the pointer lab reproduces or disproves quadrant-to-corner focal reporting.

## File Boundaries

Diagnostics live under `lib/src/features/reader_diagnostics/` with separate `domain`, `application`, and `presentation` files. Startup changes are limited to `lib/src/app.dart`. Existing workspace code is not modified to emit diagnostics during this phase.

## Removal Strategy

After the defect is understood, startup returns to `WorkspaceScreen`. The diagnostics feature directory and its tests can then be removed without changing workspace domain or persistence code. Any generally useful affine-math tests may be retained in the reader test suite.
