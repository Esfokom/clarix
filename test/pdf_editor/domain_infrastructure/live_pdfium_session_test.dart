import 'dart:io';

import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_session.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_tile_renderer.dart';
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
