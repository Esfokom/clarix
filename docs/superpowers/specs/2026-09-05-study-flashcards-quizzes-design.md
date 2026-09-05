# Study: Flashcards and Quizzes — Design

Date: 2026-09-05
Status: Approved for planning

## Problem

A reader open in Clarix has no way to turn its content into practice
material. Users must leave the app to build flashcards or quizzes from a
document they are already reading.

## Goal

Add a Study pane to the right tool rail. From an open document the user
configures a run (item count, difficulty, optional focus topic), presses
Generate, and receives a structured, persisted set of flashcards or quiz
questions. Quizzes can be played fullscreen with per-question
explanations.

Generation is cloud-first. When the network fails, the user is offered an
on-device run against Gemma 4 E2B, with an explicit quality warning.

## Non-goals

- Spaced repetition, scheduling, or due-date review.
- Question types beyond four-option multiple choice.
- Sharing, export, or sync of study sets.
- Editing generated items by hand.
- Generating from anything but the active document.

## Constraints

Enforced by `test/architecture/`:

- Every feature exposes a barrel; `lib/src/features/study/study.dart`
  must exist and be registered in `_requiredEntryPoints`
  (`feature_entry_points_test.dart`) and `_publicFeatures`
  (`flutter_feature_boundaries_test.dart`).
- Cross-feature imports resolve through barrels only. The study feature
  imports `package:clarix/src/features/ai/ai.dart` and `core/`; nothing
  else. No new entries in `temporaryFeatureBoundaryAllowlist`.
- No hand-written production Dart file exceeds 800 lines. No new entries
  in `oversizedProductionDartAllowlist`.
- New persistence keys and schema versions are asserted in
  `persistence_schema_compatibility_test.dart`.

## Reused components

| Need | Existing component |
| --- | --- |
| Model invocation, remote + local | `AiRuntimeService.sendPrompt` |
| Remote target metadata | `AiProviderProfile.contextWindowTokens` |
| On-device target | `LocalModelRuntime`, `LocalModelProfile.gemma4E2b()` |
| Source text | `DocumentChunkStore.readChunks` |
| Salience ranking / focus search | `LocalRagService.retrieve` |
| Token estimation | `conversation_context.dart` estimator |
| Persistence pattern | `ConversationStore` (sqflite_ffi) |
| Pane hosting, resize, overlay | `workspace_body.dart`, `RightToolWindow` |
| Page navigation | `goToPage` in `reader_viewer_pane.dart` |
| Theming and widgets | `WorkspaceSurfaceTokens`, `shadcn_ui` |

## Architecture

New feature `lib/src/features/study/`, layered as `ai/` is:

```
study/
  study.dart                          barrel
  domain/
    study_models.dart
    study_schema.dart
  application/
    study_budget.dart
    study_source_planner.dart
    study_generation_harness.dart
    study_service.dart
    study_notifier.dart
    study_providers.dart
  infrastructure/
    study_store.dart
  presentation/
    study_side_pane.dart
    study_flashcard_view.dart
    quiz_player_screen.dart
    quiz_results_view.dart
```

### Domain

`domain/study_models.dart`:

- `Flashcard { id, front, back, pageNumber?, sectionTitle? }`
- `QuizQuestion { id, prompt, List<String> options, correctIndex,
  explanation, pageNumber?, difficulty }` — `options.length == 4`,
  `0 <= correctIndex < 4`, invariants enforced in the constructor.
- `StudySetKind { flashcards, quiz }`
- `StudyDifficulty { easy, medium, hard, mixed }`
- `StudyGenerationConfig { kind, itemCount, difficulty, focus }` —
  `itemCount` clamped to 5..40, `focus` nullable and trimmed.
- `StudySet { id, documentId, kind, title, createdAt, modelLabel,
  generatedOnDevice, isPartial, config, cards, questions }`
- `QuizAttempt { id, setId, startedAt, completedAt, answers,
  correctCount }` — `answers` is `Map<String questionId, int optionIndex>`.

