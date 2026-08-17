import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ctrl+Z routes to PDF history while native input has focus', (
    tester,
  ) async {
    var undoCount = 0;
    final block = _block();
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
            onIntent: (PdfEditIntent _) {},
            onUndo: () => undoCount++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('pdf-native-text-input')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(undoCount, 1);
  });
}

PdfTextBlock _block() {
  const style = PdfTextStyle(
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
    objectPath: const <int>[0],
    textDigest: 't',
    geometryDigest: 'g',
    fontFingerprint: 'f',
    sourceRevision: 'rev',
  );
  return PdfTextBlock(
    locator: locator,
    text: 'After',
    originalText: 'Before',
    runs: const <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, 5), style: style),
    ],
    bounds: const PdfBox(0, 0, 100, 20),
    transform: const PdfTransform(1, 0, 0, 1, 0, 12),
    baseline: 12,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: PdfTextCapability.values,
    readOnlyReason: null,
  );
}
