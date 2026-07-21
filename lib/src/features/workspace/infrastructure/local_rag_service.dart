import '../../../core/models.dart';
import 'local_rag_store.dart';

abstract interface class LocalRagRetriever {
  LocalRagIndexStatus get status;

  Future<List<PdfChunkRecord>?> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  });
}

typedef PdfChunkReader =
    Future<List<PdfChunkRecord>> Function(String documentId);

class LocalRagService {
  LocalRagService({required this.readChunks, this.nativeRetriever});

  final PdfChunkReader readChunks;
  final LocalRagRetriever? nativeRetriever;

  Future<List<PdfChunkRecord>> retrieve(
    String documentId,
    String query, {
    int limit = 6,
  }) async {
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <PdfChunkRecord>[];
    }
    if (limit <= 0) {
      return const <PdfChunkRecord>[];
    }

    final LocalRagRetriever? retriever = nativeRetriever;
    if (retriever != null && retriever.status == LocalRagIndexStatus.ready) {
      List<PdfChunkRecord>? native;
      try {
        native = await retriever.retrieve(
          documentId,
          normalizedQuery,
          limit: limit,
        );
      } catch (_) {
        native = null;
      }
      if (native != null) {
        return native.take(limit).toList(growable: false);
      }
    }

    return _lexicalRetrieve(
      await readChunks(documentId),
      normalizedQuery,
      limit,
    );
  }

  List<PdfChunkRecord> _lexicalRetrieve(
    List<PdfChunkRecord> chunks,
    String query,
    int limit,
  ) {
    final List<String> terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((String term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) {
      return const <PdfChunkRecord>[];
    }

    final List<_ScoredChunk> scored =
        chunks
            .map(
              (PdfChunkRecord chunk) =>
                  _ScoredChunk(chunk, _termOccurrences(chunk.text, terms)),
            )
            .where((_ScoredChunk item) => item.score > 0)
            .toList(growable: false)
          ..sort((_ScoredChunk left, _ScoredChunk right) {
            final int score = right.score.compareTo(left.score);
            return score != 0
                ? score
                : left.chunk.chunkOrder.compareTo(right.chunk.chunkOrder);
          });
    return scored
        .take(limit)
        .map((_ScoredChunk item) => item.chunk)
        .toList(growable: false);
  }

  int _termOccurrences(String text, List<String> terms) {
    final String lowerText = text.toLowerCase();
    return terms.fold<int>(
      0,
      (int score, String term) => score + _occurrences(lowerText, term),
    );
  }

  int _occurrences(String text, String term) {
    var count = 0;
    var start = 0;
    while (true) {
      final int index = text.indexOf(term, start);
      if (index < 0) {
        return count;
      }
      count++;
      start = index + term.length;
    }
  }
}

class _ScoredChunk {
  const _ScoredChunk(this.chunk, this.score);

  final PdfChunkRecord chunk;
  final int score;
}
