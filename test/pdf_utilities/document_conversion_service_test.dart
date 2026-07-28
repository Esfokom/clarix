import 'dart:convert';
import 'dart:io';

import 'package:clarix/src/features/utilities/domain/utility_job.dart';
import 'package:clarix/src/features/utilities/infrastructure/document_conversion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clarix-conversion-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('routes every supported source family to its local converter', () async {
    final _RecordingDirectPdfConverter direct = _RecordingDirectPdfConverter();
    final _RecordingOfficePdfConverter office = _RecordingOfficePdfConverter();
    final DocumentConversionService service = DocumentConversionService(
      direct: direct,
      office: office,
    );

    final List<UtilityResult> results = await service.convert(<String>[
      'C:/sources/photo.PNG',
      'C:/sources/notes.txt',
      'C:/sources/readme.markdown',
      'C:/sources/report.docx',
      'C:/sources/slides.pptx',
      'C:/sources/data.xlsx',
    ], root.path);

    expect(direct.imageCalls, <_ConversionCall>[
      _ConversionCall(<String>[
        'C:/sources/photo.PNG',
      ], _outputPath(root, 'photo.pdf')),
    ]);
    expect(direct.textCalls, <_ConversionCall>[
      _ConversionCall(<String>[
        'C:/sources/notes.txt',
      ], _outputPath(root, 'notes.pdf')),
    ]);
    expect(direct.markdownCalls, <_ConversionCall>[
      _ConversionCall(<String>[
        'C:/sources/readme.markdown',
      ], _outputPath(root, 'readme.pdf')),
    ]);
    expect(office.calls, <_ConversionCall>[
      _ConversionCall(<String>[
        'C:/sources/report.docx',
      ], _outputPath(root, 'report.pdf')),
      _ConversionCall(<String>[
        'C:/sources/slides.pptx',
      ], _outputPath(root, 'slides.pdf')),
      _ConversionCall(<String>[
        'C:/sources/data.xlsx',
      ], _outputPath(root, 'data.pdf')),
    ]);
    expect(results.map((UtilityResult result) => result.outputPath), <String>[
      _outputPath(root, 'photo.pdf'),
      _outputPath(root, 'notes.pdf'),
      _outputPath(root, 'readme.pdf'),
      _outputPath(root, 'report.pdf'),
      _outputPath(root, 'slides.pdf'),
      _outputPath(root, 'data.pdf'),
    ]);
  });

  test('rejects unsupported sources before starting any conversion', () async {
    final _RecordingDirectPdfConverter direct = _RecordingDirectPdfConverter();
    final _RecordingOfficePdfConverter office = _RecordingOfficePdfConverter();
    final DocumentConversionService service = DocumentConversionService(
      direct: direct,
      office: office,
    );

    await expectLater(
      service.convert(<String>['C:/sources/archive.zip'], root.path),
      throwsA(
        isA<UtilityFailure>().having(
          (UtilityFailure failure) => failure.message,
          'message',
          contains('Unsupported source type'),
        ),
      ),
    );
    expect(direct.calls, isEmpty);
    expect(office.calls, isEmpty);
  });

  test('rejects source names that would overwrite the same output', () async {
    final _RecordingDirectPdfConverter direct = _RecordingDirectPdfConverter();
    final DocumentConversionService service = DocumentConversionService(
      direct: direct,
      office: _RecordingOfficePdfConverter(),
    );

    await expectLater(
      service.convert(<String>[
        'C:/one/notes.txt',
        'C:/two/notes.md',
      ], root.path),
      throwsA(
        isA<UtilityFailure>().having(
          (UtilityFailure failure) => failure.message,
          'message',
          contains('same output name'),
        ),
      ),
    );
    expect(direct.calls, isEmpty);
  });

  test('direct text conversion paginates UTF-8 input on A4 pages', () async {
    final File source = File(_outputPath(root, 'journal.txt'));
    await source.writeAsString(
      List<String>.generate(
        260,
        (int index) => 'Line ${index + 1}: café notes',
      ).join('\n'),
      encoding: utf8,
    );
    final String output = _outputPath(root, 'journal.pdf');

    final int pageCount = await const DartDirectPdfConverter().textToPdf(
      source.path,
      output,
    );

    final PdfDocument document = await PdfDocument.openFile(output);
    try {
      expect(pageCount, document.pages.length);
      expect(document.pages.length, greaterThan(1));
      final String extracted =
          (await document.pages.first.loadText())!.fullText;
      expect(extracted, contains('Line 1: café notes'));
    } finally {
      await document.dispose();
    }
  });

  test('direct markdown conversion renders parsed block content', () async {
    final File source = File(_outputPath(root, 'guide.md'));
    await source.writeAsString('''
# Local guide

- Keep files private
- Work offline

```dart
print('ready');
```

[Clarix help](https://example.test/help)
''');
    final String output = _outputPath(root, 'guide.pdf');

    final int pageCount = await const DartDirectPdfConverter().markdownToPdf(
      source.path,
      output,
    );

    final PdfDocument document = await PdfDocument.openFile(output);
    try {
      expect(pageCount, 1);
      final String extracted =
          (await document.pages.single.loadText())!.fullText;
      expect(extracted, contains('Local guide'));
      expect(extracted, contains('Keep files private'));
      expect(extracted, contains("print('ready');"));
      expect(extracted, contains('Clarix help'));
      expect(extracted, contains('https://example.test/help'));
    } finally {
      await document.dispose();
    }
  });

  test('direct image conversion creates one A4 page per image', () async {
    final File first = File(_outputPath(root, 'first.png'));
    final File second = File(_outputPath(root, 'second.png'));
    final List<int> pixel = await File('web/favicon.png').readAsBytes();
    await first.writeAsBytes(pixel);
    await second.writeAsBytes(pixel);
    final String output = _outputPath(root, 'images.pdf');

    final int pageCount = await const DartDirectPdfConverter().imagesToPdf(
      <String>[first.path, second.path],
      output,
    );

    final PdfDocument document = await PdfDocument.openFile(output);
    try {
      expect(pageCount, 2);
      expect(document.pages, hasLength(2));
      for (final page in document.pages) {
        expect(page.width, closeTo(595.28, 0.1));
        expect(page.height, closeTo(841.89, 0.1));
      }
    } finally {
      await document.dispose();
    }
  });
}

