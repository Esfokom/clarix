import 'dart:io';

import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/ai/domain/ai_provider.dart';
import 'package:clarix/src/features/workspace/infrastructure/document_metadata_store.dart';
import 'package:clarix/src/features/ai/infrastructure/provider_profile_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  test(
    'hydrates the persisted default provider and clears it when deleted',
    () async {
      final SharedPreferencesAsync preferences = SharedPreferencesAsync();
      final ProviderProfileStore store = ProviderProfileStore(
        preferences: preferences,
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
      await store.saveProfile(openAi, apiKey: 'sk-openai');
      await store.saveProfile(other, apiKey: 'sk-other');
      await store.saveDefaultProfileId(other.id);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          providerProfileStoreProvider.overrideWithValue(store),
          documentMetadataStoreProvider.overrideWith(
            (Ref ref) async =>
                DocumentMetadataStore(root: Directory.systemTemp),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(workspaceNotifierProvider.future);

      expect(state.aiState.selectedProviderId, other.id);
      expect(state.aiState.providerReady, isTrue);

      await container
          .read(workspaceNotifierProvider.notifier)
          .deleteProvider(other.id);

      expect(
        container
            .read(workspaceNotifierProvider)
            .requireValue
            .aiState
            .selectedProviderId,
        isNull,
      );
      expect(await store.readDefaultProfileId(), isNull);
    },
  );
}

class _MemorySecretStore implements ProviderSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}
