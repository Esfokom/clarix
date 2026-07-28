import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';

/// A rendered PDF page and the text that accompanies it in a visual export.
final class VisualPdfPage {
  const VisualPdfPage({
    required this.pageNumber,
    required this.widthPoints,
    required this.heightPoints,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.pngBytes,
    required this.extractedText,
  }) : assert(pageNumber > 0),
       assert(widthPoints > 0),
       assert(heightPoints > 0),
       assert(pixelWidth > 0),
       assert(pixelHeight > 0);

  final int pageNumber;
  final double widthPoints;
  final double heightPoints;
  final int pixelWidth;
  final int pixelHeight;
  final List<int> pngBytes;
  final String extractedText;
}

abstract interface class OoxmlVisualExport {
  Future<void> writeWord({
    required String outputPath,
    required List<VisualPdfPage> pages,
  });

  Future<void> writePowerPoint({
    required String outputPath,
    required List<VisualPdfPage> pages,
  });
}

/// Writes minimal, self-contained OOXML packages using page images for fidelity.
final class ArchiveOoxmlVisualExport implements OoxmlVisualExport {
  const ArchiveOoxmlVisualExport();

  static const int _emuPerInch = 914400;
  static const int _wordImageMaxWidth = 6 * _emuPerInch + _emuPerInch ~/ 2;
  static const int _wordImageMaxHeight = 7 * _emuPerInch;
  static const int _slideWidth = 10 * _emuPerInch;
  static const int _slideHeight = 7 * _emuPerInch + _emuPerInch ~/ 2;

