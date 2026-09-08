import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tts_models.dart';

/// Persists the user's TTS engine/model/voice selection and speed, configured
/// from Settings and applied to every reading session.
class TtsPreferencesStore {
  TtsPreferencesStore(this._preferences);

  static const String _voiceIdKey = 'clarix.tts.default_voice_sid';
  static const String _speedKey = 'clarix.tts.default_speed';
  static const String _activeEngineKey = 'clarix.tts.active_engine';
  static const String _activeModelIdKey = 'clarix.tts.active_model_id';
  static const String _systemVoiceNameKey = 'clarix.tts.system_voice_name';
  static const String _systemVoiceLocaleKey = 'clarix.tts.system_voice_locale';

  final SharedPreferencesAsync _preferences;

  Future<int> readDefaultVoice() async =>
      await _preferences.getInt(_voiceIdKey) ?? 0;

  Future<void> saveDefaultVoice(int sid) =>
      _preferences.setInt(_voiceIdKey, sid);

  Future<double> readSpeed() async =>
      await _preferences.getDouble(_speedKey) ?? 1.0;

  Future<void> saveSpeed(double speed) =>
      _preferences.setDouble(_speedKey, speed);

  Future<TtsEngineKind> readActiveEngine() async {
    final String? name = await _preferences.getString(_activeEngineKey);
    if (name == null) return TtsEngineKind.kittenSherpa;
    return TtsEngineKind.values.byName(name);
  }

  Future<void> saveActiveEngine(TtsEngineKind engine) =>
      _preferences.setString(_activeEngineKey, engine.name);

  Future<String?> readActiveModelId() =>
      _preferences.getString(_activeModelIdKey);

  Future<void> saveActiveModelId(String? id) => id == null
      ? _preferences.remove(_activeModelIdKey)
      : _preferences.setString(_activeModelIdKey, id);

  Future<String?> readSystemVoiceName() =>
      _preferences.getString(_systemVoiceNameKey);

  Future<String?> readSystemVoiceLocale() =>
      _preferences.getString(_systemVoiceLocaleKey);

  Future<void> saveSystemVoice({required String? name, required String? locale}) async {
    if (name == null || locale == null) {
      await _preferences.remove(_systemVoiceNameKey);
      await _preferences.remove(_systemVoiceLocaleKey);
      return;
    }
    await _preferences.setString(_systemVoiceNameKey, name);
    await _preferences.setString(_systemVoiceLocaleKey, locale);
  }
}
