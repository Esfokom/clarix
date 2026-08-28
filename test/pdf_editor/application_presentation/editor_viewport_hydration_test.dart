import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'visible hydration failure surfaces page_scene_failed in state',
    () async {
      final gateway = HydrationGateway();
      final controller = EditorSessionController(
        gateway: gateway,
        commandIds: () => 'command-1',
      );
      await controller.open('fixture.pdf');
      expect(controller.state.errorCode, isNull);

      gateway.failPageRequests = true;
      await controller.refreshPage(
        1,
        priority: EditorViewportPriority.visible,
        force: true,
      );

      expect(controller.state.errorCode, 'page_scene_failed');
      await controller.close();
    },
  );

  test(
    'preload hydration failure is logged without surfacing an error',
    () async {
      final gateway = HydrationGateway();
      final controller = EditorSessionController(
        gateway: gateway,
        commandIds: () => 'command-1',
      );
      await controller.open('fixture.pdf');

      gateway.failPageRequests = true;
      await controller.refreshPage(
        1,
        priority: EditorViewportPriority.preload,
        force: true,
      );

      expect(controller.state.errorCode, isNull);
      await controller.close();
    },
  );

  test(
    'updateViewport retries a failed visible page once the gateway recovers',
    () async {
      final gateway = HydrationGateway()..failPageRequests = true;
      final controller = EditorSessionController(
        gateway: gateway,
        commandIds: () => 'command-1',
      );
      await controller.open('fixture.pdf');
      await pumpEventQueue();

      expect(controller.state.errorCode, 'page_scene_failed');
      expect(controller.state.scenes[1], isNull);

      // Fires refreshPage un-awaited; a leaked async error fails the test.
      controller.updateViewport(<int>{1});
      await pumpEventQueue();
      expect(controller.state.errorCode, 'page_scene_failed');
      expect(controller.state.scenes[1], isNull);

      gateway.failPageRequests = false;
      controller.updateViewport(<int>{1});
      await pumpEventQueue();

      expect(controller.state.scenes[1], isNotNull);
      expect(controller.state.scenes[1]!.pageNumber, 1);
      await controller.close();
    },
  );
}

class HydrationGateway implements EditorSessionGateway {
  HydrationGateway({this.pageCount = 1});

  final int pageCount;
  bool failPageRequests = false;
  int pageRequests = 0;

  @override
  Stream<EditorEvent> get events => const Stream<EditorEvent>.empty();

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: 'session-1',
        documentId: 'document-1',
        sourceFingerprint: 'fingerprint',
        revision: 0,
        pageCount: pageCount,
      );

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async {
    pageRequests++;
    if (failPageRequests) {
      throw Exception('page_scene_failed: hydration failure on page $pageNumber');
    }
    return EditorPageScene(
      schemaVersion: 1,
      pageId: 'page-$pageNumber',
      pageNumber: pageNumber,
      width: 612,
      height: 792,
      revision: expectedRevision,
      objects: const <EditorSceneObject>[],
    );
  }

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      throw UnimplementedError();

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      throw UnimplementedError();

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<void> close() async {}
}