  @override
  Future<void> writeWord({
    required String outputPath,
    required List<VisualPdfPage> pages,
  }) async {
    _requirePages(pages);
    final Archive archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _wordContentTypes))
      ..add(ArchiveFile.string('_rels/.rels', _wordRootRelationships))
      ..add(ArchiveFile.string('docProps/core.xml', _coreProperties))
      ..add(ArchiveFile.string('docProps/app.xml', _wordAppProperties))
      ..add(ArchiveFile.string('word/document.xml', _wordDocument(pages)))
      ..add(
        ArchiveFile.string(
          'word/_rels/document.xml.rels',
          _wordDocumentRelationships(pages),
        ),
      );
    for (final VisualPdfPage page in pages) {
      archive.add(
        ArchiveFile.bytes(
          'word/media/page-${page.pageNumber}.png',
          page.pngBytes,
        ),
      );
    }
    await _writeArchive(outputPath, archive);
  }

  @override
  Future<void> writePowerPoint({
    required String outputPath,
    required List<VisualPdfPage> pages,
  }) async {
    _requirePages(pages);
    final Archive archive = Archive()
      ..add(
        ArchiveFile.string(
          '[Content_Types].xml',
          _powerPointContentTypes(pages.length),
        ),
      )
      ..add(ArchiveFile.string('_rels/.rels', _powerPointRootRelationships))
      ..add(ArchiveFile.string('docProps/core.xml', _coreProperties))
      ..add(ArchiveFile.string('docProps/app.xml', _powerPointAppProperties))
      ..add(
        ArchiveFile.string(
          'ppt/presentation.xml',
          _powerPointPresentation(pages.length),
        ),
      )
      ..add(
        ArchiveFile.string(
          'ppt/_rels/presentation.xml.rels',
          _powerPointPresentationRelationships(pages.length),
        ),
      )
      ..add(
        ArchiveFile.string('ppt/slideMasters/slideMaster1.xml', _slideMaster),
      )
      ..add(
        ArchiveFile.string(
          'ppt/slideMasters/_rels/slideMaster1.xml.rels',
          _slideMasterRelationships,
        ),
      )
      ..add(
        ArchiveFile.string('ppt/slideLayouts/slideLayout1.xml', _slideLayout),
      )
      ..add(
        ArchiveFile.string(
          'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
          _slideLayoutRelationships,
        ),
      )
      ..add(ArchiveFile.string('ppt/theme/theme1.xml', _theme));
    for (final VisualPdfPage page in pages) {
      archive
        ..add(
          ArchiveFile.string(
            'ppt/slides/slide${page.pageNumber}.xml',
            _slide(page),
          ),
        )
        ..add(
          ArchiveFile.string(
            'ppt/slides/_rels/slide${page.pageNumber}.xml.rels',
            _slideRelationships(page),
          ),
        )
        ..add(
          ArchiveFile.bytes(
            'ppt/media/page-${page.pageNumber}.png',
            page.pngBytes,
          ),
        );
    }
    await _writeArchive(outputPath, archive);
  }

  Future<void> _writeArchive(String outputPath, Archive archive) async {
    final List<int> bytes = ZipEncoder().encodeBytes(
      archive,
      modified: DateTime.utc(2026),
    );
    await File(outputPath).writeAsBytes(bytes, flush: true);
  }

  void _requirePages(List<VisualPdfPage> pages) {
    if (pages.isEmpty) {
      throw ArgumentError.value(
        pages,
        'pages',
        'At least one page is required.',
      );
    }
  }

  String _wordDocument(List<VisualPdfPage> pages) {
    final StringBuffer body = StringBuffer();
    for (int index = 0; index < pages.length; index++) {
      final VisualPdfPage page = pages[index];
      final ({int width, int height}) extent = _containedExtent(
        sourceWidth: page.pixelWidth,
        sourceHeight: page.pixelHeight,
        maxWidth: _wordImageMaxWidth,
        maxHeight: _wordImageMaxHeight,
      );
      body
        ..write(
          '<w:p><w:pPr><w:keepNext/></w:pPr><w:r><w:drawing>'
          '<wp:inline distT="0" distB="0" distL="0" distR="0">'
          '<wp:extent cx="${extent.width}" cy="${extent.height}"/>'
          '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
          '<wp:docPr id="${page.pageNumber}" name="PDF page ${page.pageNumber}" '
          'descr="Rendered visual of PDF page ${page.pageNumber}"/>'
          '<wp:cNvGraphicFramePr>'
          '<a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>'
          '</wp:cNvGraphicFramePr>'
          '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
          '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
          '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
          '<pic:nvPicPr><pic:cNvPr id="0" name="page-${page.pageNumber}.png" '
          'descr="PDF page ${page.pageNumber}"/>'
          '<pic:cNvPicPr><a:picLocks noChangeAspect="1"/></pic:cNvPicPr></pic:nvPicPr>'
          '<pic:blipFill><a:blip r:embed="rIdImage${page.pageNumber}"/>'
          '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
          '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
          '<a:ext cx="${extent.width}" cy="${extent.height}"/></a:xfrm>'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
          '</pic:pic></a:graphicData></a:graphic>'
          '</wp:inline></w:drawing></w:r></w:p>',
        )
        ..write(
          '<w:p><w:pPr><w:spacing before="120" after="120"/></w:pPr>'
          '${_wordTextRuns(page.extractedText)}</w:p>',
        );
      if (index != pages.length - 1) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }
    return _xml(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
      '<w:body>$body'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" '
      'w:header="360" w:footer="360" w:gutter="0"/></w:sectPr>'
      '</w:body></w:document>',
    );
  }

  String _wordDocumentRelationships(List<VisualPdfPage> pages) => _xml(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${pages.map((VisualPdfPage page) => '<Relationship Id="rIdImage${page.pageNumber}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/page-${page.pageNumber}.png"/>').join()}'
    '</Relationships>',
  );

  String _wordTextRuns(String text) {
    final List<String> lines = text.split('\n');
    final StringBuffer runs = StringBuffer();
    for (int index = 0; index < lines.length; index++) {
      if (index > 0) {
        runs.write('<w:r><w:br/></w:r>');
      }
      runs.write(
        '<w:r><w:rPr><w:sz w:val="18"/></w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(lines[index])}</w:t></w:r>',
      );
    }
    return runs.toString();
  }

  String _slide(VisualPdfPage page) {
    final ({int width, int height}) extent = _containedExtent(
      sourceWidth: page.pixelWidth,
      sourceHeight: page.pixelHeight,
      maxWidth: _slideWidth,
      maxHeight: _slideHeight,
    );
    final int x = (_slideWidth - extent.width) ~/ 2;
    final int y = (_slideHeight - extent.height) ~/ 2;
    return _xml(
      '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>'
      '<a:effectLst/></p:bgPr></p:bg><p:spTree>'
      '$_groupShapeProperties'
      '<p:pic><p:nvPicPr><p:cNvPr id="2" name="PDF page ${page.pageNumber}" '
      'descr="Rendered visual of PDF page ${page.pageNumber}"/>'
      '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
      '<p:blipFill><a:blip r:embed="rIdImage"/>'
      '<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
      '<p:spPr><a:xfrm><a:off x="$x" y="$y"/>'
      '<a:ext cx="${extent.width}" cy="${extent.height}"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Accessible page text" hidden="1" '
      'descr="Extracted text for PDF page ${page.pageNumber}"/>'
      '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="0" y="${_slideHeight - 1}"/>'
      '<a:ext cx="1" cy="1"/></a:xfrm><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>'
      '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r>'
      '<a:rPr lang="en-US" sz="100"/><a:t>${_escapeXml(page.extractedText)}</a:t>'
      '</a:r><a:endParaRPr lang="en-US" sz="100"/></a:p></p:txBody></p:sp>'
      '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sld>',
    );
  }

  String _slideRelationships(VisualPdfPage page) => _xml(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdLayout" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" '
    'Target="../slideLayouts/slideLayout1.xml"/>'
    '<Relationship Id="rIdImage" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
    'Target="../media/page-${page.pageNumber}.png"/>'
    '</Relationships>',
  );

  String _powerPointContentTypes(int pageCount) => _xml(
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
    '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
    '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
    '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
    '${List<String>.generate(pageCount, (int index) => '<Override PartName="/ppt/slides/slide${index + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>').join()}'
    '</Types>',
  );

  String _powerPointPresentation(int pageCount) => _xml(
    '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
    '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rIdMaster"/></p:sldMasterIdLst>'
    '<p:sldIdLst>${List<String>.generate(pageCount, (int index) => '<p:sldId id="${256 + index}" '
        'r:id="rIdSlide${index + 1}"/>').join()}</p:sldIdLst>'
    '<p:sldSz cx="$_slideWidth" cy="$_slideHeight" type="screen4x3"/>'
    '<p:notesSz cx="6858000" cy="9144000"/>'
    '<p:defaultTextStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr></p:defaultTextStyle>'
    '</p:presentation>',
  );

  String _powerPointPresentationRelationships(int pageCount) => _xml(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdMaster" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" '
    'Target="slideMasters/slideMaster1.xml"/>'
    '${List<String>.generate(pageCount, (int index) => '<Relationship Id="rIdSlide${index + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
        'Target="slides/slide${index + 1}.xml"/>').join()}'
    '</Relationships>',
  );

  ({int width, int height}) _containedExtent({
    required int sourceWidth,
    required int sourceHeight,
    required int maxWidth,
    required int maxHeight,
  }) {
    final double scale = math.min(
      maxWidth / sourceWidth,
      maxHeight / sourceHeight,
    );
    return (
      width: (sourceWidth * scale).round(),
      height: (sourceHeight * scale).round(),
    );
  }
}

