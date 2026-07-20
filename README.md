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
