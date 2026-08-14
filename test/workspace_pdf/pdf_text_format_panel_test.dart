import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_text_format_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mixed selection shows indeterminate size and emits format intent',
    (tester) async {
      final intents = <PdfEditIntent>[];
      final block = _block();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfTextFormatPanel(
              documentId: 'doc',
              documentRevision: 'rev',
              block: block,
              selection: PdfTextSelection(
                locator: block.locator,
                range: const PdfTextRange(0, 2),
              ),
              availableFamilies: const <String>['Arial', 'Calibri'],
              onIntent: intents.add,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('pdf-font-size-mixed')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('pdf-font-size-input')),
        '14',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(intents, hasLength(1));
      final intent = intents.single as FormatPdfTextIntent;
      expect(intent.patch.fontSize, 14);
      expect(intent.range, const PdfTextRange(0, 2));
    },
  );

  testWidgets('bold and case matching controls are exposed', (tester) async {
    final intents = <PdfEditIntent>[];
    final block = _block();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfTextFormatPanel(
            documentId: 'doc',
            documentRevision: 'rev',
            block: block,
            selection: PdfTextSelection(
              locator: block.locator,
              range: const PdfTextRange(0, 0),
            ),
            availableFamilies: const <String>['Arial'],
            caseMatching: true,
            onIntent: intents.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('pdf-font-bold')));
    await tester.pump();
    expect((intents.single as FormatPdfTextIntent).patch.fontWeight, 700);
    expect(find.byKey(const Key('pdf-case-matching')), findsOneWidget);
  });
}

PdfTextBlock _block() {
  const first = PdfTextStyle(
    fontFamily: 'Arial',
    fontSize: 10,
    fillColorValue: 0xff000000,
    fontWeight: 400,
    italic: false,
    underline: false,
    baselineShift: 0,
    alignment: PdfTextAlignment.left,
    characterSpacing: 0,
    lineSpacing: 0,
    horizontalScaling: 1,
  );
  const second = PdfTextStyle(
    fontFamily: 'Arial',
    fontSize: 12,
    fillColorValue: 0xff000000,
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
    objectPath: <int>[0],
    textDigest: 't',
    geometryDigest: 'g',
    fontFingerprint: 'f',
    sourceRevision: 'rev',
  );
  return PdfTextBlock(
    locator: locator,
    text: 'AB',
    originalText: 'AB',
    runs: const <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, 1), style: first),
      PdfTextRun(range: PdfTextRange(1, 2), style: second),
    ],
    bounds: const PdfBox(0, 0, 20, 12),
    transform: const PdfTransform(1, 0, 0, 1, 0, 0),
    baseline: 0,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: const <PdfTextCapability>[
      PdfTextCapability.replace,
      PdfTextCapability.format,
    ],
    readOnlyReason: null,
  );
}
