import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNativeEditorPort implements NativeEditorPort {
  FakeNativeEditorPort({this.schemaVersion = 1});

  final int schemaVersion;
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast(sync: true);
  int closeCount = 0;

  void emit(EditorEvent event) => _events.add(event);

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<EditorSessionMetadata> metadata() async => EditorSessionMetadata(
    schemaVersion: schemaVersion,
    sessionId: '00000000-0000-4000-8000-000000000001',
    documentId: '00000000-0000-4000-8000-000000000002',
    sourceFingerprint: 'sha256',
    revision: 0,
    pageCount: 1,
  );

  @override
  Future<EditorPageScene> pageScene({
    required int pageNumber,
    required int expectedRevision,
    required EditorViewportPriority priority,
  }) async => EditorPageScene(
    schemaVersion: schemaVersion,
    pageId: '00000000-0000-4000-8000-000000000003',
    pageNumber: pageNumber,
    width: 612,
    height: 792,
    revision: expectedRevision,
    objects: const <EditorSceneObject>[],
  );

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) async =>
      EditorCommandResult(
        schemaVersion: schemaVersion,
        commandId: request.commandId,
        previousRevision: request.baseRevision,
        committedRevision: request.baseRevision + 1,
        durable: true,
        warnings: const <String>[],
        objectPatches: const <EditorObjectPatch>[],
      );

  @override
  Future<EditorSceneObject> objectDetails(String objectId) async =>
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
  }) => submit(
    EditorCommandRequest(
      commandId: '00000000-0000-4000-8000-000000000004',
      baseRevision: baseRevision,
      payload: EditorCommand(
        kind: EditorCommandKind.createCheckpoint,
        label: label,
      ),
    ),
  );
}

class FakePhaseTwoPort extends FakeNativeEditorPort
    implements NativePhaseTwoPort {
  EditorAnnotation? annotation;

  @override
  Future<EditorSearchResult> search(EditorSearchRequest request) async =>
      EditorSearchResult(
        schemaVersion: schemaVersion,
        revision: request.expectedRevision,
        matches: const <EditorSearchMatch>[
          EditorSearchMatch(
            objectId: '00000000-0000-4000-8000-000000000010',
            pageId: '00000000-0000-4000-8000-000000000011',
            pageNumber: 1,
            startUtf16: 0,
            endUtf16: 5,
            quotedText: 'hello',
          ),
        ],
        totalMatches: 1,
        indexedPages: 1,
        pageCount: 1,
        isComplete: true,
      );

  @override
  Future<EditorSelectionSet> validateSelection(
    EditorSelectionSet selection,
  ) async => selection;

  @override
  Future<EditorCompatibilityReport> compatibilityReport(
    int expectedRevision,
  ) async => EditorCompatibilityReport(
    schemaVersion: schemaVersion,
    revision: expectedRevision,
    editableCount: 1,
    overlayOnlyCount: 0,
    readOnlyCount: 0,
    issues: const <EditorCompatibilityIssue>[],
  );

  @override
  Future<void> reportMemoryPressure(EditorMemoryPressureLevel level) async {}

  @override
  Future<EditorAnnotation> annotationDetails(String objectId) async =>
      annotation!;

  @override
  Future<EditorCommandResult> createAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  }) async {
    this.annotation = annotation;
    return _annotationResult(commandId, baseRevision);
  }

  @override
  Future<EditorCommandResult> updateAnnotation({
    required String commandId,
    required int baseRevision,
    required EditorAnnotation annotation,
  }) async {
    this.annotation = annotation;
    return _annotationResult(commandId, baseRevision);
  }

  @override
  Future<EditorCommandResult> deleteAnnotation({
    required String commandId,
    required int baseRevision,
    required String objectId,
  }) async {
    annotation = null;
    return EditorCommandResult(
      schemaVersion: schemaVersion,
      commandId: commandId,
      previousRevision: baseRevision,
      committedRevision: baseRevision + 1,
      durable: true,
      warnings: const <String>[],
      objectPatches: const <EditorObjectPatch>[],
      removedObjectIds: <String>[objectId],
    );
  }

  EditorCommandResult _annotationResult(String commandId, int baseRevision) =>
      EditorCommandResult(
        schemaVersion: schemaVersion,
        commandId: commandId,
        previousRevision: baseRevision,
        committedRevision: baseRevision + 1,
        durable: true,
        warnings: const <String>[],
        objectPatches: const <EditorObjectPatch>[],
      );
}

const _sessionId = '00000000-0000-4000-8000-000000000001';

