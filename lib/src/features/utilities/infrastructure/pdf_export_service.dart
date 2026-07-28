import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../core/pdf_oxide_bridge.dart';
import '../domain/utility_job.dart';
import 'ooxml_visual_export.dart';

const String noExtractablePdfText = '[No extractable text on this page.]';

abstract interface class PdfDocumentTextExtractor {
  Future<List<String>> extractDocumentText(String sourcePath);
}

final class HybridPdfDocumentTextExtractor implements PdfDocumentTextExtractor {
  HybridPdfDocumentTextExtractor([HybridPdfExtractionService? extraction])
    : _extraction = extraction ?? HybridPdfExtractionService();

  final HybridPdfExtractionService _extraction;

  @override
  Future<List<String>> extractDocumentText(String sourcePath) =>
      _extraction.extractDocumentText(sourcePath);
}

/// One PDF page rendered at a known physical and pixel size.
final class RenderedPdfPage {
  const RenderedPdfPage({
    required this.pageNumber,
    required this.widthPoints,
    required this.heightPoints,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.pngBytes,
  });

  final int pageNumber;
  final double widthPoints;
  final double heightPoints;
  final int pixelWidth;
  final int pixelHeight;
  final List<int> pngBytes;
}

abstract interface class PdfPageRenderer {
  Future<List<RenderedPdfPage>> render(String sourcePath);
}

/// Uses PDFium through pdfrx and rasterizes each page at exactly 150 DPI.
final class PdfrxPdfPageRenderer implements PdfPageRenderer {
  const PdfrxPdfPageRenderer();

  static const double dpi = 150;

  @override
  Future<List<RenderedPdfPage>> render(String sourcePath) async {
    await pdfrx.pdfrxInitialize();
    final pdfrx.PdfDocument document = await pdfrx.PdfDocument.openFile(
      sourcePath,
    );
    try {
      final List<RenderedPdfPage> output = <RenderedPdfPage>[];
      for (final pdfrx.PdfPage initialPage in document.pages) {
        final pdfrx.PdfPage page = await initialPage.ensureLoaded();
        final int pixelWidth = (page.width * dpi / 72).round();
        final int pixelHeight = (page.height * dpi / 72).round();
        final pdfrx.PdfImage? rendered = await page.render(
          width: pixelWidth,
          height: pixelHeight,
          fullWidth: pixelWidth.toDouble(),
          fullHeight: pixelHeight.toDouble(),
          backgroundColor: 0xffffffff,
        );
        if (rendered == null) {
          throw UtilityFailure('Could not render PDF page ${page.pageNumber}.');
        }
        try {
          final image.Image raster = rendered.createImageNF();
          output.add(
            RenderedPdfPage(
              pageNumber: page.pageNumber,
              widthPoints: page.width,
              heightPoints: page.height,
              pixelWidth: rendered.width,
              pixelHeight: rendered.height,
              pngBytes: Uint8List.fromList(image.encodePng(raster)),
            ),
          );
        } finally {
          rendered.dispose();
        }
      }
      return output;
    } finally {
      await document.dispose();
    }
  }
}

/// Exports a local PDF to Markdown or an image-first Word/PowerPoint package.
final class PdfExportService {
  PdfExportService({
    PdfDocumentTextExtractor? extraction,
    PdfPageRenderer? renderer,
    OoxmlVisualExport? visualExport,
  }) : _extraction = extraction ?? HybridPdfDocumentTextExtractor(),
       _renderer = renderer ?? const PdfrxPdfPageRenderer(),
       _visualExport = visualExport ?? const ArchiveOoxmlVisualExport();

  final PdfDocumentTextExtractor _extraction;
  final PdfPageRenderer _renderer;
  final OoxmlVisualExport _visualExport;

  Future<UtilityResult> export({
    required String sourcePath,
    required UtilityFormat format,
    required String outputPath,
  }) async {
    if (format != UtilityFormat.markdown &&
        format != UtilityFormat.word &&
        format != UtilityFormat.powerpoint) {
      throw ArgumentError.value(format, 'format', 'Unsupported PDF export.');
    }
    if (_samePath(sourcePath, outputPath)) {
      throw const UtilityFailure(
        'Choose an output path different from the source PDF.',
      );
    }

    final List<String> extracted;
    try {
      extracted = await _extraction.extractDocumentText(sourcePath);
    } catch (error) {
      if (error is UtilityFailure) {
        rethrow;
      }
      throw UtilityFailure('Could not extract PDF text: $error');
    }
    if (extracted.isEmpty) {
      throw const UtilityFailure('The selected PDF has no pages.');
    }

    final File temporary = File(_temporaryPath(outputPath));
    try {
      final int pageCount;
      if (format == UtilityFormat.markdown) {
        pageCount = extracted.length;
        await temporary.writeAsString(_markdown(extracted), flush: true);
      } else {
        final List<RenderedPdfPage> rendered = await _renderer.render(
          sourcePath,
        );
        if (rendered.isEmpty) {
          throw const UtilityFailure('The selected PDF has no pages.');
        }
        final List<VisualPdfPage> pages = <VisualPdfPage>[
          for (int index = 0; index < rendered.length; index++)
            VisualPdfPage(
              pageNumber: rendered[index].pageNumber,
              widthPoints: rendered[index].widthPoints,
              heightPoints: rendered[index].heightPoints,
              pixelWidth: rendered[index].pixelWidth,
              pixelHeight: rendered[index].pixelHeight,
              pngBytes: rendered[index].pngBytes,
              extractedText: _pageText(
                index < extracted.length ? extracted[index] : '',
              ),
            ),
        ];
        pageCount = pages.length;
        if (format == UtilityFormat.word) {
          await _visualExport.writeWord(
            outputPath: temporary.path,
            pages: pages,
          );
        } else {
          await _visualExport.writePowerPoint(
            outputPath: temporary.path,
            pages: pages,
          );
        }
      }
      await _replaceOutput(temporary, File(outputPath));
      return UtilityResult(outputPath: outputPath, pageCount: pageCount);
    } catch (error) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (error is UtilityFailure || error is ArgumentError) {
        rethrow;
      }
      throw UtilityFailure('Could not write the exported document: $error');
    }
  }

  String _markdown(List<String> pages) {
    final StringBuffer output = StringBuffer();
    for (int index = 0; index < pages.length; index++) {
      if (index > 0) {
        output.writeln();
      }
      output
        ..writeln('## Page ${index + 1}')
        ..writeln()
        ..writeln(_pageText(pages[index]));
    }
    return output.toString();
  }

  String _pageText(String text) {
    final String normalized = text.trim();
    return normalized.isEmpty ? noExtractablePdfText : normalized;
  }

  bool _samePath(String first, String second) =>
      path.equals(path.absolute(first), path.absolute(second));

  String _temporaryPath(String outputPath) {
    final String parent = path.dirname(outputPath);
    final String name = path.basename(outputPath);
    return path.join(
      parent,
      '.$name.clarix-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
  }

  Future<void> _replaceOutput(File temporary, File output) async {
    if (!await temporary.exists()) {
      throw const UtilityFailure('The export did not produce an output file.');
    }
    if (await output.exists()) {
      await output.delete();
    }
    await temporary.rename(output.path);
  }
}
