import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's default read-aloud voice and speed, configured from
/// Settings and applied to every reading session.
class TtsPreferencesStore {
  TtsPreferencesStore(this._preferences);

  static const String _voiceIdKey = 'clarix.tts.default_voice_sid';
  static const String _speedKey = 'clarix.tts.default_speed';

  final SharedPreferencesAsync _preferences;

  Future<int> readDefaultVoice() async =>
      await _preferences.getInt(_voiceIdKey) ?? 0;

  Future<void> saveDefaultVoice(int sid) =>
      _preferences.setInt(_voiceIdKey, sid);

  Future<double> readSpeed() async =>
      await _preferences.getDouble(_speedKey) ?? 1.0;

  Future<void> saveSpeed(double speed) =>
      _preferences.setDouble(_speedKey, speed);
}
