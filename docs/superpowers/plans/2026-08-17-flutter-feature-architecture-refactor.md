# Flutter Feature Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make AI, PDF editing, reader, settings, and utilities independent root-level Flutter features; leave workspace as a thin composition shell; preserve behavior and persisted/native contracts; and keep every hand-written production Dart file at or below 800 physical lines.

**Architecture:** Each feature owns its domain, application, infrastructure, and presentation code and publishes one small barrel. `workspace/application/workspace_feature_bindings.dart` is the composition point. Workspace owns tabs, layout, document lifecycle, and immutable shell state; feature notifiers/controllers own capability state. Core contains only genuinely shared contracts. Feature internals never import another feature's internal path.

**Tech Stack:** Flutter, Dart, Riverpod, SharedPreferencesAsync, SQLite-backed stores, flutter_rust_bridge/native PDF APIs, `flutter_test`, PowerShell verification scripts.

**Spec:** `docs/superpowers/specs/2026-08-17-flutter-feature-architecture-refactor-design.md`

**Execution mode:** Work inline on `main`; do not create a worktree. Make the named small commits after each task. Do not run stress tests, live-provider tests, full golden suites, release builds, or commands expected to take over 20 minutes. Stop a command that approaches that limit and record it as an optional user-run check.

**Global constraints:**

- Preserve UI layout, labels, shortcuts, errors, and behavior unless an import boundary requires a mechanical callback.
- Preserve all Rust, FRB, SQLite, native editor, JSON, preference, secure-key, and filesystem contracts.
- Never hand-edit generated files under `lib/src/core/ffi/`; they are the only file-size exemption.
- Do not use `part` files, giant extensions, duplicate implementations, or permanent forwarding exports to evade ownership or line-size rules.
- Do not split a hand-written file below 800 lines unless moving it is necessary for feature ownership.
- Run `dart format` only on touched Dart files. Use targeted tests after each task.
- Before every commit, inspect `git diff --check`, `git status --short`, and the staged diff. Preserve unrelated user changes.

---

## Task 1: Add executable architecture and persistence guardrails

**Files:**

- Create: `test/architecture/architecture_allowlist.dart`
- Create: `test/architecture/production_dart_file_size_test.dart`
- Create: `test/architecture/flutter_feature_boundaries_test.dart`
- Create: `test/architecture/feature_entry_points_test.dart`
- Create: `test/architecture/persistence_schema_compatibility_test.dart`
- Read without changing: `lib/src/core/session_store.dart`
- Read without changing: `lib/src/core/models.dart`
- Read without changing: `lib/src/features/workspace/infrastructure/provider_profile_store.dart`
- Read without changing: `lib/src/features/workspace/infrastructure/conversation_store.dart`

### 1.1 Create the temporary exception inventory

Use exact repository-relative paths, not directory-wide exceptions. Define:

```dart
const oversizedProductionDartAllowlist = <String>{
  'lib/src/core/editing/editor_bridge.dart',
  'lib/src/core/models.dart',
  'lib/src/features/workspace/application/workspace_notifier.dart',
  'lib/src/features/workspace/editing/application/editor_session_controller.dart',
  'lib/src/features/workspace/infrastructure/pdfium_text_engine_native.dart',
  'lib/src/features/workspace/domain/pdf_text_types.dart',
  'lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart',
  'lib/src/features/workspace/presentation/widgets/document_workspace.dart',
  'lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart',
};

const temporaryFeatureBoundaryAllowlist = <String>{
  // Populate only with existing violating source paths reported by the first
  // boundary-test run. Every entry must be deleted by Task 11.
};
```

Treat all files under `lib/src/core/ffi/` as generated exemptions, including `editing_api.dart`. Do not exempt other directories.

### 1.2 Write the production file-size test

The test must recursively enumerate `lib/**/*.dart`, normalize separators to `/`, skip `lib/src/core/ffi/`, count physical lines with `LineSplitter`, and fail when a non-allowlisted file exceeds 800 lines. It must also fail if an allowlisted path is missing or has already fallen below the limit, so stale exceptions cannot survive.

Run:

```powershell
flutter test test/architecture/production_dart_file_size_test.dart
```

Expected: PASS with the explicit temporary list.

### 1.3 Write dependency and entry-point tests

Parse source imports using a regular expression anchored to `import`/`export` directives. Enforce:

