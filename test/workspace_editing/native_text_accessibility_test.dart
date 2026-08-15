import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  testWidgets('editable text exposes stable value and selection actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = NativeEditorTestHarness(text: 'Accessible');
    await harness.open(selectionOffset: 2);
    await tester.pumpWidget(harness.widget());
    await tester.pump();

    final node = tester.getSemantics(
      find.byKey(const Key('clarix-native-editor-semantics')),
    );
    expect(node.getSemanticsData().flagsCollection.isTextField, isTrue);
    expect(node.getSemanticsData().flagsCollection.isReadOnly, isFalse);
    expect(node.value, 'Accessible');
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.setSelection),
      isTrue,
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.setText), isTrue);

    node.owner!.performAction(
      node.id,
      SemanticsAction.setSelection,
      const <String, int>{'base': 0, 'extent': 6},
    );
    await tester.pump();
    expect(harness.controller.state.selection?.range.end, 6);

    semantics.dispose();
    await tester.runAsync(harness.controller.close);
  });

  testWidgets('read-only reason is announced and mutation actions are absent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = NativeEditorTestHarness(
      text: 'Protected',
      capability: 'read_only',
    );
    await harness.open();
    await tester.pumpWidget(harness.widget());
    await tester.pump();

    final node = tester.getSemantics(
      find.byKey(const Key('clarix-native-editor-semantics')),
    );
    expect(node.getSemanticsData().flagsCollection.isReadOnly, isTrue);
    expect(node.hint, 'unsupported_font');
    expect(node.getSemanticsData().hasAction(SemanticsAction.setText), isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.cut), isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.copy), isTrue);

    semantics.dispose();
    await tester.runAsync(harness.controller.close);
  });
}
