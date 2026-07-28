import 'dart:io';

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
    required this.imagePath,
  });

  final int pageNumber;
  final double widthPoints;
  final double heightPoints;
  final int pixelWidth;
  final int pixelHeight;
  final String imagePath;
}

abstract interface class PdfPageRenderer {
  Future<List<RenderedPdfPage>> render(
    String sourcePath, {
    required Directory spoolDirectory,
  });
}

/// Uses PDFium through pdfrx and rasterizes each page at exactly 150 DPI.
final class PdfrxPdfPageRenderer implements PdfPageRenderer {
  const PdfrxPdfPageRenderer();

  static const double dpi = 150;

  @override
  Future<List<RenderedPdfPage>> render(
    String sourcePath, {
    required Directory spoolDirectory,
  }) async {
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
          final File imageFile = File(
            path.join(spoolDirectory.path, 'page-${page.pageNumber}.png'),
          );
          await imageFile.writeAsBytes(image.encodePng(raster), flush: true);
          output.add(
            RenderedPdfPage(
              pageNumber: page.pageNumber,
              widthPoints: page.width,
              heightPoints: page.height,
              pixelWidth: rendered.width,
              pixelHeight: rendered.height,
              imagePath: imageFile.path,
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

abstract interface class OutputFileSystem {
  Future<bool> exists(String filePath);

  Future<void> rename(String sourcePath, String destinationPath);

  Future<void> delete(String filePath);
}

final class LocalOutputFileSystem implements OutputFileSystem {
  const LocalOutputFileSystem();

  @override
  Future<void> delete(String filePath) => File(filePath).delete();

  @override
  Future<bool> exists(String filePath) => File(filePath).exists();

  @override
  Future<void> rename(String sourcePath, String destinationPath) async {
    await File(sourcePath).rename(destinationPath);
  }
}

abstract interface class OutputFileReplacer {
  Future<void> replace({required File temporary, required File output});
}

/// Installs a completed export and restores an existing destination on failure.
final class BackupOutputFileReplacer implements OutputFileReplacer {
  BackupOutputFileReplacer({OutputFileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const LocalOutputFileSystem();

  final OutputFileSystem _fileSystem;

  @override
  Future<void> replace({required File temporary, required File output}) async {
    if (!await _fileSystem.exists(temporary.path)) {
      throw const UtilityFailure('The export did not produce an output file.');
    }
    String? backupPath;
    if (await _fileSystem.exists(output.path)) {
      backupPath = _backupPath(output.path);
      await _fileSystem.rename(output.path, backupPath);
    }
    try {
      await _fileSystem.rename(temporary.path, output.path);
    } catch (error, stackTrace) {
      if (backupPath != null) {
        if (await _fileSystem.exists(output.path)) {
          await _fileSystem.delete(output.path);
        }
        await _fileSystem.rename(backupPath, output.path);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (backupPath != null) {
      try {
        await _fileSystem.delete(backupPath);
      } on FileSystemException {
        // The new output is installed. A stale backup is safer than removing it.
      }
    }
  }

  String _backupPath(String outputPath) {
    final String parent = path.dirname(outputPath);
    final String name = path.basename(outputPath);
    return path.join(
      parent,
      '.$name.clarix-backup-${DateTime.now().microsecondsSinceEpoch}',
    );
  }
}

/// Exports a local PDF to Markdown or an image-first Word/PowerPoint package.
final class PdfExportService {
  PdfExportService({
    PdfDocumentTextExtractor? extraction,
    PdfPageRenderer? renderer,
    OoxmlVisualExport? visualExport,
    OutputFileReplacer? outputReplacer,
  }) : _extraction = extraction ?? HybridPdfDocumentTextExtractor(),
       _renderer = renderer ?? const PdfrxPdfPageRenderer(),
       _visualExport = visualExport ?? const ArchiveOoxmlVisualExport(),
       _outputReplacer = outputReplacer ?? BackupOutputFileReplacer();

  final PdfDocumentTextExtractor _extraction;
  final PdfPageRenderer _renderer;
  final OoxmlVisualExport _visualExport;
  final OutputFileReplacer _outputReplacer;

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
    Directory? spoolDirectory;
    try {
      final int pageCount;
      if (format == UtilityFormat.markdown) {
        pageCount = extracted.length;
        await temporary.writeAsString(_markdown(extracted), flush: true);
      } else {
        spoolDirectory = await Directory.systemTemp.createTemp(
          'clarix-pdf-export-pages-',
        );
        final List<RenderedPdfPage> rendered = await _renderer.render(
          sourcePath,
          spoolDirectory: spoolDirectory,
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
              imagePath: rendered[index].imagePath,
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
      await _outputReplacer.replace(
        temporary: temporary,
        output: File(outputPath),
      );
      return UtilityResult(outputPath: outputPath, pageCount: pageCount);
    } catch (error) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (error is UtilityFailure || error is ArgumentError) {
        rethrow;
      }
      throw UtilityFailure('Could not write the exported document: $error');
    } finally {
      if (spoolDirectory != null && await spoolDirectory.exists()) {
        await spoolDirectory.delete(recursive: true);
      }
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
}
