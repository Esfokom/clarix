import 'package:flutter/material.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'editor_semantics.dart';
import 'editor_shortcuts.dart';

class NativeTextEditor extends StatefulWidget {
  const NativeTextEditor({
    required this.session,
    required this.object,
    required this.text,
    required this.selection,
    this.onEscape,
    this.onUndo,
    this.onRedo,
    this.autofocus = true,
    this.scale = 1,
    super.key,
  });

  final EditorSessionController session;
  final EditorSceneObject object;
  final String text;
  final EditorSelection selection;
  final VoidCallback? onEscape;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool autofocus;
  final double scale;

  @override
  State<NativeTextEditor> createState() => _NativeTextEditorState();
}

class _NativeTextEditorState extends State<NativeTextEditor> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late TextEditingValue _lastValue;
  TextEditingValue? _compositionBase;
  bool _updatingFromModel = false;

  @override
  void initState() {
    super.initState();
    _lastValue = _initialValue(widget);
    _textController = TextEditingController.fromValue(_lastValue)
      ..addListener(_handleEditingValue);
    _focusNode = FocusNode(debugLabel: 'Clarix native PDF text editor');
    widget.session.setCompositionCommitter(_commitComposition);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant NativeTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.objectId != widget.object.objectId) {
      _replaceFromModel(_initialValue(widget));
      return;
    }
    if (widget.text != _textController.text && _compositionBase == null) {
      final selection = _textController.selection;
      _replaceFromModel(
        TextEditingValue(
          text: widget.text,
          selection: TextSelection(
            baseOffset: selection.baseOffset.clamp(0, widget.text.length),
            extentOffset: selection.extentOffset.clamp(0, widget.text.length),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.session.setCompositionCommitter(null);
    _textController
      ..removeListener(_handleEditingValue)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _textStyle(widget.object, widget.scale);
    return EditorSemantics(
      controller: _textController,
      focusNode: _focusNode,
      readOnlyReason: widget.object.capability == 'editable'
          ? null
          : widget.object.capabilityReason ?? 'This PDF text is read only.',
      child: EditorShortcuts(
        onEscape: () {
          widget.session.updateSelection(null);
          widget.onEscape?.call();
        },
        onUndo: widget.onUndo,
        onRedo: widget.onRedo,
        child: DefaultSelectionStyle(
          selectionColor: const Color(0x553b82f6),
          cursorColor: const Color(0xff2f80ed),
          child: TextField(
            key: const Key('clarix-native-editor'),
            controller: _textController,
            focusNode: _focusNode,
            style: style,
            cursorColor: const Color(0xff2f80ed),
            textDirection: widget.object.layout?.direction == 'rtl'
                ? TextDirection.rtl
                : TextDirection.ltr,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            readOnly: widget.object.capability != 'editable',
            maxLines: null,
            minLines: null,
            expands: true,
            autofocus: widget.autofocus,
            selectionControls: materialTextSelectionControls,
            enableInteractiveSelection: true,
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ),
    );
  }

  void _handleEditingValue() {
    if (_updatingFromModel) return;
    final next = _textController.value;
    final previous = _lastValue;
    _lastValue = next;
    if (next.selection.isValid) {
      widget.session.updateSelection(
        EditorSelection(
          objectId: widget.object.objectId,
          range: EditorTextRange(
            start: next.selection.start,
            end: next.selection.end,
          ),
        ),
      );
    }
    final composing = next.composing.isValid && !next.composing.isCollapsed;
    if (composing) {
      _compositionBase ??= previous;
      return;
    }
    final base = _compositionBase ?? previous;
    _compositionBase = null;
    if (next.text == base.text) return;
    final delta = _delta(base.text, next.text);
    widget.session.applyLocalDelta(
      objectId: widget.object.objectId,
      range: EditorTextRange(start: delta.start, end: delta.end),
      replacement: delta.replacement,
    );
  }

  void _replaceFromModel(TextEditingValue value) {
    _updatingFromModel = true;
    _textController.value = value;
    _lastValue = value;
    _compositionBase = null;
    _updatingFromModel = false;
  }

  Future<void> _commitComposition() async {
    final value = _textController.value;
    if (!value.composing.isValid || value.composing.isCollapsed) return;
    _textController.value = value.copyWith(composing: TextRange.empty);
    await Future<void>.value();
  }
}

TextEditingValue _initialValue(NativeTextEditor widget) {
  final start = widget.selection.range.start.clamp(0, widget.text.length);
  final end = widget.selection.range.end.clamp(start, widget.text.length);
  return TextEditingValue(
    text: widget.text,
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

TextStyle _textStyle(EditorSceneObject object, double scale) {
  final source = object.runs.firstOrNull?.style;
  final rgba = source?.colorRgba ?? const <int>[0, 0, 0, 255];
  return TextStyle(
    color: Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]),
    fontFamily: source?.fontFamily,
    fontSize: (source?.fontSize ?? 12) * scale,
    fontWeight: FontWeight
        .values[(((source?.fontWeight ?? 400) ~/ 100) - 1).clamp(0, 8)],
    fontStyle: source?.italic == true ? FontStyle.italic : FontStyle.normal,
    letterSpacing: object.layout == null
        ? null
        : object.layout!.characterSpacing * scale,
    height: source == null || object.layout == null
        ? null
        : object.layout!.lineHeight / source.fontSize,
    decoration: TextDecoration.none,
  );
}

({int start, int end, String replacement}) _delta(String before, String after) {
  final oldUnits = before.codeUnits;
  final newUnits = after.codeUnits;
  var prefix = 0;
  while (prefix < oldUnits.length &&
      prefix < newUnits.length &&
      oldUnits[prefix] == newUnits[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldUnits.length - prefix &&
      suffix < newUnits.length - prefix &&
      oldUnits[oldUnits.length - suffix - 1] ==
          newUnits[newUnits.length - suffix - 1]) {
    suffix++;
  }
  return (
    start: prefix,
    end: oldUnits.length - suffix,
    replacement: String.fromCharCodes(
      newUnits.sublist(prefix, newUnits.length - suffix),
    ),
  );
}