- `ai/**` cannot import `features/workspace/` or `features/pdf_editor/` internals;
- `pdf_editor/**` cannot import `features/ai/` or `features/workspace/`;
- `reader/**` and `utilities/**` cannot import `features/workspace/`;
- `settings/**` may import only the public `ai.dart` and `pdf_editor.dart` entry points from those features;
- outside a feature, imports of that feature must target its top-level barrel, except `workspace_feature_bindings.dart`, which may use public barrels only;
- no source export points back to a former workspace location.

The entry-point test must require these files:

```text
lib/src/features/ai/ai.dart
lib/src/features/pdf_editor/pdf_editor.dart
lib/src/features/reader/reader.dart
lib/src/features/settings/settings.dart
lib/src/features/utilities/utilities.dart
lib/src/features/workspace/workspace.dart
```

Initially, allow absent target feature folders and list current source violations explicitly. Tighten the test as each task lands; Task 11 removes every exception.

### 1.4 Characterize persisted schemas before moving ownership

Construct representative `WorkspaceSession`, `AiWorkspaceState`, provider profile, conversation, citation, bookmark, highlight, and document-chunk values. Assert exact JSON maps, default decoding, and round trips. Assert these preference keys as literals:

```dart
expect(ClarixSessionStore.workspaceStorageKeyForTest, 'clarix.workspace.session');
expect(ClarixSessionStore.aiStorageKeyForTest, 'clarix.ai.state');
expect(ProviderProfileStore.profilesStorageKeyForTest, 'clarix.ai.providers');
expect(ProviderProfileStore.defaultProfileStorageKeyForTest,
    'clarix.ai.default_provider');
```

Expose test-visible static getters rather than duplicating private implementation constants. For SQLite/file stores, use their existing in-memory/temp-directory test fixtures and assert schema/migration identifiers already covered by their focused tests. Do not alter production serialization.

Run:

```powershell
flutter test test/architecture/persistence_schema_compatibility_test.dart
flutter test test/architecture/flutter_feature_boundaries_test.dart test/architecture/feature_entry_points_test.dart
```

### 1.5 Commit

```powershell
git add test/architecture lib/src/core/session_store.dart lib/src/features/workspace/infrastructure/provider_profile_store.dart
git commit -m "test: characterize Flutter architecture contracts"
```

---

## Task 2: Extract the PDF editor domain and native infrastructure

**Files:**

- Create: `lib/src/features/pdf_editor/pdf_editor.dart`
- Move: `lib/src/features/workspace/domain/pdf_*.dart` → `lib/src/features/pdf_editor/domain/`
- Move: `lib/src/features/workspace/editing/domain/*.dart` → `lib/src/features/pdf_editor/domain/`
- Move: `lib/src/features/workspace/infrastructure/pdf_native_text_layout.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move: `lib/src/features/workspace/infrastructure/pdf_text_block_grouper.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move: `lib/src/features/workspace/infrastructure/pdf_text_engine.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move: `lib/src/features/workspace/infrastructure/pdfium_text_engine_{native,stub}.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move: `lib/src/features/workspace/infrastructure/pdfium_worker_executor.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move: `lib/src/features/workspace/infrastructure/{installed_font_catalog,windows_font_source}.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move tests: `test/workspace_pdf/**` → `test/pdf_editor/domain_infrastructure/**`

### 2.1 Move without renaming public concepts

Use `Move-Item` only for exact files after verifying each source and destination. Then update imports mechanically. The initial `pdf_editor.dart` exports only domain contracts and `PdfTextEngine`; do not export concrete native workers or font sources.

### 2.2 Split `pdfium_text_engine_native.dart`

Keep the `PdfiumTextEngineNative` adapter in `pdfium_text_engine_native.dart`. Extract cohesive helpers until every file is below 800 lines:

- `pdfium_text_document.dart`: document lifetime and page loading;
- `pdfium_text_extractor.dart`: character/word/block extraction and mapping;
- `pdfium_text_geometry.dart`: native rectangles, transforms, and normalization.

Keep the same `PdfTextEngine` behavior and error text. Helpers are infrastructure-private and are not barrel exports.

Split `pdf_text_types.dart` at its existing type-family boundaries into text
geometry, text content/style, and text operation/result files. Preserve every
class name, constructor, enum value, JSON/native conversion, equality rule, and
default. Export the split domain files from `pdf_editor.dart`; do not leave a
forwarding file at the former workspace path.

