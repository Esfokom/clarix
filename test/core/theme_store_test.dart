import 'package:clarix/src/core/theme_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late SharedPreferencesAsyncPlatform? previousPlatform;

  setUp(() {
    previousPlatform = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previousPlatform;
  });

  test(
    'falls back to defaults when the persisted profile is malformed',
    () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString('clarix.theme.profile', '{not json');

      final profile = await ClarixThemeStore(preferences).read();

      expect(profile.readerBackgroundPath, isNull);
    },
  );
}
