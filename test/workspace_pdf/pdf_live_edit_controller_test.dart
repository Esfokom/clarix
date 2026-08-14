import 'dart:typed_data';
import 'dart:io';

import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_text_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test('accepted replacement is projected before dispatch completes', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);

    final result = await harness.controller.dispatchAndProject(
      tabId: 'tab',
      intent: _replacement(harness.controller.sessionFor('tab'), 'After'),
      provenance: PdfCommandProvenance.manual,
    );

    expect(result.isSuccess, isTrue);
    expect(harness.mutator.requests.single.block.text, 'After');
    expect(harness.controller.sessionFor('tab').blocks.single.text, 'After');
  });

  test('selecting a text block primes native caret geometry', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);

    await harness.controller.selectTextBlock(
      'tab',
      harness.document,
      harness.controller.sessionFor('tab').blocks.single.locator,
    );
    await harness.controller.selectTextBlock(
      'tab',
      harness.document,
      harness.controller.sessionFor('tab').blocks.single.locator,
    );

    expect(harness.mutator.requests, hasLength(2));
    expect(
      harness.mutator.requests.every((request) => request.readOnlyGeometry),
      isTrue,
    );
    expect(harness.reloadedPages, isEmpty);
    expect(harness.controller.nativeResultFor('tab')?.block.text, 'Before');
  });

  test(
    'object selection does not activate text input until requested',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final locator = harness.controller
          .sessionFor('tab')
          .blocks
          .single
          .locator;

      await harness.controller.selectTextObject(
        'tab',
        harness.document,
        locator,
      );

      expect(
        harness.controller.sessionFor('tab').interaction,
        PdfEditingInteraction.objectSelected,
      );
      expect(harness.mutator.requests.single.readOnlyGeometry, isTrue);

      await harness.controller.beginTextEditing(
        'tab',
        harness.document,
        locator,
        const PdfTextRange(1, 4),
      );
      expect(
        harness.controller.sessionFor('tab').interaction,
        PdfEditingInteraction.textEditing,
      );
      expect(
        harness.controller.sessionFor('tab').selection?.range,
        const PdfTextRange(1, 4),
      );

      harness.controller.leaveTextEditing('tab');
      expect(
        harness.controller.sessionFor('tab').interaction,
        PdfEditingInteraction.objectSelected,
      );
      expect(harness.controller.sessionFor('tab').selection?.locator, locator);

      await harness.controller.clearSelection('tab');
      expect(
        harness.controller.sessionFor('tab').interaction,
        PdfEditingInteraction.reading,
      );
      expect(harness.controller.sessionFor('tab').selection, isNull);
    },
  );

  test('native projection failure restores the prior session', () async {
    final harness = await _Harness.create(failProjection: true);
    addTearDown(harness.dispose);

    await expectLater(
      harness.controller.dispatchAndProject(
        tabId: 'tab',
        intent: _replacement(harness.controller.sessionFor('tab'), 'After'),
        provenance: PdfCommandProvenance.manual,
      ),
      throwsA(isA<StateError>()),
    );

    expect(harness.controller.sessionFor('tab').blocks.single.text, 'Before');
    expect(harness.controller.sessionFor('tab').canUndo, isFalse);
  });

  test('undo and redo project complete historical block states', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    await harness.controller.dispatchAndProject(
      tabId: 'tab',
      intent: _replacement(harness.controller.sessionFor('tab'), 'After'),
      provenance: PdfCommandProvenance.manual,
    );
    harness.mutator.requests.clear();

    await harness.controller.undo('tab');
    await harness.controller.redo('tab');

    expect(
      harness.mutator.requests.map((request) => request.block.text),
      <String>['Before', 'After'],
    );
  });

  test(
    'discard projects the saved native text state without writing the file',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.dispatchAndProject(
        tabId: 'tab',
        intent: _replacement(harness.controller.sessionFor('tab'), 'Saved'),
        provenance: PdfCommandProvenance.manual,
      );
      harness.controller.markSaved('tab');
      await harness.controller.dispatchAndProject(
        tabId: 'tab',
        intent: _replacement(harness.controller.sessionFor('tab'), 'Draft'),
        provenance: PdfCommandProvenance.manual,
      );
      harness.mutator.requests.clear();

      await harness.controller.discardChanges('tab');

      expect(harness.controller.sessionFor('tab').blocks.single.text, 'Saved');
      expect(harness.controller.sessionFor('tab').isDirty, isFalse);
      expect(harness.mutator.requests.single.block.text, 'Saved');
    },
  );
}

ReplacePdfTextIntent _replacement(PdfEditingSession session, String after) =>
    ReplacePdfTextIntent(
      documentId: session.documentId,
      documentRevision: session.revision,
      locator: session.blocks.single.locator,
      range: PdfTextRange(0, session.blocks.single.text.length),
      replacement: after,
    );

final class _Harness {
  _Harness(
    this.controller,
    this.document,
    this.fixture,
    this.mutator,
    this.reloadedPages,
  );

  static Future<_Harness> create({bool failProjection = false}) async {
    final fixture = await PdfTextFixture.singleBlock('Before');
    final document = await PdfDocument.openFile(fixture.path);
    final mutator = _RecordingLiveMutator(failProjection: failProjection);
    final reloadedPages = <List<int>>[];
    final coordinator = PdfNativeEditCoordinator(
      mutator: mutator,
      reloadPages: (_, pages) async => reloadedPages.add(List<int>.of(pages)),
    );
    final controller = PdfEditingController(nativeCoordinator: coordinator)
      ..registerSession('tab', _session())
      ..registerDocument('tab', document);
    return _Harness(controller, document, fixture, mutator, reloadedPages);
  }

  final PdfEditingController controller;
  final PdfDocument document;
  final File fixture;
  final _RecordingLiveMutator mutator;
  final List<List<int>> reloadedPages;

  Future<void> dispose() async {
    controller.dispose();
    await document.dispose();
    await fixture.parent.delete(recursive: true);
  }
}

final class _RecordingLiveMutator implements PdfLiveDocumentMutator {
  _RecordingLiveMutator({required this.failProjection});

  final bool failProjection;
  final List<PdfNativeProjectionRequest> requests =
      <PdfNativeProjectionRequest>[];

  @override
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  }) async {
    requests.add(request);
    if (failProjection) throw StateError('native projection failed');
    return PdfNativeProjectionResult(
      requestedRevision: request.editRevision,
      appliedRevision: request.editRevision,
      block: request.block,
      lines: <PdfNativeLine>[
        PdfNativeLine(
          range: PdfTextRange(0, request.block.text.length),
          bounds: request.block.bounds,
        ),
      ],
      characters: const <PdfNativeCharacterBox>[],
      affectedPages: <int>[request.block.locator.pageNumber],
    );
  }

  @override
  Future<Uint8List> encodeLiveDocument({required PdfDocument document}) async =>
      Uint8List(0);
}

PdfEditingSession _session() => PdfEditingSession.empty(
  'document',
  sourceRevision: 'revision',
).withBlocks(<PdfTextBlock>[_block()]);

PdfTextBlock _block() => PdfTextBlock(
  locator: PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: 'revision',
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
        lineSpacing: 12,
        horizontalScaling: 1,
      ),
    ),
  ],
  bounds: const PdfBox(10, 20, 100, 32),
  transform: const PdfTransform(1, 0, 0, 1, 10, 20),
  baseline: 20,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: PdfTextCapability.values,
  readOnlyReason: null,
);
