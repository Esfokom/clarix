import 'package:clarix/src/features/pdf_editor/presentation/text_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moves and deletes whole emoji graphemes', () {
    const value = TextEditingValue(
      text: 'A👩🏽‍💻B',
      selection: TextSelection.collapsed(offset: 8),
    );
    final left = editTextForKey(
      value,
      LogicalKeyboardKey.arrowLeft,
      extendSelection: false,
    )!;
    expect(left.value.selection, const TextSelection.collapsed(offset: 1));
    final deleted = editTextForKey(
      left.value,
      LogicalKeyboardKey.delete,
      extendSelection: false,
    )!;
    expect(deleted.value.text, 'AB');
    expect(deleted.value.selection, const TextSelection.collapsed(offset: 1));
  });

  test('extends and deletes a selection', () {
    const value = TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 1),
    );
    final extended = editTextForKey(
      value,
      LogicalKeyboardKey.arrowRight,
      extendSelection: true,
    )!;
    expect(
      extended.value.selection,
      const TextSelection(baseOffset: 1, extentOffset: 2),
    );
    final deleted = editTextForKey(
      extended.value,
      LogicalKeyboardKey.backspace,
      extendSelection: false,
    )!;
    expect(deleted.value.text, 'ac');
    expect(deleted.value.selection, const TextSelection.collapsed(offset: 1));
  });

  test('home and end navigate without changing text', () {
    const value = TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(
      editTextForKey(
        value,
        LogicalKeyboardKey.home,
        extendSelection: false,
      )!.value.selection,
      const TextSelection.collapsed(offset: 0),
    );
    expect(
      editTextForKey(
        value,
        LogicalKeyboardKey.end,
        extendSelection: false,
      )!.value.selection,
      const TextSelection.collapsed(offset: 3),
    );
  });
}