All types are immutable, JSON round-trippable, and Flutter-free.

### JSON contract

`domain/study_schema.dart` owns both halves of the contract so the prompt
and the parser cannot drift:

- `studySchemaPrompt(kind)` — the schema description injected into the
  request, including a worked example item.
- `StudyJsonParser.parse(raw, kind)` returns
  `ParsedBatch { items, dropped, warnings }`.

Parsing is deliberately tolerant of model output shape and strict about
item content:

1. Strip Markdown code fences.
2. Scan for the first balanced `[` ... `]` region, so a prose preamble
   or trailing commentary does not fail the batch.
3. `jsonDecode`, then validate each element independently.
4. An element that fails validation (missing field, wrong option count,
   `correctIndex` out of range, empty prompt) is dropped and counted in
   `dropped`, never fatal.

A batch is a parse failure only when no balanced JSON region is found or
`jsonDecode` throws.

### Budgeting

`application/study_budget.dart`:

- `StudyBudget.forTarget({required StudyTarget target, required
  StudyGenerationConfig config})`.
- Remote targets take `AiProviderProfile.contextWindowTokens`. The local
  target uses `kLocalContextTokens`, a named constant for Gemma 4 E2B.
- Reserved completion tokens = `itemQuota * perItemCost`, where
  `perItemCost` is 90 for flashcards and 220 for quiz questions, clamped
  to a floor and to half the context window.
- Prompt budget = context window - reserved - fixed instruction overhead.
- Batch count = `ceil(totalSourceTokens / promptBudget)`, at least 1.
  Item quota per batch = `ceil(itemCount / batchCount)`, with the final
  batch trimmed so quotas sum to `itemCount`.

The private `_estimate` in `application/conversation_context.dart` is
lifted to a top-level `estimateTokens(String)` in that same file and
reused here. One estimator in the codebase, not two. Existing callers are
updated in place; behaviour is unchanged.

### Source selection

`application/study_source_planner.dart` produces
`StudyRunPlan { batches, totalItems, estimatedPromptTokens }` where each
`StudyBatch { pageRange, chunks, itemQuota }`.

Two modes:

- **Focus empty** — `DocumentChunkStore.readChunks(documentId)` sorted by
  page then chunk order. Guarantees whole-document coverage.
- **Focus set** — `LocalRagService.retrieve(documentId, focus, limit:
  itemCount * 4)`, then the returned chunks are sorted the same way. This
  inherits the native embedding retriever when the document is indexed
  and the lexical fallback when it is not; the study feature adds no
  retrieval code of its own.

Either source list is then partitioned by a greedy walk: accumulate
chunks in order until the next one would exceed the prompt budget, then
close the batch. This subsumes fixed page windows — no batch can exceed
budget by construction — and it keeps batch boundaries aligned to natural
page order. A single chunk larger than the whole budget forms its own
batch and has its text truncated to the budget at prompt-build time.

Item quotas are spread across batches: `itemCount ~/ batchCount` each,
with the remainder distributed to the earliest batches. When batches
outnumber requested items, batches are sampled down by even stride so the
selected batches still span the document.

A document with no chunks yields an empty plan; the pane reports that the
document is not indexed yet rather than calling a model.

### Generation harness

`application/study_generation_harness.dart` exposes
`Stream<StudyRunProgress> run({plan, target, config, cancelToken})`.

Per batch, sequentially:

1. Emit `StudyRunProgress.batchStarted(index, total)`.
2. Build the prompt: schema, difficulty instruction, item quota, and the
   batch's chunks with page and section labels.
3. Call `AiRuntimeService.sendPrompt`, accumulating tokens.
4. `StudyJsonParser.parse`. On parse failure, one repair retry that
   resends the raw output with an instruction to return only the JSON
   array. A second failure skips the batch and records a warning.
5. Dedupe accepted items against those already collected, comparing
   normalized front/prompt text (lowercased, punctuation and whitespace
   collapsed).
6. Emit `StudyRunProgress.batchCompleted(index, acceptedItems, warnings)`.

