import 'package:clarix/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recorder evicts oldest records at capacity', () {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      capacity: 3,
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);

    for (int index = 0; index < 5; index++) {
      recorder.record(
        source: ReaderDiagnosticSource.instrumentedPdfrx,
        type: ReaderDiagnosticEventType.pointerMove,
      );
    }

    expect(
      recorder.events.value.map((ReaderDiagnosticEvent event) => event.sequence),
      <int>[3, 4, 5],
    );
  });

  test('pause blocks records and clear resets the visible buffer', () {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);

    recorder.paused.value = true;
    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.scaleStart,
    );
    expect(recorder.events.value, isEmpty);

    recorder.paused.value = false;
    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.scaleStart,
    );
    recorder.clear();

    expect(recorder.events.value, isEmpty);
  });

  test('hover is sampled but scale updates are retained', () {
    int micros = 0;
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      nowMicros: () => micros,
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);

    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.pointerHover,
    );
    micros = 10 * 1000;
    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.pointerHover,
    );
    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.scaleUpdate,
    );

    expect(recorder.events.value.length, 2);
  });

  test('recorder clamps oversized capacities to the hard maximum', () {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      capacity: 501,
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);

    for (int index = 0; index < 501; index++) {
      recorder.record(
        source: ReaderDiagnosticSource.instrumentedPdfrx,
        type: ReaderDiagnosticEventType.pointerMove,
      );
    }

    expect(recorder.capacity, 500);
    expect(recorder.events.value.length, 500);
    expect(recorder.events.value.first.sequence, 2);
  });

  test('recorder rejects non-positive capacities', () {
    expect(
      () => ReaderDiagnosticsRecorder(capacity: 0, logSink: (_) {}),
      throwsArgumentError,
    );
    expect(
      () => ReaderDiagnosticsRecorder(capacity: -1, logSink: (_) {}),
      throwsArgumentError,
    );
  });

  test('initial recorder buffer is immutable', () {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);

    expect(
      () => recorder.events.value.add(_testEvent()),
      throwsUnsupportedError,
    );
  });

  test('cleared recorder buffer is immutable', () {
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: (_) {},
    );
    addTearDown(recorder.dispose);
    recorder.record(
      source: ReaderDiagnosticSource.instrumentedPdfrx,
      type: ReaderDiagnosticEventType.pointerMove,
    );
    recorder.clear();

    expect(
      () => recorder.events.value.add(_testEvent()),
      throwsUnsupportedError,
    );
  });

  test('recorder logger excludes raw source and note values', () {
    final List<String> logged = <String>[];
    final ReaderDiagnosticsRecorder recorder = ReaderDiagnosticsRecorder(
      logSink: logged.add,
    );
    addTearDown(recorder.dispose);
    const String unsafeValue = r'C:\private\patient-report.pdf';

    recorder.record(
      source: ReaderDiagnosticSource.fromRaw(unsafeValue),
      type: ReaderDiagnosticEventType.viewerError,
      note: unsafeValue,
    );

    expect(logged.single, isNot(contains(unsafeValue)));
    expect(logged.single, contains('"source":"unknown"'));
    expect(logged.single, isNot(contains('"note":"')));
  });
}

ReaderDiagnosticEvent _testEvent() => ReaderDiagnosticEvent(
  sequence: 1,
  elapsedMicros: 0,
  source: ReaderDiagnosticSource.instrumentedPdfrx,
  type: ReaderDiagnosticEventType.pointerMove,
);
