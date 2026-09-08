# Gemini Live document conversation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hands-free Gemini Live audio conversation to Clarix’s active-document AI pane, with automatic barge-in, local-RAG tool calls, Google Search, server captions, citations, and saved history.

**Architecture:** Keep the Live protocol, continuous PCM audio, and conversation lifecycle outside the existing typed-chat runtime. A `GeminiLiveGateway` translates WebSocket JSON to typed events; `LiveConversationController` composes it with one real-time audio adapter, active-document RAG, and `ConversationStore`; the pane renders immutable live state and owns no protocol or audio logic.

**Tech Stack:** Flutter/Dart 3.12, Riverpod, existing `record`, `flutter_soloud`, `permission_handler`, `dart:io` WebSocket, Gemini Live API (`gemini-3.1-flash-live-preview`), PDFRx (unchanged), existing local RAG and SQLite conversation store.

**Spec:** `docs/superpowers/specs/2026-09-08-gemini-live-document-conversation-design.md`

## Global Constraints

- Work only on the `experimental` branch; retain PDFRx and do not add Syncfusion.
- Read the API key only through `String.fromEnvironment('GEMINI_API_KEY')`; never write it to preferences, SQLite, files, or logs.
- Configure Gemini model `gemini-3.1-flash-live-preview`, `AUDIO` output, Google Search, input/output audio transcription, automatic VAD, and start-of-speech interruption.
- Search only `AiDocumentContext.documentId`, return at most six local RAG chunks, and terminate a live session before an active-tab change can use stale context.
- PCM input is 16-bit little-endian 16 kHz; Gemini output is 24 kHz PCM. Do not use Groq or local speech-to-text for live captions.
- The existing `record` package captures PCM16 microphone data and `flutter_soloud` buffers PCM16 playback; `permission_handler` requests microphone permission. Add Android `RECORD_AUDIO` and `INTERNET`; add `NSMicrophoneUsageDescription` on iOS.
- Persist only completed exchanges through `ConversationStore`; partial or interrupted captions remain memory-only.
- UI copy uses sentence case. The orb respects `MediaQuery.disableAnimations`.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `lib/src/features/ai/domain/live_conversation.dart` | Immutable session state, transcript/source models, phases, and typed gateway events. |
| `lib/src/features/ai/infrastructure/gemini_live_gateway.dart` | Gemini WebSocket wire protocol, setup payload, event parsing, function-response encoding, and terminal close. |
| `lib/src/features/ai/infrastructure/live_audio_adapter.dart` | `record`/`flutter_soloud` wrapper for PCM capture, 24 kHz playback queue, levels, permission, and stop/dispose. |
| `lib/src/features/ai/application/live_conversation_controller.dart` | Lifecycle state machine, barge-in, RAG tool dispatcher, transcript finalization, persistence, and cleanup. |
| `lib/src/features/ai/application/ai_providers.dart` | Riverpod factories and the app-wide `liveConversationProvider`. |
| `lib/src/features/ai/presentation/live_conversation_surface.dart` | Voice entry button, status header, amplitude orb, live captions, citations/sources, error and exit actions. |
| `lib/src/features/ai/presentation/ai_side_pane.dart` | Chooses normal text/history or the live voice surface; ends voice on collapse/context change/disposal. |
| `lib/src/features/ai/ai.dart` | Public exports for the new domain, controller, and presentation surface. |
| `pubspec.yaml`, platform manifests | `flutter_soloud` and microphone/network platform declarations. |
| `test/ai/...` | Unit and widget coverage using fake Live gateway/audio adapters. |

### Task 1: Establish package, platform, and test seams

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Create: `test/ai/infrastructure/live_audio_adapter_test.dart`
- Create: `lib/src/features/ai/infrastructure/live_audio_adapter.dart`

**Interfaces:**
- Produces `LiveAudioAdapter` for later controller use:

```dart
abstract interface class LiveAudioAdapter {
  Future<bool> requestPermission();
  Stream<Uint8List> get inputPcm16;
  Stream<double> get inputLevel;
  Future<void> startCapture({String? deviceId});
  Future<void> enqueueOutputPcm24(Uint8List bytes);
  Future<void> stopOutput();
  Future<void> stop();
  Future<void> dispose();
}
```

- [ ] **Step 1: Add a failing adapter contract test**

