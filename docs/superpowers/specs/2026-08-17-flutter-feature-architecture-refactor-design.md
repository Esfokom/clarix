# Flutter Feature Architecture Refactor Design

**Date:** 2026-08-17

**Status:** Approved for implementation planning

## Purpose

Clarix's Flutter code currently places AI, native PDF editing, reader support, settings, and utility presentation beneath `features/workspace`. That layout makes the workspace appear to own capabilities that are independently testable and conceptually standalone. Two composition files have also grown beyond a practical review size: `workspace_notifier.dart` is approximately 1,680 lines and `document_workspace.dart` is approximately 2,248 lines.

This refactor will expose the real feature boundaries without redesigning behavior. The workspace becomes the application shell and composition root. AI, PDF editing, reader support, settings, and PDF utilities become root-level features. No production Dart file may exceed 800 lines after the migration.

## Goals

- Make the Flutter architecture explainable from root-level feature folders and one workspace composition file.
- Give AI independent state, persistence, runtime, infrastructure, and presentation ownership.
- Give native PDF editing a coherent clean-architecture folder.
- Keep workspace responsible for tabs, layout, active-document lifecycle, recent files, and feature composition.
- Split oversized production Dart files along existing responsibilities.
- Preserve visible UI behavior, persisted data, native calls, and command semantics.
- Preserve or improve focused test coverage while keeping verification practical on a slow machine.

## Non-Goals

- No Rust, FRB, SQLite, provider protocol, or native editing changes.
- No UI redesign, new feature, navigation redesign, or state-management framework change.
- No renaming campaign for established public concepts when their current names remain accurate.
- No repository-wide conversion to generated dependency injection or an event bus.
- No stress test, full golden-test suite, or live-provider qualification as part of the required gate.
- No splitting files below 800 lines unless a feature move or ownership boundary requires it.

## Target Feature Layout

```text
lib/src/features/
├── ai/
│   ├── ai.dart
│   ├── application/
│   ├── domain/
│   ├── infrastructure/
│   └── presentation/
├── pdf_editor/
│   ├── pdf_editor.dart
│   ├── application/
│   ├── domain/
│   ├── infrastructure/
│   └── presentation/
├── reader/
│   ├── reader.dart
│   ├── application/
│   ├── infrastructure/
│   └── presentation/
├── settings/
│   ├── settings.dart
│   └── presentation/
├── utilities/
│   ├── utilities.dart
│   ├── application/
│   ├── domain/
│   └── presentation/
├── workspace/
│   ├── workspace.dart
│   ├── application/
│   ├── domain/
│   └── presentation/
└── reader_diagnostics/
```

The existing `utilities` feature is retained and expanded with the PDF utility presentation currently owned by workspace.

## Feature Ownership

### AI

The AI feature owns:

- `AiFeatureState`, `AiRuntimePhase`, `ComposerMessage`, and `CitationSnippet`;
- provider profiles and provider secret/profile persistence;
- conversations, conversation persistence, context planning, and native migration;
- local RAG stores, retrieval, indexing adapters, and document chunks used for retrieval;
- `AiRuntimeService`, `AiNotifier`, and agent run control;
- selection AI actions, disclosure, approvals, diff overlays, the AI side pane, and inline citations;
- agent permission settings and their persistence.

AI may consume an active editor's `AgentBridgeSession`, but it may not mutate workspace state. The workspace composition layer supplies active-document identity and bridge access.

### PDF editor

The PDF editor feature owns:

- the existing `editing/application`, `editing/domain`, `editing/infrastructure`, and `editing/presentation` tree;
- PDF edit commands, intents, session state, text/layout types, page-object types, and native-edit projection types;
- PDF text engines and worker execution support;
- installed-font discovery and Windows font sources used for editing;
- editing overlays, text input, object transform UI, format panels, save/recovery dialogs, and page edit scenes;
- `EditorSessionController`, `EditorSessionRegistry`, and a `PdfEditorCoordinator` for save, save-copy, undo, redo, recovery, rebase, checkpoint, and dirty-state operations.

The PDF editor must not import AI or workspace. It exposes editor state and core `AgentBridgeSession` access through narrow public APIs.

### Reader

The reader feature owns read-only PDF concerns that are independently useful:

- reader search services and viewer interaction math;
- reader inspector presentation;
- reusable viewer controls and overlays extracted from the oversized document workspace;
- the PDF viewer pane where it can remain independent of workspace state.

