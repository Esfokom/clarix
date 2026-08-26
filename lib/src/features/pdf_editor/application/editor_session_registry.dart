import 'dart:async';

import '../../../core/agent/agent_bridge.dart';
import '../domain/editor_document_state.dart';
import 'editor_session_controller.dart';
import '../infrastructure/editor_session_gateway.dart';

typedef EditorGatewayFactory = EditorSessionGateway Function();

class EditorSessionRegistry {
  factory EditorSessionRegistry({
    required EditorGatewayFactory gateways,
    required EditorCommandIdFactory commandIds,
  }) => EditorSessionRegistry._(gateways, commandIds);

  EditorSessionRegistry._(this._gateways, this._commandIds);

  final EditorGatewayFactory _gateways;
  final EditorCommandIdFactory _commandIds;
  final Map<String, EditorSessionController> _sessions =
      <String, EditorSessionController>{};
  final Map<String, AgentBridgeSession> _agentBridges =
      <String, AgentBridgeSession>{};
  final Map<String, StreamSubscription<EditorDocumentState>> _subscriptions =
      <String, StreamSubscription<EditorDocumentState>>{};
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );

  Iterable<String> get tabIds => _sessions.keys;

  EditorSessionController? operator [](String tabId) => _sessions[tabId];
  AgentBridgeSession? agentBridge(String tabId) => _agentBridges[tabId];

  Stream<AgentBridgeSession?> watchAgentBridge(String tabId) =>
      Stream<AgentBridgeSession?>.multi((controller) {
        controller.add(_agentBridges[tabId]);
        final subscription = _changes.stream
            .where((changedTabId) => changedTabId == tabId)
            .listen((_) => controller.add(_agentBridges[tabId]));
        controller.onCancel = subscription.cancel;
      }, isBroadcast: true);

  Stream<EditorDocumentState?> watch(String tabId) async* {
    yield _sessions[tabId]?.state;
    await for (final changedTabId in _changes.stream) {
      if (changedTabId == tabId) yield _sessions[tabId]?.state;
    }
  }

  Future<EditorSessionController> open({
    required String tabId,
    required String sourcePath,
  }) async {
    final existing = _sessions[tabId];
    if (existing != null) return existing;
    final gateway = _gateways();
    final controller = EditorSessionController(
      gateway: gateway,
      commandIds: _commandIds,
    );
    _sessions[tabId] = controller;
    try {
      await controller.open(sourcePath);
      if (gateway is EditorAgentGateway) {
        _agentBridges[tabId] = (gateway as EditorAgentGateway)
            .agentBridgeSession();
      }
      _subscriptions[tabId] = controller.changes.listen(
        (_) => _changes.add(tabId),
      );
      _changes.add(tabId);
      return controller;
    } catch (_) {
      _sessions.remove(tabId);
      await _agentBridges.remove(tabId)?.close();
      await controller.close();
      rethrow;
    }
  }

  Future<void> close(String tabId) async {
    final controller = _sessions[tabId];
    if (controller == null) return;
    await _agentBridges.remove(tabId)?.close();
    await _subscriptions.remove(tabId)?.cancel();
    await controller.close();
    _sessions.remove(tabId);
    _changes.add(tabId);
  }

  Future<EditorSessionController> reopen({
    required String tabId,
    required String sourcePath,
  }) async {
    await close(tabId);
    return open(tabId: tabId, sourcePath: sourcePath);
  }

  Future<void> closeAll() async {
    for (final tabId in _sessions.keys.toList(growable: false)) {
      await close(tabId);
    }
    await _changes.close();
  }
}
