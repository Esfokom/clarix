# AI Chat Markdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render Markdown and LaTex math in both user and assistant chat bubbles.

**Architecture:** A shared bubble-content widget uses `flutter_markdown_plus` for Markdown blocks and `flutter_math_fork` builders for inline and display math. Bubble layout, messages, streaming state, and citations remain unchanged.

**Tech Stack:** Flutter, flutter_markdown_plus, flutter_math_fork, flutter_test.

## Global Constraints

- Both user and assistant bubble content renders Markdown and inline/display LaTex.
- Malformed LaTex renders as literal text and must not crash a chat view.
- Preserve role-specific bubble colors, existing citations, and streaming partial responses.

---

### Task 1: Add rendering dependencies and shared content widget

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock` via `flutter pub get`
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Create: `test/workspace_ai/ai_side_pane_test.dart`

**Interfaces:**

- Produce `_MarkdownMessageContent({required String source, required TextStyle style})` used by `_MessageBubble` for both roles.

- [ ] **Step 1: Write failing widget tests**

Render user and assistant `ComposerMessage` values through `AiSidePane`; assert Markdown heading/list/code widgets appear for both roles and the raw Markdown markers are not presented as a plain `Text` body. Include `$x^2$` and `$$\\frac{a}{b}$$` and assert `Math` widgets exist.

```dart
expect(find.byType(Math), findsNWidgets(2));
expect(find.textContaining('**bold**'), findsNothing);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`

Expected: FAIL because bubbles use `Text` and the dependencies are unavailable.

- [ ] **Step 3: Add packages and implement shared Markdown/math content**

Add compatible `flutter_markdown_plus` and `flutter_math_fork` constraints to `pubspec.yaml`, run `flutter pub get`, then replace bubble `Text` content with a shared `MarkdownBody`. Configure role-specific Markdown styles from the existing bubble `TextStyle`; map inline and block LaTex syntax to `Math.tex`; use a builder error fallback that renders the original source string.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add pubspec.yaml pubspec.lock lib/src/features/workspace/presentation/widgets/ai_side_pane.dart test/workspace_ai/ai_side_pane_test.dart; git commit -m "feat: render chat markdown and math"`

### Task 2: Verify chat regressions

**Files:**

- Modify only when verification exposes a defect.

- [ ] **Step 1: Run chat tests and analysis**

Run: `flutter test test/workspace_ai`

Run: `flutter analyze`

Expected: both exit 0.

- [ ] **Step 2: Inspect final diff**

Run: `git diff HEAD~1..HEAD --check`

Run: `git status --short`

Confirm both roles render Markdown/math and the worktree contains no unintended files.
