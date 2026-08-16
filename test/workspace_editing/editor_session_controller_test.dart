import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/application/editor_session_controller.dart';
import 'package:clarix/src/features/workspace/editing/domain/editor_selection.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'optimistic text paints immediately and matching patch reconciles',
    () async {
      final gateway = FakeEditorSessionGateway();
      final controller = _controller(gateway);
      await controller.open('fixture.pdf');

      controller.applyLocalDelta(
        objectId: objectId,
        range: const EditorTextRange(start: 0, end: 6),
        replacement: 'After',
      );

      expect(controller.state.visibleText(objectId), 'After');
      expect(gateway.pendingSubmitCount, 1);
      gateway.completeSubmit(
        commandId: 'command-1',
        revision: 1,
        text: 'After',
      );
      await pumpEventQueue();

      expect(controller.state.revision, 1);
      expect(controller.state.optimisticEdit, isNull);
      expect(controller.state.visibleText(objectId), 'After');
      await controller.close();
    },
  );

  test(
    'keeps at most one coalesced command behind the active submit',
    () async {
      final gateway = FakeEditorSessionGateway();
      final controller = _controller(gateway);
      await controller.open('fixture.pdf');

      controller.applyLocalDelta(
        objectId: objectId,
        range: const EditorTextRange(start: 0, end: 6),
        replacement: 'First',
      );
      controller.applyLocalDelta(
        objectId: objectId,
        range: const EditorTextRange(start: 0, end: 5),
        replacement: 'Second',
      );
      controller.applyLocalDelta(
        objectId: objectId,
        range: const EditorTextRange(start: 0, end: 6),
        replacement: 'Latest',
      );

      expect(gateway.pendingSubmitCount, 1);
      expect(controller.state.visibleText(objectId), 'Latest');
      gateway.completeSubmit(
        commandId: 'command-1',
        revision: 1,
        text: 'First',
      );
      await pumpEventQueue();
      expect(gateway.pendingSubmitCount, 1);
      expect(gateway.pending.single.commandId, 'command-3');

      gateway.completeSubmit(
        commandId: 'command-3',
        revision: 2,
        text: 'Latest',
      );
      await pumpEventQueue();
      expect(controller.state.visibleText(objectId), 'Latest');
      await controller.close();
    },
  );

  test(
    'revision rejection rolls back, preserves selection, and refreshes',
    () async {
      final gateway = FakeEditorSessionGateway();
      final controller = _controller(gateway);
      await controller.open('fixture.pdf');

      controller.applyLocalDelta(
        objectId: objectId,
        range: const EditorTextRange(start: 0, end: 6),
        replacement: 'After',
      );
      gateway.rejectSubmit(Exception('revision_conflict: stale base revision'));
      await pumpEventQueue();

      expect(controller.state.visibleText(objectId), 'Before');
      expect(controller.state.selection?.range.start, 5);
      expect(controller.state.errorCode, 'revision_conflict');
      expect(gateway.pageRequests, 2);
      await controller.close();
    },
  );

  for (final code in <String>['text_overflow']) {
    test(
      '$code rolls back optimistic text without refreshing the page',
      () async {
        final gateway = FakeEditorSessionGateway();
        final controller = _controller(gateway);
        await controller.open('fixture.pdf');

        controller.applyLocalDelta(
          objectId: objectId,
          range: const EditorTextRange(start: 0, end: 6),
          replacement: 'Rejected',
        );
        expect(controller.state.visibleText(objectId), 'Rejected');
        gateway.rejectSubmit(Exception('$code: rejected before durability'));
        await pumpEventQueue();

        expect(controller.state.visibleText(objectId), 'Before');
        expect(controller.state.errorCode, code);
        expect(controller.state.revision, 0);
        expect(gateway.pageRequests, 1);
        await controller.close();
      },
    );
  }

  test(
    'font fallback remains inert until its one-time proposal is approved',
    () async {
      final gateway = FakeEditorSessionGateway();
      final controller = _controller(gateway);
      await controller.open('fixture.pdf');

      controller.applyLocalDelta(
        objectId: objectId,
        range: const EditorTextRange(start: 0, end: 6),
        replacement: '€',
      );
      gateway.rejectSubmit(
        Exception('font_fallback_required: approval required'),
      );
      await pumpEventQueue();

      expect(controller.state.revision, 0);
      expect(controller.state.visibleText(objectId), 'Before');
      expect(controller.state.fontFallbackProposal?.token, 'proposal-1');
      expect(gateway.proposedReplacement, '€');

      await controller.approveFontFallback('proposal-1');

      expect(controller.state.revision, 1);
      expect(controller.state.visibleText(objectId), '€');
      expect(controller.state.fontFallbackProposal, isNull);
      expect(gateway.approvedProposalToken, 'proposal-1');
      await controller.close();
    },
  );

  test('discards a result for a different command id', () async {
    final gateway = FakeEditorSessionGateway();
    final controller = _controller(gateway);
    await controller.open('fixture.pdf');
    controller.applyLocalDelta(
      objectId: objectId,
      range: const EditorTextRange(start: 0, end: 6),
      replacement: 'After',
    );

    gateway.completeSubmit(
      commandId: 'stale-command',
      revision: 1,
      text: 'Stale',
    );
    await pumpEventQueue();

    expect(controller.state.revision, 0);
    expect(controller.state.visibleText(objectId), 'After');
    await controller.close();
  });

  test(
    'lagged events refresh loaded scenes and close unsubscribes first',
    () async {
      final order = <String>[];
      final gateway = FakeEditorSessionGateway(order: order);
      final controller = _controller(gateway);
      await controller.open('fixture.pdf');

      gateway.emit(
        const EditorEvent.lagged(
          sessionId: sessionId,
          sequence: 2,
          latestRevision: 1,
        ),
      );
      await pumpEventQueue();
      expect(gateway.pageRequests, 2);

      await controller.close();
      expect(order, <String>['unsubscribe', 'gateway-close']);
    },
  );
}

