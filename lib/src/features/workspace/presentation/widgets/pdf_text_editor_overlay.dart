import 'package:flutter/material.dart';

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
    super.key,
  });

  final PdfEditingMode mode;
  final List<PdfTextBlock> blocks;
  final PdfTextSelection? selection;
  final PdfTextBlockRectResolver rectForBlock;
  final ValueChanged<PdfTextBlockLocator> onSelect;
  final bool loading;

  @override
  State<PdfTextEditorOverlay> createState() => _PdfTextEditorOverlayState();
}

final class _PdfTextEditorOverlayState extends State<PdfTextEditorOverlay> {
  PdfTextBlockLocator? _hovered;

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
}
