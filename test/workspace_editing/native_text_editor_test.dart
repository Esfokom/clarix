import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  testWidgets(
    'single click enters with a collapsed caret, not block selection',
    (tester) async {
      final harness = NativeEditorTestHarness(text: 'one two');
      await harness.open();
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final rect = tester.getRect(
        find.byKey(const Key('clarix-native-editor')),
      );
      await tester.tapAt(rect.topLeft + const Offset(73, 15));
      await tester.pump();

      final value = _value(tester);
      expect(value.selection.isCollapsed, isTrue);
      expect(value.selection.extentOffset, inInclusiveRange(3, 5));
      await tester.runAsync(harness.controller.close);
    },
  );

  testWidgets(
    'double click selects a word and drag keeps a valid UTF-16 range',
    (tester) async {
      final harness = NativeEditorTestHarness();
      await harness.open();
      await tester.pumpWidget(harness.widget());
      await tester.pump();
      final editableState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final renderEditable = editableState.renderEditable;
      final word = renderEditable.localToGlobal(
        renderEditable
            .getLocalRectForCaret(const TextPosition(offset: 5))
            .center,
      );

      await tester.tapAt(word, buttons: kPrimaryButton);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(word, buttons: kPrimaryButton);
      await tester.pump();
      expect(_value(tester).selection.textInside(_value(tester).text), 'two');

      final gesture = await tester.startGesture(word);
      final end = renderEditable.localToGlobal(
        renderEditable
            .getLocalRectForCaret(
              TextPosition(offset: _value(tester).text.length),
            )
            .center,
      );
      await gesture.moveTo(end);
      await gesture.up();
      await tester.pump();
      final selection = _value(tester).selection;
      expect(selection.isValid, isTrue);
      expect(
        selection.extentOffset,
        inInclusiveRange(0, _value(tester).text.length),
      );
      await tester.runAsync(harness.controller.close);
    },
  );

  testWidgets('keyboard, clipboard, history, space, and escape stay owned', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var undo = 0;
    var redo = 0;
    final harness = NativeEditorTestHarness(text: 'one two');
    await harness.open(selectionOffset: 7);
    await tester.pumpWidget(
      harness.widget(onUndo: () => undo++, onRedo: () => redo++),
    );
    await tester.pump();

    tester.testTextInput.enterText('one two ');
    await tester.pump();
    expect(_value(tester).text, 'one two ');

    await _controlKey(tester, LogicalKeyboardKey.keyA);
    expect(
      _value(tester).selection,
      const TextSelection(baseOffset: 0, extentOffset: 8),
    );
    await _controlKey(tester, LogicalKeyboardKey.keyC);
    expect(clipboardText, 'one two ');
    await _controlKey(tester, LogicalKeyboardKey.keyX);
    expect(_value(tester).text, isEmpty);
    await _controlKey(tester, LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(_value(tester).text, 'one two ');

    await _controlKey(tester, LogicalKeyboardKey.keyZ);
    await _controlKey(tester, LogicalKeyboardKey.keyY);
    expect(undo, 1);
    expect(redo, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(_value(tester).text, 'one two ');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(harness.controller.state.selection, isNull);
    await tester.runAsync(harness.controller.close);
  });

  testWidgets('Home End arrows and deletion respect grapheme boundaries', (
    tester,
  ) async {
    const text = 'A👩🏽‍💻';
    final harness = NativeEditorTestHarness(text: text);
    await harness.open(selectionOffset: text.length);
    await tester.pumpWidget(harness.widget());
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_value(tester).selection.extentOffset, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(_value(tester).text, 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(_value(tester).text, isEmpty);

    await tester.runAsync(harness.controller.close);
  });

  testWidgets('triple click selects the visual line', (tester) async {
    final harness = NativeEditorTestHarness(text: 'one two\nthree');
    await harness.open();
    await tester.pumpWidget(harness.widget());
    await tester.pump();
    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final renderEditable = editableState.renderEditable;
    final point = renderEditable.localToGlobal(
      renderEditable.getLocalRectForCaret(const TextPosition(offset: 2)).center,
    );

    await tester.tapAt(point, buttons: kPrimaryButton);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(point, buttons: kPrimaryButton);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(point, buttons: kPrimaryButton);
    await tester.pump();

    expect(
      _value(tester).selection.textInside(_value(tester).text),
      'one two\n',
    );
    await tester.runAsync(harness.controller.close);
  });

  testWidgets('acknowledgement preserves the focused editor', (tester) async {
    final harness = NativeEditorTestHarness(text: 'Before');
    await harness.open(selectionOffset: 6);
    await tester.pumpWidget(harness.widget());
    await tester.pump();

    tester.testTextInput.enterText('After');
    await tester.pump();
    await tester.pump();

    expect(harness.gateway.requests, hasLength(1));
    expect(_value(tester).text, 'After');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    await tester.runAsync(harness.controller.close);
  });
}

TextEditingValue _value(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.value;

Future<void> _controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}
