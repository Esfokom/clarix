import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

final class RasterDiffReport {
  const RasterDiffReport({
    required this.width,
    required this.height,
    required this.changedPixels,
    required this.changedRatio,
    required this.meanAbsoluteChannelDelta,
    required this.maximumChannelDelta,
  });

  final int width;
  final int height;
  final int changedPixels;
  final double changedRatio;
  final double meanAbsoluteChannelDelta;
  final int maximumChannelDelta;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': 1,
    'width': width,
    'height': height,
    'changedPixels': changedPixels,
    'changedRatio': changedRatio,
    'meanAbsoluteChannelDelta': meanAbsoluteChannelDelta,
    'maximumChannelDelta': maximumChannelDelta,
  };
}

RasterDiffReport compareRasterBytes(
  Uint8List expectedBytes,
  Uint8List actualBytes,
) {
  final expected = image.decodeImage(expectedBytes);
  final actual = image.decodeImage(actualBytes);
  if (expected == null || actual == null) {
    throw const FormatException('Both inputs must be decodable images');
  }
  if (expected.width != actual.width || expected.height != actual.height) {
    throw const FormatException('Raster dimensions do not match');
  }

  var changed = 0;
  var channelDeltaTotal = 0;
  var maximumDelta = 0;
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      final left = expected.getPixel(x, y);
      final right = actual.getPixel(x, y);
      final deltas = <int>[
        (left.r.toInt() - right.r.toInt()).abs(),
        (left.g.toInt() - right.g.toInt()).abs(),
        (left.b.toInt() - right.b.toInt()).abs(),
        (left.a.toInt() - right.a.toInt()).abs(),
      ];
      if (deltas.any((delta) => delta != 0)) changed++;
      for (final delta in deltas) {
        channelDeltaTotal += delta;
        if (delta > maximumDelta) maximumDelta = delta;
      }
    }
  }
  final pixels = expected.width * expected.height;
  return RasterDiffReport(
    width: expected.width,
    height: expected.height,
    changedPixels: changed,
    changedRatio: pixels == 0 ? 0 : changed / pixels,
    meanAbsoluteChannelDelta: pixels == 0
        ? 0
        : channelDeltaTotal / (pixels * 4),
    maximumChannelDelta: maximumDelta,
  );
}

void runRasterDiff(String expectedPath, String actualPath, String outputPath) {
  final report = compareRasterBytes(
    File(expectedPath).readAsBytesSync(),
    File(actualPath).readAsBytesSync(),
  );
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

  final expected = valueAfter('--expected');
  final actual = valueAfter('--actual');
  final output = valueAfter('--output');
  if (expected == null || actual == null || output == null) {
    stderr.writeln(
      'Usage: dart raster_diff.dart --expected a.png --actual b.png --output report.json',
    );
    exitCode = 64;
    return;
  }
  try {
    runRasterDiff(expected, actual, output);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  }
}
