import 'package:clarix/src/features/workspace/domain/ai_provider.dart';
import 'package:clarix/src/features/workspace/infrastructure/provider_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('profile normalizes a v1 chat completion endpoint', () {
    final AiProviderProfile profile = AiProviderProfile.create(
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1/',
      modelId: 'gpt-5',
      shareRetrievedPassages: true,
    );

    expect(
      profile.chatCompletionsUri.toString(),
      'https://api.openai.com/v1/chat/completions',
    );
  });

  test(
    'profile store persists metadata but keeps key in secret storage',
    () async {
      final _MemorySecretStore secrets = _MemorySecretStore();
      final ProviderProfileStore store = ProviderProfileStore(
        preferences: SharedPreferencesAsync(),
        secretStore: secrets,
      );
      final AiProviderProfile profile = AiProviderProfile.create(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        modelId: 'gpt-5',
        shareRetrievedPassages: true,
      );

      await store.saveProfile(profile, apiKey: 'sk-secret');

      expect(await store.readProfiles(), <AiProviderProfile>[profile]);
      expect(await store.readApiKey(profile.id), 'sk-secret');
      expect(secrets.values, <String, String>{
        'clarix.provider.openai.api_key': 'sk-secret',
      });
    },
  );

  test('provider store persists the default profile independently', () async {
    final ProviderProfileStore store = ProviderProfileStore(
      preferences: SharedPreferencesAsync(),
      secretStore: _MemorySecretStore(),
    );
    final AiProviderProfile openAi = AiProviderProfile.create(
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      modelId: 'gpt-5',
      shareRetrievedPassages: true,
    );
    final AiProviderProfile other = AiProviderProfile.create(
      id: 'other',
      label: 'Other',
      baseUrl: 'https://api.example.com/v1',
      modelId: 'example-model',
      shareRetrievedPassages: false,
    );

    await store.saveProfile(openAi);
    await store.saveProfile(other);
    await store.saveDefaultProfileId(other.id);

    expect(await store.readDefaultProfileId(), other.id);
  });

  test(
    'deleting the default profile clears default selection and secret',
    () async {
      final _MemorySecretStore secrets = _MemorySecretStore();
      final ProviderProfileStore store = ProviderProfileStore(
        preferences: SharedPreferencesAsync(),
        secretStore: secrets,
      );
      final AiProviderProfile openAi = AiProviderProfile.create(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        modelId: 'gpt-5',
        shareRetrievedPassages: true,
      );

      await store.saveProfile(openAi, apiKey: 'sk-secret');
      await store.saveDefaultProfileId(openAi.id);
      await store.deleteProfile(openAi.id);

      expect(await store.readDefaultProfileId(), isNull);
      expect(await store.readApiKey(openAi.id), isNull);
    },
  );
}

class _MemorySecretStore implements ProviderSecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
