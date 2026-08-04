# Document Conversation History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist document-bound AI threads in SQLite, support continuation and deletion, and keep provider requests within a configurable context window through invisible history compaction.

**Architecture:** A `ConversationStore` backed by SQLite owns durable thread, message, and summary records. The workspace notifier projects one active thread into `AiWorkspaceState`, while `AiAgentRuntime` builds a document-grounded request from the compacted summary and recent turns. The AI pane manages threads for only the active document; Settings independently clears cache or conversation data.

**Tech Stack:** Flutter, Riverpod, `sqflite_common_ffi`, `path_provider`, existing OpenAI-compatible provider client, Flutter widget/unit tests.

## Global Constraints

- A conversation belongs to exactly one `documentId`; cross-document threads are out of scope.
- Store data under Clarix application support, not `SharedPreferences`.
- Default `AiProviderProfile.contextWindowTokens` to `256000`; validate all stored and edited values as positive integers.
- Preserve complete original messages and citations after compaction; only model-facing request history is summarized.
- Answers must be grounded in retrieved document passages and inline page citations, with no `From the document` or `General knowledge` headings.
- External information may appear only as `*(General context, not stated in the document: …)*`.
- Clear document cache and clear all conversations are separate confirmed Settings actions.
- Implement and commit directly on `main`, preserving all pre-existing worktree changes.

---

## File structure

- `lib/src/features/workspace/domain/conversation.dart`: immutable conversation/message/summary models and citation conversion.
- `lib/src/features/workspace/infrastructure/conversation_store.dart`: SQLite schema, migrations, and transactional persistence boundary.
- `lib/src/features/workspace/application/conversation_context.dart`: token estimation, compaction selection, and request-context model.
- `lib/src/features/workspace/application/ai_agent_runtime.dart`: grounded prompt assembly and compaction-provider calls.
- `lib/src/features/workspace/application/workspace_notifier.dart`: active-thread lifecycle, persistence orchestration, cache/conversation clearing.
- `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`: thread controls and context indicator.
- `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`: provider context limit and Storage actions.
- `test/workspace_ai/conversation_store_test.dart`: SQLite persistence/isolation coverage.
- `test/workspace_ai/conversation_context_test.dart`: estimation/compaction policy coverage.

### Task 1: Add durable conversation primitives and SQLite storage

**Files:**

