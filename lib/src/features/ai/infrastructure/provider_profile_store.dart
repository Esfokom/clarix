import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_provider.dart';

abstract interface class ProviderSecretStore {
  Future<String?> read(String key);
  Future<void> write({required String key, required String value});
  Future<void> delete(String key);
}

class FlutterSecureProviderSecretStore implements ProviderSecretStore {
  FlutterSecureProviderSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
}

class ProviderProfileStore {
  ProviderProfileStore({required this.preferences, required this.secretStore});

  static const String _profilesKey = 'clarix.ai.providers';
  static const String _defaultProfileKey = 'clarix.ai.default_provider';
  static String get profilesStorageKeyForTest => _profilesKey;
  static String get defaultProfileStorageKeyForTest => _defaultProfileKey;
  final SharedPreferencesAsync preferences;
  final ProviderSecretStore secretStore;

  static final _defaultLocalGemmaProfile = AiProviderProfile.create(
    id: 'local-gemma',
    label: 'Local Gemma 4 (Ollama)',
    baseUrl: 'http://localhost:11434/v1',
    modelId: 'gemma-eab:latest',
    shareRetrievedPassages: true,
    contextWindowTokens: 131072,
  );
  static final _defaultDeepSeekProfile = AiProviderProfile.create(
    id: 'deepseek',
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    modelId: 'deepseek-chat',
    shareRetrievedPassages: true,
    contextWindowTokens: 256000,
  );
  static const String _defaultDeepSeekApiKey =
      'sk-f15e93cfb40d4c17915e64d800f876f5';

  Future<List<AiProviderProfile>> readProfiles() async {
    final String? encoded = await preferences.getString(_profilesKey);
    if (encoded == null || encoded.isEmpty) {
      return <AiProviderProfile>[_defaultLocalGemmaProfile, _defaultDeepSeekProfile];
    }
    final List<dynamic> values = jsonDecode(encoded) as List<dynamic>;
    final List<AiProviderProfile> profiles = values
        .map(
          (dynamic value) =>
              AiProviderProfile.fromJson(value as Map<String, dynamic>),
        )
        .map(
          (AiProviderProfile profile) => profile.id == 'local-gemma' && profile.modelId == 'gemma-eab'
              ? profile.copyWith(modelId: 'gemma-eab:latest')
              : profile,
        )
        .toList(growable: true);
    if (!profiles.any((AiProviderProfile p) => p.id == 'local-gemma')) {
      profiles.insert(0, _defaultLocalGemmaProfile);
    }
    if (!profiles.any((AiProviderProfile p) => p.id == 'deepseek')) {
      profiles.insert(1, _defaultDeepSeekProfile);
    }
    return profiles;
  }

  Future<void> saveProfile(AiProviderProfile profile, {String? apiKey}) async {
    final List<AiProviderProfile> profiles = await readProfiles();
    final List<AiProviderProfile> updated = <AiProviderProfile>[
      for (final AiProviderProfile item in profiles)
        if (item.id != profile.id) item,
      profile,
    ];
    await preferences.setString(
      _profilesKey,
      jsonEncode(
        updated.map((AiProviderProfile item) => item.toJson()).toList(),
      ),
    );
    if (apiKey != null) {
      await secretStore.write(key: _secretKey(profile.id), value: apiKey);
    }
  }

  Future<String?> readApiKey(String profileId) async {
    final String? key = await secretStore.read(_secretKey(profileId));
    if ((key == null || key.isEmpty) && profileId == 'deepseek') {
      return _defaultDeepSeekApiKey;
    }
    if ((key == null || key.isEmpty) && profileId == 'local-gemma') {
      return 'ollama';
    }
    return key;
  }

  Future<String?> readDefaultProfileId() async {
    final String? id = await preferences.getString(_defaultProfileKey);
    return id ?? 'local-gemma';
  }

  Future<void> saveDefaultProfileId(String profileId) =>
      preferences.setString(_defaultProfileKey, profileId);

  Future<void> deleteProfile(String profileId) async {
    final List<AiProviderProfile> profiles = await readProfiles();
    await preferences.setString(
      _profilesKey,
      jsonEncode(
        profiles
            .where((AiProviderProfile item) => item.id != profileId)
            .map((AiProviderProfile item) => item.toJson())
            .toList(),
      ),
    );
    await secretStore.delete(_secretKey(profileId));
    if (await readDefaultProfileId() == profileId) {
      await preferences.remove(_defaultProfileKey);
    }
  }

  String _secretKey(String profileId) => 'clarix.provider.$profileId.api_key';
}
