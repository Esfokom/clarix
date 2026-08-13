import 'dart:convert';

import '../../../core/models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/local_rag_service.dart';
import '../infrastructure/openai_compatible_provider.dart';
import 'ai_tool_registry.dart';

class AiAgentRequest {
  const AiAgentRequest({
    required this.profile,
    required this.apiKey,
    required this.prompt,
    required this.documentIds,
    this.history = const <AiChatMessage>[],
  });

  final AiProviderProfile profile;
  final String apiKey;
  final String prompt;
  final List<String> documentIds;
  final List<AiChatMessage> history;
}

class AiAgentReply {
  const AiAgentReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}

class AiAgentRuntime {
  AiAgentRuntime({
    required this.provider,
    required this.localRag,
    this.toolRegistry,
  });

  final OpenAiCompatibleProvider provider;
  final LocalRagService localRag;
  final AiToolRegistry? toolRegistry;

  Future<AiAgentReply> run(AiAgentRequest request) async {
    final List<PdfChunkRecord> passages = request.profile.shareRetrievedPassages
        ? await _retrievePassages(request.documentIds, request.prompt)
        : const <PdfChunkRecord>[];
    final List<CitationSnippet> citations = passages
        .map(_citationFor)
        .toList(growable: false);
    final bool canSearchDocument = citations.isNotEmpty;
    final List<AiChatMessage> messages = <AiChatMessage>[
      const AiChatMessage.system(
        'You are Clarix, a PDF reading assistant. Answer directly from supplied '
        'document evidence and cite supported claims by page number. Do not use '
        '"From the document" or "General knowledge" headings. If the document '
        'does not establish a point, say so. Include outside information only '
        'when necessary and only as *(General context, not stated in the '
        'document: …)*. Use tools only for local document context.',
      ),
      if (citations.isNotEmpty) AiChatMessage.system(_contextFor(citations)),
      ...request.history,
      AiChatMessage.user(request.prompt),
    ];
    final StringBuffer answer = StringBuffer();
    for (int round = 0; round < 6; round++) {
      final List<AiProviderEvent> events = await provider
          .streamChat(
            OpenAiChatRequest(
              profile: request.profile,
              apiKey: request.apiKey,
              messages: messages,
              tools: <Map<String, dynamic>>[
                if (canSearchDocument) ..._tools,
                if (request.documentIds.isNotEmpty) ...?toolRegistry?.schemas,
              ],
            ),
          )
          .toList();
      for (final AiTextDelta delta in events.whereType<AiTextDelta>()) {
        answer.write(delta.text);
      }
      final AiCompletionFinished finish = events
          .whereType<AiCompletionFinished>()
          .last;
      if (finish.toolCalls.isEmpty) {
        return AiAgentReply(text: answer.toString(), citations: citations);
      }
      messages.add(AiChatMessage.assistantToolCalls(finish.toolCalls));
      for (final AiToolCall call in finish.toolCalls) {
        messages.add(
          AiChatMessage.tool(
            toolCallId: call.id,
            content: await _executeTool(call, request.documentIds),
          ),
        );
      }
    }
    throw StateError('Clarix stopped after six tool rounds.');
  }

  void cancel() => provider.cancel();

  Future<String> _executeTool(AiToolCall call, List<String> allowedIds) async {
    final registry = toolRegistry;
    if (registry != null && AiToolRegistry.names.contains(call.name)) {
      return jsonEncode(
        await registry.execute(call, allowedDocumentIds: allowedIds.toSet()),
      );
    }
    if (call.name != 'search_document') {
      return jsonEncode(<String, dynamic>{
        'error': 'Unknown or disallowed tool.',
      });
    }
    final dynamic decoded = jsonDecode(call.argumentsJson);
    if (decoded is! Map || decoded['query'] is! String) {
      return jsonEncode(<String, dynamic>{
        'error': 'search_document requires a string query.',
      });
    }
    final String query = (decoded['query'] as String).trim().toLowerCase();
    final List<PdfChunkRecord> found = await _retrievePassages(
      allowedIds,
      query,
    );
    return jsonEncode(<String, dynamic>{
      'matches': found
          .map(
            (PdfChunkRecord chunk) => <String, dynamic>{
              'documentId': chunk.documentId,
              'pageNumber': chunk.pageNumber,
              'text': _truncate(chunk.text),
            },
          )
          .toList(),
    });
  }

  CitationSnippet _citationFor(PdfChunkRecord chunk) => CitationSnippet(
    documentId: chunk.documentId,
    label: chunk.title,
    pageNumber: chunk.pageNumber,
    snippet: _truncate(chunk.text),
  );

  Future<List<PdfChunkRecord>> _retrievePassages(
    List<String> documentIds,
    String query,
  ) async {
    final List<PdfChunkRecord> passages = <PdfChunkRecord>[];
    for (final String documentId in documentIds) {
      final int remaining = 6 - passages.length;
      if (remaining <= 0) {
        break;
      }
      passages.addAll(
        await localRag.retrieve(documentId, query, limit: remaining),
      );
    }
    return passages.take(6).toList(growable: false);
  }

  String _truncate(String text) =>
      text.substring(0, text.length > 1500 ? 1500 : text.length);

  String _contextFor(List<CitationSnippet> citations) => citations
      .asMap()
      .entries
      .map(
        (MapEntry<int, CitationSnippet> entry) =>
            '[source ${entry.key + 1}, page ${entry.value.pageNumber}] ${entry.value.snippet}',
      )
      .join('\n\n');

  static const List<Map<String, dynamic>> _tools = <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_document',
        'description': 'Searches locally indexed PDF text.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['query'],
          'additionalProperties': false,
        },
      },
    },
  ];
}
