import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clarix/src/features/utilities/infrastructure/ooxml_visual_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

void main() {
  late Directory root;
  late List<VisualPdfPage> pages;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clarix-ooxml-test-');
    final List<int> png = await File('web/favicon.png').readAsBytes();
    final File firstImage = File(_path(root, 'page-1.png'));
    final File secondImage = File(_path(root, 'page-2.png'));
    await firstImage.writeAsBytes(png);
    await secondImage.writeAsBytes(png);
    pages = <VisualPdfPage>[
      VisualPdfPage(
        pageNumber: 1,
        widthPoints: 612,
        heightPoints: 792,
        pixelWidth: 1275,
        pixelHeight: 1650,
        imagePath: firstImage.path,
        extractedText: 'First & searchable',
      ),
      VisualPdfPage(
        pageNumber: 2,
        widthPoints: 792,
        heightPoints: 612,
        pixelWidth: 1650,
        pixelHeight: 1275,
        imagePath: secondImage.path,
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

  test(
    'PowerPoint package has resolvable OPC relationships and valid theme style lists',
    () async {
      final File output = File(_path(root, 'validated.pptx'));

      await const ArchiveOoxmlVisualExport().writePowerPoint(
        outputPath: output.path,
        pages: pages,
      );

      final Archive zip = ZipDecoder().decodeBytes(await output.readAsBytes());
      _validateOpenXmlPackage(zip);
      final XmlDocument theme = XmlDocument.parse(
        _text(zip, 'ppt/theme/theme1.xml'),
      );
      for (final String listName in <String>[
        'fillStyleLst',
        'lnStyleLst',
        'effectStyleLst',
        'bgFillStyleLst',
      ]) {
        final XmlElement list = theme.descendants
            .whereType<XmlElement>()
            .singleWhere(
              (XmlElement element) => element.name.local == listName,
            );
        expect(
          list.childElements,
          hasLength(greaterThanOrEqualTo(3)),
          reason: '$listName must satisfy the DrawingML schema minimum.',
        );
      }
    },
  );

  test(
    'OOXML text removes XML 1.0 forbidden controls before escaping',
    () async {
      final File output = File(_path(root, 'controls.docx'));
      final VisualPdfPage page = VisualPdfPage(
        pageNumber: 1,
        widthPoints: pages.first.widthPoints,
        heightPoints: pages.first.heightPoints,
        pixelWidth: pages.first.pixelWidth,
        pixelHeight: pages.first.pixelHeight,
        imagePath: pages.first.imagePath,
        extractedText: 'kept\tvalue\u0000\u0001\u000B<&',
      );

      await const ArchiveOoxmlVisualExport().writeWord(
        outputPath: output.path,
        pages: <VisualPdfPage>[page],
      );

      final Archive zip = ZipDecoder().decodeBytes(await output.readAsBytes());
      final String documentText = _text(zip, 'word/document.xml');
      final XmlDocument document = XmlDocument.parse(documentText);
      expect(document.innerText, contains('kept\tvalue<&'));
      expect(documentText, isNot(contains('\u0000')));
      expect(documentText, isNot(contains('\u0001')));
      expect(documentText, isNot(contains('\u000B')));
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

void _validateOpenXmlPackage(Archive archive) {
  final Set<String> parts = archive.files
      .map((ArchiveFile file) => path.posix.normalize(file.name))
      .toSet();
  for (final ArchiveFile file in archive.files.where(
    (ArchiveFile file) =>
        file.name.endsWith('.xml') || file.name.endsWith('.rels'),
  )) {
    final XmlDocument document = XmlDocument.parse(utf8.decode(file.content));
    if (!file.name.endsWith('.rels')) {
      continue;
    }
    final String relationshipBase = file.name == '_rels/.rels'
        ? ''
        : path.posix.dirname(path.posix.dirname(file.name));
    for (final XmlElement relationship in document.rootElement.childElements) {
      if (relationship.getAttribute('TargetMode') == 'External') {
        continue;
      }
      final String? target = relationship.getAttribute('Target');
      expect(target, isNotNull);
      final String resolved = path.posix.normalize(
        path.posix.join(relationshipBase, target!),
      );
      expect(
        parts,
        contains(resolved),
        reason: '${file.name} references missing part $resolved',
      );
    }
  }

  final XmlDocument contentTypes = XmlDocument.parse(
    _text(archive, '[Content_Types].xml'),
  );
  for (final XmlElement override
      in contentTypes.rootElement.childElements.where(
        (XmlElement element) => element.name.local == 'Override',
      )) {
    final String partName = override.getAttribute('PartName')!.substring(1);
    expect(
      parts,
      contains(partName),
      reason: 'Missing override part $partName',
    );
  }
}
