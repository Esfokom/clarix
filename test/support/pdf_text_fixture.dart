import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final class PdfTextFixture {
  static Future<File> singleBlock(String text) async {
    return _write('text.pdf', <pw.Page>[
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 12)),
        ),
      ),
    ]);
  }

  static Future<File> multiObjectBlock() async {
    return _write('multi-object.pdf', <pw.Page>[
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: <pw.Widget>[
              pw.Text('Hello', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('world', style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    ]);
  }

  static Future<File> rotatedBlock(String text) async {
    return _write('rotated.pdf', <pw.Page>[
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Transform.rotate(
            angle: 0.12,
            child: pw.Text(text, style: const pw.TextStyle(fontSize: 12)),
          ),
        ),
      ),
    ]);
  }

  static Future<File> imageOnly() async {
    final image = pw.MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    return _write('image-only.pdf', <pw.Page>[
      pw.Page(build: (_) => pw.Image(image)),
    ]);
  }

  static Future<File> mixedPageObjects() async {
    final image = pw.MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    return _write('mixed-objects.pdf', <pw.Page>[
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text('Selectable text'),
            pw.SizedBox(height: 16),
            pw.Image(image, width: 24, height: 24),
            pw.SizedBox(height: 16),
            pw.Container(
              width: 80,
              height: 30,
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
            ),
          ],
        ),
      ),
    ]);
  }

  static Future<File> malformed() async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'clarix-pdf-text-',
    );
    final File file = File('${directory.path}${Platform.pathSeparator}bad.pdf');
    await file.writeAsBytes(<int>[0x25, 0x50, 0x44, 0x46, 0x2d], flush: true);
    return file;
  }

  static Future<File> _write(String name, List<pw.Page> pages) async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'clarix-pdf-text-',
    );
    final File file = File('${directory.path}${Platform.pathSeparator}$name');
    final pw.Document document = pw.Document();
    for (final page in pages) {
      document.addPage(page);
    }
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }
}

Future<String> sha256File(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

String sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();
