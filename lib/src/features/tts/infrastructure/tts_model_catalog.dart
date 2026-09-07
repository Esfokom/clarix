import '../domain/tts_models.dart';

/// Voice packs known to the app, packaged by the sherpa-onnx project.
class TtsModelCatalog {
  const TtsModelCatalog._();

  static const String _releaseBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  /// ~25.6MB, 8 built-in voices. Benchmarked faster than realtime (RTF ~0.65)
  /// on modest hardware, so it stays the only shipped voice pack for now.
  static const TtsModelSpec kitten = TtsModelSpec(
    id: 'kitten-nano-en-v0_1-fp16',
    engine: TtsEngineKind.kitten,
    label: 'Kitten (nano)',
    description: 'Fast, on-device voice pack.',
    downloadUrl: '$_releaseBase/kitten-nano-en-v0_1-fp16.tar.bz2',
    approxArchiveSizeBytes: 26 * 1000 * 1000,
    modelFileName: 'model.fp16.onnx',
    voicesFileName: 'voices.bin',
    tokensFileName: 'tokens.txt',
    dataDirName: 'espeak-ng-data',
    voiceCount: 8,
  );

  static const List<TtsModelSpec> all = <TtsModelSpec>[kitten];

  static const TtsModelSpec defaultModel = kitten;

  static TtsModelSpec byId(String id) =>
      all.firstWhere((TtsModelSpec spec) => spec.id == id, orElse: () => defaultModel);
}
