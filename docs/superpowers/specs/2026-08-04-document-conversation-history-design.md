# Document Conversation History Design

## Goal

Give every PDF its own durable, local AI conversation history. Users can reopen and continue a thread, start a new one, or delete one from the AI pane. Conversations must stay independent from document cache, use the selected provider's configurable context limit, and automatically compact only the model-facing history while retaining the complete visible transcript.

## Scope

- Persist document-scoped threads and messages locally in SQLite.
- Continue a thread across restarts and display previous messages in full.
- Create and delete threads from the AI pane.
- Configure each provider's context-window limit, defaulting to 256,000 tokens.
- Estimate context usage and compact older turns automatically before requests approach the configured limit.
- Make document evidence the default answer form; permit external information only as an italic, bracketed disclaimer.
- Let Settings clear document cache separately from all conversations.

This feature does not add cross-document conversations, cloud sync, full-text search over chat history, or a tokenizer downloaded per model.

## Storage

`ConversationStore` owns a SQLite database located in Clarix's application-support directory. It is separate from `SharedPreferences`, provider secrets, and the local document/RAG cache.

### Tables

`conversations`

- `id` (primary key)
- `document_id` (required; a thread belongs to exactly one document)
- `title` (derived from the first user prompt and editable only in a future feature)
- `created_at` and `updated_at` UTC timestamps
- `summary` (nullable compaction summary)
- `summary_through_sequence` (highest message sequence represented by `summary`; nullable)

`conversation_messages`

- `id` (primary key)
- `conversation_id` (foreign key with cascade delete)
- `sequence` (stable chronological ordering within its conversation)
- `role` (`user` or `assistant`)
- `content` (Markdown)
- `citations_json` (stored per assistant response)
- `created_at` UTC timestamp
- `token_estimate` (non-negative integer)
- `is_compacted` (whether this message is represented in the saved summary)

Indexes cover `conversations(document_id, updated_at)` and `conversation_messages(conversation_id, sequence)`.

Writes that add or update a user/assistant exchange, create a summary, or delete a conversation use SQLite transactions. The existing current-message state remains an in-memory projection of the active thread; SQLite is the source of truth after startup.

## Thread behavior

When an active document opens its AI pane, Clarix restores that document's most recently updated thread. If none exists, the pane presents its empty state and creates a thread when the user sends the first prompt.

The AI-pane header contains:

- A compact thread-history selector, restricted to the active document.
- A new-conversation action that clears only the active display and begins a thread on the next prompt.
- A context-use indicator for the active conversation.

Selecting a historical thread restores all its messages, including messages compacted from the model-facing context. The history selector exposes a delete action per thread, protected by confirmation. Deleting a thread removes its message records and summary, never another document's conversation.

## Provider configuration and context accounting

`AiProviderProfile` gains `contextWindowTokens`, validated as a positive value and defaulting to `256000`. The provider editor exposes this as an advanced numeric setting. Existing saved profiles deserialize to the default.

Clarix uses a deterministic local estimate rather than claiming exact tokenizer counts. It estimates tokens from UTF-8/text length for:

- the system instruction;
- the active summary;
- recent un-compacted turns;
- retrieved document passages and tool results; and
- the new user prompt.

It reserves a fixed completion budget before calculating the percentage. The displayed percentage is the estimated request-context share of the provider's configured limit. It is explicitly an estimate in accessible tooltip text.

## Automatic compaction

Before dispatching a question, the runtime calculates the proposed context. If it would exceed the working threshold, it compacts the oldest eligible complete turns into a new summary. The summary replaces the prior summary for model context, and the represented messages are marked compacted in SQLite. Their original content remains available in the rendered history.

The compaction request is made with the selected provider and is instructed to preserve:

- user intent, decisions, questions, and unresolved items;
- document-supported conclusions and page citations;
- important quantities, dates, names, and definitions; and
- constraints that must guide later answers.

The normal request includes the system instruction, saved summary (if any), all recent un-compacted messages, fresh retrieved passages, and the new prompt. It does not include the full compacted transcript. If compaction cannot make a request fit, or the provider call fails, Clarix does not send the original prompt and reports an actionable error. Existing messages and summaries are never discarded on failure.

## Grounding and response presentation

The model is instructed to answer directly from supplied document evidence and place inline page references beside supported claims. It must not add `From the document` or `General knowledge` headings.

When document evidence is sufficient, no source-label boilerplate appears. If genuinely necessary information lies outside the document, the assistant may include it only as a concise italic disclaimer in brackets:

`*(General context, not stated in the document: …)*`

Unsupported document claims must instead state that the document does not establish the point. Existing citation storage and inline page navigation continue to work for persisted assistant messages.

## Settings and deletion boundaries

Settings adds a Storage section with separate, confirmed actions:

- **Clear document cache** removes re-creatable document metadata, extraction artifacts, chunks, and local retrieval indexes. It does not touch conversations.
- **Clear all conversations** removes every conversation, message, and summary in SQLite. It does not touch document cache or provider configuration.

Both actions report completion or a recoverable error. Neither affects provider API keys.

## Errors and lifecycle

The AI pane disables thread-changing and destructive actions during generation. It shows a short preparation state while context is compacted. Database initialization or write errors retain the currently rendered conversation, report the error, and prevent unsafe persistence claims. New installs start with an empty database; no migration from the current transient `AiWorkspaceState.messages` is required because it is not durable conversation history.

## Verification

Tests cover:

- SQLite create, read, transaction, per-document isolation, and cascade deletion;
- thread creation, reopening, continuation, and deletion in the notifier and pane;
- configured context limits and default migration behavior;
- context estimation, compaction selection, summary persistence, and preservation of visible originals;
- prompt construction including summary plus recent turns, fresh document retrieval, and no retired headings;
- Settings independently clearing cache and conversations; and
- persisted citations continuing to navigate to a document page.
