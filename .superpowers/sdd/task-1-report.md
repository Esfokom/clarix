# Task 1: Diagnostic Event Model, Math, and Recorder

## Status

Implemented and source-level reviewed. Runtime test execution is intentionally
deferred because the task explicitly prohibits all `flutter` and `dart`
commands.

## TDD record

The focused diagnostic tests were written before the Task 1 production files:

- `test/reader_diagnostics/reader_diagnostic_event_test.dart`
- `test/reader_diagnostics/reader_diagnostics_recorder_test.dart`

The required RED/GREEN command executions were not performed. This is the
intentional exception forced by the user constraint, not a claim that the tests
pass.

## Delivered

- Immutable diagnostic point, viewer snapshot, event type, and event models.
  Event serialization includes only declared diagnostic fields and has no
  document path, title, text, or model fields.
- `isFiniteOffset`, `matrixTranslation`, and anchor-preserving affine
  translation helpers.
- A `ValueNotifier`-backed recorder with a 500-event default capacity, oldest
  event eviction, pause/clear/dispose controls, 50 ms hover sampling, JSON
  export, and default `clarixLog.t` output.

## Source-level verification performed

- Reviewed all five Task 1 source and test files after implementation.
- Confirmed the existing package configuration resolves `vector_math`, used by
  the `Matrix4` interface.
- Ran `git diff --check`; it produced no whitespace errors.
- Confirmed no Flutter or Dart commands were run.

## User verification remaining

Run exactly:

```text
flutter test test/reader_diagnostics/reader_diagnostic_event_test.dart test/reader_diagnostics/reader_diagnostics_recorder_test.dart
```

Expected result: all diagnostic model, math, and recorder tests pass.

## Concerns

No implementation blockers found. The focused Flutter tests remain unexecuted,
so runtime compilation and test status are not confirmed in this report.

## Review fixes

- Enforced a hard maximum recorder capacity of 500, retained smaller injected
  capacities, and reject non-positive capacities with `ArgumentError`.
- Replaced raw source strings with `ReaderDiagnosticSource`; raw values resolve
  only to allowlisted identifiers or `unknown`. Event notes are allowlisted at
  construction, so document paths, titles, text, and model identifiers cannot
  reach JSON exports or the logger sink. The approved
  `readerDiagnosticNearBoundaryNote` (`near_boundary`) remains available for
  Task 3.
- Normalized non-finite event scale and every snapshot numeric field to `null`
  before serialization, so `jsonEncode` and recorder export remain safe.
- Made initial and cleared event buffers unmodifiable.
- Added focused tests for capacity bounds, immutable buffers, privacy in event
  JSON and recorder logs, non-finite serialization, and the Task 3 note.

### Cross-task ownership

`controllerSnapshot` coalescing is intentionally not implemented in Task 1.
Task 3 owns one-per-rendered-frame scheduling at the controller listener via
`SchedulerBinding`; that behavior is therefore not verifiable in this task.

### Verification pending

No Flutter or Dart command was run. The user should run:

```text
flutter test test/reader_diagnostics/reader_diagnostic_event_test.dart test/reader_diagnostics/reader_diagnostics_recorder_test.dart
```

## Final device-kind privacy fix

- Replaced the raw `String? deviceKind` event and recorder API with
  `ReaderDiagnosticDeviceKind`. The allowlist contains `unknown`, `mouse`,
  `touch`, `stylus`, `invertedStylus`, and `trackpad`; `fromRaw` maps every
  unrecognized value to `unknown` before event construction.
- Event JSON, recorder export JSON, and logger output now serialize only the
  enum's fixed JSON values. Focused tests cover path-like, document-text-like,
  and model-like raw inputs plus normal device-kind serialization.

### Final verification pending

No Flutter or Dart command was run. The user should run:

```text
flutter test test/reader_diagnostics/reader_diagnostic_event_test.dart test/reader_diagnostics/reader_diagnostics_recorder_test.dart
```