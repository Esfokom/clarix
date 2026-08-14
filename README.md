# clarix

Clarix is a Windows-first Flutter PDF workspace with:

- a left-side document rail for recent files, tabs, and page navigation
- a central `pdfrx` reading surface
- a remote AI composer using user-configured OpenAI-compatible providers
- persisted session restore and provider selection
- a Rust `pdf_oxide` scaffold for extraction/search FFI work

## Current architecture

- `lib/src/features/workspace/domain`: entities and aggregate UI state
- `lib/src/features/workspace/application`: Riverpod 3 notifiers and AI orchestration
- `lib/src/features/workspace/infrastructure`: persistence and chunk storage
- `lib/src/features/workspace/presentation`: desktop shell, viewer, and composer UI
- `rust/clarix_pdf_oxide`: native extraction/search scaffold

## Remote AI and document context

- Configurable OpenAI-compatible endpoints and models
- API keys are stored through platform-secure storage, never in workspace preferences
- Clarix sends only bounded retrieved PDF passages when passage sharing is enabled; it never sends a full PDF by default
- PDF indexing remains page-aware with a persisted chunk cache
- This release does not include local inference

## Run it

```bash
flutter pub get
flutter run -d windows
```

## Notes

- `pdfrx` on Windows requires Developer Mode to be enabled.
- The Flutter app currently falls back to a Dart extraction path while the Rust `pdf_oxide` dynamic library wiring is still scaffolded rather than fully linked.

## Native PDF object editing scope

Clarix edits genuine, existing PDF text objects. Saved text remains selectable,
searchable, and extractable; pages are never rasterized to simulate an edit.
The first release does not perform OCR, so image-only text and unsupported PDF
objects (including Type 3 glyphs, vector outlines, and unsafe shared form
objects) remain visibly read-only.

In object-edit mode, Clarix discovers genuine top-level PDF text, image, and
vector-path objects. These objects can be moved, resized, and rotated with
affine transforms while retaining their native object type. Objects nested in
shared form XObjects are inspectable but locked because changing them could
alter every form instance. OCR is intentionally deferred; image-only text is
not presented as editable text.

Text can be replaced, formatted, moved, resized, undone, and redone through the
same command history used by manual UI actions and agent tools. Font matching
uses the closest compatible installed face and discloses substitutions. A font
whose license prohibits embedding is rejected. Text overflow must be resolved
before Save is enabled.

When text is selected, Clarix temporarily suppresses its native PDFium glyphs
in the in-memory preview before showing the aligned editable glyph layer. This
prevents doubled text without drawing a cover shape or changing the source
file. Leaving edit mode restores the exact native render modes.

Saving writes and validates a working copy before replacing the destination.
If validation, external-change detection, font embedding, or replacement fails,
the original PDF and the in-memory edit draft are preserved. Clarix then offers
the relevant recovery action, such as reload, select the overflowing block, or
save a copy. Agent edits and saves obey the configured `Allow`, `Ask when
risky`, or `Always ask` permission policy; a granted workspace scope is reused
until it is revoked.
