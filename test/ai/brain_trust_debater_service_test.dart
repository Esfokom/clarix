import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/application/brain_trust_debater_service.dart';

void main() {
  group('BrainTrustDebaterService tests', () {
    late BrainTrustDebaterService service;

    setUp(() {
      service = BrainTrustDebaterService(
        ollamaEndpoint: 'http://127.0.0.1:51935', // mock unreachable port for deterministic fallback execution
      );
    });

    test('runPanelDebate synthesizes multi-document debate session across expert personas', () async {
      final docTexts = {
        'Q3_Financials.pdf': 'Revenue grew by 34% with strong expansion margins in Q3.',
        'Audit_Risk_Report.pdf': 'Omitted disclosures regarding operational liabilities and regulatory risks.',
      };

      final session = await service.runPanelDebate(
        topic: 'Q3 Financial Expansion vs Regulatory Risk',
        documentTexts: docTexts,
      );

      expect(session.topic, equals('Q3 Financial Expansion vs Regulatory Risk'));
      expect(session.documentTitles, containsAll(['Q3_Financials.pdf', 'Audit_Risk_Report.pdf']));
      expect(session.consensusSummary, isNotEmpty);
      expect(session.turns, hasLength(greaterThanOrEqualTo(4)));

      final roles = session.turns.map((t) => t.role).toSet();
      expect(roles, contains(PanelPersonaRole.optimist));
      expect(roles, contains(PanelPersonaRole.skeptic));
      expect(roles, contains(PanelPersonaRole.methodologist));
      expect(roles, contains(PanelPersonaRole.moderator));
    });

    test('askPanelQuestion appends follow-up moderator response turn to active session', () async {
      final docTexts = {
        'Q3_Financials.pdf': 'Revenue grew by 34% with strong expansion margins.',
      };

      await service.runPanelDebate(
        topic: 'Growth Strategy',
        documentTexts: docTexts,
      );

      final initialTurnCount = service.currentSession!.turns.length;

      final turn = await service.askPanelQuestion('What is the recommended risk cap threshold?');

      expect(turn.personaName, equals('Moderator'));
      expect(turn.statement, contains('recommended risk cap threshold'));
      expect(service.currentSession!.turns.length, equals(initialTurnCount + 1));
    });
  });
}
