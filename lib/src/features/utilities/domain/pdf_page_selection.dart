/// An ordered, duplicate-free collection of 1-based PDF page numbers.
final class PdfPageSelection {
  const PdfPageSelection._(this.pages);

  /// The selected page numbers in the order they were written.
  final List<int> pages;

  /// Parses comma-separated page numbers and inclusive ranges such as `1-3, 7`.
  ///
  /// Every page number must be within `1..pageCount`. Later occurrences of a
  /// page are ignored while preserving the order of its first occurrence.
  factory PdfPageSelection.parse(String expression, {required int pageCount}) {
    if (pageCount < 1) {
      throw FormatException('Page count must be greater than zero.');
    }

    final Set<int> selected = <int>{};
    for (final String token in expression.split(',')) {
      final Match? match = RegExp(
        r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$',
      ).firstMatch(token);
      if (match == null) {
        throw FormatException('Invalid page selection: "$token".');
      }

      final int start = int.parse(match.group(1)!);
      final int end = int.parse(match.group(2) ?? match.group(1)!);
      if (start > end) {
        throw FormatException('Page ranges must be in ascending order.');
      }
      if (start < 1 || end > pageCount) {
        throw FormatException('Page selection is outside 1-$pageCount.');
      }

      for (int page = start; page <= end; page++) {
        selected.add(page);
      }
    }

    if (selected.isEmpty) {
      throw FormatException('Select at least one page.');
    }
    return PdfPageSelection._(List<int>.unmodifiable(selected));
  }
}
