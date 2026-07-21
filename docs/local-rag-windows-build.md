# Windows local-RAG build

Clarix packages its Flutter Rust Bridge library as part of the Windows runner.
The `clarix_rust_ffi` CMake target runs Cargo in release mode and the Windows
install step places `clarix_pdf_oxide.dll`, plus any Rust-side runtime DLLs
such as ONNX Runtime, next to `clarix.exe`.

## Prerequisites

- Flutter Windows desktop tooling and Visual Studio C++ build tools.
- Rust stable with Cargo on `PATH`.
- Network access for the first Cargo/FastEmbed build; the embedding model is
  still downloaded on first local-RAG indexing, not at application startup.

## Build

```powershell
flutter build windows --release
```

For development use `flutter run -d windows` or `flutter build windows
--debug`. The first build can take several minutes because Cargo compiles the
FastEmbed/ORT dependency graph. Verify the resulting bundle contains
`clarix.exe` and `clarix_pdf_oxide.dll` in the same directory.

The Flutter runtime opens the DLL adjacent to its executable on Windows. If
the bundled DLL is missing or cannot load, Clarix still launches and uses
lexical local retrieval; no PDF text is sent to a provider.
