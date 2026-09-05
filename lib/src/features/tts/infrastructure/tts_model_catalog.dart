import '../domain/tts_models.dart';

/// Voice packs known to the app, packaged by the sherpa-onnx project.
///
/// Both are confirmed-supported native TTS families (unlike the newer
/// KittenTTS v0.8 ONNX2 release assets, whose sherpa-onnx inference support
/// was still pending upstream at the time these were chosen) and both fit
/// comfortably under a 100MB download.
class TtsModelCatalog {
  const TtsModelCatalog._();

  static const String _releaseBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  /// ~25.6MB, 8 built-in voices. Installed by default.
  static const TtsModelSpec kitten = TtsModelSpec(
    id: 'kitten-nano-en-v0_1-fp16',
    engine: TtsEngineKind.kitten,
    label: 'Kitten (nano)',
    description: 'Smallest voice pack. Fast on modest hardware, 8 voices.',
    downloadUrl: '$_releaseBase/kitten-nano-en-v0_1-fp16.tar.bz2',
    approxArchiveSizeBytes: 26 * 1000 * 1000,
    modelFileName: 'model.fp16.onnx',
    voicesFileName: 'voices.bin',
    tokensFileName: 'tokens.txt',
    dataDirName: 'espeak-ng-data',
  );

  /// ~98.5MB (int8), 11 built-in voices. Higher quality fallback.
  static const TtsModelSpec kokoro = TtsModelSpec(
    id: 'kokoro-int8-en-v0_19',
    engine: TtsEngineKind.kokoro,
    label: 'Kokoro (int8)',
    description: 'Higher-quality voices, larger download, 11 voices.',
    downloadUrl: '$_releaseBase/kokoro-int8-en-v0_19.tar.bz2',
    approxArchiveSizeBytes: 99 * 1000 * 1000,
    modelFileName: 'model.int8.onnx',
    voicesFileName: 'voices.bin',
    tokensFileName: 'tokens.txt',
    dataDirName: 'espeak-ng-data',
  );

  static const List<TtsModelSpec> all = <TtsModelSpec>[kitten, kokoro];

  static const TtsModelSpec defaultModel = kitten;
  static const TtsModelSpec fallbackModel = kokoro;

  static TtsModelSpec byId(String id) =>
      all.firstWhere((TtsModelSpec spec) => spec.id == id, orElse: () => defaultModel);
}
