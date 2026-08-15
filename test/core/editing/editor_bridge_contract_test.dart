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

const _sessionId = '00000000-0000-4000-8000-000000000001';

void main() {
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
}