```dart
test('stopping the adapter stops capture and clears queued output', () async {
  final audio = _FakeLiveAudioAdapter();
  await audio.startCapture();
  await audio.enqueueOutputPcm24(Uint8List.fromList(<int>[1, 2]));
  await audio.stop();
  expect(audio.captureActive, isFalse);
  expect(audio.queuedOutput, isEmpty);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ai/infrastructure/live_audio_adapter_test.dart`

Expected: FAIL because `LiveAudioAdapter` and its adapter implementation do not exist.

- [ ] **Step 3: Add the dependency and platform declarations**

Add `flutter_soloud: ^4.1.7` and `permission_handler` under `dependencies`. Add these direct children of the Android manifest root before `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

Add this iOS plist pair inside `<dict>`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Clarix uses the microphone for live document conversations.</string>
```

Run `flutter pub get` and inspect the generated plugin registration changes without manually editing generated files.

- [ ] **Step 4: Implement `RecordSoloudLiveAudioAdapter` minimally**

Wrap `AudioRecorder.startStream`, `AudioRecorder.onAmplitudeChanged`, and a SoLoud PCM data stream behind the interface. Start capture with:

```dart
await _recorder.startStream(const RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
));
```

Derive the input level from `onAmplitudeChanged`. `requestPermission()` calls `Permission.microphone.request()` and returns `true` only for `isGranted`. Initialize `SoLoud.instance`, create a mono `BufferType.s16le` streaming source at 24 kHz, and pass Gemini chunks to `addAudioDataStream`. `stopOutput()` must stop the current sound handle and reset/dispose the stream before a later reply. Make `stop()` and `dispose()` idempotent.

```dart
class RecordSoloudLiveAudioAdapter implements LiveAudioAdapter {
  RecordSoloudLiveAudioAdapter({AudioRecorder? recorder, SoLoud? soloud})
      : _recorder = recorder ?? AudioRecorder(),
        _soloud = soloud ?? SoLoud.instance;
  final AudioRecorder _recorder;
  final SoLoud _soloud;
}
```

- [ ] **Step 5: Run focused checks**

Run: `flutter test test/ai/infrastructure/live_audio_adapter_test.dart && flutter analyze lib/src/features/ai/infrastructure/live_audio_adapter.dart`

Expected: PASS with no analyzer diagnostics.

- [ ] **Step 6: Commit**

```powershell
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist lib/src/features/ai/infrastructure/live_audio_adapter.dart test/ai/infrastructure/live_audio_adapter_test.dart
git commit -m "feat: add live PCM audio adapter"
```

### Task 2: Define Live models and Gemini wire protocol

**Files:**
- Create: `lib/src/features/ai/domain/live_conversation.dart`
- Create: `lib/src/features/ai/infrastructure/gemini_live_gateway.dart`
- Create: `test/ai/infrastructure/gemini_live_gateway_test.dart`

**Interfaces:**
- Produces `GeminiLiveGateway` and `GeminiLiveSession` for Task 4.

```dart
enum LiveConversationPhase { idle, connecting, listening, endingUserTurn, retrievingDocument, searchingWeb, speaking, interrupted, error, ended }
sealed class GeminiLiveEvent { const GeminiLiveEvent(); }
abstract interface class GeminiLiveSession {
  Stream<GeminiLiveEvent> get events;
  Future<void> sendAudio(Uint8List pcm16k);
  Future<void> sendToolResponse({required String id, required String name, required Map<String, Object?> response});
  Future<void> close();
}
abstract interface class GeminiLiveGateway {
  Future<GeminiLiveSession> connect({required GeminiLiveConfiguration configuration});
}
```

- [ ] **Step 1: Write failing wire-format tests**

```dart
test('setup enables VAD barge-in, captions, RAG, and Google Search', () {
  final payload = GeminiLiveConfiguration(apiKey: 'key', documentTitle: 'report.pdf').setupPayload;
  expect(payload['setup']['model'], 'models/gemini-3.1-flash-live-preview');
  expect(payload.toString(), contains('inputAudioTranscription'));
  expect(payload.toString(), contains('outputAudioTranscription'));
  expect(payload.toString(), contains('googleSearch'));
  expect(payload.toString(), contains('query_active_document'));
});

test('parses all simultaneous server parts from one message', () {
  final events = GeminiLiveEventParser().parse(_serverMessageWithAudioAndTranscript);
  expect(events.whereType<GeminiAudioEvent>(), hasLength(1));
  expect(events.whereType<GeminiOutputTranscriptEvent>().single.text, 'Answer');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ai/infrastructure/gemini_live_gateway_test.dart`

