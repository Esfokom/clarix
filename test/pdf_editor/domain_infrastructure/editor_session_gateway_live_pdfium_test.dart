import 'dart:async';

import 'package:clarix/src/core/editing/editor_bridge.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/core/editing/live_pdfium_editor_port.dart';
import 'package:clarix/src/core/ffi/editing_api.dart' as native;
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
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

  test('closes both owners when the import manifest is rejected', () async {
    final liveSession = _FakeLivePdfiumSession();
    final native = _NativePort();
    final gateway = BridgeEditorSessionGateway.forTest(
      openBridgeSession: (_, {String? projectRoot}) async =>
          EditorBridgeSession.forTest(native),
      openLivePdfiumSession: (_) async => liveSession,
      loadLivePdfiumImportManifest: (_) async => const LivePdfiumImportManifest(
        sourceFingerprint: 'different-source',
        bindings: <LivePdfiumImportBinding>[],
      ),
    );

    await expectLater(gateway.open('fixture.pdf'), throwsStateError);
    expect(liveSession.closed, isTrue);
    expect(native.closed, isTrue);
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
        loadLivePdfiumImportManifest: (_) async =>
            const LivePdfiumImportManifest(
              sourceFingerprint: 'source',
              bindings: <LivePdfiumImportBinding>[
                LivePdfiumImportBinding(
                  objectId: _objectId,
                  sourceKey: 'manifest/page/1/object/0',
                  sourceRevision: 'source',
                  locator: EditorPhysicalLocator(
                    pageNumber: 1,
                    objectPath: <int>[0],
                    objectType: 'text',
                    sourceFingerprint: 'source',
                    objectRevision: 0,
                  ),
                ),
              ],
            ),
      );
      await gateway.open('fixture.pdf');

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

  test('rejects an unbound text edit in a live session', () async {
    final liveSession = _FakeLivePdfiumSession();
    final native = _NativePort();
    final gateway = BridgeEditorSessionGateway.forTest(
      openBridgeSession: (_, {String? projectRoot}) async =>
          EditorBridgeSession.forTest(native),
      openLivePdfiumSession: (_) async => liveSession,
    );
    await gateway.open('fixture.pdf');
    expect(
      () => gateway.submit(
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
      ),
      throwsStateError,
    );

    expect(native.prepared, isFalse);
    expect(native.published, isFalse);
    expect(native.legacySubmissions, isZero);
    expect(liveSession.appliedPlans, isEmpty);
  });

  test('routes undo through the live PDFium transaction', () async {
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

    await gateway.submit(
      const EditorCommandRequest(
        commandId: _commandId,
        baseRevision: 0,
        payload: EditorCommand(kind: EditorCommandKind.undo),
      ),
    );

    expect(native.prepared, isTrue);
    expect(native.published, isTrue);
    expect(native.legacySubmissions, isZero);
    expect(liveSession.appliedPlans, hasLength(1));
  });

  test('routes redo through the live PDFium transaction', () async {
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

    await gateway.submit(
      const EditorCommandRequest(
        commandId: _commandId,
        baseRevision: 0,
        payload: EditorCommand(kind: EditorCommandKind.redo),
      ),
    );

    expect(native.prepared, isTrue);
    expect(native.published, isTrue);
    expect(native.legacySubmissions, isZero);
    expect(liveSession.appliedPlans, hasLength(1));
  });

  test(
    'emits live tile invalidations only after the semantic publish',
    () async {
      final liveSession = _FakeLivePdfiumSession()
        ..invalidations = const <EditorTileInvalidation>[
          EditorTileInvalidation(
            pageNumber: 1,
            bounds: EditorPdfBox(left: 10, bottom: 20, right: 30, top: 40),
            revision: 1,
          ),
        ];
      final gateway = BridgeEditorSessionGateway.forTest(
        openBridgeSession: (_, {String? projectRoot}) async =>
            EditorBridgeSession.forTest(_NativePort()),
        openLivePdfiumSession: (_) async => liveSession,
        loadLivePdfiumImportManifest: (_) async =>
            const LivePdfiumImportManifest(
              sourceFingerprint: 'source',
              bindings: <LivePdfiumImportBinding>[
                LivePdfiumImportBinding(
                  objectId: _objectId,
                  sourceKey: 'manifest/page/1/object/0',
                  sourceRevision: 'source',
                  locator: EditorPhysicalLocator(
                    pageNumber: 1,
                    objectPath: <int>[0],
                    objectType: 'text',
                    sourceFingerprint: 'source',
                    objectRevision: 0,
                  ),
                ),
              ],
            ),
      );
      await gateway.open('fixture.pdf');
      final notification = gateway.liveTileInvalidations.first;

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

      expect(await notification, liveSession.invalidations);
    },
  );

  test('hydrates a visible page from its live PDFium inspection', () async {
    final liveSession = _ImportingLivePdfiumSession();
    final nativePort = _NativePort();
    final gateway = BridgeEditorSessionGateway.forTest(
      openBridgeSession: (_, {String? projectRoot}) async =>
          EditorBridgeSession.forTest(nativePort),
      openLivePdfiumSession: (_) async => liveSession,
    );
    await gateway.open('fixture.pdf');

    await gateway.requestPage(1, 0);

    expect(nativePort.importedPages, hasLength(1));
    final page = nativePort.importedPages.single;
    expect(page.pageNumber, 1);
    expect(page.width, 595);
    expect(page.height, 842);
    expect(page.objects.single.sourceKey, 'source/live-pdfium/page/1/object/0');
    expect(page.objects.single.objectId, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test(
    'surfaces a recovered projection conflict instead of binding mismatched objects',
    () async {
      final liveSession = _ImportingLivePdfiumSession();
      final nativePort = _NativePort()
        ..importError = StateError(
          'invalid_command: invalid command: page 1 was already hydrated '
          'with different content',
        );
      final gateway = BridgeEditorSessionGateway.forTest(
        openBridgeSession: (_, {String? projectRoot}) async =>
            EditorBridgeSession.forTest(nativePort),
        openLivePdfiumSession: (_) async => liveSession,
      );
      await gateway.open('fixture.pdf');

      await expectLater(gateway.requestPage(1, 0), throwsStateError);
      expect(nativePort.importedPages, hasLength(1));
    },
  );
}

const _commandId = '00000000-0000-4000-8000-000000000010';
const _preparedToken = '00000000-0000-4000-8000-000000000011';
const _objectId = '00000000-0000-4000-8000-000000000012';

class _FakeLivePdfiumSession implements LivePdfiumSessionOwner {
  final List<String> openedPaths = <String>[];
  final List<LivePdfiumEditPlan> appliedPlans = <LivePdfiumEditPlan>[];
  List<EditorTileInvalidation> invalidations = const <EditorTileInvalidation>[];
  bool closed = false;

  @override
  Future<LivePdfiumApplyResult> apply(LivePdfiumEditPlan plan) async {
    appliedPlans.add(plan);
    return LivePdfiumApplyResult(
      revision: plan.revision ?? 1,
      invalidations: invalidations,
    );
  }

  @override
  Future<void> close() async => closed = true;
}

final class _ImportingLivePdfiumSession extends _FakeLivePdfiumSession
    implements LivePdfiumPageImportSource {
  @override
  Future<LivePdfiumPageInspection> inspectPageForImport({
    required String sourceRevision,
    required int pageNumber,
  }) async => LivePdfiumPageInspection(
    pageNumber: pageNumber,
    width: 595,
    height: 842,
    blocks: <PdfTextBlock>[_importableBlock(sourceRevision)],
  );
}

final class _NativePort
    implements
        NativeEditorPort,
        NativeLivePdfiumPort,
        NativeLivePageImportPort {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();
  bool prepared = false;
  bool published = false;
  bool closed = false;
  int legacySubmissions = 0;
  Object? importError;
  final List<native.NativeLivePageImport> importedPages =
      <native.NativeLivePageImport>[];

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }

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
  }) async => EditorPageScene(
    schemaVersion: 1,
    pageId: '00000000-0000-4000-8000-000000000003',
    pageNumber: pageNumber,
    width: 595,
    height: 842,
    revision: expectedRevision,
    objects: const <EditorSceneObject>[],
  );

  @override
  Future<void> importLivePage(native.NativeLivePageImport request) async {
    importedPages.add(request);
    if (importError case final error?) throw error;
  }

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
            kind: EditorPhysicalEditOperationKind.replaceText,
            objectId: _objectId,
            sourceKey: 'manifest/page/1/object/0',
            sourceRevision: 'source',
            expectedText: 'Before',
            replacement: 'Changed',
            oldBounds: EditorPdfBox(left: 0, bottom: 0, right: 1, top: 1),
            newBounds: EditorPdfBox(left: 0, bottom: 0, right: 1, top: 1),
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

PdfTextBlock _importableBlock(String sourceRevision) => PdfTextBlock(
  locator: PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: sourceRevision,
  ),
  text: 'Before',
  originalText: 'Before',
  runs: const <PdfTextRun>[
    PdfTextRun(
      range: PdfTextRange(0, 6),
      style: PdfTextStyle(
        fontFamily: 'Helvetica',
        fontSize: 12,
        fillColorValue: 0xff000000,
        fontWeight: 400,
        italic: false,
        underline: false,
        baselineShift: 0,
        alignment: PdfTextAlignment.left,
        characterSpacing: 0,
        lineSpacing: 0,
        horizontalScaling: 1,
      ),
    ),
  ],
  bounds: const PdfBox(10, 10, 50, 20),
  transform: const PdfTransform(1, 0, 0, 1, 0, 0),
  baseline: 10,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: const <PdfTextCapability>[PdfTextCapability.replace],
  readOnlyReason: null,
);
