import 'dart:io';

import 'package:clarix/src/features/tts/application/tts_providers.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_catalog.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeSystemTtsClient implements SystemTtsClient {
  @override
  Future<List<SystemTtsVoice>> getVoices() async => const <SystemTtsVoice>[
    SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
  ];
  @override
  Future<void> setVoice(SystemTtsVoice voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void onComplete(void Function() callback) {}
  @override
  void onError(void Function(Object error) callback) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('build() loads system voices and defaults to the catalog default model', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_notifier_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final ProviderContainer container = ProviderContainer(
      overrides: [
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(ttsNotifierProvider.future);
    expect(state.activeEngine, TtsEngineKind.kittenSherpa);
    expect(state.activeModelId, isNull);
    expect(state.availableSystemVoices, hasLength(1));
    expect(state.availableSystemVoices.single.name, 'Karen');
  });

  test('setActiveModel persists selection and is reflected in state', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_notifier_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final ProviderContainer container = ProviderContainer(
      overrides: [
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ttsNotifierProvider.future);

    await container.read(ttsNotifierProvider.notifier).setActiveModel(
      TtsModelCatalog.piperAmy,
    );

    final state = container.read(ttsNotifierProvider).requireValue;
    expect(state.activeModelId, TtsModelCatalog.piperAmy.id);

    final SharedPreferencesAsync prefs = SharedPreferencesAsync();
    expect(
      await prefs.getString('clarix.tts.active_model_id'),
      TtsModelCatalog.piperAmy.id,
    );
  });

  test('setActiveEngine to system persists and is reflected in state', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_notifier_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final ProviderContainer container = ProviderContainer(
      overrides: [
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ttsNotifierProvider.future);

    await container.read(ttsNotifierProvider.notifier).setActiveEngine(
      TtsEngineKind.system,
    );

    expect(
      container.read(ttsNotifierProvider).requireValue.activeEngine,
      TtsEngineKind.system,
    );
  });
}
