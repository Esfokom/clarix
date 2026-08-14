import 'package:clarix/src/features/workspace/domain/pdf_text_layout.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports overflow without reducing font size', () {
    final result = const PdfTextLayoutEngine().layout(
      text: 'A long replacement that cannot fit',
      bounds: const PdfBox(0, 0, 60, 12),
      style: _style(fontSize: 12),
      metrics: const PdfMonospaceTextMetrics(advance: 6, lineHeight: 12),
    );

    expect(result.overflow, isTrue);
    expect(result.effectiveStyle.fontSize, 12);
    expect(result.lines.length, greaterThan(1));
  });

  test('preserves explicit newlines and breaks an overlong token', () {
    final result = const PdfTextLayoutEngine().layout(
      text: 'alpha\nsuperlong',
      bounds: const PdfBox(0, 0, 24, 60),
      style: _style(fontSize: 10),
      metrics: const PdfMonospaceTextMetrics(advance: 6, lineHeight: 10),
    );

    expect(result.lines.map((line) => line.text), [
      'alph',
      'a',
      'supe',
      'rlon',
      'g',
    ]);
    expect(result.overflow, isFalse);
  });

  test('applies alignment without changing the fixed boundary', () {
    final result = const PdfTextLayoutEngine().layout(
      text: 'one',
      bounds: const PdfBox(10, 20, 110, 40),
      style: _style(fontSize: 10, alignment: PdfTextAlignment.right),
      metrics: const PdfMonospaceTextMetrics(advance: 10, lineHeight: 10),
    );

    expect(result.lines.single.originX, 80);
    expect(result.usedBounds, const PdfBox(80, 30, 110, 40));
  });
}

PdfTextStyle _style({
  required double fontSize,
  PdfTextAlignment alignment = PdfTextAlignment.left,
}) => PdfTextStyle(
  fontFamily: 'Test Sans',
  fontSize: fontSize,
  fillColorValue: 0xff000000,
  fontWeight: 400,
  italic: false,
  underline: false,
  baselineShift: 0,
  alignment: alignment,
  characterSpacing: 0,
  lineSpacing: 0,
  horizontalScaling: 100,
);
