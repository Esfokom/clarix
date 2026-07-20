import 'package:clarix/src/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Gemma state restores without selecting a remote provider', () {
    final AiWorkspaceState restored = AiWorkspaceState.fromJson(
      <String, dynamic>{
        'activeInferenceModelId': 'gemma-4-e2b-it',
        'activeEmbeddingModelId': 'embedding-gemma-1024',
      },
    );

    expect(restored.selectedProviderId, isNull);
    expect(restored.providerReady, isFalse);
    expect(restored.statusMessage, contains('provider'));
  });
}
