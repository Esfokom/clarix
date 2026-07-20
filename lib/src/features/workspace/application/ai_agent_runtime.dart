import 'dart:convert';

import '../../../core/models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/openai_compatible_provider.dart';

class AiAgentRequest {
  const AiAgentRequest({
    required this.profile,
    required this.apiKey,
    required this.prompt,
    required this.documentIds,
  });

  final AiProviderProfile profile;
  final String apiKey;
  final String prompt;
  final List<String> documentIds;
}

class AiAgentReply {
  const AiAgentReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}

class AiAgentRuntime {
  AiAgentRuntime({required this.provider, required this.readChunks});

  final OpenAiCompatibleProvider provider;
  final Future<List<PdfChunkRecord>> Function(String documentId) readChunks;

  Future<AiAgentReply> run(AiAgentRequest request) async {
    final List<PdfChunkRecord> chunks = <PdfChunkRecord>[];
    for (final String documentId in request.documentIds) {
      chunks.addAll(await readChunks(documentId));
    }
    final List<CitationSnippet> citations =
        request.profile.shareRetrievedPassages
        ? chunks.take(4).map(_citationFor).toList(growable: false)
        : const <CitationSnippet>[];
    final List<AiChatMessage> messages = <AiChatMessage>[
      const AiChatMessage.system(
        'You are Clarix, a PDF reading assistant. Cite supplied passages by page number. '
        'Use tools only for local document context.',
      ),
      if (citations.isNotEmpty) AiChatMessage.system(_contextFor(citations)),
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
              tools: _tools,
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
            content: _executeTool(call, chunks, request.documentIds),
          ),
        );
      }
    }
    throw StateError('Clarix stopped after six tool rounds.');
  }

  void cancel() => provider.cancel();

  String _executeTool(
    AiToolCall call,
    List<PdfChunkRecord> chunks,
    List<String> allowedIds,
  ) {
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
    final List<PdfChunkRecord> found = chunks
        .where(
          (PdfChunkRecord chunk) =>
              allowedIds.contains(chunk.documentId) &&
              chunk.text.toLowerCase().contains(query),
        )
        .take(4)
        .toList(growable: false);
    return jsonEncode(<String, dynamic>{
      'matches': found
          .map(
            (PdfChunkRecord chunk) => <String, dynamic>{
              'documentId': chunk.documentId,
              'pageNumber': chunk.pageNumber,
              'text': chunk.text,
            },
          )
          .toList(),
    });
  }

  CitationSnippet _citationFor(PdfChunkRecord chunk) => CitationSnippet(
    documentId: chunk.documentId,
    label: chunk.title,
    pageNumber: chunk.pageNumber,
    snippet: chunk.text,
  );

  String _contextFor(List<CitationSnippet> citations) => citations
      .asMap()
      .entries
      .map(
        (MapEntry<int, CitationSnippet> entry) =>
            '[source ${entry.key + 1}, page ${entry.value.pageNumber}] ${entry.value.snippet.substring(0, entry.value.snippet.length > 1500 ? 1500 : entry.value.snippet.length)}',
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
