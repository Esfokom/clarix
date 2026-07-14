# Generated native bindings

Run `flutter_rust_bridge_codegen generate` from the repository root after installing the 2.12.0 code generator. Generated files are intentionally not handwritten.

The Rust indexing endpoint emits bounded batches as JSON strings over the FRB stream. Decode each string into a typed index event in the generated Dart adapter; this keeps the Rust crate independently testable before bindings exist.

Until generation and Windows DLL packaging are completed, `HybridPdfExtractionService` uses the shared `pdfrx` fallback while preserving the same batch-oriented interface.

The optional `ocr` Cargo feature also requires LLVM/libclang for `ocr-rs` bindgen. Set `LIBCLANG_PATH` to the directory containing `libclang.dll` before compiling that feature. PP-OCRv6/MNN model assets and their licenses must be installed and validated separately.