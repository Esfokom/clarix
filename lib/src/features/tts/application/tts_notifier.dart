import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:clarix/src/core/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/tts_models.dart';
import '../infrastructure/tts_engine_worker.dart';
import '../infrastructure/tts_model_catalog.dart';
import '../infrastructure/tts_model_store.dart';
import 'tts_feature_state.dart';
import 'tts_providers.dart';
import 'tts_reader_service.dart';

class TtsNotifier extends AsyncNotifier<TtsFeatureState> {
  AudioPlayer? _player;
  TtsEngineWorker? _engine;
  StreamSubscription<void>? _completeSub;
  List<PdfChunkRecord> _activeChunks = const <PdfChunkRecord>[];
  final List<String> _pendingPaths = <String>[];
  int _playedIndex = -1;
  bool _playerBusy = false;
  bool _synthesisComplete = false;
  Directory? _sessionDir;
  bool _cancelSynthesis = false;

  @override
  Future<TtsFeatureState> build() async {
    ref.onDispose(() {
      _cancelSynthesis = true;
      _player?.dispose();
      _engine?.dispose();
    });

    final TtsModelStore store = ref.read(ttsModelStoreProvider);
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
    return TtsFeatureState.initial().copyWith(installState: installState);
  }

  TtsFeatureState get _current => state.value ?? TtsFeatureState.initial();

  void _commit(TtsFeatureState value) => state = AsyncData<TtsFeatureState>(value);

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
    if (_current.selectedModelId == spec.id) {
      await stop();
    }
    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    await store.delete(spec);
    _updateInstall(spec.id, const TtsModelInstallState());
  }

  void selectModel(String specId) {
    final TtsModelInstallState? install = _current.installState[specId];
    if (install?.status != TtsInstallStatus.installed) return;
    _commit(_current.copyWith(selectedModelId: specId, selectedSid: 0));
  }

  void setSid(int sid) => _commit(_current.copyWith(selectedSid: sid));

  void setSpeed(double speed) => _commit(_current.copyWith(speed: speed));

  Future<void> play(String documentId) async {
    await stop();
    final TtsModelSpec spec = TtsModelCatalog.byId(_current.selectedModelId);
    if (_current.installState[spec.id]?.status != TtsInstallStatus.installed) {
      _commit(
        _current.copyWith(errorMessage: 'Download a voice pack first.'),
      );
      return;
    }

    _commit(
      _current.copyWith(
        playback: TtsPlaybackState(
          status: TtsPlaybackStatus.preparing,
          documentId: documentId,
        ),
        clearErrorMessage: true,
      ),
    );

    final TtsModelStore store = ref.read(ttsModelStoreProvider);
    final TtsReaderService reader = ref.read(ttsReaderServiceProvider);

    final List<PdfChunkRecord> chunks = await reader.loadReadableChunks(
      documentId,
    );
    if (chunks.isEmpty) {
      _commit(
        _current.copyWith(
          playback: const TtsPlaybackState(),
          errorMessage: "This document hasn't been indexed for reading yet.",
        ),
      );
      return;
    }
    _activeChunks = chunks;

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
    _playedIndex = -1;
    _synthesisComplete = false;
    _pendingPaths.clear();
    _completeSub = _player!.onPlayerComplete.listen((_) => _advanceQueue());

    _commit(
      _current.copyWith(
        playback: _current.playback.copyWith(segmentTotal: chunks.length),
      ),
    );

    _cancelSynthesis = false;
    unawaited(_runSynthesis(reader));
  }

  Future<void> _runSynthesis(TtsReaderService reader) async {
    await for (final TtsSegment segment in reader.synthesize(
      chunks: _activeChunks,
      engine: _engine!,
      sid: _current.selectedSid,
      speed: _current.speed,
      outputDir: _sessionDir!,
      isCancelled: () => _cancelSynthesis,
    )) {
      if (_cancelSynthesis || _player == null) return;
      _pendingPaths.add(segment.filePath);
      if (!_playerBusy) {
        unawaited(_advanceQueue());
      }
    }
    if (!_cancelSynthesis) {
      _synthesisComplete = true;
    }
  }

  Future<void> _advanceQueue() async {
    if (_cancelSynthesis || _player == null) return;
    if (_pendingPaths.isEmpty) {
      _playerBusy = false;
      if (_synthesisComplete && _playedIndex >= _activeChunks.length - 1) {
        unawaited(stop());
      }
      return;
    }
    _playerBusy = true;
    final String path = _pendingPaths.removeAt(0);
    _playedIndex++;
    final int index = _playedIndex;
    if (index < _activeChunks.length) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(
            status: TtsPlaybackStatus.speaking,
            segmentIndex: index,
            currentPage: _activeChunks[index].pageNumber,
          ),
        ),
      );
    }
    await _player?.play(DeviceFileSource(path));
  }

  Future<void> pause() async {
    await _player?.pause();
    if (_current.playback.status == TtsPlaybackStatus.speaking) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(
            status: TtsPlaybackStatus.paused,
          ),
        ),
      );
    }
  }

  Future<void> resume() async {
    await _player?.resume();
    if (_current.playback.status == TtsPlaybackStatus.paused) {
      _commit(
        _current.copyWith(
          playback: _current.playback.copyWith(
            status: TtsPlaybackStatus.speaking,
          ),
        ),
      );
    }
  }

  Future<void> stop() async {
    _cancelSynthesis = true;
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
    _pendingPaths.clear();
    _playedIndex = -1;
    _playerBusy = false;
    _synthesisComplete = false;
    _activeChunks = const <PdfChunkRecord>[];
    _commit(_current.copyWith(playback: const TtsPlaybackState()));
  }

  void _updateInstall(String specId, TtsModelInstallState value) {
    final Map<String, TtsModelInstallState> next =
        Map<String, TtsModelInstallState>.of(_current.installState)
          ..[specId] = value;
    _commit(_current.copyWith(installState: next));
  }
}