Workspace owns the document tabs and composes the reader surface with optional PDF editor and AI controls. Reader does not directly mutate workspace state; callbacks or small context objects carry user actions upward.

### Settings

Settings owns only settings presentation and section composition. It consumes public providers or callbacks from core theme support, AI, and PDF editing. It does not own provider profiles, permission policies, fonts, or theme persistence.

### Utilities

The existing utilities feature owns utility jobs, services, and all PDF utility dialogs. Each large dialog becomes a focused file. Utilities return `UtilityResult` values; workspace decides whether to open resulting documents.

### Workspace

Workspace owns:

- `WorkspaceSession`, `DocumentTabState`, and workspace layout state;
- active tab, recent files, pane visibility and widths, and document lifecycle;
- workspace screen, body, tab strip, sidebar, and application chrome;
- document identity/metadata coordination that is specific to open workspace documents;
- the composition root connecting reader, PDF editor, AI, settings, and utilities.

Workspace must not contain implementations of provider calls, RAG, agent runs, PDF mutations, font matching, or utility workflows.

## Dependency Direction

Allowed dependencies are:

```text
core ← pdf_editor
core ← ai
core ← reader
core ← utilities
core ← settings

pdf_editor ← workspace composition
reader     ← workspace composition
ai         ← workspace composition
utilities  ← workspace composition
settings   ← workspace composition
```

Feature implementation folders do not import workspace. PDF editor does not import AI. AI does not import workspace. Settings may import stable public entry points from AI and PDF editor because it composes their settings UI, but it does not import their internal folders.

`workspace/application/workspace_feature_bindings.dart` is the only intended cross-feature construction point. It wires the editor registry, AI run controllers, active-document context, and feature providers.

## Public Feature Entry Points

Each feature exposes a deliberately small barrel:

- `features/ai/ai.dart`
- `features/pdf_editor/pdf_editor.dart`
- `features/reader/reader.dart`
- `features/settings/settings.dart`
- `features/utilities/utilities.dart`
- `features/workspace/workspace.dart`

External consumers import these files instead of reaching into another feature's internal folders. Entry points export stable domain types, controllers/providers, and top-level presentation widgets needed for composition. They do not export private infrastructure helpers.

Internal files use direct relative imports to keep ownership visible and avoid circular barrels.

## State Ownership and Interaction

### AI state

`AiNotifier` owns `AiFeatureState`, including provider profiles, selected provider, readiness, current messages, active conversation, generation activity, citations, and scope selection. Its public commands include provider management, conversation management, prompt execution, generation cancellation, and scope changes.

Prompt execution receives an `AiDocumentContext` containing only the active tab/document identifiers and the relevant `AgentRunController`. AI persists its state through an AI-owned store while retaining existing JSON keys and defaults.

### Workspace state

`WorkspaceNotifier` owns workspace shell state only. It delegates filesystem/import/index operations to focused services that return values rather than mutating notifier state directly. The notifier remains the single writer for `WorkspaceFeatureState`.

`WorkspaceFeatureState` no longer embeds `AiWorkspaceState` or provider profiles. AI widgets watch `aiNotifierProvider` independently.

### Editor state

`EditorSessionRegistry` remains the per-tab editor registry. It creates and closes native editor sessions, exposes editor document streams, and supplies an `AgentBridgeSession` for workspace composition. It no longer constructs an AI-owned `AgentRunController`.

### Composition flow

```text
WorkspaceScreen
  ├─ WorkspaceNotifier: tabs, layout, lifecycle
  ├─ Reader surface: rendering, search, read-only interactions
  ├─ PdfEditorCoordinator: edit/save/recovery commands
  └─ AiNotifier
       └─ AgentRunController
            └─ AgentBridgeSession supplied for the active editor tab
```

## Oversized File Decomposition

### Workspace notifier

`workspace_notifier.dart` will remain the public shell controller and fall below 800 lines. AI methods move to `AiNotifier`; editing operations move behind `PdfEditorCoordinator`. Remaining workspace work is supported by:

- `workspace_document_service.dart`: file picking, identity, open/close preparation, missing-file relocation, and indexing orchestration;
- `workspace_session_service.dart`: restore, rehydrate, discard, and persistence coordination;
- `document_metadata_service.dart`: bookmark, note, highlight, outline, and metadata persistence operations.

These services return immutable results or domain values. They do not receive a Riverpod `Ref` and do not mutate `WorkspaceFeatureState`.

### Document workspace

`document_workspace.dart` becomes composition only. Its contents split into:

