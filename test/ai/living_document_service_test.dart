import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('LivingDocumentService tests', () {
    test('detects rain audio scenery from page text', () {
      final service = LivingDocumentService();
      final scenery = service.detectAudioScenery('The heavy rain fell outside the corporate window.');

      expect(scenery, equals(AmbientSceneryType.rain));
      expect(service.currentScenery, equals(AmbientSceneryType.rain));
    });

    test('detects office audio scenery from page text', () {
      final service = LivingDocumentService();
      final scenery = service.detectAudioScenery('Quarterly corporate market reports and business strategy.');

      expect(scenery, equals(AmbientSceneryType.office));
    });

    test('interrogates cropped visual chart image bytes', () async {
      final service = LivingDocumentService(visionEndpoint: 'http://127.0.0.1:9999');
      final result = await service.interrogateChartRegion(
        Uint8List.fromList([0, 1, 2, 3]),
        'What is the percentage drop between Q2 and Q3?',
      );

      expect(result.question, contains('percentage drop'));
      expect(result.analysisText, isNotEmpty);
      expect(result.confidenceScore, greaterThan(0.5));
      expect(service.lastChartResult, isNotNull);
    });
  });
}
