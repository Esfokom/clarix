import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveFontFamilyLabel', () {
    test('passes a plain family name through', () {
      expect(
        resolveFontFamilyLabel(familyName: 'ArialMT', flags: 0),
        'ArialMT',
      );
    });

    test('strips subset prefixes', () {
      expect(
        resolveFontFamilyLabel(familyName: 'ABCDEF+ArialMT', flags: 0),
        'ArialMT',
      );
      expect(
        resolveFontFamilyLabel(familyName: 'AABBCC+DroidSerif', flags: 0),
        'DroidSerif',
      );
    });

    test('falls back to a base-14 family from descriptor flags', () {
      expect(resolveFontFamilyLabel(familyName: '', flags: 4), 'Symbol');
      expect(resolveFontFamilyLabel(familyName: '', flags: 1), 'Courier New');
      expect(resolveFontFamilyLabel(familyName: '', flags: 2), 'Times New Roman');
      expect(resolveFontFamilyLabel(familyName: '', flags: 0), 'Helvetica');
    });

    test('treats Unknown as a missing family name', () {
      expect(resolveFontFamilyLabel(familyName: 'Unknown', flags: 1), 'Courier New');
    });

    test('flag priority is symbolic, then fixed pitch, then serif', () {
      expect(resolveFontFamilyLabel(familyName: '', flags: 5), 'Symbol');
      expect(resolveFontFamilyLabel(familyName: '', flags: 3), 'Courier New');
    });
  });
}
