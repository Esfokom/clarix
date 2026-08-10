# PDF Bookmarks and Highlights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide PDF-native bookmarks and highlights with editor history, save controls, keyboard shortcuts, and unsaved-change protection.

**Architecture:** A Dart edit-session domain layer provides immediate reader state and command undo/redo. The Rust bridge uses `lopdf` to read/write standard PDF outlines and highlight annotation objects. UI widgets bind reader interactions to session commands, and save serializes the session back to the open file.

**Tech Stack:** Flutter, Riverpod, pdfrx, flutter_rust_bridge, Rust, lopdf, flutter_test, cargo test.

## Global Constraints

- Work directly on `main`; do not create or use a worktree.
- Save bookmarks and highlights into the original PDF, never only in Clarix metadata.
- Preserve unrelated existing PDF content and annotations.
- Save, Undo, and Redo live at the left edge of the title bar and accurately expose disabled states.
- Support `Ctrl+S`, `Ctrl+Z`, and `Ctrl+Shift+Z`.

---

### Task 1: Model PDF editor state and reversible commands

**Files:**
- Create: `lib/src/features/workspace/domain/pdf_edit_session.dart`
- Test: `test/workspace_pdf/pdf_edit_session_test.dart`

**Interfaces:** `PdfEditSession.apply(PdfEditOperation)`, `undo()`, `redo()`, and `markSaved()` expose `isDirty`, `canUndo`, and `canRedo`.

- [ ] Write a failing test proving a newly-added bookmark makes the session dirty, undo restores an empty clean session, redo restores the bookmark, and a new edit clears redo.
- [ ] Run `flutter test test/workspace_pdf/pdf_edit_session_test.dart` and confirm the missing API fails.
- [ ] Implement immutable bookmark/highlight models and command history storing forward/inverse operations.
- [ ] Re-run `flutter test test/workspace_pdf/pdf_edit_session_test.dart` and commit only Task 1 files.

### Task 2: Read and write standard PDF bookmarks and highlights

**Files:**
- Create: `rust/clarix_pdf_oxide/src/pdf_annotations.rs`
- Modify: `rust/clarix_pdf_oxide/src/api.rs`, `rust/clarix_pdf_oxide/src/lib.rs`, and `lib/src/core/ffi/api.dart`
- Test: Rust module tests in `pdf_annotations.rs`

**Interfaces:** `read_pdf_annotations(path)` returns outlines and highlights; `save_pdf_annotations(request)` replaces the file atomically after emitting `/Outlines` and `/Highlight` objects.

- [ ] Write failing Rust fixture tests that assert an emitted highlight contains `/Subtype /Highlight` and the exact expected `/QuadPoints`, and an outline entry resolves to its expected page.
- [ ] Run `cargo test pdf_annotations --manifest-path rust/clarix_pdf_oxide/Cargo.toml` and confirm failure.
- [ ] Implement `lopdf` traversal/serialization with temporary sibling output and original-file replacement; preserve all non-Clarix annotations.
- [ ] Regenerate bridge code, run `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml`, and commit Task 2 files.

### Task 3: Integrate editor sessions with workspace

**Files:**
- Modify: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart` and `workspace_providers.dart`
- Test: `test/workspace_pdf/workspace_notifier_pdf_edits_test.dart`

**Interfaces:** notifier methods `addBookmark`, `renameBookmark`, `addHighlight`, `updateHighlight`, `undoPdfEdit`, `redoPdfEdit`, `savePdfEdits`, and `discardPdfEdits`.

- [ ] Write a failing notifier test asserting save clears dirty state only after a successful native save, while save failure preserves dirty state.
- [ ] Run its isolated `flutter test` command and confirm failure.
- [ ] Load sessions on document open, forward edit operations to the session, and invalidate/reload the viewer after native save.
- [ ] Re-run the notifier test and commit Task 3 files.

### Task 4: Implement bookmark, highlight, and docked-colour UI

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/pdf_editing_widgets.dart`
- Modify: `document_workspace.dart` and `workspace_sidebar.dart`
- Test: `test/workspace_pdf/pdf_editing_widgets_test.dart`

**Interfaces:** `PdfBookmarksPane`, `PdfSelectionContextMenu`, `PdfHighlightEditor`, and `DockedColourInspector` consume the active `PdfEditSession` and notifier commands.

- [ ] Write failing widget tests for bookmark rename, bookmark navigation, Copy, swatch highlight creation, custom-colour update, and highlight delete.
- [ ] Run the widget test file and confirm missing widgets/behavior fail.
- [ ] Render highlight overlays and selection menu, bind Clipboard copy, and add a docked swatch/HSV inspector plus highlight editor popover.
- [ ] Re-run the widget test file and commit Task 4 files.

### Task 5: Add chrome commands, shortcuts, and dirty-close confirmation

**Files:**
- Modify: `desktop_window_chrome.dart`, `document_workspace.dart`, and `workspace_screen.dart`
- Test: `test/workspace_pdf/pdf_editing_commands_test.dart`

**Interfaces:** `PdfEditCommands` exposes active session command state to the chrome; close guards return save/discard/cancel decisions.

- [ ] Write failing widget tests for disabled initial Save/Undo/Redo, Ctrl+S, Ctrl+Z, Ctrl+Shift+Z, and a dirty close dialog with Save, Discard, and Cancel outcomes.
- [ ] Run the focused test command and confirm failure.
- [ ] Add title-bar controls, Flutter shortcuts/actions, tab-close interception, and window close interception through `window_manager`.
- [ ] Run `flutter test`, `flutter analyze`, and `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml`; commit Task 5 files after all pass.
