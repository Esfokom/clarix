import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

File phase1CorpusFile(String relativePath) {
  final file = File(relativePath).absolute;
  if (!file.existsSync()) {
    throw StateError('Phase 1 corpus file is missing: ${file.path}');
  }
  return file;
}

Future<File> writeBlankPdfCorpus(Directory directory, int pageCount) async {
  if (pageCount < 1) {
    throw ArgumentError.value(pageCount, 'pageCount', 'must be positive');
  }
  final pageStart = 3;
  final contentId = pageStart + pageCount;
  final objectCount = contentId;
  final bytes = BytesBuilder(copy: false);
  final offsets = List<int>.filled(objectCount + 1, 0);

  void append(String value) => bytes.add(latin1.encode(value));
  void object(int id, String body) {
    offsets[id] = bytes.length;
    append('$id 0 obj\n$body\nendobj\n');
  }

  append('%PDF-1.7\n%âãÏÓ\n');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  final kids = List<String>.generate(
    pageCount,
    (index) => '${pageStart + index} 0 R',
  ).join(' ');
  object(2, '<< /Type /Pages /Count $pageCount /Kids [$kids] >>');
  for (var index = 0; index < pageCount; index++) {
    object(
      pageStart + index,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources <<>> /Contents $contentId 0 R >>',
    );
  }
  object(contentId, '<< /Length 0 >>\nstream\n\nendstream');
  final xrefOffset = bytes.length;
  append('xref\n0 ${objectCount + 1}\n');
  append('0000000000 65535 f \n');
  for (var id = 1; id <= objectCount; id++) {
    append('${offsets[id].toString().padLeft(10, '0')} 00000 n \n');
  }
  append(
    'trailer\n<< /Size ${objectCount + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );

  final output = File('${directory.path}${Platform.pathSeparator}large.pdf');
  await output.writeAsBytes(bytes.takeBytes(), flush: true);
  return output;
}

int percentile95(List<int> samples) {
  if (samples.isEmpty) return 0;
  samples.sort();
  return samples[((samples.length - 1) * 0.95).round()];
}
