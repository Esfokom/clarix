import 'package:clarix/src/features/ai/domain/local_model_profile.dart';
import 'package:clarix/src/features/ai/infrastructure/local_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test(
    'persists downloaded local model metadata separately from remote profiles',
    () async {
      final LocalModelStore store = LocalModelStore(SharedPreferencesAsync());
      final LocalModelProfile model = LocalModelProfile.gemma4(
        id: 'local-gemma-4-e2b',
        label: 'Gemma 4 E2B',
        modelFileName: 'gemma-4-E2B-it.litertlm',
      );

      await store.save(model);

      expect(await store.readAll(), <LocalModelProfile>[model]);
    },
  );

  test('removes metadata when a local model is deleted', () async {
    final LocalModelStore store = LocalModelStore(SharedPreferencesAsync());
    final LocalModelProfile model = LocalModelProfile.gemma4(
      id: 'local-gemma-4-e2b',
      label: 'Gemma 4 E2B',
      modelFileName: 'gemma-4-E2B-it.litertlm',
    );
    await store.save(model);

    await store.delete(model.id);

    expect(await store.readAll(), isEmpty);
  });

  test(
    'restores a supported model found in Flutter Gemma at startup',
    () async {
      final LocalModelStore store = LocalModelStore(SharedPreferencesAsync());
      final LocalModelProfile model = LocalModelProfile.gemma4(
        id: 'local-gemma-4-e2b',
        label: 'Gemma 4 E2B (Local)',
        modelFileName: 'gemma-4-E2B-it.litertlm',
      );

      final List<LocalModelProfile> available = await store.reconcile(
        supportedProfiles: <LocalModelProfile>[model],
        isInstalled: (LocalModelProfile profile) async => profile == model,
      );

      expect(available, <LocalModelProfile>[model]);
      expect(await store.readAll(), <LocalModelProfile>[model]);
    },
  );

  test(
    'removes stale metadata when the local file is no longer installed',
    () async {
      final LocalModelStore store = LocalModelStore(SharedPreferencesAsync());
      final LocalModelProfile model = LocalModelProfile.gemma4(
        id: 'local-gemma-4-e2b',
        label: 'Gemma 4 E2B (Local)',
        modelFileName: 'gemma-4-E2B-it.litertlm',
      );
      await store.save(model);

      final List<LocalModelProfile> available = await store.reconcile(
        supportedProfiles: <LocalModelProfile>[model],
        isInstalled: (_) async => false,
      );

      expect(available, isEmpty);
      expect(await store.readAll(), isEmpty);
    },
  );
}
