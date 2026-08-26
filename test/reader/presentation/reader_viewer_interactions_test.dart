import 'package:clarix/src/features/reader/presentation/reader_viewer_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('annotation hit testing accepts a typed rectangle predicate', () {
    expect(
      annotationHitAreaContains(const <Rect>[
        Rect.fromLTWH(10, 20, 30, 40),
      ], const Offset(25, 35)),
      isTrue,
    );
  });
}
