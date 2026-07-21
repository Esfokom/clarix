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
  final SharedPreferencesAsync preferences;
  final ProviderSecretStore secretStore;

  Future<List<AiProviderProfile>> readProfiles() async {
    final String? encoded = await preferences.getString(_profilesKey);
    if (encoded == null || encoded.isEmpty) return const <AiProviderProfile>[];
    final List<dynamic> values = jsonDecode(encoded) as List<dynamic>;
    return values
        .map(
          (dynamic value) =>
              AiProviderProfile.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
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

  Future<String?> readApiKey(String profileId) =>
      secretStore.read(_secretKey(profileId));

  Future<String?> readDefaultProfileId() =>
      preferences.getString(_defaultProfileKey);

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
