import '../../../core/models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/document_chunk_store.dart';
import '../infrastructure/openai_compatible_provider.dart';
import '../infrastructure/provider_profile_store.dart';
import 'ai_agent_runtime.dart';

class AiRuntimeService {
  AiRuntimeService({
    required this.providerProfiles,
    required this.chunkStore,
    OpenAiCompatibleProvider? provider,
  }) : _provider = provider ?? OpenAiCompatibleProvider();

  final ProviderProfileStore providerProfiles;
  final DocumentChunkStore chunkStore;
  final OpenAiCompatibleProvider _provider;

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
    final reply =
        await AiAgentRuntime(
          provider: _provider,
          readChunks: chunkStore.readChunks,
        ).run(
          AiAgentRequest(
            profile: profile,
            apiKey: key,
            prompt: prompt,
            documentIds: useCurrentDocumentScope && currentDocumentId != null
                ? <String>[currentDocumentId]
                : const <String>[],
          ),
        );
    onToken(reply.text);
    return AiReply(text: reply.text, citations: reply.citations);
  }

  Future<void> stopGeneration() async => _provider.cancel();
  Future<void> dispose() async {}
}

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