Batches run sequentially: the local runtime is single-threaded, and
sequential progress keeps the readout truthful.

Shortfall is reported, not concealed — a run that yields 18 of 20
requested items completes with a warning naming the failed batches. There
is no automatic top-up pass.

Cancellation uses the existing `CancelToken`. A cancelled run keeps the
items already accepted and marks the set partial.

### Target selection and local fallback

`application/study_service.dart` owns policy:

- The default target is the provider profile currently selected in AI
  preferences. If none is configured, the pane directs the user to
  settings and does not call a model.
- On `SocketException`, a timeout, or a non-2xx response, the run halts
  and the service emits `StudyFallbackOffer`, carrying the config so the
  same work can be re-run without re-deriving it.
- The pane renders the offer as a card: "No connection — generate
  on-device with Gemma 4? Quality is lower and it may not finish."
- Accepting re-plans the budget for the local target (its context window
  differs, so batch count changes), runs, and stamps
  `generatedOnDevice: true`. Declining leaves the run failed.
- `generatedOnDevice` is badged on the set in the pane and in the quiz
  player header.

Connectivity is inferred from request failure. No connectivity plugin is
added.

### Persistence

`infrastructure/study_store.dart`, sqflite_ffi, database
`clarix_study.sqlite`, following `ConversationStore`'s
`initialize()`/`onCreate`/`onUpgrade` structure.

Tables, schema version 1:

- `study_sets(id TEXT PRIMARY KEY, document_id TEXT NOT NULL, kind TEXT
  NOT NULL, title TEXT NOT NULL, created_at TEXT NOT NULL, model_label
  TEXT, generated_on_device INTEGER NOT NULL, config_json TEXT NOT NULL,
  is_partial INTEGER NOT NULL DEFAULT 0)`
- `flashcards(id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES
  study_sets(id) ON DELETE CASCADE, position INTEGER NOT NULL, front TEXT
  NOT NULL, back TEXT NOT NULL, page_number INTEGER, section_title TEXT)`
- `quiz_questions(id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES
  study_sets(id) ON DELETE CASCADE, position INTEGER NOT NULL, prompt
  TEXT NOT NULL, options_json TEXT NOT NULL, correct_index INTEGER NOT
  NULL, explanation TEXT NOT NULL, page_number INTEGER, difficulty TEXT
  NOT NULL)`
- `quiz_attempts(id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES
  study_sets(id) ON DELETE CASCADE, started_at TEXT NOT NULL,
  completed_at TEXT, answers_json TEXT NOT NULL, correct_count INTEGER
  NOT NULL)`

Indexes on `study_sets(document_id, created_at DESC)`,
`flashcards(set_id, position)`, `quiz_questions(set_id, position)`, and
`quiz_attempts(set_id, started_at DESC)`. `PRAGMA foreign_keys = ON` in
`onConfigure`.

Only the most recent attempt per set is surfaced; older attempts are
retained but unused by the UI.

### State

`application/study_notifier.dart` — `AsyncNotifier<StudyFeatureState>`.

`StudyFeatureState { Map<String documentId, List<StudySet>> setsByDocument,
StudyRunState? activeRun, StudyFallbackOffer? pendingOffer, String?
errorMessage }`.

`StudyRunState { kind, batchIndex, batchCount, itemsAccepted,
itemsRequested, warnings, cancelToken }`.

`application/study_providers.dart` mirrors `ai_providers.dart`: store
future provider, service provider, notifier provider.

## User interface

### Hosting

`RightToolWindow` in `core/models.dart` gains a `study` value. Session
deserialization already uses `_enumByNameOr` with a `none` fallback, so
sessions written by older builds load unchanged.

`workspace_body.dart` gains a third rail button
(`LucideIcons.graduationCap`, tooltip "Study") and routes
`RightToolWindow.study` to `StudySidePane`, reusing the existing pane
resizer, persisted width, and sub-1200px overlay behaviour. The
`_RightToolRail` and inline-pane branches are generalized from a pair of
booleans to a switch on the selected tool so a fourth tool costs nothing.

