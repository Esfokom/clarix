import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_registry.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owns one controller per tab and closes before removal', () async {
    final gateways = <RegistryGateway>[];
    final registry = EditorSessionRegistry(
      gateways: () {
        final gateway = RegistryGateway();
        gateways.add(gateway);
        return gateway;
      },
      commandIds: () => 'unused',
    );

    final first = await registry.open(tabId: 'tab-1', sourcePath: 'one.pdf');
    final same = await registry.open(tabId: 'tab-1', sourcePath: 'one.pdf');
    await registry.open(tabId: 'tab-2', sourcePath: 'two.pdf');

    expect(identical(first, same), isTrue);
    expect(gateways, hasLength(2));
    final closing = registry.close('tab-1');
    expect(registry['tab-1'], isNotNull);
    await closing;
    expect(gateways.first.closed, isTrue);
    expect(registry['tab-1'], isNull);

    await registry.closeAll();
    expect(registry.tabIds, isEmpty);
    expect(gateways.last.closed, isTrue);
  });
}

class RegistryGateway implements EditorSessionGateway {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  bool closed = false;

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: sourcePath,
        documentId: sourcePath,
        sourceFingerprint: sourcePath,
        revision: 0,
        pageCount: 0,
      );

  @override
  Future<void> close() async {
    await Future<void>.delayed(Duration.zero);
    closed = true;
    await _events.close();
  }

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      throw UnimplementedError();

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) => throw UnimplementedError();

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      throw UnimplementedError();
}
