# Native-text Local RAG Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement task-by-task.

**Goal:** Add CPU-local semantic retrieval for native-text PDFs, with existing OpenAI-compatible providers used only to create grounded final answers.

**Architecture:** PDF chunks stay the durable source of text and citations. Rust owns FastEmbed ONNX embedding, model cache, and USearch HNSW persistence/query; Flutter schedules indexing and uses a lexical fallback whenever the local model/index is unavailable.

**Tech Stack:** Rust, flutter_rust_bridge 2.12, fastembed 5.17, usearch 2.26, Flutter/Riverpod.

## Global Constraints

- Windows desktop and CPU only.
- Use FastEmbed AllMiniLML6V2. It downloads/caches the complete ONNX and tokenizer package; do not use GGUF.
- Native text only. OCR remains phase two and is not invoked.
- PDF text, vectors, and queries remain local.
- The remote provider receives only prompt plus at most six retrieved passages when sharing is enabled.
- Persist document fingerprint, model ID, vector dimensions, and chunk IDs. Any mismatch forces rebuild.
- Lexical retrieval must work while indexing or when model download fails.

---

## Task 1: Retrieval contract and lexical fallback

**Files:** Create lib/src/features/workspace/infrastructure/local_rag_store.dart; create local_rag_service.dart; create test/workspace_ai/local_rag_service_test.dart.

- [ ] Write failing tests proving ranked native results are used when ready and query-term lexical results are used when unavailable.
- [ ] Run flutter test test/workspace_ai/local_rag_service_test.dart and record RED.
- [ ] Implement LocalRagRetriever.retrieve(documentId, query, limit = 6), status values idle/indexing/ready/unavailable/failed, a versioned local manifest, and case-insensitive lexical term ranking with chunk-order tie breaks.
- [ ] Run the focused test and record GREEN.
- [ ] Commit with message: feat: add local RAG retrieval contract.

## Task 2: Rust CPU embedding and persistent ANN

**Files:** Modify rust/clarix_pdf_oxide/Cargo.toml, src/lib.rs; create src/rag.rs; add Rust module tests.

- [ ] Write failing deterministic-embedding tests proving semantic ranking and manifest dimension mismatch rejection.
- [ ] Run cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml rag and record RED.
- [ ] Add fastembed 5.17 and usearch 2.26 under a rag feature. Implement FastEmbed AllMiniLML6V2 model cache, batched embeddings, cosine HNSW index, manifest/index persistence per document fingerprint, and query search. Prefix corpus text with passage: and queries with query:. Tests must inject embeddings and never download production models.
- [ ] Run cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml rag and record GREEN.
- [ ] Commit with message: feat: add local CPU vector retrieval.

## Task 3: FFI and background indexing

**Files:** Modify Rust api.rs; regenerate lib/src/core/ffi; modify pdf_oxide_bridge.dart, workspace_providers.dart, workspace_notifier.dart; extend local RAG tests.

- [ ] Write failing tests proving a PDF persists chunks before scheduling RAG indexing, and model/index errors retain lexical retrieval.
- [ ] Run focused test and record RED.
- [ ] Add FFI APIs for index, search, and model status. Regenerate bindings. Schedule indexing only after successful DocumentChunkStore persistence; do not block opening a PDF. Report unavailable/failed state but keep lexical results.
- [ ] Run focused tests and record GREEN.
- [ ] Commit with message: feat: index native PDF text for local RAG.

## Task 4: Ground answers in ranked passages

**Files:** Modify ai_runtime_service.dart and ai_agent_runtime.dart; extend ai_agent_runtime_test.dart.

- [ ] Write failing tests proving semantic ordering replaces first-chunk selection and disabled sharing produces no passages.
- [ ] Run flutter test test/workspace_ai/ai_agent_runtime_test.dart and record RED.
- [ ] Pass retrieved chunks to the AI runtime. Supply no more than six page-labelled passages, each clipped to 1500 characters. Send no document context when sharing is disabled or no evidence exists.
- [ ] Run focused tests and record GREEN.
- [ ] Commit with message: feat: ground AI answers in local RAG results.

## Task 5: Documentation and verification

**Files:** Create docs/local-rag-models.md; update approved design only if implementation differs.

- [ ] Document the Hugging Face URL, ONNX package format, automatic FastEmbed cache, FASTEMBED_CACHE_DIR override, no-GGUF rule, offline behavior, rebuild rules, and phase-two OCR boundary.
- [ ] Run cargo fmt check, cargo clippy with warnings denied, cargo test, flutter analyze, and flutter test.
- [ ] Manually verify a Windows native-text PDF: first download/index, offline cached reopen, page-cited answer, and no passages when sharing is disabled.
- [ ] Commit with message: docs: explain local RAG model setup.

