# OpenAI-Compatible Agent Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Replace Flutter Gemma in the workspace with secure, user-configured OpenAI-compatible streaming chat and a bounded typed read-only agent loop.

**Architecture:** \`WorkspaceNotifier\` invokes \`AiAgentRuntime\`, which gathers local chunks, calls \`OpenAiCompatibleProvider\`, validates tool calls, runs read-only tools, and persists the result. Provider metadata lives in preferences; API keys live only in \`flutter_secure_storage\`.

**Tech Stack:** Flutter/Dart 3.12, Riverpod 3, \`dart:io\` \`HttpClient\`, SSE, \`flutter_secure_storage: ^10.3.1\`, SharedPreferencesAsync, existing PDF chunks, flutter_test.

## Global Constraints

- Retain the reader diagnostics hub; change only the existing fourth workspace section.
- Remove \`flutter_gemma\`, \`flutter_gemma_litertlm\`, \`flutter_gemma_embeddings\`, and \`flutter_gemma_rag_qdrant\` plus all imports/call sites.
- No Python, LangChain/LangGraph, Google ADK, or Rust LLM runtime.
- Send only a bounded retrieved-passage packet when the selected profile has \`shareRetrievedPassages == true\`; never send a full PDF by default.
- Store each key only as \`clarix.provider.<profileId>.api_key\` in FlutterSecureStorage. Do not log, serialize, or put it in run history.
- Phase 2 tools are read-only and allow-listed; model/tool execution has a six-round maximum.
- Cancellation closes the request and retains partial output/events.
- Write and observe every test fail before production code.

---

## File structure

- Create \`lib/src/features/workspace/domain/ai_provider.dart\`: provider/profile, chat message, tool call, run/event value types.
- Create \`lib/src/features/workspace/infrastructure/provider_profile_store.dart\`: preferences metadata plus secure-key indirection.
- Create \`lib/src/features/workspace/infrastructure/openai_compatible_provider.dart\`: HTTP request, SSE parser, normalized deltas/tool calls.
- Create \`lib/src/features/workspace/application/ai_tool_registry.dart\`: schemas, validation, read-only chunk/context tools.
- Replace \`ai_runtime_service.dart\` with \`lib/src/features/workspace/application/ai_agent_runtime.dart\`.
- Modify \`models.dart\`, \`session_store.dart\`, providers, notifier, and AI widgets for provider state and streamed runs.
- Delete the Gemma model catalog, local store, Windows asset helper, and model catalog sheet.
- Add focused tests under \`test/workspace_ai/\`; remove only obsolete Gemma tests from \`test/widget_test.dart\`.

### Task 1: Secure provider profile boundary

**Files:**
- Create: \`lib/src/features/workspace/domain/ai_provider.dart\`
- Create: \`lib/src/features/workspace/infrastructure/provider_profile_store.dart\`
- Modify: \`pubspec.yaml\`, \`pubspec.lock\`
- Test: \`test/workspace_ai/provider_profile_store_test.dart\`

**Interfaces:**
- Produces \`AiProviderProfile\` (\`id,label,baseUrl,modelId,shareRetrievedPassages,headers\`) with \`Uri get chatCompletionsUri\`.
- Produces \`ProviderProfileStore.readProfiles/saveProfile/readApiKey/deleteProfile\`.

- [ ] **Step 1: Write the failing tests**

\`\`\`dart
test('profile constructs the chat completions URL', () {
  final profile = AiProviderProfile.create(
    id: 'openai', label: 'OpenAI', baseUrl: 'https://api.openai.com/v1/',
    modelId: 'gpt-5', shareRetrievedPassages: true,
  );
  expect(profile.chatCompletionsUri.toString(),
      'https://api.openai.com/v1/chat/completions');
});

test('store persists metadata without serializing the API key', () async {
  await store.saveProfile(profile, apiKey: 'sk-secret');
  expect(await store.readProfiles(), contains(profile));
  expect(await store.readApiKey(profile.id), 'sk-secret');
  expect(preferences.getString('clarix.ai.providers'), isNot(contains('sk-secret')));
});
\`\`\`

- [ ] **Step 2: Verify red**

Run: \`flutter test test/workspace_ai/provider_profile_store_test.dart\`

Expected: FAIL because the profile and store types are missing.

- [ ] **Step 3: Implement the minimum contract**

Add \`flutter_secure_storage: ^10.3.1\`. Store profile JSON in \`clarix.ai.providers\`, and write/delete the key via injected \`FlutterSecureStorage\`. Normalize a missing trailing slash; allow HTTPS plus only \`http://localhost\` and \`http://127.0.0.1\`. Reject blank ID/label/model, malformed URLs, and custom \`Authorization\` headers.

\`\`\`dart
Uri get chatCompletionsUri =>
    Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/')
        .resolve('chat/completions');
\`\`\`

- [ ] **Step 4: Verify green**

Run: \`flutter test test/workspace_ai/provider_profile_store_test.dart\`

Expected: PASS for JSON round trip, key replacement/deletion, and invalid URL/header rejection.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add pubspec.yaml pubspec.lock lib/src/features/workspace/domain/ai_provider.dart lib/src/features/workspace/infrastructure/provider_profile_store.dart test/workspace_ai/provider_profile_store_test.dart
git commit -m "feat: add secure AI provider profiles"
\`\`\`

### Task 2: OpenAI-compatible SSE client

**Files:**
- Create: \`lib/src/features/workspace/infrastructure/openai_compatible_provider.dart\`
- Test: \`test/workspace_ai/openai_compatible_provider_test.dart\`

**Interfaces:**
- Produces \`OpenAiCompatibleProvider.streamChat(OpenAiChatRequest): Stream<AiProviderEvent>\`, \`cancel()\`, \`AiTextDelta\`, \`AiCompletionFinished\`, and \`AiProviderException\`.
- Consumes a profile, key, normalized chat messages, and OpenAI function-tool JSON.

- [ ] **Step 1: Write failing transport tests**

\`\`\`dart
test('encodes the standard streaming chat-completions request', () async {
  final request = fakeClient.requests.single;
  expect(request.headers['authorization'], 'Bearer sk-test');
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['stream'], isTrue);
  expect((body['tools'] as List).single['function']['name'], 'search_document');
});

test('parses text deltas and completion from SSE', () async {
  final events = await provider.streamChat(request).toList();
  expect(events.whereType<AiTextDelta>().map((event) => event.text).join(), 'Hello');
  expect(events.last, isA<AiCompletionFinished>());
});
\`\`\`

- [ ] **Step 2: Verify red**

Run: \`flutter test test/workspace_ai/openai_compatible_provider_test.dart\`

Expected: FAIL because the provider is missing.

- [ ] **Step 3: Implement streaming protocol normalization**

Use injected \`HttpClient\`, POST JSON to \`profile.chatCompletionsUri\`, and send \`Accept: text/event-stream\`, \`Authorization: Bearer <key>\`, profile headers, and \`stream: true\`. Buffer line-delimited \`data: \` SSE records; parse \`choices[0].delta.content\`; combine indexed \`tool_calls\` fragments by ID/name/argument JSON; emit \`AiCompletionFinished(toolCalls: ...)\` at \`[DONE]\`. Map non-2xx bodies to a sanitized \`AiProviderException\`.

\`\`\`dart
if (data == '[DONE]') {
  yield AiCompletionFinished(toolCalls: accumulatedToolCalls);
  return;
}
\`\`\`

- [ ] **Step 4: Verify green**

Run: \`flutter test test/workspace_ai/openai_compatible_provider_test.dart\`

Expected: PASS for headers/body, multi-frame tool arguments, malformed SSE, 401, 429, and cancellation.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add lib/src/features/workspace/infrastructure/openai_compatible_provider.dart test/workspace_ai/openai_compatible_provider_test.dart
git commit -m "feat: stream OpenAI-compatible completions"
\`\`\`

### Task 3: Tool schemas, local retrieval context, and agent loop

**Files:**
- Create: \`lib/src/features/workspace/application/ai_tool_registry.dart\`
- Create: \`lib/src/features/workspace/application/ai_agent_runtime.dart\`
- Test: \`test/workspace_ai/ai_agent_runtime_test.dart\`

**Interfaces:**
- Produces \`AiAgentRuntime.run(AiRunRequest, {onToken,onStatus}) -> Future<AiReply>\` and \`cancel()\`.
- Produces tools: \`search_document(query, document_id?)\`, \`get_page_context(document_id,page_number)\`, \`list_open_documents()\`.
- Consumes existing \`DocumentChunkStore\` / \`PdfChunkRecord\` and the provider from Task 2.

- [ ] **Step 1: Write failing agent tests**

\`\`\`dart
test('does not include source passages when sharing is disabled', () async {
  await runtime.run(request.copyWith(shareRetrievedPassages: false),
      onToken: (_) {}, onStatus: (_, __) {});
  expect(fakeProvider.requests.single.messages.join(), isNot(contains('[source')));
});

test('executes a valid read-only tool and returns its result to the model', () async {
  fakeProvider.enqueueToolCall('search_document', {'query': 'termination'});
  fakeProvider.enqueueFinalText('The clause is on page 4.');
  final reply = await runtime.run(request, onToken: (_) {}, onStatus: (_, __) {});
  expect(reply.text, contains('page 4'));
  expect(fakeProvider.requests, hasLength(2));
});

test('stops after six model/tool rounds', () async {
  fakeProvider.enqueueRepeatingToolCall();
  await expectLater(runtime.run(request, onToken: (_) {}, onStatus: (_, __) {}),
      throwsA(isA<AiAgentStepLimitException>()));
});
\`\`\`

- [ ] **Step 2: Verify red**

Run: \`flutter test test/workspace_ai/ai_agent_runtime_test.dart\`

Expected: FAIL because runtime/registry types are missing.

- [ ] **Step 3: Implement a bounded, validated loop**

Declare standard OpenAI function schemas with \`additionalProperties: false\`. Reject unknown names, non-object JSON, missing required fields, non-string query, page < 1, pages outside the active document, and document IDs outside the open-tab allow-list. Build a maximum of four sources, at most 1,500 characters each, yielding the current \`CitationSnippet\` values.

\`\`\`dart
for (var round = 0; round < 6; round++) {
  final completion = await _complete(messages, onToken);
  if (completion.toolCalls.isEmpty) {
    return AiReply(text: completion.text, citations: citations);
  }
  messages.addAll(await tools.executeAll(completion.toolCalls, context));
}
throw AiAgentStepLimitException();
\`\`\`

Use only local chunk data for tools. Convert safe tool exceptions to structured tool-result messages; fail immediately for policy/schema errors. Cancellation terminates the HTTP client, records partial text, and throws \`AiGenerationCancelledException\`.

- [ ] **Step 4: Verify green**

Run: \`flutter test test/workspace_ai/ai_agent_runtime_test.dart\`

Expected: PASS for sharing policy, sources/citations, tool success, unknown/invalid tool call, provider error, step limit, and partial cancellation.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add lib/src/features/workspace/application/ai_tool_registry.dart lib/src/features/workspace/application/ai_agent_runtime.dart test/workspace_ai/ai_agent_runtime_test.dart
git commit -m "feat: add bounded PDF reading agent"
\`\`\`

### Task 4: Migrate workspace state and delete local-model runtime

**Files:**
- Modify: \`lib/src/core/models.dart\`, \`lib/src/core/session_store.dart\`, \`lib/src/features/workspace/application/workspace_providers.dart\`, \`lib/src/features/workspace/application/workspace_notifier.dart\`, \`lib/src/core/boot.dart\`
- Delete: \`lib/flutter_gemma_windows_native_assets.dart\`, \`lib/src/core/local_gemma_model_store.dart\`, \`lib/src/core/model_catalog.dart\`, \`lib/src/features/workspace/application/ai_runtime_service.dart\`
- Test: \`test/workspace_ai/workspace_ai_migration_test.dart\`
- Modify test: \`test/widget_test.dart\`

**Interfaces:**
- \`AiWorkspaceState\` has \`providerReady, selectedProviderId, providerProfiles, messages, lastRunId, useCurrentDocumentScope\`; it has no inference/embedder/vector/catalog/download fields.
- \`WorkspaceNotifier\` exposes \`selectProvider/saveProvider/deleteProvider/testProvider/sendPrompt/stopGeneration\`.

- [ ] **Step 1: Write failing migration/notifier tests**

\`\`\`dart
test('legacy Gemma state restores PDFs but selects no remote provider', () async {
  await store.writeAiWorkspaceStateJson({'activeInferenceModelId': 'gemma-4-e2b-it'});
  final state = await container.read(workspaceNotifierProvider.future);
  expect(state.session.tabs.single.title, 'paper.pdf');
  expect(state.aiState.selectedProviderId, isNull);
  expect(state.aiState.statusMessage, contains('provider'));
});

test('notifier updates the assistant message from streamed tokens', () async {
  await notifier.sendPrompt('Summarize this PDF');
  expect(container.read(workspaceNotifierProvider).value!.aiState.messages.last.text,
      'Summary');
});
\`\`\`

- [ ] **Step 2: Verify red**

Run: \`flutter test test/workspace_ai/workspace_ai_migration_test.dart\`

Expected: FAIL because old model state and runtime remain.

- [ ] **Step 3: Implement migration and Riverpod wiring**

Replace Gemma phases with \`idle, validatingProvider, retrieving, callingProvider, executingTool, generating, cancelled, failed\`. Persist provider selection and messages/run IDs without keys. On restore, discard legacy active-model/embedder/download fields while retaining workspace session and PDF metadata. Load profiles and set readiness only if the selected profile exists and its secure key is readable. Replace model install/restore actions and status copy with profile actions. Wire \`AiAgentRuntime\` and \`ProviderProfileStore\` via providers; stream each token into the existing final assistant message.

Remove Flutter Gemma initialization and every Gemma catalog/download/vector synchronization branch. Existing chunk extraction remains, now feeding the Task 3 context builder.

- [ ] **Step 4: Verify green**

Run: \`flutter test test/workspace_ai/workspace_ai_migration_test.dart && flutter test\`

Expected: PASS. Remove or rewrite only the Gemma-specific catalog/local-file/restore tests in \`test/widget_test.dart\`; preserve reader behavior tests.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add lib/src/core/models.dart lib/src/core/session_store.dart lib/src/features/workspace/application/workspace_providers.dart lib/src/features/workspace/application/workspace_notifier.dart lib/src/core/boot.dart lib/flutter_gemma_windows_native_assets.dart lib/src/core/local_gemma_model_store.dart lib/src/core/model_catalog.dart lib/src/features/workspace/application/ai_runtime_service.dart test/workspace_ai/workspace_ai_migration_test.dart test/widget_test.dart
git commit -m "feat: replace Gemma workspace state with providers"
\`\`\`

### Task 5: Provider management and chat UI

**Files:**
- Create: \`lib/src/features/workspace/presentation/widgets/provider_settings_sheet.dart\`
- Modify: \`lib/src/features/workspace/presentation/widgets/ai_side_pane.dart\`, \`lib/src/features/workspace/presentation/widgets/workspace_body.dart\`
- Test: \`test/workspace_ai/ai_side_pane_test.dart\`

**Interfaces:**
- Uses notifier methods from Task 4.
- Renders selected provider, sharing state, settings CRUD, cancellation, citations, and sanitized execution details.

- [ ] **Step 1: Write failing widget tests**

\`\`\`dart
testWidgets('shows provider and remote-passage disclosure', (tester) async {
  await pumpPane(tester, profile: profile, selected: true);
  expect(find.text('OpenAI · Remote'), findsOneWidget);
  expect(find.text('Retrieved PDF passages may be shared'), findsOneWidget);
});

testWidgets('settings form saves a profile and key', (tester) async {
  await tester.tap(find.text('Add provider'));
  await tester.enterText(find.byKey(const Key('provider-base-url')),
      'https://api.openai.com/v1');
  await tester.enterText(find.byKey(const Key('provider-api-key')), 'sk-test');
  await tester.tap(find.text('Save provider'));
  expect(fakeNotifier.savedProfiles.single.modelId, 'gpt-5');
});
\`\`\`

- [ ] **Step 2: Verify red**

Run: \`flutter test test/workspace_ai/ai_side_pane_test.dart\`

Expected: FAIL because the picker and settings sheet are absent.

- [ ] **Step 3: Implement concise workspace controls**

Replace the model catalog control with a provider dropdown and settings button. Add explicit text showing remote use and whether retrieved passages may be shared. The settings sheet validates label/base URL/model/headers, saves the key only when supplied, tests credentials using a minimal chat-completions call, and asks before deletion. Disable composer only when no selected profile/key exists or a run is active. Replace send with enabled Stop during streaming. Render citations plus a disclosure containing provider/model, source count, tool names, elapsed time, and sanitized error.

- [ ] **Step 4: Verify green**

Run: \`flutter test test/workspace_ai/ai_side_pane_test.dart\`

Expected: PASS for no provider, configured provider, sharing disabled, streaming, cancellation, failed test, and delete confirmation.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add lib/src/features/workspace/presentation/widgets/ai_side_pane.dart lib/src/features/workspace/presentation/widgets/provider_settings_sheet.dart lib/src/features/workspace/presentation/widgets/workspace_body.dart test/workspace_ai/ai_side_pane_test.dart
git commit -m "feat: manage remote AI providers in workspace"
\`\`\`

### Task 6: Dependency removal and release verification

**Files:**
- Modify: \`pubspec.yaml\`, \`pubspec.lock\`, \`README.md\`
- Create test: \`test/workspace_ai/gemma_removal_test.dart\`

- [ ] **Step 1: Write the failing source boundary test**

\`\`\`dart
test('application source contains no Flutter Gemma import', () {
  final source = Directory('lib').listSync(recursive: true).whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.readAsStringSync()).join('\\n');
  expect(source, isNot(contains('flutter_gemma')));
});
\`\`\`

- [ ] **Step 2: Verify red**

Run: \`flutter test test/workspace_ai/gemma_removal_test.dart\`

Expected: FAIL while the Gemma runtime exists.

- [ ] **Step 3: Remove package graph and document remote privacy behavior**

Delete the four Flutter Gemma dependency lines, run \`flutter pub get\`, and update README to state: configurable OpenAI-compatible endpoints; platform-secure key storage; only bounded retrieved passages shared when enabled; no local inference in this release.

- [ ] **Step 4: Verify all release gates**

Run:

\`\`\`powershell
flutter pub get
flutter analyze
flutter test
cargo fmt --check --manifest-path rust/clarix_pdf_oxide/Cargo.toml
cargo clippy --manifest-path rust/clarix_pdf_oxide/Cargo.toml -- -D warnings
cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml
\`\`\`

Expected: every command exits 0. Rust remains PDF/OCR-only.

- [ ] **Step 5: Run the Windows smoke test and commit**

Run: \`flutter run -d windows\`

Expected: diagnostics hub opens; its fourth workspace creates/tests a provider, streams chat, exposes passage sharing, cancels a request, and restores the selected provider. Inspect preferences and logs: neither contains the API key.

\`\`\`powershell
git add pubspec.yaml pubspec.lock README.md test/workspace_ai/gemma_removal_test.dart
git commit -m "chore: remove Flutter Gemma runtime"
\`\`\`

