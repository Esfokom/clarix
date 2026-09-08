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
