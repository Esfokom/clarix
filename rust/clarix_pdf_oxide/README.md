# Clarix PDF native core

This crate is the Windows-first native PDF and OCR core for Clarix.

## Implemented

- A long-lived `PdfDocumentSession` that opens `pdf_oxide` once per document.
- Page text extraction with an LRU-style cache bounded to 32 pages and 8 MiB.
- Bounding-box text search through `pdf_oxide`.
- Incremental indexing in batches (the Flutter caller uses 32 records per batch).
- UTF-8-safe text chunking.
- `flutter_rust_bridge` 2.12 API entry points in `src/api.rs`.
- Optional `ocr-rs` 2.3.2 support in `src/ocr.rs`, using PP-OCRv6/MNN models.

## Generate Flutter bindings

From the Flutter project root:

```text
flutter_rust_bridge_codegen generate
```

The configuration is in `flutter_rust_bridge.yaml`; generated Dart files belong under `lib/src/core/ffi/`.

## Build and test

```text
cargo fmt --check --manifest-path rust/clarix_pdf_oxide/Cargo.toml
cargo clippy --manifest-path rust/clarix_pdf_oxide/Cargo.toml -- -D warnings
cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml
cargo build --release --manifest-path rust/clarix_pdf_oxide/Cargo.toml --target x86_64-pc-windows-msvc
```

Enable OCR only when the three local PP-OCRv6 model assets are installed:

```text
cargo build --release --features ocr --manifest-path rust/clarix_pdf_oxide/Cargo.toml
```

Document bytes and OCR inputs remain local. Model acquisition is a separate, user-initiated network operation.

## Phase 0 editing foundation

The Windows editing foundation is split into four crates: the canonical model and
session actor in `clarix_editing_core`, typed agent tools in `clarix_agent_core`,
the read-only PDF qualification adapter in `clarix_pdf_adapter`, and this crate as
the only Flutter FFI/DLL facade. Canonical IDs and snapshots never contain native
PDF handles.

From the repository root, run the reproducible checks with:

```text
pwsh -File tool/editing_foundation/run_phase0_checks.ps1
pwsh -File tool/editing_foundation/record_baseline.ps1 -OutputPath docs/testing/editing-phase0-baseline.json
```

Binding regeneration is opt-in with `-IncludeBindingGeneration`. The Windows
release build is deliberately opt-in with `-IncludeNativeBuild`; its explicit
manual command remains the `cargo build --release` command above.
