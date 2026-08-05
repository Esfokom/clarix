# Workspace Theming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persisted global theme tokens, reader-only backgrounds, configurable highlights, and a reference-matched tabbed Settings dialog.

**Architecture:** A persisted `ClarixThemeProfile` is resolved by `ThemeController` into semantic UI tokens. The app root and workspace surfaces consume those tokens; the PDF reader alone owns the selected background image. Settings writes profile changes immediately through the controller.

**Tech Stack:** Flutter, Riverpod, SharedPreferences, path_provider, file_picker, Flutter tests.

## Global Constraints

- Theme mode supports system, light, and dark.
- Accent changes the app-wide semantic accent, not arbitrary individual widget colors.
- Reader background imagery is restricted to the PDF reader surface.
- Imported backgrounds are copied to application-support storage.
- Highlight palette includes five built-ins and at most ten custom colors.
- Existing annotations retain their stored colors.
- Preserve unrelated user work on `main`.

---

### Task 1: Create profile, persistence, and semantic tokens

**Files:**
- Create: `lib/src/core/theme_profile.dart`
- Create: `lib/src/core/theme_store.dart`
- Create: `lib/src/core/theme_controller.dart`
- Modify: `lib/src/app.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_common.dart`
- Test: `test/theme_profile_test.dart`

**Interfaces:**
- Produces `ClarixThemeProfile`, `ClarixThemeStore`, `ThemeController`, and `ClarixThemeTokens`.
- `ThemeController.update(ClarixThemeProfile profile)` persists and emits an updated profile.

- [ ] **Step 1: Write failing serialization/token tests**

```dart
test('legacy profile defaults to dark neutral and 256k-independent theme values', () {
  expect(ClarixThemeProfile.fromJson(<String, dynamic>{}).mode, ThemeMode.system);
});
test('cherry accent resolves accent tokens without changing warning tokens', () {
  expect(resolveThemeTokens(profile).accent, const Color(0xFF...));
});
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/theme_profile_test.dart`

- [ ] **Step 3: Implement profile, store, controller, and tokens**

Define mode, accent preset/custom color, reader background, inversion/book override, built-in/custom highlight list, active highlight, and opacity. Use semantic tokens instead of direct workspace color constants.

- [ ] **Step 4: Verify and commit**

Run: `flutter test test/theme_profile_test.dart && flutter analyze lib/src/core/theme_profile.dart lib/src/core/theme_controller.dart`

Commit only task files with message `feat: add persisted workspace theme tokens`.

### Task 2: Apply tokens and reader-only backgrounds

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart`
- Test: `test/workspace_ai/theme_surface_test.dart`

**Interfaces:**
- Consumes `ClarixThemeTokens` and reader background selection.
- Produces live theme updates across workspace surfaces and a background painted solely under PDF content.

- [ ] **Step 1: Write failing surface tests**

Assert reader background is found inside document workspace and absent from AI/sidebar chrome; assert accent token changes selected state.

- [ ] **Step 2: Implement token migration**

Replace workspace hard-coded color use with semantic tokens in the listed surfaces. Paint the reader background behind the PDF viewer and apply optional inversion only there.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/workspace_ai/theme_surface_test.dart && flutter analyze lib/src/features/workspace/presentation/widgets`

Commit only task files with message `feat: apply configurable workspace theme`.

### Task 3: Store and select reader backgrounds/highlight palette

**Files:**
- Create: `lib/src/core/reader_background_store.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Test: `test/reader_background_store_test.dart`

**Interfaces:**
- Produces `ReaderBackgroundStore.importImage(File source)` and profile updates for active background/highlight color.
- New highlights read the theme profile’s selected color/opacity.

- [ ] **Step 1: Write failing import and highlight-limit tests**

```dart
expect(await store.importImage(source), startsWith(appSupport.path));
expect(profile.addCustomHighlight(color), throwsA(isA<StateError>()));
```

- [ ] **Step 2: Implement copy/fallback and active highlight selection**

Copy imported images into Clarix-owned storage; gracefully fall back when missing. Wire selected highlight color/opacity into the existing new-highlight creation path.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/reader_background_store_test.dart && flutter analyze lib/src/core/reader_background_store.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart`

Commit only task files with message `feat: configure reader backgrounds and highlights`.

### Task 4: Rebuild Settings as tabbed theme controls

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`
- Test: `test/workspace_ai/app_settings_dialog_test.dart`

**Interfaces:**
- Consumes `ThemeController`, reader background store, and existing provider/storage operations.
- Produces Font, Theme, and Provider/Storage tabs matching the supplied reference.

- [ ] **Step 1: Write failing widget tests**

Assert tab selection, system/light/dark controls, accent grid, background import, highlight palette limit, and existing provider/storage actions.

- [ ] **Step 2: Implement rounded icon-tab dialog**

Build the top tab strip and use the reference’s grouped controls. Keep existing provider and storage actions in their own tab; add Font controls for reader settings and Theme controls for profile updates.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/workspace_ai/app_settings_dialog_test.dart && flutter analyze lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`

Commit only task files with message `feat: add tabbed theme settings`.

### Task 5: Full verification

- [ ] **Step 1: Format and analyze**

Run: `dart format lib test && flutter analyze`

- [ ] **Step 2: Run tests and Windows build**

Run: `flutter test && flutter build windows --debug`

- [ ] **Step 3: Inspect scope**

Run: `git diff --check && git status --short`

