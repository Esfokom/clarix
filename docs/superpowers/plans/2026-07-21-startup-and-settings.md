# Startup and Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Launch directly into the workspace and provide persistent OpenAI-compatible provider configuration through an app-level Settings dialog.

**Architecture:** `ClarixApp` changes only its default route. A provider configuration store owns profile metadata and default-provider selection. `WorkspaceNotifier` hydrates from that store while the Settings dialog owns its UI visibility locally.

**Tech Stack:** Flutter, Riverpod, shadcn_ui, shared_preferences `SharedPreferencesAsync`, flutter_secure_storage, flutter_test.

## Global Constraints

- Desktop Clarix launches directly to `WorkspaceScreen`; diagnostics are not the home screen.
- Only OpenAI-compatible answer providers are supported in this phase.
- Persist provider metadata and default provider ID in `SharedPreferencesAsync`.
- Keep API keys exclusively in `flutter_secure_storage`; never serialize them into sessions or preferences.
- Provider testing must not persist an unsaved profile.
- Do not implement Rust RAG in this plan; its approved architecture is `docs/superpowers/specs/2026-07-21-startup-settings-local-rag-design.md`.

---

## File structure

- Modify `lib/src/app.dart`: set `WorkspaceScreen` as `ShadApp.home`.
- Modify `lib/src/features/workspace/infrastructure/provider_profile_store.dart`: persist/read/delete the default profile ID.
- Modify `lib/src/features/workspace/application/workspace_notifier.dart`: hydrate/select profiles from configuration, remove workspace settings visibility.
- Modify `lib/src/features/workspace/domain/workspace_feature_state.dart`: remove `showProviderSettings`.
- Modify `lib/src/features/workspace/presentation/widgets/workspace_body.dart`: remove settings overlay and accept `onOpenSettings`.
- Modify `lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart`: expose a Settings action.
- Create `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`: modal settings and provider editor.
- Modify `lib/src/features/workspace/presentation/screens/workspace_screen.dart`: open the Settings dialog.
- Delete `lib/src/features/workspace/presentation/widgets/provider_settings_sheet.dart`.
- Modify `test/widget_test.dart` and `test/workspace_ai/provider_profile_store_test.dart`; create `test/workspace_ai/app_settings_dialog_test.dart`.

### Task 1: Direct startup route

**Files:**
- Modify: `lib/src/app.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `ClarixApp.home == _WindowBootstrap(child: WorkspaceScreen())`.

- [ ] **Step 1: Write the failing startup test**

```dart
testWidgets('Clarix launches directly into the workspace', (tester) async {
  await tester.pumpWidget(const ClarixApp());
  await tester.pump();
  expect(find.byType(WorkspaceScreen), findsOneWidget);
  expect(find.byType(ReaderDiagnosticsHub), findsNothing);
});
```

- [ ] **Step 2: Run the test to verify failure**

Run: `flutter test test/widget_test.dart`

Expected: FAIL because `ClarixApp.home` is `ReaderDiagnosticsHub`.

- [ ] **Step 3: Set the production home route**

```dart
import 'features/workspace/presentation/screens/workspace_screen.dart';

// in build
home: const _WindowBootstrap(child: WorkspaceScreen()),
```

Do not delete diagnostics; it remains available only through a deliberate developer entry point.

- [ ] **Step 4: Run the focused test**

Run: `flutter test test/widget_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/app.dart test/widget_test.dart
git commit -m "feat: launch Clarix into workspace"
```

### Task 2: Persist an application default provider

**Files:**
- Modify: `lib/src/features/workspace/infrastructure/provider_profile_store.dart`
- Modify: `test/workspace_ai/provider_profile_store_test.dart`

**Interfaces:**
- Produces: `Future<String?> readDefaultProfileId()` and `Future<void> saveDefaultProfileId(String profileId)`.
- Changes: `deleteProfile(String profileId)` clears the default ID when it matches.

- [ ] **Step 1: Write failing store tests**

```dart
test('provider store persists the default profile independently', () async {
  await store.saveProfile(openAi);
  await store.saveProfile(other);
  await store.saveDefaultProfileId(other.id);
  expect(await store.readDefaultProfileId(), other.id);
});

