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
}
