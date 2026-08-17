import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_models.dart';

class AiPreferencesStore {
  AiPreferencesStore(this._preferences);

  static const String _stateKey = 'clarix.ai.state';
  static String get storageKeyForTest => _stateKey;

  final SharedPreferencesAsync _preferences;

  Future<AiWorkspaceState> readState() async {
    final String? raw = await _preferences.getString(_stateKey);
    if (raw == null || raw.isEmpty) return AiWorkspaceState.initial();
    return AiWorkspaceState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> writeState(AiWorkspaceState state) =>
      _preferences.setString(_stateKey, jsonEncode(state.toJson()));
}
