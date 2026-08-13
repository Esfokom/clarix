import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/pdf_edit_intent.dart';
import '../../domain/pdf_edit_session.dart';
import '../../domain/pdf_text_types.dart';

typedef PdfTextBlockRectResolver = Rect Function(PdfTextBlock block);

final class PdfTextEditorOverlay extends StatefulWidget {
  const PdfTextEditorOverlay({
    required this.mode,
    required this.blocks,
    required this.selection,
    required this.rectForBlock,
    required this.onSelect,
    this.loading = false,
    this.documentId,
    this.documentRevision,
    this.caseMatching = true,
    this.onIntent,
    this.onClearSelection,
    super.key,
  });

  final PdfEditingMode mode;
  final List<PdfTextBlock> blocks;
  final PdfTextSelection? selection;
  final PdfTextBlockRectResolver rectForBlock;
  final ValueChanged<PdfTextBlockLocator> onSelect;
  final bool loading;
  final String? documentId;
  final String? documentRevision;
  final bool caseMatching;
  final ValueChanged<ReplacePdfTextIntent>? onIntent;
  final VoidCallback? onClearSelection;

  @override
  State<PdfTextEditorOverlay> createState() => _PdfTextEditorOverlayState();
}

final class _PdfTextEditorOverlayState extends State<PdfTextEditorOverlay> {
  PdfTextBlockLocator? _hovered;
  TextEditingController? _textController;
  FocusNode? _focusNode;
  PdfTextBlockLocator? _editingLocator;
  String? _lastText;
  String? _typingGroup;

  @override
  void dispose() {
    _textController?.dispose();
    _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode != PdfEditingMode.text) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final block in widget.blocks) _outline(block),
        if (widget.loading)
          const Positioned(
            top: 8,
            right: 8,
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
      ],
    );
  }

  Widget _outline(PdfTextBlock block) {
    final selected = widget.selection?.locator == block.locator;
    final hovered = _hovered == block.locator;
    final readOnly = block.readOnlyReason != null;
    final Color color = block.overflow
        ? const Color(0xffd97706)
        : readOnly
        ? const Color(0xffa16207)
        : selected
        ? const Color(0xff2563eb)
        : hovered
        ? const Color(0xff64748b)
        : const Color(0x66718096);
    if (selected && block.isEditable && widget.onIntent != null) {
      return _inlineEditor(block);
    }
    return Positioned.fromRect(
      rect: widget.rectForBlock(block),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = block.locator),
        onExit: (_) {
          if (_hovered == block.locator) setState(() => _hovered = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => widget.onSelect(block.locator),
          child: Container(
            key: const Key('pdf-text-block-outline'),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.06) : null,
              border: Border.all(color: color, width: selected ? 1.2 : 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
            child: readOnly
                ? Align(
                    key: const Key('pdf-text-block-read-only'),
                    alignment: Alignment.topRight,
                    child: Icon(Icons.lock_outline, size: 11, color: color),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _inlineEditor(PdfTextBlock block) {
    if (_editingLocator != block.locator) {
      _textController?.dispose();
      _focusNode?.dispose();
      _editingLocator = block.locator;
      _lastText = block.text;
      _typingGroup = _newTypingGroup();
      _textController = TextEditingController(text: block.text);
      _focusNode = FocusNode()..requestFocus();
    } else if (_textController!.text != block.text && _lastText != block.text) {
      final selection = _textController!.selection;
      _textController!.value = TextEditingValue(
        text: block.text,
        selection: TextSelection.collapsed(
          offset: selection.extentOffset.clamp(0, block.text.length),
        ),
      );
      _lastText = block.text;
    }
    return Positioned.fromRect(
      rect: widget.rectForBlock(block),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _typingGroup = null;
            widget.onClearSelection?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          key: const Key('pdf-inline-text-editor'),
          controller: _textController,
          focusNode: _focusNode,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
            fontFamily: block.runs.first.style.fontFamily,
            fontSize: block.runs.first.style.fontSize,
            color: Color(block.runs.first.style.fillColorValue),
            height: 1,
          ),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onTapOutside: (_) {
            _typingGroup = null;
            _focusNode?.unfocus();
          },
          onChanged: (next) {
            final before = _lastText ?? block.text;
            final delta = PdfTextDelta.between(before, next);
            _lastText = next;
            widget.onIntent!(
              ReplacePdfTextIntent(
                documentId: widget.documentId!,
                documentRevision: widget.documentRevision!,
                locator: block.locator,
                range: delta.replacedRange,
                replacement: delta.insertedText,
                caseMatching: widget.caseMatching,
                coalescingKey: _typingGroup ??= _newTypingGroup(),
              ),
            );
          },
        ),
      ),
    );
  }

  String _newTypingGroup() =>
      'typing-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
}
