import 'package:clarix/src/features/utilities/domain/pdf_page_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps written range order and removes later duplicates', () {
    expect(PdfPageSelection.parse('3-4, 1, 3', pageCount: 4).pages, <int>[
      3,
      4,
      1,
    ]);
  });

  test('rejects an out-of-bounds page', () {
    expect(
      () => PdfPageSelection.parse('1, 8', pageCount: 7),
      throwsFormatException,
    );
  });
}
