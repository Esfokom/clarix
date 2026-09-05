import 'package:clarix/src/features/pdf_editor/domain/editor_document_state.dart';
import 'package:clarix/src/features/pdf_editor/presentation/page_edit_scene.dart';
import 'package:clarix/src/features/pdf_editor/presentation/session_text_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  Future<NativeEditorTestHarness> mount(WidgetTester tester) async {
    final harness = NativeEditorTestHarness(text: 'one two');
    await harness.open(selectionOffset: 7);
    addTearDown(harness.controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamBuilder<EditorDocumentState>(
            stream: harness.controller.changes,
            initialData: harness.controller.state,
            builder: (context, snapshot) => PageEditScene(
              scene: snapshot.data!.scenes[1]!,
              document: snapshot.data!,
              session: harness.controller,
              editingEnabled: true,
              displaySize: const Size(420, 72),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return harness;
  }

  testWidgets('accepted revisions preserve the active input connection', (
    tester,
  ) async {
    final harness = await mount(tester);
    final input = tester.state(find.byType(SessionTextInput));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'one two!',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    await harness.controller.flushCommands();
    await tester.pump();
    expect(tester.state(find.byType(SessionTextInput)), same(input));
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(harness.controller.state.scenes[1]!.objects.single.text, 'one two!');
  });

  testWidgets('select all and backspace clear the active paragraph', (
    tester,
  ) async {
    final harness = await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(harness.controller.state.selection!.range.start, 0);
    expect(harness.controller.state.selection!.range.end, 7);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await harness.controller.flushCommands();
    expect(harness.controller.state.visibleText('object-1'), '');
  });

  testWidgets('escape leaves text editing selection', (tester) async {
    final harness = await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(harness.controller.state.selection, isNull);
  });

  testWidgets('backward shift selection keeps its anchor across rebuilds', (
    tester,
  ) async {
    final harness = await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(harness.controller.state.selection!.range.start, 5);
    expect(harness.controller.state.selection!.range.end, 7);
  });

  testWidgets('clipboard paste replaces the selected paragraph', (
    tester,
  ) async {
    final harness = await mount(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'pasted'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await harness.controller.flushCommands();
    expect(harness.controller.state.visibleText('object-1'), 'pasted');
  });
}
