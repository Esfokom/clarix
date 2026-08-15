import 'dart:async';

import 'editor_session_controller.dart';
import '../domain/editor_document_state.dart';
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
  final Map<String, StreamSubscription<EditorDocumentState>> _subscriptions =
      <String, StreamSubscription<EditorDocumentState>>{};
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );

  Iterable<String> get tabIds => _sessions.keys;

  EditorSessionController? operator [](String tabId) => _sessions[tabId];

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
    final controller = EditorSessionController(
      gateway: _gateways(),
      commandIds: _commandIds,
    );
    _sessions[tabId] = controller;
    try {
      await controller.open(sourcePath);
      _subscriptions[tabId] = controller.changes.listen(
        (_) => _changes.add(tabId),
      );
      _changes.add(tabId);
      return controller;
    } catch (_) {
      _sessions.remove(tabId);
      await controller.close();
      rethrow;
    }
  }

  Future<void> close(String tabId) async {
    final controller = _sessions[tabId];
    if (controller == null) return;
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
