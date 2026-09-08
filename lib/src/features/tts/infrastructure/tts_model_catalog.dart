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
    modelFileName: 'en_GB-alan-low.onnx',
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
