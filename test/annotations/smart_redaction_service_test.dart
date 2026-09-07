import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/annotations/annotations.dart';

void main() {
  group('SmartRedactionService tests', () {
    test('initial state is not scanning', () {
      final service = SmartRedactionService();

      expect(service.isScanning, isFalse);
      expect(service.lastMatches, isEmpty);
    });

    test('scans and detects SSN, email, credit card, phone, and financial data', () {
      final service = SmartRedactionService();
      const text = r'User Name: Jane Smith, SSN: 123-45-6789, Email: jane@example.com, Phone: 555-123-4567, Balance: $4,500.00';

      final matches = service.scanDocumentForPii(text);

      expect(matches, isNotEmpty);
      final categories = matches.map((m) => m.category).toSet();
      expect(categories.contains(RedactionCategory.ssn), isTrue);
      expect(categories.contains(RedactionCategory.email), isTrue);
      expect(categories.contains(RedactionCategory.phone), isTrue);
      expect(categories.contains(RedactionCategory.financial), isTrue);
      expect(categories.contains(RedactionCategory.names), isTrue);
    });

    test('generates blacked-out redacted text output', () {
      final service = SmartRedactionService();
      const text = 'Contact: test@example.com, SSN: 987-65-4321';

      final matches = service.scanDocumentForPii(text);
      final redacted = service.generateRedactedText(text, matches);

      expect(redacted, contains('████████████████'));
      expect(redacted, isNot(contains('test@example.com')));
      expect(redacted, isNot(contains('987-65-4321')));
    });
  });
}
