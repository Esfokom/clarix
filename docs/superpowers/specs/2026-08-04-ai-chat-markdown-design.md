# AI chat Markdown and math rendering

## Goal

Render assistant and user chat messages as Markdown, including inline and
display LaTex, while preserving existing citations.

## Design

Add `flutter_markdown_plus` and `flutter_math_fork`. Assistant bubbles use a
`MarkdownBody` configured with the workspace chat typography, code styling,
and custom inline/block math builders. Inline `$...$` and display `$$...$$`
expressions render through `Math.tex`; malformed expressions fall back to their
literal source instead of failing the chat view.

Both user and assistant bubbles use the same Markdown/math renderer, with
role-specific colors and typography. During streaming, each partial assistant
response is rendered from the current message text; no message-state or
citation behavior changes.

## Tests

Widget tests will verify headings/lists/code and inline/display math in both
message roles, plus malformed-math fallback. Existing chat and workspace tests
remain green.
