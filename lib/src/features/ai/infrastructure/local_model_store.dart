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
}