### 2.3 Verify

Run:

```powershell
dart format lib/src/features/pdf_editor test/pdf_editor
flutter test test/pdf_editor/domain_infrastructure
flutter test test/architecture/production_dart_file_size_test.dart test/architecture/flutter_feature_boundaries_test.dart
dart analyze lib/src/features/pdf_editor test/pdf_editor/domain_infrastructure
```

Delete the relevant allowlist paths once moved/split.

### 2.4 Commit

```powershell
git add lib/src/features/pdf_editor lib/src/features/workspace test/pdf_editor test/workspace_pdf test/architecture
git commit -m "refactor: extract PDF editor domain and infrastructure"
```

---

## Task 3: Extract PDF editor application and presentation

**Files:**

- Move: `lib/src/features/workspace/editing/application/*.dart` → `lib/src/features/pdf_editor/application/`
- Move: `lib/src/features/workspace/editing/infrastructure/*.dart` → `lib/src/features/pdf_editor/infrastructure/`
- Move: `lib/src/features/workspace/editing/presentation/*.dart` → `lib/src/features/pdf_editor/presentation/`
- Move: `lib/src/features/workspace/presentation/widgets/pdf_{native_text_input,object_transform_overlay,text_editor_overlay,text_format_panel}.dart` → `lib/src/features/pdf_editor/presentation/`
- Create: `lib/src/features/pdf_editor/application/pdf_editor_coordinator.dart`
- Split: `lib/src/features/pdf_editor/application/editor_session_controller.dart`
- Move tests: `test/workspace_editing/**` → `test/pdf_editor/application_presentation/**`

### 3.1 Add a narrow coordinator

The coordinator delegates and never owns Riverpod state:

```dart
class PdfEditorCoordinator {
  const PdfEditorCoordinator(this.registry);

  final EditorSessionRegistry registry;

  EditorSessionController? controllerFor(String tabId) =>
      registry.controller(tabId);
  AgentBridgeSession? agentBridgeFor(String tabId) =>
      registry.agentBridge(tabId);
  bool hasUnsavedEdits(String tabId) =>
      registry.controller(tabId)?.hasUnsavedEdits ?? false;
  Future<void> checkpointAll() => registry.checkpointAll();
  Future<void> close(String tabId) => registry.close(tabId);
}
```

Adapt member names to the existing controller's exact API; do not add parallel save state. Workspace continues to translate coordinator results into shell state.

### 3.2 Remove AI construction from the editor registry

Replace `_agentSessions: Map<String, AgentRunController>` with `_agentBridges: Map<String, AgentBridgeSession>`. During native session creation, obtain the bridge from `EditorAgentGateway.agentBridgeSession()`. Expose `agentBridge(String tabId)`. Close the bridge in the same lifecycle location that previously disposed the run controller. The registry must import core bridge contracts, never `features/ai`.

Add tests that prove one bridge per tab, bridge cleanup on close/dispose, and no `AgentRunController` reference in the registry source.

### 3.3 Split the controller by delegation

Keep `EditorSessionController` as the public façade and state stream owner. Extract:

- `editor_save_coordinator.dart`: save, save-copy, conflict, recovery, and rebase decisions;
- `editor_command_dispatcher.dart`: execute/undo/redo and command IDs;
- `editor_checkpoint_service.dart`: checkpoint scheduling and recovery probe calls.

Inject these helpers. Preserve ordering, controller state transitions, messages, and native calls exactly. No extracted file may receive a Riverpod `Ref`.

### 3.4 Verify and commit

```powershell
dart format lib/src/features/pdf_editor test/pdf_editor
flutter test test/pdf_editor
flutter test test/architecture
dart analyze lib/src/features/pdf_editor test/pdf_editor
git add lib/src/features/pdf_editor lib/src/features/workspace test/pdf_editor test/workspace_editing test/architecture
git commit -m "refactor: extract PDF editor application and UI"
```

---

## Task 4: Extract AI domain, persistence, and infrastructure

**Files:**