String _xml(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>$body';

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

const String _wordContentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    '</Types>';

const String _wordRootRelationships =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const String _powerPointRootRelationships =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const String _coreProperties =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:dcterms="http://purl.org/dc/terms/" '
    'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    '<dc:title>Clarix visual PDF export</dc:title>'
    '<dc:creator>Clarix</dc:creator>'
    '<cp:lastModifiedBy>Clarix</cp:lastModifiedBy>'
    '</cp:coreProperties>';

const String _wordAppProperties =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
    'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
    '<Application>Clarix</Application><AppVersion>1.0</AppVersion>'
    '</Properties>';

const String _powerPointAppProperties =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
    'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
    '<Application>Clarix</Application><PresentationFormat>On-screen Show (4:3)</PresentationFormat>'
    '<AppVersion>1.0</AppVersion></Properties>';

const String _groupShapeProperties =
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';

const String _slideMaster =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
    '<p:cSld name="Clarix visual export"><p:spTree>$_groupShapeProperties</p:spTree></p:cSld>'
    '<p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" '
    'accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" '
    'hlink="hlink" tx1="dk1" tx2="dk2"/>'
    '<p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rIdLayout"/></p:sldLayoutIdLst>'
    '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>'
    '</p:sldMaster>';

const String _slideMasterRelationships =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdLayout" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
    '<Relationship Id="rIdTheme" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
    '</Relationships>';

const String _slideLayout =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>'
    '$_groupShapeProperties</p:spTree></p:cSld>'
    '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';

const String _slideLayoutRelationships =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdMaster" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
    '</Relationships>';

const String _theme =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Clarix">'
    '<a:themeElements><a:clrScheme name="Clarix">'
    '<a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="222222"/></a:dk2><a:lt2><a:srgbClr val="F2F2F2"/></a:lt2>'
    '<a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
    '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
    '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
    '<a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
    '</a:clrScheme><a:fontScheme name="Clarix">'
    '<a:majorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
    '</a:fontScheme><a:fmtScheme name="Clarix">'
    '<a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
    '<a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:prstDash val="solid"/></a:ln></a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>'
    '</a:fmtScheme></a:themeElements></a:theme>';
