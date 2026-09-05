// Temporary benchmark: compares TTS real-time factor across voice packs and
// thread counts, to pick a default that can keep ahead of playback.
// Delete after use.
import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const List<String> _passages = <String>[
  'Scope three. Agentic document workflows, the new paradigm.',
  'Claude Cowork launched as a research preview in January, as a tab '
      'within the desktop application, adjacent to chat and code.',
];

void main(List<String> args) {
  final String appData = Platform.environment['APPDATA']!;
  final String root = '$appData\\com.example\\clarix\\clarix\\tts_models';
  final String sherpaDir =
      '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache\\hosted\\pub.dev'
      '\\sherpa_onnx_windows-1.13.7\\windows';

  DynamicLibrary.open('$sherpaDir\\onnxruntime.dll');
  sherpa.initBindings(sherpaDir);
  stdout.writeln('processors: ${Platform.numberOfProcessors}');

  for (final int threads in <int>[2, 4, 8]) {
    _bench(
      label: 'kitten fp16 (threads=$threads)',
      dir: '$root\\kitten-nano-en-v0_1-fp16',
      threads: threads,
      isKokoro: false,
      modelFile: 'model.fp16.onnx',
    );
  }

  final String kokoro = '$root\\kokoro-int8-en-v0_19';
  if (Directory(kokoro).existsSync()) {
    for (final int threads in <int>[4, 8]) {
      _bench(
        label: 'kokoro int8 (threads=$threads)',
        dir: kokoro,
        threads: threads,
        isKokoro: true,
        modelFile: 'model.int8.onnx',
      );
    }
  } else {
    stdout.writeln('kokoro not installed, skipping');
  }
}

void _bench({
  required String label,
  required String dir,
  required int threads,
  required bool isKokoro,
  required String modelFile,
}) {
  final sherpa.OfflineTtsModelConfig model = isKokoro
      ? sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: '$dir\\$modelFile',
            voices: '$dir\\voices.bin',
            tokens: '$dir\\tokens.txt',
            dataDir: '$dir\\espeak-ng-data',
          ),
          numThreads: threads,
          debug: false,
        )
      : sherpa.OfflineTtsModelConfig(
          kitten: sherpa.OfflineTtsKittenModelConfig(
            model: '$dir\\$modelFile',
            voices: '$dir\\voices.bin',
            tokens: '$dir\\tokens.txt',
            dataDir: '$dir\\espeak-ng-data',
          ),
          numThreads: threads,
          debug: false,
        );

  final sherpa.OfflineTts tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(model: model, maxNumSenetences: 1),
  );

  // Warm up once so the reported numbers are steady state.
  tts.generate(text: 'Warm up.', sid: 0, speed: 1.0);

  int totalMs = 0;
  double totalAudio = 0;
  for (final String passage in _passages) {
    final Stopwatch sw = Stopwatch()..start();
    final sherpa.GeneratedAudio audio =
        tts.generate(text: passage, sid: 0, speed: 1.0);
    sw.stop();
    totalMs += sw.elapsedMilliseconds;
    totalAudio += audio.samples.length / audio.sampleRate;
  }
  final double rtf = totalMs / 1000 / totalAudio;
  stdout.writeln(
    '$label: ${totalMs}ms for ${totalAudio.toStringAsFixed(2)}s '
    '-> RTF ${rtf.toStringAsFixed(2)} (speakers=${tts.numSpeakers})',
  );
  tts.free();
}