### Study pane

`presentation/study_side_pane.dart`:

- Header: segmented Flashcards | Quiz control, and a collapse button
  matching the AI pane.
- Options block, collapsed by default, expanding with `AnimatedSize`:
  item count slider (5–40), difficulty `ShadSelect`, focus text field
  with placeholder "Optional: a topic to concentrate on".
- Generate button, disabled while a run is active or the document has no
  chunks.
- Running state: determinate progress bar, "Batch 3 of 7", a live count
  of accepted items, and a Cancel button.
- Fallback offer card when `pendingOffer` is set.
- Results: saved sets newest first, each with kind icon, item count,
  relative timestamp, model label, an on-device badge when applicable, a
  partial badge when `isPartial`, and overflow actions (play/study,
  delete).

### Flashcards

`presentation/study_flashcard_view.dart` — a list of cards; tapping flips
via `AnimatedSwitcher` with a `Transform` rotateY, front to back. A page
chip navigates the reader through the existing `goToPage` path. Keyboard:
space flips, arrows move between cards when the list has focus.

### Quiz player

`presentation/quiz_player_screen.dart` — pushed as an opaque
`PageRouteBuilder` with a fade-and-scale transition.

- Top: linear progress, question index, set title, on-device badge when
  applicable.
- Question card, then four option tiles entering with a short stagger.
- Selecting an option locks the question, animates the chosen tile to
  correct or incorrect, reveals the correct tile when wrong, and slides
  the explanation in beneath.
- Next advances; the last question routes to results.
- Escape exits, confirming first if the attempt is incomplete.
- Responsive via `LayoutBuilder`: at or above 900px logical width the
  explanation occupies a second column beside the question; below that it
  is one scrolling column with width-constrained tiles. This is the
  Android-readiness hedge and costs nothing on Windows today.

`presentation/quiz_results_view.dart` — animated score ring, correct
count, and a per-question review list showing the user's answer, the
correct answer, and the explanation. Actions: retake, back to pane.

The attempt is written to `quiz_attempts` on completion and on early
exit.

## Error handling

| Condition | Behaviour |
| --- | --- |
| No provider configured | Pane points the user at settings; no model call |
| Document has no chunks | Pane reports the document is not indexed yet |
| Network failure | Run halts, local fallback offered |
| Batch parse failure after repair | Batch skipped, warning recorded, run continues |
| All batches fail | Run fails with the collected warnings; nothing persisted |
| Partial yield | Set persisted with `isPartial`, badged in the pane |
| Cancelled mid-run | Accepted items persisted as partial |
| Local model not installed | Fallback offer routes to the local model installer |

## Testing

Unit, in `test/study/`:

- Parser: fenced output, prose-wrapped output, trailing commentary,
  malformed JSON, wrong option count, out-of-range `correctIndex`, empty
  fields. Asserts drop counts and that partial batches survive.
- Budget: batch counts and quotas across context sizes; quotas sum to
  `itemCount`; local versus remote targets differ as expected.
- Source planner: focus-empty partitioning covers all chunks and no batch
  exceeds budget; focus-set path delegates to `LocalRagService.retrieve`;
  quotas sum to `itemCount`; batches are stride-sampled when they
  outnumber requested items.
- Harness: repair retry on first parse failure, skip on second, dedupe
  across batches, cancellation keeps accepted items.
- Store: round-trip of sets, cards, questions, attempts; cascade delete;
  key and schema-version assertions added to
  `persistence_schema_compatibility_test.dart`.

Widget:

- Pane: configure, generate, progress, result, against a fake runtime.
- Fallback offer appears on injected `SocketException` and re-runs
  against the local target on accept.
- Player: answer, explanation reveal, advance, score, and the two
  responsive layouts at 1200px and 700px widths.

Architecture: `study` added to `_requiredEntryPoints` and
`_publicFeatures`; no allowlist additions.
