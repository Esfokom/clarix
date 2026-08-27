import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owns and closes the matching live PDFium session', () async {
    final liveSession = _FakeLivePdfiumSession();
    final gateway = BridgeEditorSessionGateway.forTest(
      openBridgeSession: (_, {String? projectRoot}) async =>
          EditorBridgeSession.forTest(_NativePort()),
      openLivePdfiumSession: (sourcePath) async {
        liveSession.openedPaths.add(sourcePath);
        return liveSession;
      },
    );

    await gateway.open('fixture.pdf');
    expect(liveSession.openedPaths, <String>['fixture.pdf']);
    expect(gateway.hasLivePdfiumSession, isTrue);
    expect(gateway.hasLivePdfiumLocatorRegistry, isTrue);

    await gateway.close();
    expect(liveSession.closed, isTrue);
    expect(gateway.hasLivePdfiumSession, isFalse);
    expect(gateway.hasLivePdfiumLocatorRegistry, isFalse);
  });

  test('closes the live session if semantic opening fails', () async {
    final liveSession = _FakeLivePdfiumSession();
    final gateway = BridgeEditorSessionGateway.forTest(
      openBridgeSession: (_, {String? projectRoot}) async =>
          throw StateError('semantic session unavailable'),
      openLivePdfiumSession: (sourcePath) async {
        liveSession.openedPaths.add(sourcePath);
        return liveSession;
      },
    );

    await expectLater(gateway.open('fixture.pdf'), throwsStateError);
    expect(liveSession.closed, isTrue);
  });
}

final class _FakeLivePdfiumSession implements LivePdfiumSessionOwner {
  final List<String> openedPaths = <String>[];
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

final class _NativePort implements NativeEditorPort {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<void> close() => _events.close();

  @override
  Future<EditorSessionMetadata> metadata() async => const EditorSessionMetadata(
    schemaVersion: 1,
    sessionId: '00000000-0000-4000-8000-000000000001',
    documentId: '00000000-0000-4000-8000-000000000002',
    sourceFingerprint: 'source',
    revision: 0,
    pageCount: 1,
  );

  @override
  Future<EditorPageScene> pageScene({
    required int pageNumber,
    required int expectedRevision,
    required EditorViewportPriority priority,
  }) => throw UnimplementedError();

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      throw UnimplementedError();

  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      throw UnimplementedError();

  @override
  Future<EditorCleanPatchAsset> cleanPatch({
    required String objectId,
    required int dpi,
  }) => throw UnimplementedError();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<EditorCommandResult> checkpoint({
    required int baseRevision,
    required String label,
  }) => throw UnimplementedError();
}
