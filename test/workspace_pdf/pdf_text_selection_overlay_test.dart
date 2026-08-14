import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('caret and selection paint from native boxes only', (
    tester,
  ) async {
    PdfTextRange? tappedRange;
    final block = _block();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfTextEditorOverlay(
            mode: PdfEditingMode.object,
            blocks: <PdfTextBlock>[block],
            selection: PdfTextSelection(
              locator: block.locator,
              range: const PdfTextRange(1, 3),
            ),
            nativeProjection: _projection(block),
            rectForBlock: (_) => const Rect.fromLTWH(20, 30, 100, 20),
            onSelect: (_) {},
            onSelectionChanged: (range) => tappedRange = range,
            documentId: 'document',
            documentRevision: 'revision',
            onIntent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('pdf-native-caret')), findsOneWidget);
    expect(find.byKey(const Key('pdf-native-selection')), findsNWidgets(2));
    expect(find.byType(EditableText), findsNothing);

    await tester.tapAt(const Offset(35, 45));
    expect(tappedRange, const PdfTextRange(1, 1));
  });
}

PdfNativeProjectionResult _projection(PdfTextBlock block) =>
    PdfNativeProjectionResult(
      requestedRevision: 1,
      appliedRevision: 1,
      block: block,
      lines: <PdfNativeLine>[
        PdfNativeLine(range: const PdfTextRange(0, 4), bounds: block.bounds),
      ],
      characters: const <PdfNativeCharacterBox>[
        PdfNativeCharacterBox(offset: 0, bounds: PdfBox(0, 0, 10, 20)),
        PdfNativeCharacterBox(offset: 1, bounds: PdfBox(10, 0, 20, 20)),
        PdfNativeCharacterBox(offset: 2, bounds: PdfBox(20, 0, 30, 20)),
        PdfNativeCharacterBox(offset: 3, bounds: PdfBox(30, 0, 40, 20)),
      ],
      affectedPages: const <int>[1],
    );

PdfTextBlock _block() => PdfTextBlock(
  locator: PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: const <int>[0],
    textDigest: 'text',
    geometryDigest: 'geometry',
    fontFingerprint: 'font',
    sourceRevision: 'revision',
  ),
  text: 'Text',
  originalText: 'Text',
  runs: const <PdfTextRun>[
    PdfTextRun(
      range: PdfTextRange(0, 4),
      style: PdfTextStyle(
        fontFamily: 'Helvetica',
        fontSize: 12,
        fillColorValue: 0xff000000,
        fontWeight: 400,
        italic: false,
        underline: false,
        baselineShift: 0,
        alignment: PdfTextAlignment.left,
        characterSpacing: 0,
        lineSpacing: 12,
        horizontalScaling: 1,
      ),
    ),
  ],
  bounds: const PdfBox(0, 0, 100, 20),
  transform: const PdfTransform(1, 0, 0, 1, 0, 0),
  baseline: 12,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: PdfTextCapability.values,
  readOnlyReason: null,
);
