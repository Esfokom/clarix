# PDF input diagnostics runbook

Use this runbook to distinguish input behavior caused by Flutter itself, the
stock `pdfrx` viewer, and Clarix's observation-only diagnostics. Run it on the
Windows machine and input device where the issue is observed.

Do not include a PDF path, filename, title, document text, screenshots of
document content, or model information in copied JSON, tickets, or notes. Give
the chosen PDF a private external identifier if it must be referenced.

## Result to collect

Produce one comparison record containing:

- the five location results for the stock and instrumented viewers;
- the complete bounded JSON batch set from the instrumented viewer and pointer
  lab, with no accepted batch reporting evicted events;
- the equivalent pointer-lab observations; and
- the complete outputs for formatting, analysis, focused tests, full tests,
  and the Windows build.

Record the Windows version, display scaling, display resolution, app commit,
input device and driver, and input method (for example, precision trackpad
pinch). These are environment details, not PDF details.

## Set up the comparison

1. Start Clarix. Confirm that **Reader diagnostics** is the startup screen and
   that **Open workspace** opens normal Clarix in one click. Return to the hub.
2. Choose one local PDF for the entire run. Use the same file, page, window
   size, display scaling, and input device in both viewers. Do not record its
   path or other identifying/content information.
3. Open **Stock pdfrx viewer**, select the PDF with **Open PDF**, and navigate
   to the target page. Establish the page at fit width using the viewer's
   normal fit-width presentation. If the platform does not expose a separate
   fit-width action, reopen or reset the PDF and record that the initial
   width-fitted presentation was used. Do not add a custom zoom control.
4. Open **Instrumented pdfrx viewer**, select that same PDF, navigate to the
   same page, and establish the same fit-width baseline. Keep its Events panel
   visible while preparing a batch. The cyan crosshair is the cursor; the
   amber crosshair is the gesture focal point. The Events toolbar reports both
   buffered and evicted event counts.

The locations below are page-relative, not window- or Events-panel-relative.
For corner locations, measure 20 logical pixels inward from both adjoining
page edges. Use **Hide viewer controls** before every corner gesture in both
viewers; the center-top visibility button restores the controls without
resizing the viewer surface.

| ID | Required page location |
| --- | --- |
| C | Center of the visible page at fit width |
| TL | 20 px inside the page's top-left corner |
| TR | 20 px inside the page's top-right corner |
| BL | 20 px inside the page's bottom-left corner |
| BR | 20 px inside the page's bottom-right corner |

## Viewer procedure

Complete the following matrix for **each** location in the listed order. A
gesture counts only when it crosses the fit-width threshold: zoom-in starts at
fit width or below it and ends above it; zoom-out starts above fit width and
ends at fit width or below it. Reset to the appropriate side of the threshold
between gestures as needed, so every one of the twenty gestures crosses it.

1. In the stock viewer, place the pointer at the location and perform ten
   zoom-in gestures followed by ten zoom-out gestures. Watch for a page jump,
   unexpected anchor relocation, or input that the viewer does not receive.
   For TL, TR, BL, and BR, hide viewer controls before each gesture and keep
   them hidden for the entire gesture. Show them only when status or navigation
   is required; the viewer surface must not resize. Record the visible behavior
   and the current page/zoom status after the twentieth gesture.
2. In the instrumented viewer, show viewer controls, press **Clear**, and
   confirm the toolbar reads `0 buffered · 0 evicted`. Hide viewer controls for
   TL, TR, BL, and BR before starting each gesture. Keep the pointer stationary
   at the corresponding page location while each gesture begins.
3. Record the twenty gestures as four ordered batches of five: `01` and `02`
   contain the ten zoom-ins; `03` and `04` contain the ten zoom-outs. After
   each batch, show viewer controls, immediately press **Pause**, and confirm
   the toolbar still reports `0 evicted`. Press **Copy diagnostic JSON** and
   verify its `metadata.evictedEventCount` is `0` and `metadata.truncated` is
   `false`. Save it as `<location>-<batch>` (for example, `TL-03`), press
   **Clear**, resume recording, and hide controls before the next corner batch.
4. If a batch reports any evicted events or `truncated: true`, reject that
   export: it is incomplete. Clear it and repeat those gestures in smaller
   ordered batches, down to one gesture per batch if necessary. Never combine
   twenty gestures in one recorder buffer and never accept a truncated export.
5. Verify visually that the cyan cursor and amber focal marker remain
   independently positioned. Note any focal jump, especially to a viewport
   corner, and whether the cursor remained at the intended location.
