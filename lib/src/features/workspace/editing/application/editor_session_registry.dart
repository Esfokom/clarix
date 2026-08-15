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

  Iterable<String> get tabIds => _sessions.keys;

  EditorSessionController? operator [](String tabId) => _sessions[tabId];

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
    await controller.close();
    _sessions.remove(tabId);
  }

  Future<void> closeAll() async {
    for (final tabId in _sessions.keys.toList(growable: false)) {
      await close(tabId);
    }
  }
}
