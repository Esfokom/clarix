import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import '../domain/editor_selection.dart';
import 'text_delta.dart';
import 'text_navigation.dart';

/// Invisible IME client that drives [EditorSessionController] edits for one
/// active object.
///
/// Nothing is painted here — the PDF page keeps rendering the real content in
/// its own fonts. This widget only owns focus and the platform text-input
/// connection, translating keystrokes (including backspace and IME
/// composition) into [EditorSessionController.applyLocalDelta] calls. The
/// caret itself is painted by the scene from PDF character geometry.
final class SessionTextInput extends StatefulWidget {
  const SessionTextInput({
    required this.session,
    required this.object,
    required this.text,
    required this.selection,
    this.onSelectionChanged,
    this.onEscape,
    this.onUndo,
    this.onRedo,
    super.key,
  });

  final EditorSessionController session;
  final EditorSceneObject object;
  final String text;
  final EditorSelection selection;
  final ValueChanged<EditorTextRange>? onSelectionChanged;
  final VoidCallback? onEscape;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  State<SessionTextInput> createState() => _SessionTextInputState();
}

final class _SessionTextInputState extends State<SessionTextInput>
    with TextInputClient {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Session PDF text input');
  TextInputConnection? _connection;
  late TextEditingValue _value;
  TextEditingValue? _compositionBase;
  final List<String> _pendingTexts = <String>[];
  bool _attachScheduled = false;

  @override
  void initState() {
    super.initState();
    _value = _valueFor(widget);
    _focusNode.addListener(_handleFocusChanged);
    widget.session.setCompositionCommitter(_commitComposition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(SessionTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.setCompositionCommitter(null);
      widget.session.setCompositionCommitter(_commitComposition);
    }
    if (oldWidget.object.objectId != widget.object.objectId) {
      _pendingTexts.clear();
      _compositionBase = null;
      _value = _valueFor(widget);
      _connection?.setEditingState(_value);
    } else if (widget.text != _value.text &&
        _compositionBase == null &&
        !_acknowledgePending(widget.text)) {
      _pendingTexts.clear();
      _value = _valueFor(widget);
      _connection?.setEditingState(_value);
    } else {
      _acknowledgePending(widget.text);
      final start = widget.selection.range.start.clamp(0, _value.text.length);
      final end = widget.selection.range.end.clamp(start, _value.text.length);
      final selection = TextSelection(baseOffset: start, extentOffset: end);
      if (_value.selection.start != selection.start ||
          _value.selection.end != selection.end) {
        _value = _value.copyWith(selection: selection);
        _connection?.setEditingState(_value);
      }
    }
    if ((oldWidget.selection.range != widget.selection.range ||
            oldWidget.object.objectId != widget.object.objectId) &&
        mounted &&
        !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.session.setCompositionCommitter(null);
    _focusNode.removeListener(_handleFocusChanged);
    _connection?.close();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    key: const Key('session-text-input'),
    focusNode: _focusNode,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onEscape?.call();
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          widget.onRedo?.call();
        } else {
          widget.onUndo?.call();
        }
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyA) {
        _value = _value.copyWith(
          selection: TextSelection(
            baseOffset: 0,
            extentOffset: _value.text.length,
          ),
        );
        _notifySelection(_value);
        _connection?.setEditingState(_value);
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isControlPressed) {
        if (event.logicalKey == LogicalKeyboardKey.keyC ||
            event.logicalKey == LogicalKeyboardKey.keyX) {
          final range = _value.selection;
          if (range.isValid && !range.isCollapsed) {
            unawaited(
              Clipboard.setData(
                ClipboardData(text: range.textInside(_value.text)),
              ),
            );
            if (event.logicalKey == LogicalKeyboardKey.keyX) {
              _replaceSelection('');
            }
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyV) {
          unawaited(_paste());
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyY) {
          widget.onRedo?.call();
          return KeyEventResult.handled;
        }
      }
      if (_value.composing.isValid && !_value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      final result = editTextForKey(
        _value,
        event.logicalKey,
        extendSelection: HardwareKeyboard.instance.isShiftPressed,
      );
      if (result == null) return KeyEventResult.ignored;
      if (result.textChanged) {
        updateEditingValue(result.value);
      } else {
        _value = result.value;
        _notifySelection(_value);
      }
      _connection?.setEditingState(_value);
      return KeyEventResult.handled;
    },
    child: const SizedBox.expand(),
  );

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _scheduleAttach();
    } else {
      _connection?.close();
      _connection = null;
    }
  }

  Future<void> _paste() async {
    final objectId = widget.object.objectId;
    final before = _value;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        !_focusNode.hasFocus ||
        widget.object.objectId != objectId ||
        _value != before ||
        data?.text == null) {
      return;
    }
    _replaceSelection(data!.text!);
  }

  void _replaceSelection(String text) {
    final selection = _value.selection;
    if (!selection.isValid) return;
    updateEditingValue(
      TextEditingValue(
        text: _value.text.replaceRange(selection.start, selection.end, text),
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      ),
    );
    _connection?.setEditingState(_value);
  }

  void _scheduleAttach() {
    if (_attachScheduled || _connection != null) return;
    _attachScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScheduled = false;
      if (!mounted || !_focusNode.hasFocus || _connection != null) return;
      final connection = TextInput.attach(
        this,
        TextInputConfiguration(
          viewId: View.of(context).viewId,
          inputType: TextInputType.multiline,
          inputAction: TextInputAction.newline,
          autocorrect: true,
          enableSuggestions: true,
        ),
      );
      _connection = connection;
      connection
        ..setEditingState(_value)
        ..show();
    });
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (value == _value) return;
    final previous = _value;
    _value = value;
    _notifySelection(value);
    final composing = value.composing.isValid && !value.composing.isCollapsed;
    if (composing) {
      _compositionBase ??= previous;
      return;
    }
    final base = _compositionBase ?? previous;
    _compositionBase = null;
    if (value.text == base.text) return;
    final delta = computeTextDelta(base.text, value.text);
    if (delta.replacement.isEmpty && delta.start == delta.end) return;
    _pendingTexts.add(value.text);
    widget.session.applyLocalDelta(
      objectId: widget.object.objectId,
      range: EditorTextRange(start: delta.start, end: delta.end),
      replacement: delta.replacement,
    );
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
  }

  Future<void> _commitComposition() async {
    if (!_value.composing.isValid || _value.composing.isCollapsed) return;
    final committed = _value.copyWith(composing: TextRange.empty);
    updateEditingValue(committed);
    _connection?.setEditingState(_value);
    await Future<void>.value();
  }

  bool _acknowledgePending(String text) {
    final index = _pendingTexts.indexOf(text);
    if (index == -1) return false;
    _pendingTexts.removeRange(0, index + 1);
    return true;
  }

  void _notifySelection(TextEditingValue value) {
    if (!value.selection.isValid) return;
    widget.onSelectionChanged?.call(
      EditorTextRange(start: value.selection.start, end: value.selection.end),
    );
  }

  static TextEditingValue _valueFor(SessionTextInput widget) {
    final start = widget.selection.range.start.clamp(0, widget.text.length);
    final end = widget.selection.range.end.clamp(start, widget.text.length);
    return TextEditingValue(
      text: widget.text,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
  }
}
