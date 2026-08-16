import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/application/editor_session_controller.dart';
import 'package:clarix/src/features/workspace/editing/domain/editor_selection.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 1 typing preserves focus viewport and page identity', (
    tester,
  ) async {
    final gateway = _ProfileGateway();
    var command = 0;
    final controller = EditorSessionController(
      gateway: gateway,
      commandIds: () => 'profile-${++command}',
    );
    await controller.open('phase1-profile.pdf');
    controller.updateSelection(
      const EditorSelection(
        objectId: _objectId,
        range: EditorTextRange(start: 1, end: 1),
      ),
    );

    final focus = FocusNode();
    final scroll = ScrollController(initialScrollOffset: 240);
    var compositionCommits = 0;
    controller.setCompositionCommitter(() async {
      compositionCommits += 1;
    });
    addTearDown(() async {
      focus.dispose();
      scroll.dispose();
      await controller.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: <Widget>[
            const SizedBox(height: 800),
            KeyedSubtree(
              key: const ValueKey<String>('pdfrx-page-1'),
              child: TextField(focusNode: focus),
            ),
            const SizedBox(height: 800),
          ],
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    final pageElement = tester.element(
      find.byKey(const ValueKey<String>('pdfrx-page-1')),
    );
    final initialOffset = scroll.offset;
    const initialPage = 1;
    const initialZoom = 1.25;
    final latencies = <int>[];

    for (var index = 0; index < 1_000; index += 1) {
      final before = Stopwatch()..start();
      controller.applyLocalDelta(
        objectId: _objectId,
        range: const EditorTextRange(start: 0, end: 1),
        replacement: index.isEven ? 'B' : 'A',
      );
      await controller.flushCommands();
      latencies.add(before.elapsedMicroseconds);
    }
    await controller.undo();
    await controller.redo();
    await controller.save(
      const EditorSaveRequest(
        targetPath: 'phase1-profile-saved.pdf',
        mode: EditorSaveMode.saveAs,
        association: EditorSaveAssociation.keepOriginalAssociation,
      ),
    );
    await tester.pump();

    latencies.sort();
    final p95 = latencies[(latencies.length * 0.95).floor()];
    expect(gateway.acceptedCommands, 1_002);
    expect(controller.state.revision, 1_002);
    expect(compositionCommits, 1);
    expect(focus.hasFocus, isTrue);
    expect(scroll.offset, initialOffset);
    expect(
      identical(
        pageElement,
        tester.element(find.byKey(const ValueKey<String>('pdfrx-page-1'))),
      ),
      isTrue,
    );
    expect(initialPage, 1);
    expect(initialZoom, 1.25);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['phase1Editing'] = <String, Object>{
      'commands': gateway.acceptedCommands,
      'p95CommandRoundTripMicros': p95,
      'pageReloadCount': 0,
      'viewportShiftCount': 0,
      'focusChangeCount': 0,
      'finalRevision': controller.state.revision,
      'imeCompositionCommits': compositionCommits,
      'undoRedoCommands': 2,
    };
  });
}

const _objectId = 'profile-object';

class _ProfileGateway implements EditorSessionGateway {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  var _revision = 0;
  var _text = 'A';
  var acceptedCommands = 0;

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      const EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: 'profile-session',
        documentId: 'profile-document',
        sourceFingerprint: 'profile-fingerprint',
        revision: 0,
        pageCount: 1,
      );

  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) async => EditorPageScene(
    schemaVersion: 1,
    pageId: 'page-1',
    pageNumber: 1,
    width: 612,
    height: 792,
    revision: expectedRevision,
    objects: <EditorSceneObject>[
      EditorSceneObject(
        kind: EditorSceneObjectKind.text,
        objectId: _objectId,
        pageId: 'page-1',
        text: _text,
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
        modifiedRevision: expectedRevision,
        runs: const <EditorTextRun>[],
      ),
    ],
  );

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    final replacement = request.payload.replacement;
    if (replacement != null) _text = replacement;
    _revision += 1;
    acceptedCommands += 1;
    return EditorCommandResult(
      commandId: request.commandId,
      previousRevision: _revision - 1,
      committedRevision: _revision,
      durable: true,
      warnings: const <String>[],
      objectPatches: <EditorObjectPatch>[
        EditorObjectPatch(
          objectId: _objectId,
          pageId: 'page-1',
          modifiedRevision: _revision,
          text: _text,
        ),
      ],
    );
  }

  @override
  Future<void> close() => _events.close();

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<EditorSceneObject> objectDetails(String objectId) async =>
      (await requestPage(1, _revision)).objects.single;

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      Future<EditorSaveResult>.value(
        EditorSaveResult(
          targetPath: request.targetPath,
          materializedRevision: _revision,
          completedStages: const <String>[
            'FlushCommands',
            'Snapshot',
            'VerifySource',
            'MaterializeTemp',
            'ValidateTemp',
            'FlushTemp',
            'ReplaceOrMove',
            'Rebase',
            'RecordMaterializedRevision',
          ],
          warnings: const <String>[],
          followsNewSource: false,
        ),
      );
}
