import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../domain/pdf_edit_session.dart';
import '../domain/pdf_native_edit_types.dart';
import '../domain/pdf_page_object.dart';
import '../domain/pdf_text_types.dart';
import 'pdfium_text_engine_stub.dart'
    if (dart.library.io) 'pdfium_text_engine_native.dart'
    as implementation;

abstract interface class PdfPreviewMutator {
  Future<void> setTextObjectsVisible({
    required PdfDocument document,
    required PdfTextBlock block,
    required bool visible,
  });

  Future<void> setPageObjectPreviewTransform({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
    required PdfTransform transform,
  });
}

abstract interface class PdfLiveDocumentMutator {
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  });

  Future<Uint8List> encodeLiveDocument({required PdfDocument document});
}

abstract interface class PdfTextEngine
    implements PdfPreviewMutator, PdfLiveDocumentMutator {
  Future<List<PdfTextBlock>> inspectPages({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  });

  Future<PdfResolvedTextObject> resolveLocator({
    required PdfDocument document,
    required PdfTextBlockLocator locator,
  });

  Future<List<PdfPageObject>> inspectPageObjects({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  });

  Future<PdfPageObject> resolvePageObject({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
  });

  Future<Uint8List> applyDraft({
    required PdfDocument document,
    required PdfEditingSession draft,
  });
}

final class PdfResolvedTextObject {
  const PdfResolvedTextObject({required this.block});

  final PdfTextBlock block;
}

PdfTextEngine createPdfTextEngine() => implementation.createPdfTextEngine();
