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
        regenerateContent: true,
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
    'commits a dirty page once after multiple live text mutations',
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

      await session.replaceTextObject(
        locator,
        'First',
        regenerateContent: false,
      );
      await session.replaceTextObject(
        locator,
        'Final',
        regenerateContent: false,
      );
      final committed = await session.commit();

      expect(committed, <int>{1});
      expect(await session.commit(), isEmpty);
    },
  );
}