- Create: `lib/src/features/ai/ai.dart`
- Create: `lib/src/features/ai/domain/ai_feature_state.dart`
- Move: `lib/src/features/workspace/domain/{ai_provider,conversation}.dart` → `lib/src/features/ai/domain/`
- Extract AI models from: `lib/src/core/models.dart` → `lib/src/features/ai/domain/`
- Move: `lib/src/features/workspace/infrastructure/{conversation_store,document_chunk_store,local_rag_native_retriever,local_rag_service,local_rag_store,native_conversation_migrator,provider_profile_store}.dart` → `lib/src/features/ai/infrastructure/`
- Create: `lib/src/features/ai/infrastructure/ai_preferences_store.dart`
- Update: `lib/src/core/session_store.dart`
- Move AI-focused tests: `test/workspace_ai/**` → `test/ai/domain_infrastructure/**`

### 4.1 Define AI-owned state

Move, without JSON-key changes, `AiRuntimePhase`, `AiWorkspaceState`, `ComposerMessage`, `CitationSnippet`, retrieval chunks/records, provider models, and conversation models. Rename `AiWorkspaceState` to `AiFeatureState` only if all call sites and fixtures can be changed in the same task; retain `AiWorkspaceState` if renaming adds risk. The state must now include the existing provider-profile list previously stored on `WorkspaceFeatureState`.

Keep workspace models—`WorkspaceSession`, `DocumentTabState`, bookmarks, notes, highlights, outline, recent files—in core/workspace ownership. Split `core/models.dart` into cohesive files and leave a compatibility barrel only if it is the established core public entry point, not a forwarding path to feature internals.

### 4.2 Move AI preferences intact

`AiPreferencesStore` owns key `clarix.ai.state` and implements the old `readAiWorkspaceState`/`writeAiWorkspaceState` behavior. `ClarixSessionStore` retains only workspace session persistence. Provider profile store retains keys `clarix.ai.providers` and `clarix.ai.default_provider`, secure-key naming, defaults, and ordering.

Run the characterization test before deleting the old methods, update it to instantiate the new AI store, and require the exact same fixture maps after migration.

### 4.3 Verify and commit

```powershell
dart format lib/src/core lib/src/features/ai test/ai test/architecture
flutter test test/architecture/persistence_schema_compatibility_test.dart test/ai/domain_infrastructure
flutter test test/architecture
dart analyze lib/src/core/models.dart lib/src/core/session_store.dart lib/src/features/ai test/ai
git add lib/src/core lib/src/features/ai lib/src/features/workspace test/ai test/workspace_ai test/architecture
git commit -m "refactor: extract AI domain and persistence"
```

---

## Task 5: Extract AI application state and presentation

**Files:**

- Move: `lib/src/features/workspace/application/{action_permission_service,ai_runtime_service,conversation_context}.dart` → `lib/src/features/ai/application/`
- Move: `lib/src/features/workspace/agent/application/agent_run_controller.dart` → `lib/src/features/ai/application/`
- Create: `lib/src/features/ai/application/ai_notifier.dart`
- Create: `lib/src/features/ai/application/ai_providers.dart`
- Create: `lib/src/features/ai/application/ai_document_context.dart`
- Move: `lib/src/features/workspace/agent/presentation/*.dart` → `lib/src/features/ai/presentation/`
- Move: `lib/src/features/workspace/presentation/widgets/{ai_side_pane,inline_page_reference}.dart` → `lib/src/features/ai/presentation/`
- Update: `lib/src/features/workspace/application/workspace_notifier.dart`
- Update tests: `test/ai/**`

### 5.1 Add the document boundary object

```dart
class AiDocumentContext {
  const AiDocumentContext({
    required this.tabId,
    required this.documentId,
    required this.agentController,
  });

  final String tabId;
  final String documentId;
  final AgentRunController agentController;
}
```

If read-only path/page metadata is required by existing prompt context, add explicit immutable fields. Do not pass `WorkspaceFeatureState`, `WorkspaceNotifier`, or Riverpod `Ref`.

### 5.2 Move all AI commands to `AiNotifier`

Transfer initialization, provider CRUD/default selection, readiness, conversation CRUD/switching, prompt send/cancel, scope selection, citation/retrieval, and AI persistence from `WorkspaceNotifier`. Preserve public behavior and errors. `AiNotifier` is the sole writer of AI state and calls `AiPreferencesStore` after the same state transitions as before.

Add focused tests for restoration, provider changes, prompt success/failure/cancel, conversation switching, and persistence. Workspace tests should prove shell changes no longer rewrite AI preferences.

### 5.3 Move AI widgets

Widgets watch `aiNotifierProvider` and accept `AiDocumentContext?` or focused callbacks. They must not import workspace internals. Preserve layout and keys so existing widget tests need only import/provider updates.