Expected: FAIL because Live configuration/parser types do not exist.

- [ ] **Step 3: Implement immutable domain models**

Define `LiveTranscriptSegment`, `LiveWebSource`, `LiveConversationTurn`, `LiveConversationState`, `LiveCitation`, and event variants for session ready, activity start/end, input/output transcript fragment, PCM output, function call, search status, turn complete, error, and closed. `LiveConversationState.initial()` must be an idle, empty state and `copyWith` must preserve immutable lists.

- [ ] **Step 4: Implement the gateway**

Use `WebSocket.connect` to the documented Gemini Live endpoint with the API key only in the connection request. Send a setup message containing:

```dart
{
  'setup': {
    'model': 'models/gemini-3.1-flash-live-preview',
    'generationConfig': {'responseModalities': <String>['AUDIO']},
    'inputAudioTranscription': <String, Object?>{},
    'outputAudioTranscription': <String, Object?>{},
    'realtimeInputConfig': {
      'automaticActivityDetection': {
        'disabled': false,
        'activityHandling': 'START_OF_ACTIVITY_INTERRUPTS',
      },
    },
    'tools': <Object>[googleSearchTool, activeDocumentFunctionTool],
  },
}
```

Send microphone chunks with `realtimeInput.mediaChunks` and MIME type `audio/pcm;rate=16000`; parse every part in `serverContent.modelTurn.parts`, not only the first part. Encode function responses with the received call id/name. Treat malformed JSON or unexpected event shape as `GeminiLiveErrorEvent` without including server payloads that might contain sensitive material.

- [ ] **Step 5: Run focused checks**

Run: `flutter test test/ai/infrastructure/gemini_live_gateway_test.dart && flutter analyze lib/src/features/ai/domain/live_conversation.dart lib/src/features/ai/infrastructure/gemini_live_gateway.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/ai/domain/live_conversation.dart lib/src/features/ai/infrastructure/gemini_live_gateway.dart test/ai/infrastructure/gemini_live_gateway_test.dart
git commit -m "feat: add Gemini Live protocol gateway"
```

### Task 3: Build the active-document RAG tool response

**Files:**
- Create: `lib/src/features/ai/application/live_document_tool.dart`
- Create: `test/ai/application/live_document_tool_test.dart`

**Interfaces:**
- Consumes `LocalRagService.retrieve(String, String, {int limit})` and `AiDocumentContext`.
- Produces `ActiveDocumentToolResult` used by Task 4:

```dart
class ActiveDocumentTool {
  Future<ActiveDocumentToolResult> execute({required AiDocumentContext context, required String query});
}
class ActiveDocumentToolResult {
  const ActiveDocumentToolResult({required this.response, required this.citations});
  final Map<String, Object?> response;
  final List<CitationSnippet> citations;
}
```

- [ ] **Step 1: Write failing tool tests**

```dart
test('returns page-aware excerpts from only the supplied active document', () async {
  final result = await tool.execute(context: activeDocument, query: 'termination');
  expect(fakeRag.documentIds, <String>[activeDocument.documentId]);
  expect(result.response['matches'], isNotEmpty);
  expect(result.citations.single.pageNumber, 4);
});

test('reports unavailable grounding without throwing', () async {
  final result = await unavailableTool.execute(context: activeDocument, query: 'term');
  expect(result.response['status'], 'unavailable');
  expect(result.citations, isEmpty);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ai/application/live_document_tool_test.dart`

Expected: FAIL because `ActiveDocumentTool` does not exist.

- [ ] **Step 3: Implement compact, deterministic results**

Reject blank queries as `{status: 'invalid_query', matches: []}`. Call local RAG once with `context.documentId` and `limit: 6`. Map chunks to `CitationSnippet` and send only `title`, `pageNumber`, optional `sectionTitle`, and a bounded excerpt. Empty matches return `{status: 'no_matches', matches: []}`; retrieval exceptions return `{status: 'unavailable', matches: []}`. Do not include path, document id, key, or raw full PDF content.

