import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ClarixSessionStore {
  ClarixSessionStore(this._preferences);

  static const String _workspaceKey = 'clarix.workspace.session';

  static String get workspaceStorageKeyForTest => _workspaceKey;

  final SharedPreferencesAsync _preferences;

  Future<WorkspaceSession> readWorkspaceSession() async {
    final String? raw = await _preferences.getString(_workspaceKey);
    if (raw == null || raw.isEmpty) {
      return WorkspaceSession.initial();
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    return WorkspaceSession.fromJson(decoded);
  }

  Future<void> writeWorkspaceSession(WorkspaceSession session) {
    return _preferences.setString(_workspaceKey, jsonEncode(session.toJson()));
  }
}
