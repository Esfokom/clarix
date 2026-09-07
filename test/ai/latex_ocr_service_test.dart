import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('LatexOcrService tests', () {
    test('initial state is idle with default endpoint', () {
      final service = LatexOcrService();

      expect(service.state, equals(LatexOcrState.idle));
      expect(service.isProcessing, isFalse);
      expect(service.lastLatexResult, isEmpty);
      expect(service.visionEndpoint, equals('http://127.0.0.1:11434'));
    });

    test('updates vision endpoint correctly', () {
      final service = LatexOcrService();
      service.updateVisionEndpoint('http://localhost:8880///');

      expect(service.visionEndpoint, equals('http://localhost:8880'));
    });

    test('parses math text tokens to LaTeX fractions and square roots', () {
      final service = LatexOcrService();
      final result = service.parseTextToLatex('sqrt(x + 1) / (y - 2)');

      expect(result, contains(r'\sqrt{x + 1}'));
      expect(result, contains(r'\frac{'));
      expect(service.state, equals(LatexOcrState.completed));
    });

    test('parses integrals, summations, and Greek symbols', () {
      final service = LatexOcrService();
      final result = service.parseTextToLatex('int 0 to infinity alpha * x^2 dx');

      expect(result, contains(r'\int_{0}^{\infty}'));
      expect(result, contains(r'\alpha'));
      expect(result, contains(r'\times'));
      expect(result, contains(r'x^{2}'));
      expect(service.state, equals(LatexOcrState.completed));
    });

    test('fallback math formula returned on invalid/unavailable image bytes', () async {
      final service = LatexOcrService(visionEndpoint: 'http://127.0.0.1:9999');
      final result = await service.parseImageToLatex(
        Uint8List.fromList([0, 1, 2, 3]),
        fallbackText: 'alpha / beta',
      );

      expect(result, contains(r'\alpha'));
      expect(result, contains(r'\frac{'));
      expect(service.state, equals(LatexOcrState.completed));
    });
  });
}
