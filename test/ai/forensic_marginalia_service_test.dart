import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/application/forensic_marginalia_service.dart';

void main() {
  group('ForensicMarginaliaService tests', () {
    late ForensicMarginaliaService service;

    setUp(() {
      service = ForensicMarginaliaService(
        ollamaEndpoint: 'http://127.0.0.1:51935', // mock unreachable port for deterministic local fallback execution
      );
    });

    test('compareDocuments generates forensic diff report with categorized semantic items', () async {
      const docA = 'Party A agrees to indemnify Party B up to \$1,000,000 for breach of contract.';
      const docB = 'Party A liability cap removed; indemnification capped at \$100,000 for breach of contract.';

      final report = await service.compareDocuments(
        docATitle: 'Contract_v1.pdf',
        docAText: docA,
        docBTitle: 'Contract_v2.pdf',
        docBText: docB,
      );

      expect(report.docATitle, equals('Contract_v1.pdf'));
      expect(report.docBTitle, equals('Contract_v2.pdf'));
      expect(report.overallSimilarity, greaterThan(0.0));
      expect(report.riskLevel, greaterThan(0.0));
      expect(report.items, isNotEmpty);

      final legalItem = report.items.firstWhere((item) => item.category == SemanticDiffCategory.legal);
      expect(legalItem.title, contains('Indemnity'));
      expect(legalItem.riskScore, greaterThan(0.5));
    });

    test('parseMarginaliaScribble interprets margin annotation into actionable command', () async {
      final dummyBytes = List<int>.generate(16, (i) => i);

      final action = await service.parseMarginaliaScribble(
        scribbleImageBytes: Uint8List.fromList(dummyBytes),
        contextPageText: 'Sensitive SSN 000-12-3456 confidential record',
      );

      expect(action.intent, equals(MarginaliaIntent.redact));
      expect(action.actionDescription, contains('redact'));
      expect(service.recentActions, contains(action));
    });

  });
}
