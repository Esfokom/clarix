import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_document_state.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/workspace/editing/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/workspace/editing/presentation/native_text_editor.dart';
import 'package:flutter/material.dart';

const harnessObjectId = 'object-1';

class NativeEditorTestHarness {
  NativeEditorTestHarness({
    this.text = 'one two 👩🏽‍💻',
    this.capability = 'editable',
  }) : gateway = NativeEditorGateway(text: text, capability: capability);

  final String text;
  final String capability;
  final NativeEditorGateway gateway;
  late final EditorSessionController controller;

  Future<void> open({int selectionOffset = 0}) async {
    var command = 0;
    controller = EditorSessionController(
      gateway: gateway,
      commandIds: () => 'command-${++command}',
    );
    await controller.open('fixture.pdf');
    controller.updateSelection(
      EditorSelection(
        objectId: harnessObjectId,
        range: EditorTextRange(start: selectionOffset, end: selectionOffset),
      ),
    );
  }

  Widget widget({VoidCallback? onUndo, VoidCallback? onRedo}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          height: 72,
          child: StreamBuilder<EditorDocumentState>(
            stream: controller.changes,
            initialData: controller.state,
            builder: (context, snapshot) {
              final state = snapshot.data ?? controller.state;
              final selection =
                  state.selection ??
                  const EditorSelection(
                    objectId: harnessObjectId,
                    range: EditorTextRange(start: 0, end: 0),
                  );
              return NativeTextEditor(
                session: controller,
                object: gateway.object,
                text: state.visibleText(harnessObjectId) ?? gateway.text,
                selection: selection,
                onUndo: onUndo,
                onRedo: onRedo,
              );
            },
          ),
        ),
      ),
    ),
  );
}

class NativeEditorGateway
    implements EditorSessionGateway, EditorPhaseTwoGateway {
  NativeEditorGateway({required this.text, required String capability})
    : object = _object(text, capability);

  String text;
  final EditorSceneObject object;
  final List<EditorCommandRequest> requests = <EditorCommandRequest>[];
  final List<String> calls = <String>[];
  Object? saveError;
  EditorAnnotation? annotation;
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      const EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: 'session',
        documentId: 'document',
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
    width: 420,
    height: 72,
    revision: expectedRevision,
    objects: <EditorSceneObject>[object],
  );

  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    calls.add('submit');
    requests.add(request);
    final payload = request.payload;
    if (payload.kind == EditorCommandKind.replaceTextRange) {
      text = _replace(text, payload.start!, payload.end!, payload.replacement!);
    }
    return EditorCommandResult(
      commandId: request.commandId,
      previousRevision: request.baseRevision,
      committedRevision: request.baseRevision + 1,
      durable: true,
      warnings: const <String>[],
      objectPatches: <EditorObjectPatch>[
        EditorObjectPatch(
          objectId: harnessObjectId,
          pageId: 'page-1',
          modifiedRevision: request.baseRevision + 1,
          text: text,
        ),
      ],
    );
  }

  @override
  Future<EditorSceneObject> objectDetails(String objectId) async => object;

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();

  @override
  Future<void> releaseCleanPatchMemory() async {}

  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) async {
    calls.add('save');
    final error = saveError;
    if (error != null) throw error;
    return EditorSaveResult(
      targetPath: request.targetPath,
      materializedRevision: requests.length,
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
      followsNewSource:
          request.association == EditorSaveAssociation.followNewSource,
    );
  }

  @override
  Future<void> close() => _events.close();

  @override
  Future<EditorSearchResult> search(EditorSearchRequest request) async =>
      EditorSearchResult(
        schemaVersion: 1,
        revision: request.expectedRevision,
        matches: <EditorSearchMatch>[
          EditorSearchMatch(
            objectId: harnessObjectId,
            pageId: 'page-1',
            pageNumber: 1,
            startUtf16: 0,
            endUtf16: text.codeUnits.length,
            quotedText: text,
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
    schemaVersion: 1,
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
        commandId: commandId,
        previousRevision: baseRevision,
        committedRevision: baseRevision + 1,
        durable: true,
        warnings: const <String>[],
        objectPatches: const <EditorObjectPatch>[],
      );
}

EditorSceneObject _object(String text, String capability) => EditorSceneObject(
  kind: EditorSceneObjectKind.text,
  objectId: harnessObjectId,
  pageId: 'page-1',
  text: text,
  bounds: const EditorPdfBox(left: 0, bottom: 0, right: 420, top: 72),
  transform: const EditorAffineTransform(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0),
  capability: capability,
  capabilityReason: capability == 'editable' ? null : 'unsupported_font',
  modifiedRevision: 0,
  runs: <EditorTextRun>[
    EditorTextRun(
      start: 0,
      end: text.codeUnits.length,
      style: const EditorTextStyle(
        fontFamily: 'Arial',
        fontSize: 18,
        fontWeight: 400,
        italic: false,
        colorRgba: <int>[0, 0, 0, 255],
      ),
    ),
  ],
  layout: const EditorTextLayoutRecipe(
    baseline: 18,
    lineHeight: 22,
    characterSpacing: 0,
    horizontalScale: 1,
    direction: 'ltr',
  ),
);

String _replace(String source, int start, int end, String replacement) =>
    String.fromCharCodes(<int>[
      ...source.codeUnits.take(start),
      ...replacement.codeUnits,
      ...source.codeUnits.skip(end),
    ]);
