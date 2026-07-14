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
        source: 'lab',
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
      source: 'lab',
      type: ReaderDiagnosticEventType.scaleStart,
    );
    expect(recorder.events.value, isEmpty);

    recorder.paused.value = false;
    recorder.record(
      source: 'lab',
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
      source: 'lab',
      type: ReaderDiagnosticEventType.pointerHover,
    );
    micros = 10 * 1000;
    recorder.record(
      source: 'lab',
      type: ReaderDiagnosticEventType.pointerHover,
    );
    recorder.record(
      source: 'lab',
      type: ReaderDiagnosticEventType.scaleUpdate,
    );

    expect(recorder.events.value.length, 2);
  });
}
