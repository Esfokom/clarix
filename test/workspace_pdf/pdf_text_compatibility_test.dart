import 'dart:io';

import 'package:clarix/src/features/workspace/domain/pdf_edit_command.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  final supported = <String, Future<File> Function()>{
    'standard font': () => PdfTextFixture.singleBlock('Original'),
    'rotated text': () => PdfTextFixture.rotatedBlock('Original'),
  };

  for (final entry in supported.entries) {
    test(
      '${entry.key} stays selectable and searchable after editing',
      () async {
        final file = await entry.value();
        addTearDown(() => file.parent.delete(recursive: true));
        final revision = await sha256File(file);
        const engine = PdfiumTextEngine();
        final source = await PdfDocument.openFile(file.path);
        final blocks = await engine.inspectPages(
          document: source,
          sourceRevision: revision,
          pageNumbers: const <int>[1],
        );
        final target = blocks.firstWhere(
          (block) => block.text.contains('Original'),
        );
        final draft =
            PdfEditingSession.empty('compatibility', sourceRevision: revision)
                .withBlocks(blocks)
                .applyCommand(
                  ReplacePdfTextCommand(
                    id: 'replace',
                    provenance: PdfCommandProvenance.manual,
                    locator: target.locator,
                    before: target.text,
                    after: 'Changed',
                    range: PdfTextRange(0, target.text.length),
                  ),
                );
        final bytes = await engine.applyDraft(document: source, draft: draft);
        await source.dispose();
        await file.writeAsBytes(bytes, flush: true);

        final reopened = await PdfDocument.openFile(file.path);
        final text = await reopened.pages.first.loadText();
        final reopenedBlocks = await engine.inspectPages(
          document: reopened,
          sourceRevision: await sha256File(file),
          pageNumbers: const <int>[1],
        );
        await reopened.dispose();
        expect(text?.fullText, contains('Changed'));
        expect(
          reopenedBlocks.any((block) => block.text.contains('Changed')),
          isTrue,
        );
      },
    );
  }

  test('image-only pages expose no editable text objects', () async {
    final file = await PdfTextFixture.imageOnly();
    addTearDown(() => file.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(file.path);
    final blocks = await const PdfiumTextEngine().inspectPages(
      document: document,
      sourceRevision: await sha256File(file),
      pageNumbers: const <int>[1],
    );
    await document.dispose();
    expect(blocks, isEmpty);
  });

  test('malformed input is rejected instead of being rewritten', () async {
    final file = await PdfTextFixture.malformed();
    addTearDown(() => file.parent.delete(recursive: true));
    final before = await file.readAsBytes();
    await expectLater(PdfDocument.openFile(file.path), throwsA(anything));
    expect(await file.readAsBytes(), before);
  });
}
