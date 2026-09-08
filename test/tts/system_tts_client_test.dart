import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses name/locale pairs and skips malformed entries', () {
    final List<SystemTtsVoice> voices = parseSystemTtsVoices(<dynamic>[
      <String, String>{'name': 'Karen', 'locale': 'en-AU'},
      <String, String>{'name': 'Daniel', 'locale': 'en-GB'},
      <String, String>{'name': 'NoLocale'},
      'not a map',
    ]);

    expect(voices, hasLength(2));
    expect(voices[0].name, 'Karen');
    expect(voices[0].locale, 'en-AU');
    expect(voices[1].name, 'Daniel');
  });

  test('returns an empty list for non-list input', () {
    expect(parseSystemTtsVoices('unexpected'), isEmpty);
    expect(parseSystemTtsVoices(null), isEmpty);
  });
}
