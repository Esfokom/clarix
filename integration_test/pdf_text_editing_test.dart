import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_edit_save_service.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/support/pdf_text_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manual and agent edits save as genuine PDF text', (
    tester,
  ) async {
    final file = await PdfTextFixture.singleBlock('TOTAL REVENUE');
    addTearDown(() => file.parent.delete(recursive: true));
    final revision = await sha256File(file);
    const engine = PdfiumTextEngine();
    final source = await PdfDocument.openFile(file.path);
    final blocks = await engine.inspectPages(
      document: source,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    );
    await source.dispose();
    final locator = blocks.single.locator;
    final saveService = PdfEditSaveService(
      writeDraft: (working, draft) async {
        final document = await PdfDocument.openFile(working.path);
        try {
          await working.writeAsBytes(
            await engine.applyDraft(document: document, draft: draft),
            flush: true,
          );
        } finally {
          await document.dispose();
        }
      },
    );
    final controller =
        PdfEditingController(engine: engine, saveService: saveService)
          ..registerSession(
            'tab',
            PdfEditingSession.empty(
              'document',
              sourceRevision: revision,
            ).withBlocks(blocks),
          );

    final manual = await controller.dispatch(
      ReplacePdfTextIntent(
        documentId: 'document',
        documentRevision: revision,
        locator: locator,
        range: const PdfTextRange(0, 13),
        replacement: 'net income',
      ),
      provenance: PdfCommandProvenance.manual,
    );
    expect(manual.isSuccess, isTrue);
    expect(controller.sessionFor('tab').blocks.single.text, 'NET INCOME');

    await controller.undo('tab');
    await controller.redo('tab');
    final agent = await controller.dispatch(
      FormatPdfTextIntent(
        documentId: 'document',
        documentRevision: revision,
        locator: locator,
        range: const PdfTextRange(0, 10),
        patch: const PdfTextStylePatch(
          fontSize: 16,
          fillColorValue: 0xff2457c5,
          fontWeight: 700,
        ),
      ),
      provenance: PdfCommandProvenance.agent,
    );
    expect(agent.isSuccess, isTrue);
    await controller.save('tab', file.path);

    final reopened = await PdfDocument.openFile(file.path);
    final extracted = await reopened.pages.single.loadText();
    final reopenedBlocks = await engine.inspectPages(
      document: reopened,
      sourceRevision: await sha256File(file),
      pageNumbers: const <int>[1],
    );
    await reopened.dispose();
    expect(extracted?.fullText, contains('NET INCOME'));
    expect(reopenedBlocks.single.text, contains('NET INCOME'));
    expect(reopenedBlocks.single.styleAt(0).fontSize, closeTo(16, 0.1));
  });
}
