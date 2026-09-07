import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:clarix/src/features/reader/domain/pdf_night_mode.dart';

void main() {
  group('PdfNightMode domain tests', () {
    test('PdfNightMode labels and icons match expectations', () {
      expect(PdfNightMode.off.label, equals('Normal Light'));
      expect(PdfNightMode.inverted.label, equals('True Dark (Inverted)'));
      expect(PdfNightMode.smartDark.label, equals('Smart Dark (Warm)'));

      expect(PdfNightMode.off.icon, equals(Icons.light_mode_outlined));
      expect(PdfNightMode.inverted.icon, equals(Icons.dark_mode_outlined));
      expect(PdfNightMode.smartDark.icon, equals(Icons.nightlight_round));
    });

    test('PdfNightMode produces expected ColorFilter matrices', () {
      expect(PdfNightMode.off.colorFilter, isNull);

      final invertedFilter = PdfNightMode.inverted.colorFilter;
      expect(invertedFilter, isNotNull);
      expect(invertedFilter, isA<ColorFilter>());

      final smartDarkFilter = PdfNightMode.smartDark.colorFilter;
      expect(smartDarkFilter, isNotNull);
      expect(smartDarkFilter, isA<ColorFilter>());
    });
  });
}
