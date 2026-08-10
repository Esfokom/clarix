import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_profile.dart';
import 'theme_store.dart';

final clarixThemeStoreProvider = Provider<ClarixThemeStore>(
  (ref) => ClarixThemeStore(SharedPreferencesAsync()),
);
final clarixThemeProvider =
    AsyncNotifierProvider<ClarixThemeController, ClarixThemeProfile>(
      ClarixThemeController.new,
    );

class ClarixThemeController extends AsyncNotifier<ClarixThemeProfile> {
  @override
  Future<ClarixThemeProfile> build() =>
      ref.read(clarixThemeStoreProvider).read();
  Future<void> setProfile(ClarixThemeProfile profile) async {
    state = AsyncData(profile);
    await ref.read(clarixThemeStoreProvider).write(profile);
  }
}
