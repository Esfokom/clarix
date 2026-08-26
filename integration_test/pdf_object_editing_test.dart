import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_page_object.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/support/pdf_text_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native image and path transforms survive encode and reopen', (
    tester,
  ) async {
    final file = await PdfTextFixture.mixedPageObjects();
    addTearDown(() => file.parent.delete(recursive: true));
    const engine = PdfiumTextEngine();
    final revision = await sha256File(file);
    final document = await PdfDocument.openFile(file.path);
    final objects = await engine.inspectPageObjects(
      document: document,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    );
    var session = PdfEditingSession.empty(
      'document',
      sourceRevision: revision,
    ).withPageObjects(objects);
    final expected = <PdfPageObjectType, PdfTransform>{};
    var command = 0;
    for (final type in <PdfPageObjectType>[
      PdfPageObjectType.image,
      PdfPageObjectType.path,
    ]) {
      final source = session.pageObjects.firstWhere(
        (item) => item.locator.type == type,
      );
      final after = source.transform.translated(dx: 12 + command * 4, dy: -6);
      expected[type] = after;
      session = session.applyCommand(
        TransformPdfPageObjectCommand(
          id: 'object-${++command}',
          provenance: PdfCommandProvenance.manual,
          locator: source.locator,
          before: source.transform,
          after: after,
          summary: 'Transform native object',
        ),
      );
    }
    await file.writeAsBytes(
      await engine.applyDraft(document: document, draft: session),
      flush: true,
    );
    await document.dispose();

    final reopened = await PdfDocument.openFile(file.path);
    final saved = await engine.inspectPageObjects(
      document: reopened,
      sourceRevision: await sha256File(file),
      pageNumbers: const <int>[1],
    );
    final extracted = await reopened.pages.single.loadText();
    await reopened.dispose();
    expect(extracted?.fullText, contains('Selectable text'));
    for (final entry in expected.entries) {
      final object = saved.firstWhere((item) => item.locator.type == entry.key);
      expect(object.locator.type, entry.key);
      expect(
        object.transform.translateX,
        closeTo(entry.value.translateX, 0.001),
      );
      expect(
        object.transform.translateY,
        closeTo(entry.value.translateY, 0.001),
      );
    }
  });
}
