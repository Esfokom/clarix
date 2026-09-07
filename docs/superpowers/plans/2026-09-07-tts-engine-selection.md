# TTS Engine Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single fp16 Kitten voice pack with a faster int8 build, add a lightweight Piper voice pack as a second on-device option, and add a System TTS (OS voices via `flutter_tts`) fallback — all selectable and (where applicable) downloadable from Settings, with the same segment-by-segment reading experience (highlighting, click-to-skip, pause/resume) regardless of which engine is active.

**Architecture:** `TtsEngineKind` expands to `kittenSherpa` / `piperSherpa` / `system`. The two sherpa-onnx engines keep running through the existing isolate-based `TtsEngineWorker` (synthesize-to-WAV-file, queued `AudioPlayer` playback), now parameterized by the active `TtsModelSpec` instead of a single hardcoded one. System TTS is a separate, simpler code path inside `TtsNotifier` that drives a `SystemTtsClient` (a thin, mockable wrapper around `flutter_tts`) one segment at a time, updating the same `TtsPlaybackState` shape so the reader UI needs no changes. Active engine/model/voice selection is persisted and read on notifier startup.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifier`), `sherpa_onnx` ^1.13.7 (already a dependency), `flutter_tts` (new dependency), `shared_preferences`, `dio` + `archive` (existing download/extract path, unchanged).

**Spec:** `docs/superpowers/specs/2026-09-07-tts-engine-selection-design.md`

## Global Constraints

- English-only catalog for now (no non-English voices).
- Catalog stays hardcoded in `tts_model_catalog.dart` — no remote/data-driven catalog.
- No migration of the previously-shipped `kitten-nano-en-v0_1-fp16` install; leave any existing on-disk files for that id alone.
- New Kitten spec: id `kitten-nano-en-v0_8-int8`, archive `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_8-int8.tar.bz2` (31,220,690 bytes), in-archive files confirmed by direct inspection: `model.int8.onnx`, `voices.bin` (3,276,800 bytes = 8 voices × 409,600 bytes/voice), `tokens.txt`, `espeak-ng-data/`.
- New Piper specs: `vits-piper-en_US-amy-low-int8` (confirmed: `en_US-amy-low.onnx`, `tokens.txt`, `espeak-ng-data/`, no voices file, no lexicon needed) and `vits-piper-en_GB-alan-low-int8` (same package shape, by the catalog's consistent naming convention — confirm on download in Task 1).

---

## Task 1: Domain model — engine kinds and nullable voices file

**Files:**
- Modify: `lib/src/features/tts/domain/tts_models.dart:1-30`
- Test: `test/tts/tts_model_catalog_test.dart` (new)

**Interfaces:**
- Produces: `TtsEngineKind { kittenSherpa, piperSherpa, system }`; `TtsModelSpec` with `voicesFileName` now `String?`.

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_model_catalog_test.dart`:

```dart
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog has one Kitten (multi-voice) spec and two single-voice Piper specs', () {
    expect(TtsModelCatalog.all, hasLength(3));

    final TtsModelSpec kitten = TtsModelCatalog.byId('kitten-nano-en-v0_8-int8');
    expect(kitten.engine, TtsEngineKind.kittenSherpa);
    expect(kitten.voiceCount, 8);
    expect(kitten.voicesFileName, 'voices.bin');
    expect(kitten.modelFileName, 'model.int8.onnx');

    final TtsModelSpec amy = TtsModelCatalog.byId('vits-piper-en_US-amy-low-int8');
    expect(amy.engine, TtsEngineKind.piperSherpa);
    expect(amy.voiceCount, 1);
    expect(amy.voicesFileName, isNull);
    expect(amy.modelFileName, 'en_US-amy-low.onnx');

    final TtsModelSpec alan = TtsModelCatalog.byId('vits-piper-en_GB-alan-low-int8');
    expect(alan.engine, TtsEngineKind.piperSherpa);
    expect(alan.voiceCount, 1);

    expect(TtsModelCatalog.defaultModel.id, 'kitten-nano-en-v0_8-int8');
  });

  test('byId falls back to the default model for an unknown id', () {
    expect(TtsModelCatalog.byId('nonexistent').id, TtsModelCatalog.defaultModel.id);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_model_catalog_test.dart`
Expected: FAIL — `voicesFileName` is non-nullable and `kitten-nano-en-v0_8-int8` / the two Piper ids don't exist yet.

- [ ] **Step 3: Update the domain model**

In `lib/src/features/tts/domain/tts_models.dart`, replace lines 1-30:

```dart
enum TtsEngineKind { kittenSherpa, piperSherpa, system }

/// Describes a downloadable sherpa-onnx TTS voice pack. Not used for
/// [TtsEngineKind.system], which has no on-disk model.
class TtsModelSpec {
  const TtsModelSpec({
    required this.id,
    required this.engine,
    required this.label,
    required this.description,
    required this.downloadUrl,
    required this.approxArchiveSizeBytes,
    required this.modelFileName,
    this.voicesFileName,
    required this.tokensFileName,
    required this.dataDirName,
    required this.voiceCount,
  });

  final String id;
  final TtsEngineKind engine;
  final String label;
  final String description;
  final String downloadUrl;
  final int approxArchiveSizeBytes;
  final String modelFileName;

  /// Null for single-speaker packages (e.g. Piper), which have no separate
  /// speaker-embedding file. Set for Kitten, which packs multiple voices into
  /// one `voices.bin`.
  final String? voicesFileName;
  final String tokensFileName;
  final String dataDirName;
  final int voiceCount;
}
```

Leave the rest of the file (from `enum TtsInstallStatus` onward) unchanged.

- [ ] **Step 4: Update the catalog to match (minimal — full catalog content comes in Task 2)**

For now just make the file compile against the new shape. Open `lib/src/features/tts/infrastructure/tts_model_catalog.dart` and change line 12's `kitten` constant so `engine: TtsEngineKind.kitten` becomes `engine: TtsEngineKind.kittenSherpa` — leave everything else in that file as-is; Task 2 replaces the rest.

- [ ] **Step 5: Run test to verify it still fails on the missing ids (not a compile error)**

Run: `flutter test test/tts/tts_model_catalog_test.dart`
Expected: FAIL with `Bad state: No element` / expectation mismatches on `kitten-nano-en-v0_8-int8`, not analyzer errors. This confirms the domain model compiles; Task 2 makes the test pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/tts/domain/tts_models.dart lib/src/features/tts/infrastructure/tts_model_catalog.dart test/tts/tts_model_catalog_test.dart
git commit -m "refactor(tts): expand TtsEngineKind and allow nullable voices file"
```

---

## Task 2: Model catalog — int8 Kitten + two Piper voices

**Files:**
- Modify: `lib/src/features/tts/infrastructure/tts_model_catalog.dart` (full replace)
- Test: `test/tts/tts_model_catalog_test.dart` (from Task 1, now should pass)

**Interfaces:**
- Consumes: `TtsModelSpec`, `TtsEngineKind` from Task 1.
- Produces: `TtsModelCatalog.all`, `TtsModelCatalog.defaultModel`, `TtsModelCatalog.byId`.

- [ ] **Step 1: Confirm the second Piper archive's in-tar layout**

Run (from repo root, using a scratch directory so nothing is left in the working tree):

```bash
curl -sL -o /tmp/piper_alan.tar.bz2 "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alan-low-int8.tar.bz2"
tar -tjf /tmp/piper_alan.tar.bz2 | grep -v espeak-ng-data
rm /tmp/piper_alan.tar.bz2
```

Expected output includes `vits-piper-en_GB-alan-low-int8/en_GB-alan-low.onnx` and `vits-piper-en_GB-alan-low-int8/tokens.txt` (matching the Amy package's shape confirmed during design). If the model filename differs from `en_GB-alan-low.onnx`, use the actual name in Step 2.

- [ ] **Step 2: Replace the catalog**

Replace all of `lib/src/features/tts/infrastructure/tts_model_catalog.dart`:

```dart
import '../domain/tts_models.dart';

/// Voice packs known to the app, packaged by the sherpa-onnx project.
class TtsModelCatalog {
  const TtsModelCatalog._();

