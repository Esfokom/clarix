# clarix_pdf_oxide

Rust extraction/search scaffold for Clarix.

Current status:
- Defines the `pdf_oxide`-backed DTOs and public functions Clarix expects.
- Intended to become the native FFI backend for text extraction, chunking, and search.
- The Flutter app currently falls back to a `pdfrx` extraction implementation until the dynamic library is wired into the desktop runner.
