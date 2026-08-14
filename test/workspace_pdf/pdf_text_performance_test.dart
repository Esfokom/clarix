import 'dart:typed_data';

import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_native_edit_types.dart';
import 'package:clarix/src/features/workspace/domain/pdf_page_object.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_text_engine.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdfium_text_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test('visible warm-page discovery meets the 250 ms budget', () async {
    final file = await PdfTextFixture.singleBlock('Warm page text');
    addTearDown(() => file.parent.delete(recursive: true));
    final document = await PdfDocument.openFile(file.path);
    addTearDown(document.dispose);
    const engine = PdfiumTextEngine();
    final revision = await sha256File(file);
    await engine.inspectPages(
      document: document,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    );

    final stopwatch = Stopwatch()..start();
    await engine.inspectPages(
      document: document,
      sourceRevision: revision,
      pageNumbers: const <int>[1],
    );
    stopwatch.stop();

    // This is intentionally a release budget, not an averaged benchmark.
    expect(stopwatch.elapsedMilliseconds, lessThan(250));
  });

  test('10k-character draft mutation does not reparse the document', () async {
    final engine = _CountingPdfTextEngine();
    final controller = PdfEditingController(engine: engine)
      ..registerSession('tab', _session());

    final result = await controller.dispatch(
      ReplacePdfTextIntent(
        documentId: 'document',
        documentRevision: 'revision',
        locator: _locator,
        range: const PdfTextRange(0, 4),
        replacement: 'x' * 10000,
      ),
      provenance: PdfCommandProvenance.manual,
    );

    expect(result.isSuccess, isTrue);
    expect(controller.sessionFor('tab').blocks.single.text.length, 10000);
    expect(engine.inspectCalls, 0);
  });
}

final _locator = PdfTextBlockLocator(
  pageNumber: 1,
  objectPath: const <int>[0],
  textDigest: 'text',
  geometryDigest: 'geometry',
  fontFingerprint: 'font',
  sourceRevision: 'revision',
);

PdfEditingSession _session() {
  const style = PdfTextStyle(
    fontFamily: 'Helvetica',
    fontSize: 12,
    fillColorValue: 0xff000000,
    fontWeight: 400,
    italic: false,
    underline: false,
    baselineShift: 0,
    alignment: PdfTextAlignment.left,
    characterSpacing: 0,
    lineSpacing: 12,
    horizontalScaling: 1,
  );
  final block = PdfTextBlock(
    locator: _locator,
    text: 'seed',
    originalText: 'seed',
    runs: const <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, 4), style: style),
    ],
    bounds: const PdfBox(0, 0, 100000, 100),
    transform: const PdfTransform(1, 0, 0, 1, 0, 0),
    baseline: 12,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: PdfTextCapability.values,
    readOnlyReason: null,
  );
  return PdfEditingSession.empty(
    'document',
    sourceRevision: 'revision',
  ).withBlocks(<PdfTextBlock>[block]);
}

final class _CountingPdfTextEngine implements PdfTextEngine {
  int inspectCalls = 0;

  @override
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> encodeLiveDocument({required PdfDocument document}) async =>
      Uint8List(0);

  @override
  Future<Uint8List> applyDraft({
    required PdfDocument document,
    required PdfEditingSession draft,
  }) async => Uint8List(0);

  @override
  Future<List<PdfTextBlock>> inspectPages({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) async {
    inspectCalls++;
    return const <PdfTextBlock>[];
  }

  @override
  Future<PdfResolvedTextObject> resolveLocator({
    required PdfDocument document,
    required PdfTextBlockLocator locator,
  }) => throw UnimplementedError();

  @override
  Future<List<PdfPageObject>> inspectPageObjects({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) async => const <PdfPageObject>[];

  @override
  Future<PdfPageObject> resolvePageObject({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
  }) => throw UnimplementedError();

  @override
  Future<void> setTextObjectsVisible({
    required PdfDocument document,
    required PdfTextBlock block,
    required bool visible,
  }) async {}

  @override
  Future<void> setPageObjectPreviewTransform({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
    required PdfTransform transform,
  }) async {}
}
