import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  testWidgets('IME composition paints locally and commits one command', (
    tester,
  ) async {
    final harness = NativeEditorTestHarness(text: 'one two');
    await harness.open(selectionOffset: 4);
    await tester.pumpWidget(harness.widget());
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'one xtwo',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 4, end: 5),
      ),
    );
    await tester.pump();
    expect(_value(tester).text, 'one xtwo');
    expect(_value(tester).composing, const TextRange(start: 4, end: 5));
    expect(harness.gateway.requests, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'one xytoo',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 4, end: 6),
      ),
    );
    await tester.pump();
    expect(harness.gateway.requests, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'one xytoo',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(harness.gateway.requests, hasLength(1));
    await tester.runAsync(harness.controller.close);
  });

  testWidgets(
    'cancelled IME composition restores accepted text without submit',
    (tester) async {
      final harness = NativeEditorTestHarness(text: 'one two');
      await harness.open(selectionOffset: 4);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one xtwo',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 4, end: 5),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'one two',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();

      expect(_value(tester).text, 'one two');
      expect(harness.gateway.requests, isEmpty);
      await tester.runAsync(harness.controller.close);
    },
  );
}

TextEditingValue _value(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.value;
