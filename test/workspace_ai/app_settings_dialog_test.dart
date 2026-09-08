import 'dart:io';

import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/ai/domain/ai_provider.dart';
import 'package:clarix/src/features/ai/application/ai_providers.dart';
import 'package:clarix/src/features/workspace/infrastructure/document_metadata_store.dart';
import 'package:clarix/src/features/ai/infrastructure/provider_profile_store.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/app_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  testWidgets('shows initial provider state with an add-provider action', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);

    await harness.pump(tester);

    await tester.ensureVisible(find.text('Local Gemma 4 (Ollama)'));
    expect(find.text('Local Gemma 4 (Ollama)'), findsOneWidget);
    await tester.ensureVisible(find.text('Add provider'));
    expect(find.text('Add provider'), findsOneWidget);
  });

  testWidgets('saves a provider and selects it as the default', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);

    await harness.pump(tester);
    await tester.ensureVisible(find.text('Add provider'));
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('provider-label')), 'OpenAI');
    await tester.enterText(
      find.byKey(const Key('provider-base-url')),
      'https://api.openai.com/v1',
    );
    await tester.enterText(find.byKey(const Key('provider-model')), 'gpt-5');
    await tester.enterText(
      find.byKey(const Key('provider-api-key')),
      'sk-test',
    );
    await tester.ensureVisible(find.text('Save provider'));
    await tester.tap(find.text('Save provider'));
    await tester.pumpAndSettle();

    final List<AiProviderProfile> profiles = await harness.store.readProfiles();
    expect(profiles, hasLength(3));
    expect(await harness.store.readDefaultProfileId(), profiles.last.id);
    expect(
      harness.container
          .read(aiNotifierProvider)
          .requireValue
          .chat
          .selectedProviderId,
      profiles.last.id,
    );
  });

  testWidgets('editing never prefills the API key', (
    WidgetTester tester,
  ) async {
    final AiProviderProfile profile = _profile();
    final _Harness harness = await _Harness.create(profile: profile);
    addTearDown(harness.dispose);

    await harness.pump(tester);
    await tester.ensureVisible(find.byTooltip('Edit OpenAI'));
    await tester.tap(find.byTooltip('Edit OpenAI'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('provider-api-key')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('shows a connection-test error without saving a provider', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _Harness.create();
    addTearDown(harness.dispose);

    await harness.pump(tester);
    await tester.ensureVisible(find.text('Add provider'));
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('provider-label')), 'OpenAI');
    await tester.enterText(
      find.byKey(const Key('provider-base-url')),
      'https://api.openai.com/v1',
    );
    await tester.enterText(find.byKey(const Key('provider-model')), 'gpt-5');
    await tester.ensureVisible(find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.textContaining('OpenAI error'));
    expect(find.textContaining('OpenAI error'), findsOneWidget);
    expect(await harness.store.readProfiles(), hasLength(2));
  });

  testWidgets('marks the default provider and confirms before deletion', (
    WidgetTester tester,
  ) async {
    final AiProviderProfile profile = _profile();
    final _Harness harness = await _Harness.create(profile: profile);
    addTearDown(harness.dispose);

    await harness.pump(tester);

    await tester.ensureVisible(find.text('Default'));
    expect(find.text('Default'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Delete OpenAI'));
    await tester.tap(find.byTooltip('Delete OpenAI'));
    await tester.pumpAndSettle();
    expect(find.text('Delete provider?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete provider'), findsOneWidget);
  });
}

AiProviderProfile _profile() => AiProviderProfile.create(
  id: 'openai',
  label: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  modelId: 'gpt-5',
  shareRetrievedPassages: false,
);

class _Harness {
  _Harness(this.container, this.store);

  final ProviderContainer container;
  final ProviderProfileStore store;

  static Future<_Harness> create({AiProviderProfile? profile}) async {
    final SharedPreferencesAsync preferences = SharedPreferencesAsync();
    final ProviderProfileStore store = ProviderProfileStore(
      preferences: preferences,
      secretStore: _MemorySecretStore(),
    );
    if (profile != null) {
      await store.saveProfile(profile, apiKey: 'sk-secret');
      await store.saveDefaultProfileId(profile.id);
    }
    return _Harness(
      ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          aiSharedPreferencesProvider.overrideWithValue(preferences),
          providerProfileStoreProvider.overrideWithValue(store),
          documentMetadataStoreProvider.overrideWith(
            (Ref ref) async =>
                DocumentMetadataStore(root: Directory.systemTemp),
          ),
        ],
      ),
      store,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 700,
                height: 700,
                child: AppSettingsDialog(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget dialog() => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: AppSettingsDialog())),
  );

  void dispose() => container.dispose();
}

class _MemorySecretStore implements ProviderSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}