6. Treat the complete ordered batch set as the location trace. Each export
   contains a privacy-safe metadata envelope plus raw pointer and scale events,
   focal/cursor positions, converted viewer/document coordinates where
   available, scale/pan, boundary booleans, and camera before/after snapshots.

Use this record while running the matrix:

| Location | Stock: 10 in / 10 out | Instrumented visible result | Complete JSON batch set saved | Focal jump/cursor stability |
| --- | --- | --- | --- | --- |
| C |  |  |  |  |
| TL |  |  |  |  |
| TR |  |  |  |  |
| BL |  |  |  |  |
| BR |  |  |  |  |

## Pointer / trackpad lab procedure

Open **Pointer / trackpad lab** from the hub. It is PDF-free; do not load a
PDF or try to compare document coordinates here. Use the same input device and
repeat the equivalent sequence at the center and 20 px inside each corresponding
canvas corner (C, TL, TR, BL, BR): ten zoom-in and ten zoom-out gestures that
cross the lab's current scale baseline. The lab uses its own recorder and Events
panel. Show overlays to clear and confirm `0 buffered · 0 evicted`, then use
**Hide lab overlays** during every corner gesture so the back button, readout,
and Events panel cannot intercept a 20 px target.

Use the same four ordered five-gesture export batches described for the
instrumented viewer. Pause and copy after each batch, accept it only when
`metadata.evictedEventCount` is `0` and `metadata.truncated` is `false`, then
clear, resume, and hide overlays before the next corner batch. If truncation is
reported, reject and repeat that batch in smaller units. This procedure is
required even when only visual lab observations are ultimately attached.

For every location, explicitly record whether the amber focal marker jumps to
a viewport corner while the cyan cursor stays stable. Also note the local/global
cursor and focal readouts, scale, translation, pan, and detected device kind.

| Location | Amber focal jumps to viewport corner? | Cyan cursor stable? | Lab scale/pan observation | Complete JSON batch set saved |
| --- | --- | --- | --- | --- |
| C |  |  |  |  |
| TL |  |  |  |  |
| TR |  |  |  |  |
| BL |  |  |  |  |
| BR |  |  |  |  |

Interpret the matrix as follows:

- A matching corner jump in the pointer lab points first to Flutter input or
  platform input delivery.
- A jump only in the stock and instrumented PDF viewers points first to stock
  `pdfrx` behavior.
- A difference between stock and instrumented viewers requires inspection of
  the instrumented event JSON and its observation layer; it is not evidence to
  change the controller camera.

These are investigation leads, not root-cause conclusions. Preserve the
environment record and JSON exports for follow-up.

## User-run formatting and static analysis

Run the following commands from the repository root and paste the **complete**
output into the verification record. Do not substitute partial output.

```text
dart format --output=none --set-exit-if-changed lib/src/features/reader_diagnostics test/reader_diagnostics lib/src/app.dart
flutter analyze
```

Expected: the formatter reports no required changes and the analyzer reports no
issues. If the formatter reports changes, run `dart format` on the listed paths,
inspect the resulting diff, and repeat the two commands before continuing.

## User-run tests and Windows build

Run each command from the repository root and paste the complete output.

```text
flutter test test/reader_diagnostics
flutter test
flutter build windows
```

Expected: the focused diagnostics suite passes, the full existing suite passes,
and the Windows build succeeds without native-asset or `pdfrx` compilation
errors. Treat any failure as evidence to investigate; do not change diagnostic
source or tests without user-provided compiler or test output identifying the
defect.

## Source-level privacy and architecture review

Run these non-Flutter checks from the repository root:

```text
rg -n "clarixLog|ReaderDiagnosticsRecorder" lib/src/features/reader_diagnostics
rg -n "filePath|documentText|modelId|PdfViewerController.*=|\.value\s*=|zoomOnLocalPosition|handlePointerSignalEvent" lib/src/features/reader_diagnostics
```

Review the matches, rather than treating every `.value =` assignment as a
failure: notifier state in the recorder and UI is expected. Confirm that logger
calls contain event JSON or local diagnostic errors only; no PDF path, document
text, model ID, title, or document content is logged or exported. Confirm that
the export metadata contains only capacity/count/truncation values and that
every controller snapshot serializes a typed `nearBoundary` boolean. Confirm
that there is no `PdfViewerController` write, camera zoom/pan call, or forwarded
pointer-signal handler in the diagnostic code. Finally, inspect
`stock_pdfrx_screen.dart` and confirm it has neither a
`ReaderDiagnosticsRecorder` nor pointer handlers, and uses default
`PdfViewerParams`.

