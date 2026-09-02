import 'package:clarix/src/features/ai/application/ai_runtime_service.dart';
import 'package:clarix/src/features/ai/domain/ai_provider.dart';
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

  test(
    'checks native runtime availability before testing a provider',
    () async {
      var checkedRuntime = false;
      final AiRuntimeService service = AiRuntimeService(
        providerProfiles: ProviderProfileStore(
          preferences: SharedPreferencesAsync(),
          secretStore: _MemorySecretStore(),
        ),
        localModels: LocalModelStore(SharedPreferencesAsync()),
        localRuntime: LocalModelRuntime(gateway: _NoopLocalGateway()),
        ensureNativeReady: () async {
          checkedRuntime = true;
          throw StateError('Native runtime is unavailable.');
        },
      );

      await expectLater(
        service.testProvider(_profile, 'sk-test'),
        throwsA(isA<StateError>()),
      );

      expect(checkedRuntime, isTrue);
    },
  );
}

class _NoopLocalGateway implements LocalModelGateway {
  @override
  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
  }) => const Stream<String>.empty();
  @override
  Future<void> install(LocalModelProfile profile) async {}
}

final AiProviderProfile _profile = AiProviderProfile.create(
  id: 'test-provider',
  label: 'Test provider',
  baseUrl: 'https://example.invalid/v1',
  modelId: 'test-model',
  shareRetrievedPassages: false,
);

class _MemorySecretStore implements ProviderSecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}
}