String _outputPath(Directory directory, String name) =>
    '${directory.path}${Platform.pathSeparator}$name';

final class _RecordingDirectPdfConverter implements DirectPdfConverter {
  final List<_ConversionCall> imageCalls = <_ConversionCall>[];
  final List<_ConversionCall> textCalls = <_ConversionCall>[];
  final List<_ConversionCall> markdownCalls = <_ConversionCall>[];

  List<_ConversionCall> get calls => <_ConversionCall>[
    ...imageCalls,
    ...textCalls,
    ...markdownCalls,
  ];

  @override
  Future<int> imagesToPdf(List<String> sourcePaths, String outputPath) async {
    imageCalls.add(_ConversionCall(sourcePaths, outputPath));
    return sourcePaths.length;
  }

  @override
  Future<int> markdownToPdf(String sourcePath, String outputPath) async {
    markdownCalls.add(_ConversionCall(<String>[sourcePath], outputPath));
    return 1;
  }

  @override
  Future<int> textToPdf(String sourcePath, String outputPath) async {
    textCalls.add(_ConversionCall(<String>[sourcePath], outputPath));
    return 1;
  }
}

final class _RecordingOfficePdfConverter implements OfficePdfConverter {
  final List<_ConversionCall> calls = <_ConversionCall>[];

  @override
  Future<void> convert(String inputPath, String outputPath) async {
    calls.add(_ConversionCall(<String>[inputPath], outputPath));
  }
}

final class _ConversionCall {
  const _ConversionCall(this.sources, this.outputPath);

  final List<String> sources;
  final String outputPath;

  @override
  bool operator ==(Object other) =>
      other is _ConversionCall &&
      _listEquals(other.sources, sources) &&
      other.outputPath == outputPath;

  @override
  int get hashCode => Object.hash(Object.hashAll(sources), outputPath);
}

bool _listEquals(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
