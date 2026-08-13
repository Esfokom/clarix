import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_text_block_grouper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups adjacent same-direction lines deterministically', () {
    final first = _object(path: [2], text: 'Quarterly', baseline: 700);
    final second = _object(path: [3], text: 'Revenue', baseline: 684);

    final forward = const PdfTextBlockGrouper().group([second, first]);
    final reverse = const PdfTextBlockGrouper().group([first, second]);

    expect(forward.single.objectPaths, [
      [2],
      [3],
    ]);
    expect(reverse, forward);
    expect(forward.single.text, 'Quarterly\nRevenue');
  });

  test('does not group different writing directions or distant objects', () {
    final groups = const PdfTextBlockGrouper().group([
      _object(path: [1], text: 'Left', baseline: 700),
      _object(
        path: [2],
        text: 'Right',
        baseline: 684,
        direction: PdfWritingDirection.rightToLeft,
      ),
      _object(path: [3], text: 'Far away', baseline: 400),
    ]);

    expect(groups, hasLength(3));
  });
}

PdfTextObjectSnapshot _object({
  required List<int> path,
  required String text,
  required double baseline,
  PdfWritingDirection direction = PdfWritingDirection.leftToRight,
}) => PdfTextObjectSnapshot(
  objectPath: path,
  text: text,
  bounds: PdfBox(50, baseline - 12, 150, baseline),
  transform: const PdfTransform(1, 0, 0, 1, 0, 0),
  style: const PdfTextStyle(
    fontFamily: 'Test Sans',
    fontSize: 12,
    fillColorValue: 0xff000000,
    fontWeight: 400,
    italic: false,
    underline: false,
    baselineShift: 0,
    alignment: PdfTextAlignment.left,
    characterSpacing: 0,
    lineSpacing: 0,
    horizontalScaling: 100,
  ),
  baseline: baseline,
  writingDirection: direction,
);