test('deleting the default profile clears default selection and secret', () async {
  await store.saveProfile(openAi, apiKey: 'sk-secret');
  await store.saveDefaultProfileId(openAi.id);
  await store.deleteProfile(openAi.id);
  expect(await store.readDefaultProfileId(), isNull);
  expect(await store.readApiKey(openAi.id), isNull);
});
```

- [ ] **Step 2: Run the focused store tests to verify failure**

Run: `flutter test test/workspace_ai/provider_profile_store_test.dart`

Expected: FAIL because default-provider methods do not exist.

- [ ] **Step 3: Add default-provider persistence**

```dart
static const String _defaultProfileKey = 'clarix.ai.default_provider';

Future<String?> readDefaultProfileId() =>
    preferences.getString(_defaultProfileKey);

Future<void> saveDefaultProfileId(String profileId) =>
    preferences.setString(_defaultProfileKey, profileId);
```

Append the following cleanup to `deleteProfile`:

```dart
if (await readDefaultProfileId() == profileId) {
  await preferences.remove(_defaultProfileKey);
}
```

- [ ] **Step 4: Run the focused store tests**

Run: `flutter test test/workspace_ai/provider_profile_store_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/infrastructure/provider_profile_store.dart test/workspace_ai/provider_profile_store_test.dart
git commit -m "feat: persist default AI provider"
```

### Task 3: Separate provider configuration from workspace state

**Files:**
- Modify: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Delete: `lib/src/features/workspace/presentation/widgets/provider_settings_sheet.dart`
- Create: `test/workspace_ai/workspace_notifier_test.dart`

**Interfaces:**
- Removes: `WorkspaceFeatureState.showProviderSettings` and `WorkspaceNotifier.toggleProviderSettings([bool?])`.
- Preserves: `saveProvider`, `testProvider`, `selectProvider`, and `deleteProvider` for the Settings dialog.

- [ ] **Step 1: Write a failing default-hydration notifier test**

```dart
await store.saveProfile(openAi, apiKey: 'sk-openai');
await store.saveProfile(other, apiKey: 'sk-other');
await store.saveDefaultProfileId(other.id);
final WorkspaceFeatureState state = await notifier.future;
expect(state.aiState.selectedProviderId, other.id);
expect(state.aiState.providerReady, isTrue);

await notifier.deleteProvider(other.id);
expect((await notifier.future).aiState.selectedProviderId, isNull);
expect(await store.readDefaultProfileId(), isNull);
```

- [ ] **Step 2: Run the focused notifier test to verify failure**

Run: `flutter test test/workspace_ai/workspace_notifier_test.dart`

Expected: FAIL until hydration reads the default profile.

- [ ] **Step 3: Make configuration the hydration source**

In `WorkspaceNotifier.build`, use:

```dart
final String? defaultProfileId = await _providerProfiles.readDefaultProfileId();
final AiProviderProfile? selectedProfile =
    _profileById(providerProfiles, defaultProfileId) ??
    (providerProfiles.isEmpty ? null : providerProfiles.first);
```

In `selectProvider`, save a non-null selection before committing runtime state:

```dart
if (profile != null) {
  await _providerProfiles.saveDefaultProfileId(profile.id);
}
```

Remove `toggleProviderSettings`, `showProviderSettings`, the `WorkspaceBody` overlay, and the side-sheet file. Session `selectedProviderId` remains runtime/chat compatibility state but is not the hydration source.

- [ ] **Step 4: Run workspace-AI tests**

Run: `flutter test test/workspace_ai`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/domain/workspace_feature_state.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart test/workspace_ai
git rm lib/src/features/workspace/presentation/widgets/provider_settings_sheet.dart
git commit -m "refactor: separate provider configuration from workspace"
```

### Task 4: Implement Settings dialog and provider editor

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Modify: `lib/src/features/workspace/presentation/screens/workspace_screen.dart`
- Create: `test/workspace_ai/app_settings_dialog_test.dart`

