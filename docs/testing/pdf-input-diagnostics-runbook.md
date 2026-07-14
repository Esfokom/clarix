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
- five JSON exports from the instrumented viewer, one after each location;
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
   visible. The cyan crosshair is the cursor; the amber crosshair is the
   gesture focal point.

The locations below are page-relative, not window- or Events-panel-relative.
For corner locations, measure 20 logical pixels inward from both adjoining
page edges.

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
   Record the visible behavior and the current page/zoom status after the
   twentieth gesture.
2. In the instrumented viewer, press **Clear** in Events before beginning the
   location. Repeat the exact ten zoom-in and ten zoom-out gesture sequence at
   the corresponding page location. Keep the pointer stationary at that
   location while each gesture begins.
3. Verify visually that the cyan cursor and amber focal marker remain
   independently positioned. Note any focal jump, especially to a viewport
   corner, and whether the cursor remained at the intended location.
4. Press **Copy diagnostic JSON** after completing the location. Save the
   clipboard content as `C`, `TL`, `TR`, `BL`, or `BR` without adding any PDF
   identifier. The export is expected to contain raw pointer and scale events,
   focal/cursor positions, converted viewer/document coordinates where
   available, scale/pan, and camera before/after snapshots.

Use this record while running the matrix:

| Location | Stock: 10 in / 10 out | Instrumented visible result | JSON saved | Focal jump/cursor stability |
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
cross the lab's current scale baseline. Clear the Events panel before each
location and copy JSON after it when an event trace is needed.

For every location, explicitly record whether the amber focal marker jumps to
a viewport corner while the cyan cursor stays stable. Also note the local/global
cursor and focal readouts, scale, translation, pan, and detected device kind.

| Location | Amber focal jumps to viewport corner? | Cyan cursor stable? | Lab scale/pan observation | JSON saved (if collected) |
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
there is no `PdfViewerController` write, camera zoom/pan call, or forwarded
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
- [ ] Recorder/UI work remains bounded and exported JSON has no path, title, text, model, or document content.
- [ ] Diagnostics do not modify the `PdfViewerController` camera.
- [ ] Complete user-provided format, analysis, test, and Windows-build outputs are clean.
- [ ] The completed comparison distinguishes Flutter input, stock `pdfrx`, and Clarix observation behavior.
