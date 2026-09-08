import 'dart:io';

import 'package:clarix/src/features/tts/domain/tts_models.dart';
import 'package:clarix/src/features/tts/infrastructure/tts_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const TtsModelSpec _singleVoiceSpec = TtsModelSpec(
  id: 'fake-piper',
  engine: TtsEngineKind.piperSherpa,
  label: 'Fake Piper',
  description: '',
  downloadUrl: 'https://example.invalid/fake-piper.tar.bz2',
  approxArchiveSizeBytes: 0,
  modelFileName: 'model.onnx',
  tokensFileName: 'tokens.txt',
  dataDirName: 'espeak-ng-data',
  voiceCount: 1,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tts_model_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('isInstalled and paths work for a spec with no voices file', () async {
    final TtsModelStore store = TtsModelStore(
      directoryProvider: () async => tempDir,
    );

    expect(await store.isInstalled(_singleVoiceSpec), isFalse);

    final String installDir = p.join(tempDir.path, _singleVoiceSpec.id);
    await File(p.join(installDir, 'model.onnx')).create(recursive: true);
    await File(p.join(installDir, 'tokens.txt')).create(recursive: true);
    await Directory(p.join(installDir, 'espeak-ng-data')).create(recursive: true);

    expect(await store.isInstalled(_singleVoiceSpec), isTrue);

    final TtsInstalledModelPaths paths = await store.paths(_singleVoiceSpec);
    expect(paths.voices, isNull);
    expect(paths.model, p.join(installDir, 'model.onnx'));
  });
}
