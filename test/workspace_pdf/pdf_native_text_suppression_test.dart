import 'package:clarix/src/features/workspace/infrastructure/pdf_preview_document_controller.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test(
    'suppression restores native text without changing source bytes',
    () async {
      final fixture = await PdfTextFixture.singleBlock(
        'Native searchable text',
      );
      final originalBytes = await fixture.readAsBytes();
      final document = await PdfDocument.openFile(fixture.path);
      addTearDown(() => fixture.parent.delete(recursive: true));
      addTearDown(document.dispose);
      const engine = PdfiumTextEngine();
      final revision = await sha256File(fixture);
      final block = (await engine.inspectPages(
        document: document,
        sourceRevision: revision,
        pageNumbers: const <int>[1],
      )).single;
      final preview = PdfPreviewDocumentController(mutator: engine);

      await preview.suppressText(document, block);
      await preview.restoreSuppressedText(document);

      final restored = (await engine.inspectPages(
        document: document,
        sourceRevision: revision,
        pageNumbers: const <int>[1],
      )).single;
      expect(restored.text, 'Native searchable text');
      expect(await fixture.readAsBytes(), originalBytes);
    },
  );
}
