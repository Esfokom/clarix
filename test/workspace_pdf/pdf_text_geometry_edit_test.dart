import 'package:clarix/src/features/workspace/application/pdf_edit_intent_dispatcher.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'selected text exposes eight resize handles and emits one resize',
    (tester) async {
      final block = _block();
      final intents = <PdfEditIntent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfTextEditorOverlay(
              mode: PdfEditingMode.text,
              interaction: PdfEditingInteraction.textEditing,
              blocks: <PdfTextBlock>[block],
              selection: PdfTextSelection(
                locator: block.locator,
                range: const PdfTextRange(0, 0),
              ),
              rectForBlock: (_) => const Rect.fromLTWH(20, 30, 160, 40),
              onSelect: (_) {},
              documentId: 'doc',
              documentRevision: 'rev',
              onIntent: intents.add,
            ),
          ),
        ),
      );

      for (final name in <String>[
        'north-west',
        'north',
        'north-east',
        'east',
        'south-east',
        'south',
        'south-west',
        'west',
      ]) {
        expect(find.byKey(Key('pdf-resize-$name')), findsOneWidget);
      }
      await tester.drag(
        find.byKey(const Key('pdf-resize-east')),
        const Offset(-80, 0),
      );
      await tester.pump();

      expect(intents.whereType<ResizePdfTextBlockIntent>(), hasLength(1));
      expect(
        intents.whereType<ResizePdfTextBlockIntent>().single.bounds.width,
        closeTo(80, 0.1),
      );
    },
  );

  test('reflow marks overflow and blocks save intent', () async {
    var session = PdfEditingSession.empty(
      'doc',
      sourceRevision: 'rev',
    ).withBlocks(<PdfTextBlock>[_block(width: 30, height: 12)]);
    final dispatcher = PdfEditIntentDispatcher(
      readSession: (_) => session,
      writeSession: (next) => session = next,
      commandId: () => 'command',
    );
    final block = session.blocks.single;
    await dispatcher.dispatch(
      ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'rev',
        locator: block.locator,
        range: PdfTextRange(0, block.text.length),
        replacement: 'one two three four five',
        caseMatching: false,
      ),
      provenance: PdfCommandProvenance.manual,
    );

    expect(session.blocks.single.overflow, isTrue);
    final save = await dispatcher.dispatch(
      const SavePdfEditsIntent(documentId: 'doc', documentRevision: 'rev'),
      provenance: PdfCommandProvenance.manual,
    );
    expect(save.failure, isA<PdfTextOverflowFailure>());
    expect(session.blocks.single.styleAt(0).fontSize, 12);
  });
}

PdfTextBlock _block({double width = 160, double height = 40}) {
  const style = PdfTextStyle(
    fontFamily: 'Helvetica',
    fontSize: 12,
    fillColorValue: 0xff111111,
    fontWeight: 400,
    italic: false,
    underline: false,
    baselineShift: 0,
    alignment: PdfTextAlignment.left,
    characterSpacing: 0,
    lineSpacing: 0,
    horizontalScaling: 1,
  );
  final locator = PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: 'rev',
  );
  return PdfTextBlock(
    locator: locator,
    text: 'one two three four',
    originalText: 'one two three four',
    runs: const <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, 18), style: style),
    ],
    bounds: PdfBox(0, 0, width, height),
    transform: const PdfTransform(1, 0, 0, 1, 0, 12),
    baseline: 12,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: PdfTextCapability.values,
    readOnlyReason: null,
  );
}
