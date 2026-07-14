import '../../../core/models.dart';
import '../../../core/pdf_oxide_bridge.dart';

class ReaderSearchService {
  ReaderSearchService(this._extraction);

  final HybridPdfExtractionService _extraction;

  Future<List<PdfSearchMatch>> search({
    required String path,
    required String query,
    required DocumentMetadata? metadata,
  }) async {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <PdfSearchMatch>[];
    }
    final List<PdfSearchMatch> results =
        await _extraction.searchDocument(path, needle);
    if (metadata != null) {
      for (final OcrPageData page in metadata.ocrPages.values) {
        for (final OcrWordData word in page.words) {
          if (word.text.toLowerCase().contains(needle)) {
            results.add(
              PdfSearchMatch(
                pageNumber: page.pageNumber,
                text: word.text,
                bounds: word.bounds,
              ),
            );
          }
        }
      }
    }
    results.sort((PdfSearchMatch a, PdfSearchMatch b) {
      final int pageOrder = a.pageNumber.compareTo(b.pageNumber);
      return pageOrder != 0 ? pageOrder : a.bounds.top.compareTo(b.bounds.top);
    });
    return results;
  }
}
