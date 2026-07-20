import 'package:clarix/src/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy local-model state restores without selecting a remote provider',
    () {
      final AiWorkspaceState restored =
          AiWorkspaceState.fromJson(<String, dynamic>{
            'activeInferenceModelId': 'legacy-local-model',
            'activeEmbeddingModelId': 'legacy-embedding-model',
          });

      expect(restored.selectedProviderId, isNull);
      expect(restored.providerReady, isFalse);
      expect(restored.statusMessage, contains('provider'));
    },
  );
}
