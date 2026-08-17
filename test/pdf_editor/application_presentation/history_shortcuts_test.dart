import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  testWidgets('undo redo shortcuts and checkpoints use typed native commands', (
    tester,
  ) async {
    final harness = NativeEditorTestHarness();
    await harness.open();

    await harness.controller.createCheckpoint('Before formatting');
    await harness.controller.submitCommand(
      EditorCommand(
        kind: EditorCommandKind.setTextStyle,
        objectId: harnessObjectId,
        start: 0,
        end: 1,
        style: harness.gateway.object.runs.single.style,
      ),
    );
    await tester.pumpWidget(
      harness.widget(
        onUndo: () => harness.controller.dispatchCommand(
          const EditorCommand(kind: EditorCommandKind.undo),
        ),
        onRedo: () => harness.controller.dispatchCommand(
          const EditorCommand(kind: EditorCommandKind.redo),
        ),
      ),
    );
    await tester.pump();
    await _controlKey(tester, LogicalKeyboardKey.keyZ);
    await _controlKey(tester, LogicalKeyboardKey.keyY);

    expect(
      harness.gateway.requests.map((request) => request.payload.kind),
      <EditorCommandKind>[
        EditorCommandKind.createCheckpoint,
        EditorCommandKind.setTextStyle,
        EditorCommandKind.undo,
        EditorCommandKind.redo,
      ],
    );
    expect(harness.gateway.requests.first.payload.label, 'Before formatting');
    await tester.runAsync(harness.controller.close);
  });
}

Future<void> _controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}
