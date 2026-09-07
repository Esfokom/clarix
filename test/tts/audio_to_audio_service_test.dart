import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/tts/tts.dart';

void main() {
  group('AudioToAudioService tests', () {
    test('initial state is idle', () {
      final tts = KittenTtsService();
      final audioService = AudioToAudioService(ttsService: tts);

      expect(audioService.state, equals(AudioInteractionState.idle));
      expect(audioService.isActive, isFalse);
      expect(audioService.lastUserTranscript, isEmpty);
      expect(audioService.lastAiResponse, isEmpty);
    });

    test('updates STT base URL', () {
      final tts = KittenTtsService();
      final audioService = AudioToAudioService(ttsService: tts);

      audioService.updateSttBaseUrl('http://127.0.0.1:8880/');
      expect(audioService.isActive, isFalse);
    });
  });
}
