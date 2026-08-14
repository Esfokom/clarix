# Right Tool Window Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the Document inspector and Clarix AI pane through a compact far-right vertical tool-window rail.

**Architecture:** `WorkspaceSession` persists the selected right tool window (`none`, `document`, or `ai`). `WorkspaceBody` renders one 40 px rail plus at most one content pane. Narrow layouts preserve the AI overlay.

**Tech Stack:** Flutter, Riverpod, flutter_test.

## Global Constraints

- The rail is fixed at 40 px on the far right of desktop layouts.
- Selecting the active tool closes it; selecting another tool replaces it.
- Only one right tool window is visible at a time.
- Existing narrow-layout AI overlay behavior remains unchanged.

---

### Task 1: Persist right tool-window selection

**Files:**

- Modify: `lib/src/core/models.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Test: `test/workspace_ai/workspace_ai_migration_test.dart`

**Interfaces:**

- Produce `enum RightToolWindow { none, document, ai }`.
- Add `rightToolWindow` to `WorkspaceSession` and `selectRightToolWindow(RightToolWindow)` to `WorkspaceNotifier`.

- [ ] **Step 1: Write failing persistence tests**

Assert legacy session JSON defaults to `RightToolWindow.none`; assert JSON round-trip retains `ai`; assert selecting the same tool twice leaves `none`.

```dart
expect(WorkspaceSession.fromJson(<String, dynamic>{}).rightToolWindow, RightToolWindow.none);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/workspace_ai_migration_test.dart`

Expected: FAIL because the enum and session field do not exist.

- [ ] **Step 3: Implement session/notifier state**

Add enum, migrated JSON key, copy-with field, and notifier method. The notifier maps a request equal to the current selection to `none`; all other requests become the new selection and commit the session.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/workspace_ai_migration_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/core/models.dart lib/src/features/workspace/application/workspace_notifier.dart test/workspace_ai/workspace_ai_migration_test.dart; git commit -m "feat: persist right tool window selection"`

### Task 2: Render the desktop rail and exclusive tool pane

**Files:**

- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Create: `test/workspace_ai/right_tool_window_rail_test.dart`

**Interfaces:**

- Consume `session.rightToolWindow` and notifier selection method.
- Produce keyed rail buttons `right-tool-document` and `right-tool-ai`.

- [ ] **Step 1: Write failing widget tests**

At desktop width, assert both rail buttons exist, neither pane is visible initially, tapping Document shows only `ReaderInspector`, tapping AI shows only `AiSidePane`, and tapping AI again closes it.

```dart
await tester.tap(find.byKey(const Key('right-tool-ai')));
expect(find.byType(AiSidePane), findsOneWidget);
expect(find.byType(ReaderInspector), findsNothing);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/right_tool_window_rail_test.dart`

Expected: FAIL because the rail and keys are absent.

- [ ] **Step 3: Implement the rail**

Replace current `composerExpanded` desktop right-pane selection with a fixed-width `DecoratedBox` rail after the optional right pane. Use icon-only vertical `ShadIconButton`s and tooltips. Render exactly one `SizedBox(width: session.rightPaneWidth)` content pane for the selected enum. Keep the existing AI overlay condition for widths below the inspector breakpoint.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/right_tool_window_rail_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add lib/src/features/workspace/presentation/widgets/workspace_body.dart test/workspace_ai/right_tool_window_rail_test.dart; git commit -m "feat: add right tool window rail"`

### Task 3: Verify workspace regressions

- [ ] **Step 1: Run workspace tests**

Run: `flutter test test/workspace_ai`

Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: exit 0.

- [ ] **Step 3: Inspect final change set**

Run: `git diff HEAD~2..HEAD --check`

Run: `git status --short`

Confirm the rail is always present on desktop, selection is exclusive and closable, and the narrow AI overlay remains available.