### 5.4 Verify and commit

```powershell
dart format lib/src/features/ai lib/src/features/workspace test/ai
flutter test test/ai
flutter test test/architecture/persistence_schema_compatibility_test.dart test/architecture/flutter_feature_boundaries_test.dart
dart analyze lib/src/features/ai lib/src/features/workspace/application
git add lib/src/features/ai lib/src/features/workspace test/ai test/architecture
git commit -m "refactor: give AI independent state and UI"
```

---

## Task 6: Add the workspace composition boundary

**Files:**

- Create: `lib/src/features/workspace/application/workspace_feature_bindings.dart`
- Update: `lib/src/features/workspace/application/workspace_providers.dart`
- Update: `lib/src/features/workspace/domain/workspace_feature_state.dart`
- Update: `lib/src/features/workspace/presentation/screens/workspace_screen.dart`
- Update: `lib/src/features/workspace/presentation/widgets/workspace_{body,sidebar}.dart`
- Create/update: `test/workspace/workspace_feature_bindings_test.dart`

### 6.1 Make shell state shell-only

Remove AI state and provider profiles from `WorkspaceFeatureState`, including constructor parameters, `copyWith`, equality, and defaults. Keep only workspace session, active/open-document shell information, layout, recent files, document metadata view state, and shell-level busy/error state.

### 6.2 Wire cross-feature composition in one file

`workspace_feature_bindings.dart` may import public `ai.dart` and `pdf_editor.dart`. Define providers for:

- `PdfEditorCoordinator` from `EditorSessionRegistry`;
- `AgentRunController?` by active tab using `registry.agentBridge(tabId)`;
- `AiDocumentContext?` from active document identity and run controller;
- callbacks/results required to open documents produced by utilities.

Dispose AI controllers when their tab bridge is closed. Do not make PDF editor import AI to achieve this.

`workspace_providers.dart` retains core/workspace services and storage construction; feature-owned providers move to their feature provider file.

### 6.3 Verify and commit

```powershell
dart format lib/src/features/workspace test/workspace
flutter test test/workspace/workspace_feature_bindings_test.dart test/workspace_ai/workspace_shell_test.dart
flutter test test/architecture
dart analyze lib/src/features/workspace
git add lib/src/features/workspace test/workspace test/workspace_ai test/architecture
git commit -m "refactor: make workspace the feature composition root"
```

---

## Task 7: Reduce `WorkspaceNotifier` to a shell controller

**Files:**

- Create: `lib/src/features/workspace/application/workspace_document_service.dart`
- Create: `lib/src/features/workspace/application/workspace_session_service.dart`
- Create: `lib/src/features/workspace/application/document_metadata_service.dart`
- Update: `lib/src/features/workspace/application/workspace_notifier.dart`
- Create/update tests: `test/workspace/application/**`

### 7.1 Extract stateless orchestration services

`WorkspaceDocumentService` owns file picking/open preparation, identity resolution, missing-file relocation, and index orchestration. It returns records such as `PreparedWorkspaceDocument`; it never mutates notifier state.

`WorkspaceSessionService` owns restore/rehydrate/discard/persist coordination and returns `WorkspaceSession` or typed results.

`DocumentMetadataService` owns bookmark, note, highlight, outline, and metadata persistence transformations and returns updated immutable metadata/tab values.

Construct services through providers. Do not pass `Ref` into them.

### 7.2 Keep notifier responsibilities explicit

`WorkspaceNotifier` may contain `build`, open/close/activate tab, layout changes, recent files, shell error/busy transitions, and applying service results. It delegates all AI and editor mutations. Keep it below 800 lines without extensions or parts.

Add service unit tests and retain notifier tests for open/close, missing file, restore, metadata edits, editor dirty-close result handling, and error preservation.

### 7.3 Verify and commit

```powershell
dart format lib/src/features/workspace/application test/workspace/application
flutter test test/workspace/application
flutter test test/architecture/production_dart_file_size_test.dart
dart analyze lib/src/features/workspace/application test/workspace/application
git add lib/src/features/workspace/application test/workspace test/architecture
git commit -m "refactor: split workspace lifecycle services"
```

---

## Task 8: Extract reader and split the document surface

**Files:**

