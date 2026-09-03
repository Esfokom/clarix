import 'package:clarix/src/features/ai/application/ai_runtime_service.dart';
import 'package:clarix/src/features/ai/domain/ai_provider.dart';
import 'package:clarix/src/features/ai/domain/ai_models.dart';
import 'package:clarix/src/features/ai/infrastructure/provider_profile_store.dart';
import 'package:clarix/src/features/ai/infrastructure/local_model_store.dart';
import 'package:clarix/src/features/ai/application/local_model_runtime.dart';
import 'package:clarix/src/features/ai/domain/local_model_profile.dart';
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

  test('tests a remote provider without requiring the Rust runtime', () async {
    var checkedRuntime = false;
    final AiRuntimeService service = AiRuntimeService(
      providerProfiles: ProviderProfileStore(
        preferences: SharedPreferencesAsync(),
        secretStore: _MemorySecretStore(),
      ),
      localModels: LocalModelStore(SharedPreferencesAsync()),
      localRuntime: LocalModelRuntime(gateway: _NoopLocalGateway()),
      remoteGateway: _FakeRemoteGateway(),
      ensureNativeReady: () async {
        checkedRuntime = true;
      },
    );

    await service.testProvider(_profile, 'sk-test');

    expect(checkedRuntime, isFalse);
  });

  test('sends prior conversation turns before the new remote prompt', () async {
    final _CapturingRemoteGateway gateway = _CapturingRemoteGateway();
    final _MemorySecretStore secrets = _MemorySecretStore();
    final ProviderProfileStore profiles = ProviderProfileStore(
      preferences: SharedPreferencesAsync(),
      secretStore: secrets,
    );
    await profiles.saveProfile(_profile, apiKey: 'sk-test');
    final AiRuntimeService service = AiRuntimeService(
      providerProfiles: profiles,
      localModels: LocalModelStore(SharedPreferencesAsync()),
      localRuntime: LocalModelRuntime(gateway: _NoopLocalGateway()),
      remoteGateway: gateway,
    );

    await service.sendPrompt(
      prompt: 'What follows from that?',
      profileId: _profile.id,
      documentSnippets: const <CitationSnippet>[],
      conversationHistory: const <RemoteChatMessage>[
        RemoteChatMessage(role: 'user', content: 'What is the conclusion?'),
        RemoteChatMessage(
          role: 'assistant',
          content: 'The conclusion is positive.',
        ),
      ],
      onToken: (_) {},
    );

    expect(
      gateway.messages.map((RemoteChatMessage item) => item.content),
      <String>[
        'What is the conclusion?',
        'The conclusion is positive.',
        'What follows from that?',
      ],
    );
  });
}

class _NoopLocalGateway implements LocalModelGateway {
  @override
  Future<bool> isInstalled(LocalModelProfile profile) async => false;

  @override
  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
    required List<String> conversationHistory,
  }) => const Stream<String>.empty();
  @override
  Future<void> install(LocalModelProfile profile) async {}
  @override
  Future<void> uninstall(LocalModelProfile profile) async {}
}

class _FakeRemoteGateway implements RemoteChatGateway {
  @override
  Stream<String> stream({
    required AiProviderProfile profile,
    required String apiKey,
    required List<RemoteChatMessage> messages,
  }) => Stream<String>.value('OK');
}

class _CapturingRemoteGateway implements RemoteChatGateway {
  List<RemoteChatMessage> messages = const <RemoteChatMessage>[];

  @override
  Stream<String> stream({
    required AiProviderProfile profile,
    required String apiKey,
    required List<RemoteChatMessage> messages,
  }) {
    this.messages = messages;
    return Stream<String>.value('OK');
  }
}

final AiProviderProfile _profile = AiProviderProfile.create(
  id: 'test-provider',
  label: 'Test provider',
  baseUrl: 'https://example.invalid/v1',
  modelId: 'test-model',
  shareRetrievedPassages: false,
);

class _MemorySecretStore implements ProviderSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}
