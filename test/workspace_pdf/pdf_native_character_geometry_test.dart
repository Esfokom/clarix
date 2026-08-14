import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test(
    'native character boxes map every UTF-16 offset in edited text',
    () async {
      final fixture = await PdfTextFixture.singleBlock('Before');
      addTearDown(() => fixture.parent.delete(recursive: true));
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
          block: original.copyWith(text: 'AB CD'),
        ),
      );

      expect(result.characters.map((character) => character.offset), <int>[
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(
        result.characters.every((character) => character.bounds.width >= 0),
        isTrue,
      );
    },
  );
}
