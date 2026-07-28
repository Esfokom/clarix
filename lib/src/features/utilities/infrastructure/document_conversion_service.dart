import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as markdown;
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart' as pdfrx show PdfDocument;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf_widgets;

import '../domain/utility_job.dart';
import 'libreoffice_converter.dart';

export 'libreoffice_converter.dart' show OfficePdfConverter;

typedef ConversionFileExists = bool Function(String path);

/// In-app PDF generation boundary for images, text, and Markdown.
abstract interface class DirectPdfConverter {
  Future<int> imagesToPdf(List<String> sourcePaths, String outputPath);

  Future<int> textToPdf(String sourcePath, String outputPath);

  Future<int> markdownToPdf(String sourcePath, String outputPath);
}

/// Routes supported local sources to direct Dart or LibreOffice conversion.
final class DocumentConversionService {
  DocumentConversionService({
    DirectPdfConverter? direct,
    OfficePdfConverter? office,
    ConversionFileExists? fileExists,
  }) : _direct = direct ?? const DartDirectPdfConverter(),
       _office = office ?? LibreOfficeConverter(),
       _fileExists = fileExists ?? _fileExistsOnDisk;

  static const Set<String> supportedExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.txt',
    '.md',
    '.markdown',
    '.docx',
    '.pptx',
    '.xlsx',
  };

  final DirectPdfConverter _direct;
  final OfficePdfConverter _office;
  final ConversionFileExists _fileExists;

  /// Converts each source into `<outputDirectory>/<source-name>.pdf`.
  ///
  /// Sources are validated as one batch before conversion begins so unsupported
  /// formats and colliding output names cannot leave partial results.
  Future<List<UtilityResult>> convert(
    List<String> sourcePaths,
    String outputDirectory,
  ) async {
    if (sourcePaths.isEmpty) {
      throw const UtilityFailure('Select at least one file to convert.');
    }
    if (outputDirectory.trim().isEmpty) {
      throw const UtilityFailure('Select an output directory.');
    }

    final List<_ConversionRoute> routes = <_ConversionRoute>[];
    final Set<String> outputNames = <String>{};
    for (final String sourcePath in sourcePaths) {
      final String extension = path.extension(sourcePath).toLowerCase();
      if (!supportedExtensions.contains(extension)) {
        throw UtilityFailure(
          'Unsupported source type "${extension.isEmpty ? '(none)' : extension}" '
          'for ${path.basename(sourcePath)}.',
        );
      }
      final String outputName =
          '${path.basenameWithoutExtension(sourcePath)}.pdf';
      final String collisionKey = Platform.isWindows
          ? outputName.toLowerCase()
          : outputName;
      if (!outputNames.add(collisionKey)) {
        throw UtilityFailure(
          'Two selected files would use the same output name: $outputName',
        );
      }
      final String outputPath = path.join(outputDirectory, outputName);
      if (_fileExists(outputPath)) {
        throw UtilityFailure('The output PDF already exists: $outputPath');
      }
      routes.add(
        _ConversionRoute(
          sourcePath: sourcePath,
          outputPath: outputPath,
          extension: extension,
        ),
      );
    }

    final List<UtilityResult> results = <UtilityResult>[];
    try {
      for (final _ConversionRoute route in routes) {
        final int pageCount = switch (route.extension) {
          '.png' || '.jpg' || '.jpeg' || '.webp' => await _direct.imagesToPdf(
            <String>[route.sourcePath],
            route.outputPath,
          ),
          '.txt' => await _direct.textToPdf(route.sourcePath, route.outputPath),
          '.md' || '.markdown' => await _direct.markdownToPdf(
            route.sourcePath,
            route.outputPath,
          ),
          '.docx' || '.pptx' || '.xlsx' => await _convertOffice(route),
          _ => throw StateError('Unsupported prevalidated conversion route.'),
        };
        results.add(
          UtilityResult(outputPath: route.outputPath, pageCount: pageCount),
        );
      }
      return List<UtilityResult>.unmodifiable(results);
    } on UtilityFailure {
      await _removeCreatedOutputs(results);
      rethrow;
    } catch (error) {
      await _removeCreatedOutputs(results);
      throw UtilityFailure('Could not convert the selected files: $error');
    }
  }

  Future<int> _convertOffice(_ConversionRoute route) async {
    await _office.convert(route.sourcePath, route.outputPath);
    final pdfrx.PdfDocument document = await pdfrx.PdfDocument.openFile(
      route.outputPath,
    );
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  static Future<void> _removeCreatedOutputs(List<UtilityResult> results) async {
    for (final UtilityResult result in results) {
      final File output = File(result.outputPath);
      if (await output.exists()) {
        try {
          await output.delete();
        } on FileSystemException {
          // Preserve the original conversion failure.
        }
      }
    }
  }

  static bool _fileExistsOnDisk(String candidate) =>
      File(candidate).existsSync();
}

