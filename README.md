# clarix

Clarix is a Windows-first Flutter PDF workspace with:

- a left-side document rail for recent files, tabs, and page navigation
- a central `pdfrx` reading surface
- a bottom AI composer powered by `flutter_gemma`
- persisted session restore and model/download state
- a Rust `pdf_oxide` scaffold for extraction/search FFI work

## Current architecture

- `lib/src/features/workspace/domain`: entities and aggregate UI state
- `lib/src/features/workspace/application`: Riverpod 3 notifiers and AI orchestration
- `lib/src/features/workspace/infrastructure`: persistence and chunk storage
- `lib/src/features/workspace/presentation`: desktop shell, viewer, and composer UI
- `rust/clarix_pdf_oxide`: native extraction/search scaffold

## Local AI and RAG

- Inference default: Gemma 4 `E2B IT`
- Embeddings default: `EmbeddingGemma 1024`
- Vector store: `flutter_gemma` native vector store path
- PDF indexing: page-aware chunking with persisted chunk cache

## Run it

```bash
flutter pub get
flutter run -d windows
```

## Notes

- `pdfrx` on Windows requires Developer Mode to be enabled.
- The Flutter app currently falls back to a Dart extraction path while the Rust `pdf_oxide` dynamic library wiring is still scaffolded rather than fully linked.
