# Workspace Panes and Citations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add resizable/collapsible reader and AI panes plus previewable, clickable AI citation chips.

**Architecture:** Persist pane geometry in `WorkspaceSession`; a workspace shell owns clamped drag/collapse behavior. Assistant citations become interactive chips. Clicks dispatch one-shot document/page navigation requests that the existing PDF viewer consumes with its animated controller.

**Tech Stack:** Flutter, Riverpod, pdfrx, flutter_test.

## Global Constraints

- Expanded pane widths clamp to 200–480 logical pixels.
- Collapsed toggles remain available on the central reader edge.
- Citation previews reuse the existing `PdfDocumentRefFile`; clicks do not reopen PDFs.
- Page jumps must be animated and consumed only once.

---

### Task 1: Persist pane layout state

**Files:**

- Modify: `lib/src/core/models.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Test: `test/workspace_ai/workspace_ai_migration_test.dart`

**Interfaces:**

- Add `leftPaneWidth`, `rightPaneWidth`, `leftPaneCollapsed`, and `rightPaneCollapsed` to `WorkspaceSession`, with JSON migration defaults.
- Add notifier methods `setLeftPaneWidth(double)`, `setRightPaneWidth(double)`, `toggleLeftPane()`, `toggleRightPane()`.

- [ ] **Step 1: Write failing state tests**

Assert JSON restoration clamps persisted widths and defaults legacy sessions to expanded panes. Assert notifier width methods clamp 100 to 200 and 900 to 480.

```dart
expect(restored.leftPaneWidth, 200);
expect(restored.rightPaneWidth, 480);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/workspace_ai_migration_test.dart`

Expected: FAIL because session geometry and notifier methods do not exist.

- [ ] **Step 3: Implement state and persistence**

Define constants `minWorkspacePaneWidth = 200` and `maxWorkspacePaneWidth = 480`. Add session fields, JSON keys, copy-with arguments, backward-compatible defaults, and notifier methods that clamp then commit the session.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/workspace_ai_migration_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/core/models.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_ai/workspace_ai_migration_test.dart; git commit -m "feat: persist workspace pane layout"`

### Task 2: Render draggable, collapsible panes

**Files:**

- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Create: `test/workspace_ai/workspace_pane_layout_test.dart`

**Interfaces:**

- Consume the session pane fields and notifier geometry methods.
- Produce left/right `MouseRegion` drag handles and center-edge collapse/expand buttons.

- [ ] **Step 1: Write failing layout tests**

Render the workspace, drag each divider past its limits, and assert notifier state is clamped. Tap collapsed edge controls and assert the matching pane disappears while its expand button remains visible.

```dart
await tester.drag(find.byKey(const Key('left-pane-resizer')), const Offset(-500, 0));
expect(session.leftPaneWidth, 200);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/workspace_pane_layout_test.dart`

Expected: FAIL because resizer and edge-control keys are absent.

- [ ] **Step 3: Implement the shell controls**

Use `SizedBox(width: session.leftPaneWidth/rightPaneWidth)` for expanded panes. Add 6px `GestureDetector` dividers keyed `left-pane-resizer` and `right-pane-resizer`; update widths from horizontal drag delta. Add keyed center-edge controls `left-pane-toggle` and `right-pane-toggle` with direction-aware chevrons. Remove collapsed content from layout but leave its control adjacent to the reader.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/workspace_pane_layout_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/features/workspace/presentation/widgets/document_workspace.dart lib/src/features/workspace/presentation/widgets/workspace_sidebar.dart lib/src/features/workspace/presentation/widgets/ai_side_pane.dart test/workspace_ai/workspace_pane_layout_test.dart; git commit -m "feat: resize and collapse workspace panes"`

### Task 3: Add citation previews and animated page navigation

**Files:**

- Modify: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Test: `test/workspace_ai/ai_side_pane_test.dart`
- Create: `test/workspace_ai/citation_navigation_test.dart`

**Interfaces:**

- Add `PageNavigationRequest { documentId, pageNumber, requestId }` to feature state.
- Add `navigateToCitation(CitationSnippet)` and `consumePageNavigationRequest(String requestId)` to the notifier.

- [ ] **Step 1: Write failing citation tests**

Render an assistant message with citations and assert `citation-page-4` is present. Hover it and assert `citation-preview-page-4` appears. Tap it and assert a page-navigation request targets the citation document/page; consuming its request ID clears it.

```dart
await tester.tap(find.byKey(const Key('citation-page-4')));
expect(state.pendingPageNavigation!.pageNumber, 4);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart test/workspace_ai/citation_navigation_test.dart`

Expected: FAIL because citation chips and navigation requests are absent.

- [ ] **Step 3: Implement chips, preview, and jump consumption**

Render assistant `message.citations` as `MouseRegion`/`Tooltip` chips under the Markdown body. On hover, show an overlay/card keyed by page number using the cited tab’s existing `PdfDocumentRefFile` and `PdfPageView`. On tap, select the cited tab then set a unique page-navigation request. In the active viewer, listen for a matching request, call its existing animated page-navigation controller method, then consume the request after dispatch.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart test/workspace_ai/citation_navigation_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/features/workspace/domain/workspace_feature_state.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/features/workspace/presentation/widgets/ai_side_pane.dart lib/src/features/workspace/presentation/widgets/document_workspace.dart test/workspace_ai/ai_side_pane_test.dart test/workspace_ai/citation_navigation_test.dart; git commit -m "feat: preview and navigate AI citations"`

### Task 4: Verify complete workspace interaction

- [ ] **Step 1: Run workspace tests**

Run: `flutter test test/workspace_ai`

Expected: PASS.

- [ ] **Step 2: Run static and desktop build checks**

Run: `flutter analyze`

Run: `flutter build windows`

Expected: both exit 0.

- [ ] **Step 3: Inspect final changes**

Run: `git diff HEAD~3..HEAD --check`

Run: `git status --short`

Confirm pane persistence, clamped resizing, retained collapsed controls, preview reuse, and one-shot animated navigation.