- [ ] **Step 4: Run focused checks**

Run: `flutter test test/ai/application/live_document_tool_test.dart && flutter analyze lib/src/features/ai/application/live_document_tool.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/ai/application/live_document_tool.dart test/ai/application/live_document_tool_test.dart
git commit -m "feat: expose active-document RAG tool"
```

### Task 4: Implement the live conversation state machine and persistence

**Files:**
- Create: `lib/src/features/ai/application/live_conversation_controller.dart`
- Create: `test/ai/application/live_conversation_controller_test.dart`
- Modify: `lib/src/features/ai/domain/conversation.dart`
- Modify: `lib/src/features/ai/infrastructure/conversation_store.dart`
- Modify: `test/ai/domain_infrastructure/conversation_store_test.dart`

**Interfaces:**
- Consumes Tasks 1–3 and the current `ConversationStore` API.
- Produces:

```dart
class LiveConversationController extends StateNotifier<LiveConversationState> {
  Future<void> start(AiDocumentContext context);
  Future<void> end({String reason = 'Voice conversation ended.'});
  Future<void> replaceDocumentContext(AiDocumentContext context);
}
```

- [ ] **Step 1: Write failing lifecycle tests**

```dart
test('speech start interrupts queued model audio immediately', () async {
  await controller.start(document);
  fakeGateway.emit(const GeminiAudioEvent(Uint8List(4)));
  fakeGateway.emit(const GeminiActivityStartEvent());
  await pumpEventQueue();
  expect(fakeAudio.stopOutputCalls, 1);
  expect(controller.state.phase, LiveConversationPhase.listening);
});

test('function call persists one completed exchange with page citations', () async {
  await controller.start(document);
  fakeGateway.emit(const GeminiFunctionCallEvent(id: 'call-1', name: 'query_active_document', arguments: {'query': 'term'}));
  fakeGateway.emit(const GeminiInputTranscriptEvent('What are the terms?', isFinal: true));
  fakeGateway.emit(const GeminiOutputTranscriptEvent('They are on page four.', isFinal: true));
  fakeGateway.emit(const GeminiTurnCompleteEvent());
  await pumpEventQueue();
  expect(await store.readMessages(threadId), hasLength(2));
});

test('changing the active tab closes before it accepts new tool calls', () async {
  await controller.start(firstDocument);
  await controller.replaceDocumentContext(secondDocument);
  expect(fakeSession.closed, isTrue);
  expect(controller.state.phase, LiveConversationPhase.ended);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ai/application/live_conversation_controller_test.dart`

Expected: FAIL because the controller does not exist.

- [ ] **Step 3: Implement start and centralized cleanup**

`start` validates a non-empty Dart-defined key and microphone permission before connecting. Subscribe to gateway events and audio PCM only after a successful setup event. Every exit path goes through one private idempotent `_teardown()` that cancels subscriptions, calls `audio.stop()`, closes the session, and clears references. The controller owns no UI `BuildContext`.

- [ ] **Step 4: Implement event transitions and tool calls**

Map activity start to immediate `audio.stopOutput()` and `listening`; map output PCM to `audio.enqueueOutputPcm24` and `speaking`; map function calls named `query_active_document` through `ActiveDocumentTool`, add returned citations to the pending turn, and respond with the exact Gemini call id. Unknown functions receive a `{status: 'unsupported_function'}` response. Google Search grounding events only set `searchingWeb` and collect their final source metadata. Never start a model reply locally: wait for Gemini events.

- [ ] **Step 5: Persist only completed turns and sources**

Add `List<LiveWebSource> sources` to `ConversationMessage`, defaulting to an empty immutable list. Upgrade `ConversationStore` to schema version 3 with nullable `sources_json TEXT`; the migration uses `ALTER TABLE conversation_messages ADD COLUMN sources_json TEXT`. Encode an empty list as `[]`, decode missing/null legacy values to an empty list, and include sources when appending and reading an exchange. Accumulate server input/output transcripts in a pending turn. On a model `turnComplete`, skip persistence if either finalized side is empty or the turn was interrupted. Otherwise create/reuse an existing-document thread, append user/assistant messages, and update state with the completed turn, assistant `CitationSnippet`s, and web sources.

- [ ] **Step 6: Run focused checks**

