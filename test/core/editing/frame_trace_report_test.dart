import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/editing_foundation/frame_trace_report.dart';

void main() {
  test('frame trace report calculates tail and budget metrics', () {
    final report = buildFrameTraceReport(
      jsonDecode('''
        {
          "schemaVersion": 1,
          "traceEvents": [
            {"name":"Frame","ph":"X","dur":8000},
            {"name":"Frame","ph":"X","dur":12000},
            {"name":"Frame","ph":"X","dur":20000}
          ]
        }
      ''')
          as Map<String, Object?>,
    );

    expect(report.frameCount, 3);
    expect(report.p95Micros, 20000);
    expect(report.maxMicros, 20000);
    expect(report.framesOverBudget, 1);
  });

  test('frame trace command rejects unsupported schema', () async {
    final directory = await Directory.systemTemp.createTemp('clarix-frame-');
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/input.json')
      ..writeAsStringSync('{"schemaVersion":2,"traceEvents":[]}');
    final output = File('${directory.path}/output.json');

    expect(
      () => runFrameTraceReport(input.path, output.path),
      throwsA(isA<FormatException>()),
    );
  });
}
