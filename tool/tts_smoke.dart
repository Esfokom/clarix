// Temporary smoke test: verifies sherpa-onnx TTS synthesis works on this
// machine against the installed Kitten voice pack. Delete after use.
import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main() {
  final String home = Platform.environment['APPDATA']!;
  final String dir =
      '$home\\com.example\\clarix\\clarix\\tts_models\\kitten-nano-en-v0_1-fp16';
  final String sherpaDir =
      '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache\\hosted\\pub.dev'
      '\\sherpa_onnx_windows-1.13.7\\windows';

  stdout.writeln('model dir: $dir');
  stdout.writeln('exists: ${Directory(dir).existsSync()}');

  // Windows resolves a bare `onnxruntime.dll` import from System32 before PATH,
  // and this machine has an old ORT 1.17.1 there. Load the matching runtime by
  // absolute path first so the loader reuses that module for sherpa's import.
  DynamicLibrary.open('$sherpaDir\\onnxruntime.dll');
  stdout.writeln('preloaded matching onnxruntime.dll');

  sherpa.initBindings(sherpaDir);
  stdout.writeln('bindings initialized');

  final sherpa.OfflineTts tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kitten: sherpa.OfflineTtsKittenModelConfig(
          model: '$dir\\model.fp16.onnx',
          voices: '$dir\\voices.bin',
          tokens: '$dir\\tokens.txt',
          dataDir: '$dir\\espeak-ng-data',
        ),
        numThreads: 2,
        debug: false,
      ),
      maxNumSenetences: 1,
    ),
  );

  stdout.writeln('sampleRate: ${tts.sampleRate}');
  stdout.writeln('numSpeakers: ${tts.numSpeakers}');

  const List<String> passages = <String>[
    'Scope three. Agentic document workflows, the new paradigm.',
    'This is a test of on-device text to speech inside Clarix.',
    'Claude Cowork launched as a research preview in January, as a tab '
        'within the desktop application, adjacent to chat and code.',
    'Short one.',
  ];

  late sherpa.GeneratedAudio audio;
  for (int i = 0; i < passages.length; i++) {
    final Stopwatch sw = Stopwatch()..start();
    audio = tts.generate(text: passages[i], sid: 0, speed: 1.0);
    sw.stop();
    final double seconds = audio.samples.length / audio.sampleRate;
    final double rtf = sw.elapsedMilliseconds / 1000 / seconds;
    stdout.writeln(
      'run $i: ${sw.elapsedMilliseconds} ms for '
      '${seconds.toStringAsFixed(2)}s audio -> RTF ${rtf.toStringAsFixed(2)}'
      '${i == 0 ? '  (includes warm-up)' : ''}',
    );
  }

  final String out = '${Directory.systemTemp.path}\\clarix_tts_smoke.wav';
  final bool ok = sherpa.writeWave(
    filename: out,
    samples: audio.samples,
    sampleRate: audio.sampleRate,
  );
  stdout.writeln('wrote wav: $ok -> $out');
  stdout.writeln('wav size: ${File(out).lengthSync()} bytes');

  tts.free();
}