## Final verification checklist

- [ ] The diagnostics hub is the startup screen and normal Clarix is one click away.
- [ ] Stock viewer opens the local PDF with default `PdfViewerParams` and no diagnostic handlers.
- [ ] Instrumented events contain raw pointer/focal observations, converted viewer/document coordinates, scale/pan, and before/after camera state through `clarixLog`.
- [ ] Cyan cursor and amber focal crosshairs are visibly independent.
- [ ] Pointer lab works without loading `pdfrx` or a PDF.
- [ ] Recorder/UI work remains bounded; every accepted batch reports zero
      evictions and `truncated: false`; exported JSON has no path, title, text,
      model, or document content.
- [ ] Diagnostics do not modify the `PdfViewerController` camera.
- [ ] Complete user-provided format, analysis, test, and Windows-build outputs are clean.
- [ ] The completed comparison distinguishes Flutter input, stock `pdfrx`, and Clarix observation behavior.

## Final evidence table

Complete this table before declaring the diagnostic run complete. Reference the
saved artifact, log, screenshot, or pasted complete command output in **Actual
evidence/output reference**. Do not mark a gate as passed based on an expected
result or a partial output.

| Gate | Required evidence | Actual evidence/output reference | Pass/fail status |
| --- | --- | --- | --- |
| Diagnostics hub and workspace access | Startup shows **Reader diagnostics**; **Open workspace** reaches normal Clarix in one click and Back returns to the hub. |  | ☐ Pass ☐ Fail |
| Stock viewer baseline | Stock viewer opens the selected local PDF with default `PdfViewerParams`, no recorder, and no diagnostic pointer handlers. |  | ☐ Pass ☐ Fail |
| Instrumented observation coverage | Instrumented JSON/log evidence includes raw pointer and focal data, converted viewer/document coordinates where available, scale/pan, and before/after camera state through `clarixLog`. |  | ☐ Pass ☐ Fail |
| Crosshair independence | Observation from the instrumented viewer shows the cyan cursor and amber focal crosshairs remain visually independent. |  | ☐ Pass ☐ Fail |
| Stock/instrumented five-location manual comparison | Completed C, TL, TR, BL, and BR matrix for the same PDF, page, device, and fit-width baseline; corner gestures used hidden chrome and each location has ten zoom-ins and ten zoom-outs crossing the threshold plus a complete ordered, non-truncated instrumented JSON batch set. |  | ☐ Pass ☐ Fail |
| Pointer-lab result | Completed equivalent C, TL, TR, BL, and BR lab sequence without loading `pdfrx` or a PDF; corner gestures used hidden overlays, exports are complete and non-truncated, and the result explicitly states whether the amber focal marker jumps while the cyan cursor remains stable. |  | ☐ Pass ☐ Fail |
| Recorder bounds and export privacy | Source/manual evidence confirms capacity remains at most 500; panel/export eviction counts agree; every accepted batch has zero evictions and `truncated: false`; JSON contains no path, title, text, model, or document content. |  | ☐ Pass ☐ Fail |
| Privacy and architecture source checks | Complete output of both required `rg` commands, classification of expected notifier assignments, and inspection confirming no sensitive logger fields, controller camera writes, zoom/pan calls, or forwarded pointer signals; stock screen has no recorder or pointer handlers. |  | ☐ Pass ☐ Fail |
| Formatter | Complete output of `dart format --output=none --set-exit-if-changed lib/src/features/reader_diagnostics test/reader_diagnostics lib/src/app.dart`; if it changed files, include the formatted diff and rerun output. |  | ☐ Pass ☐ Fail |
| Static analysis | Complete output of `flutter analyze` with no issues. |  | ☐ Pass ☐ Fail |
| Focused diagnostics tests | Complete output of `flutter test test/reader_diagnostics` with all focused diagnostics tests passing. |  | ☐ Pass ☐ Fail |
| Full test suite | Complete output of `flutter test` with the existing suite passing. |  | ☐ Pass ☐ Fail |
| Windows build | Complete output of `flutter build windows` showing success and no native-asset or `pdfrx` compilation errors. |  | ☐ Pass ☐ Fail |
| Final diagnosis | A written diagnosis links the five-location comparison, pointer-lab result, JSON exports, environment record, and source checks to a conclusion that distinguishes Flutter input, stock `pdfrx`, and Clarix workspace behavior. |  | ☐ Pass ☐ Fail |
