import '../../../core/models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/local_rag_service.dart';
import '../infrastructure/openai_compatible_provider.dart';
import '../infrastructure/provider_profile_store.dart';
import 'ai_agent_runtime.dart';

class AiRuntimeService {
  AiRuntimeService({
    required this.providerProfiles,
    required this.chunkStore,
    LocalRagService? localRag,
    OpenAiCompatibleProvider? provider,
  }) : _provider = provider ?? OpenAiCompatibleProvider(),
       _localRag =
           localRag ?? LocalRagService(readChunks: chunkStore.readChunks);

  final ProviderProfileStore providerProfiles;
  final DocumentChunkStore chunkStore;
  final OpenAiCompatibleProvider _provider;
  final LocalRagService _localRag;

  Future<void> testProvider(AiProviderProfile profile, String apiKey) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('Enter an API key before testing this provider.');
    }
    return _provider.testCredentials(profile: profile, apiKey: apiKey.trim());
  }

  Future<AiReply> sendPrompt({
    required String prompt,
    required String profileId,
    required bool useCurrentDocumentScope,
    String? currentDocumentId,
    List<AiChatMessage> history = const <AiChatMessage>[],
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    final profiles = await providerProfiles.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) {
      throw StateError('Select a remote AI provider to chat.');
    }
    final key = await providerProfiles.readApiKey(profile.id);
    if (key == null || key.isEmpty) {
      throw StateError('Add an API key for ${profile.label}.');
    }
    onStatus?.call(AiRuntimePhase.generating, 'Contacting ${profile.label}.');
    final reply = await AiAgentRuntime(provider: _provider, localRag: _localRag)
        .run(
          AiAgentRequest(
            profile: profile,
            apiKey: key,
            prompt: prompt,
            documentIds: useCurrentDocumentScope && currentDocumentId != null
                ? <String>[currentDocumentId]
                : const <String>[],
            history: history,
          ),
        );
    onToken(reply.text);
    return AiReply(text: reply.text, citations: reply.citations);
  }

  Future<void> stopGeneration() async => _provider.cancel();

  Future<String> summarizeConversation({
    required String profileId,
    required String transcript,
  }) async {
    final profiles = await providerProfiles.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) {
      throw StateError('Select a remote AI provider to chat.');
    }
    final key = await providerProfiles.readApiKey(profile.id);
    if (key == null || key.isEmpty) {
      throw StateError('Add an API key for ${profile.label}.');
    }
    final events = await _provider
        .streamChat(
          OpenAiChatRequest(
            profile: profile,
            apiKey: key,
            messages: <AiChatMessage>[
              const AiChatMessage.system(
                'Summarize the conversation for future follow-ups. Preserve user intent, unresolved questions, document-supported conclusions with page citations, and important names, dates, quantities, and constraints.',
              ),
              AiChatMessage.user(transcript),
            ],
            tools: const <Map<String, dynamic>>[],
          ),
        )
        .toList();
    return events.whereType<AiTextDelta>().map((item) => item.text).join();
  }

  Future<void> dispose() async {}
}

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