/// Generates PDFs locally with the `pdf` package.
final class DartDirectPdfConverter implements DirectPdfConverter {
  const DartDirectPdfConverter();

  @override
  Future<int> imagesToPdf(List<String> sourcePaths, String outputPath) async {
    if (sourcePaths.isEmpty) {
      throw const UtilityFailure('Select at least one image.');
    }
    final pdf_widgets.Document document = pdf_widgets.Document();
    try {
      for (final String sourcePath in sourcePaths) {
        final Uint8List bytes = await File(sourcePath).readAsBytes();
        final pdf_widgets.MemoryImage image = pdf_widgets.MemoryImage(bytes);
        document.addPage(
          pdf_widgets.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pdf_widgets.EdgeInsets.all(36),
            build: (_) => pdf_widgets.Center(
              child: pdf_widgets.Image(image, fit: pdf_widgets.BoxFit.contain),
            ),
          ),
        );
      }
      await _writeDocument(document, outputPath);
      return sourcePaths.length;
    } on UtilityFailure {
      rethrow;
    } catch (error) {
      throw UtilityFailure('Could not convert image to PDF: $error');
    }
  }

  @override
  Future<int> textToPdf(String sourcePath, String outputPath) async {
    try {
      String contents = await File(sourcePath).readAsString(encoding: utf8);
      if (contents.startsWith('\ufeff')) {
        contents = contents.substring(1);
      }
      final pdf_widgets.Font font = await _loadTextFont();
      final pdf_widgets.Document document = pdf_widgets.Document(
        theme: _themeFor(font),
      );
      document.addPage(
        pdf_widgets.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pdf_widgets.EdgeInsets.all(48),
          maxPages: 1000,
          build: (_) => contents
              .split('\n')
              .map((String line) {
                if (line.isEmpty) {
                  return pdf_widgets.SizedBox(height: 12);
                }
                return pdf_widgets.Text(
                  line,
                  style: pdf_widgets.TextStyle(
                    font: font,
                    fontSize: 10,
                    lineSpacing: 2,
                  ),
                );
              })
              .toList(growable: false),
        ),
      );
      await _writeDocument(document, outputPath);
      return document.document.pdfPageList.pages.length;
    } on UtilityFailure {
      rethrow;
    } catch (error) {
      throw UtilityFailure(
        'Could not convert ${path.basename(sourcePath)} to PDF: $error',
      );
    }
  }

  @override
  Future<int> markdownToPdf(String sourcePath, String outputPath) async {
    try {
      String contents = await File(sourcePath).readAsString(encoding: utf8);
      if (contents.startsWith('\ufeff')) {
        contents = contents.substring(1);
      }
      final List<markdown.Node> nodes = markdown.Document(
        extensionSet: markdown.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parse(contents);
      final pdf_widgets.Font font = await _loadTextFont();
      final pdf_widgets.Document document = pdf_widgets.Document(
        theme: _themeFor(font),
      );
      document.addPage(
        pdf_widgets.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pdf_widgets.EdgeInsets.all(48),
          maxPages: 1000,
          build: (_) => nodes
              .expand((markdown.Node node) => _markdownBlock(node, font))
              .toList(growable: false),
        ),
      );
      await _writeDocument(document, outputPath);
      return document.document.pdfPageList.pages.length;
    } on UtilityFailure {
      rethrow;
    } catch (error) {
      throw UtilityFailure(
        'Could not convert ${path.basename(sourcePath)} to PDF: $error',
      );
    }
  }

  static Iterable<pdf_widgets.Widget> _markdownBlock(
    markdown.Node node,
    pdf_widgets.Font font,
  ) sync* {
    if (node is markdown.Text) {
      yield _paragraph(<markdown.Node>[node], font);
      return;
    }
    if (node is! markdown.Element) {
      return;
    }
    final List<markdown.Node> children =
        node.children ?? const <markdown.Node>[];
    final RegExpMatch? heading = RegExp(r'^h([1-6])$').firstMatch(node.tag);
    if (heading != null) {
      final int level = int.parse(heading.group(1)!);
      yield pdf_widgets.Padding(
        padding: pdf_widgets.EdgeInsets.only(
          top: level == 1 ? 8 : 5,
          bottom: 6,
        ),
        child: pdf_widgets.Text(
          node.textContent,
          style: pdf_widgets.TextStyle(
            font: font,
            fontSize: 24 - (level * 2.2),
            fontWeight: pdf_widgets.FontWeight.bold,
          ),
        ),
      );
      return;
    }
    switch (node.tag) {
      case 'p':
        yield _paragraph(children, font);
      case 'ul':
        yield* _list(children, font, ordered: false);
      case 'ol':
        yield* _list(children, font, ordered: true);
      case 'pre':
        yield pdf_widgets.Container(
          margin: const pdf_widgets.EdgeInsets.symmetric(vertical: 5),
          padding: const pdf_widgets.EdgeInsets.all(9),
          decoration: const pdf_widgets.BoxDecoration(
            color: PdfColor.fromInt(0xfff1f3f5),
          ),
          child: pdf_widgets.Text(
            node.textContent.trimRight(),
            style: pdf_widgets.TextStyle(font: font, fontSize: 9),
          ),
        );
      case 'blockquote':
        yield pdf_widgets.Container(
          margin: const pdf_widgets.EdgeInsets.symmetric(vertical: 5),
          padding: const pdf_widgets.EdgeInsets.only(left: 10),
          decoration: const pdf_widgets.BoxDecoration(
            border: pdf_widgets.Border(
              left: pdf_widgets.BorderSide(
                color: PdfColor.fromInt(0xff87909c),
                width: 2,
              ),
            ),
          ),
          child: _paragraph(children, font),
        );
      case 'hr':
        yield pdf_widgets.Divider(color: const PdfColor.fromInt(0xffa8afb8));
      default:
        for (final markdown.Node child in children) {
          yield* _markdownBlock(child, font);
        }
    }
    yield pdf_widgets.SizedBox(height: 6);
  }

  static Iterable<pdf_widgets.Widget> _list(
    List<markdown.Node> nodes,
    pdf_widgets.Font font, {
    required bool ordered,
  }) sync* {
    int index = 0;
    for (final markdown.Node item in nodes) {
      if (item is! markdown.Element || item.tag != 'li') {
        continue;
      }
      index++;
      yield pdf_widgets.Padding(
        padding: const pdf_widgets.EdgeInsets.only(left: 12, bottom: 4),
        child: pdf_widgets.Row(
          crossAxisAlignment: pdf_widgets.CrossAxisAlignment.start,
          children: <pdf_widgets.Widget>[
            pdf_widgets.SizedBox(
              width: 22,
              child: pdf_widgets.Text(
                ordered ? '$index.' : '\u2022',
                style: pdf_widgets.TextStyle(font: font, fontSize: 11),
              ),
            ),
            pdf_widgets.Expanded(
              child: _paragraph(
                item.children ?? const <markdown.Node>[],
                font,
                margin: pdf_widgets.EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );
    }
  }

  static pdf_widgets.Widget _paragraph(
    List<markdown.Node> nodes,
    pdf_widgets.Font font, {
    pdf_widgets.EdgeInsetsGeometry margin = const pdf_widgets.EdgeInsets.only(
      bottom: 7,
    ),
  }) {
    return pdf_widgets.Padding(
      padding: margin,
      child: pdf_widgets.RichText(
        text: pdf_widgets.TextSpan(
          style: pdf_widgets.TextStyle(font: font, fontSize: 11),
          children: nodes
              .expand((markdown.Node node) => _inlineSpans(node, font))
              .toList(growable: false),
        ),
      ),
    );
  }

  static Iterable<pdf_widgets.InlineSpan> _inlineSpans(
    markdown.Node node,
    pdf_widgets.Font font,
  ) sync* {
    if (node is markdown.Text) {
      yield pdf_widgets.TextSpan(text: node.text);
      return;
    }
    if (node is! markdown.Element) {
      return;
    }
    final List<markdown.Node> children =
        node.children ?? const <markdown.Node>[];
    if (node.tag == 'br') {
      yield const pdf_widgets.TextSpan(text: '\n');
      return;
    }
    if (node.tag == 'a') {
      final String destination = node.attributes['href'] ?? '';
      final String label = node.textContent;
      final String text = destination.isEmpty || destination == label
          ? label
          : '$label ($destination)';
      yield pdf_widgets.TextSpan(
        text: text,
        style: pdf_widgets.TextStyle(
          font: font,
          color: PdfColors.blue700,
          decoration: pdf_widgets.TextDecoration.underline,
        ),
        annotation: destination.isEmpty
            ? null
            : pdf_widgets.AnnotationUrl(destination),
      );
      return;
    }
    if (node.tag == 'img') {
      final String alt = node.attributes['alt'] ?? 'Image';
      final String source = node.attributes['src'] ?? '';
      yield pdf_widgets.TextSpan(text: source.isEmpty ? alt : '$alt ($source)');
      return;
    }
    final pdf_widgets.TextStyle? style = switch (node.tag) {
      'strong' || 'b' => pdf_widgets.TextStyle(
        font: font,
        fontWeight: pdf_widgets.FontWeight.bold,
      ),
      'em' || 'i' => pdf_widgets.TextStyle(
        font: font,
        fontStyle: pdf_widgets.FontStyle.italic,
      ),
      'code' => pdf_widgets.TextStyle(
        font: font,
        fontSize: 9.5,
        background: const pdf_widgets.BoxDecoration(
          color: PdfColor.fromInt(0xfff1f3f5),
        ),
      ),
      _ => null,
    };
    yield pdf_widgets.TextSpan(
      style: style,
      children: children
          .expand((markdown.Node child) => _inlineSpans(child, font))
          .toList(growable: false),
    );
  }

  static pdf_widgets.ThemeData _themeFor(pdf_widgets.Font font) =>
      pdf_widgets.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      );

  static Future<pdf_widgets.Font> _loadTextFont() async {
    const List<String> candidates = <String>[
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\arial.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    ];
    for (final String candidate in candidates) {
      final File file = File(candidate);
      if (await file.exists()) {
        final Uint8List bytes = await file.readAsBytes();
        return pdf_widgets.Font.ttf(ByteData.sublistView(bytes));
      }
    }
    return pdf_widgets.Font.helvetica();
  }

  static Future<void> _writeDocument(
    pdf_widgets.Document document,
    String outputPath,
  ) async {
    final File output = File(outputPath);
    if (await output.exists()) {
      throw UtilityFailure('The output PDF already exists: $outputPath');
    }
    if (!await output.parent.exists()) {
      throw UtilityFailure(
        'The selected output directory does not exist: ${output.parent.path}',
      );
    }
    final File pending = File(
      '$outputPath.clarix-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      final Uint8List bytes = await document.save(
        enableEventLoopBalancing: true,
      );
      await pending.writeAsBytes(bytes, flush: true);
      if (await output.exists()) {
        throw UtilityFailure('The output PDF already exists: $outputPath');
      }
      await pending.rename(outputPath);
    } finally {
      if (await pending.exists()) {
        await pending.delete();
      }
    }
  }
}

final class _ConversionRoute {
  const _ConversionRoute({
    required this.sourcePath,
    required this.outputPath,
    required this.extension,
  });

  final String sourcePath;
  final String outputPath;
  final String extension;
}
