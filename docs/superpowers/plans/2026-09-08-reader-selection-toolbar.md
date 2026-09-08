# Reader Selection Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a persistent, compact reader selection toolbar for annotations and document actions.

**Architecture:** PDFRx's `buildContextMenu` renders a Clarix toolbar using its selection delegate and anchor coordinates. Reader callbacks perform actions then use one dismissal helper. The workspace notifier persists note anchors in existing document metadata.

**Tech Stack:** Flutter, Riverpod, PDFRx, existing document metadata persistence.

**Spec:** `docs/superpowers/specs/2026-09-08-reader-selection-toolbar-design.md`

## Global Constraints

- Reuse `ClarixThemeProfile.highlightPalette` and `highlightOpacity`.
- Preserve existing page-only notes and highlight persistence.
- Clear PDFRx selection after every terminal toolbar action, outside tap, and Escape.

### Task 1: Persist note selection anchors

**Files:**

- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Test: `test/workspace/workspace_notifier_test.dart`

**Interfaces:** `addNote` gains optional `selectedText`, `pageRects`, and `colorValue` arguments, stored in the new `DocumentAnnotation`.

- [ ] Write a failing notifier test that calls `addNote` with text and a `Rect`, then asserts those fields survive in document metadata.
- [ ] Extend `addNote` with defaulted anchor arguments and store them.
- [ ] Run `flutter test test/workspace/workspace_notifier_test.dart` and commit.

### Task 2: Render reader selection toolbar

**Files:**

- Modify: `lib/src/features/reader/presentation/reader_viewer_pane.dart`
- Modify: `lib/src/features/reader/presentation/reader_read_aloud.dart`
- Modify: `lib/src/features/reader/presentation/reader_viewer_interactions.dart`
- Modify: `lib/src/features/reader/presentation/reader_viewer_components.dart`
- Test: `test/reader/reader_selection_toolbar_test.dart`

**Interfaces:** A custom PDFRx context-menu builder consumes `PdfViewerContextMenuBuilderParams` and emits the compact toolbar. Terminal actions share one selection/menu dismissal helper.

- [ ] Add failing widget tests for the toolbar action and persisted palette keys.
- [ ] Configure `PdfViewerParams.buildContextMenu` and render Copy, Ask AI, Note, Bookmark, Read aloud, palette circles, and More colours.
- [ ] Use selected ranges to persist highlights and note anchors; send Ask AI as a grounded query.
- [ ] Run the focused reader tests and commit.

### Task 3: Dismiss selection consistently

**Files:**

- Modify: `lib/src/features/reader/presentation/reader_viewer_pane.dart`
- Modify: `lib/src/features/reader/presentation/reader_viewer_interactions.dart`
- Test: `test/reader/reader_selection_toolbar_test.dart`

- [ ] Add failing tests for PDF background click and Escape dismissal.
- [ ] Route both paths through the shared selection-clearing helper without blocking annotation clicks.
- [ ] Run `flutter test test/reader/reader_selection_toolbar_test.dart test/architecture/persistence_schema_compatibility_test.dart` and commit.
