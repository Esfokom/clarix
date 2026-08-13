import 'dart:math' as math;

import 'pdf_text_types.dart';

abstract interface class PdfTextMetrics {
  double get lineHeight;
  double measure(String text, PdfTextStyle style);
}

final class PdfMonospaceTextMetrics implements PdfTextMetrics {
  const PdfMonospaceTextMetrics({
    required this.advance,
    required this.lineHeight,
  });

  final double advance;

  @override
  final double lineHeight;

  @override
  double measure(String text, PdfTextStyle style) {
    if (text.isEmpty) return 0;
    final double glyphWidth = advance * style.horizontalScaling / 100;
    return text.runes.length * glyphWidth +
        math.max(0, text.runes.length - 1) * style.characterSpacing;
  }
}

final class PdfLaidOutLine {
  const PdfLaidOutLine({
    required this.text,
    required this.originX,
    required this.baseline,
    required this.width,
  });

  final String text;
  final double originX;
  final double baseline;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is PdfLaidOutLine &&
      other.text == text &&
      other.originX == originX &&
      other.baseline == baseline &&
      other.width == width;

  @override
  int get hashCode => Object.hash(text, originX, baseline, width);
}

final class PdfTextLayoutResult {
  PdfTextLayoutResult({
    required List<PdfLaidOutLine> lines,
    required this.usedBounds,
    required this.overflow,
    required this.effectiveStyle,
  }) : lines = List<PdfLaidOutLine>.unmodifiable(lines);

  final List<PdfLaidOutLine> lines;
  final PdfBox usedBounds;
  final bool overflow;
  final PdfTextStyle effectiveStyle;
}

final class PdfTextLayoutEngine {
  const PdfTextLayoutEngine();

  PdfTextLayoutResult layout({
    required String text,
    required PdfBox bounds,
    required PdfTextStyle style,
    required PdfTextMetrics metrics,
  }) {
    final List<String> wrapped = <String>[];
    for (final String paragraph in text.split('\n')) {
      wrapped.addAll(_wrapParagraph(paragraph, bounds.width, style, metrics));
    }
    if (wrapped.isEmpty) wrapped.add('');

    final double lineAdvance = metrics.lineHeight + style.lineSpacing;
    final List<PdfLaidOutLine> lines = <PdfLaidOutLine>[];
    for (int index = 0; index < wrapped.length; index++) {
      final String line = wrapped[index];
      final double width = metrics.measure(line, style);
      final double originX = switch (style.alignment) {
        PdfTextAlignment.center => bounds.left + (bounds.width - width) / 2,
        PdfTextAlignment.right => bounds.right - width,
        PdfTextAlignment.left || PdfTextAlignment.justify => bounds.left,
      };
      lines.add(
        PdfLaidOutLine(
          text: line,
          originX: originX,
          baseline: bounds.top - metrics.lineHeight - index * lineAdvance,
          width: width,
        ),
      );
    }
    final double height =
        metrics.lineHeight + math.max(0, lines.length - 1) * lineAdvance;
    final double minX = lines.fold<double>(
      double.infinity,
      (v, l) => math.min(v, l.originX),
    );
    final double maxX = lines.fold<double>(
      double.negativeInfinity,
      (v, l) => math.max(v, l.originX + l.width),
    );
    return PdfTextLayoutResult(
      lines: lines,
      usedBounds: PdfBox(minX, bounds.top - height, maxX, bounds.top),
      overflow: height > bounds.height,
      effectiveStyle: style,
    );
  }

  List<String> _wrapParagraph(
    String paragraph,
    double maxWidth,
    PdfTextStyle style,
    PdfTextMetrics metrics,
  ) {
    if (paragraph.isEmpty) return const <String>[''];
    final List<String> output = <String>[];
    String current = '';
    final Iterable<RegExpMatch> tokens = RegExp(
      r'\S+|\s+',
      unicode: true,
    ).allMatches(paragraph);
    for (final RegExpMatch match in tokens) {
      final String token = match.group(0)!;
      if (RegExp(r'^\s+$', unicode: true).hasMatch(token)) continue;
      final String candidate = current.isEmpty ? token : '$current $token';
      if (metrics.measure(candidate, style) <= maxWidth) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) {
        output.add(current);
        current = '';
      }
      if (metrics.measure(token, style) <= maxWidth) {
        current = token;
      } else {
        final List<String> chunks = _breakToken(
          token,
          maxWidth,
          style,
          metrics,
        );
        output.addAll(chunks.take(chunks.length - 1));
        current = chunks.last;
      }
    }
    if (current.isNotEmpty || output.isEmpty) output.add(current);
    return output;
  }

  List<String> _breakToken(
    String token,
    double maxWidth,
    PdfTextStyle style,
    PdfTextMetrics metrics,
  ) {
    final List<String> output = <String>[];
    String current = '';
    for (final int rune in token.runes) {
      final String character = String.fromCharCode(rune);
      final String candidate = '$current$character';
      if (current.isNotEmpty && metrics.measure(candidate, style) > maxWidth) {
        output.add(current);
        current = character;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) output.add(current);
    return output;
  }
}
