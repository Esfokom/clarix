# OpenAI-Compatible Agent Runtime Design

## Status and scope

This design replaces the current `flutter_gemma`-backed workspace AI runtime.
The first delivery targets the existing fourth diagnostic-section workspace and
supports user-configured OpenAI-compatible remote providers. Flutter Gemma,
LiteRT-LM, EmbeddingGemma, and the Flutter Gemma Qdrant integration are removed
from the active AI architecture. A local inference provider may be introduced
later through the same provider interface, but is explicitly out of scope.

The diagnostics hub remains the application entry point. This work changes the
workspace reached through that hub; it does not change its launch layout.

## Goals

- Chat with any OpenAI-compatible `/v1/chat/completions` endpoint.
- Let users configure a provider profile: name, base URL, model, API key, and
  optional request headers.
- Store secrets in platform secure storage and non-secret profile metadata in
  the existing local preference store.
- Send retrieved PDF passages to remote providers when enabled in the selected
  profile. Do not send an entire document by default.
- Provide streaming answers, citations, persisted conversations, execution
  records, typed tools, bounded tool-call loops, cancellation, and useful
  failure recovery.
- Establish the agent/tool boundary required by the future PDF editing agent.

## Non-goals

- Local inference, local embeddings, model downloads, or model catalog support.
- Python packaging, LangChain, LangGraph, Google ADK, or a Rust LLM runtime.
- PDF mutation tools, undo checkpoints, and editing-agent automation. Those
  remain Phase 3/4 work.
- Changing the reader diagnostics navigation or implementing a new editor.

## Architecture

`AiSidePane` delegates a user request to `AiAgentRuntime`. The runtime owns the
run state and coordinates four replaceable components:

1. `OpenAiCompatibleProvider` sends chat-completions requests, parses Server-
   Sent Events, emits text deltas, and normalizes final messages/tool calls.
2. `RetrievalContextBuilder` reads the existing locally extracted PDF chunks,
   applies the active-PDF scope, and produces a bounded citation-bearing context
   packet. Retrieval is local; its selected passages are the only PDF text sent
   remotely.
3. `ToolRegistry` exposes typed, validated tools. Phase 2 contains only
   read-only document/context tools. It returns structured tool results.
4. `RunStore` persists conversations and runs locally. It stores provider and
   model identifiers, messages, citations, tool events, timings, status, and
   recoverable errors. It never stores API keys in the run data or logs.

The agent loop uses a maximum of six model/tool rounds. It validates every tool
call against its declared JSON-compatible schema and an allow-list before
execution. Any future mutating tool must be classified as `requiresApproval`;
the runtime pauses before it and creates an audit entry. Automatic retries apply
only to idempotent provider requests with transient network failures.

## Provider profiles and privacy

Provider profiles contain a stable ID, user-visible label, normalized base URL,
model ID, passage-sharing consent, and optional non-secret headers. The API key
is stored separately under the profile ID using platform secure storage.

The UI labels a selected remote profile as remote and shows whether retrieved
passages may be shared. The user can disable passage sharing; in that case the
model receives the conversation and request but no retrieved PDF text. The
system instruction makes this limitation clear so the model does not claim to
have read a document it did not receive.

## Request and execution flow

1. The user chooses a provider and sends a message from the workspace AI pane.
2. The runtime creates a run record and gathers local PDF context under the
   selected scope.
3. It sends the system prompt, bounded conversation history, user message,
   declared tools, and—only when consented—the bounded retrieval packet.
4. Response deltas stream to the existing chat message.
5. If the response requests tools, the runtime validates and executes each
   allowed call, records an event, appends tool results, and repeats step 3.
6. The runtime records the final response and citations, or a structured
   cancelled/failed/step-limit result.

## UI

The workspace AI pane gains a provider picker, a remote-data indicator, and
controls to open provider settings. Provider settings allow profile creation,
editing, connection testing, API-key replacement/removal, and deletion. The
chat can expose expandable execution details for provider/model, retrieval
sources, tool calls, elapsed time, and errors without overwhelming the normal
message flow.

Removing local models also removes or hides the workspace model catalog and all
model-install/download status messaging. Existing local AI state is migrated
defensively: stale active model IDs and download tasks are ignored/cleared
without affecting PDF sessions, annotations, or chat history.

## Errors and cancellation

- Invalid URLs, missing keys, malformed SSE frames, unsupported tool schemas,
  unauthorized responses, rate limits, and network failures produce concise,
  actionable chat errors.
- Cancellation closes the active HTTP stream and marks the run cancelled while
  retaining partial text and execution events.
- Tool exceptions are converted into tool-result errors for the model where it
  is safe to continue; validation and policy failures terminate the run.
- Provider errors do not affect PDF reader availability.

## Testing and acceptance

Tests are written before production changes. They cover profile serialization,
secure-key indirection, OpenAI request construction, SSE parsing, tool-call
normalization, schema and policy validation, loop limits, retrieval sharing
rules, cancellation, run persistence, migration away from local-model state,
and the workspace provider/settings/chat states. HTTP behavior is exercised via
a fake transport, not live provider credentials.

Acceptance requires a user to configure a compatible endpoint, test it, chat
with streaming output, receive PDF-grounded citations when sharing is enabled,
run a read-only tool call, cancel a stream, relaunch with configuration and
history preserved, and verify no API key or full PDF is written to logs or run
data.