void main() {
  test('preserves a recursive physical locator and dirty tile identity', () {
    const locator = EditorPhysicalLocator(
      pageNumber: 4,
      objectPath: <int>[5, 12, 3],
      objectType: 'text',
      sourceFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      objectRevision: 7,
    );
    const tile = EditorDirtyTile(
      pageNumber: 4,
      revision: 7,
      bounds: EditorPdfBox(left: 12, bottom: 24, right: 48, top: 72),
      width: 72,
      height: 96,
      rgbaBytes: <int>[0, 1, 2, 3],
    );

    expect(locator.objectPath, <int>[5, 12, 3]);
    expect(locator.objectRevision, 7);
    expect(tile.revision, locator.objectRevision);
    expect(tile.rgbaBytes, <int>[0, 1, 2, 3]);
  });

  test('editor bridge rejects requests and events after close', () async {
    final native = FakeNativeEditorPort();
    final session = EditorBridgeSession.forTest(native);
    final events = <EditorEvent>[];
    final subscription = session.events.listen(events.add);
    native.emit(
      const EditorEvent.ready(sessionId: _sessionId, sequence: 1, revision: 0),
    );

    await session.close();
    native.emit(
      const EditorEvent.commandCommitted(
        sessionId: _sessionId,
        sequence: 2,
        revision: 1,
        commandId: 'late',
      ),
    );

    await expectLater(session.metadata(), throwsA(isA<EditorSessionClosed>()));
    expect(events, <EditorEvent>[
      const EditorEvent.ready(sessionId: _sessionId, sequence: 1, revision: 0),
    ]);
    expect(native.closeCount, 1);
    await session.close();
    expect(native.closeCount, 1);
    await subscription.cancel();
  });

  test('editor bridge rejects unsupported schema versions', () async {
    final session = EditorBridgeSession.forTest(
      FakeNativeEditorPort(schemaVersion: 2),
    );
    await expectLater(
      session.metadata(),
      throwsA(isA<EditorProtocolViolation>()),
    );
    await session.close();
  });

  test(
    'editor bridge reports duplicate and decreasing event sequences',
    () async {
      final native = FakeNativeEditorPort();
      final session = EditorBridgeSession.forTest(native);
      final events = <EditorEvent>[];
      final errors = <Object>[];
      final subscription = session.events.listen(
        events.add,
        onError: (Object error) => errors.add(error),
      );

      native.emit(
        const EditorEvent.ready(
          sessionId: _sessionId,
          sequence: 2,
          revision: 0,
        ),
      );
      native.emit(
        const EditorEvent.ready(
          sessionId: _sessionId,
          sequence: 1,
          revision: 0,
        ),
      );
      native.emit(
        const EditorEvent.ready(
          sessionId: _sessionId,
          sequence: 2,
          revision: 0,
        ),
      );

      expect(events, <EditorEvent>[
        const EditorEvent.ready(
          sessionId: _sessionId,
          sequence: 2,
          revision: 0,
        ),
      ]);
      expect(errors, hasLength(2));
      expect(errors, everyElement(isA<EditorProtocolViolation>()));
      await session.close();
      await subscription.cancel();
    },
  );

  test('editor bridge exposes revisioned Phase 2 workflows', () async {
    final native = FakePhaseTwoPort();
    final session = EditorBridgeSession.forTest(native);
    final search = await session.search(
      const EditorSearchRequest(expectedRevision: 0, query: 'hello'),
    );
    expect(search.matches.single.quotedText, 'hello');
    expect((await session.compatibilityReport(0)).editableCount, 1);

    final annotation = const EditorAnnotation(
      objectId: '00000000-0000-4000-8000-000000000020',
      pageId: '00000000-0000-4000-8000-000000000021',
      bounds: EditorPdfBox(left: 1, bottom: 2, right: 3, top: 4),
      kind: EditorAnnotationKind.comment,
      anchorKind: EditorAnnotationAnchorKind.pagePoint,
      anchorX: 1,
      anchorY: 2,
      body: 'Review this',
    );
    final created = await session.createAnnotation(
      commandId: '00000000-0000-4000-8000-000000000022',
      baseRevision: 0,
      annotation: annotation,
    );
    expect(created.committedRevision, 1);
    expect(
      (await session.annotationDetails(annotation.objectId)).body,
      'Review this',
    );
    final deleted = await session.deleteAnnotation(
      commandId: '00000000-0000-4000-8000-000000000023',
      baseRevision: 1,
      objectId: annotation.objectId,
    );
    expect(deleted.removedObjectIds, <String>[annotation.objectId]);
    await session.close();
  });
}
