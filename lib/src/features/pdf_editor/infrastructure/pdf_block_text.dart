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
