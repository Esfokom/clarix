import '../../../core/models.dart';
import '../../../core/pdf_oxide_bridge.dart';

class ReaderSearchService {
  ReaderSearchService(this._extraction);

  final HybridPdfExtractionService _extraction;

  Future<List<PdfSearchMatch>> search({
    required String path,
    required String query,
  }) async {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <PdfSearchMatch>[];
    }
    final List<PdfSearchMatch> results = await _extraction.searchDocument(
      path,
      needle,
    );
    results.sort((PdfSearchMatch a, PdfSearchMatch b) {
      final int pageOrder = a.pageNumber.compareTo(b.pageNumber);
      return pageOrder != 0 ? pageOrder : a.bounds.top.compareTo(b.bounds.top);
    });
    return results;
  }
}
