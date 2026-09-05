import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/tts_models.dart';
import 'tts_model_store.dart';

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
      engine == TtsEngineKind.kokoro ? 'kokoro' : 'kitten',
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
    final String engine = args[1]! as String;
    final String model = args[2]! as String;
    final String voices = args[3]! as String;
    final String tokens = args[4]! as String;
    final String dataDir = args[5]! as String;

    late final sherpa.OfflineTts tts;
    try {
      sherpa.initBindings();
      final sherpa.OfflineTtsModelConfig modelConfig = engine == 'kokoro'
          ? sherpa.OfflineTtsModelConfig(
              kokoro: sherpa.OfflineTtsKokoroModelConfig(
                model: model,
                voices: voices,
                tokens: tokens,
                dataDir: dataDir,
              ),
              numThreads: 2,
              debug: false,
            )
          : sherpa.OfflineTtsModelConfig(
              kitten: sherpa.OfflineTtsKittenModelConfig(
                model: model,
                voices: voices,
                tokens: tokens,
                dataDir: dataDir,
              ),
              numThreads: 2,
              debug: false,
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
