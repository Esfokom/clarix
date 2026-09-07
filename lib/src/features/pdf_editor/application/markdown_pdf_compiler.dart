import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Premium Markdown-to-PDF Compiler with explicit Page Break support,
/// clean unicode box-character filtering, and publication-quality styling.
class MarkdownPdfCompiler {
  MarkdownPdfCompiler._();

  static final PdfColor _slate900 = PdfColor.fromHex('#0F172A');
  static final PdfColor _slate800 = PdfColor.fromHex('#1E293B');
  static final PdfColor _slate700 = PdfColor.fromHex('#334155');
  static final PdfColor _slate600 = PdfColor.fromHex('#475569');
  static final PdfColor _slate100 = PdfColor.fromHex('#F1F5F9');
  static final PdfColor _primaryBlue = PdfColor.fromHex('#1E40AF');

  /// Clean text from unprintable box/glyph characters (e.g. \uFFFD, unmapped bullets)
  static String _cleanText(String input) {
    return input
        .replaceAll('\uFFFD', '')
        .replaceAll(RegExp(r'[\uF000-\uFFFF]'), '')
        .replaceAll('•', '-')
        .replaceAll('🕮', '')
        .replaceAll('🗌', '')
        .trim();
  }

  static Future<Uint8List> compile(String markdown, {String title = 'Clarix Document'}) async {
    final pdf = pw.Document(
      title: title,
      author: 'Clarix AI Engine',
    );

    final pageHeaderRegex = RegExp(r'^\s*##\s*Page\s*\d+', caseSensitive: false);
    final rawLines = markdown.split('\n');

    final pageBlocks = <List<String>>[];
    List<String> currentBlock = [];

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (pageHeaderRegex.hasMatch(trimmed)) {
        if (currentBlock.isNotEmpty) {
          pageBlocks.add(List<String>.from(currentBlock));
          currentBlock.clear();
        }
      } else {
        currentBlock.add(line);
      }
    }
    if (currentBlock.isNotEmpty) {
      pageBlocks.add(currentBlock);
    }

    final blocksToRender = pageBlocks.isNotEmpty ? pageBlocks : [rawLines];

    for (var pageIndex = 0; pageIndex < blocksToRender.length; pageIndex++) {
      final lines = blocksToRender[pageIndex];
      final widgets = <pw.Widget>[];

      bool inCodeBlock = false;
      final codeBlockBuffer = StringBuffer();
      List<List<String>> tableRows = [];
      bool inTable = false;

      void flushTable() {
        if (tableRows.isNotEmpty) {
          widgets.add(
            pw.TableHelper.fromTextArray(
              headers: tableRows.first,
              data: tableRows.skip(1).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: _primaryBlue),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              cellStyle: pw.TextStyle(fontSize: 9, color: _slate800),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),
          );
          widgets.add(pw.SizedBox(height: 8));
          tableRows = [];
          inTable = false;
        }
      }

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimRight();

