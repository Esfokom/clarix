import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clarix/src/core/models.dart';

/// Preset model containing a named snapshot of a workspace session layout
class WorkspacePreset {
  const WorkspacePreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.session,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final WorkspaceSession session;

  int get tabCount => session.tabs.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'session': session.toJson(),
      };

  factory WorkspacePreset.fromJson(Map<String, dynamic> json) {
    return WorkspacePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      session: WorkspaceSession.fromJson(json['session'] as Map<String, dynamic>),
    );
  }
}

/// Persistent store for named Workspace Layout Presets
class WorkspacePresetStore {
  WorkspacePresetStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  static const String _storageKey = 'clarix_workspace_presets_v1';

  Future<List<WorkspacePreset>> readPresets() async {
    final rawJson = await _preferences.getString(_storageKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return <WorkspacePreset>[];
    }
    try {
      final List<dynamic> list = jsonDecode(rawJson) as List<dynamic>;
      return list
          .map((item) => WorkspacePreset.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <WorkspacePreset>[];
    }
  }

  Future<void> savePreset(WorkspacePreset preset) async {
    final presets = await readPresets();
    final existingIndex = presets.indexWhere((p) => p.id == preset.id);
    if (existingIndex >= 0) {
      presets[existingIndex] = preset;
    } else {
      presets.insert(0, preset);
    }
    final encoded = jsonEncode(presets.map((p) => p.toJson()).toList());
    await _preferences.setString(_storageKey, encoded);
  }

  Future<void> deletePreset(String presetId) async {
    final presets = await readPresets();
    presets.removeWhere((p) => p.id == presetId);
    final encoded = jsonEncode(presets.map((p) => p.toJson()).toList());
    await _preferences.setString(_storageKey, encoded);
  }
}
