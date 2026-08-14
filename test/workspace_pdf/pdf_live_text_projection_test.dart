import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test(
    'projection changes open native extraction without changing source bytes',
    () async {
      final fixture = await PdfTextFixture.singleBlock('Before');
      addTearDown(() => fixture.parent.delete(recursive: true));
      final sourceBytes = await fixture.readAsBytes();
      final document = await PdfDocument.openFile(fixture.path);
      addTearDown(document.dispose);
      const engine = PdfiumTextEngine();
      final revision = await sha256File(fixture);
      final original = (await engine.inspectPages(
        document: document,
        sourceRevision: revision,
        pageNumbers: const <int>[1],
      )).single;

      final result = await engine.projectTextBlock(
        document: document,
        request: PdfNativeProjectionRequest(
          documentRevision: revision,
          editRevision: 1,
          block: original.copyWith(text: 'After'),
        ),
      );

      expect(result.block.text, 'After');
      expect(
        (await document.pages.first.loadText())!.fullText,
        contains('After'),
      );
      expect(await fixture.readAsBytes(), sourceBytes);
    },
  );

  test('successive projections follow refreshed native object paths', () async {
    final fixture = await PdfTextFixture.singleBlock('Before');
    addTearDown(() => fixture.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(fixture.path);
    addTearDown(document.dispose);
    const engine = PdfiumTextEngine();
    final revision = await sha256File(fixture);
    final logicalBlock = (await engine.inspectPages(
      document: document,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    )).single;
    final coordinator = PdfNativeEditCoordinator(mutator: engine);

    await coordinator.projectBlock(
      document,
      PdfNativeProjectionRequest(
        documentRevision: revision,
        editRevision: 1,
        block: logicalBlock.copyWith(text: 'After'),
      ),
    );
    await coordinator.projectBlock(
      document,
      PdfNativeProjectionRequest(
        documentRevision: revision,
        editRevision: 2,
        block: logicalBlock.copyWith(text: 'Again'),
      ),
    );

    expect(
      (await document.pages.first.loadText())!.fullText,
      contains('Again'),
    );
  });
}
