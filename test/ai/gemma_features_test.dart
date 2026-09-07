import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('Gemma 4 E4B Features tests', () {
    test('GemmaSimulationService parses formula schemas and evaluates values', () {
      final service = GemmaSimulationService();
      final formulas = service.parseFormulasFromJson('Sample physics document text');

      expect(formulas, isNotEmpty);
      expect(formulas.first.formulaName, contains('Einstein'));
      
      final result = service.evaluateFormula(formulas.first);
      expect(result, greaterThan(0));
    });

    test('GemmaTimelineService extracts 128K context timeline events', () {
      final service = GemmaTimelineService();
      final events = service.extractChronology('History of project development document text');

      expect(events, isNotEmpty);
      expect(service.activeEventIndex, equals(0));
      expect(service.activeEvent?.title, contains('Initial'));

      service.setActiveEventIndex(1);
      expect(service.activeEventIndex, equals(1));
      expect(service.activeEvent?.title, contains('Multimodal'));
    });

    test('GemmaCognitiveUiService reflows layout and generates bionic reading typography', () {
      final service = GemmaCognitiveUiService();
      const rawText = 'Multi-column\n\nscanned-  document text layout';

      final reflowed = service.reflowLayout(rawText);
      expect(reflowed, isNotEmpty);

      final bionic = service.generateBionicReadingText('Cognitive UI Bionic Speed Reading');
      expect(bionic, contains('**Cogni**tive'));
      expect(bionic, contains('**Bio**nic'));
    });

    test('GemmaAuditorService audits document for logical fallacies and bias', () {
      final service = GemmaAuditorService();
      final fallacies = service.auditDocumentBiasAndFallacies('Document text containing logical claims');

      expect(fallacies, isNotEmpty);
      final types = fallacies.map((f) => f.fallacyType).toList();
      expect(types, contains('Hasty Generalization'));
      expect(types, contains('False Cause (Post Hoc)'));
    });

    test('VoiceCopilotService processes spoken document copilot commands', () {
      final service = VoiceCopilotService();

      final res1 = service.processVoiceCommand('Summarize page 4');
      expect(res1.actionKind, equals(VoiceActionKind.summarizePage));
      expect(res1.targetPage, equals(4));

      final res2 = service.processVoiceCommand('Where is the indemnity clause?');
      expect(res2.actionKind, equals(VoiceActionKind.findClause));
      expect(res2.replyText, contains('Indemnity'));
    });
  });
}
