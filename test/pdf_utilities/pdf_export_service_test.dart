import 'dart:io';

import 'package:clarix/src/features/utilities/domain/utility_job.dart';
import 'package:clarix/src/features/utilities/infrastructure/ooxml_visual_export.dart';
import 'package:clarix/src/features/utilities/infrastructure/pdf_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clarix-pdf-export-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'markdown writes an explicit heading and content for every PDF page',
    () async {
      final File output = File(_path(root, 'report.md'));
      final PdfExportService service = PdfExportService(
        extraction: _FakeTextExtractor(<String>['First page', '   ']),
        renderer: _FakePageRenderer(const <RenderedPdfPage>[]),
      );

      final UtilityResult result = await service.export(
        sourcePath: _path(root, 'report.pdf'),
        format: UtilityFormat.markdown,
        outputPath: output.path,
      );

      expect(await output.readAsString(), '''
## Page 1

First page

## Page 2

[No extractable text on this page.]
''');
      expect(result.outputPath, output.path);
      expect(result.pageCount, 2);
    },
  );

  test(
    'visual export pairs every rendered page with accessible text',
    () async {
      final File output = File(_path(root, 'report.docx'));
      final _RecordingVisualExport visual = _RecordingVisualExport();
      final PdfExportService service = PdfExportService(
        extraction: _FakeTextExtractor(<String>['Page one', '']),
        renderer: _FakePageRenderer(<RenderedPdfPage>[
          RenderedPdfPage(
            pageNumber: 1,
            widthPoints: 612,
            heightPoints: 792,
            pixelWidth: 1275,
            pixelHeight: 1650,
            pngBytes: <int>[1],
          ),
          RenderedPdfPage(
            pageNumber: 2,
            widthPoints: 792,
            heightPoints: 612,
            pixelWidth: 1650,
            pixelHeight: 1275,
            pngBytes: <int>[2],
          ),
        ]),
        visualExport: visual,
      );

      final UtilityResult result = await service.export(
        sourcePath: _path(root, 'report.pdf'),
        format: UtilityFormat.word,
        outputPath: output.path,
      );

      expect(visual.wordPages, hasLength(2));
      expect(visual.wordPages[0].extractedText, 'Page one');
      expect(
        visual.wordPages[1].extractedText,
        '[No extractable text on this page.]',
      );
      expect(visual.wordPages[1].pixelWidth, 1650);
      expect(result.pageCount, 2);
    },
  );

  test('pdfrx renderer rasterizes every page at 150 DPI', () async {
    final File source = File(_path(root, 'square.pdf'));
    final pw.Document document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(72, 144),
        build: (_) => pw.SizedBox(),
      ),
    );
    await source.writeAsBytes(await document.save());

    final List<RenderedPdfPage> pages = await const PdfrxPdfPageRenderer()
        .render(source.path);

    expect(pages, hasLength(1));
    expect(pages.single.pixelWidth, 150);
    expect(pages.single.pixelHeight, 300);
    expect(pages.single.widthPoints, closeTo(72, 0.1));
    expect(pages.single.heightPoints, closeTo(144, 0.1));
    expect(pages.single.pngBytes.take(4), <int>[137, 80, 78, 71]);
  });
}

String _path(Directory directory, String name) =>
    '${directory.path}${Platform.pathSeparator}$name';

final class _FakeTextExtractor implements PdfDocumentTextExtractor {
  const _FakeTextExtractor(this.pages);

  final List<String> pages;

  @override
  Future<List<String>> extractDocumentText(String sourcePath) async => pages;
}

final class _FakePageRenderer implements PdfPageRenderer {
  const _FakePageRenderer(this.pages);

  final List<RenderedPdfPage> pages;

  @override
  Future<List<RenderedPdfPage>> render(String sourcePath) async => pages;
}

final class _RecordingVisualExport implements OoxmlVisualExport {
  List<VisualPdfPage> wordPages = <VisualPdfPage>[];
  List<VisualPdfPage> powerpointPages = <VisualPdfPage>[];

  @override
  Future<void> writePowerPoint({
    required String outputPath,
    required List<VisualPdfPage> pages,
  }) async {
    powerpointPages = pages;
    await File(outputPath).writeAsBytes(const <int>[1]);
  }

  @override
  Future<void> writeWord({
    required String outputPath,
    required List<VisualPdfPage> pages,
  }) async {
    wordPages = pages;
    await File(outputPath).writeAsBytes(const <int>[1]);
  }
}
