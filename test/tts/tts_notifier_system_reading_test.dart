import 'dart:async';
import 'dart:io';

import 'package:clarix/src/features/tts/application/tts_providers.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _ScriptedSystemTtsClient implements SystemTtsClient {
  final List<String> spoken = <String>[];
  void Function()? _onComplete;

  @override
  Future<List<SystemTtsVoice>> getVoices() async => const <SystemTtsVoice>[];
  @override
  Future<void> setVoice(SystemTtsVoice voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    // Simulate the platform completing the utterance asynchronously, the
    // same way flutter_tts's completion handler fires.
    scheduleMicrotask(() => _onComplete?.call());
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void onComplete(void Function() callback) => _onComplete = callback;
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

  test('reads all segments via SystemTtsClient and returns to idle', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_system_test_');
    addTearDown(() => tempDir.delete(recursive: true));
    final _ScriptedSystemTtsClient client = _ScriptedSystemTtsClient();

    final ProviderContainer container = ProviderContainer(
      overrides: [
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ttsNotifierProvider.future);

    final notifier = container.read(ttsNotifierProvider.notifier);
    await notifier.setActiveEngine(TtsEngineKind.system);

    await notifier.startReading(
      documentId: 'doc-1',
      segments: const <ReadAloudSegment>[
        ReadAloudSegment(id: 's1', text: 'First sentence.', pageNumber: 1),
        ReadAloudSegment(id: 's2', text: 'Second sentence.', pageNumber: 1),
      ],
      startIndex: 0,
    );
    notifier.finishSegments();

    // Let the microtask-scheduled completions and the internal await chain
    // drain.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(client.spoken, <String>['First sentence.', 'Second sentence.']);
    expect(
      container.read(ttsNotifierProvider).requireValue.playback.status,
      TtsPlaybackStatus.idle,
    );
  });
}
