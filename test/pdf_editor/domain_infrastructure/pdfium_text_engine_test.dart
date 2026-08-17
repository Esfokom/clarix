import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../support/pdf_text_fixture.dart';

void main() {
  test('discovers selectable page text with stable locator data', () async {
    final file = await PdfTextFixture.singleBlock('Quarterly Revenue');
    addTearDown(() async => file.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(file.path);
    addTearDown(document.dispose);
    final revision = await sha256File(file);

    final blocks = await const PdfiumTextEngine().inspectPages(
      document: document,
      sourceRevision: revision,
      pageNumbers: const [1],
    );

    expect(blocks, hasLength(1));
    expect(blocks.single.text, 'Quarterly Revenue');
    expect(blocks.single.locator.objectPath, isNotEmpty);
    expect(blocks.single.locator.sourceRevision, revision);
    expect(blocks.single.capabilities, contains(PdfTextCapability.replace));
  });

  test('resolves a locator and rejects a stale source revision', () async {
    final file = await PdfTextFixture.singleBlock('Stable text');
    addTearDown(() async => file.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(file.path);
    addTearDown(document.dispose);
    final engine = const PdfiumTextEngine();
    final revision = await sha256File(file);
    final blocks = await engine.inspectPages(
      document: document,
      sourceRevision: revision,
      pageNumbers: const [1],
    );

    final resolved = await engine.resolveLocator(
      document: document,
      locator: blocks.first.locator,
    );
    expect(resolved.block, blocks.first);

    final stale = PdfTextBlockLocator(
      pageNumber: blocks.first.locator.pageNumber,
      objectPath: blocks.first.locator.objectPath,
      textDigest: blocks.first.locator.textDigest,
      geometryDigest: blocks.first.locator.geometryDigest,
      fontFingerprint: blocks.first.locator.fontFingerprint,
      sourceRevision: 'different',
    );
    await expectLater(
      engine.resolveLocator(document: document, locator: stale),
      throwsA(isA<PdfStaleLocatorFailure>()),
    );
  });
}
