import '../../../core/models.dart';
import '../domain/ai_models.dart';
import '../application/ai_document_context.dart';
import '../infrastructure/local_rag_service.dart';

class ActiveDocumentToolResult {
  const ActiveDocumentToolResult({
    required this.response,
    required this.citations,
  });
  final Map<String, Object?> response;
  final List<CitationSnippet> citations;
}

class ActiveDocumentTool {
  const ActiveDocumentTool(this._rag);
  final LocalRagService _rag;
  Future<ActiveDocumentToolResult> execute({
    required AiDocumentContext context,
    required String query,
  }) async {
    if (query.trim().isEmpty) {
      return const ActiveDocumentToolResult(
        response: <String, Object?>{
          'status': 'invalid_query',
          'matches': <Object>[],
        },
        citations: <CitationSnippet>[],
      );
    }
    try {
      final List<PdfChunkRecord> chunks = await _rag.retrieve(
        context.documentId,
        query,
        limit: 6,
      );
      final citations = chunks
          .map(
            (chunk) => CitationSnippet(
              documentId: chunk.documentId,
              label: chunk.title,
              pageNumber: chunk.pageNumber,
              snippet: chunk.text,
            ),
          )
          .toList(growable: false);
      return ActiveDocumentToolResult(
        response: <String, Object?>{
          'status': chunks.isEmpty ? 'no_matches' : 'ok',
          'matches': chunks
              .map(
                (chunk) => <String, Object?>{
                  'title': chunk.title,
                  'pageNumber': chunk.pageNumber,
                  'sectionTitle': chunk.sectionTitle,
                  'excerpt': chunk.text.length > 1200
                      ? chunk.text.substring(0, 1200)
                      : chunk.text,
                },
              )
              .toList(growable: false),
        },
        citations: citations,
      );
    } catch (_) {
      return const ActiveDocumentToolResult(
        response: <String, Object?>{
          'status': 'unavailable',
          'matches': <Object>[],
        },
        citations: <CitationSnippet>[],
      );
    }
  }
}
