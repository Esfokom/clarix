import 'package:clarix/src/features/pdf_editor/domain/pdf_page_object.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../support/pdf_text_fixture.dart';

void main() {
  test(
    'discovers top-level text image and path objects by native type',
    () async {
      final fixture = await PdfTextFixture.mixedPageObjects();
      final document = await PdfDocument.openFile(fixture.path);
      addTearDown(() => fixture.parent.delete(recursive: true));
      addTearDown(document.dispose);

      final objects = await const PdfiumTextEngine().inspectPageObjects(
        document: document,
        sourceRevision: await sha256File(fixture),
        pageNumbers: const <int>[1],
      );

      expect(
        objects.map((item) => item.locator.type),
        containsAll(<PdfPageObjectType>{
          PdfPageObjectType.text,
          PdfPageObjectType.image,
          PdfPageObjectType.path,
        }),
      );
      expect(
        objects.where((item) => item.locator.objectPath.length == 1),
        everyElement(
          predicate<PdfPageObject>(
            (item) =>
                item.capabilities.contains(PdfPageObjectCapability.inspect),
          ),
        ),
      );
    },
  );

  test('resolves an exact object and rejects a stale revision', () async {
    final fixture = await PdfTextFixture.mixedPageObjects();
    final document = await PdfDocument.openFile(fixture.path);
    addTearDown(() => fixture.parent.delete(recursive: true));
    addTearDown(document.dispose);
    final engine = const PdfiumTextEngine();
    final revision = await sha256File(fixture);
    final object = (await engine.inspectPageObjects(
      document: document,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    )).first;

    expect(
      (await engine.resolvePageObject(
        document: document,
        locator: object.locator,
      )).locator,
      object.locator,
    );
    final stale = PdfPageObjectLocator(
      pageNumber: object.locator.pageNumber,
      objectPath: object.locator.objectPath,
      type: object.locator.type,
      contentDigest: object.locator.contentDigest,
      geometryDigest: object.locator.geometryDigest,
      sourceRevision: 'stale',
    );
    await expectLater(
      engine.resolvePageObject(document: document, locator: stale),
      throwsA(isA<PdfStalePageObjectLocatorFailure>()),
    );
  });
}
