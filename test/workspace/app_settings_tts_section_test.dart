import 'package:clarix/src/features/tts/application/tts_providers.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/app_settings_tts_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Avoids any real dart:io File access in this widget test — automated
/// widget-test pumping doesn't service real IO callbacks outside
/// `tester.runAsync`, so a real [TtsModelStore] would hang.
class _FakeTtsModelStore extends TtsModelStore {
  @override
  Future<bool> isInstalled(TtsModelSpec spec) async => false;
}

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

  testWidgets('shows all three catalog voice packs and switches to System voice', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsModelStoreProvider.overrideWithValue(_FakeTtsModelStore()),
          systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TtsSettingsSection()),
        ),
      ),
    );
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Kitten (nano, int8) · 31MB'), findsOneWidget);
    expect(find.text('Piper — Amy (US) · 21MB'), findsOneWidget);
    expect(find.text('Piper — Alan (UK) · 21MB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts-engine-system')));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Karen (en-AU)'), findsOneWidget);
  });
}
