import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/pdf_edit_session.dart';
import '../../domain/pdf_text_types.dart';

final class PdfNativeTextInput extends StatefulWidget {
  const PdfNativeTextInput({
    required this.block,
    required this.selection,
    required this.onDelta,
    this.onEscape,
    this.onUndo,
    this.onRedo,
    super.key,
  });

  final PdfTextBlock block;
  final PdfTextSelection selection;
  final ValueChanged<PdfTextDelta> onDelta;
  final VoidCallback? onEscape;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  State<PdfNativeTextInput> createState() => _PdfNativeTextInputState();
}

final class _PdfNativeTextInputState extends State<PdfNativeTextInput>
    with TextInputClient {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PDF native text input');
  TextInputConnection? _connection;
  late TextEditingValue _value;
  final List<String> _pendingTexts = <String>[];
  bool _attachScheduled = false;

  @override
  void initState() {
    super.initState();
    _value = _valueFor(widget);
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(PdfNativeTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.locator != widget.block.locator ||
        (widget.block.text != _value.text &&
            widget.block.text != oldWidget.block.text &&
            !_acknowledgePending(widget.block.text))) {
      _pendingTexts.clear();
      _value = _valueFor(widget);
      _connection?.setEditingState(_value);
    } else {
      _acknowledgePending(widget.block.text);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _connection?.close();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    key: const Key('pdf-native-text-input'),
    focusNode: _focusNode,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
      return KeyEventResult.ignored;
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

  void _scheduleAttach() {
    if (_attachScheduled || _connection != null) return;
    _attachScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScheduled = false;
      if (!mounted || !_focusNode.hasFocus || _connection != null) return;
      // Attaching in the focus callback can happen before Flutter has assigned
      // a view ID to this overlay on Windows.  Waiting for the next frame gives
      // the framework a mounted view and avoids a dead text-input client.
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
    final delta = PdfTextDelta.between(_value.text, value.text);
    _value = value;
    if (delta.replacedRange.isEmpty && delta.insertedText.isEmpty) return;
    _pendingTexts.add(value.text);
    widget.onDelta(delta);
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

  bool _acknowledgePending(String text) {
    final index = _pendingTexts.indexOf(text);
    if (index == -1) return false;
    _pendingTexts.removeRange(0, index + 1);
    return true;
  }

  static TextEditingValue _valueFor(PdfNativeTextInput widget) {
    final start = widget.selection.range.start.clamp(
      0,
      widget.block.text.length,
    );
    final end = widget.selection.range.end.clamp(
      start,
      widget.block.text.length,
    );
    return TextEditingValue(
      text: widget.block.text,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
  }
}
