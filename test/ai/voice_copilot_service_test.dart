import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('VoiceCopilotService tests', () {
    test('processes spoken document copilot commands', () {
      final service = VoiceCopilotService();

      final res1 = service.processVoiceCommand('Summarize page 4');
      expect(res1.actionKind, equals(VoiceActionKind.summarizePage));
      expect(res1.targetPage, equals(4));

      final res2 = service.processVoiceCommand('Where is the indemnity clause?');
      expect(res2.actionKind, equals(VoiceActionKind.findClause));
      expect(res2.replyText, contains('Indemnity'));
    });

    test('handles unknown spoken commands gracefully', () {
      final service = VoiceCopilotService();
      final res = service.processVoiceCommand('Hello computer');

      expect(res.actionKind, equals(VoiceActionKind.unknown));
      expect(res.replyText, contains('Hello computer'));
    });
  });
}
