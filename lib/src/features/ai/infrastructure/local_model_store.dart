import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/local_model_profile.dart';

class LocalModelStore {
  LocalModelStore(this._preferences);

  static const String _modelsKey = 'clarix.ai.local_models';

  final SharedPreferencesAsync _preferences;

  Future<List<LocalModelProfile>> readAll() async {
    final String? raw = await _preferences.getString(_modelsKey);
    if (raw == null || raw.isEmpty) return const <LocalModelProfile>[];
    return (jsonDecode(raw) as List<dynamic>)
        .map(
          (dynamic value) =>
              LocalModelProfile.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<void> save(LocalModelProfile profile) async {
    final List<LocalModelProfile> models = await readAll();
    final List<LocalModelProfile> updated = <LocalModelProfile>[
      for (final LocalModelProfile item in models)
        if (item.id != profile.id) item,
      profile,
    ];
    await _preferences.setString(
      _modelsKey,
      jsonEncode(
        updated.map((LocalModelProfile item) => item.toJson()).toList(),
      ),
    );
  }

  Future<void> delete(String modelId) async {
    final List<LocalModelProfile> models = await readAll();
    await _preferences.setString(
      _modelsKey,
      jsonEncode(
        models
            .where((LocalModelProfile model) => model.id != modelId)
            .map((LocalModelProfile model) => model.toJson())
            .toList(),
      ),
    );
  }

  /// Makes Clarix's presentation metadata match Flutter Gemma's installed
  /// model registry. This runs before the AI UI chooses its initial provider.
  Future<List<LocalModelProfile>> reconcile({
    required Iterable<LocalModelProfile> supportedProfiles,
    required Future<bool> Function(LocalModelProfile profile) isInstalled,
  }) async {
    final Map<String, LocalModelProfile> candidates =
        <String, LocalModelProfile>{
          for (final LocalModelProfile profile in await readAll())
            profile.id: profile,
          for (final LocalModelProfile profile in supportedProfiles)
            profile.id: profile,
        };
    final List<LocalModelProfile> installed = <LocalModelProfile>[];
    for (final LocalModelProfile profile in candidates.values) {
      if (await isInstalled(profile)) installed.add(profile);
    }
    await _writeAll(installed);
    return installed;
  }

  Future<void> _writeAll(List<LocalModelProfile> models) =>
      _preferences.setString(
        _modelsKey,
        jsonEncode(
          models.map((LocalModelProfile model) => model.toJson()).toList(),
        ),
      );
}