- `document_tab_strip.dart`;
- `pdf_viewer_pane.dart`;
- `pdf_viewer_interactions.dart`;
- `pdf_viewer_overlays.dart`;
- `pdf_viewer_hud.dart`.

The split uses explicit widgets/controllers and constructor dependencies. It must not use Dart `part` files or giant extension blocks to disguise one class across files. Viewer interaction state that is not widget lifecycle state moves into a focused controller or notifier.

### Settings

`app_settings_dialog.dart` becomes a small settings shell with:

- `appearance_settings.dart`;
- `ai_provider_settings.dart`;
- `editing_permission_settings.dart`.

### PDF utility dialogs

`pdf_utilities_dialogs.dart` splits into:

- `export_pdf_dialog.dart`;
- `convert_to_pdf_dialog.dart`;
- `combine_pdf_dialog.dart`;
- `extract_pages_dialog.dart`.

Shared picker/callback typedefs move to `pdf_utility_dialog_contracts.dart` only when two or more dialogs consume them.

## File Size Rule

Every production Dart file under `lib/` must contain no more than 800 physical lines. Generated Dart under `lib/src/core/ffi/` is exempt because it is mechanically produced and must not be hand-split. A focused architecture test enumerates non-generated production Dart files and reports every violation with its line count.

The 800-line rule is a ceiling, not a target. A file below the ceiling remains intact unless ownership or cohesion requires movement.

## Migration Strategy

The migration proceeds in independently testable commits:

1. Add file-size and dependency-boundary tests while recording explicit temporary exceptions for current violations.
2. Move PDF editor code and its tests, then remove its temporary exceptions.
3. Move AI code, split AI state from workspace state, and preserve AI persistence JSON.
4. Add `workspace_feature_bindings.dart` and remove editor-to-AI construction.
5. Extract workspace document/session/metadata services and reduce `WorkspaceNotifier`.
6. Split `DocumentWorkspace` and move reader-owned pieces.
7. Split and move settings presentation.
8. Split and move PDF utility dialogs.
9. Add feature entry points, update external imports, remove forwarding exports, and enforce final dependency rules.
10. Run the lightweight architecture exit gate and document evidence.

Temporary forwarding exports are allowed only inside a task that also updates all consumers. No forwarding export or duplicate implementation may remain at the exit gate.

## Persistence Compatibility

- Workspace session JSON keys, defaults, and storage keys remain unchanged.
- AI preference JSON keys, defaults, and storage keys remain unchanged.
- Provider profile files and secure-storage key naming remain unchanged.
- Conversation database location, schema, migration markers, IDs, and ordering remain unchanged.
- Document metadata and chunk storage locations and schemas remain unchanged.

Before moving ownership, characterization tests capture representative serialized values. After migration, the same persisted fixtures must decode to equivalent domain state and re-encode without schema drift.

## Error Handling

Feature extraction must preserve existing user-visible error messages and recovery behavior. Services return existing typed failures or throw existing exceptions; presentation/notifiers remain responsible for translating them into current state and UI messages.

Moving code must not replace typed errors with generic strings, swallow failures, or add fallback execution paths. Native editor and agent failures continue through their established controller states.

## Testing Strategy

Required tests are focused and deterministic:

- architecture tests for file size, forbidden imports, feature entry points, and absence of forwarding exports;
- serialization characterization tests for workspace and AI persisted state;
- existing AI bridge/controller/migration/UI tests from their relocated paths;
- existing PDF editor domain/controller/widget tests from their relocated paths;
- focused workspace notifier and document workspace widget tests;
- focused settings and PDF utility dialog tests;
- `dart analyze` over `lib/src/features` and affected tests;
- existing lightweight Phase 3 gate after path updates.

Full stress tests, live-provider calls, and broad golden suites are optional and excluded from the required slow-machine gate.

## Exit Gate

The refactor is complete only when:

- every non-generated production Dart file is at most 800 lines;
- AI, PDF editor, reader, settings, and utilities exist as root-level features with public entry points;
- workspace contains no AI/provider/RAG/agent, PDF mutation/font, or utility implementation;
- PDF editor imports neither AI nor workspace;
- AI imports no workspace implementation;
- `WorkspaceFeatureState` has no embedded AI state or provider profiles;
- editor registry does not construct AI controllers;
- persisted fixtures prove schema compatibility;
- no temporary forwarding exports or duplicate implementations remain;
- focused feature tests, analyzer, architecture tests, and the updated lightweight Phase 3 gate pass;
- the worktree is clean on `main`.
