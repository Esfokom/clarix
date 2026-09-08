# Theming Full Reskin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make light/dark/system mode, accent color, custom accent, and reader background invert/book-override actually work end to end, matching the persisted `ClarixThemeProfile` fields that already exist.

**Architecture:** `WorkspaceSurfaceTokens` becomes brightness-aware (dark/light base palettes, resolved from `Theme.of(context).brightness`) and gains `viewerBackground`/`backdrop` for full parity with the static `WorkspaceColors` class, which is then deleted once every consumer migrates to instance tokens. `app.dart` builds separate light/dark `ShadThemeData`s with the accent injected into `ShadColorScheme`. Reader background invert/book-override get real rendering logic plus Settings UI.

**Tech Stack:** Flutter, Riverpod, shadcn_ui `ShadColorScheme.copyWith`.

**Spec:** `docs/superpowers/specs/2026-09-08-theming-full-reskin-design.md`

## Global Constraints

- `backdrop` (`0xAA020203`) and `warning` (`0xFFF59E0B`) are constant across brightness.
- No new color-picker dependency — custom accent uses a hex text field.
- `WorkspaceColors` static class is removed once migration is complete (no dual system).
- Light palette: `canvas #F4F4F5, canvasRaised #FAFAFA, panel #FFFFFF, panelRaised #F4F4F5, viewerBackground #D4D4D8, border #E4E4E7, textStrong #18181B, textMuted #52525B, textFaint #A1A1AA`.
- Dark palette keeps today's exact values: `canvas #2F2F2F, canvasRaised #343434, panel #343434, panelRaised #3A3A3A, viewerBackground #292929, border #484848, textStrong #FAFAFA, textMuted #A1A1AA, textFaint #71717A`.

---

## Task 1: Brightness-aware `WorkspaceSurfaceTokens`

**Files:**
- Modify: `lib/src/core/workspace_surface_tokens.dart` (full replace)
- Test: `test/core/workspace_surface_tokens_test.dart` (new)

**Interfaces:**
- Produces: `WorkspaceSurfaceTokens.fromProfile(ClarixThemeProfile profile, BuildContext context)` (new required `context` param), plus new fields `viewerBackground`, `backdrop`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:clarix/src/core/theme_profile.dart';
import 'package:clarix/src/core/workspace_surface_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Brightness brightness, Widget Function(BuildContext) builder) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(builder: builder),
    );

