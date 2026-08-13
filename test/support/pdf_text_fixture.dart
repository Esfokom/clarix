import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final class PdfTextFixture {
  static Future<File> singleBlock(String text) async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'clarix-pdf-text-',
    );
    final File file = File(
      '${directory.path}${Platform.pathSeparator}text.pdf',
    );
    final pw.Document document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 12)),
        ),
      ),
    );
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }
}

Future<String> sha256File(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

String sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();
