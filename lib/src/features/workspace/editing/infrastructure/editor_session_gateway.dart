import '../../../../core/editing/editor_bridge.dart';
import '../../../../core/editing/editor_bridge_types.dart';

abstract class EditorSessionGateway {
  Stream<EditorEvent> get events;

  Future<EditorSessionMetadata> open(String sourcePath);

  Future<EditorPageScene> requestPage(int pageNumber, int expectedRevision);

  Future<EditorCommandResult> submit(EditorCommandRequest request);

  Future<EditorSceneObject> objectDetails(String objectId);

  Future<void> close();
}

class BridgeEditorSessionGateway implements EditorSessionGateway {
  factory BridgeEditorSessionGateway({
    EditorBridge bridge = const EditorBridge(),
  }) => BridgeEditorSessionGateway._(bridge);

  BridgeEditorSessionGateway._(this._bridge);

  final EditorBridge _bridge;
  EditorBridgeSession? _session;

  @override
  Stream<EditorEvent> get events =>
      _session?.events ?? const Stream<EditorEvent>.empty();

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async {
    _session = await _bridge.open(sourcePath);
    return _session!.metadata();
  }

  @override
  Future<EditorPageScene> requestPage(int pageNumber, int expectedRevision) =>
      _required().pageScene(
        pageNumber: pageNumber,
        expectedRevision: expectedRevision,
      );

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      _required().submit(request);

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      _required().objectDetails(objectId);

  @override
  Future<void> close() async {
    final session = _session;
    _session = null;
    await session?.close();
  }

  EditorBridgeSession _required() =>
      _session ?? (throw StateError('editor session is not open'));
}
