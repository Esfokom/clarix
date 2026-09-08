import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/clarix_logger.dart';
import '../domain/ai_models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/provider_profile_store.dart';
import 'agent_run_controller.dart';

class AiRuntimeService {
  AiRuntimeService({required this.providerProfiles});

  final ProviderProfileStore providerProfiles;
  AgentRunController? _activeController;

  Future<void> testProvider(AiProviderProfile profile, String apiKey) async {
    final client = HttpClient();
    try {
      final String endpoint = profile.baseUrl.endsWith('/chat/completions')
          ? profile.baseUrl
          : '${profile.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
      final uri = Uri.parse(endpoint);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (apiKey.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $apiKey');
      }
      profile.headers.forEach((k, v) => request.headers.set(k, v));

      final body = jsonEncode({
        'model': profile.modelId,
        'messages': [
          {'role': 'user', 'content': 'hi'}
        ],
        'max_tokens': 5,
      });

      request.write(body);
      final response = await request.close();
      if (response.statusCode >= 400) {
        final errorText = await response.transform(utf8.decoder).join();
        throw StateError('${profile.label} error (${response.statusCode}): $errorText');
      }
    } finally {
      client.close();
    }
  }

  Future<AiReply> sendPrompt({
    required String prompt,
    required String profileId,
    required String conversationId,
    required AgentRunController? controller,
    required void Function(String token) onToken,
    List<Map<String, String>>? history,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    final profiles = await providerProfiles.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) {
      clarixLog.w('AI runtime rejected prompt: selected provider is missing.');
      throw StateError('Select an AI provider to chat.');
    }
    final key = await providerProfiles.readApiKey(profile.id) ?? '';
    clarixLog.i(
      'AI runtime prepared ${profile.label} direct HTTP streaming request '
      '(model=${profile.modelId}, endpoint=${profile.baseUrl}).',
    );

    onStatus?.call(AiRuntimePhase.generating, 'Contacting ${profile.label}...');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final String endpoint = profile.baseUrl.endsWith('/chat/completions')
          ? profile.baseUrl
          : '${profile.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
      final uri = Uri.parse(endpoint);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (key.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $key');
      }
      profile.headers.forEach((k, v) => request.headers.set(k, v));

      final isLocal = profile.baseUrl.contains('localhost') || profile.baseUrl.contains('127.0.0.1');

      const systemPrompt = '''You are Clarix, an autonomous AI PDF document agent powered by local Gemma & PDFOxide.
You HAVE direct control over the active PDF workspace and Markdown Document Editor.

Supported Autonomous Operations:
1. [[EDIT_TEXT: {"page": <page_number>, "oldText": "<exact_old_text>", "newText": "<new_text>"}]]
   - Replaces or updates document text, headers, formulas, or tables on a specific page.
2. [[SCROLL_TO_PAGE: {"page": <page_number>}]]
   - Scrolls the PDF document viewer directly to page N.
3. [[CREATE_SOLUTION_PDF: {"solutionName": "<document>-solution.pdf"}]]
   - Compiles step-by-step solutions, GFM tables, Base64 images, and Mermaid state diagrams into a new PDF and opens it in a tab.
4. [[SAVE_DOCUMENT: {"filename": "<name>.pdf"}]]
   - Compiles current Markdown workspace content to PDF and saves it locally.

Capabilities & Rules:
- NEVER say "I cannot edit" or "I cannot scroll". Execute the action using command tags!
- When asked to solve exercises, construct DFAs/NFAs, or generate answer diagrams:
  1. Output clear step-by-step logic.
  2. Include GFM transition tables (| State | a | b |).
  3. Draw state diagrams using ```mermaid (e.g. stateDiagram-v2 with `q0 --> q1 : a`).
  4. Include `[[CREATE_SOLUTION_PDF: {"solutionName": "<document>-solution.pdf"}]]` tag.
- Put the command tag at the very beginning of your response whenever an action is requested.''';

      final messageList = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
      ];
      if (history != null && history.isNotEmpty) {
        // Retain context from past conversation turns (up to 16 entries)
        final startIndex = (history.length - 16).clamp(0, history.length);
        messageList.addAll(history.sublist(startIndex));
      }
      messageList.add({'role': 'user', 'content': prompt});

      final bodyMap = <String, dynamic>{
        'model': profile.modelId,
        'messages': messageList,
        'stream': true,
      };
      if (isLocal) {
        bodyMap['keep_alive'] = '24h';
        bodyMap['options'] = <String, dynamic>{
          'num_gpu': 0,
          'num_thread': 12,
          'num_ctx': 2048,
        };
      }

      final body = jsonEncode(bodyMap);

      request.write(body);
      final response = await request.close();

      if (response.statusCode >= 400) {
        final errorText = await response.transform(utf8.decoder).join();
        throw StateError('${profile.label} error (${response.statusCode}): $errorText');
      }

      final fullText = StringBuffer();
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (trimmed == 'data: [DONE]') break;
        
        final jsonStr = trimmed.startsWith('data: ') ? trimmed.substring(6).trim() : trimmed;
        if (jsonStr.startsWith('{')) {
          try {
            final map = jsonDecode(jsonStr) as Map<String, dynamic>;
            final choices = map['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final firstChoice = choices.first as Map<String, dynamic>;
              final delta = (firstChoice['delta'] as Map<String, dynamic>?) ??
                            (firstChoice['message'] as Map<String, dynamic>?);
              if (delta != null) {
                final content = (delta['content'] as String?) ??
                    (delta['reasoning'] as String?) ??
                    (delta['reasoning_content'] as String?);
                if (content != null && content.isNotEmpty) {
                  fullText.write(content);
                  onToken(content);
                }
              }
            } else if (map.containsKey('message')) {
              final msg = map['message'] as Map<String, dynamic>?;
              final content = (msg?['content'] as String?) ??
                  (msg?['reasoning'] as String?) ??
                  (msg?['reasoning_content'] as String?);
              if (content != null && content.isNotEmpty) {
                fullText.write(content);
                onToken(content);
              }
            }
          } catch (_) {}
        }
      }
      return AiReply(text: fullText.toString(), citations: const <CitationSnippet>[]);
    } finally {
      client.close();
    }
  }

  Future<void> stopGeneration() async => _activeController?.cancel();
  Future<void> dispose() async => stopGeneration();
}

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
