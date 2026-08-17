import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/domain/editor_selection.dart';
import 'package:clarix/src/features/pdf_editor/presentation/pdf_text_format_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  testWidgets('canonical format panel preserves source style fields', (
    tester,
  ) async {
    final harness = NativeEditorTestHarness(text: 'Styled');
    await harness.open();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanonicalPdfTextFormatPanel(
            session: harness.controller,
            object: harness.gateway.object,
            selection: const EditorSelection(
              objectId: harnessObjectId,
              range: EditorTextRange(start: 0, end: 6),
            ),
            availableFamilies: const <String>['Arial'],
          ),
        ),
      ),
    );

    expect(find.text('Arial'), findsWidgets);
    await tester.enterText(find.byKey(const Key('font-size-field')), '14');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final command = harness.gateway.requests.single.payload;
    expect(command.kind, EditorCommandKind.setTextStyle);
    expect(command.style?.fontSize, 14);
    expect(command.style?.fontWeight, 400);
    expect(command.style?.italic, isFalse);
    await tester.runAsync(harness.controller.close);
  });
}
