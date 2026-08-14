import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test(
    'narrower bounds create more native lines without changing size',
    () async {
      const text = 'one two three four';
      final fixture = await PdfTextFixture.singleBlock(text);
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
      final before = await engine.projectTextBlock(
        document: document,
        request: PdfNativeProjectionRequest(
          documentRevision: revision,
          editRevision: 1,
          block: original,
        ),
      );
      final narrower = original.copyWith(
        bounds: PdfBox(
          original.bounds.left,
          original.bounds.bottom - original.bounds.height * 3,
          original.bounds.left + original.bounds.width / 2,
          original.bounds.top,
        ),
      );

      final after = await engine.projectTextBlock(
        document: document,
        request: PdfNativeProjectionRequest(
          documentRevision: revision,
          editRevision: 2,
          block: narrower,
          nativeTarget: before.block,
        ),
      );

      expect(after.lines.length, greaterThan(before.lines.length));
      expect(
        after.block.runs.first.style.fontSize,
        original.runs.first.style.fontSize,
      );
      expect(after.block.text, text);
    },
  );
}
