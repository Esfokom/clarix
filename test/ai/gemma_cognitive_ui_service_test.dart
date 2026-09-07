import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('GemmaCognitiveUiService tests', () {
    test('reflows layout and generates bionic reading typography', () {
      final service = GemmaCognitiveUiService();
      const rawText = 'Multi-column\n\nscanned-  document text layout';

      final reflowed = service.reflowLayout(rawText);
      expect(reflowed, isNotEmpty);

      final bionic = service.generateBionicReadingText('Cognitive UI Bionic Speed Reading');
      expect(bionic, contains('**Cogni**tive'));
      expect(bionic, contains('**Bio**nic'));
    });

    test('handles empty text input for layout reflow and bionic reading', () {
      final service = GemmaCognitiveUiService();

      expect(service.reflowLayout(''), isEmpty);
      expect(service.generateBionicReadingText(''), isEmpty);
    });
  });
}
