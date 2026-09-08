import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('defaults to kittenSherpa with no active model or system voice', () async {
    final TtsPreferencesStore store = TtsPreferencesStore(SharedPreferencesAsync());
    expect(await store.readActiveEngine(), TtsEngineKind.kittenSherpa);
    expect(await store.readActiveModelId(), isNull);
    expect(await store.readSystemVoiceName(), isNull);
    expect(await store.readSystemVoiceLocale(), isNull);
  });

  test('round-trips engine, model id, and system voice', () async {
    final TtsPreferencesStore store = TtsPreferencesStore(SharedPreferencesAsync());

    await store.saveActiveEngine(TtsEngineKind.system);
    expect(await store.readActiveEngine(), TtsEngineKind.system);

    await store.saveActiveModelId('vits-piper-en_US-amy-low-int8');
    expect(await store.readActiveModelId(), 'vits-piper-en_US-amy-low-int8');

    await store.saveSystemVoice(name: 'Karen', locale: 'en-AU');
    expect(await store.readSystemVoiceName(), 'Karen');
    expect(await store.readSystemVoiceLocale(), 'en-AU');
  });
}
