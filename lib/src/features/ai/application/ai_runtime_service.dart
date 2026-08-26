import '../../../core/clarix_logger.dart';
import '../../../core/ffi/chat_api.dart' as native_chat;
import '../domain/ai_models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/provider_profile_store.dart';

class AiRuntimeService {
  AiRuntimeService({required this.providerProfiles});

  final ProviderProfileStore providerProfiles;
  Future<void> testProvider(AiProviderProfile profile, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('Enter an API key before testing this provider.');
    }
    await native_chat
        .streamChat(
          request: native_chat.NativeChatRequest(
            providerEndpoint: profile.baseUrl,
            modelId: profile.modelId,
            headers: profile.headers,
            apiKey: apiKey.trim(),
            messages: const <native_chat.NativeChatMessage>[
              native_chat.NativeChatMessage(
                role: 'user',
                content: 'Reply with OK.',
              ),
            ],
          ),
        )
        .first;
  }

  Future<AiReply> sendPrompt({
    required String prompt,
    required String profileId,
    required List<CitationSnippet> documentSnippets,
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    final profiles = await providerProfiles.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) {
      clarixLog.w('AI runtime rejected prompt: selected provider is missing.');
      throw StateError('Select a remote AI provider to chat.');
    }
    final key = await providerProfiles.readApiKey(profile.id);
    if (key == null || key.isEmpty) {
      clarixLog.w(
        'AI runtime rejected prompt: ${profile.label} has no API key.',
      );
      throw StateError('Add an API key for ${profile.label}.');
    }
    clarixLog.i(
      'AI runtime prepared ${profile.label} streaming request '
      '(model=${profile.modelId}, endpoint=${profile.baseUrl}).',
    );
    onStatus?.call(AiRuntimePhase.generating, 'Contacting ${profile.label}.');
    final buffer = StringBuffer();
    await for (final event in native_chat.streamChat(
      request: native_chat.NativeChatRequest(
        providerEndpoint: profile.baseUrl,
        modelId: profile.modelId,
        headers: profile.headers,
        apiKey: key,
        messages: <native_chat.NativeChatMessage>[
          if (documentSnippets.isNotEmpty)
            native_chat.NativeChatMessage(
              role: 'system',
              content: _documentContext(documentSnippets),
            ),
          native_chat.NativeChatMessage(role: 'user', content: prompt),
        ],
      ),
    )) {
      switch (event) {
        case native_chat.NativeChatEvent_TextDelta(:final text):
          buffer.write(text);
          onToken(text);
        case native_chat.NativeChatEvent_Error(:final message):
          throw StateError(message);
        case native_chat.NativeChatEvent_Done():
          break;
      }
    }
    return AiReply(
      text: buffer.toString(),
      citations: const <CitationSnippet>[],
    );
  }

  Future<void> stopGeneration() async {}
  Future<void> dispose() async {}
}

String _documentContext(List<CitationSnippet> snippets) {
  final String excerpts = snippets
      .map(
        (CitationSnippet snippet) =>
            '[${snippet.label}, page ${snippet.pageNumber}]\n${snippet.snippet}',
      )
      .join('\n\n');
  return 'Answer using the supplied PDF excerpts when relevant. '
      'Mention page numbers when you rely on an excerpt.\n\n$excerpts';
}

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
