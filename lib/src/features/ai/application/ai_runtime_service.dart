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

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
