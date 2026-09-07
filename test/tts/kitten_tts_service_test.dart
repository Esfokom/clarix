import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/tts/tts.dart';

void main() {
  group('KittenTtsService tests', () {
    test('initial state is idle with default voice', () {
      final tts = KittenTtsService();
      expect(tts.state, equals(KittenTtsState.idle));
      expect(tts.selectedVoiceId, equals('kitten_female_1'));
      expect(tts.speed, equals(1.0));
      expect(tts.isSpeaking, isFalse);
    });

    test('updates voice and speed', () {
      final tts = KittenTtsService();
      tts.setVoice('kitten_male_1');
      expect(tts.selectedVoiceId, equals('kitten_male_1'));

      tts.setSpeed(1.5);
      expect(tts.speed, equals(1.5));
    });

    test('updates base url', () {
      final tts = KittenTtsService();
      tts.updateBaseUrl('http://127.0.0.1:5000/');
      expect(tts.baseUrl, equals('http://127.0.0.1:5000'));
    });
  });
}
