# Full Theming Reskin: Light/Dark Mode, Accent, Reader Background Options

## Problem

`ClarixThemeProfile` (mode/accent/custom accent/reader background/invert/book-override)
is persisted and has Settings UI, but most of it does nothing:

- `app.dart` builds identical `theme`/`darkTheme` (`Brightness.dark` always) — Light mode has no visual effect.
- Accent tints custom workspace panels (`WorkspaceSurfaceTokens`) but never reaches
  shadcn's `ShadThemeData.colorScheme` (hardcoded zinc) — native components ignore it.
- `ClarixAccent.custom` has no color picker — unreachable.
- `readerBackgroundInverted` / `readerBookBackgroundOverride` are persisted fields with
  no Settings UI and are never read by the reader.

## Goals

- Light/system/dark mode visibly changes the whole app (custom panels + native components).
- Accent color reaches both custom panels and native shadcn components.
- Custom accent color is pickable via a hex input.
- Reader background invert and book-override are real, toggleable, and applied.

## Non-goals

- No new color-picker dependency (hex text field + swatch preview instead).
- No redesign of the accent palette itself, highlight palette, or font system.
- `backdrop` (modal scrim) and `warning` stay constant across brightness — scrims/warnings
  read fine in both themes.

## Design

### Brightness resolution

`app.dart` builds two `ShadThemeData`s (light, dark) and passes both to `ShadApp` with
`themeMode: profile.mode`; Flutter's app widget resolves system/light/dark automatically —
no manual system-brightness lookup needed there.

Everywhere else, read the already-resolved `Theme.of(context).brightness` (authoritative,
correct for the `system` case for free) rather than re-deriving it from `profile.mode`.

### Native component theming (`app.dart`)

```dart
ShadThemeData _buildTheme(ClarixThemeProfile profile, Brightness brightness) {
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

`ShadApp(theme: _buildTheme(profile, Brightness.light), darkTheme: _buildTheme(profile, Brightness.dark), themeMode: profile.mode, ...)`.

### `WorkspaceSurfaceTokens` — brightness-aware base palette

Two private static palettes replace the single hardcoded `WorkspaceColors` set:

```
dark:  canvas #2F2F2F, canvasRaised #343434, panel #343434, panelRaised #3A3A3A,
       viewerBackground #292929, border #484848, textStrong #FAFAFA,
       textMuted #A1A1AA, textFaint #71717A   (today's values, unchanged)
light: canvas #F4F4F5, canvasRaised #FAFAFA, panel #FFFFFF, panelRaised #F4F4F5,
       viewerBackground #D4D4D8, border #E4E4E7, textStrong #18181B,
       textMuted #52525B, textFaint #A1A1AA
```

`backdrop` (`0xAA020203`) and `warning` (`0xFFF59E0B`) stay constant in both.

`WorkspaceSurfaceTokens.fromProfile(ClarixThemeProfile profile, BuildContext context)`
(new required `context` param) resolves `Theme.of(context).brightness`, selects the base
palette, then blends the accent tint exactly as today. `WorkspaceSurfaceTokens` gains
`viewerBackground` and `backdrop` fields (parity with the old static `WorkspaceColors`, so
every consumer can fully switch off the static class).

`WorkspaceColors` (the static class) is deleted once all consumers migrate — no dual system
left behind to drift out of sync.

### Migrating the 18 consuming files

Mechanical per file: replace `WorkspaceColors.X` with the in-scope `colors.X` (already
threaded as a field/param in most of these widgets); for files not yet building
`WorkspaceSurfaceTokens.fromProfile(...)`, add it via `ref.watch(clarixThemeProvider)` +
`context`, following the existing pattern in `document_workspace.dart`/`workspace_sidebar.dart`.
Files, by static-usage count (from a repo scan): `app_settings_dialog.dart` (33),
`pdf_utilities_dialogs.dart` (22), `reader_viewer_components.dart` (20),
`pdf_combine_extract_dialogs.dart` (16), `app_settings_tts_section.dart` (13),
`quickstart_surface.dart` (12), `reader_inspector.dart` (11), `workspace_screen.dart` (9),
`workspace_body.dart` (7), `ai_side_pane.dart` (6), `workspace_common.dart` (6),
`workspace_sidebar.dart` (6), `document_workspace.dart` (4), `ai_composer.dart` (3),
`inline_page_reference.dart` (3), `reader_viewer_pane.dart` (2),
`provider_editor_dialog.dart` (1), plus `workspace_surface_tokens.dart` itself.

### Reader background invert / book-override

In `reader_viewer_pane.dart`, where the background `Image.file` is painted:

```dart
if (readerBackgroundPath case final String path)
  Positioned.fill(
    child: profile.readerBackgroundInverted
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              -1, 0, 0, 0, 255,
              0, -1, 0, 0, 255,
              0, 0, -1, 0, 255,
              0, 0, 0, 1, 0,
            ]),
            child: Image.file(File(path), fit: BoxFit.cover, errorBuilder: ...),
          )
        : Image.file(File(path), fit: BoxFit.cover, errorBuilder: ...),
  ),
```

`readerBookBackgroundOverride`, when true, replaces the `backgroundColor` passed to
`PdfViewerParams` (currently `widget.colors.viewerBackground`) with a fixed warm paper
tone `Color(0xFFF3ECD9)`, independent of `readerBackgroundPath`.

### Settings UI additions (`app_settings_dialog.dart`, `_ThemeSettings`)

- Two new `CheckboxListTile`-style rows under "Reader background": "Invert background image
  for dark mode" (enabled only when `readerBackgroundPath != null`) and "Warm paper page
  background" (always available).
- Custom accent: clicking the `ClarixAccent.custom` swatch opens a small dialog with a hex
  text field (`#RRGGBB`, validated) and a live preview swatch; confirming calls
  `setProfile(profile.copyWith(accent: ClarixAccent.custom, customAccentColor: parsed))`.

## Testing

- `WorkspaceSurfaceTokens.fromProfile` unit tests: dark/light base selection by
  `Brightness`, accent tint blending unchanged, `backdrop`/`warning` constant across modes.
- `app.dart`/`_buildTheme`: light and dark `ShadColorScheme.primary` reflect the accent.
- Widget test: reader background invert applies a `ColorFiltered` ancestor of the `Image.file`
  when `readerBackgroundInverted` is true; book-override changes `PdfViewerParams.backgroundColor`.
- Settings widget test: custom accent hex picker round-trips a valid hex into
  `customAccentColor`; invalid hex is rejected without changing the profile.
- Manual: toggle mode/accent/custom color/background options in a running app and confirm
  every panel (sidebar, dialogs, reader chrome) updates immediately, matching the original
  spec's "updates apply immediately" requirement.
