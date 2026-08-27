import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart';
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

  test(
    'routes an explicitly bound text edit through the live transaction',
    () async {
      final liveSession = _FakeLivePdfiumSession();
      final native = _NativePort();
      final gateway = BridgeEditorSessionGateway.forTest(
        openBridgeSession: (_, {String? projectRoot}) async =>
            EditorBridgeSession.forTest(native),
        openLivePdfiumSession: (_) async => liveSession,
      );
      await gateway.open('fixture.pdf');
      gateway.registerLivePdfiumBinding(
        objectId: _objectId,
        sourceKey: 'manifest/page/1/object/0',
        sourceRevision: 'source',
        locator: const EditorPhysicalLocator(
          pageNumber: 1,
          objectPath: <int>[0],
          objectType: 'text',
          sourceFingerprint: 'source',
          objectRevision: 0,
        ),
      );

      final result = await gateway.submit(
        const EditorCommandRequest(
          commandId: _commandId,
          baseRevision: 0,
          payload: EditorCommand(
            kind: EditorCommandKind.replaceTextRange,
            objectId: _objectId,
            start: 0,
            end: 6,
            replacement: 'Changed',
          ),
        ),
      );

      expect(native.prepared, isTrue);
      expect(native.published, isTrue);
      expect(native.legacySubmissions, isZero);
      expect(liveSession.appliedPlans, hasLength(1));
      expect(result.committedRevision, 1);
    },
  );

  test('keeps an unbound text edit on the legacy transaction path', () async {
    final liveSession = _FakeLivePdfiumSession();
    final native = _NativePort();
    final gateway = BridgeEditorSessionGateway.forTest(
      openBridgeSession: (_, {String? projectRoot}) async =>
          EditorBridgeSession.forTest(native),
      openLivePdfiumSession: (_) async => liveSession,
    );
    await gateway.open('fixture.pdf');

    await gateway.submit(
      const EditorCommandRequest(
        commandId: _commandId,
        baseRevision: 0,
        payload: EditorCommand(
          kind: EditorCommandKind.replaceTextRange,
          objectId: _objectId,
          start: 0,
          end: 6,
          replacement: 'Changed',
        ),
      ),
    );

    expect(native.prepared, isFalse);
    expect(native.published, isFalse);
    expect(native.legacySubmissions, 1);
    expect(liveSession.appliedPlans, isEmpty);
  });
}

const _commandId = '00000000-0000-4000-8000-000000000010';
const _preparedToken = '00000000-0000-4000-8000-000000000011';
const _objectId = '00000000-0000-4000-8000-000000000012';

final class _FakeLivePdfiumSession implements LivePdfiumSessionOwner {
  final List<String> openedPaths = <String>[];
  final List<LivePdfiumEditPlan> appliedPlans = <LivePdfiumEditPlan>[];
  bool closed = false;

  @override
  Future<LivePdfiumApplyResult> apply(LivePdfiumEditPlan plan) async {
    appliedPlans.add(plan);
    return LivePdfiumApplyResult(
      revision: plan.revision ?? 1,
      invalidations: const <EditorTileInvalidation>[],
    );
  }

  @override
  Future<void> close() async => closed = true;
}

final class _NativePort implements NativeEditorPort, NativeLivePdfiumPort {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  bool prepared = false;
  bool published = false;
  int legacySubmissions = 0;

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
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    legacySubmissions += 1;
    return _result(request.commandId, request.baseRevision);
  }

  @override
  Future<EditorPreparedLiveCommand> prepareLiveCommand(
    EditorCommandRequest request,
  ) async {
    prepared = true;
    return const EditorPreparedLiveCommand(
      token: _preparedToken,
      commandId: _commandId,
      previousRevision: 0,
      committedRevision: 1,
      plan: EditorPhysicalEditPlan(
        previousRevision: 0,
        revision: 1,
        operations: <EditorPhysicalEditOperation>[
          EditorPhysicalEditOperation(
            objectId: _objectId,
            sourceKey: 'manifest/page/1/object/0',
            sourceRevision: 'source',
            expectedText: 'Before',
            replacement: 'Changed',
            bounds: EditorPdfBox(left: 0, bottom: 0, right: 1, top: 1),
          ),
        ],
        inverseOperations: <EditorPhysicalEditOperation>[],
      ),
    );
  }

  @override
  Future<EditorCommandResult> publishPreparedLiveCommand(String token) async {
    published = true;
    return _result(_commandId, 0);
  }

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

  EditorCommandResult _result(String commandId, int baseRevision) =>
      EditorCommandResult(
        commandId: commandId,
        previousRevision: baseRevision,
        committedRevision: baseRevision + 1,
        durable: true,
        warnings: const <String>[],
        objectPatches: const <EditorObjectPatch>[],
      );
}
