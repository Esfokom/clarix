import 'package:clarix/src/features/workspace/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_edit_save_service.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test('saved replacement remains extractable PDF text', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final revision = await sha256File(file);
    final source = await PdfDocument.openFile(file.path);
    final engine = const PdfiumTextEngine();
    final blocks = await engine.inspectPages(
      document: source,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    );
    await source.dispose();
    final block = blocks.single;
    final draft = PdfEditingSession.empty('doc', sourceRevision: revision)
        .withBlocks(blocks)
        .applyCommand(
          ReplacePdfTextCommand(
            id: 'replace-1',
            provenance: PdfCommandProvenance.manual,
            locator: block.locator,
            before: block.text,
            after: 'Changed',
            range: PdfTextRange(0, block.text.length),
          ),
        );
    final service = PdfEditSaveService(
      writeDraft: (working, draft) async {
        final document = await PdfDocument.openFile(working.path);
        try {
          final bytes = await engine.applyDraft(
            document: document,
            draft: draft,
          );
          await working.writeAsBytes(bytes, flush: true);
        } finally {
          await document.dispose();
        }
      },
      validate: (working) async {
        final document = await PdfDocument.openFile(working.path);
        try {
          final text = await document.pages.single.loadText();
          if (text?.fullText.contains('Changed') != true) {
            throw const PdfValidationFailure(
              'Replacement text was not extractable.',
            );
          }
        } finally {
          await document.dispose();
        }
      },
    );

    await service.save(
      PdfSaveRequest(path: file.path, sourceRevision: revision, draft: draft),
    );

    final reopened = await PdfDocument.openFile(file.path);
    addTearDown(reopened.dispose);
    final text = await reopened.pages.single.loadText();
    expect(text?.fullText, contains('Changed'));
    expect(text?.fullText, isNot(contains('Original')));
  });
}