- Create: `lib/src/features/reader/reader.dart`
- Move: `lib/src/features/workspace/infrastructure/reader_search_service.dart` → `lib/src/features/reader/infrastructure/`
- Move: `lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart` → `lib/src/features/reader/application/`
- Move: `lib/src/features/workspace/presentation/widgets/reader_inspector.dart` → `lib/src/features/reader/presentation/`
- Replace: `lib/src/features/workspace/presentation/widgets/document_workspace.dart`
- Create: `lib/src/features/workspace/presentation/widgets/document_tab_strip.dart`
- Create: `lib/src/features/reader/presentation/pdf_viewer_pane.dart`
- Create: `lib/src/features/reader/application/pdf_viewer_interaction_controller.dart`
- Create: `lib/src/features/reader/presentation/pdf_viewer_overlays.dart`
- Create: `lib/src/features/reader/presentation/pdf_viewer_hud.dart`
- Move/update tests: reader/viewer tests → `test/reader/**`; composition tests → `test/workspace/presentation/**`

### 8.1 Split by state ownership, not textual chunks

`DocumentWorkspace` becomes a small composition widget accepting tab state and callbacks. `DocumentTabStrip` owns tab rendering only. `PdfViewerPane` owns reader widget lifecycle. `PdfViewerInteractionController` owns zoom mode, search state, selection/autopan calculations, and view-state changes that do not require a `BuildContext`. Overlay and HUD files contain focused widgets with explicit constructor inputs.

Do not use `part`, global keys as service locators, or extensions on the old private state. Preserve keys, gestures, scroll/zoom behavior, selection menus, search navigation, and persisted view callbacks.

### 8.2 Verify and commit

```powershell
dart format lib/src/features/reader lib/src/features/workspace/presentation test/reader test/workspace/presentation
flutter test test/reader test/workspace/presentation
flutter test test/architecture
dart analyze lib/src/features/reader lib/src/features/workspace/presentation
git add lib/src/features/reader lib/src/features/workspace test/reader test/workspace test/architecture
git commit -m "refactor: extract reader and split document workspace"
```

---

## Task 9: Extract settings and split its sections

**Files:**

- Create: `lib/src/features/settings/settings.dart`
- Move/replace: `lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart` → `lib/src/features/settings/presentation/app_settings_dialog.dart`
- Create: `lib/src/features/settings/presentation/appearance_settings.dart`
- Create: `lib/src/features/settings/presentation/ai_provider_settings.dart`
- Create: `lib/src/features/settings/presentation/editing_permission_settings.dart`
- Move/update tests: settings tests → `test/settings/**`

The dialog shell owns tabs/section navigation and close actions. Section widgets receive values and callbacks or consume only public feature providers. Settings may import `features/ai/ai.dart` and `features/pdf_editor/pdf_editor.dart`, never their internal folders. Preserve controls, labels, validation, secrets handling, and dialog dimensions.

Verify and commit:

```powershell
dart format lib/src/features/settings test/settings
flutter test test/settings
flutter test test/architecture
dart analyze lib/src/features/settings test/settings
git add lib/src/features/settings lib/src/features/workspace test/settings test/architecture
git commit -m "refactor: extract settings presentation"
```

---

## Task 10: Extract and split PDF utility presentation

**Files:**

- Create: `lib/src/features/utilities/utilities.dart`
- Move/replace: `lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart`
- Create: `lib/src/features/utilities/presentation/export_pdf_dialog.dart`
- Create: `lib/src/features/utilities/presentation/convert_to_pdf_dialog.dart`
- Create: `lib/src/features/utilities/presentation/combine_pdf_dialog.dart`
- Create: `lib/src/features/utilities/presentation/extract_pages_dialog.dart`
- Create if shared: `lib/src/features/utilities/presentation/pdf_utility_dialog_contracts.dart`
- Move/update: `test/pdf_utilities/**` → `test/utilities/**`

Each dialog calls the existing `PdfUtilityService` and returns the existing `UtilityResult`. Workspace receives a result through one callback and decides whether to open the output. Preserve picker behavior, validation, progress, cancellation, errors, and last-used values. Put a typedef/helper in the contracts file only when at least two dialogs use it.

Verify and commit:

```powershell
dart format lib/src/features/utilities test/utilities
flutter test test/utilities
flutter test test/architecture
dart analyze lib/src/features/utilities test/utilities
git add lib/src/features/utilities lib/src/features/workspace test/utilities test/pdf_utilities test/architecture
git commit -m "refactor: extract PDF utility dialogs"
```

---

