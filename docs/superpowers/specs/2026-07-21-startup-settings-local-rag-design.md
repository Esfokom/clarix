# Startup, settings, and local RAG design

**Status:** Approved design, awaiting implementation-plan review  
**Date:** 2026-07-21  
**Scope:** Desktop Clarix

## Goals

1. Launch Clarix directly into the document workspace. Reader diagnostics must
   remain available for development but must not be the production start screen.
2. Move AI provider configuration out of the document workspace and into a
   persistent app-level Settings dialog.
3. Keep answer generation compatible with the existing OpenAI-compatible
   providers.
4. Define a local, CPU-first RAG pipeline for questions about the open PDF.
   Embedding, retrieval, OCR, and optional reranking must remain on-device.

## Non-goals

- Hosting a vector-database service.
- Sending complete PDFs to an AI provider.
- Local generative LLM inference in this phase.
- Running OCR for PDFs that already have usable selectable text.

## Application UX

### Launch

`ClarixApp` uses `WorkspaceScreen` as its home. The diagnostic hub is retained
as a development-only route/entry point, never selected at ordinary launch.

The workspace preserves its existing session restoration behavior. A first-run
user sees the normal empty/quick-start workspace, not a chooser screen.

### Settings

The workspace shell exposes a single Settings affordance. Selecting it opens a
modal settings dialog rather than altering the workspace layout. Its first
section is **AI providers**.

The provider section contains:

- A concise explanation that Clarix uses the selected provider only to answer
  questions.
- A list of configured OpenAI-compatible profiles, marking the default profile.
- An explicit **Add provider** action.
- A focused add/edit dialog with label, base URL, model ID, API key, retrieved
  passage sharing consent, Test connection, Save, Cancel, and Delete (edit
  only).
- Clear empty, saving, testing, invalid-form, and connection-failure states.

The add flow starts blank except for sensible OpenAI-compatible URL/model
placeholders. It never relies on a workspace/document being open.

### Persistence and privacy

Provider metadata remains in `SharedPreferencesAsync`; API keys remain in
`flutter_secure_storage`. The profile store becomes application configuration,
not workspace state. The selected/default provider ID is persisted separately.

Provider profiles are not serialized into the document session. Deleting a
profile also removes its stored secret. Testing a profile does not persist it.

## Local RAG architecture

### Boundaries

The Flutter workspace owns UI state and calls a Rust service through the
existing `pdf_oxide_bridge`. The Rust service owns document text preparation,
chunking, embedding, lexical/vector indexes, retrieval, OCR eligibility, and
index persistence. It returns passages with page and chunk provenance.

The existing OpenAI-compatible runtime only receives: the user's prompt and a
bounded set of retrieved passages when the active profile grants passage-sharing
consent. It does not access the on-disk index or raw document.

### Ingestion

On opening or changing a PDF:

1. Extract native text page-by-page using the current PDF path.
2. Mark pages with no meaningful native text as OCR candidates. Do not OCR
   pages that already contain text.
3. OCR candidates locally with Tesseract through a Rust abstraction, saving
   recognized text and page provenance.
4. Normalize and chunk text by headings/pages into roughly 350--500-token
   chunks with a small overlap. Preserve document fingerprint, page number,
   chunk ordering, heading, extraction origin, and model version.
5. Compute local embeddings in batches with `fastembed-rs`, initially
   `AllMiniLML6V2`.
6. Persist chunks/metadata, a lexical index, vectors, and a `usearch` HNSW
   index under the application-support directory. The index key includes the
   PDF fingerprint and embedding model/version.

Indexing runs off the UI thread, is cancellable when a document closes, and
reports progress. Before semantic indexing completes, lexical retrieval remains
available.

### Query path

1. Locally embed the question.
2. Retrieve top candidates from local lexical search and `usearch` ANN search.
3. Fuse the rankings with Reciprocal Rank Fusion.
4. Start with deterministic lexical/evidence-density reranking. Add the local
   `fastembed-rs` cross-encoder only after benchmark data show it improves
   answer-grounding enough to justify its latency; it evaluates at most the top
   20 fused candidates.
5. Return the best 4--6 short passages, each with title and page number.
6. Build an answer request with an explicit instruction to cite those passages
   and state when the evidence is insufficient.

### Recommended CPU-first components

| Concern | Choice | Reason |
| --- | --- | --- |
| Embeddings | `fastembed-rs`, `AllMiniLML6V2` | On-device CPU inference, simple model cache, and an available reranker API. |
| ANN | `usearch` | Embedded persistent HNSW with SIMD-accelerated distance computation. |
| Lexical | Rust-owned BM25/FTS implementation | Essential for identifiers, numbers, names, and exact PDF terms. |
| OCR | Tesseract behind a Rust OCR trait | Mature local CPU OCR and replaceable engine boundary. |
| Optional reranker | `fastembed-rs` cross-encoder | Local and isolated to a small candidate set. |

Alternatives rejected for this phase:

- **Candle/candle_embed:** preferred future pure-Rust option, but higher
  integration/model-loading effort than `fastembed-rs`.
- **Direct `ort`:** greater runtime and integration responsibility without an
  immediate advantage over the wrapper.
- **hnsw_rs:** viable pure-Rust ANN alternative, but `usearch` better matches
  persisted high-performance desktop ANN now.
- **Always-on reranking:** unnecessary latency before retrieval benchmarks.

## Data and versioning

Changing the PDF fingerprint, chunking algorithm, embedding model, model
revision, or vector dimension invalidates the affected index. Invalid indexes
are rebuilt in the background; queries may use lexical retrieval while that
happens. Cache quota and per-document deletion are explicit future settings.

## Error handling

- Missing model/download failure: report a recoverable local-indexing state;
  document reading remains available.
- OCR engine unavailable: retain native text, mark affected pages as not
  searchable, and offer a clear remediation action.
- Corrupt index: delete only the affected document index and rebuild it.
- Provider failure: retain the local retrieval results and show a provider
  error without losing the chat draft.

## Testing and acceptance criteria

### Startup/settings

- A widget test proves the default app route is `WorkspaceScreen`, not the
  diagnostic hub.
- Provider profiles and the default provider survive relaunch; API keys do not
  appear in preferences/session serializations.
- Add, edit, test, select default, and delete flows have focused widget tests.
- Existing workspace/session and provider-store tests stay green.

### RAG design spike

- Fixture PDFs cover native text, image-only pages, mixed pages, and tables.
- Every returned passage carries the correct document and page citation.
- Index version mismatch triggers a rebuild, never a stale-vector query.
- Benchmark a representative 100-page native PDF and an image-only PDF. Record
  cold/warm indexing time, CPU use, memory, query p50/p95, and grounded-answer
  retrieval recall before enabling cross-encoder reranking.
- No remote request occurs during extraction, OCR, chunking, embedding, or
  retrieval.

## Delivery order

1. Implement and verify direct workspace launch plus Settings/provider UX.
2. Add Rust RAG interfaces and a benchmarkable local ingestion/retrieval spike.
3. Add OCR fallback.
4. Evaluate optional cross-encoder reranking against the recorded benchmark
   corpus.

