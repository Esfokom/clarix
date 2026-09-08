# Gemini Live document conversation

## Problem

Clarix currently offers document-aware text chat and a separate
record-then-transcribe input path. Neither supports a natural, continuous
audio conversation, immediate interruption of an AI answer, Gemini Live tool
calls, or web-grounded answers. The requested feature must remain compatible
with the PDFRx reader and run on the `experimental` branch.

## Goals

- Add a hands-free audio-to-audio conversation to the right-side AI pane,
  powered by `gemini-3.1-flash-live-preview`.
- Use Gemini automatic voice activity detection (VAD): wait for the user to
  finish speaking before answering, and immediately interrupt AI playback
  when new user speech begins.
- Ground document questions through a client-owned
  `query_active_document` function that searches only the active tab's
  existing local RAG index.
- Allow Gemini Live Google Search for time-sensitive web questions.
- Show Gemini-provided input and output transcripts without local
  transcription work, and persist finalized exchanges in the existing
  active-document conversation history.
- Present a visually distinctive listening/speaking state that reacts to
  microphone amplitude without changing PDFRx or the document reader.

## Non-goals

- Searching across multiple open documents.
- Replacing normal typed AI chat or the existing Groq transcription feature.
- Remote document indexing or uploading the entire PDF to Gemini.
- A production secret-brokering service. The initial configuration receives
  the key through `--dart-define=GEMINI_API_KEY=...`, as requested.
- Changing the PDF rendering engine or reintroducing Syncfusion.

## Architecture

### Live session boundary

Create a dedicated Live stack, independent of `AiRuntimeService` and the
one-shot `VoiceInputController`:

- `GeminiLiveGateway` owns a direct authenticated WebSocket connection to the
  Gemini Live API. It configures model
  `gemini-3.1-flash-live-preview`, `AUDIO` output, automatic VAD with
  start-of-speech interruption, input/output audio transcription, Google
  Search, and the local RAG function declaration.
- `LiveConversationController` owns the session lifecycle and is the only
  layer that combines microphone capture, PCM conversion, playback, VAD
  events, Live events, transcript assembly, and the RAG tool dispatcher.
- `LiveConversationState` is a typed, immutable presentation state: idle,
  connecting, listening, user-turn-ending, retrieving-document-context,
  web-searching, speaking, interrupted, error, and ended. It also contains
  normalized input/output amplitude, partial transcripts, completed turns,
  citations, and a recoverable error description.
- A Riverpod provider constructs the controller from the live gateway, an
  audio capture/playback adapter, `LocalRagService`, and the conversation
  store. It is disposed when the app disposes and is explicitly stopped when
  the pane closes, collapses, or its active tab changes.

The direct WebSocket implementation is deliberately selected over a local
proxy to minimize latency and distribution complexity. The initial key is
read only from `String.fromEnvironment('GEMINI_API_KEY')`; it is never stored
in preferences, conversation files, or logs.

### Audio and turn management

Capture the microphone continuously in raw PCM chunks suitable for Gemini's
native 16-bit little-endian 16 kHz audio input. Gemini returns 24 kHz PCM
audio chunks; the playback adapter queues and plays them in order.

Gemini automatic VAD determines turn boundaries. Clarix reflects the Live
activity events in the UI but does not run a second speech-to-text or VAD
engine. On activity start while Gemini output is queued or playing, the
controller immediately clears the queue and stops playback. It retains the
partially spoken AI transcript as interrupted, sends ongoing user audio, and
waits for Gemini's end-of-turn event before receiving the next answer.

The session config requests `inputAudioTranscription` and
`outputAudioTranscription`. Clarix renders the server events as captions and
does not invoke Groq or any local model to create them.

### Tools and document context

The Live setup declares `query_active_document` with a required non-empty
`query` string and an optional bounded result limit. Its instruction is to use
the function before making claims about the active PDF, and to mention source
pages where useful.

