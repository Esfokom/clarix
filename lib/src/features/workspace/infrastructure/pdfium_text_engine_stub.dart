import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../domain/pdf_edit_session.dart';
import '../domain/pdf_page_object.dart';
import '../domain/pdf_text_types.dart';
import 'pdf_text_engine.dart';

PdfTextEngine createPdfTextEngine() => const PdfiumTextEngineStub();

final class PdfiumTextEngineStub implements PdfTextEngine {
  const PdfiumTextEngineStub();

  @override
  Future<Uint8List> applyDraft({
    required PdfDocument document,
    required PdfEditingSession draft,
  }) => Future<Uint8List>.error(const PdfNativeEditingUnavailableFailure());

  @override
  Future<List<PdfTextBlock>> inspectPages({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) => Future<List<PdfTextBlock>>.error(
    const PdfNativeEditingUnavailableFailure(),
  );

  @override
  Future<PdfResolvedTextObject> resolveLocator({
    required PdfDocument document,
    required PdfTextBlockLocator locator,
  }) => Future<PdfResolvedTextObject>.error(
    const PdfNativeEditingUnavailableFailure(),
  );

  @override
  Future<List<PdfPageObject>> inspectPageObjects({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) => Future<List<PdfPageObject>>.error(
    const PdfNativeEditingUnavailableFailure(),
  );

  @override
  Future<PdfPageObject> resolvePageObject({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
  }) => Future<PdfPageObject>.error(const PdfNativeEditingUnavailableFailure());
}
