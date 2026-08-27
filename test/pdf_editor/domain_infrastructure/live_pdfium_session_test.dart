import 'dart:io';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pdf_text_fixture.dart';

void main() {
  test('renders a page rectangle from its live PDFium document', () async {
    final file = await PdfTextFixture.singleBlock('Live tile');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);

    final tile = await session.renderTile(
      const LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 0,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 120,
        height: 160,
      ),
    );

    expect(tile.width, 120);
    expect(tile.height, 160);
    expect(tile.rgbaBytes, hasLength(120 * 160 * 4));
    expect(tile.rgbaBytes.any((channel) => channel != 255), isTrue);
  });

  test('inspects text from its owned live PDFium document', () async {
    final file = await PdfTextFixture.singleBlock('Live import text');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);

    final blocks = await session.inspectTextBlocks(
      sourceRevision: 'source-revision',
      pageNumbers: const <int>[1],
    );

    expect(blocks, hasLength(1));
    expect(blocks.single.text, 'Live import text');
    expect(blocks.single.locator.sourceRevision, 'source-revision');
    expect(blocks.single.locator.objectPath, isNotEmpty);
  });

  test(
    'regenerating changed page content updates a live PDFium tile',
    () async {
      final file = await PdfTextFixture.singleBlock('Original');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      const beforeRequest = LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 0,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 240,
        height: 320,
      );
      final before = await session.renderTile(beforeRequest);

      await session.replaceTextObject(
        const EditorPhysicalLocator(
          pageNumber: 1,
          objectPath: <int>[0],
          objectType: 'text',
          sourceFingerprint: 'fixture',
          objectRevision: 0,
        ),
        'Changed',
      );
      final after = await session.renderTile(
        const LivePdfiumTileRequest(
          pageNumber: 1,
          revision: 1,
          bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
          width: 240,
          height: 320,
        ),
      );

      expect(after.rgbaBytes, isNot(orderedEquals(before.rgbaBytes)));
    },
  );

  test(
    'regenerates each live text mutation before its page handle closes',
    () async {
      final file = await PdfTextFixture.singleBlock('Original');
      addTearDown(() => file.parent.delete(recursive: true));
      final session = await LivePdfiumSession.open(file.path);
      addTearDown(session.close);
      const locator = EditorPhysicalLocator(
        pageNumber: 1,
        objectPath: <int>[0],
        objectType: 'text',
        sourceFingerprint: 'fixture',
        objectRevision: 0,
      );

      await session.replaceTextObject(locator, 'First');
      await session.replaceTextObject(locator, 'Final');
      final committed = await session.commit();

      expect(committed, isEmpty);
      expect(await session.commit(), isEmpty);
    },
  );

  test('applies a same-page text plan in one live revision', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const locator = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );

    final result = await session.apply(
      LivePdfiumEditPlan(
        replacements: const <LivePdfiumTextReplacement>[
          LivePdfiumTextReplacement(locator: locator, replacement: 'First'),
          LivePdfiumTextReplacement(locator: locator, replacement: 'Final'),
        ],
      ),
    );

    expect(result.revision, 1);
    expect(result.invalidations, hasLength(2));
    expect(result.invalidations.every((item) => item.pageNumber == 1), isTrue);
  });

  test('rejects a plan prepared for a different live revision', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const locator = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );

    await expectLater(
      session.apply(
        LivePdfiumEditPlan(
          expectedRevision: 1,
          revision: 2,
          replacements: const <LivePdfiumTextReplacement>[
            LivePdfiumTextReplacement(locator: locator, replacement: 'Changed'),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a physical edit plan that spans pages', () {
    const pageOne = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );
    const pageTwo = EditorPhysicalLocator(
      pageNumber: 2,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );

    expect(
      () => LivePdfiumEditPlan(
        replacements: const <LivePdfiumTextReplacement>[
          LivePdfiumTextReplacement(locator: pageOne, replacement: 'One'),
          LivePdfiumTextReplacement(locator: pageTwo, replacement: 'Two'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('rejects a stale text plan before mutating its live object', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const locator = EditorPhysicalLocator(
      pageNumber: 1,
      objectPath: <int>[0],
      objectType: 'text',
      sourceFingerprint: 'fixture',
      objectRevision: 0,
    );
    final before = await session.renderTile(
      const LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 0,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 240,
        height: 320,
      ),
    );

    await expectLater(
      session.apply(
        LivePdfiumEditPlan(
          replacements: const <LivePdfiumTextReplacement>[
            LivePdfiumTextReplacement(
              locator: locator,
              replacement: 'Changed',
              expectedText: 'Different source text',
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
    final after = await session.renderTile(
      const LivePdfiumTileRequest(
        pageNumber: 1,
        revision: 1,
        bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
        width: 240,
        height: 320,
      ),
    );
    expect(after.rgbaBytes, orderedEquals(before.rgbaBytes));
  });

  test('saves committed text through the live PDFium document', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final session = await LivePdfiumSession.open(file.path);
    addTearDown(session.close);
    const tileRequest = LivePdfiumTileRequest(
      pageNumber: 1,
      revision: 0,
      bounds: EditorPdfBox(left: 0, bottom: 0, right: 595, top: 842),
      width: 240,
      height: 320,
    );
    final originalTile = await session.renderTile(tileRequest);
    await session.replaceTextObject(
      const EditorPhysicalLocator(
        pageNumber: 1,
        objectPath: <int>[0],
        objectType: 'text',
        sourceFingerprint: 'fixture',
        objectRevision: 0,
      ),
      'Persisted',
    );

    final saved = await session.saveBytes();
    expect(saved, hasLength(greaterThan(64)));
    expect(String.fromCharCodes(saved.take(5)), '%PDF-');
    final savedFile = File('${file.parent.path}/persisted.pdf');
    await savedFile.writeAsBytes(saved, flush: true);
    final reopened = await LivePdfiumSession.open(savedFile.path);
    addTearDown(reopened.close);
    final persistedTile = await reopened.renderTile(tileRequest);
    expect(
      persistedTile.rgbaBytes,
      isNot(orderedEquals(originalTile.rgbaBytes)),
    );
  });
}
