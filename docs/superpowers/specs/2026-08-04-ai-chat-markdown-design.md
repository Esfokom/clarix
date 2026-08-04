# AI chat Markdown and math rendering

## Goal

Render assistant chat messages as Markdown, including inline and display LaTex,
while preserving plain-text user bubbles and existing citations.

## Design

Add `flutter_markdown_plus` and `flutter_math_fork`. Assistant bubbles use a
`MarkdownBody` configured with the workspace chat typography, code styling,
and custom inline/block math builders. Inline `$...$` and display `$$...$$`
expressions render through `Math.tex`; malformed expressions fall back to their
literal source instead of failing the chat view.

User bubbles remain plain `Text` so their input is never interpreted as
Markdown. During streaming, each partial assistant response is rendered from
the current message text; no message-state or citation behavior changes.

## Tests

Widget tests will verify assistant headings/lists/code and inline/display math
render, malformed math fallback, and that a user bubble keeps Markdown source
literal. Existing chat and workspace tests remain green.
