# Workspace Theming Design

## Goal

Make Clarix visually configurable through a persistent, tabbed settings surface. Theme mode and accent color must update the full workspace from shared tokens; reader backgrounds apply only behind the PDF surface; new highlights use a selected color palette.

## Theme profile

Persist a `ClarixThemeProfile` locally with:

- `mode`: system, light, or dark.
- `accent`: Default, Gray, Sepia, Grass, Cherry, Sky, Solarized, Gruvbox, Nord, or custom.
- Reader background selection: a built-in asset or imported image copied into application support storage.
- Reader options: dark-mode image inversion and book/paper color override.
- Highlight palette: Red, Yellow, Green, Blue, Violet and no more than ten custom colors; one active color and opacity for new highlights.

Existing users migrate to the current dark-neutral appearance. Existing annotation colors do not change.

## Tokens and application

`ThemeController` exposes the current profile and resolved tokens: canvas, canvas-raised, panel, panel-raised, text levels, borders, accent, accent soft/border, selection, warning, and reader surface. Workspace widgets consume resolved tokens instead of static hard-coded colors, and updates apply immediately.

Reader background imagery is painted only behind the PDF reading surface. It never affects title chrome, sidebars, AI pane, or dialogs. Missing/deleted imported files fall back safely to the default background.

## Settings

Settings becomes a rounded tabbed dialog matching the supplied references. The Font tab controls reader font settings. The Theme tab controls system/light/dark mode, accent grid, reader background grid/import, image inversion, book-color override, highlight palette/custom picker, and opacity. Existing provider and storage controls remain available in their own settings tab.

Imported images are copied into Clarix-owned app-support storage. Removing an imported image removes only that owned copy.

## Verification

Test profile serialization and migration, token resolution across modes/accents, reader-only background rendering, imported image fallback, custom highlight limit/selection, and settings-tab behavior.