**Interfaces:**
- Produces: `Future<void> showAppSettingsDialog(BuildContext context)` and `AppSettingsDialog`.
- Consumes: `WorkspaceNotifier.saveProvider`, `.testProvider`, `.selectProvider`, and `.deleteProvider`.
- Changes: `WorkspaceBody` and `WorkspaceSidebar` accept `required VoidCallback onOpenSettings`.

- [ ] **Step 1: Write failing dialog widget tests**

```dart
testWidgets('settings shows an empty provider state and add action', (tester) async {
  await pumpSettings(tester, profiles: const <AiProviderProfile>[]);
  expect(find.text('AI providers'), findsOneWidget);
  expect(find.text('Add provider'), findsOneWidget);
});

testWidgets('saving a provider selects it as default', (tester) async {
  await pumpSettings(tester, profiles: const <AiProviderProfile>[]);
  await tester.tap(find.text('Add provider'));
  await tester.enterText(find.byKey(const Key('provider-label')), 'OpenAI');
  await tester.enterText(find.byKey(const Key('provider-base-url')), 'https://api.openai.com/v1');
  await tester.enterText(find.byKey(const Key('provider-model')), 'gpt-5');
  await tester.enterText(find.byKey(const Key('provider-api-key')), 'sk-test');
  await tester.tap(find.text('Save provider'));
  expect(fakeNotifier.savedProfile?.id, 'openai');
  expect(fakeNotifier.selectedProfileId, 'openai');
});
```

Also test edit prefill, connection-test error presentation, default marker, and delete confirmation.

- [ ] **Step 2: Run dialog tests to verify failure**

Run: `flutter test test/workspace_ai/app_settings_dialog_test.dart`

Expected: FAIL because `AppSettingsDialog` does not exist.

- [ ] **Step 3: Implement the modal dialog**

```dart
Future<void> showAppSettingsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AppSettingsDialog(),
);

class AppSettingsDialog extends ConsumerWidget {
  const AppSettingsDialog({super.key});
}
```

Create private `_ProviderEditorDialog` state for label, base URL, model, API key, consent, test, error, and saving. Reuse `AiProviderProfile.create` validation. Save calls `saveProvider(profile, apiKey: key)` then `selectProvider(profile.id)`; Test calls only `testProvider`. Preserve keys `provider-label`, `provider-base-url`, `provider-model`, and `provider-api-key`.

- [ ] **Step 4: Wire the app Settings action**

```dart
class WorkspaceBody extends ConsumerStatefulWidget {
  const WorkspaceBody({
    required this.state,
    required this.onOpenSettings,
    super.key,
  });

  final WorkspaceFeatureState state;
  final VoidCallback onOpenSettings;
}
```

Pass `onOpenSettings` into `WorkspaceSidebar`. In `WorkspaceScreen.build`, create `WorkspaceBody(state: state, onOpenSettings: () => showAppSettingsDialog(context))`. Replace the sidebar’s old provider action with a tooltip-labelled Settings action calling this callback; it remains available without a PDF.

- [ ] **Step 5: Run focused widget tests**

Run: `flutter test test/workspace_ai/app_settings_dialog_test.dart test/widget_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/presentation/screens/workspace_screen.dart test/workspace_ai/app_settings_dialog_test.dart
git commit -m "feat: add persistent app settings for AI providers"
```

### Task 5: Complete verification

**Files:**
- Modify only files needed to correct a verification failure.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format lib/src/app.dart lib/src/features/workspace test/widget_test.dart test/workspace_ai`

Expected: formatter completes without errors.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 4: Perform Windows smoke check**

Run: `flutter run -d windows`

Verify: workspace opens immediately; Settings opens with no PDF; create/test/save provider; relaunch selects default; edit has a blank API-key field; deleting default clears selection.

- [ ] **Step 5: Commit a scoped verification correction if needed**

```powershell
git add <only-files-fixed-during-verification>
git commit -m "fix: complete settings startup verification"
```

Skip this commit if no correction was needed.
