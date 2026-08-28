import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_document_state.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/pdf_editor/presentation/page_edit_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping an editable object places a caret selection', (
    tester,
  ) async {
    final gateway = TapGateway();
    final controller = EditorSessionController(
      gateway: gateway,
      commandIds: () => 'command-1',
    );
    addTearDown(controller.close);
    await controller.open('fixture.pdf');

    await tester.pumpWidget(
      MaterialApp(
        home: StreamBuilder<EditorDocumentState>(
          stream: controller.changes,
          initialData: controller.state,
          builder: (context, snapshot) {
            final state = snapshot.data!;
            final scene = state.scenes[1];
            if (scene == null) return const SizedBox.shrink();
            return Material(
              child: SizedBox(
                width: 300,
                height: 200,
                child: PageEditScene(
                  scene: scene,
                  document: state,
                  displaySize: const Size(300, 200),
                  session: controller,
                  editingEnabled: true,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    // The object fills the page bounds, so its interactive region spans the
    // whole scene. Tap at the horizontal middle: 'Abc' anchors land at
    // offsets 0, 1, 2 across the width.
    await tester.tapAt(const Offset(150, 100));
    await tester.pump();
    await tester.pump();

    expect(controller.state.selection, isNotNull);
    expect(controller.state.selection!.objectId, 'object-1');
    expect(controller.state.selection!.range.start, 1);
    expect(find.byKey(const Key('clarix-native-editor')), findsOneWidget);
  });
}

class TapGateway implements EditorSessionGateway {
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
    width: 120,
    height: 20,
    revision: expectedRevision,
    objects: <EditorSceneObject>[
      EditorSceneObject(
        kind: EditorSceneObjectKind.text,
        objectId: 'object-1',
        pageId: 'page-1',
        text: 'Abc',
        bounds: const EditorPdfBox(left: 0, bottom: 0, right: 120, top: 20),
        transform: const EditorAffineTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0),
        capability: 'editable',
        modifiedRevision: 0,
        runs: const <EditorTextRun>[],
      ),
    ],
  );

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