void main() {
  testWidgets('dark brightness resolves the dark base palette', (tester) async {
    late WorkspaceSurfaceTokens tokens;
    await tester.pumpWidget(_wrap(Brightness.dark, (context) {
      tokens = WorkspaceSurfaceTokens.fromProfile(const ClarixThemeProfile(), context);
      return const SizedBox();
    }));
    expect(tokens.panel.value, 0xFF343434);
    expect(tokens.textStrong.value, 0xFFFAFAFA);
  });

  testWidgets('light brightness resolves the light base palette', (tester) async {
    late WorkspaceSurfaceTokens tokens;
    await tester.pumpWidget(_wrap(Brightness.light, (context) {
      tokens = WorkspaceSurfaceTokens.fromProfile(const ClarixThemeProfile(), context);
      return const SizedBox();
    }));
    expect(tokens.panel.value, 0xFFFFFFFF);
    expect(tokens.textStrong.value, 0xFF18181B);
  });

  testWidgets('backdrop and warning stay constant across brightness', (tester) async {
    late WorkspaceSurfaceTokens dark;
    late WorkspaceSurfaceTokens light;
    await tester.pumpWidget(_wrap(Brightness.dark, (context) {
      dark = WorkspaceSurfaceTokens.fromProfile(const ClarixThemeProfile(), context);
      return const SizedBox();
    }));
    await tester.pumpWidget(_wrap(Brightness.light, (context) {
      light = WorkspaceSurfaceTokens.fromProfile(const ClarixThemeProfile(), context);
      return const SizedBox();
    }));
    expect(dark.backdrop, light.backdrop);
    expect(dark.warning, light.warning);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/workspace_surface_tokens_test.dart`
Expected: FAIL — `fromProfile` doesn't take a `context` param yet.

- [ ] **Step 3: Replace `workspace_surface_tokens.dart`**

```dart
import 'package:flutter/material.dart';

import 'theme_profile.dart';

class _Palette {
  const _Palette({
    required this.canvas,
    required this.canvasRaised,
    required this.panel,
    required this.panelRaised,
    required this.viewerBackground,
    required this.border,
    required this.textStrong,
    required this.textMuted,
    required this.textFaint,
  });

  final Color canvas;
  final Color canvasRaised;
  final Color panel;
  final Color panelRaised;
  final Color viewerBackground;
  final Color border;
  final Color textStrong;
  final Color textMuted;
  final Color textFaint;
}

const _Palette _darkPalette = _Palette(
  canvas: Color(0xFF2F2F2F),
  canvasRaised: Color(0xFF343434),
  panel: Color(0xFF343434),
  panelRaised: Color(0xFF3A3A3A),
  viewerBackground: Color(0xFF292929),
  border: Color(0xFF484848),
  textStrong: Color(0xFFFAFAFA),
  textMuted: Color(0xFFA1A1AA),
  textFaint: Color(0xFF71717A),
);

const _Palette _lightPalette = _Palette(
  canvas: Color(0xFFF4F4F5),
  canvasRaised: Color(0xFFFAFAFA),
  panel: Color(0xFFFFFFFF),
  panelRaised: Color(0xFFF4F4F5),
  viewerBackground: Color(0xFFD4D4D8),
  border: Color(0xFFE4E4E7),
  textStrong: Color(0xFF18181B),
  textMuted: Color(0xFF52525B),
  textFaint: Color(0xFFA1A1AA),
);

const Color _backdrop = Color(0xAA020203);
const Color _warning = Color(0xFFF59E0B);

class WorkspaceSurfaceTokens {
  const WorkspaceSurfaceTokens._({
    required this.canvas,
    required this.canvasRaised,
    required this.panel,
    required this.panelRaised,
    required this.viewerBackground,
    required this.border,
    required this.textStrong,
    required this.textMuted,
    required this.textFaint,
    required this.warning,
    required this.backdrop,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.selection,
  });

  factory WorkspaceSurfaceTokens.fromProfile(
    ClarixThemeProfile profile,
    BuildContext context,
  ) {
    final Brightness brightness = Theme.of(context).brightness;
    final _Palette base = brightness == Brightness.dark ? _darkPalette : _lightPalette;
    final ClarixThemeTokens theme = resolveThemeTokens(profile);
    final Color tint = theme.accent.withValues(alpha: 0.035);
    return WorkspaceSurfaceTokens._(
      canvas: Color.alphaBlend(tint, base.canvas),
      canvasRaised: Color.alphaBlend(tint, base.canvasRaised),
      panel: Color.alphaBlend(tint, base.panel),
      panelRaised: Color.alphaBlend(tint, base.panelRaised),
      viewerBackground: base.viewerBackground,
      border: Color.alphaBlend(theme.accent.withValues(alpha: 0.09), base.border),
      textStrong: base.textStrong,
      textMuted: base.textMuted,
      textFaint: base.textFaint,
      warning: _warning,
      backdrop: _backdrop,
      accent: theme.accent,
      accentSoft: theme.accentSoft,
      accentBorder: theme.accentBorder,
      selection: theme.accent.withValues(alpha: 0.26),
    );
  }

  final Color canvas;
  final Color canvasRaised;
  final Color panel;
  final Color panelRaised;
  final Color viewerBackground;
  final Color border;
  final Color textStrong;
  final Color textMuted;
  final Color textFaint;
  final Color warning;
  final Color backdrop;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final Color selection;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/workspace_surface_tokens_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/core/workspace_surface_tokens.dart test/core/workspace_surface_tokens_test.dart
git commit -m "feat(theme): brightness-aware WorkspaceSurfaceTokens with light palette"
```

Note: this intentionally breaks every existing `.fromProfile(profile)` call site (missing
the new `context` arg) and every direct `WorkspaceColors.X` reference (class still exists
for now, deleted in Task 9) — that's expected; Tasks 2-8 fix each call site. The app will
not compile between this task and Task 9's completion, which is fine for inline execution
(no CI gate runs mid-plan) but if executed by parallel subagents, Task 1 must land before
any consumer task starts.

---

## Task 2: `app.dart` — real light/dark themes with accent

**Files:**
- Modify: `lib/src/app.dart`
- Test: `test/app_theme_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:clarix/src/core/theme_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Re-implements the pure function under test by importing it directly once
// app.dart exposes `buildShadTheme` (see Step 3) — avoids booting the whole
// app (native TTS/PDF plugins) just to check color math.
import 'package:clarix/src/app.dart' show buildShadTheme;

void main() {
  test('accent color reaches primary/ring for both brightnesses', () {
    const ClarixThemeProfile profile = ClarixThemeProfile(accent: ClarixAccent.sky);
    final Color expected = accentFor(ClarixAccent.sky);

    final ShadThemeData light = buildShadTheme(profile, Brightness.light);
    final ShadThemeData dark = buildShadTheme(profile, Brightness.dark);

    expect(light.colorScheme.primary, expected);
    expect(dark.colorScheme.primary, expected);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.background, isNot(dark.colorScheme.background));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_theme_test.dart`
Expected: FAIL — `buildShadTheme` doesn't exist / isn't exported yet.

- [ ] **Step 3: Update `app.dart`**

Replace the `ClarixApp` class body:

```dart
class ClarixApp extends StatelessWidget {
  const ClarixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          final profile =
              ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
          return ShadApp(
            debugShowCheckedModeBanner: false,
            title: 'Clarix',
            themeMode: profile.mode,
            theme: buildShadTheme(profile, Brightness.light),
            darkTheme: buildShadTheme(profile, Brightness.dark),
            home: const _WindowBootstrap(child: WorkspaceScreen()),
          );
        },
      ),
    );
  }
}

/// Builds the shadcn theme for [profile] at a fixed [brightness]. Pure (no
/// BuildContext), so it's unit-testable without booting the app.
ShadThemeData buildShadTheme(ClarixThemeProfile profile, Brightness brightness) {
  final Color accentColor = accentFor(profile.accent, customAccentColor: profile.customAccentColor);
  final ShadColorScheme base = brightness == Brightness.dark
      ? const ShadZincColorScheme.dark()
      : const ShadZincColorScheme.light();
  return ShadThemeData(
    brightness: brightness,
    colorScheme: base.copyWith(
      primary: accentColor,
      ring: accentColor,
      selection: accentColor.withValues(alpha: 0.3),
    ),
    textTheme: ShadTextTheme.fromGoogleFont(switch (profile.font) {
      ClarixFont.sans => GoogleFonts.roboto,
      ClarixFont.serif => GoogleFonts.sourceSerif4,
      ClarixFont.mono => GoogleFonts.jetBrainsMono,
    }),
  );
}
```

(Keep `_WindowBootstrap` and `_WindowBootstrapState` unchanged below it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app_theme_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/app.dart test/app_theme_test.dart
git commit -m "feat(theme): real light/dark ShadThemeData with accent wired to colorScheme"
```

---

## Task 3: Migrate `core`/`ai` feature files to instance tokens

**Files:**
- Modify: `lib/src/features/ai/presentation/ai_composer.dart`, `ai_side_pane.dart`, `inline_page_reference.dart`
- Modify: `lib/src/features/ai/presentation/ai_conversation_history.dart` (already takes `colors` — check for stray static refs)
- Modify: `lib/src/features/settings/presentation/provider_editor_dialog.dart`

**Mechanical rule for every file in this task and Tasks 4-6:**
1. `grep -n "WorkspaceColors\."` the file.
2. For each hit, replace `WorkspaceColors.X` with `colors.X` if a `WorkspaceSurfaceTokens colors` (or `widget.colors`) is already in scope in that method/class.
3. If no `colors` is in scope yet, the widget must be a `ConsumerWidget`/`ConsumerStatefulWidget` (all of these already are, since they're inside the Riverpod-driven workspace tree) — add `final ClarixThemeProfile profile = ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();` and `final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(profile, context);` at the top of the relevant `build`, then use `colors.X`.
4. Re-run `grep -n "WorkspaceColors\."` on the file — must return nothing when done.

- [ ] **Step 1: Apply the mechanical rule to each file in this task's Files list**

- [ ] **Step 2: Verify no static references remain**

Run: `grep -rn "WorkspaceColors\." lib/src/features/ai/presentation/ai_composer.dart lib/src/features/ai/presentation/ai_side_pane.dart lib/src/features/ai/presentation/inline_page_reference.dart lib/src/features/ai/presentation/ai_conversation_history.dart lib/src/features/settings/presentation/provider_editor_dialog.dart`
Expected: no output.

- [ ] **Step 3: Compile-check this slice**

Run: `flutter analyze lib/src/features/ai lib/src/features/settings`
Expected: no new errors from these files (the app as a whole won't compile until Task 9 — see Task 1's note — so ignore errors originating in other, not-yet-migrated files).

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/ai/presentation/ai_composer.dart lib/src/features/ai/presentation/ai_side_pane.dart lib/src/features/ai/presentation/inline_page_reference.dart lib/src/features/ai/presentation/ai_conversation_history.dart lib/src/features/settings/presentation/provider_editor_dialog.dart
git commit -m "refactor(theme): migrate ai/settings widgets off static WorkspaceColors"
```

---

## Task 4: Migrate `reader` feature files to instance tokens

**Files:**
- Modify: `lib/src/features/reader/presentation/reader_viewer_components.dart`, `reader_viewer_pane.dart`

Apply the same mechanical rule as Task 3.

- [ ] **Step 1: Apply the mechanical rule to both files**
- [ ] **Step 2: Verify no static references remain**

Run: `grep -rn "WorkspaceColors\." lib/src/features/reader/presentation/reader_viewer_components.dart lib/src/features/reader/presentation/reader_viewer_pane.dart`
Expected: no output.

- [ ] **Step 3: Compile-check this slice**

Run: `flutter analyze lib/src/features/reader`
Expected: no new errors from these two files.

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/reader/presentation/reader_viewer_components.dart lib/src/features/reader/presentation/reader_viewer_pane.dart
git commit -m "refactor(theme): migrate reader widgets off static WorkspaceColors"
```

---

## Task 5: Migrate `workspace/screens` + `workspace_common`/`workspace_body`/`workspace_sidebar`/`document_workspace`

**Files:**
- Modify: `lib/src/features/workspace/presentation/screens/workspace_screen.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_common.dart`, `workspace_body.dart`, `workspace_sidebar.dart`, `document_workspace.dart`

Apply the same mechanical rule.

- [ ] **Step 1: Apply the mechanical rule to each file**
- [ ] **Step 2: Verify no static references remain**

Run: `grep -rn "WorkspaceColors\." lib/src/features/workspace/presentation/screens/workspace_screen.dart lib/src/features/workspace/presentation/widgets/workspace_common.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart`
Expected: no output.

- [ ] **Step 3: Compile-check this slice**

Run: `flutter analyze lib/src/features/workspace/presentation/screens lib/src/features/workspace/presentation/widgets/workspace_common.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart`
Expected: no new errors from these files.

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/workspace/presentation/screens/workspace_screen.dart lib/src/features/workspace/presentation/widgets/workspace_common.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart
git commit -m "refactor(theme): migrate workspace screen/chrome widgets off static WorkspaceColors"
```

---

## Task 6: Migrate remaining `workspace/widgets` dialogs

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_combine_extract_dialogs.dart`, `pdf_utilities_dialogs.dart`, `quickstart_surface.dart`, `reader_inspector.dart`, `app_settings_tts_section.dart`

Apply the same mechanical rule. (`app_settings_dialog.dart` is Task 7, kept separate since it also gets new UI in that task.)

- [ ] **Step 1: Apply the mechanical rule to each file**
- [ ] **Step 2: Verify no static references remain**

Run: `grep -rn "WorkspaceColors\." lib/src/features/workspace/presentation/widgets/pdf_combine_extract_dialogs.dart lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart lib/src/features/workspace/presentation/widgets/quickstart_surface.dart lib/src/features/workspace/presentation/widgets/reader_inspector.dart lib/src/features/workspace/presentation/widgets/app_settings_tts_section.dart`
Expected: no output.

- [ ] **Step 3: Compile-check this slice**

Run: `flutter analyze lib/src/features/workspace/presentation/widgets`
Expected: no new errors from these files (errors from `app_settings_dialog.dart`'s still-pending migration in Task 7 are expected here — ignore those).

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/workspace/presentation/widgets/pdf_combine_extract_dialogs.dart lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart lib/src/features/workspace/presentation/widgets/quickstart_surface.dart lib/src/features/workspace/presentation/widgets/reader_inspector.dart lib/src/features/workspace/presentation/widgets/app_settings_tts_section.dart
git commit -m "refactor(theme): migrate remaining workspace dialogs off static WorkspaceColors"
```

---

## Task 7: `app_settings_dialog.dart` — migrate tokens + custom accent picker + reader background toggles

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`
- Test: `test/workspace/app_settings_theme_section_test.dart` (new)

**Interfaces:**
- Consumes: `WorkspaceSurfaceTokens.fromProfile(profile, context)` (Task 1), `ClarixThemeProfile.copyWith` (existing).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:clarix/src/core/theme_controller.dart';
import 'package:clarix/src/core/theme_profile.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/app_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  testWidgets('custom accent hex picker updates the profile', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    // Open the settings dialog via the exported helper against the same tree.
    await showAppSettingsDialog(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-accent-hex-field')), '3B82F6');
    await tester.tap(find.byKey(const Key('custom-accent-confirm')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    final ClarixThemeProfile profile = container.read(clarixThemeProvider).requireValue;
    expect(profile.accent, ClarixAccent.custom);
    expect(profile.customAccentColor, 0xFF3B82F6);
  });

  testWidgets('reader background toggles are visible and update the profile', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    await showAppSettingsDialog(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();

    expect(find.text('Warm paper page background'), findsOneWidget);
    await tester.tap(find.text('Warm paper page background'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    expect(
      container.read(clarixThemeProvider).requireValue.readerBookBackgroundOverride,
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace/app_settings_theme_section_test.dart`
Expected: FAIL — no hex field/keys/checkbox text exist yet.

- [ ] **Step 3: Migrate static tokens and add the new controls**

Apply the Task 3 mechanical rule to every `WorkspaceColors.X` in this file first (33 hits — same rule: use the already-built `colors` in each widget, or build `WorkspaceSurfaceTokens.fromProfile(profile, context)` where missing).

Then, in `_ThemeSettings.build` (which by this point in Step 3 has its own
`WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(profile, context);` from
the mechanical-rule pass), change the `onTap` for the `ClarixAccent.custom` swatch
specifically:

```dart
onTap: () => accent == ClarixAccent.custom
    ? _pickCustomAccent(context, ref, profile, colors)
    : notifier.setProfile(profile.copyWith(accent: accent)),
```

Add this method to `_ThemeSettings`:

```dart
Future<void> _pickCustomAccent(
  BuildContext context,
  WidgetRef ref,
  ClarixThemeProfile profile,
  WorkspaceSurfaceTokens colors,
) async {
  final TextEditingController controller = TextEditingController(
    text: (profile.customAccentColor ?? 0xFFE4E4E7)
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase(),
  );
  final int? picked = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final int? parsed = _parseHex(controller.text);
        return AlertDialog(
          title: const Text('Custom accent color'),
          content: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: parsed != null ? Color(parsed) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('custom-accent-hex-field'),
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixText: '#', hintText: 'RRGGBB'),
                  maxLength: 6,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('custom-accent-confirm'),
              onPressed: parsed == null
                  ? null
                  : () => Navigator.of(context).pop(parsed),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    ),
  );
  if (picked != null) {
    await ref.read(clarixThemeProvider.notifier).setProfile(
      profile.copyWith(accent: ClarixAccent.custom, customAccentColor: picked),
    );
  }
}

int? _parseHex(String text) {
  final String cleaned = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return null;
  return int.parse('FF$cleaned', radix: 16);
}
```

Finally, add two rows under the existing "Reader background" section, right after the
Import/Remove `Row`:

```dart
const SizedBox(height: 8),
CheckboxListTile(
  contentPadding: EdgeInsets.zero,
  controlAffinity: ListTileControlAffinity.leading,
  dense: true,
  title: const Text('Invert background image for dark mode'),
  value: profile.readerBackgroundInverted,
  onChanged: profile.readerBackgroundPath == null
      ? null
      : (bool? value) => notifier.setProfile(
            profile.copyWith(readerBackgroundInverted: value ?? false),
          ),
),
CheckboxListTile(
  contentPadding: EdgeInsets.zero,
  controlAffinity: ListTileControlAffinity.leading,
  dense: true,
  title: const Text('Warm paper page background'),
  value: profile.readerBookBackgroundOverride,
  onChanged: (bool? value) => notifier.setProfile(
    profile.copyWith(readerBookBackgroundOverride: value ?? false),
  ),
),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/workspace/app_settings_theme_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify no static references remain**

Run: `grep -n "WorkspaceColors\." lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart test/workspace/app_settings_theme_section_test.dart
git commit -m "feat(theme): custom accent hex picker and reader background toggles"
```

---

## Task 8: Reader background invert + book-override rendering

**Files:**
- Modify: `lib/src/features/reader/presentation/reader_viewer_pane.dart`
- Test: `test/reader/reader_viewer_pane_background_test.dart` (new, if a suitable lightweight
  harness exists for this widget — otherwise extend whatever existing reader pane test
  fixture the repo already uses; check `test/` for one before writing a new harness from
  scratch)

- [ ] **Step 1: Check for an existing reader_viewer_pane test harness**

Run: `find test -iname "*reader_viewer_pane*"`

If one exists, extend it with the two cases below inside its existing setup. If none
exists, this step's rendering logic is still covered adequately by Task 7's settings test
plus manual verification (Step 4) — skip adding a new harness rather than inventing
scaffolding for a widget this deep in the native-PDF-plugin tree (real PDF rendering can't
run in `flutter test`).

- [ ] **Step 2: Apply invert + book-override in `reader_viewer_pane.dart`**

Read `profile` from `ref.watch(clarixThemeProvider).value` alongside the existing
`readerBackgroundPath` read (same provider, so no new watch needed — just also destructure
`readerBackgroundInverted` and `readerBookBackgroundOverride`). Wrap the existing
`Image.file(...)` for the background:

```dart
if (readerBackgroundPath case final String path)
  Positioned.fill(
    child: readerBackgroundInverted
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              -1, 0, 0, 0, 255,
              0, -1, 0, 0, 255,
              0, 0, -1, 0, 255,
              0, 0, 0, 1, 0,
            ]),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
          )
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
  ),
```

And change the `PdfViewerParams.backgroundColor` line:

```dart
backgroundColor: readerBookBackgroundOverride
    ? const Color(0xFFF3ECD9)
    : (readerBackgroundPath == null
        ? widget.colors.viewerBackground
        : Colors.transparent),
```

- [ ] **Step 3: Compile-check**

Run: `flutter analyze lib/src/features/reader/presentation/reader_viewer_pane.dart`
Expected: no new errors.

- [ ] **Step 4: Manual verification**

Run the app, import a background image, toggle "Invert background image for dark mode" and
confirm the image visibly inverts; toggle "Warm paper page background" and confirm the area
around PDF pages turns the warm paper tone regardless of whether a background image is set.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/reader/presentation/reader_viewer_pane.dart
git commit -m "feat(theme): apply reader background invert and book-background override"
```

---

## Task 9: Delete `WorkspaceColors`, final verification

**Files:**
- Modify: `lib/src/core/workspace_surface_tokens.dart` (remove the now-unused static class,
  if Task 1 left it in place for incremental migration — check first; the Task 1 replacement
  above already omits it, so this task is really the verification/cleanup pass)

- [ ] **Step 1: Confirm zero remaining references**

Run: `grep -rn "WorkspaceColors\." lib`
Expected: no output. If any remain, migrate them using the Task 3 mechanical rule before
proceeding — every consumer must be done by this point.

- [ ] **Step 2: Full analyzer pass**

Run: `flutter analyze`
Expected: no errors (warnings pre-existing and unrelated to this feature are fine — cross-
check against `git status` to confirm they're in files this plan never touched).

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: PASS, plus the same pre-existing-and-unrelated failures noted in prior sessions
(if any) — confirm via `git status` that failing tests live in files this plan didn't touch.

- [ ] **Step 4: Manual verification**

Run the app on Windows. For each of System/Light/Dark: confirm the sidebar, dialogs (open
Settings), reader chrome, and native shadcn components (buttons, inputs) all visibly switch.
For each of the 9 accent presets plus a custom hex color: confirm swatches highlight
correctly, workspace panels tint, and shadcn buttons/inputs pick up the accent. Confirm the
Settings dialog "updates apply immediately" without needing to reopen it (matches the
original 2026-08-05 design's requirement).

- [ ] **Step 5: Commit (only if Steps 1-3 required fixes)**

```bash
git add -A
git commit -m "fix(theme): final cleanup pass after full reskin migration"
```

If nothing needed fixing, skip — nothing to commit.
