import 'package:clarix/src/features/pdf_editor/infrastructure/pdf_block_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('separatorBetween', () {
    test('yields no separator when adjacent text carries whitespace', () {
      expect(
        separatorBetween(
          (text: 'Hello ', fontSize: 12, baseline: 700),
          (text: 'world', fontSize: 12, baseline: 700),
        ),
        '',
      );
      expect(
        separatorBetween(
          (text: 'Hello', fontSize: 12, baseline: 700),
          (text: ' world', fontSize: 12, baseline: 700),
        ),
        '',
      );
    });

    test('yields a space for same-baseline neighbors', () {
      expect(
        separatorBetween(
          (text: 'Hello', fontSize: 12, baseline: 700),
          (text: 'world', fontSize: 12, baseline: 700),
        ),
        ' ',
      );
    });

    test('yields a newline when baselines differ beyond tolerance', () {
      expect(
        separatorBetween(
          (text: 'Hello', fontSize: 12, baseline: 700),
          (text: 'world', fontSize: 12, baseline: 690),
        ),
        '\n',
      );
    });

    test('tolerance is a quarter of the combined font sizes', () {
      // (12 + 12) * 0.25 = 6 — a 6pt gap is still one line, 7pt is a break.
      expect(
        separatorBetween(
          (text: 'a', fontSize: 12, baseline: 700),
          (text: 'b', fontSize: 12, baseline: 694),
        ),
        ' ',
      );
      expect(
        separatorBetween(
          (text: 'a', fontSize: 12, baseline: 700),
          (text: 'b', fontSize: 12, baseline: 693),
        ),
        '\n',
      );
    });
  });

  group('joinObjectTexts', () {
    test('same-line pair joins with a single space', () {
      expect(
        joinObjectTexts(<PdfObjectTextSample>[
          (text: 'Hello', fontSize: 12, baseline: 700),
          (text: 'world', fontSize: 12, baseline: 700),
        ]),
        'Hello world',
      );
    });

    test('multiline pair joins with a newline', () {
      expect(
        joinObjectTexts(<PdfObjectTextSample>[
          (text: 'first', fontSize: 12, baseline: 700),
          (text: 'second', fontSize: 12, baseline: 688),
        ]),
        'first\nsecond',
      );
    });

    test('whitespace-adjacent pair joins without a separator', () {
      expect(
        joinObjectTexts(<PdfObjectTextSample>[
          (text: 'Hello ', fontSize: 12, baseline: 700),
          (text: 'world', fontSize: 12, baseline: 700),
        ]),
        'Hello world',
      );
    });

    test('mixed grouping reproduces the inspection join', () {
      expect(
        joinObjectTexts(<PdfObjectTextSample>[
          (text: 'One', fontSize: 12, baseline: 700),
          (text: 'two', fontSize: 12, baseline: 700),
          (text: 'three', fontSize: 12, baseline: 688),
          (text: 'four ', fontSize: 12, baseline: 688),
          (text: 'five', fontSize: 12, baseline: 688),
        ]),
        'One two\nthree four five',
      );
    });

    test('single sample passes through unchanged', () {
      expect(
        joinObjectTexts(<PdfObjectTextSample>[
          (text: 'solo', fontSize: 10, baseline: 500),
        ]),
        'solo',
      );
    });

    test('empty input yields an empty string', () {
      expect(joinObjectTexts(<PdfObjectTextSample>[]), '');
    });
  });

  group('distributeReplacement', () {
    test('single segment passes through unchanged', () {
      expect(
        distributeReplacement(
          replacement: 'anything',
          originalSegments: <String>['old'],
          separators: <String>[],
        ),
        <String>['anything'],
      );
    });

    test('intra-segment edit keeps separators in place', () {
      expect(
        distributeReplacement(
          replacement: 'Hellx world',
          originalSegments: <String>['Hello', 'world'],
          separators: <String>[' '],
        ),
        <String>['Hellx', 'world'],
      );
    });

    test('deleted separator collapses via prefix fill', () {
      expect(
        distributeReplacement(
          replacement: 'onetwo',
          originalSegments: <String>['one', 'two'],
          separators: <String>['\n'],
        ),
        <String>['onetwo', ' '],
      );
    });

    test('every empty segment becomes a space anchor', () {
      expect(
        distributeReplacement(
          replacement: 'b',
          originalSegments: <String>['a', 'b', 'c'],
          separators: <String>[' ', ' '],
        ),
        <String>['b', ' ', ' '],
      );
    });

    test('full delete leaves a space anchor in every object', () {
      expect(
        distributeReplacement(
          replacement: '',
          originalSegments: <String>['a', 'b', 'c'],
          separators: <String>[' ', ' '],
        ),
        <String>[' ', ' ', ' '],
      );
    });

    test('typed newline re-splits at the existing separator', () {
      expect(
        distributeReplacement(
          replacement: 'one\ntwo and more',
          originalSegments: <String>['one', 'two'],
          separators: <String>['\n'],
        ),
        <String>['one', 'two and more'],
      );
    });

    test('replacement re-joins to the same trimmed text', () {
      final segments = distributeReplacement(
        replacement: 'Bye world',
        originalSegments: <String>['Hello', 'world'],
        separators: <String>[' '],
      );
      expect(segments, <String>['Bye', 'world']);
      expect(
        joinObjectTexts(<PdfObjectTextSample>[
          for (final segment in segments)
            (text: segment, fontSize: 12, baseline: 700),
        ]).trimRight(),
        'Bye world',
      );
    });
  });
}
