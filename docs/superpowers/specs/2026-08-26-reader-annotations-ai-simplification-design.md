# Reader, Annotations, and AI Simplification Design

## Goal

Reduce Clarix to a predictable desktop PDF application for reading, ordinary
annotations, local PDF utilities, and document-aware AI chat. Remove all PDF
text/object editing and the agent harness.

## Product scope

### Retained

- Open and read PDFs with the existing reader stack.
- Create highlights, notes/comments, ink annotations, and bookmarks.
- Use the existing PDF utility workflows independently of the reader.
- Chat normally with an OpenAI-compatible provider about the open document.
- Retrieve relevant document context through Rust chunking, embeddings, and
  local index/search.

### Explicitly removed

- Changing source PDF text, fonts, object bounds, or other page objects.
- Native text editing controls, clean-patch rendering, PDF materialization,
  save-back/recovery, and editing undo/redo.
- Agent runs, plans, tool registries, mutation proposals, permission gates,
  and all agent-driven document operations.

## Architecture

The Flutter application owns presentation and local interaction state. The
Rust library is a narrow native service for work that benefits from native
execution: document text extraction for RAG, chunking, embeddings/indexing,
retrieval, OpenAI-compatible SSE transport, and atomic sidecar persistence.

The generated Flutter Rust Bridge surface exposes only document/RAG, chat, and
sidecar types. It does not expose editor session, PDF mutation, or agent tool
types.

```text
Flutter reader ───────────> PDF rendering/navigation
       │
       ├─ Dart annotation state ── Save ──> Rust atomic sidecar write
       │                                     <pdf>.clarix
       │
       └─ Chat prompt ───────────> Rust retrieval + OpenAI SSE
                                                │
Flutter chat <──────── streamed text/citations ┘
```

## Feature boundaries

### Reader

The reader remains a view-only PDF renderer. It may expose selection for
annotation anchors and page references, but never mounts editable text/object
overlays or starts a native edit session.

### Annotations

Annotations are Dart domain data while the document is open. Each record has a
stable ID, page number, annotation kind, geometry or text range anchor,
created/updated timestamps, and the kind-specific payload (highlight color,
note text, ink strokes, or bookmark metadata).

Opening a document derives its sidecar path and loads that sidecar if present.
Creating, changing, or deleting an annotation only updates memory and marks
the document annotation state dirty. No disk write occurs until the user
selects Save. Rust writes the complete sidecar atomically at Save time; a
failed save preserves the previous sidecar and reports an error to Flutter.
The source PDF is never rewritten by annotations.

### AI chat

Chat remains ordinary document-aware conversation. Flutter sends the user
message and active document identity to Rust. Rust obtains relevant chunks from
the retained embedding/index model, invokes the configured OpenAI-compatible
chat-completions stream, and forwards text deltas plus page citations over FRB.
Flutter renders the conversation, markdown/math, loading/error state, and page
reference navigation.

There are no tool calls, agent loops, proposals, permissions, or document
mutation actions in the chat contract. If document context is not ready, the
chat composer waits or states that indexing is in progress; it must not
substitute an editing or agent workflow.

### Utilities

Existing combine, extract, convert, compress, and related utility flows remain
available as standalone workflows. They do not require an open reader document,
annotation state, RAG index, editor session, or agent runtime.

## Native structure

Replace the current combined native workspace with a single focused crate
(`clarix_native_core`; final folder/crate rename is part of implementation).
It contains:

- FRB API definitions and generated bindings;
- RAG extraction, chunking, embedding/index persistence, and retrieval;
- OpenAI-compatible streaming transport via `reqwest`;
- sidecar validation, serialization, atomic write, and read.

Delete the editing core/store/adapter crates and the agent core crate. Remove
the editing/agent portions of the current `clarix_pdf_oxide` crate rather than
carrying compatibility shims. Any Rust dependency used only by editing or agent
features is removed from the workspace.

## Error handling

- Missing sidecar is a normal empty-annotation state.
- Invalid or unreadable sidecar is non-destructive: report a clear error and
  leave the source PDF readable.
- Sidecar saves write a temporary sibling then atomically replace the target.
- RAG failures keep the reader usable and produce a chat-specific error.
- SSE/provider failures preserve the existing conversation and end the pending
  response with an actionable error.

## Migration and tests

1. Remove Dart editing and agent-harness references, then verify reader and
   utilities compile without the old bridge.
2. Establish the narrow native API and regenerate FRB bindings.
3. Retain/migrate RAG tests and add SSE boundary tests using a local mock
   response stream.
4. Add annotation tests for dirty in-memory changes, no write before Save,
   atomic save/reload, and malformed-sidecar handling.
5. Add reader and chat tests proving no edit controls or agent APIs remain,
   while document-aware streamed chat and citations continue to work.
6. Verify `flutter analyze`, focused Flutter tests, and `cargo test` for the
   remaining native crate.

## Non-goals

- Importing existing PDF annotation objects into the sidecar model.
- Writing annotations into source PDFs.
- Reintroducing text/object editing, an agent harness, or chat tools.
- Replacing the existing reader or PDF utility UX beyond removing editing and
  agent-specific controls.
