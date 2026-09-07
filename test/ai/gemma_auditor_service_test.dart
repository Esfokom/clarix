import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('GemmaAuditorService tests', () {
    test('audits document for logical fallacies and bias', () {
      final service = GemmaAuditorService();
      final fallacies = service.auditDocumentBiasAndFallacies('Document text containing logical claims');

      expect(fallacies, isNotEmpty);
      final types = fallacies.map((f) => f.fallacyType).toList();
      expect(types, contains('Hasty Generalization'));
      expect(types, contains('False Cause (Post Hoc)'));
    });

    test('handles empty document text for auditing', () {
      final service = GemmaAuditorService();
      final fallacies = service.auditDocumentBiasAndFallacies('');

      expect(fallacies, isEmpty);
      expect(service.isAuditing, isFalse);
    });
  });
}