Run: `flutter test test/ai/application/live_conversation_controller_test.dart test/ai/domain_infrastructure/conversation_store_test.dart && flutter analyze lib/src/features/ai/application/live_conversation_controller.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add lib/src/features/ai/application/live_conversation_controller.dart lib/src/features/ai/infrastructure/conversation_store.dart lib/src/features/ai/domain/conversation.dart test/ai/application/live_conversation_controller_test.dart test/ai/domain_infrastructure/conversation_store_test.dart
git commit -m "feat: manage persistent live document conversations"
```

### Task 5: Wire Riverpod and active-tab lifecycle

**Files:**
- Modify: `lib/src/features/ai/application/ai_providers.dart`
- Modify: `lib/src/features/ai/ai.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/workspace_body.dart`
- Create: `test/ai/application/live_conversation_providers_test.dart`

**Interfaces:**
- Produces `liveConversationProvider`, a single controller instance whose state is `LiveConversationState`.
- Consumes `AiDocumentContext?` already passed into `AiSidePane` and active tab changes already observed by `WorkspaceBody`.

- [ ] **Step 1: Write failing provider/lifecycle tests**

```dart
test('provider disposes its live session when the container is disposed', () async {
  final container = ProviderContainer(overrides: _liveOverrides);
  await container.read(liveConversationProvider.notifier).start(document);
  container.dispose();
  expect(fakeAudio.disposeCalls, 1);
  expect(fakeSession.closed, isTrue);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ai/application/live_conversation_providers_test.dart`

Expected: FAIL because the provider is absent.

- [ ] **Step 3: Register providers without touching typed-chat provider state**

Construct the gateway with `const String.fromEnvironment('GEMINI_API_KEY')`, `AudioIoLiveAudioAdapter`, `ActiveDocumentTool`, and the existing conversation-store future. Register `ref.onDispose(controller.dispose)`. Do not add Gemini as an `AiProviderProfile`, and do not change `AiRuntimeService`.

- [ ] **Step 4: End the session on active-document identity changes**

At the workspace/pane boundary compare `AiDocumentContext.tabId` with the context passed to a live session. If it differs while the controller is not idle/ended, call `end(reason: 'Voice conversation ended because the active document changed.')`. Do this before rendering the new document’s pane and before any tool callback can see it.

- [ ] **Step 5: Run focused checks**

Run: `flutter test test/ai/application/live_conversation_providers_test.dart && flutter analyze lib/src/features/ai/application/ai_providers.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart lib/src/features/ai/ai.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/ai/application/ai_providers.dart lib/src/features/ai/ai.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart test/ai/application/live_conversation_providers_test.dart
git commit -m "feat: wire live conversations to active documents"
```

### Task 6: Create the voice surface and integrate it into the AI pane

**Files:**
- Create: `lib/src/features/ai/presentation/live_conversation_surface.dart`
- Modify: `lib/src/features/ai/presentation/ai_side_pane.dart`
- Modify: `test/ai/application_presentation/ai_side_pane_test.dart`
- Create: `test/ai/presentation/live_conversation_surface_test.dart`

**Interfaces:**
- Consumes `LiveConversationState`, `LiveConversationController`, `AiDocumentContext`, and `WorkspaceSurfaceTokens`.
- Produces `LiveConversationSurface` with `onStart`, `onEnd`, and `onRetry` callbacks.

- [ ] **Step 1: Write failing visual-state tests**

```dart
testWidgets('start action swaps the composer for the listening surface', (tester) async {
  await tester.pumpWidget(_pane(liveState: LiveConversationState.initial()));
  await tester.tap(find.byKey(const Key('start-live-conversation')));
  await tester.pump();
  expect(find.byKey(const Key('live-conversation-orb')), findsOneWidget);
  expect(find.byKey(const Key('end-live-conversation')), findsOneWidget);
});

testWidgets('reduced motion shows a static listening status', (tester) async {
  await tester.pumpWidget(_surface(disableAnimations: true, phase: LiveConversationPhase.listening));
  expect(find.text('Listening'), findsOneWidget);
  expect(find.byType(AnimatedBuilder), findsNothing);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ai/presentation/live_conversation_surface_test.dart test/ai/application_presentation/ai_side_pane_test.dart`

Expected: FAIL because the surface and entry action do not exist.

- [ ] **Step 3: Build the focused visual system**

