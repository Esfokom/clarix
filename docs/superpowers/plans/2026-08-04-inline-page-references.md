# Inline Page References Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn natural page references in assistant Markdown into hover-preview, click-to-navigate PDF references without detached citation chips.

**Architecture:** Add a focused Markdown inline syntax and element builder that recognize page-reference prose and produce an interactive document-page widget. Keep PDF preview and navigation in that reusable widget, and have `AiSidePane` provide the active PDF tab as its target. The existing retrieval citation records remain available to the RAG flow but are not rendered as trailing chips.

**Tech Stack:** Flutter, Riverpod, `flutter_markdown_plus`, `markdown`, `pdfrx`, `flutter_test`.

## Global Constraints

- Match assistant Markdown only; user messages remain ordinary Markdown.
- Match `page N`, `pages N and M`, `pages N–M`, and `pages N-M`.
- A multi-page match has one target: its starting page.
- Do not rewrite model text or append standalone citation chips.
- Use the already-open active PDF for hover preview and animated page navigation.
- Leave RAG retrieval, provider requests, and citation persistence unchanged.

---

### Task 1: Add failing inline-reference behavior coverage

**Files:**
- Modify: `test/workspace_ai/ai_side_pane_test.dart`

**Interfaces:**
- Consumes: `AiSidePane(state, activeTab)`.
- Produces: regression coverage for inline page-reference rendering.

- [ ] **Step 1: Write failing assistant-prose tests**

Add an assistant message containing `Case study (page 2)` and `Organizational structure (pages 7–8)`, then assert that `inline-page-reference-2` and `inline-page-reference-7` exist. Add a separate assistant message with no page wording and assert no `inline-page-reference-*` widget exists. Assert that the legacy `citation-page-*` chip keys are absent.

- [ ] **Step 2: Run the focused test to verify failure**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`

Expected: FAIL because assistant Markdown has no inline page-reference syntax or builder.

- [ ] **Step 3: Commit the regression tests**

```powershell
git add test/workspace_ai/ai_side_pane_test.dart
git commit -m "test: cover inline document page references"
```

### Task 2: Build the reusable inline page-reference renderer

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/inline_page_reference.dart`

**Interfaces:**
- Consumes: `DocumentTabState? activeTab`, `WidgetRef`, `pdfDocumentRefProvider`, and `WorkspaceNotifier.navigateToCitation(CitationSnippet)`.
- Produces: `InlinePageReferenceSyntax extends markdown.InlineSyntax` and `InlinePageReferenceBuilder extends MarkdownElementBuilder`.

- [ ] **Step 1: Implement the Markdown syntax**

Create `InlinePageReferenceSyntax` with a case-insensitive pattern matching `page N`, `pages N and M`, `pages N–M`, and `pages N-M`. In `onMatch`, write the original matched text into an `inline-page-reference` element and store the parsed starting page as `element.attributes['page']`.

```dart
class InlinePageReferenceSyntax extends markdown.InlineSyntax {
  InlinePageReferenceSyntax()
      : super(r'(?i)\\bpages?\\s+(\\d+)(?:(?:\\s*(?:and|[-–])\\s*)\\d+)?\\b');

  @override
  bool onMatch(markdown.InlineParser parser, Match match) {
    final markdown.Element element = markdown.Element.text(
      'inline-page-reference',
      match.group(0)!,
    )..attributes['page'] = match.group(1)!;
    parser.addNode(element);
    return true;
  }
}
```

- [ ] **Step 2: Implement the interactive element builder**

Create `InlinePageReferenceBuilder(activeTab: ...)`. Its `visitElementAfterWithContext` creates a lightweight `ConsumerStatefulWidget` keyed `inline-page-reference-$page`. The widget renders the original page text with accent styling, opens the existing `PdfPageView` preview on hover, and calls `navigateToCitation` with a `CitationSnippet(documentId: activeTab.documentId, pageNumber: page, ...)` on click. When the tab is null or missing, render non-interactive styled text and omit the preview.

- [ ] **Step 3: Ensure page previews are clipped and non-disruptive**

Use the current 220 × 270 preview treatment inside a `Stack(clipBehavior: Clip.none)` and a `Material` surface. Resolve the PDF with `pdfDocumentRefProvider(activeTab.filePath)` and display `PdfPageView(document: document, pageNumber: page)` after it loads.

- [ ] **Step 4: Format and statically analyze the new renderer**

Run: `dart format lib/src/features/workspace/presentation/widgets/inline_page_reference.dart; flutter analyze lib/src/features/workspace/presentation/widgets/inline_page_reference.dart`

Expected: PASS.

- [ ] **Step 5: Commit the reusable renderer**

```powershell
git add lib/src/features/workspace/presentation/widgets/inline_page_reference.dart
git commit -m "feat: add inline document page references"
```

### Task 3: Connect assistant Markdown and remove detached chips

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Test: `test/workspace_ai/ai_side_pane_test.dart`

**Interfaces:**
- Consumes: `InlinePageReferenceSyntax`, `InlinePageReferenceBuilder`, and the active `DocumentTabState?` passed from `AiSidePane`.
- Produces: assistant-only interactive inline references with no trailing citation widgets.

- [ ] **Step 1: Add the renderer dependencies**

Import `inline_page_reference.dart`. Pass `activeTab: widget.activeTab` into `_MessageBubble` and add the inline syntax plus builder only when `message.isUser` is false.

```dart
extensionSet: markdown.ExtensionSet(
  <markdown.BlockSyntax>[LatexBlockSyntax()],
  <markdown.InlineSyntax>[
    LatexInlineSyntax(),
    if (!isUser) InlinePageReferenceSyntax(),
  ],
),
builders: <String, MarkdownElementBuilder>{
  'latex': LatexElementBuilder(...),
  if (!isUser)
    'inline-page-reference': InlinePageReferenceBuilder(
      activeTab: activeTab,
    ),
},
```

- [ ] **Step 2: Remove standalone citation-chip rendering**

Delete the trailing `Wrap` of `_CitationChip`s and the `_CitationChip` widget. Do not change `CitationSnippet` models or notifier navigation; only remove the obsolete visual list.

- [ ] **Step 3: Run focused behavior coverage**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`

Expected: PASS, including page-2/page-7 inline keys and no detached chips.

- [ ] **Step 4: Commit the integration**

```powershell
git add lib/src/features/workspace/presentation/widgets/ai_side_pane.dart test/workspace_ai/ai_side_pane_test.dart
git commit -m "feat: render document pages inline in AI replies"
```

### Task 4: Verify the workspace surface

**Files:**
- Verify: `lib/src/features/workspace/presentation/widgets/inline_page_reference.dart`
- Verify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Verify: `test/workspace_ai/ai_side_pane_test.dart`

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze lib/src/features/workspace/presentation/widgets/inline_page_reference.dart lib/src/features/workspace/presentation/widgets/ai_side_pane.dart test/workspace_ai/ai_side_pane_test.dart`

Expected: PASS with no diagnostics.

- [ ] **Step 2: Run workspace and full regression suites**

Run: `flutter test test/workspace_ai; flutter test`

Expected: PASS.

- [ ] **Step 3: Inspect the scope and commit any final corrections**

Run: `git diff --check; git status --short`

Expected: only the renderer, AI pane, and regression test changes are committed; existing untracked planning files remain untouched.
