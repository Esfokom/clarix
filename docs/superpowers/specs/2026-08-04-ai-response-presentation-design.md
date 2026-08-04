# AI response presentation design

## Goal

Give Clarix AI a professional response surface with concise, composer-local progress feedback and full-width assistant content.

## Loading feedback

Remove provider names, remote-disclosure copy, and raw runtime status messages from the pane header. While a request is pending, show a compact indicator immediately above the composer: a pulsing dot and a shimmering single PDF-relevant word. Rotate every five seconds through `Reading`, `Tracing`, `Grounding`, `Pondering`, `Synthesizing`, and `Citing`. The composer send button remains a stop action while loading.

## Messages

User messages remain compact right-aligned bubbles. Assistant messages lose their bubble, border, and max-width constraint; Markdown content uses the full available pane width with 16 px horizontal padding on the pane background. Citation chips remain beneath the assistant content.

## Tests

Widget tests cover loader placement/visibility, rotating-word timer behavior, assistant full-width unboxed presentation, and preserved user bubbles/citations.
