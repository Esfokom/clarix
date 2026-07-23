# Windows local-RAG build

Clarix packages a prebuilt Flutter Rust Bridge library with the Windows runner.
The optional build step produces `clarix_pdf_oxide.dll`; the Windows install
step then places it, plus any Rust-side runtime DLLs such as ONNX Runtime,
next to `clarix.exe`.

## Prerequisites

- Flutter Windows desktop tooling and Visual Studio C++ build tools.
- Rust stable with Cargo on `PATH`.
- Network access for the first Cargo/FastEmbed build; the embedding model is
  still downloaded on first local-RAG indexing, not at application startup.

## Build

```powershell
.\tool\build_local_rag.ps1
flutter build windows --release
```

For normal development use `flutter run -d windows` directly. It does not
compile Rust and launches with lexical retrieval immediately. Run
`.\tool\build_local_rag.ps1` only when you need semantic local retrieval; the
next Flutter build copies the cached DLL into the bundle. The first Rust build
can take many minutes because Cargo compiles the FastEmbed/ORT dependency
graph, but later builds are incremental. Verify the resulting bundle contains
`clarix.exe` and `clarix_pdf_oxide.dll` in the same directory.

The Flutter runtime opens the DLL adjacent to its executable on Windows. If
the bundled DLL is missing or cannot load, Clarix still launches and uses
lexical local retrieval; no PDF text is sent to a provider.

The same `clarix_pdf_oxide.dll` is also the native PDF extraction/search
runtime. Clarix initializes it once and shares it between PDF operations and
local RAG; it never loads a separate source-tree DLL for either feature.
