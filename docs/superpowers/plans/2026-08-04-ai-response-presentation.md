# AI Response Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Present document-chat responses as full-width readable content, while moving neutral, animated loading feedback to the composer area.

**Architecture:** Keep the existing chat state and streaming behavior unchanged. Refine only `AiSidePane` presentation: remove provider/runtime copy from its header, add a self-contained composer loading indicator, and render assistant Markdown directly on the pane background. User messages retain compact, right-aligned bubbles.

**Tech Stack:** Flutter, Riverpod, `flutter_markdown_plus`, `flutter_math_fork`, `flutter_test`.

## Global Constraints

- Do not alter RAG retrieval, provider requests, or chat persistence.
- Never expose a provider name or raw runtime phase in the visible loading UI.
- Keep the composer stop behavior available while a request is pending.
- Preserve Markdown, math rendering, and interactive citation chips.

---

### Task 1: Add presentation regression coverage

**Files:**
- Modify: `test/workspace_ai/ai_side_pane_test.dart`

1. Add a failing widget test for a busy conversation that verifies the composer-area loader is present, provider-specific status copy is absent, and the loading word advances after five seconds.
2. Add assertions that user messages use the compact bubble key and assistant messages use a full-width content key without a bubble container.
3. Retain coverage for Markdown/math rendering and citation chips.
4. Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`
5. Expected: FAIL until Task 2 is complete.

### Task 2: Implement the chat presentation refinement

**Files:**
- Modify: `lib/src/features/workspace/presentation/ai_side_pane.dart`

1. Remove the header status badge, provider disclosure, and raw phase-based loading copy.
2. Add a compact stateful loader immediately above the composer when chat is busy. It must have a pulsing indicator, a shimmering word, and rotate through `Reading`, `Tracing`, `Grounding`, `Pondering`, `Synthesizing`, and `Citing` every five seconds.
3. Keep the existing composer and stop action behavior intact.
4. Split message presentation by role: retain the current compact user bubble and render assistant Markdown/citations directly on the pane background with 16 px horizontal padding and available-width layout.
5. Add stable widget keys only where needed for the regression tests.
6. Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`
7. Expected: PASS.

### Task 3: Verify the affected workspace surface

**Files:**
- Verify: `lib/src/features/workspace/presentation/ai_side_pane.dart`
- Verify: `test/workspace_ai/ai_side_pane_test.dart`

1. Run: `flutter analyze lib/src/features/workspace/presentation/ai_side_pane.dart test/workspace_ai/ai_side_pane_test.dart`
2. Run: `flutter test test/workspace_ai`
3. Inspect the diff to confirm no provider or RAG behavior changed.
4. Commit the implementation and report the verification results.
