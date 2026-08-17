import '../domain/pdf_text_types.dart';

typedef PdfNativeGlyphAdvance =
    double Function(int codePoint, PdfTextStyle style);
typedef PdfNativeLineHeight = double Function(PdfTextStyle style);

final class PdfNativeLayoutLine {
  const PdfNativeLayoutLine({
    required this.range,
    required this.text,
    required this.originX,
    required this.baseline,
  });

  final PdfTextRange range;
  final String text;
  final double originX;
  final double baseline;
}

final class PdfNativeTextLayout {
  const PdfNativeTextLayout({required this.lines, required this.overflow});

  final List<PdfNativeLayoutLine> lines;
  final bool overflow;
}

final class PdfNativeTextLayoutEngine {
  const PdfNativeTextLayoutEngine();

  PdfNativeTextLayout layout({
    required String text,
    required List<PdfTextRun> runs,
    required PdfBox bounds,
    required double baseline,
    required PdfNativeGlyphAdvance advance,
    required PdfNativeLineHeight lineHeight,
    required PdfWritingDirection direction,
  }) {
    if (direction != PdfWritingDirection.leftToRight) {
      throw UnsupportedError('Only left-to-right native reflow is supported.');
    }
    if (runs.isEmpty || text.isEmpty) {
      return const PdfNativeTextLayout(
        lines: <PdfNativeLayoutLine>[],
        overflow: false,
      );
    }
    final ranges = <PdfTextRange>[];
    var lineStart = 0;
    var index = 0;
    var width = 0.0;
    int? lastBreak;
    while (index < text.length) {
      final firstUnit = text.codeUnitAt(index);
      final isSurrogate =
          firstUnit & 0xfc00 == 0xd800 && index + 1 < text.length;
      final codePoint = isSurrogate
          ? 0x10000 +
                ((firstUnit - 0xd800) << 10) +
                (text.codeUnitAt(index + 1) - 0xdc00)
          : firstUnit;
      final length = codePoint > 0xffff ? 2 : 1;
      if (codePoint == 0x0a) {
        ranges.add(PdfTextRange(lineStart, index));
        index += length;
        lineStart = index;
        width = 0;
        lastBreak = null;
        continue;
      }
      final style = _styleAt(runs, index);
      final nextWidth = width + advance(codePoint, style);
      if (nextWidth > bounds.width && index > lineStart) {
        final breakOffset = lastBreak;
        final end = breakOffset != null && breakOffset > lineStart
            ? breakOffset
            : index;
        ranges.add(PdfTextRange(lineStart, end));
        lineStart = end;
        index = end;
        width = 0;
        lastBreak = null;
        continue;
      }
      width = nextWidth;
      index += length;
      if (codePoint == 0x20 || codePoint == 0x09) lastBreak = index;
    }
    if (lineStart <= text.length) {
      ranges.add(PdfTextRange(lineStart, text.length));
    }

    final lines = <PdfNativeLayoutLine>[];
    var currentBaseline = baseline;
    var overflow = false;
    for (final range in ranges) {
      final style = _styleAt(runs, range.start.clamp(0, text.length - 1));
      final lineText = text.substring(range.start, range.end);
      final lineWidth = _measure(lineText, style, advance);
      final originX = switch (style.alignment) {
        PdfTextAlignment.center => bounds.left + (bounds.width - lineWidth) / 2,
        PdfTextAlignment.right => bounds.right - lineWidth,
        _ => bounds.left,
      };
      lines.add(
        PdfNativeLayoutLine(
          range: range,
          text: lineText,
          originX: originX,
          baseline: currentBaseline,
        ),
      );
      currentBaseline -= lineHeight(style);
      if (currentBaseline < bounds.bottom) overflow = true;
    }
    return PdfNativeTextLayout(
      lines: List<PdfNativeLayoutLine>.unmodifiable(lines),
      overflow: overflow,
    );
  }
}

PdfTextStyle _styleAt(List<PdfTextRun> runs, int offset) => runs
    .firstWhere(
      (run) => run.range.start <= offset && offset < run.range.end,
      orElse: () => runs.last,
    )
    .style;

double _measure(
  String text,
  PdfTextStyle style,
  PdfNativeGlyphAdvance advance,
) => text.runes.fold<double>(0, (width, rune) => width + advance(rune, style));
