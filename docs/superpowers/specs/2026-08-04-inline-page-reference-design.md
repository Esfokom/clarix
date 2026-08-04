# Inline Page Reference Design

## Goal

Make document page references part of the assistant's rendered prose instead of showing detached citation chips below an answer.

## Matching and rendering

For assistant messages only, the renderer recognizes natural-language references in Markdown text: `page N`, `pages N and M`, and `pages N–M` / `pages N-M`. A matched range is represented by one inline interactive reference and uses its starting page as the target.

The rest of the model response remains unchanged. User-authored Markdown never gains page links. No standalone page chips are rendered below an answer.

## Interaction

An inline page reference is visually distinct from body text. Hovering it uses the existing local PDF page preview. Clicking it activates the already-open document and navigates to the referenced starting page using the current animated viewer behavior.

The active document is the navigation target. If it is unavailable or the page cannot be resolved, the reference stays non-disruptive and shows no preview.

## Data flow

The assistant-message widget derives lightweight page-reference spans from its text, then supplies each matched span to the existing citation preview/navigation component through a `CitationSnippet` for the active document. Retrieval citations continue to support grounding internally, but they are not appended as visual chips.

## Tests

Widget tests verify that assistant prose containing an individual page and a page range produces inline interactive references, that the range targets the first page, and that an answer without a page mention produces no citation UI. Existing Markdown, math, user-bubble, and loader coverage remains in place.
