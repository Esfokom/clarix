# TTS engine selection: faster on-device voices, Piper option, system TTS fallback

## Problem

The TTS feature ships exactly one voice pack: `kitten-nano-en-v0_1-fp16`
(sherpa-onnx's Kitten model, fp16 weights). On CPU-only devices this is too
slow — fp16 has no native CPU speedup and is typically upcast to fp32 for
compute, so real-time factor suffers. There's also no alternative voice or
fallback if a user doesn't want to download a voice pack at all.

## Goals

- Replace the shipped Kitten model with an int8-quantized variant for real
  CPU speedup.
- Add a second, lighter-weight voice option (Piper VITS voices via
  sherpa-onnx), selectable and downloadable from Settings like Kitten is
  today.
- Add a System TTS option (the OS's built-in voices via `flutter_tts`) as a
  no-download fallback, selectable from Settings, with the same
  segment-by-segment reading experience (sentence highlighting, click-to-skip,
  pause/resume) as the sherpa-onnx engines.

## Non-goals

- Non-English voices (catalog stays English-only for now).
- A remote/data-driven voice catalog — the catalog stays hardcoded in
  `tts_model_catalog.dart`, same pattern as today.
- Migrating or cleaning up files from the previously-shipped
  `kitten-nano-en-v0_1-fp16` install; those are simply orphaned on disk for
  users who had it installed. Not worth migration machinery pre-release.

## Design

### Engine abstraction

`TtsEngineKind` expands from a single value to:

```dart
enum TtsEngineKind { kittenSherpa, piperSherpa, system }
```

`kittenSherpa` and `piperSherpa` both run through the existing isolate-based
`TtsEngineWorker` (synthesize each segment to a WAV file, played back via
`AudioPlayer`); only the `sherpa.OfflineTtsModelConfig` branch built in
`TtsEngineWorker._entryPoint` differs (`kitten:` vs `vits:` config), selected
by `TtsModelSpec.engine`. `system` bypasses `TtsEngineWorker`/sherpa entirely
— no install, no on-disk model, no `TtsModelSpec`.

`TtsNotifier` no longer hardcodes `TtsModelCatalog.defaultModel`; it reads the
persisted active-engine selection (see Preferences below) to decide what to
use for `startReading`, `previewVoice`, etc.

Internally, `TtsNotifier` delegates the actual per-segment synthesis/playback
to one of two private engine adapters, both driving the same
`TtsPlaybackState` shape so the reader UI (`reader_read_aloud.dart`,
`reader_viewer_pane.dart`) needs no changes:

- `_SherpaReadAloudEngine` — today's logic (synthesis-ahead queue via
  `TtsEngineWorker`, sequential `AudioPlayer` playback of WAV files),
  extracted essentially as-is, parameterized by the active `TtsModelSpec`.
- `_SystemReadAloudEngine` — wraps a `FlutterTts` instance. For each segment,
  calls `speak(text)` and awaits completion via
  `setCompletionHandler`/`setErrorHandler`, updating `TtsPlaybackState` the
  same way the sherpa path does per segment (mirroring today's
  `onPlayerComplete` → `_advanceQueue` flow). No synthesis-ahead queue is
  needed since `flutter_tts` speaks directly.

### Model catalog

`TtsModelSpec` becomes engine-shaped:

- `voicesFileName` becomes nullable (Piper VITS packages have no separate
  speaker-embedding file; Kitten does).
- `voiceCount` is always `1` for Piper specs (single-speaker packages) vs `8`
  for Kitten.

Catalog (`tts_model_catalog.dart`):

```dart
static const TtsModelSpec kittenNano = TtsModelSpec(
  id: 'kitten-nano-en-v0_8-int8',
  engine: TtsEngineKind.kittenSherpa,
  label: 'Kitten (nano, int8)',
  downloadUrl: '$_releaseBase/kitten-nano-en-v0_8-int8.tar.bz2',
  modelFileName: 'model.int8.onnx',
  voicesFileName: 'voices.bin',
  tokensFileName: 'tokens.txt',
  dataDirName: 'espeak-ng-data', // confirm against real archive contents
  voiceCount: 8,
);

static const TtsModelSpec piperAmy = TtsModelSpec(
  id: 'vits-piper-en_US-amy-low-int8',
  engine: TtsEngineKind.piperSherpa,
  label: 'Piper — Amy (US)',
  downloadUrl: '$_releaseBase/vits-piper-en_US-amy-low-int8.tar.bz2',
  modelFileName: 'en_US-amy-low.onnx', // confirm
  voicesFileName: null,
  tokensFileName: 'tokens.txt',
  voiceCount: 1,
);

static const TtsModelSpec piperAlan = TtsModelSpec( /* en_GB, male, same shape */ );

static const List<TtsModelSpec> all = [kittenNano, piperAmy, piperAlan];
static const TtsModelSpec defaultModel = kittenNano;
```

Both the Kitten int8 archive and a Piper archive must be downloaded and
inspected during implementation to confirm exact in-tar filenames (data
gathered so far — sherpa-onnx's own build scripts — confirms
`model.int8.onnx` for Kitten v0.8 int8, but not whether `espeak-ng-data` is
still bundled; this must be verified against the real archive, not assumed).

Multiple specs can be installed at once (the existing `installState` map
already supports this per-id); the user separately picks which installed
spec is *active*.

### Preferences & state

`TtsPreferencesStore` gains:

- `activeEngine` (`TtsEngineKind`, stored as its enum name string).
- `activeModelId` (`String?`) — which installed `TtsModelSpec.id` is active,
  meaningful when `activeEngine != system`.
- `systemVoiceName` / `systemVoiceLocale` (`String?` each) — the chosen
  system voice, meaningful when `activeEngine == system`.
- `defaultVoiceSid` stays as today, meaningful only for `kittenSherpa` (Piper
  packages are single-voice: sid is always `0` and the voice grid is hidden
  for them in Settings).

`TtsFeatureState` gains `activeEngine`, `activeModelId`, `systemVoice`, and
`availableSystemVoices` (loaded once via `flutter_tts.getVoices()` when the
notifier builds).

### Settings UI

`TtsSettingsSection` restructures around an engine switch at the top:

- **Engine selector**: segmented control — "On-device" vs "System voice".
- **On-device**: one row per `TtsModelCatalog.all` entry (today's
  download/progress/installed row, repeated per spec), each selectable as
  active. The active *and* installed spec additionally shows the voice grid
  below it — only when `voiceCount > 1` (Kitten) — and the shared speed
  slider.
- **System voice**: a list built from `state.availableSystemVoices`
  (English-first), no download UI, plus the same speed slider (its value
  mapped internally to whatever range `setSpeechRate` expects on the current
  platform — determined empirically during implementation rather than
  assumed).
- Error messaging (`state.errorMessage`) stays as today.

### Dependencies

- Add `flutter_tts` to `pubspec.yaml`. It covers Android/iOS/Windows/macOS/
  Web, matching this app's current target platforms (android/ios/windows).

## Testing

- Unit-level: `TtsModelCatalog` entries resolve to valid specs;
  `TtsPreferencesStore` round-trips the new fields.
- `TtsNotifier` tests (mirroring existing patterns) for: switching active
  engine persists and is picked up by `startReading`/`previewVoice`; the
  system engine path advances segments and updates `TtsPlaybackState`
  equivalently to the sherpa path (fake/mock `FlutterTts`).
- Manual verification on at least one CPU-only Windows machine: Kitten int8
  vs the old fp16 for perceived latency; Piper voice as a lighter option;
  System voice as a no-download fallback.
