import 'dart:io';

import 'package:clarix/src/features/workspace/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_page_object.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  for (final type in <PdfPageObjectType>[
    PdfPageObjectType.image,
    PdfPageObjectType.path,
  ]) {
    test('$type retains its native type and exact matrix after save', () async {
      final fixture = await PdfTextFixture.mixedPageObjects();
      final output = File(
        '${fixture.parent.path}${Platform.pathSeparator}out.pdf',
      );
      final document = await PdfDocument.openFile(fixture.path);
      const engine = PdfiumTextEngine();
      final revision = await sha256File(fixture);
      final objects = await engine.inspectPageObjects(
        document: document,
        sourceRevision: revision,
        pageNumbers: const <int>[1],
      );
      final source = objects.firstWhere((item) => item.locator.type == type);
      final expected = source.transform.translated(dx: 17, dy: -9);
      final session = PdfEditingSession.empty('doc', sourceRevision: revision)
          .withPageObjects(objects)
          .applyCommand(
            TransformPdfPageObjectCommand(
              id: 'transform',
              provenance: PdfCommandProvenance.manual,
              locator: source.locator,
              before: source.transform,
              after: expected,
              summary: 'Transform object',
            ),
          );
      await output.writeAsBytes(
        await engine.applyDraft(document: document, draft: session),
        flush: true,
      );
      document.dispose();

      final reopened = await PdfDocument.openFile(output.path);
      addTearDown(() => fixture.parent.delete(recursive: true));
      addTearDown(reopened.dispose);
      final saved = (await engine.inspectPageObjects(
        document: reopened,
        sourceRevision: await sha256File(output),
        pageNumbers: const <int>[1],
      )).firstWhere((item) => item.locator.type == type);

      expect(saved.locator.type, type);
      expect(saved.transform.a, closeTo(expected.a, 0.0001));
      expect(saved.transform.b, closeTo(expected.b, 0.0001));
      expect(saved.transform.c, closeTo(expected.c, 0.0001));
      expect(saved.transform.d, closeTo(expected.d, 0.0001));
      expect(saved.transform.translateX, closeTo(expected.translateX, 0.0001));
      expect(saved.transform.translateY, closeTo(expected.translateY, 0.0001));
    });
  }
}
