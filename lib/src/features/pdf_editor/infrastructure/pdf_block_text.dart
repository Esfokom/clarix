/// Shared pure helpers for joining per-object text reads into the block-level
/// text used by both the import pipeline and the live PDFium apply worker.
///
/// The import side builds block text from inspection snapshots; the apply
/// worker must reconstruct the same joined text from its own per-object reads
/// to verify `expectedText` before mutating. These functions are the single
/// source of truth for that join so the two can never drift.
library;

typedef PdfObjectTextSample = ({String text, double fontSize, double baseline});

/// The separator the inspection pipeline inserts between two adjacent text
/// objects of the same block.
String separatorBetween(
  PdfObjectTextSample previous,
  PdfObjectTextSample current,
) {
  if (RegExp(r'\s$').hasMatch(previous.text) ||
      RegExp(r'^\s').hasMatch(current.text)) {
    return '';
  }
  final tolerance = (previous.fontSize + current.fontSize) * 0.25;
  return (previous.baseline - current.baseline).abs() <= tolerance ? ' ' : '\n';
}

/// Joins per-object text samples with [separatorBetween], reproducing the
/// block text produced by the inspection pipeline.
String joinObjectTexts(List<PdfObjectTextSample> objects) {
  final buffer = StringBuffer();
  for (var index = 0; index < objects.length; index++) {
    if (index > 0) {
      buffer.write(separatorBetween(objects[index - 1], objects[index]));
    }
    buffer.write(objects[index].text);
  }
  return buffer.toString();
}

/// Distributes a block-level [replacement] across the block's physical text
/// objects so that re-joining the segments reproduces the replacement.
///
/// Splits greedily at the first occurrence of each recorded separator (the
/// separators between adjacent [originalSegments], as produced by
/// [separatorBetween]). If a separator is missing from the replacement the
/// remainder goes entirely to the current segment (prefix fill). PDFium
/// discards a truly empty text object during content generation — which would
/// shift page-object indices and desync the locator registry — so every empty
/// segment is pinned to a single space.
List<String> distributeReplacement({
  required String replacement,
  required List<String> originalSegments,
  required List<String> separators,
}) {
  if (originalSegments.length == 1) return <String>[replacement];
  final segments = <String>[];
  var cursor = 0;
  var exhausted = false;
  for (var index = 0; index < originalSegments.length; index++) {
    if (exhausted) {
      segments.add(' ');
      continue;
    }
    if (index == originalSegments.length - 1) {
      segments.add(replacement.substring(cursor));
      exhausted = true;
      continue;
    }
    final separator = index < separators.length ? separators[index] : '';
    if (separator.isEmpty) {
      segments.add(replacement.substring(cursor));
      exhausted = true;
      continue;
    }
    final match = replacement.indexOf(separator, cursor);
    if (match < 0) {
      segments.add(replacement.substring(cursor));
      exhausted = true;
      continue;
    }
    segments.add(replacement.substring(cursor, match));
    cursor = match + separator.length;
  }
  for (var index = 0; index < segments.length; index++) {
    if (segments[index].isEmpty) segments[index] = ' ';
  }
  return segments;
}