When Gemini requests the function, the controller calls
`LocalRagService.retrieve(activeDocument.documentId, query, limit: 6)`. It
returns a compact typed payload of title, page number, section title, and
excerpt for each chunk. This result is sent as a synchronous Live tool
response, after which Gemini resumes the same turn. If the local index is not
ready, returns no results, or fails, the tool response says so explicitly and
the model must explain that it could not ground the requested document claim.

The session config also enables Gemini's Google Search tool. Search is chosen
by Gemini for current external information; the pane labels final web sources
separately from local PDF citations. A RAG function call and Google Search can
both be available in the same conversation.

Changing the active document while a session exists ends the session before
the controller adopts the new context. No tool response may be fulfilled
against a stale tab.

### Persistence

Only completed user/assistant exchanges are added to the current
per-document `ConversationStore` thread. The saved assistant message includes
the finalized output transcript, local page citations, and web sources.
Partial captions and cancelled speech stay in session memory and are discarded
when a session ends. The regular typed composer and its history remain
unchanged.

## Pane experience

The existing AI pane receives a clear entry action, `Start voice
conversation`. While live, it swaps the text composer for the voice surface:

- Header: connected/listening/speaking status and an accessible `End voice
  conversation` control.
- Center: one deep-indigo orb with a narrow cyan/lilac shaded edge. Its size
  and glow follow normalized microphone amplitude during listening. During
  AI speech it changes to slower concentric response waves. It is static at
  idle and uses a status badge when reduced motion is enabled.
- Lower pane: incoming user and model transcripts grow in place. Completed
  assistant turns show compact local page citation chips and web-source links.
- Exit: ending the session restores the existing text composer and leaves the
  saved turn in normal conversation history.

The interface uses the app's existing workspace surface tokens. The orb is
the only expressive visual element; the rest of the pane remains restrained
and reader-focused.

## Error handling

Missing `GEMINI_API_KEY`, denied microphone permission, unavailable audio
devices, WebSocket authentication/connection errors, malformed Live events,
tool failures, and audio playback errors transition the controller to an
error state. The pane says what failed and gives a specific retry or setup
action. Every terminal path stops capture, clears playback, and closes the
socket. Ending/collapsing the pane, switching active documents, and provider
disposal use the same idempotent cleanup path.

## Dependencies and platforms

Add `audio_io` for one real-time PCM capture/playback adapter. It supports
Windows, Android, and iOS, supplies the amplitude stream that drives the orb,
and avoids competing capture/playback audio engines. Use Dart's built-in
`WebSocket` for the Live protocol. Android must request microphone and network
permissions; iOS must include the microphone usage string. Existing desktop
input-device selection should be reused where `audio_io` exposes it.

## Testing

- Unit tests for Live message encoding/decoding, session state transitions,
  server transcript assembly, automatic barge-in playback cancellation, RAG
  function result formatting, stale-document rejection, persistence, and
  cleanup.
- Widget tests for entry, connecting, listening, retrieving, speaking,
  interrupted, error/retry, reduced-motion, transcript, and citation states.
- Manual Windows verification with a valid `GEMINI_API_KEY`: microphone
  permission, normal hands-free turns, interrupting an AI reply, grounded
  active-PDF questions with correct page references, web search, transcript
  display without Groq, history persistence, tab-switch cleanup, and retry
  after a disconnected network.

## Acceptance criteria

1. A user can open the active PDF's AI pane, start one continuous Gemini Live
   audio session, speak naturally, hear audio replies, and see server-provided
   captions.
2. The user can start speaking over an AI answer; playback stops immediately
   and Gemini receives the new turn.
3. Gemini can invoke `query_active_document`; its response comes from the
   active tab's local RAG index and produces page-aware citations in the pane
   and saved history.
4. Gemini can use Google Search for external current information and Clarix
   identifies those sources.
5. No Gemini key is persisted or logged, and every session terminal path
   releases microphone, playback, and socket resources.