## Task 11: Finish hand-written file splits and enforce public boundaries

**Files:**

- Split if still oversized: `lib/src/core/editing/editor_bridge.dart`
- Split if still oversized: `lib/src/core/models.dart`
- Update: all imports under `lib/` and `test/`
- Create/finalize: all six feature entry points
- Update: `test/architecture/*.dart`

### 11.1 Split remaining non-generated offenders

For `editor_bridge.dart`, keep the public bridge façade and extract command conversion, event decoding, and native session lifecycle into focused core editing helpers. Preserve the exact public API consumed by PDF editor/AI and all native call ordering.

For `core/models.dart`, retain core workspace/document models only and split serialization-heavy groups into `workspace_session.dart`, `document_metadata.dart`, and `document_view_state.dart`. Either make `models.dart` an intentional core barrel or update every consumer and delete it. It must not re-export AI models.

Run the size test repeatedly until it reports no allowlisted or unexpected files.

### 11.2 Finalize barrels

Each barrel exports only stable cross-feature contracts/providers/widgets. Internal feature files use relative imports. External feature consumers use the barrel. Delete old workspace files after consumers move; no forwarding export may remain.

Delete every item from `oversizedProductionDartAllowlist` and `temporaryFeatureBoundaryAllowlist`. Make architecture tests fail if either set is non-empty.

### 11.3 Update the Phase 3 gate paths

Update `tool/editing_phase3/run_phase3_checks.ps1` so moved PDF editor tests and paths are used. Keep the same substantive checks. Do not add a stress loop or release build.

### 11.4 Verify and commit

```powershell
dart format lib test/architecture tool/editing_phase3
flutter test test/architecture
dart analyze lib/src/features test/architecture
powershell -NoProfile -ExecutionPolicy Bypass -File tool/editing_phase3/run_phase3_checks.ps1
git add lib test tool/editing_phase3
git commit -m "refactor: enforce Flutter feature boundaries"
```

If the phase script would exceed 20 minutes, stop it, record the last completed stage, and run only its focused moved-path tests plus analyzer. Do not claim the full script passed.

---

## Task 12: Run and document the lightweight exit gate

**Files:**

- Create: `docs/architecture/flutter-feature-boundaries.md`
- Create/update: `docs/verification/flutter-feature-refactor-exit-gate.md`

### 12.1 Document the architecture in one screenful

Describe root features, ownership, allowed dependency arrows, `workspace_feature_bindings.dart`, AI document context, and the editor bridge handoff. Link to public entry points. Include the 800-line rule and generated FFI exemption.

### 12.2 Run the required gate

Run these independently so a slow/failing command does not hide earlier evidence:

```powershell
git branch --show-current
flutter test test/architecture
flutter test test/ai test/pdf_editor test/reader test/settings test/utilities test/workspace
dart analyze lib/src/features test/architecture test/ai test/pdf_editor test/reader test/settings test/utilities test/workspace
powershell -NoProfile -ExecutionPolicy Bypass -File tool/editing_phase3/run_phase3_checks.ps1
git diff --check
git status --short
```

Required results:

- branch is `main`;
- architecture tests pass with zero exceptions;
- all focused feature suites pass;
- analyzer has no errors or warnings in affected paths;
- updated lightweight Phase 3 gate passes, or its over-20-minute status is honestly recorded with equivalent focused checks;
- no hand-written `lib/**/*.dart` file exceeds 800 lines;
- `WorkspaceFeatureState` contains no AI state/provider profiles;
- `EditorSessionRegistry` contains no `AgentRunController` construction;
- workspace contains no AI/RAG/provider, PDF mutation/font, reader implementation, settings implementation, or utility workflow implementation;
- persistence fixtures pass unchanged;
- no deleted-path forwarding files or duplicated implementations remain.

Write exact commands, duration/result, and any explicitly deferred optional check into the exit-gate document. Do not paste huge logs.

### 12.3 Final review and commit

Inspect the diff for accidental UI/persistence/native changes, stale old directories, forbidden imports, and test skips. Then:

```powershell
git add docs/architecture/flutter-feature-boundaries.md docs/verification/flutter-feature-refactor-exit-gate.md
git commit -m "docs: record Flutter refactor exit gate"
git status --short
```

The goal is complete only when the required results above are satisfied and the worktree is clean. Optional stress, live-provider, full-golden, and release-build checks may be listed for the user but are not exit blockers.