const sessionId = 'session-1';
const objectId = 'object-1';

EditorSessionController _controller(FakeEditorSessionGateway gateway) {
  var next = 0;
  return EditorSessionController(
    gateway: gateway,
    commandIds: () => 'command-${++next}',
  );
}

class FakeEditorSessionGateway implements EditorSessionGateway {
  FakeEditorSessionGateway({this.order}) {
    _events = StreamController<EditorEvent>.broadcast(
      sync: true,
      onCancel: () => order?.add('unsubscribe'),
    );
  }

  final List<String>? order;
  late final StreamController<EditorEvent> _events;
  final List<EditorCommandRequest> pending = <EditorCommandRequest>[];
  final List<Completer<EditorCommandResult>> _completers =
      <Completer<EditorCommandResult>>[];
  int pageRequests = 0;
  String? proposedReplacement;
  String? approvedProposalToken;

  int get pendingSubmitCount => pending.length;

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      const EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: sessionId,
        documentId: 'document-1',
        sourceFingerprint: 'fingerprint',
        revision: 0,
        pageCount: 1,
      );

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async {
    pageRequests++;
    return _scene(expectedRevision);
  }

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) {
    pending.add(request);
    final completer = Completer<EditorCommandResult>();
    _completers.add(completer);
    return completer.future.whenComplete(() {
      final index = _completers.indexOf(completer);
      if (index >= 0) {
        _completers.removeAt(index);
        pending.removeAt(index);
      }
    });
  }

  @override
  Future<EditorFontFallbackProposal> proposeFontFallback({
    required int baseRevision,
    required String objectId,
    required int start,
    required int end,
    required String replacement,
  }) async {
    proposedReplacement = replacement;
    return EditorFontFallbackProposal(
      token: 'proposal-1',
      objectId: objectId,
      fontName: 'Arial',
      source: 'installed',
      embeddingAllowed: true,
      affectedCharacters: '€',
    );
  }

  @override
  Future<EditorCommandResult> approveFontFallback({
    required String commandId,
    required int baseRevision,
    required String proposalToken,
  }) async {
    approvedProposalToken = proposalToken;
    return EditorCommandResult(
      commandId: commandId,
      previousRevision: baseRevision,
      committedRevision: baseRevision + 1,
      durable: true,
      warnings: const <String>[],
      objectPatches: <EditorObjectPatch>[
        EditorObjectPatch(
          objectId: objectId,
          pageId: 'page-1',
          modifiedRevision: baseRevision + 1,
          text: proposedReplacement,
        ),
      ],
    );
  }

  void completeSubmit({
    required String commandId,
    required int revision,
    required String text,
  }) {
    _completers.first.complete(
      EditorCommandResult(
        commandId: commandId,
        previousRevision: revision - 1,
        committedRevision: revision,
        durable: true,
        warnings: const <String>[],
        objectPatches: <EditorObjectPatch>[
          EditorObjectPatch(
            objectId: objectId,
            pageId: 'page-1',
            modifiedRevision: revision,
            text: text,
          ),
        ],
      ),
    );
  }

  void rejectSubmit(Object error) => _completers.first.completeError(error);

  void emit(EditorEvent event) => _events.add(event);

  @override
  Future<EditorSceneObject> objectDetails(String objectId) async =>
      _scene(0).objects.single;

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {
    order?.add('gateway-close');
    await _events.close();
  }
}

EditorPageScene _scene(int revision) => EditorPageScene(
  schemaVersion: 1,
  pageId: 'page-1',
  pageNumber: 1,
  width: 612,
  height: 792,
  revision: revision,
  objects: <EditorSceneObject>[
    EditorSceneObject(
      kind: EditorSceneObjectKind.text,
      objectId: objectId,
      pageId: 'page-1',
      text: 'Before',
      bounds: const EditorPdfBox(left: 0, bottom: 0, right: 100, top: 20),
      transform: const EditorAffineTransform(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        e: 0,
        f: 0,
      ),
      capability: 'editable',
      modifiedRevision: revision,
      runs: const <EditorTextRun>[],
    ),
  ],
);