Implement a `CustomPainter` or `AnimatedBuilder` orb keyed
`live-conversation-orb`; map `inputAmplitude` to radius/glow only in
`listening` and use a slow repeating output amplitude wave only in `speaking`.
Use deep indigo fill with a narrow cyan/lilac shaded edge and current
`WorkspaceSurfaceTokens` for every other surface. With
`MediaQuery.disableAnimations`, render the same state as a non-animated orb
plus a text status. Do not add a generic card grid or a second page.

- [ ] **Step 4: Render complete interaction states**

Provide the entry action `Start voice conversation`, a status header, `End
voice conversation` button keyed `end-live-conversation`, a single retry
button only for errors, scrollable captions, local page chips, and web source
links. Map phases to exact user-facing strings: `Connecting…`, `Listening`,
`Finishing your turn…`, `Finding relevant passages…`, `Searching the web…`,
`Speaking`, and `Interrupted`. Keep the normal composer available only while
the session is idle or ended. Pane collapse calls `controller.end()` before
`widget.onCollapse()`.

- [ ] **Step 5: Run focused checks**

Run: `flutter test test/ai/presentation/live_conversation_surface_test.dart test/ai/application_presentation/ai_side_pane_test.dart && flutter analyze lib/src/features/ai/presentation/live_conversation_surface.dart lib/src/features/ai/presentation/ai_side_pane.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/ai/presentation/live_conversation_surface.dart lib/src/features/ai/presentation/ai_side_pane.dart test/ai/presentation/live_conversation_surface_test.dart test/ai/application_presentation/ai_side_pane_test.dart
git commit -m "feat: add hands-free AI conversation surface"
```

### Task 7: Run regression checks and document manual verification

**Files:**
- Modify: `README.md`
- Create: `docs/testing/gemini-live-document-conversation-runbook.md`
- Modify: test files from Tasks 1–6 only if regression failures reveal a real contract gap

**Interfaces:**
- Consumes the complete integrated feature.
- Produces reproducible startup and manual verification instructions.

- [ ] **Step 1: Write the failing launch-documentation assertion if the repository tests README commands**

If no documentation test exists, skip creating a test and proceed directly to the implementation step; do not add a test merely to mirror Markdown.

- [ ] **Step 2: Document the exact launch command and test matrix**

Add this command to the README and runbook, without placing a real key in either file:

```powershell
flutter run -d windows --dart-define=GEMINI_API_KEY=your-key
```

The runbook must test microphone permission, a normal turn, built-in user/model captions, immediate barge-in, active-PDF retrieval/page citations, Google Search source display, saved history after a completed exchange, active-tab session termination, network-disconnect retry, and resource cleanup after pane collapse.

- [ ] **Step 3: Run automated verification**

Run:

```powershell
flutter test test/ai
flutter test test/workspace_ai
flutter analyze
```

Expected: all tests pass and analyzer exits 0. Investigate failures before changing unrelated code.

- [ ] **Step 4: Run the Windows manual check**

Run the documented command with a user-provided key. Confirm no key appears in logs, source, SQLite files, or preferences. Record results in the runbook with date, Windows version, audio device, and pass/fail for each case.

- [ ] **Step 5: Commit**

```powershell
git add README.md docs/testing/gemini-live-document-conversation-runbook.md test
git commit -m "docs: add Gemini Live verification runbook"
```

## Plan review

### Spec coverage

- Hands-free turns, server VAD, and barge-in: Tasks 1, 2, and 4.
- Gemini model, audio, server captions, Google Search, and synchronous tool calls: Task 2.
- Active-tab-only local RAG with page-aware citations: Task 3 and Task 4.
- Existing history persistence and web-source migration: Task 4.
- Pane visual direction, reduced motion, error/retry, collapse behavior: Task 6.
- Dart define, platform permissions, tests, and manual Windows validation: Tasks 1 and 7.
- PDFRx preservation and experimental branch constraints: Global Constraints.

### Consistency check

`GeminiLiveGateway`/`GeminiLiveSession`, `LiveAudioAdapter`,
`ActiveDocumentTool`, and `LiveConversationController` are introduced before
their consumers. The controller alone owns cleanup and persistence; UI only
renders state and invokes controller commands. Conversation schema work is
explicitly conditional on preserving web source URLs, with a named migration
version and regression requirement.
