import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_native_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wraps at spaces and preserves explicit newlines', () {
    final layout = const PdfNativeTextLayoutEngine().layout(
      text: 'one two\nthree',
      runs: const <PdfTextRun>[
        PdfTextRun(range: PdfTextRange(0, 13), style: _style),
      ],
      bounds: const PdfBox(0, 0, 6, 40),
      baseline: 36,
      advance: (_, _) => 1,
      lineHeight: (_) => 10,
      direction: PdfWritingDirection.leftToRight,
    );

    expect(layout.lines.map((line) => line.text), <String>[
      'one ',
      'two',
      'three',
    ]);
  });

  test('uses alignment without changing font size', () {
    final layout = const PdfNativeTextLayoutEngine().layout(
      text: 'text',
      runs: const <PdfTextRun>[
        PdfTextRun(
          range: PdfTextRange(0, 4),
          style: PdfTextStyle(
            fontFamily: 'Helvetica',
            fontSize: 12,
            fillColorValue: 0xff000000,
            fontWeight: 400,
            italic: false,
            underline: false,
            baselineShift: 0,
            alignment: PdfTextAlignment.right,
            characterSpacing: 0,
            lineSpacing: 0,
            horizontalScaling: 1,
          ),
        ),
      ],
      bounds: const PdfBox(10, 0, 30, 20),
      baseline: 12,
      advance: (_, style) => style.fontSize / 12,
      lineHeight: (style) => style.fontSize,
      direction: PdfWritingDirection.leftToRight,
    );

    expect(layout.lines.single.originX, 26);
  });

  test('rejects unsupported writing directions', () {
    expect(
      () => const PdfNativeTextLayoutEngine().layout(
        text: 'text',
        runs: const <PdfTextRun>[
          PdfTextRun(range: PdfTextRange(0, 4), style: _style),
        ],
        bounds: const PdfBox(0, 0, 20, 20),
        baseline: 12,
        advance: (_, _) => 1,
        lineHeight: (_) => 10,
        direction: PdfWritingDirection.vertical,
      ),
      throwsUnsupportedError,
    );
  });
}

const _style = PdfTextStyle(
  fontFamily: 'Helvetica',
  fontSize: 12,
  fillColorValue: 0xff000000,
  fontWeight: 400,
  italic: false,
  underline: false,
  baselineShift: 0,
  alignment: PdfTextAlignment.left,
  characterSpacing: 0,
  lineSpacing: 0,
  horizontalScaling: 1,
);
