import 'package:clarix/src/core/ffi/editing_api.dart' as native;
import 'package:clarix/src/features/pdf_editor/domain/pdf_text_types.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/live_pdfium_import_manifest_builder.dart';
import 'package:flutter_test/flutter_test.dart';

const PdfTextStyle _style = PdfTextStyle(
  fontFamily: 'Helvetica',
  fontSize: 12,
  fillColorValue: 0xff000000,
  fontWeight: 400,
  italic: false,
  underline: false,
  baselineShift: 0,
  alignment: PdfTextAlignment.left,
  characterSpacing: 0,
  lineSpacing: 0,
  horizontalScaling: 1,
);

PdfTextBlock _block({
  required String text,
  required List<List<int>> objectPaths,
  bool editable = true,
  bool includeRun = true,
}) => PdfTextBlock(
  locator: PdfTextBlockLocator(
    pageNumber: 1,
    objectPath: objectPaths.first,
    textDigest: 'digest',
    geometryDigest: 'geom',
    fontFingerprint: 'font',
    sourceRevision: 'source',
  ),
  text: text,
  originalText: text,
  runs: includeRun
      ? <PdfTextRun>[PdfTextRun(range: PdfTextRange(0, text.length), style: _style)]
      : const <PdfTextRun>[],
  bounds: const PdfBox(0, 0, 100, 20),
  transform: const PdfTransform(1, 0, 0, 1, 0, 0),
  baseline: 10,
  writingDirection: PdfWritingDirection.leftToRight,
  capabilities: <PdfTextCapability>[
    if (editable) PdfTextCapability.replace,
  ],
  readOnlyReason: null,
  objectPaths: objectPaths,
);

void main() {
  test('imports a multi-object block as one binding with all paths', () {
    final manifest = const LivePdfiumImportManifestBuilder().build(
      sourceFingerprint: 'source',
      blocks: <PdfTextBlock>[
        _block(
          text: 'Hello world',
          objectPaths: <List<int>>[<int>[0], <int>[1]],
        ),
      ],
    );

    expect(manifest.bindings, hasLength(1));
    final binding = manifest.bindings.single;
    expect(binding.sourceKey, 'source/live-pdfium/page/1/object/0|1');
    expect(binding.locator.objectPath, <int>[0]);
    expect(binding.locator.objectPaths, <List<int>>[<int>[0], <int>[1]]);
    expect(binding.locator.allObjectPaths, <List<int>>[<int>[0], <int>[1]]);
  });

  test('keeps the single-object source key format unchanged', () {
    final manifest = const LivePdfiumImportManifestBuilder().build(
      sourceFingerprint: 'source',
      blocks: <PdfTextBlock>[
        _block(text: 'Solo', objectPaths: <List<int>>[<int>[0]]),
      ],
    );

    final binding = manifest.bindings.single;
    expect(binding.sourceKey, 'source/live-pdfium/page/1/object/0');
    expect(binding.locator.allObjectPaths, <List<int>>[<int>[0]]);
  });

  test('buildPageImport converts a multi-object block into one live object',
      () {
    final import = const LivePdfiumImportManifestBuilder().buildPageImport(
      expectedRevision: 3,
      sourceFingerprint: 'source',
      pageNumber: 1,
      width: 612,
      height: 792,
      blocks: <PdfTextBlock>[
        _block(
          text: 'Hello world',
          objectPaths: <List<int>>[<int>[0], <int>[1]],
        ),
      ],
    );

    expect(import.expectedRevision, BigInt.from(3));
    expect(import.objects, hasLength(1));
    final object = import.objects.single;
    expect(object.text, 'Hello world');
    expect(object.editable, isTrue);
    expect(object.objectId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(object.sourceKey, 'source/live-pdfium/page/1/object/0|1');
    expect(object.bounds, isA<native.NativePdfBox>());
  });

  test('read-only blocks import with the editable flag cleared', () {
    final import = const LivePdfiumImportManifestBuilder().buildPageImport(
      expectedRevision: 0,
      sourceFingerprint: 'source',
      pageNumber: 1,
      width: 612,
      height: 792,
      blocks: <PdfTextBlock>[
        _block(
          text: 'Locked',
          objectPaths: <List<int>>[<int>[0]],
          editable: false,
        ),
      ],
    );

    expect(import.objects.single.editable, isFalse);
  });

  test('excludes blocks without style runs', () {
    final manifest = const LivePdfiumImportManifestBuilder().build(
      sourceFingerprint: 'source',
      blocks: <PdfTextBlock>[
        _block(
          text: 'Empty',
          objectPaths: <List<int>>[<int>[0]],
          includeRun: false,
        ),
      ],
    );

    expect(manifest.bindings, isEmpty);
  });
}
