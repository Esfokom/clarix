import 'package:clarix/src/features/workspace/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_edit_save_service.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test('saved replacement and movement remain genuine PDF text', () async {
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
    final formatted = PdfEditingSession.empty('doc', sourceRevision: revision)
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
    final movedBounds = PdfBox(
      block.bounds.left + 20,
      block.bounds.bottom + 10,
      block.bounds.right + 20,
      block.bounds.top + 10,
    );
    final draft = formatted.applyCommand(
      MovePdfTextBlockCommand(
        id: 'move-1',
        provenance: PdfCommandProvenance.manual,
        locator: block.locator,
        before: block.bounds,
        after: movedBounds,
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
    final reopenedBlocks = await engine.inspectPages(
      document: reopened,
      sourceRevision: await sha256File(file),
      pageNumbers: const <int>[1],
    );
    expect(reopenedBlocks.single.bounds.left, closeTo(movedBounds.left, 1));
  });

  test('saved size and fill color remain on a genuine text object', () async {
    final file = await PdfTextFixture.singleBlock('Styled');
    addTearDown(() => file.parent.delete(recursive: true));
    final revision = await sha256File(file);
    final source = await PdfDocument.openFile(file.path);
    const engine = PdfiumTextEngine();
    final blocks = await engine.inspectPages(
      document: source,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    );
    await source.dispose();
    final block = blocks.single;
    final before = block.styleAt(0);
    final formattedDraft =
        PdfEditingSession.empty('doc', sourceRevision: revision)
            .withBlocks(blocks)
            .applyCommand(
              FormatPdfTextCommand(
                id: 'format-1',
                provenance: PdfCommandProvenance.manual,
                locator: block.locator,
                range: PdfTextRange(0, block.text.length),
                before: before,
                after: before.copyWith(
                  fontSize: 18,
                  fillColorValue: 0xff336699,
                ),
              ),
            );
    final expandedBounds = PdfBox(
      block.bounds.left,
      block.bounds.bottom,
      block.bounds.left + block.bounds.width * 2,
      block.bounds.bottom + block.bounds.height * 2,
    );
    final draft = formattedDraft.applyCommand(
      ResizePdfTextBlockCommand(
        id: 'resize-1',
        provenance: PdfCommandProvenance.manual,
        locator: block.locator,
        before: block.bounds,
        after: expandedBounds,
      ),
    );
    final working = await PdfDocument.openFile(file.path);
    final bytes = await engine.applyDraft(document: working, draft: draft);
    await working.dispose();
    await file.writeAsBytes(bytes, flush: true);

    final reopened = await PdfDocument.openFile(file.path);
    final edited = await engine.inspectPages(
      document: reopened,
      sourceRevision: await sha256File(file),
      pageNumbers: const <int>[1],
    );
    await reopened.dispose();

    expect(edited.single.text, contains('Styled'));
    expect(edited.single.styleAt(0).fontSize, closeTo(18, 0.1));
    expect(edited.single.styleAt(0).fillColorValue, 0xff336699);
  });
}
