import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/pdf_text_types.dart';

final class PdfInlineTextGeometry {
  const PdfInlineTextGeometry({
    required this.fontSize,
    required this.angleRadians,
    required this.baselineY,
    required this.scaleX,
    required this.scaleY,
  });

  final double fontSize;
  final double angleRadians;
  final double baselineY;
  final double scaleX;
  final double scaleY;

  factory PdfInlineTextGeometry.resolve({
    required PdfTextBlock block,
    required Size pageSize,
    required Size overlaySize,
  }) {
    final scaleX = overlaySize.width / pageSize.width;
    final scaleY = overlaySize.height / pageSize.height;
    return PdfInlineTextGeometry(
      fontSize: block.runs.first.style.fontSize * scaleY,
      angleRadians: math.atan2(block.transform.b, block.transform.a),
      baselineY: overlaySize.height - block.baseline * scaleY,
      scaleX: scaleX,
      scaleY: scaleY,
    );
  }
}

final class PdfInlineTextEditor extends StatelessWidget {
  const PdfInlineTextEditor({
    required this.block,
    required this.controller,
    required this.focusNode,
    required this.geometry,
    required this.onChanged,
    super.key,
  });

  final PdfTextBlock block;
  final TextEditingController controller;
  final FocusNode focusNode;
  final PdfInlineTextGeometry geometry;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = block.runs.first.style;
    return ClipRect(
      child: Transform.rotate(
        angle: geometry.angleRadians,
        alignment: Alignment.center,
        child: EditableText(
          key: const Key('pdf-inline-text-editor'),
          controller: controller,
          focusNode: focusNode,
          style: TextStyle(
            fontFamily: style.fontFamily,
            fontSize: geometry.fontSize,
            color: Color(style.fillColorValue),
            height: 1,
            fontWeight: FontWeight
                .values[((style.fontWeight / 100).round() - 1).clamp(0, 8)],
            fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          ),
          cursorColor: Theme.of(context).colorScheme.primary,
          backgroundCursorColor: Colors.transparent,
          selectionColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.22),
          textDirection:
              block.writingDirection == PdfWritingDirection.rightToLeft
              ? TextDirection.rtl
              : TextDirection.ltr,
          maxLines: null,
          expands: true,
          selectionControls: materialTextSelectionControls,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
