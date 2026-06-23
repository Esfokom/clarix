import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ClarixSessionStore {
  ClarixSessionStore(this._preferences);

  static const String _workspaceKey = 'clarix.workspace.session';
  static const String _aiKey = 'clarix.ai.state';
  static const String _downloadKey = 'clarix.download.tasks';

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
    return _preferences.setString(
      _workspaceKey,
      jsonEncode(session.toJson()),
    );
  }

  Future<AiWorkspaceState> readAiWorkspaceState() async {
    final String? raw = await _preferences.getString(_aiKey);
    if (raw == null || raw.isEmpty) {
      return AiWorkspaceState.initial();
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    return AiWorkspaceState.fromJson(decoded);
  }

  Future<void> writeAiWorkspaceState(AiWorkspaceState state) {
    return _preferences.setString(_aiKey, jsonEncode(state.toJson()));
  }

  Future<Map<String, DownloadTaskState>> readDownloads() async {
    final String? raw = await _preferences.getString(_downloadKey);
    if (raw == null || raw.isEmpty) {
      return <String, DownloadTaskState>{};
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (String key, dynamic value) => MapEntry(
        key,
        DownloadTaskState.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  Future<void> writeDownloads(Map<String, DownloadTaskState> downloads) {
    final Map<String, dynamic> encoded = downloads.map(
      (String key, DownloadTaskState value) =>
          MapEntry(key, value.toJson()),
    );
    return _preferences.setString(_downloadKey, jsonEncode(encoded));
  }
}