        if (trimmed.startsWith('```')) {
          if (inTable) flushTable();
          if (inCodeBlock) {
            final contentStr = codeBlockBuffer.toString().trimRight();
            if (contentStr.contains('mermaid') || contentStr.contains('stateDiagram') || contentStr.contains('-->')) {
              widgets.add(_buildMermaidDiagramWidget(contentStr));
            } else {
              widgets.add(
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.symmetric(vertical: 4),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: _slate900,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    contentStr,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      font: pw.Font.courier(),
                      color: _slate100,
                      height: 1.3,
                    ),
                  ),
                ),
              );
            }
            codeBlockBuffer.clear();
            inCodeBlock = false;
          } else {
            inCodeBlock = true;
          }
          continue;
        }

        if (inCodeBlock) {
          codeBlockBuffer.writeln(line);
          continue;
        }

        final cleanLine = _cleanText(trimmed);
        if (cleanLine.isEmpty) {
          widgets.add(pw.SizedBox(height: 4));
          continue;
        }

        // Explicitly skip any literal ## Page X heading so it does not print inside page body text
        if (pageHeaderRegex.hasMatch(cleanLine)) {
          continue;
        }

        // Images (![alt](src))
        final imageMatch = RegExp(r'!\[(.*?)\]\((.*?)\)').firstMatch(cleanLine);
        if (imageMatch != null) {
          if (inTable) flushTable();
          final src = imageMatch.group(2)?.trim() ?? '';
          if (src.startsWith('data:image/') && src.contains('base64,')) {
            try {
              final base64Payload = src.split('base64,').last.replaceAll(RegExp(r'\s+'), '');
              final bytes = base64Decode(base64Payload);
              final imageWidget = pw.MemoryImage(bytes);
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 6),
                  alignment: pw.Alignment.center,
                  child: pw.Image(
                    imageWidget,
                    fit: pw.BoxFit.contain,
                    height: 220,
                  ),
                ),
              );
              continue;
            } catch (_) {}
          } else {
            try {
              final parsedUri = Uri.tryParse(src);
              final filePath = parsedUri != null && parsedUri.scheme == 'file'
                  ? parsedUri.toFilePath()
                  : src;
              if (File(filePath).existsSync()) {
                final bytes = File(filePath).readAsBytesSync();
                final imageWidget = pw.MemoryImage(bytes);
                widgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.symmetric(vertical: 6),
                    alignment: pw.Alignment.center,
                    child: pw.Image(
                      imageWidget,
                      fit: pw.BoxFit.contain,
                      height: 220,
                    ),
                  ),
                );
                continue;
              }
            } catch (_) {}
          }
        }

        // Tables (| col1 | col2 |)
        if (cleanLine.startsWith('|') && cleanLine.endsWith('|')) {
          if (cleanLine.contains('---')) continue;
          final cells = cleanLine
              .split('|')
              .map((c) => _cleanText(c))
              .where((c) => c.isNotEmpty)
              .toList();
          if (cells.isNotEmpty) {
            inTable = true;
            tableRows.add(cells);
            continue;
          }
        } else if (inTable) {
          flushTable();
        }

        // Headers
        if (cleanLine.startsWith('# ')) {
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 8, bottom: 6),
              padding: const pw.EdgeInsets.only(bottom: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _primaryBlue, width: 1.5),
                ),
              ),
              child: pw.Text(
                cleanLine.substring(2),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _primaryBlue,
                ),
              ),
            ),
          );
        } else if (cleanLine.startsWith('## ')) {
          final headerText = cleanLine.substring(3).trim();
          if (RegExp(r'^Page\s+\d+', caseSensitive: false).hasMatch(headerText)) {
            continue; // Do not output literal "Page X" as body header
          }
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
              child: pw.Text(
                headerText,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _slate800,
                ),
              ),
            ),
          );
        } else if (cleanLine.startsWith('### ')) {
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 6, bottom: 3),
              child: pw.Text(
                cleanLine.substring(4),
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _slate800,
                ),
              ),
            ),
          );
        } else if (cleanLine.startsWith('- ') || cleanLine.startsWith('* ')) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 6, top: 1.5, bottom: 1.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 4,
                    height: 4,
                    margin: const pw.EdgeInsets.only(top: 4, right: 6),
                    decoration: pw.BoxDecoration(
                      color: _primaryBlue,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      cleanLine.substring(2),
                      style: pw.TextStyle(fontSize: 9.5, color: _slate900, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (cleanLine.startsWith('> ')) {
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.symmetric(vertical: 4),
              padding: const pw.EdgeInsets.all(8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.blue700, width: 3),
                ),
              ),
              child: pw.Text(
                cleanLine.substring(2),
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontStyle: pw.FontStyle.italic,
                  color: _slate700,
                ),
              ),
            ),
          );
        } else {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                cleanLine,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  color: _slate900,
                  height: 1.4,
                ),
              ),
            ),
          );
        }
      }

      if (inTable) flushTable();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          header: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 6),
              margin: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.75),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _slate700,
                    ),
                  ),
                  pw.Text(
                    'Clarix PDF Document',
                    style: pw.TextStyle(fontSize: 8, color: _slate600),
                  ),
                ],
              ),
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated via Clarix AI Engine',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _slate700,
                    ),
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) => widgets,
        ),
      );
    }

    return pdf.save();
  }

  static Future<File> saveToFile(String markdown, String targetPath) async {
    final fileName = targetPath.split(Platform.pathSeparator).last;
    final bytes = await compile(markdown, title: fileName);
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static pw.Widget _buildMermaidDiagramWidget(String rawContent) {
    final lines = rawContent.split('\n');
    final transitions = <pw.Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('-->')) {
        final parts = trimmed.split('-->');
        final fromNode = parts[0].replaceAll('[*]', 'START').replaceAll('state', '').trim();
        final rest = parts[1];
        String toNode = rest.trim();
        String label = '';

        if (rest.contains(':')) {
          final labelParts = rest.split(':');
          toNode = labelParts[0].trim();
          label = labelParts[1].trim();
        }

        transitions.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 2.5),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: PdfColors.blue200, width: 0.5),
            ),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _primaryBlue,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Text(
                    fromNode.isEmpty ? 'START' : fromNode,
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                  child: pw.Text(
                    label.isNotEmpty ? '─── [ $label ] ───▶' : '──────────▶',
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _slate700),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _slate800,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Text(
                    toNode,
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.blue800, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(color: _primaryBlue, shape: pw.BoxShape.circle),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                'State-Transition / Flow Diagram',
                style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _primaryBlue),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          if (transitions.isNotEmpty)
            ...transitions
          else
            pw.Text(rawContent, style: pw.TextStyle(fontSize: 8.5, color: _slate800)),
        ],
      ),
    );
  }
}