- Modify: `pubspec.yaml`
- Create: `lib/src/features/workspace/domain/conversation.dart`
- Create: `lib/src/features/workspace/infrastructure/conversation_store.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Test: `test/workspace_ai/conversation_store_test.dart`

**Interfaces:**

- Produces `ConversationThread`, `ConversationMessage`, `ConversationStore`, and `conversationStoreProvider`.
- `ConversationStore` provides `listThreads(documentId)`, `readThread(threadId)`, `createThread(documentId, title)`, `appendExchange(...)`, `deleteThread(threadId)`, and `clearAll()`.

- [ ] **Step 1: Write the failing storage tests**

Use a temporary directory-backed database. Test schema creation, document filtering, ordered messages, citation round trip, cascade deletion, and `clearAll`.

```dart
test('threads never cross document boundaries', () async {
  final store = await _openStore(tempDir);
  await store.createThread(documentId: 'one', title: 'First');
  await store.createThread(documentId: 'two', title: 'Second');
  expect(await store.listThreads('one'), hasLength(1));
  expect(await store.listThreads('two'), hasLength(1));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace_ai/conversation_store_test.dart`

Expected: FAIL because the storage API does not yet exist.

- [ ] **Step 3: Implement models, schema, and transaction-backed store**

Add `sqflite_common_ffi`. Create the approved `conversations` and `conversation_messages` tables, both indexes, foreign-key cascade behavior, and a transaction for each complete user/assistant exchange. Initialize FFI once for Windows and use application-support storage in production, injected paths in tests.

```dart
Future<void> appendExchange({
  required String threadId,
  required ConversationMessage user,
  required ConversationMessage assistant,
}) => _database.transaction((txn) async {
  await _insertMessage(txn, threadId, user);
  await _insertMessage(txn, threadId, assistant);
  await txn.update('conversations', <String, Object?>{
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  }, where: 'id = ?', whereArgs: <Object?>[threadId]);
});
```

- [ ] **Step 4: Run focused verification**

Run: `flutter test test/workspace_ai/conversation_store_test.dart && flutter analyze lib/src/features/workspace/domain/conversation.dart lib/src/features/workspace/infrastructure/conversation_store.dart`

Expected: PASS with no analyzer issues.

- [ ] **Step 5: Commit the storage boundary**

```powershell
git add pubspec.yaml pubspec.lock lib/src/features/workspace/domain/conversation.dart lib/src/features/workspace/infrastructure/conversation_store.dart lib/src/features/workspace/application/workspace_providers.dart test/workspace_ai/conversation_store_test.dart
git commit --only -m "feat: persist document conversations in sqlite" -- pubspec.yaml pubspec.lock lib/src/features/workspace/domain/conversation.dart lib/src/features/workspace/infrastructure/conversation_store.dart lib/src/features/workspace/application/workspace_providers.dart test/workspace_ai/conversation_store_test.dart
```

### Task 2: Account for provider context and compact eligible history

**Files:**

- Create: `lib/src/features/workspace/application/conversation_context.dart`
- Modify: `lib/src/features/workspace/domain/ai_provider.dart`
- Modify: `lib/src/features/workspace/infrastructure/provider_profile_store.dart`
- Modify: `lib/src/features/workspace/application/ai_agent_runtime.dart`
- Test: `test/workspace_ai/conversation_context_test.dart`
- Test: `test/workspace_ai/ai_agent_runtime_test.dart`

**Interfaces:**

- Produces `ContextBudget`, `ConversationContextPlanner`, and `AiAgentRequest.threadContext`.
- `ConversationContextPlanner.plan(...)` returns percentage, selected summary, recent messages, and the oldest complete turns needing compaction.

- [ ] **Step 1: Write failing context-limit and compaction-policy tests**

Test the `256000` legacy default, a custom provider value, percentage calculations including completion reserve, and selection of oldest whole exchanges while retaining newer turns.

```dart
expect(
  planner.plan(messages: turns, limit: 100, reservedCompletion: 20)
      .messagesToCompact,
  containsAllInOrder(<String>['user-1', 'assistant-1']),
);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace_ai/conversation_context_test.dart test/workspace_ai/ai_agent_runtime_test.dart`

Expected: FAIL because profiles have no context limit or planner.

- [ ] **Step 3: Implement deterministic estimation and profile migration**

Estimate text tokens from text length for system instructions, current summary, recent messages, retrieval/tool text, and new prompt; reserve a fixed completion budget. Add and validate `contextWindowTokens`; old profile JSON must map to `256000`.

- [ ] **Step 4: Implement compaction request and clean grounding instruction**

Add thread context to `AiAgentRequest`. Request a preservation-focused summary only when the planner requires compaction. The normal instruction must require direct, cited document answers; forbid old source headings; and allow external information only as the approved italic disclaimer.

```dart
const String groundingInstruction =
    'Answer directly from supplied document evidence with inline page citations. '
    'Do not use From the document or General knowledge headings. '
    'Outside information is allowed only as *(General context, not stated in the document: …)*.';
```

- [ ] **Step 5: Run focused verification and commit**

Run: `flutter test test/workspace_ai/conversation_context_test.dart test/workspace_ai/ai_agent_runtime_test.dart && flutter analyze lib/src/features/workspace/application/conversation_context.dart lib/src/features/workspace/application/ai_agent_runtime.dart lib/src/features/workspace/domain/ai_provider.dart`

Commit only the files listed above with message `feat: manage chat context windows`.

### Task 3: Integrate persistent threads into the workspace lifecycle

**Files:**

- Modify: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Test: `test/workspace_ai/workspace_notifier_test.dart`

**Interfaces:**

- Produces active-thread fields on `AiWorkspaceState` and notifier operations `loadConversationForDocument`, `startNewConversation`, `selectConversation`, `deleteConversation`, `clearAllConversations`, and `clearDocumentCache`.

- [ ] **Step 1: Write failing notifier tests**

Cover latest-thread restoration when a document is selected, thread creation on first send, follow-up context flowing to the runtime, deletion returning to empty state, and database errors leaving rendered messages unchanged.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace_ai/workspace_notifier_test.dart`

Expected: FAIL because the notifier has no thread operations.

- [ ] **Step 3: Extend state and hydrate/flush the active document thread**

Add active thread ID, thread summaries, context usage, and preparing-compaction state. On document selection/open, load only that document’s latest thread. On send, persist completed user/assistant results transactionally; save compaction summaries and compacted flags only after successful compaction. Do not persist incomplete streaming output as a complete exchange.

- [ ] **Step 4: Implement independently scoped clear operations**

`clearAllConversations` invokes `ConversationStore.clearAll` and clears the active AI projection. `clearDocumentCache` deletes only document metadata, extraction artifacts, chunks, and retrieval indexes through their owning stores; it retains SQLite conversations and provider data.

- [ ] **Step 5: Run focused verification and commit**

Run: `flutter test test/workspace_ai/workspace_notifier_test.dart && flutter analyze lib/src/features/workspace/domain/workspace_feature_state.dart lib/src/features/workspace/application/workspace_notifier.dart`

Commit only the task files with message `feat: continue document chat threads`.

### Task 4: Expose thread and context controls in the AI pane

**Files:**

- Modify: `lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`
- Test: `test/workspace_ai/ai_side_pane_test.dart`

**Interfaces:**

- Consumes active-thread state and notifier actions from Task 3.
- Produces a document-filtered history selector, delete/new actions, and context percentage indicator.

- [ ] **Step 1: Write failing widget tests**

Pump a pane with two threads for one document and a thread for another. Verify the other-document thread is absent, selecting restores its full transcript, new conversation clears only active display, percentage is shown, and deletion requests confirmation.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart`

Expected: FAIL because the header has no thread/history controls.

- [ ] **Step 3: Implement compact header controls and preparation state**

Keep title and close control. Add a history menu, new-conversation icon, and tooltip-backed percentage meter. Disable changes/destructive actions while generating or compacting. Render persisted and compacted messages through the existing message renderer.

- [ ] **Step 4: Run focused verification and commit**

Run: `flutter test test/workspace_ai/ai_side_pane_test.dart && flutter analyze lib/src/features/workspace/presentation/widgets/ai_side_pane.dart`

Commit only the task files with message `feat: manage document chat history in pane`.

### Task 5: Add Settings context configuration and independent storage clearing

**Files:**

- Modify: `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`
- Test: `test/workspace_ai/app_settings_dialog_test.dart`
- Test: `test/workspace_ai/provider_profile_store_test.dart`

**Interfaces:**

- Consumes `contextWindowTokens`, `clearDocumentCache`, and `clearAllConversations`.
- Produces a validated provider context input and confirmed Storage maintenance actions.

- [ ] **Step 1: Write failing Settings tests**

Test a `256000` default field, zero/non-numeric rejection, saving custom value, and each maintenance action invoking only its matching notifier method after confirmation.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace_ai/app_settings_dialog_test.dart test/workspace_ai/provider_profile_store_test.dart`

Expected: FAIL because the field and Storage section do not exist.

- [ ] **Step 3: Implement advanced context input and Storage section**

Add numeric `Context window (tokens)` to provider editor. Add separate descriptive, confirmed actions: clear cache states conversations remain; clear conversations states cache/providers remain. Surface completion/failure feedback.

- [ ] **Step 4: Run focused verification and commit**

Run: `flutter test test/workspace_ai/app_settings_dialog_test.dart test/workspace_ai/provider_profile_store_test.dart && flutter analyze lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart`

Commit only the task files with message `feat: configure and clear AI conversation storage`.

### Task 6: Run end-to-end verification

**Files:**

- Verify all Task 1–5 files.

- [ ] **Step 1: Format changed files**

Run: `dart format lib test`

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: no issues.

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 4: Build the Windows target**

Run: `flutter build windows --debug`

Expected: successful build.

- [ ] **Step 5: Inspect scope**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors; only intended feature changes plus pre-existing user changes.