  static const String _releaseBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  /// ~31MB, 8 built-in voices, int8-quantized for real CPU speedup (fp16 has
  /// no native CPU kernel and gets upcast to fp32 for compute).
  static const TtsModelSpec kittenNano = TtsModelSpec(
    id: 'kitten-nano-en-v0_8-int8',
    engine: TtsEngineKind.kittenSherpa,
    label: 'Kitten (nano, int8)',
    description: 'Fast, on-device voice pack with 8 built-in voices.',
    downloadUrl: '$_releaseBase/kitten-nano-en-v0_8-int8.tar.bz2',
    approxArchiveSizeBytes: 31220690,
    modelFileName: 'model.int8.onnx',
    voicesFileName: 'voices.bin',
    tokensFileName: 'tokens.txt',
    dataDirName: 'espeak-ng-data',
    voiceCount: 8,
  );

  /// ~21MB single-speaker Piper voice — lighter than Kitten, one fixed voice.
  static const TtsModelSpec piperAmy = TtsModelSpec(
    id: 'vits-piper-en_US-amy-low-int8',
    engine: TtsEngineKind.piperSherpa,
    label: 'Piper — Amy (US)',
    description: 'Lightweight single-voice pack (US English, female).',
    downloadUrl: '$_releaseBase/vits-piper-en_US-amy-low-int8.tar.bz2',
    approxArchiveSizeBytes: 21099246,
    modelFileName: 'en_US-amy-low.onnx',
    tokensFileName: 'tokens.txt',
    dataDirName: 'espeak-ng-data',
    voiceCount: 1,
  );

  /// ~21MB single-speaker Piper voice (British English, male).
  static const TtsModelSpec piperAlan = TtsModelSpec(
    id: 'vits-piper-en_GB-alan-low-int8',
    engine: TtsEngineKind.piperSherpa,
    label: 'Piper — Alan (UK)',
    description: 'Lightweight single-voice pack (UK English, male).',
    downloadUrl: '$_releaseBase/vits-piper-en_GB-alan-low-int8.tar.bz2',
    approxArchiveSizeBytes: 21289969,
    modelFileName: 'en_GB-alan-low.onnx', // confirmed/corrected in Step 1
    tokensFileName: 'tokens.txt',
    dataDirName: 'espeak-ng-data',
    voiceCount: 1,
  );

  static const List<TtsModelSpec> all = <TtsModelSpec>[
    kittenNano,
    piperAmy,
    piperAlan,
  ];

  static const TtsModelSpec defaultModel = kittenNano;

  static TtsModelSpec byId(String id) =>
      all.firstWhere((TtsModelSpec spec) => spec.id == id, orElse: () => defaultModel);
}
```

- [ ] **Step 3: Run the catalog test from Task 1**

Run: `flutter test test/tts/tts_model_catalog_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/tts/infrastructure/tts_model_catalog.dart
git commit -m "feat(tts): replace fp16 Kitten with int8, add two Piper voice packs"
```

---

## Task 3: `TtsModelStore` — support specs with no voices file

**Files:**
- Modify: `lib/src/features/tts/infrastructure/tts_model_store.dart:39-58`
- Test: `test/tts/tts_model_store_test.dart` (new)

**Interfaces:**
- Consumes: `TtsModelSpec.voicesFileName` (now `String?`) from Task 1/2.
- Produces: `TtsInstalledModelPaths.voices` becomes `String?`; `TtsModelStore.isInstalled`/`paths` handle a null `voicesFileName`.

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_model_store_test.dart`:

```dart
import 'dart:io';

import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const TtsModelSpec _singleVoiceSpec = TtsModelSpec(
  id: 'fake-piper',
  engine: TtsEngineKind.piperSherpa,
  label: 'Fake Piper',
  description: '',
  downloadUrl: 'https://example.invalid/fake-piper.tar.bz2',
  approxArchiveSizeBytes: 0,
  modelFileName: 'model.onnx',
  tokensFileName: 'tokens.txt',
  dataDirName: 'espeak-ng-data',
  voiceCount: 1,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tts_model_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('isInstalled and paths work for a spec with no voices file', () async {
    final TtsModelStore store = TtsModelStore(
      directoryProvider: () async => tempDir,
    );

    expect(await store.isInstalled(_singleVoiceSpec), isFalse);

    final String installDir = p.join(tempDir.path, _singleVoiceSpec.id);
    await File(p.join(installDir, 'model.onnx')).create(recursive: true);
    await File(p.join(installDir, 'tokens.txt')).create(recursive: true);
    await Directory(p.join(installDir, 'espeak-ng-data')).create(recursive: true);

    expect(await store.isInstalled(_singleVoiceSpec), isTrue);

    final TtsInstalledModelPaths paths = await store.paths(_singleVoiceSpec);
    expect(paths.voices, isNull);
    expect(paths.model, p.join(installDir, 'model.onnx'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_model_store_test.dart`
Expected: FAIL — `isInstalled` currently requires a voices file to exist unconditionally, so it never reports installed; `TtsInstalledModelPaths.voices` is non-nullable.

- [ ] **Step 3: Update `TtsModelStore`**

In `lib/src/features/tts/infrastructure/tts_model_store.dart`, replace lines 39-58:

```dart
  Future<bool> isInstalled(TtsModelSpec spec) async {
    final String dir = await _installDir(spec);
    final bool model = await File(p.join(dir, spec.modelFileName)).exists();
    final bool voices = spec.voicesFileName == null
        ? true
        : await File(p.join(dir, spec.voicesFileName!)).exists();
    final bool tokens = await File(p.join(dir, spec.tokensFileName)).exists();
    final bool dataDir = await Directory(p.join(dir, spec.dataDirName)).exists();
    return model && voices && tokens && dataDir;
  }

  /// Absolute paths to the files sherpa-onnx expects for [spec]. Only valid
  /// once [isInstalled] returns true.
  Future<TtsInstalledModelPaths> paths(TtsModelSpec spec) async {
    final String dir = await _installDir(spec);
    return TtsInstalledModelPaths(
      model: p.join(dir, spec.modelFileName),
      voices: spec.voicesFileName == null ? null : p.join(dir, spec.voicesFileName!),
      tokens: p.join(dir, spec.tokensFileName),
      dataDir: p.join(dir, spec.dataDirName),
    );
  }
```

Then update the `TtsInstalledModelPaths` class at the bottom of the same file (was lines 106-118):

```dart
class TtsInstalledModelPaths {
  const TtsInstalledModelPaths({
    required this.model,
    this.voices,
    required this.tokens,
    required this.dataDir,
  });

  final String model;
  final String? voices;
  final String tokens;
  final String dataDir;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tts/tts_model_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/tts/infrastructure/tts_model_store.dart test/tts/tts_model_store_test.dart
git commit -m "feat(tts): TtsModelStore supports specs with no voices file"
```

---

## Task 4: `TtsEngineWorker` — build config per engine kind

**Files:**
- Modify: `lib/src/features/tts/infrastructure/tts_engine_worker.dart` (full replace)
- Test: `test/tts/tts_engine_worker_config_test.dart` (new)

**Interfaces:**
- Consumes: `TtsEngineKind`, `TtsInstalledModelPaths` (with nullable `voices`).
- Produces: `buildOfflineTtsModelConfig(TtsEngineKind engine, TtsInstalledModelPaths paths)` — a pure function, importable and unit-testable without spawning an isolate or touching native code. `TtsEngineWorker.start` now takes a required `engine` parameter.

