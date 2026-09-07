import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace panes restore persisted widths within their limits', () {
    final WorkspaceSession restored = WorkspaceSession.fromJson(
      <String, dynamic>{'leftPaneWidth': 100, 'rightPaneWidth': 900},
    );

    expect(restored.leftPaneWidth, 200);
    expect(restored.rightPaneWidth, 480);
    expect(restored.leftPaneCollapsed, isFalse);
    expect(restored.rightPaneCollapsed, isFalse);
  });

  test('right tool window restores and defaults to closed', () {
    expect(
      WorkspaceSession.fromJson(<String, dynamic>{}).rightToolWindow,
      RightToolWindow.none,
    );
    expect(
      WorkspaceSession.fromJson(<String, dynamic>{
        'rightToolWindow': 'ai',
      }).rightToolWindow,
      RightToolWindow.ai,
    );
    expect(
      WorkspaceSession.fromJson(<String, dynamic>{
        'rightToolWindow': 'textFormat',
      }).rightToolWindow,
      RightToolWindow.textFormat,
    );
  });

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
