import 'dart:convert';
import 'dart:io';

const int frameBudgetMicros = 16667;

final class FrameTraceReport {
  const FrameTraceReport({
    required this.frameCount,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.maxMicros,
    required this.framesOverBudget,
  });

  final int frameCount;
  final int p50Micros;
  final int p95Micros;
  final int p99Micros;
  final int maxMicros;
  final int framesOverBudget;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': 1,
    'frameCount': frameCount,
    'p50Micros': p50Micros,
    'p95Micros': p95Micros,
    'p99Micros': p99Micros,
    'maxMicros': maxMicros,
    'frameBudgetMicros': frameBudgetMicros,
    'framesOverBudget': framesOverBudget,
  };
}

FrameTraceReport buildFrameTraceReport(Map<String, Object?> trace) {
  if (trace['schemaVersion'] != 1) {
    throw const FormatException('Unsupported frame trace schema');
  }
  final events = trace['traceEvents'];
  if (events is! List<Object?>) {
    throw const FormatException('traceEvents must be a list');
  }
  final durations = <int>[];
  for (final event in events) {
    if (event is! Map<String, Object?> ||
        event['name'] != 'Frame' ||
        event['ph'] != 'X') {
      continue;
    }
    final duration = event['dur'];
    if (duration is num && duration >= 0) {
      durations.add(duration.round());
    }
  }
  durations.sort();
  int percentile(double value) {
    if (durations.isEmpty) return 0;
    final index = (value * durations.length).ceil().clamp(1, durations.length);
    return durations[index - 1];
  }

  return FrameTraceReport(
    frameCount: durations.length,
    p50Micros: percentile(.50),
    p95Micros: percentile(.95),
    p99Micros: percentile(.99),
    maxMicros: durations.isEmpty ? 0 : durations.last,
    framesOverBudget: durations
        .where((duration) => duration > frameBudgetMicros)
        .length,
  );
}

void runFrameTraceReport(String inputPath, String outputPath) {
  final decoded = jsonDecode(File(inputPath).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Trace root must be an object');
  }
  final report = buildFrameTraceReport(decoded);
  File(outputPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
    );
}

void main(List<String> arguments) {
  String? valueAfter(String option) {
    final index = arguments.indexOf(option);
    return index >= 0 && index + 1 < arguments.length
        ? arguments[index + 1]
        : null;
  }

  final input = valueAfter('--input');
  final output = valueAfter('--output');
  if (input == null || output == null) {
    stderr.writeln(
      'Usage: dart frame_trace_report.dart --input trace.json --output report.json',
    );
    exitCode = 64;
    return;
  }
  try {
    runFrameTraceReport(input, output);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  }
}
