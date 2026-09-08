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