This is the one file that talks to `sherpa_onnx`'s FFI bindings, which only work inside the isolate they're initialized in — so it can't be exercised end-to-end in a plain `flutter test`. The fix is to pull the pure config-building logic (no FFI, no isolate) out into its own testable function, and leave the isolate plumbing as thin glue around it.

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_engine_worker_config_test.dart`:

```dart
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_engine_worker.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main() {
  test('builds a kitten config for kittenSherpa with a voices path', () {
    final sherpa.OfflineTtsModelConfig config = buildOfflineTtsModelConfig(
      TtsEngineKind.kittenSherpa,
      const TtsInstalledModelPaths(
        model: '/m.onnx',
        voices: '/voices.bin',
        tokens: '/tokens.txt',
        dataDir: '/espeak',
      ),
    );
    expect(config.kitten.model, '/m.onnx');
    expect(config.kitten.voices, '/voices.bin');
    expect(config.kitten.tokens, '/tokens.txt');
    expect(config.kitten.dataDir, '/espeak');
    expect(config.vits.model, ''); // untouched default
  });

  test('builds a vits config for piperSherpa with no voices path', () {
    final sherpa.OfflineTtsModelConfig config = buildOfflineTtsModelConfig(
      TtsEngineKind.piperSherpa,
      const TtsInstalledModelPaths(
        model: '/m.onnx',
        tokens: '/tokens.txt',
        dataDir: '/espeak',
      ),
    );
    expect(config.vits.model, '/m.onnx');
    expect(config.vits.tokens, '/tokens.txt');
    expect(config.vits.dataDir, '/espeak');
    expect(config.vits.lexicon, '');
    expect(config.kitten.model, ''); // untouched default
  });

  test('throws for TtsEngineKind.system, which has no sherpa model', () {
    expect(
      () => buildOfflineTtsModelConfig(
        TtsEngineKind.system,
        const TtsInstalledModelPaths(model: '', tokens: '', dataDir: ''),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_engine_worker_config_test.dart`
Expected: FAIL — `buildOfflineTtsModelConfig` doesn't exist yet.

- [ ] **Step 3: Replace `tts_engine_worker.dart`**

Replace the whole file:

```dart
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/tts_models.dart';
import 'tts_model_store.dart';

/// Builds the sherpa-onnx model config for [engine] from [paths]. Pure and
/// isolate/FFI-free, so it's unit-testable directly; [TtsEngineWorker] calls
/// it from inside the worker isolate.
sherpa.OfflineTtsModelConfig buildOfflineTtsModelConfig(
  TtsEngineKind engine,
  TtsInstalledModelPaths paths,
) {
  switch (engine) {
    case TtsEngineKind.kittenSherpa:
      return sherpa.OfflineTtsModelConfig(
        kitten: sherpa.OfflineTtsKittenModelConfig(
          model: paths.model,
          voices: paths.voices ?? '',
          tokens: paths.tokens,
          dataDir: paths.dataDir,
        ),
        numThreads: 2,
        debug: false,
      );
    case TtsEngineKind.piperSherpa:
      return sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: paths.model,
          tokens: paths.tokens,
          dataDir: paths.dataDir,
        ),
        numThreads: 2,
        debug: false,
      );
    case TtsEngineKind.system:
      throw ArgumentError(
        'TtsEngineKind.system has no sherpa-onnx model config',
      );
  }
}

/// Hosts a sherpa-onnx [sherpa.OfflineTts] engine inside a dedicated isolate.
///
/// Synthesis is CPU-bound and would otherwise block the UI isolate; sherpa's
/// FFI bindings are per-isolate (each isolate must call `initBindings` and
/// own its native pointers), so the engine is created and used entirely
/// within the worker isolate. Only plain, isolate-safe values (Strings,
/// numbers, SendPorts) cross the boundary.
class TtsEngineWorker {
  TtsEngineWorker._(
    this._isolate,
    this._commandPort,
    this.sampleRate,
    this.numSpeakers,
  );

  final Isolate _isolate;
  final SendPort _commandPort;
  final int sampleRate;
  final int numSpeakers;
  bool _disposed = false;

  static Future<TtsEngineWorker> start({
    required TtsEngineKind engine,
    required TtsInstalledModelPaths paths,
  }) async {
    final ReceivePort readyPort = ReceivePort();
    final Isolate isolate = await Isolate.spawn(_entryPoint, <Object?>[
      readyPort.sendPort,
      engine.name,
      paths.model,
      paths.voices,
      paths.tokens,
      paths.dataDir,
    ]);
    final List<Object?> ready = await readyPort.first as List<Object?>;
    readyPort.close();
    if (ready[0] == 'error') {
      isolate.kill(priority: Isolate.immediate);
      throw StateError(ready[1]! as String);
    }
    return TtsEngineWorker._(
      isolate,
      ready[0]! as SendPort,
      ready[1]! as int,
      ready[2]! as int,
    );
  }

  Future<String> synthesizeToFile({
    required String text,
    required int sid,
    required double speed,
    required String outputPath,
  }) async {
    if (_disposed) {
      throw StateError('TTS engine worker has been disposed');
    }
    final ReceivePort replyPort = ReceivePort();
    _commandPort.send(<Object?>[
      'synthesize',
      replyPort.sendPort,
      text,
      sid,
      speed,
      outputPath,
    ]);
    final List<Object?> response = await replyPort.first as List<Object?>;
    replyPort.close();
    if (response[0] == 'error') {
      throw StateError(response[1]! as String);
    }
    return response[1]! as String;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _commandPort.send(const <Object?>['shutdown']);
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _entryPoint(List<Object?> args) {
    final SendPort readyPort = args[0]! as SendPort;
    final TtsEngineKind engine = TtsEngineKind.values.byName(args[1]! as String);
    final String model = args[2]! as String;
    final String? voices = args[3] as String?;
    final String tokens = args[4]! as String;
    final String dataDir = args[5]! as String;

    late final sherpa.OfflineTts tts;
    try {
      sherpa.initBindings();
      final sherpa.OfflineTtsModelConfig modelConfig = buildOfflineTtsModelConfig(
        engine,
        TtsInstalledModelPaths(
          model: model,
          voices: voices,
          tokens: tokens,
          dataDir: dataDir,
        ),
      );
      tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(model: modelConfig, maxNumSenetences: 1),
      );
    } catch (error) {
      readyPort.send(<Object?>['error', error.toString()]);
      return;
    }

    final ReceivePort commandPort = ReceivePort();
    readyPort.send(<Object?>[
      commandPort.sendPort,
      tts.sampleRate,
      tts.numSpeakers,
    ]);

    commandPort.listen((dynamic message) {
      final List<Object?> command = message as List<Object?>;
      if (command[0] == 'shutdown') {
        tts.free();
        commandPort.close();
        return;
      }

      final SendPort replyPort = command[1]! as SendPort;
      final String text = command[2]! as String;
      final int sid = command[3]! as int;
      final double speed = command[4]! as double;
      final String outputPath = command[5]! as String;
      try {
        final sherpa.GeneratedAudio audio = tts.generate(
          text: text,
          sid: sid,
          speed: speed,
        );
        final bool ok = sherpa.writeWave(
          filename: outputPath,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        if (!ok) {
          throw StateError('Failed to write synthesized audio to disk');
        }
        replyPort.send(<Object?>['ok', outputPath]);
      } catch (error) {
        replyPort.send(<Object?>['error', error.toString()]);
      }
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tts/tts_engine_worker_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/tts/infrastructure/tts_engine_worker.dart test/tts/tts_engine_worker_config_test.dart
git commit -m "refactor(tts): parameterize TtsEngineWorker by engine kind"
```

---

## Task 5: `TtsPreferencesStore` — persist engine/model/system-voice selection

**Files:**
- Modify: `lib/src/features/tts/infrastructure/tts_preferences_store.dart` (full replace)
- Test: `test/tts/tts_preferences_store_test.dart` (new)

**Interfaces:**
- Produces: `readActiveEngine()/saveActiveEngine(TtsEngineKind)`, `readActiveModelId()/saveActiveModelId(String?)`, `readSystemVoice()/saveSystemVoice(String? name, String? locale)`.

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_preferences_store_test.dart`:

```dart
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('defaults to kittenSherpa with no active model or system voice', () async {
    final TtsPreferencesStore store = TtsPreferencesStore(SharedPreferencesAsync());
    expect(await store.readActiveEngine(), TtsEngineKind.kittenSherpa);
    expect(await store.readActiveModelId(), isNull);
    expect(await store.readSystemVoiceName(), isNull);
    expect(await store.readSystemVoiceLocale(), isNull);
  });

  test('round-trips engine, model id, and system voice', () async {
    final TtsPreferencesStore store = TtsPreferencesStore(SharedPreferencesAsync());

    await store.saveActiveEngine(TtsEngineKind.system);
    expect(await store.readActiveEngine(), TtsEngineKind.system);

    await store.saveActiveModelId('vits-piper-en_US-amy-low-int8');
    expect(await store.readActiveModelId(), 'vits-piper-en_US-amy-low-int8');

    await store.saveSystemVoice(name: 'Karen', locale: 'en-AU');
    expect(await store.readSystemVoiceName(), 'Karen');
    expect(await store.readSystemVoiceLocale(), 'en-AU');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_preferences_store_test.dart`
Expected: FAIL — the new methods don't exist.

- [ ] **Step 3: Replace `tts_preferences_store.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tts_models.dart';

/// Persists the user's TTS engine/model/voice selection and speed, configured
/// from Settings and applied to every reading session.
class TtsPreferencesStore {
  TtsPreferencesStore(this._preferences);

  static const String _voiceIdKey = 'clarix.tts.default_voice_sid';
  static const String _speedKey = 'clarix.tts.default_speed';
  static const String _activeEngineKey = 'clarix.tts.active_engine';
  static const String _activeModelIdKey = 'clarix.tts.active_model_id';
  static const String _systemVoiceNameKey = 'clarix.tts.system_voice_name';
  static const String _systemVoiceLocaleKey = 'clarix.tts.system_voice_locale';

  final SharedPreferencesAsync _preferences;

  Future<int> readDefaultVoice() async =>
      await _preferences.getInt(_voiceIdKey) ?? 0;

  Future<void> saveDefaultVoice(int sid) =>
      _preferences.setInt(_voiceIdKey, sid);

  Future<double> readSpeed() async =>
      await _preferences.getDouble(_speedKey) ?? 1.0;

  Future<void> saveSpeed(double speed) =>
      _preferences.setDouble(_speedKey, speed);

  Future<TtsEngineKind> readActiveEngine() async {
    final String? name = await _preferences.getString(_activeEngineKey);
    if (name == null) return TtsEngineKind.kittenSherpa;
    return TtsEngineKind.values.byName(name);
  }

  Future<void> saveActiveEngine(TtsEngineKind engine) =>
      _preferences.setString(_activeEngineKey, engine.name);

  Future<String?> readActiveModelId() =>
      _preferences.getString(_activeModelIdKey);

  Future<void> saveActiveModelId(String? id) => id == null
      ? _preferences.remove(_activeModelIdKey)
      : _preferences.setString(_activeModelIdKey, id);

  Future<String?> readSystemVoiceName() =>
      _preferences.getString(_systemVoiceNameKey);

  Future<String?> readSystemVoiceLocale() =>
      _preferences.getString(_systemVoiceLocaleKey);

  Future<void> saveSystemVoice({required String? name, required String? locale}) async {
    if (name == null || locale == null) {
      await _preferences.remove(_systemVoiceNameKey);
      await _preferences.remove(_systemVoiceLocaleKey);
      return;
    }
    await _preferences.setString(_systemVoiceNameKey, name);
    await _preferences.setString(_systemVoiceLocaleKey, locale);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tts/tts_preferences_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/tts/infrastructure/tts_preferences_store.dart test/tts/tts_preferences_store_test.dart
git commit -m "feat(tts): persist active engine, model id, and system voice"
```

---

## Task 6: `SystemTtsClient` — mockable wrapper around `flutter_tts`

**Files:**
- Create: `lib/src/features/tts/infrastructure/system_tts_client.dart`
- Modify: `pubspec.yaml` (add `flutter_tts` dependency)
- Test: `test/tts/system_tts_client_test.dart` (new — tests only the pure voice-parsing logic, not the platform channel)

**Interfaces:**
- Produces: `SystemTtsVoice { name, locale }`, `parseSystemTtsVoices(dynamic raw) -> List<SystemTtsVoice>`, `abstract class SystemTtsClient` with `getVoices()`, `setVoice(SystemTtsVoice)`, `setSpeechRate(double)`, `speak(String)`, `stop()`, `pause()`, `onComplete(void Function())`, `onError(void Function(Object))`, `dispose()`; concrete `FlutterTtsClient implements SystemTtsClient`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add next to the existing `sherpa_onnx: ^1.13.7` line (check pub.dev for the current stable version and use it in place of `^4.2.2` if newer):

```yaml
  flutter_tts: ^4.2.2
```

Run: `flutter pub get`

- [ ] **Step 2: Write the failing test**

Create `test/tts/system_tts_client_test.dart`:

```dart
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses name/locale pairs and skips malformed entries', () {
    final List<SystemTtsVoice> voices = parseSystemTtsVoices(<dynamic>[
      <String, String>{'name': 'Karen', 'locale': 'en-AU'},
      <String, String>{'name': 'Daniel', 'locale': 'en-GB'},
      <String, String>{'name': 'NoLocale'},
      'not a map',
    ]);

    expect(voices, hasLength(2));
    expect(voices[0].name, 'Karen');
    expect(voices[0].locale, 'en-AU');
    expect(voices[1].name, 'Daniel');
  });

  test('returns an empty list for non-list input', () {
    expect(parseSystemTtsVoices('unexpected'), isEmpty);
    expect(parseSystemTtsVoices(null), isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/tts/system_tts_client_test.dart`
Expected: FAIL — the file doesn't exist yet.

- [ ] **Step 4: Create `system_tts_client.dart`**

```dart
import 'package:flutter_tts/flutter_tts.dart';

/// One voice reported by the platform's TTS engine.
class SystemTtsVoice {
  const SystemTtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is SystemTtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Parses the raw, platform-shaped value returned by `FlutterTts.getVoices`
/// (a `List` of `Map`s with at least `name`/`locale` keys on Android/iOS/
/// Windows/macOS) into [SystemTtsVoice]s, skipping anything malformed.
List<SystemTtsVoice> parseSystemTtsVoices(dynamic raw) {
  if (raw is! List) return const <SystemTtsVoice>[];
  final List<SystemTtsVoice> voices = <SystemTtsVoice>[];
  for (final dynamic entry in raw) {
    if (entry is! Map) continue;
    final Object? name = entry['name'];
    final Object? locale = entry['locale'];
    if (name is String && locale is String) {
      voices.add(SystemTtsVoice(name: name, locale: locale));
    }
  }
  return voices;
}

/// Mockable wrapper around [FlutterTts] used by the system-voice read-aloud
/// path, so tests can substitute a fake without a platform channel.
abstract class SystemTtsClient {
  Future<List<SystemTtsVoice>> getVoices();
  Future<void> setVoice(SystemTtsVoice voice);

  /// Best-effort rate, 0.0-1.0 per flutter_tts's own normalization.
  Future<void> setSpeechRate(double rate);
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();
  void onComplete(void Function() callback);
  void onError(void Function(Object error) callback);
  Future<void> dispose();
}

class FlutterTtsClient implements SystemTtsClient {
  FlutterTtsClient() : _tts = FlutterTts() {
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts;

  @override
  Future<List<SystemTtsVoice>> getVoices() async =>
      parseSystemTtsVoices(await _tts.getVoices);

  @override
  Future<void> setVoice(SystemTtsVoice voice) => _tts.setVoice(<String, String>{
    'name': voice.name,
    'locale': voice.locale,
  });

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> pause() => _tts.pause();

  @override
  void onComplete(void Function() callback) => _tts.setCompletionHandler(callback);

  @override
  void onError(void Function(Object error) callback) =>
      _tts.setErrorHandler((dynamic error) => callback(error as Object));

  @override
  Future<void> dispose() => _tts.stop();
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/tts/system_tts_client_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/features/tts/infrastructure/system_tts_client.dart test/tts/system_tts_client_test.dart
git commit -m "feat(tts): add flutter_tts dependency and SystemTtsClient wrapper"
```

---

## Task 7: `TtsFeatureState` and `tts_providers.dart` — new fields and provider

**Files:**
- Modify: `lib/src/features/tts/application/tts_feature_state.dart` (full replace)
- Modify: `lib/src/features/tts/application/tts_providers.dart` (full replace)
- Test: `test/tts/tts_feature_state_test.dart` (new)

**Interfaces:**
- Consumes: `TtsEngineKind` (Task 1), `SystemTtsVoice`/`SystemTtsClient` (Task 6).
- Produces: `TtsFeatureState.activeEngine`, `.activeModelId`, `.systemVoice`, `.availableSystemVoices`; `systemTtsClientProvider`.

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_feature_state_test.dart`:

```dart
import 'package:clarix/src/features/tts/application/tts_feature_state.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial state defaults to kittenSherpa with no model or voice selected', () {
    final TtsFeatureState state = TtsFeatureState.initial();
    expect(state.activeEngine, TtsEngineKind.kittenSherpa);
    expect(state.activeModelId, isNull);
    expect(state.systemVoice, isNull);
    expect(state.availableSystemVoices, isEmpty);
  });

  test('copyWith updates the new fields independently', () {
    final TtsFeatureState state = TtsFeatureState.initial().copyWith(
      activeEngine: TtsEngineKind.system,
      activeModelId: 'vits-piper-en_US-amy-low-int8',
      systemVoice: const SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
      availableSystemVoices: const <SystemTtsVoice>[
        SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
      ],
    );
    expect(state.activeEngine, TtsEngineKind.system);
    expect(state.activeModelId, 'vits-piper-en_US-amy-low-int8');
    expect(state.systemVoice, const SystemTtsVoice(name: 'Karen', locale: 'en-AU'));
    expect(state.availableSystemVoices, hasLength(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_feature_state_test.dart`
Expected: FAIL — the new fields don't exist.

- [ ] **Step 3: Replace `tts_feature_state.dart`**

```dart
import '../domain/tts_models.dart';
import '../infrastructure/system_tts_client.dart';

class TtsFeatureState {
  const TtsFeatureState({
    required this.installState,
    required this.defaultVoiceSid,
    required this.defaultSpeed,
    required this.playback,
    required this.activeEngine,
    this.activeModelId,
    this.systemVoice,
    this.availableSystemVoices = const <SystemTtsVoice>[],
    this.errorMessage,
  });

  factory TtsFeatureState.initial() => const TtsFeatureState(
    installState: <String, TtsModelInstallState>{},
    defaultVoiceSid: 0,
    defaultSpeed: 1,
    playback: TtsPlaybackState(),
    activeEngine: TtsEngineKind.kittenSherpa,
  );

  final Map<String, TtsModelInstallState> installState;
  final int defaultVoiceSid;
  final double defaultSpeed;
  final TtsPlaybackState playback;

  /// Which engine is currently selected in Settings.
  final TtsEngineKind activeEngine;

  /// Which [TtsModelCatalog] spec is active, when [activeEngine] is one of
  /// the sherpa-onnx engines. Null when no sherpa spec has been chosen yet
  /// (falls back to [TtsModelCatalog.defaultModel]) or when using system TTS.
  final String? activeModelId;

  /// The chosen OS voice, when [activeEngine] is [TtsEngineKind.system].
  final SystemTtsVoice? systemVoice;

  /// Voices reported by the platform's TTS engine, loaded once on startup.
  final List<SystemTtsVoice> availableSystemVoices;

  final String? errorMessage;

  TtsFeatureState copyWith({
    Map<String, TtsModelInstallState>? installState,
    int? defaultVoiceSid,
    double? defaultSpeed,
    TtsPlaybackState? playback,
    TtsEngineKind? activeEngine,
    String? activeModelId,
    bool clearActiveModelId = false,
    SystemTtsVoice? systemVoice,
    bool clearSystemVoice = false,
    List<SystemTtsVoice>? availableSystemVoices,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsFeatureState(
    installState: installState ?? this.installState,
    defaultVoiceSid: defaultVoiceSid ?? this.defaultVoiceSid,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
    playback: playback ?? this.playback,
    activeEngine: activeEngine ?? this.activeEngine,
    activeModelId: clearActiveModelId ? null : (activeModelId ?? this.activeModelId),
    systemVoice: clearSystemVoice ? null : (systemVoice ?? this.systemVoice),
    availableSystemVoices: availableSystemVoices ?? this.availableSystemVoices,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}
```

- [ ] **Step 4: Replace `tts_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/system_tts_client.dart';
import '../infrastructure/tts_model_store.dart';
import '../infrastructure/tts_preferences_store.dart';
import 'tts_feature_state.dart';
import 'tts_notifier.dart';

final ttsModelStoreProvider = Provider<TtsModelStore>((Ref ref) => TtsModelStore());

final ttsSharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

final ttsPreferencesStoreProvider = Provider<TtsPreferencesStore>(
  (Ref ref) => TtsPreferencesStore(ref.watch(ttsSharedPreferencesProvider)),
);

final systemTtsClientProvider = Provider<SystemTtsClient>(
  (Ref ref) => FlutterTtsClient(),
);

final ttsNotifierProvider =
    AsyncNotifierProvider<TtsNotifier, TtsFeatureState>(TtsNotifier.new);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/tts/tts_feature_state_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/tts/application/tts_feature_state.dart lib/src/features/tts/application/tts_providers.dart test/tts/tts_feature_state_test.dart
git commit -m "feat(tts): add engine/model/system-voice fields to TtsFeatureState"
```

---

## Task 8: `TtsNotifier` — engine-aware model selection

**Files:**
- Modify: `lib/src/features/tts/application/tts_notifier.dart`
- Test: `test/tts/tts_notifier_engine_selection_test.dart` (new)

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: `TtsNotifier.setActiveEngine(TtsEngineKind)`, `.setActiveModel(TtsModelSpec)`, `.setSystemVoice(SystemTtsVoice)`; `activeSpec` getter resolving the effective `TtsModelSpec` for sherpa engines; `downloadModel`/`deleteModel`/`previewVoice`/`startReading` now use the active spec instead of `TtsModelCatalog.defaultModel`.

This task covers engine/model *selection* only — the system engine's actual reading-session loop is Task 9. Selecting `system` here just changes `state.activeEngine`; `startReading` still only knows how to run the sherpa path (Task 9 adds the branch).

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_notifier_engine_selection_test.dart`:

```dart
import 'dart:io';

import 'package:clarix/src/features/tts/application/tts_providers.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_catalog.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeSystemTtsClient implements SystemTtsClient {
  @override
  Future<List<SystemTtsVoice>> getVoices() async => const <SystemTtsVoice>[
    SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
  ];
  @override
  Future<void> setVoice(SystemTtsVoice voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void onComplete(void Function() callback) {}
  @override
  void onError(void Function(Object error) callback) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('build() loads system voices and defaults to the catalog default model', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_notifier_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(ttsNotifierProvider.future);
    expect(state.activeEngine, TtsEngineKind.kittenSherpa);
    expect(state.activeModelId, isNull);
    expect(state.availableSystemVoices, hasLength(1));
    expect(state.availableSystemVoices.single.name, 'Karen');
  });

  test('setActiveModel persists selection and is reflected in state', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_notifier_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ttsNotifierProvider.future);

    await container.read(ttsNotifierProvider.notifier).setActiveModel(
      TtsModelCatalog.piperAmy,
    );

    final state = container.read(ttsNotifierProvider).requireValue;
    expect(state.activeModelId, TtsModelCatalog.piperAmy.id);

    final SharedPreferencesAsync prefs = SharedPreferencesAsync();
    expect(
      await prefs.getString('clarix.tts.active_model_id'),
      TtsModelCatalog.piperAmy.id,
    );
  });

  test('setActiveEngine to system persists and is reflected in state', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_notifier_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ttsNotifierProvider.future);

    await container.read(ttsNotifierProvider.notifier).setActiveEngine(
      TtsEngineKind.system,
    );

    expect(
      container.read(ttsNotifierProvider).requireValue.activeEngine,
      TtsEngineKind.system,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_notifier_engine_selection_test.dart`
Expected: FAIL — `setActiveModel`/`setActiveEngine` don't exist, `build()` doesn't load system voices.

- [ ] **Step 3: Update `TtsNotifier`**

In `lib/src/features/tts/application/tts_notifier.dart`:

1. Update imports — add:

```dart
import '../infrastructure/system_tts_client.dart';
```

2. Replace the `build()` method (lines 42-71) with:

```dart
  @override
  Future<TtsFeatureState> build() async {
    ref.onDispose(() {
      _generation++;
      _player?.dispose();
      _engine?.dispose();
    });

    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    final TtsPreferencesStore preferences = ref.read(
      ttsPreferencesStoreProvider,
    );
    final Map<String, TtsModelInstallState> installState =
        <String, TtsModelInstallState>{};
    for (final TtsModelSpec spec in TtsModelCatalog.all) {
      final bool installed = await store.isInstalled(spec);
      installState[spec.id] = TtsModelInstallState(
        status: installed
            ? TtsInstallStatus.installed
            : TtsInstallStatus.notInstalled,
      );
    }
    final int defaultVoiceSid = await preferences.readDefaultVoice();
    final double defaultSpeed = await preferences.readSpeed();
    final TtsEngineKind activeEngine = await preferences.readActiveEngine();
    final String? activeModelId = await preferences.readActiveModelId();
    final String? systemVoiceName = await preferences.readSystemVoiceName();
    final String? systemVoiceLocale = await preferences.readSystemVoiceLocale();

    List<SystemTtsVoice> availableSystemVoices = const <SystemTtsVoice>[];
    try {
      availableSystemVoices =
          await ref.read(systemTtsClientProvider).getVoices();
    } catch (_) {
      // Platform voice enumeration failed (e.g. unsupported platform); the
      // System voice option will simply show no voices to pick from.
    }

    return TtsFeatureState.initial().copyWith(
      installState: installState,
      defaultVoiceSid: defaultVoiceSid,
      defaultSpeed: defaultSpeed,
      activeEngine: activeEngine,
      activeModelId: activeModelId,
      systemVoice: systemVoiceName != null && systemVoiceLocale != null
          ? SystemTtsVoice(name: systemVoiceName, locale: systemVoiceLocale)
          : null,
      availableSystemVoices: availableSystemVoices,
    );
  }

  TtsFeatureState get _current => state.value ?? TtsFeatureState.initial();

  void _commit(TtsFeatureState value) => state = AsyncData<TtsFeatureState>(value);

  bool get isReading => _current.playback.status != TtsPlaybackStatus.idle;

  /// The sherpa-onnx spec to use for the active selection, resolving to the
  /// catalog default when none has been explicitly chosen. Meaningless when
  /// [TtsFeatureState.activeEngine] is [TtsEngineKind.system].
  TtsModelSpec get activeSpec {
    final String? id = _current.activeModelId;
    return id == null ? TtsModelCatalog.defaultModel : TtsModelCatalog.byId(id);
  }
```

3. Add these methods in the "Preferences" section, right after `setDefaultSpeed` (originally lines 138-141):

```dart
  Future<void> setActiveEngine(TtsEngineKind engine) async {
    await ref.read(ttsPreferencesStoreProvider).saveActiveEngine(engine);
    _commit(_current.copyWith(activeEngine: engine));
  }

  Future<void> setActiveModel(TtsModelSpec spec) async {
    await ref.read(ttsPreferencesStoreProvider).saveActiveModelId(spec.id);
    _commit(_current.copyWith(activeModelId: spec.id));
  }

  Future<void> setSystemVoice(SystemTtsVoice voice) async {
    await ref
        .read(ttsPreferencesStoreProvider)
        .saveSystemVoice(name: voice.name, locale: voice.locale);
    _commit(_current.copyWith(systemVoice: voice));
  }
```

4. Replace every remaining use of `TtsModelCatalog.defaultModel` in the file (in `previewVoice` and `startReading`) with `activeSpec`. Concretely, in `previewVoice` (originally line 146) change:

```dart
    final TtsModelSpec spec = TtsModelCatalog.defaultModel;
```
to:
```dart
    final TtsModelSpec spec = activeSpec;
```

and in `startReading` (originally line 185) change the same line the same way. Leave everything else in those two methods untouched for this task — Task 9 adds the `activeEngine == system` branch to `startReading`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tts/tts_notifier_engine_selection_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full existing test suite to check for regressions**

Run: `flutter test test/tts/`
Expected: PASS (all tests from Tasks 1-8).

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/tts/application/tts_notifier.dart test/tts/tts_notifier_engine_selection_test.dart
git commit -m "feat(tts): TtsNotifier resolves the active engine/model instead of a hardcoded default"
```

---

## Task 9: `TtsNotifier` — system TTS reading session

**Files:**
- Modify: `lib/src/features/tts/application/tts_notifier.dart`
- Test: `test/tts/tts_notifier_system_reading_test.dart` (new)

**Interfaces:**
- Consumes: `SystemTtsClient` (Task 6), `activeSpec`/`setActiveEngine` (Task 8).
- Produces: `startReading` branches on `_current.activeEngine == TtsEngineKind.system` to run a system-TTS session; `pause`/`resume`/`stop`/`skipToIndex` work the same from the caller's point of view regardless of which session is active.

Speed mapping: the UI's speed slider stays 0.75x-1.5x (unchanged meaning for the sherpa engines). For system TTS, map it to flutter_tts's ~0.0-1.0 rate via `rate = (speed * 0.5).clamp(0.0, 1.0)` (so 1.0x → 0.5, flutter_tts's normal-speed default) — call this out as approximate; exact perceived speed vs. the sherpa engines will differ by platform voice and isn't a correctness requirement, just an option to speed up/slow down from wherever "normal" lands.

Pause/resume caveat: some platforms' TTS engines (notably Android) don't support true pause/resume mid-utterance — `flutter_tts.pause()` may just stop. This implementation calls `pause()`/re-`speak()`s the current segment on `resume()` as a reasonable approximation; note this in the PR description as a known platform limitation rather than trying to paper over it.

- [ ] **Step 1: Write the failing test**

Create `test/tts/tts_notifier_system_reading_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:clarix/src/features/tts/application/tts_providers.dart';
import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _ScriptedSystemTtsClient implements SystemTtsClient {
  final List<String> spoken = <String>[];
  void Function()? _onComplete;

  @override
  Future<List<SystemTtsVoice>> getVoices() async => const <SystemTtsVoice>[];
  @override
  Future<void> setVoice(SystemTtsVoice voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    // Simulate the platform completing the utterance asynchronously, the
    // same way flutter_tts's completion handler fires.
    scheduleMicrotask(() => _onComplete?.call());
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void onComplete(void Function() callback) => _onComplete = callback;
  @override
  void onError(void Function(Object error) callback) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('reads all segments via SystemTtsClient and returns to idle', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_system_test_');
    addTearDown(() => tempDir.delete(recursive: true));
    final _ScriptedSystemTtsClient client = _ScriptedSystemTtsClient();

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ttsModelStoreProvider.overrideWithValue(
          TtsModelStore(directoryProvider: () async => tempDir),
        ),
        systemTtsClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ttsNotifierProvider.future);

    final notifier = container.read(ttsNotifierProvider.notifier);
    await notifier.setActiveEngine(TtsEngineKind.system);

    await notifier.startReading(
      documentId: 'doc-1',
      segments: const <ReadAloudSegment>[
        ReadAloudSegment(id: 's1', text: 'First sentence.', pageNumber: 1),
        ReadAloudSegment(id: 's2', text: 'Second sentence.', pageNumber: 1),
      ],
      startIndex: 0,
    );
    notifier.finishSegments();

    // Let the microtask-scheduled completions and the internal await chain
    // drain.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(client.spoken, <String>['First sentence.', 'Second sentence.']);
    expect(
      container.read(ttsNotifierProvider).requireValue.playback.status,
      TtsPlaybackStatus.idle,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tts/tts_notifier_system_reading_test.dart`
Expected: FAIL — `startReading` doesn't yet branch on the system engine, so it will try (and fail) to load a sherpa model.

- [ ] **Step 3: Add the system reading path to `TtsNotifier`**

Add new private fields near the top of the class (alongside `_engine`, `_player`, etc.):

```dart
  SystemTtsClient? _systemClient;
  int _systemNextIndex = 0;
```

Replace the `startReading` method with a version that branches on the active engine:

```dart
  Future<void> startReading({
    required String documentId,
    required List<ReadAloudSegment> segments,
    required int startIndex,
  }) async {
    await stop();
    if (segments.isEmpty || startIndex < 0 || startIndex >= segments.length) {
      return;
    }

    _generation++;
    final int myGeneration = _generation;
    _segments = segments;
    _noMoreSegments = false;

    _commit(
      _current.copyWith(
        playback: TtsPlaybackState(
          status: TtsPlaybackStatus.preparing,
          documentId: documentId,
          segmentIndex: startIndex,
          segmentTotal: segments.length,
          currentPage: segments[startIndex].pageNumber,
          currentSegmentId: segments[startIndex].id,
        ),
        clearErrorMessage: true,
      ),
    );

    if (_current.activeEngine == TtsEngineKind.system) {
      await _startSystemReading(myGeneration, startIndex);
      return;
    }
    await _startSherpaReading(myGeneration, startIndex);
  }

  Future<void> _startSherpaReading(int myGeneration, int startIndex) async {
    final TtsModelSpec spec = activeSpec;
    if (_current.installState[spec.id]?.status != TtsInstallStatus.installed) {
      _commit(
        _current.copyWith(
          playback: const TtsPlaybackState(),
          errorMessage: 'Download a voice pack in Settings first.',
        ),
      );
      return;
    }

    _nextToSynthesize = startIndex;
    _pendingQueue.clear();

    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    try {
      _engine = await TtsEngineWorker.start(
        engine: spec.engine,
        paths: await store.paths(spec),
      );
    } catch (error) {
      _commit(
        _current.copyWith(
          playback: const TtsPlaybackState(),
          errorMessage: 'Could not load the voice model: $error',
        ),
      );
      return;
    }
    if (myGeneration != _generation) return;

    final Directory tempRoot = await getTemporaryDirectory();
    _sessionDir = Directory(
      p.join(
        tempRoot.path,
        'clarix_tts',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await _sessionDir!.create(recursive: true);

    _player = AudioPlayer();
    _completeSub = _player!.onPlayerComplete.listen((_) => _advanceQueue());

    unawaited(_synthesisLoop(myGeneration));
  }

  Future<void> _startSystemReading(int myGeneration, int startIndex) async {
    final SystemTtsClient client = ref.read(systemTtsClientProvider);
    _systemClient = client;
    _systemNextIndex = startIndex;

    final SystemTtsVoice? voice = _current.systemVoice;
    if (voice != null) await client.setVoice(voice);
    await client.setSpeechRate((_current.defaultSpeed * 0.5).clamp(0.0, 1.0));

    client.onComplete(() {
      if (myGeneration != _generation) return;
      unawaited(_speakNextSystemSegment(myGeneration));
    });
    client.onError((Object error) {
      if (myGeneration != _generation) return;
      _commit(
        _current.copyWith(
          playback: const TtsPlaybackState(),
          errorMessage: 'System voice failed: $error',
        ),
      );
    });

    await _speakNextSystemSegment(myGeneration);
  }

  Future<void> _speakNextSystemSegment(int generation) async {
    if (generation != _generation) return;
    if (_systemNextIndex >= _segments.length) {
      if (_noMoreSegments) unawaited(stop());
      return;
    }
    final int index = _systemNextIndex;
    final ReadAloudSegment segment = _segments[index];
    _systemNextIndex++;
    _commit(
      _current.copyWith(
        playback: _current.playback.copyWith(
          status: TtsPlaybackStatus.speaking,
          segmentIndex: index,
          currentPage: segment.pageNumber,
          currentSegmentId: segment.id,
        ),
      ),
    );
    await _systemClient?.speak(segment.text);
  }
```

Update `appendSegments` (unchanged logic, but it must also resume the system loop) — replace its body:

```dart
  void appendSegments(List<ReadAloudSegment> more) {
    if (more.isEmpty || !isReading) return;
    _segments = List<ReadAloudSegment>.of(_segments)..addAll(more);
    _commit(
      _current.copyWith(
        playback: _current.playback.copyWith(segmentTotal: _segments.length),
      ),
    );
    if (_current.activeEngine == TtsEngineKind.system) {
      if (_systemNextIndex >= _segments.length - more.length) {
        // The system loop had run out of segments and gone idle; nudge it.
        unawaited(_speakNextSystemSegment(_generation));
      }
      return;
    }
    if (_activeLoopGeneration != _generation) {
      unawaited(_synthesisLoop(_generation));
    }
  }
```

Update `skipToIndex` to branch too — replace its body:

```dart
  Future<void> skipToIndex(int index) async {
    if (_segments.isEmpty || index < 0 || index >= _segments.length) return;
    if (!isReading) return;

    _generation++;
    final int myGeneration = _generation;

    final ReadAloudSegment segment = _segments[index];
    _commit(
      _current.copyWith(
        playback: _current.playback.copyWith(
          status: TtsPlaybackStatus.preparing,
          segmentIndex: index,
          currentPage: segment.pageNumber,
          currentSegmentId: segment.id,
        ),
      ),
    );

    if (_current.activeEngine == TtsEngineKind.system) {
      await _systemClient?.stop();
      _systemNextIndex = index;
      unawaited(_speakNextSystemSegment(myGeneration));
      return;
    }

    _pendingQueue.clear();
    _nextToSynthesize = index;
    await _player?.stop();
    unawaited(_synthesisLoop(myGeneration));
  }
```

Update `pause`/`resume` to branch — replace both methods:

```dart
  Future<void> pause() async {
    if (_current.activeEngine == TtsEngineKind.system) {
      await _systemClient?.pause();
    } else {
      await _player?.pause();
    }
    if (_current.playback.status == TtsPlaybackStatus.speaking) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(status: TtsPlaybackStatus.paused),
        ),
      );
    }
  }

  Future<void> resume() async {
    if (_current.activeEngine == TtsEngineKind.system) {
      // flutter_tts doesn't guarantee true mid-utterance resume on every
      // platform; re-speak the current segment as the best available
      // approximation.
      if (_current.playback.status == TtsPlaybackStatus.paused) {
        _systemNextIndex = _current.playback.segmentIndex;
        unawaited(_speakNextSystemSegment(_generation));
      }
    } else {
      await _player?.resume();
    }
    if (_current.playback.status == TtsPlaybackStatus.paused) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(status: TtsPlaybackStatus.speaking),
        ),
      );
    }
  }
```

Finally, update `stop()` to also tear down the system client — in the existing `stop()` method, right after `_engine?.dispose();`, add:

```dart
    await _systemClient?.stop();
    _systemClient = null;
    _systemNextIndex = 0;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tts/tts_notifier_system_reading_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full tts test suite**

Run: `flutter test test/tts/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/tts/application/tts_notifier.dart test/tts/tts_notifier_system_reading_test.dart
git commit -m "feat(tts): drive system-voice reading sessions through SystemTtsClient"
```

---

## Task 10: Settings UI — engine selector, per-model rows, system voice list

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/app_settings_tts_section.dart` (full replace)
- Test: `test/workspace/app_settings_tts_section_test.dart` (new)

**Interfaces:**
- Consumes: `TtsFeatureState.activeEngine/activeModelId/systemVoice/availableSystemVoices` (Task 7/8), `TtsNotifier.setActiveEngine/setActiveModel/setSystemVoice` (Task 8), `TtsModelCatalog.all` (Task 2).

- [ ] **Step 1: Write the failing test**

Create `test/workspace/app_settings_tts_section_test.dart`:

```dart
import 'dart:io';

import 'package:clarix/src/features/tts/application/tts_providers.dart';
import 'package:clarix/src/features/tts/infrastructure/system_tts_client.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/app_settings_tts_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeSystemTtsClient implements SystemTtsClient {
  @override
  Future<List<SystemTtsVoice>> getVoices() async => const <SystemTtsVoice>[
    SystemTtsVoice(name: 'Karen', locale: 'en-AU'),
  ];
  @override
  Future<void> setVoice(SystemTtsVoice voice) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void onComplete(void Function() callback) {}
  @override
  void onError(void Function(Object error) callback) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  testWidgets('shows all three catalog voice packs and switches to System voice', (
    tester,
  ) async {
    final Directory tempDir = await Directory.systemTemp.createTemp('tts_settings_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ttsModelStoreProvider.overrideWithValue(
            TtsModelStore(directoryProvider: () async => tempDir),
          ),
          systemTtsClientProvider.overrideWithValue(_FakeSystemTtsClient()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: TtsSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kitten (nano, int8) · 31MB'), findsOneWidget);
    expect(find.text('Piper — Amy (US) · 21MB'), findsOneWidget);
    expect(find.text('Piper — Alan (UK) · 21MB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts-engine-system')));
    await tester.pumpAndSettle();

    expect(find.text('Karen (en-AU)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/workspace/app_settings_tts_section_test.dart`
Expected: FAIL — the current widget only shows one hardcoded spec and has no engine switch.

- [ ] **Step 3: Replace `app_settings_tts_section.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clarix/src/features/tts/tts.dart';
import 'workspace_common.dart';

const String _previewText =
    'This is how this voice sounds when reading a document aloud.';

/// Settings section for on-device text-to-speech: engine choice, voice-pack
/// download, and the default voice/speed used everywhere "Read aloud" is
/// invoked.
class TtsSettingsSection extends ConsumerStatefulWidget {
  const TtsSettingsSection({super.key});

  @override
  ConsumerState<TtsSettingsSection> createState() => _TtsSettingsSectionState();
}

class _TtsSettingsSectionState extends ConsumerState<TtsSettingsSection> {
  int? _previewingSid;

  @override
  Widget build(BuildContext context) {
    final TtsFeatureState state =
        ref.watch(ttsNotifierProvider).value ?? TtsFeatureState.initial();
    final bool isSystem = state.activeEngine == TtsEngineKind.system;
    final TtsModelSpec activeSpec = state.activeModelId == null
        ? TtsModelCatalog.defaultModel
        : TtsModelCatalog.byId(state.activeModelId!);
    final TtsModelInstallState activeInstall =
        state.installState[activeSpec.id] ?? const TtsModelInstallState();
    final bool activeInstalled = activeInstall.status == TtsInstallStatus.installed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Read aloud',
          style: TextStyle(
            color: WorkspaceColors.textStrong,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose an on-device voice pack to download, or use your system\'s '
          'built-in voice — available from the right-click "Read aloud" menu.',
          style: TextStyle(color: WorkspaceColors.textMuted),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              key: Key('tts-engine-on-device'),
              label: Text('On-device'),
            ),
            ButtonSegment<bool>(
              value: true,
              key: Key('tts-engine-system'),
              label: Text('System voice'),
            ),
          ],
          selected: <bool>{isSystem},
          onSelectionChanged: (Set<bool> selection) => ref
              .read(ttsNotifierProvider.notifier)
              .setActiveEngine(
                selection.first ? TtsEngineKind.system : TtsEngineKind.kittenSherpa,
              ),
        ),
        const SizedBox(height: 14),
        if (isSystem)
          _buildSystemVoiceList(state)
        else
          _buildOnDeviceSection(state, activeSpec, activeInstall, activeInstalled),
        if (state.errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            state.errorMessage!,
            style: const TextStyle(color: WorkspaceColors.warning, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildOnDeviceSection(
    TtsFeatureState state,
    TtsModelSpec activeSpec,
    TtsModelInstallState activeInstall,
    bool activeInstalled,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final TtsModelSpec spec in TtsModelCatalog.all) ...<Widget>[
          _buildModelRow(
            spec,
            state.installState[spec.id] ?? const TtsModelInstallState(),
            selected: spec.id == activeSpec.id,
          ),
          const SizedBox(height: 8),
        ],
        if (activeInstalled && activeSpec.voiceCount > 1) ...<Widget>[
          const SizedBox(height: 10),
          const Text(
            'Voice',
            style: TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildVoiceGrid(state, activeSpec),
        ],
        if (activeInstalled) ...<Widget>[
          const SizedBox(height: 18),
          _buildSpeedSlider(state),
        ],
      ],
    );
  }

  Widget _buildSystemVoiceList(TtsFeatureState state) {
    if (state.availableSystemVoices.isEmpty) {
      return const Text(
        'No system voices were found on this device.',
        style: TextStyle(color: WorkspaceColors.textMuted, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final SystemTtsVoice voice in state.availableSystemVoices)
          RadioListTile<SystemTtsVoice>(
            key: Key('system-voice-${voice.name}-${voice.locale}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${voice.name} (${voice.locale})'),
            value: voice,
            groupValue: state.systemVoice,
            onChanged: (SystemTtsVoice? value) {
              if (value != null) {
                ref.read(ttsNotifierProvider.notifier).setSystemVoice(value);
              }
            },
          ),
        const SizedBox(height: 10),
        _buildSpeedSlider(state),
      ],
    );
  }

  Widget _buildSpeedSlider(TtsFeatureState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              'Speed',
              style: TextStyle(
                color: WorkspaceColors.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${state.defaultSpeed.toStringAsFixed(2)}x',
              style: const TextStyle(color: WorkspaceColors.textMuted),
            ),
          ],
        ),
        Slider(
          value: state.defaultSpeed,
          min: 0.75,
          max: 1.5,
          divisions: 15,
          onChanged: (double value) =>
              ref.read(ttsNotifierProvider.notifier).setDefaultSpeed(value),
        ),
      ],
    );
  }

  Widget _buildModelRow(
    TtsModelSpec spec,
    TtsModelInstallState install, {
    required bool selected,
  }) {
    final double sizeMb = spec.approxArchiveSizeBytes / 1000 / 1000;
    switch (install.status) {
      case TtsInstallStatus.notInstalled:
      case TtsInstallStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (install.status == TtsInstallStatus.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  install.errorMessage ?? 'Download failed.',
                  style: const TextStyle(
                    color: WorkspaceColors.warning,
                    fontSize: 12,
                  ),
                ),
              ),
            OutlinedButton.icon(
              key: Key('download-tts-voice-${spec.id}'),
              onPressed: () =>
                  ref.read(ttsNotifierProvider.notifier).downloadModel(spec),
              icon: const Icon(Icons.download_outlined),
              label: Text('${spec.label} · ${sizeMb.toStringAsFixed(0)}MB'),
            ),
          ],
        );
      case TtsInstallStatus.downloading:
      case TtsInstallStatus.extracting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LinearProgressIndicator(
              value: install.status == TtsInstallStatus.extracting
                  ? null
                  : install.progress,
            ),
            const SizedBox(height: 6),
            Text(
              install.status == TtsInstallStatus.extracting
                  ? 'Extracting…'
                  : 'Downloading ${spec.label}… ${(install.progress * 100).round()}%',
              style: const TextStyle(color: WorkspaceColors.textMuted, fontSize: 12),
            ),
          ],
        );
      case TtsInstallStatus.installed:
        return Material(
          color: selected ? WorkspaceColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: ListTile(
            key: Key('tts-model-row-${spec.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            ),
            title: Text(spec.label),
            subtitle: const Text('Installed on this device'),
            onTap: () =>
                ref.read(ttsNotifierProvider.notifier).setActiveModel(spec),
            trailing: IconButton(
              key: Key('delete-tts-voice-${spec.id}'),
              tooltip: 'Delete ${spec.label}',
              onPressed: () =>
                  ref.read(ttsNotifierProvider.notifier).deleteModel(spec),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        );
    }
  }

  Widget _buildVoiceGrid(TtsFeatureState state, TtsModelSpec spec) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int sid = 0; sid < spec.voiceCount; sid++)
          _VoiceTile(
            sid: sid,
            selected: state.defaultVoiceSid == sid,
            previewing: _previewingSid == sid,
            onSelect: () =>
                ref.read(ttsNotifierProvider.notifier).setDefaultVoice(sid),
            onPreview: () => _preview(sid),
          ),
      ],
    );
  }

  Future<void> _preview(int sid) async {
    if (_previewingSid != null) return;
    setState(() => _previewingSid = sid);
    try {
      await ref.read(ttsNotifierProvider.notifier).previewVoice(sid, _previewText);
    } finally {
      if (mounted) setState(() => _previewingSid = null);
    }
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.sid,
    required this.selected,
    required this.previewing,
    required this.onSelect,
    required this.onPreview,
  });

  final int sid;
  final bool selected;
  final bool previewing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? WorkspaceColors.accentSoft : WorkspaceColors.panelRaised,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: Key('tts-voice-$sid'),
      borderRadius: BorderRadius.circular(8),
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Voice ${sid + 1}',
              style: TextStyle(
                color: selected
                    ? WorkspaceColors.accent
                    : WorkspaceColors.textStrong,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              height: 28,
              child: previewing
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: Key('tts-voice-preview-$sid'),
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: 'Preview',
                      onPressed: onPreview,
                      icon: const Icon(Icons.play_arrow),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

Note the download/delete widget `Key`s changed from `download-tts-voice`/`delete-tts-voice` to `download-tts-voice-${spec.id}`/`delete-tts-voice-${spec.id}` since there are now three specs; there were no existing tests referencing the old keys (confirmed no hits in `test/` before this task), so this is not a breaking rename for any other test.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/workspace/app_settings_tts_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/workspace/presentation/widgets/app_settings_tts_section.dart test/workspace/app_settings_tts_section_test.dart
git commit -m "feat(tts): settings UI for engine selection, multi-model list, system voices"
```

---

## Task 11: Full suite, analyzer, and manual smoke check

**Files:** none (verification only)

- [ ] **Step 1: Run the analyzer**

Run: `flutter analyze`
Expected: no new errors or warnings introduced by this feature (pre-existing issues elsewhere in the repo are out of scope).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 3: Manual smoke check (requires a real device/desktop build — not automatable)**

On at least one CPU-only Windows machine:
1. Open Settings → Read aloud. Confirm all three on-device rows render with correct sizes (Kitten 31MB, Amy/Alan 21MB each).
2. Download the Kitten int8 pack, select it, preview a couple of voices, then start "Read aloud" on a document — confirm synthesis latency is noticeably lower than the previous fp16 build (subjective, but should be clearly faster).
3. Download a Piper voice, switch to it, confirm reading works with a single voice (no voice grid shown).
4. Switch to "System voice", confirm the device's installed voices are listed, pick one, and start reading — confirm sentence highlighting and click-to-skip behave the same as with the on-device engines, and that pause/resume doesn't crash (even if resume restarts the current sentence rather than resuming mid-word).

Record the outcome in the PR description; this step has no automated equivalent because it depends on perceived audio latency and real platform TTS voices.

- [ ] **Step 4: Commit (only if Step 1-2 required fixes)**

If the analyzer or full suite surfaced issues needing fixes, commit them:

```bash
git add -A
git commit -m "fix(tts): address analyzer/test suite findings from full-suite verification"
```

If no fixes were needed, skip this step — there's nothing to commit.
