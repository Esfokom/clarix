import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../../../tool/editing_foundation/raster_diff.dart';

void main() {
  test('raster diff reports one changed pixel and channel delta', () {
    final expected = image.Image(width: 2, height: 2);
    final actual = image.Image(width: 2, height: 2);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        expected.setPixelRgba(x, y, 0, 0, 0, 255);
        actual.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
    actual.setPixelRgba(1, 1, 100, 0, 0, 255);

    final report = compareRasterBytes(
      Uint8List.fromList(image.encodePng(expected)),
      Uint8List.fromList(image.encodePng(actual)),
    );
    expect(report.changedPixels, 1);
    expect(report.changedRatio, 0.25);
    expect(report.maximumChannelDelta, 100);
  });

  test('raster diff rejects mismatched dimensions', () {
    final one = image.Image(width: 1, height: 1);
    final two = image.Image(width: 2, height: 1);
    expect(
      () => compareRasterBytes(
        Uint8List.fromList(image.encodePng(one)),
        Uint8List.fromList(image.encodePng(two)),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
