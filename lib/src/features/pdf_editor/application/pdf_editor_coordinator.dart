import '../../../core/agent/agent_bridge.dart';
import '../domain/editor_save_state.dart';
import 'editor_session_controller.dart';
import 'editor_session_registry.dart';

/// Workspace-facing façade for per-tab native editor lifecycle and state.
class PdfEditorCoordinator {
  const PdfEditorCoordinator(this.registry);

  final EditorSessionRegistry registry;

  EditorSessionController? controllerFor(String tabId) => registry[tabId];

  AgentBridgeSession? agentBridgeFor(String tabId) =>
      registry.agentBridge(tabId);

  bool hasUnsavedEdits(String tabId) =>
      registry[tabId]?.state.save.phase != EditorSavePhase.clean;

  Future<EditorSessionController> open({
    required String tabId,
    required String sourcePath,
  }) => registry.open(tabId: tabId, sourcePath: sourcePath);

  Future<EditorSessionController> reopen({
    required String tabId,
    required String sourcePath,
  }) => registry.reopen(tabId: tabId, sourcePath: sourcePath);

  Future<void> checkpointAll({String label = 'Workspace checkpoint'}) async {
    for (final String tabId in registry.tabIds.toList(growable: false)) {
      await registry[tabId]?.createCheckpoint(label);
    }
  }

  Future<void> close(String tabId) => registry.close(tabId);
}
