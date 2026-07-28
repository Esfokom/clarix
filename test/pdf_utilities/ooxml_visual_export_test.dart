import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clarix/src/features/utilities/infrastructure/ooxml_visual_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late List<VisualPdfPage> pages;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clarix-ooxml-test-');
    final List<int> png = await File('web/favicon.png').readAsBytes();
    pages = <VisualPdfPage>[
      VisualPdfPage(
        pageNumber: 1,
        widthPoints: 612,
        heightPoints: 792,
        pixelWidth: 1275,
        pixelHeight: 1650,
        pngBytes: png,
        extractedText: 'First & searchable',
      ),
      VisualPdfPage(
        pageNumber: 2,
        widthPoints: 792,
        heightPoints: 612,
        pixelWidth: 1650,
        pixelHeight: 1275,
        pngBytes: png,
        extractedText: '[No extractable text on this page.]',
      ),
    ];
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'Word visual export relates every rendered page and puts text below it',
    () async {
      final File output = File(_path(root, 'report.docx'));

      await const ArchiveOoxmlVisualExport().writeWord(
        outputPath: output.path,
        pages: pages,
      );

      final Archive zip = ZipDecoder().decodeBytes(await output.readAsBytes());
      expect(zip.findFile('word/media/page-1.png'), isNotNull);
      expect(zip.findFile('word/media/page-2.png'), isNotNull);
      final String relationships = _text(zip, 'word/_rels/document.xml.rels');
      expect(relationships, contains('Target="media/page-1.png"'));
      expect(relationships, contains('Target="media/page-2.png"'));
      final String document = _text(zip, 'word/document.xml');
      expect(document, contains('r:embed="rIdImage1"'));
      expect(document, contains('r:embed="rIdImage2"'));
      expect(document, contains('First &amp; searchable'));
      expect(document, contains('[No extractable text on this page.]'));
    },
  );

  test(
    'PowerPoint visual export creates one related slide image and hidden text box per page',
    () async {
      final File output = File(_path(root, 'report.pptx'));

      await const ArchiveOoxmlVisualExport().writePowerPoint(
        outputPath: output.path,
        pages: pages,
      );

      final Archive zip = ZipDecoder().decodeBytes(await output.readAsBytes());
      expect(zip.findFile('ppt/slides/slide1.xml'), isNotNull);
      expect(zip.findFile('ppt/slides/slide2.xml'), isNotNull);
      expect(zip.findFile('ppt/media/page-1.png'), isNotNull);
      expect(zip.findFile('ppt/media/page-2.png'), isNotNull);
      expect(
        _text(zip, 'ppt/_rels/presentation.xml.rels'),
        allOf(contains('slides/slide1.xml'), contains('slides/slide2.xml')),
      );
      expect(
        _text(zip, 'ppt/slides/_rels/slide2.xml.rels'),
        contains('../media/page-2.png'),
      );
      final String slide = _text(zip, 'ppt/slides/slide1.xml');
      expect(slide, contains('r:embed="rIdImage"'));
      expect(slide, contains('hidden="1"'));
      expect(slide, contains('First &amp; searchable'));
    },
  );
}

String _path(Directory directory, String name) =>
    '${directory.path}${Platform.pathSeparator}$name';

String _text(Archive archive, String name) {
  final ArchiveFile? file = archive.findFile(name);
  expect(file, isNotNull, reason: 'Expected OOXML part $name');
  return utf8.decode(file!.content);
}
