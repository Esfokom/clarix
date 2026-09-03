import 'package:shared_preferences/shared_preferences.dart';

class VoiceInputSettingsStore {
  VoiceInputSettingsStore(this._preferences);

  static const String _selectedDeviceIdKey =
      'clarix.voice.selected_input_device_id';

  final SharedPreferencesAsync _preferences;

  Future<String?> readSelectedDeviceId() =>
      _preferences.getString(_selectedDeviceIdKey);

  Future<void> saveSelectedDeviceId(String? deviceId) => deviceId == null
      ? _preferences.remove(_selectedDeviceIdKey)
      : _preferences.setString(_selectedDeviceIdKey, deviceId);
}
