# Native document RAG design

## Goal

Make the AI side pane answer questions about the active PDF using local,
persisted semantic retrieval. The active document title remains visible in the
pane. Answers must clearly separate supported document statements from any
supplementary general knowledge.

## Scope

Clarix will extend the existing Flutter/Rust RAG integration. It will not add
MarkItDown or upload document content to a remote retrieval service.

## Architecture

The document SHA-256 fingerprint is the cache identity. A native RAG manifest
is valid only when all of the following match the currently-open document:

- document fingerprint;
- embedding model identifier and vector dimensions;
- ordered chunk IDs; and
- index/manifest format version.

When a PDF is opened, Clarix will first persist or reuse its extracted chunks.
It will then ask the native RAG layer whether a valid persisted index exists.
If it does, it will mark semantic retrieval ready without rebuilding vectors.
If it does not, it will schedule indexing in the background. Rust owns model
loading, embedding generation, HNSW index persistence, and index validation.

The PDF remains usable while indexing. Repeated open requests for the same
fingerprint coalesce so only one index build runs at a time.

## Retrieval and answer generation

For each chat question scoped to the current document:

1. Retrieve a small semantic top-k set from the ready native index.
2. Fall back to the persisted lexical chunk search while native indexing is
   pending or unavailable.
3. Deduplicate overlapping results and retain page number, document title, and
   source snippet for citations.
4. Provide the retrieved passages to the configured chat provider before it
   answers. Tool-based follow-up search uses the same retrieval policy.

The system instruction requires this output behavior:

- `From the document`: claims grounded in supplied passages, with page
  citations. If the evidence is insufficient, say so.
- `General knowledge (not from this document)`: optional, explicitly labeled
  supplemental information. It must not be presented as document content.

If no relevant passages are available, the assistant can still respond from
general knowledge, but must make the missing document support clear.

## User experience

The AI pane header/scope row shows the title of the active PDF. Its status
communicates document-context progress independently of model generation:

- `Preparing document context` while chunks or embeddings are being built;
- `Ready to search this document` once a valid native index is available;
- a concise fallback notice when lexical retrieval is being used; and
- an unavailable state for PDFs with no extractable text.

The current document scope continues to limit retrieval to the active PDF.

## Errors and privacy

Document content, embeddings, and index files stay in application-support
storage. Native-index failures do not prevent PDF reading or chat: Clarix uses
the persisted lexical index when possible. Cache corruption, changed source
content, changed embedding model, or incompatible index data trigger a safe
rebuild. Logs do not contain document content.

## Tests

Tests will cover:

- cache hit skips native re-indexing after a restart;
- stale manifests rebuild on fingerprint/model/chunk mismatch;
- concurrent opens coalesce indexing work;
- semantic retrieval is preferred when ready, lexical retrieval is used while
  pending or unavailable;
- chat instructions/context enforce the document vs. general-knowledge
  separation; and
- the AI pane displays the active document title and meaningful context state.
