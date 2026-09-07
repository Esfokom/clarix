import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/tts_models.dart';
import '../infrastructure/tts_engine_worker.dart';
import '../infrastructure/tts_model_catalog.dart';
import '../infrastructure/tts_model_store.dart';
import '../infrastructure/tts_preferences_store.dart';
import 'tts_feature_state.dart';
import 'tts_providers.dart';

class _QueuedAudio {
  const _QueuedAudio({required this.index, required this.path});
  final int index;
  final String path;
}

/// Owns TTS voice-pack installation, user voice/speed preferences, and the
/// active read-aloud session (synthesis-ahead queue + sequential playback).
///
/// Reading always operates over a caller-supplied [ReadAloudSegment] list —
/// this notifier has no opinion on where segments come from; the reader
/// feature extracts them from the live PDF page text.
class TtsNotifier extends AsyncNotifier<TtsFeatureState> {
  AudioPlayer? _player;
  TtsEngineWorker? _engine;
  StreamSubscription<void>? _completeSub;
  List<ReadAloudSegment> _segments = const <ReadAloudSegment>[];
  final List<_QueuedAudio> _pendingQueue = <_QueuedAudio>[];
  int _nextToSynthesize = 0;
  int _generation = 0;
  int? _activeLoopGeneration;
  bool _playerActive = false;
  bool _noMoreSegments = false;
  Directory? _sessionDir;

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
    return TtsFeatureState.initial().copyWith(
      installState: installState,
      defaultVoiceSid: defaultVoiceSid,
      defaultSpeed: defaultSpeed,
    );
  }

  TtsFeatureState get _current => state.value ?? TtsFeatureState.initial();

  void _commit(TtsFeatureState value) => state = AsyncData<TtsFeatureState>(value);

  bool get isReading => _current.playback.status != TtsPlaybackStatus.idle;

  // --- Model management -----------------------------------------------

  Future<void> downloadModel(TtsModelSpec spec) async {
    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    _updateInstall(
      spec.id,
      const TtsModelInstallState(status: TtsInstallStatus.downloading),
    );
    try {
      await store.install(
        spec,
        onDownloadProgress: (double progress) => _updateInstall(
          spec.id,
          TtsModelInstallState(
            status: TtsInstallStatus.downloading,
            progress: progress,
          ),
        ),
        onExtracting: () => _updateInstall(
          spec.id,
          const TtsModelInstallState(status: TtsInstallStatus.extracting),
        ),
      );
      _updateInstall(
        spec.id,
        const TtsModelInstallState(status: TtsInstallStatus.installed),
      );
    } catch (error) {
      _updateInstall(
        spec.id,
        TtsModelInstallState(
          status: TtsInstallStatus.failed,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> deleteModel(TtsModelSpec spec) async {
    await stop();
    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    await store.delete(spec);
    _updateInstall(spec.id, const TtsModelInstallState());
  }

  void _updateInstall(String specId, TtsModelInstallState value) {
    final Map<String, TtsModelInstallState> next =
        Map<String, TtsModelInstallState>.of(_current.installState)
          ..[specId] = value;
    _commit(_current.copyWith(installState: next));
  }

  // --- Preferences -------------------------------------------------------

  Future<void> setDefaultVoice(int sid) async {
    await ref.read(ttsPreferencesStoreProvider).saveDefaultVoice(sid);
    _commit(_current.copyWith(defaultVoiceSid: sid));
  }

  Future<void> setDefaultSpeed(double speed) async {
    await ref.read(ttsPreferencesStoreProvider).saveSpeed(speed);
    _commit(_current.copyWith(defaultSpeed: speed));
  }

  /// Speaks [text] once with the current default voice/speed, for previewing
  /// a voice from Settings. Does not touch reading-session state.
  Future<void> previewVoice(int sid, String text) async {
    final TtsModelSpec spec = TtsModelCatalog.defaultModel;
    if (_current.installState[spec.id]?.status != TtsInstallStatus.installed) {
      return;
    }
    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    TtsEngineWorker? previewEngine;
    AudioPlayer? previewPlayer;
    try {
      previewEngine = await TtsEngineWorker.start(
        paths: await store.paths(spec),
      );
      final Directory tempRoot = await getTemporaryDirectory();
      final String outPath = p.join(
        tempRoot.path,
        'clarix_tts_preview_$sid.wav',
      );
      await previewEngine.synthesizeToFile(
        text: text,
        sid: sid,
        speed: _current.defaultSpeed,
        outputPath: outPath,
      );
      previewPlayer = AudioPlayer();
      await previewPlayer.play(DeviceFileSource(outPath));
      await previewPlayer.onPlayerComplete.first;
    } finally {
      await previewPlayer?.dispose();
      previewEngine?.dispose();
    }
  }

  // --- Reading session -----------------------------------------------------

  Future<void> startReading({
    required String documentId,
    required List<ReadAloudSegment> segments,
    required int startIndex,
  }) async {
    await stop();
    final TtsModelSpec spec = TtsModelCatalog.defaultModel;
    if (_current.installState[spec.id]?.status != TtsInstallStatus.installed) {
      _commit(
        _current.copyWith(errorMessage: 'Download a voice pack in Settings first.'),
      );
      return;
    }
    if (segments.isEmpty || startIndex < 0 || startIndex >= segments.length) {
      return;
    }

    _generation++;
    final int myGeneration = _generation;
    _segments = segments;
    _nextToSynthesize = startIndex;
    _noMoreSegments = false;
    _pendingQueue.clear();

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

    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    try {
      _engine = await TtsEngineWorker.start(paths: await store.paths(spec));
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

  /// Appends more segments to the current reading session (e.g. once the
  /// reader has extracted the next page's sentences), so a long document can
  /// start reading immediately instead of waiting for the whole thing to be
  /// extracted up front. No-op if there is no active session.
  void appendSegments(List<ReadAloudSegment> more) {
    if (more.isEmpty || !isReading) return;
    _segments = List<ReadAloudSegment>.of(_segments)..addAll(more);
    _commit(
      _current.copyWith(
        playback: _current.playback.copyWith(segmentTotal: _segments.length),
      ),
    );
    if (_activeLoopGeneration != _generation) {
      unawaited(_synthesisLoop(_generation));
    }
  }

  /// Signals that the reader has reached the end of the document — no more
  /// [appendSegments] calls will follow for this session. Lets an
  /// otherwise-idle queue know it's safe to stop rather than wait forever.
  void finishSegments() {
    _noMoreSegments = true;
    if (_player != null && !_playerActive && _pendingQueue.isEmpty) {
      unawaited(stop());
    }
  }

  /// Jumps playback to [index] within the current session's segment list
  /// (click-to-skip). No-op if there is no active reading session.
  Future<void> skipToIndex(int index) async {
    if (_segments.isEmpty || index < 0 || index >= _segments.length) return;
    if (!isReading) return;

    _generation++;
    final int myGeneration = _generation;
    _pendingQueue.clear();
    _nextToSynthesize = index;

    await _player?.stop();
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

    unawaited(_synthesisLoop(myGeneration));
  }

  Future<void> _synthesisLoop(int generation) async {
    final Directory? sessionDir = _sessionDir;
    if (sessionDir == null) return;
    _activeLoopGeneration = generation;
    try {
      while (true) {
        if (generation != _generation) return;
        if (_nextToSynthesize >= _segments.length) return;

        final int index = _nextToSynthesize;
        final ReadAloudSegment segment = _segments[index];
        _nextToSynthesize++;
        final String outputPath = p.join(sessionDir.path, 'segment_$index.wav');
        try {
          await _engine!.synthesizeToFile(
            text: segment.text,
            sid: _current.defaultVoiceSid,
            speed: _current.defaultSpeed,
            outputPath: outputPath,
          );
        } catch (_) {
          continue;
        }
        if (generation != _generation) return;
        _pendingQueue.add(_QueuedAudio(index: index, path: outputPath));
        if (_player != null && !_playerActive) {
          unawaited(_advanceQueue());
        }
      }
    } finally {
      if (_activeLoopGeneration == generation) _activeLoopGeneration = null;
    }
  }

  Future<void> _advanceQueue() async {
    if (_player == null) return;
    if (_pendingQueue.isEmpty) {
      _playerActive = false;
      if (_nextToSynthesize >= _segments.length && _noMoreSegments) {
        unawaited(stop());
      }
      return;
    }
    _playerActive = true;
    final _QueuedAudio item = _pendingQueue.removeAt(0);
    final ReadAloudSegment segment = _segments[item.index];
    _commit(
      _current.copyWith(
        playback: _current.playback.copyWith(
          status: TtsPlaybackStatus.speaking,
          segmentIndex: item.index,
          currentPage: segment.pageNumber,
          currentSegmentId: segment.id,
        ),
      ),
    );
    await _player?.play(DeviceFileSource(item.path));
  }

  Future<void> pause() async {
    await _player?.pause();
    if (_current.playback.status == TtsPlaybackStatus.speaking) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(status: TtsPlaybackStatus.paused),
        ),
      );
    }
  }

  Future<void> resume() async {
    await _player?.resume();
    if (_current.playback.status == TtsPlaybackStatus.paused) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(status: TtsPlaybackStatus.speaking),
        ),
      );
    }
  }

  Future<void> stop() async {
    _generation++;
    _playerActive = false;
    await _completeSub?.cancel();
    await _player?.stop();
    await _player?.dispose();
    _engine?.dispose();
    final Directory? sessionDir = _sessionDir;
    if (sessionDir != null && await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
    _player = null;
    _engine = null;
    _completeSub = null;
    _sessionDir = null;
    _pendingQueue.clear();
    _segments = const <ReadAloudSegment>[];
    _nextToSynthesize = 0;
    _noMoreSegments = false;
    _activeLoopGeneration = null;
    _commit(_current.copyWith(playback: const TtsPlaybackState()));
  }
}
