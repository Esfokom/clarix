import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

/// Result of applying one non-IME text-navigation key to an editing value.
final class TextNavigationResult {
  const TextNavigationResult(this.value, {required this.textChanged});

  final TextEditingValue value;
  final bool textChanged;
}

/// Performs grapheme-safe cursor movement, selection extension and deletion.
/// Returns null for keys that belong to the platform IME.
TextNavigationResult? editTextForKey(
  TextEditingValue value,
  LogicalKeyboardKey key, {
  required bool extendSelection,
}) {
  final boundaries = _graphemeBoundaries(value.text);
  final selection = value.selection;
  if (!selection.isValid) return null;
  final start = selection.start;
  final end = selection.end;

  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.home ||
      key == LogicalKeyboardKey.end) {
    final towardStart =
        key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.home;
    final target = switch (key) {
      LogicalKeyboardKey.arrowLeft => _previousBoundary(
        boundaries,
        selection.extentOffset,
      ),
      LogicalKeyboardKey.arrowRight => _nextBoundary(
        boundaries,
        selection.extentOffset,
      ),
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => value.text.length,
      _ => selection.extentOffset,
    };
    final next = !extendSelection && !selection.isCollapsed
        ? (towardStart ? start : end)
        : target;
    return TextNavigationResult(
      value.copyWith(
        selection: extendSelection
            ? TextSelection(
                baseOffset: selection.baseOffset,
                extentOffset: target,
              )
            : TextSelection.collapsed(offset: next),
        composing: TextRange.empty,
      ),
      textChanged: false,
    );
  }

  if (key != LogicalKeyboardKey.backspace && key != LogicalKeyboardKey.delete) {
    return null;
  }
  final deleteStart = !selection.isCollapsed
      ? start
      : key == LogicalKeyboardKey.backspace
      ? _previousBoundary(boundaries, start)
      : start;
  final deleteEnd = !selection.isCollapsed
      ? end
      : key == LogicalKeyboardKey.delete
      ? _nextBoundary(boundaries, end)
      : end;
  if (deleteStart == deleteEnd) {
    return TextNavigationResult(value, textChanged: false);
  }
  final text = value.text.replaceRange(deleteStart, deleteEnd, '');
  return TextNavigationResult(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: deleteStart),
    ),
    textChanged: true,
  );
}

List<int> _graphemeBoundaries(String text) {
  var offset = 0;
  return <int>[
    0,
    ...text.characters.map((character) {
      offset += character.length;
      return offset;
    }),
  ];
}

int _previousBoundary(List<int> boundaries, int offset) {
  for (var index = boundaries.length - 1; index >= 0; index--) {
    if (boundaries[index] < offset) return boundaries[index];
  }
  return 0;
}

int _nextBoundary(List<int> boundaries, int offset) {
  for (final boundary in boundaries) {
    if (boundary > offset) return boundary;
  }
  return boundaries.last;
}
