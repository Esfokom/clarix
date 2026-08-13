import 'package:pdfrx/pdfrx.dart';

import '../domain/pdf_text_types.dart';
import 'pdfium_text_engine_stub.dart'
    if (dart.library.io) 'pdfium_text_engine_native.dart'
    as implementation;

abstract interface class PdfTextEngine {
  Future<List<PdfTextBlock>> inspectPages({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  });

  Future<PdfResolvedTextObject> resolveLocator({
    required PdfDocument document,
    required PdfTextBlockLocator locator,
  });
}

final class PdfResolvedTextObject {
  const PdfResolvedTextObject({required this.block});

  final PdfTextBlock block;
}

PdfTextEngine createPdfTextEngine() => implementation.createPdfTextEngine();
