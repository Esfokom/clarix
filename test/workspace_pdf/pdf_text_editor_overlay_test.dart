import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_text_editor_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bounds exist only in text edit mode', (tester) async {
    var mode = PdfEditingMode.reading;
    late StateSetter setHarnessState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return Scaffold(
              body: Stack(
                children: <Widget>[
                  PdfTextEditorOverlay(
                    mode: mode,
                    blocks: <PdfTextBlock>[_block()],
                    selection: null,
                    rectForBlock: (_) => const Rect.fromLTWH(20, 30, 120, 24),
                    onSelect: (_) {},
                  ),
                  IconButton(
                    key: const Key('pdf-text-edit-toggle'),
                    onPressed: () => setHarnessState(
                      () => mode = mode == PdfEditingMode.reading
                          ? PdfEditingMode.text
                          : PdfEditingMode.reading,
                    ),
                    icon: const Icon(Icons.edit),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('pdf-text-block-outline')), findsNothing);
    await tester.tap(find.byKey(const Key('pdf-text-edit-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('pdf-text-block-outline')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-text-edit-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('pdf-text-block-outline')), findsNothing);
  });

  testWidgets('selects a block and distinguishes read-only content', (
    tester,
  ) async {
    PdfTextBlockLocator? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfTextEditorOverlay(
            mode: PdfEditingMode.text,
            blocks: <PdfTextBlock>[_block(editable: false)],
            selection: null,
            rectForBlock: (_) => const Rect.fromLTWH(20, 30, 120, 24),
            onSelect: (locator) => selected = locator,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('pdf-text-block-read-only')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-text-block-outline')));
    expect(selected, _locator);
  });

  testWidgets('selected block accepts input without painting editable glyphs', (
    tester,
  ) async {
    final intents = <PdfEditIntent>[];
    final selections = <PdfTextRange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfTextEditorOverlay(
            mode: PdfEditingMode.object,
            interaction: PdfEditingInteraction.textEditing,
            blocks: <PdfTextBlock>[_block()],
            selection: PdfTextSelection(
              locator: _locator,
              range: const PdfTextRange(0, 13),
            ),
            rectForBlock: (_) => const Rect.fromLTWH(20, 30, 120, 24),
            onSelect: (_) {},
            documentId: 'document',
            documentRevision: 'revision',
            onIntent: intents.add,
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('pdf-native-text-input')), findsOneWidget);
    expect(find.byKey(const Key('pdf-text-block-outline')), findsOneWidget);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(
      tester.testTextInput.setClientArgs?['viewId'],
      tester.view.viewId,
      reason: 'Windows rejects text input clients without an owning view ID.',
    );

    tester.testTextInput.enterText('After');
    await tester.pump();

    final intent = intents.single as ReplacePdfTextIntent;
    expect(intent.range, const PdfTextRange(0, 13));
    expect(intent.replacement, 'After');
    expect(
      selections,
      <PdfTextRange>[const PdfTextRange(5, 5)],
      reason: 'The visible caret must follow the platform text client.',
    );
  });

  testWidgets('single click enters text with a collapsed caret', (
    tester,
  ) async {
    final editingRanges = <PdfTextRange>[];
    var interaction = PdfEditingInteraction.reading;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: PdfTextEditorOverlay(
                mode: PdfEditingMode.object,
                interaction: interaction,
                blocks: <PdfTextBlock>[_block()],
                selection: interaction == PdfEditingInteraction.reading
                    ? null
                    : PdfTextSelection(
                        locator: _locator,
                        range: const PdfTextRange(0, 0),
                      ),
                rectForBlock: (_) => const Rect.fromLTWH(20, 30, 120, 24),
                onSelect: (locator) {
                  update(
                    () => interaction = PdfEditingInteraction.objectSelected,
                  );
                },
                onBeginTextEditing: (_, range) {
                  editingRanges.add(range);
                  update(() => interaction = PdfEditingInteraction.textEditing);
                },
                documentId: 'document',
                documentRevision: 'revision',
                onIntent: (_) {},
              ),
            );
          },
        ),
      ),
    );

    await tester.tapAt(const Offset(80, 42));
    await tester.pump();
    expect(editingRanges, hasLength(1));
    expect(editingRanges.single.isEmpty, isTrue);
    expect(editingRanges.single, isNot(const PdfTextRange(0, 13)));
    expect(find.byKey(const Key('pdf-native-text-input')), findsOneWidget);
  });
}

final _locator = PdfTextBlockLocator(
  pageNumber: 1,
  objectPath: const <int>[0],
  textDigest: 'text',
  geometryDigest: 'geometry',
  fontFingerprint: 'font',
  sourceRevision: 'revision',
);

PdfTextBlock _block({bool editable = true}) {
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
    lineSpacing: 12,
    horizontalScaling: 1,
  );
  return PdfTextBlock(
    locator: _locator,
    text: 'Editable text',
    originalText: 'Editable text',
    runs: const <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, 13), style: style),
    ],
    bounds: const PdfBox(0, 0, 100, 20),
    transform: const PdfTransform(1, 0, 0, 1, 0, 0),
    baseline: 12,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: editable
        ? PdfTextCapability.values
        : const <PdfTextCapability>[],
    readOnlyReason: editable ? null : PdfReadOnlyReason.complexRendering,
  );
}
