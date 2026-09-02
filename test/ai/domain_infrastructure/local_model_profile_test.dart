import 'package:clarix/src/features/ai/domain/local_model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gemma 4 profile persists the LiteRT-LM download identity', () {
    final LocalModelProfile profile = LocalModelProfile.gemma4(
      id: 'local-gemma-4-e2b',
      label: 'Gemma 4 E2B',
      modelFileName: 'gemma-4-E2B-it.litertlm',
    );

    expect(LocalModelProfile.fromJson(profile.toJson()), profile);
    expect(profile.isGemma4, isTrue);
    expect(profile.fileType, LocalModelFileType.litertlm);
    expect(profile.downloadUrl, contains('litert-community'));
  });
}
