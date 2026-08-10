import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_profile.dart';

class ClarixThemeStore {
  ClarixThemeStore(this._preferences);
  final SharedPreferencesAsync _preferences;
  static const _key = 'clarix.theme.profile';
  Future<ClarixThemeProfile> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return const ClarixThemeProfile();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ClarixThemeProfile();
      return ClarixThemeProfile.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return const ClarixThemeProfile();
    } on TypeError {
      return const ClarixThemeProfile();
    }
  }

  Future<void> write(ClarixThemeProfile profile) =>
      _preferences.setString(_key, jsonEncode(profile.toJson()));
}
